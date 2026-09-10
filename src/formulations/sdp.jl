"""Dense current–voltage SDP reference; a relaxation, with no rank-one constraint.

The first implementation supports one source, fixed lines/pi shunts, grounded and
explicit-neutral buses, P/Z loads, generators, fixed shunts, and fixed-tap
transformers/regulators. Unsupported
component fields are rejected before a model is built. `s_base` is in VA.
"""
Base.@kwdef struct SDPOptions
    s_base::Float64 = 1e4
    objective::Symbol = :cost
end

struct SDPInapplicableError <: Exception
    code::String
    message::String
end
Base.showerror(io::IO, e::SDPInapplicableError) = print(io, e.code, ": ", e.message)
_sdp_refuse(message) = throw(SDPInapplicableError("E.SDP.UNSUPPORTED", message))
const _SDPRow = Dict{Int,ComplexF64}
_sdp_e(i) = i == 0 ? _SDPRow() : _SDPRow(i => 1)
function _sdp_add!(a, b, scale=1)
    for (k,v) in b
        a[k] = get(a,k,0.0im) + scale*v
        iszero(a[k]) && delete!(a,k)
    end
    a
end

function _sdp_fields(data, allowed, label; matrix=())
    for key in keys(data)
        key in allowed && continue
        matched = false
        for prefix in matrix
            startswith(key,prefix) || continue
            suffix = key[length(prefix)+1:end]
            indices = match(r"^(\d+)_(\d+)$",suffix)
            if indices !== nothing && all(x -> parse(Int,x)>0, indices.captures)
                matched = true
                break
            end
        end
        matched && continue
        _sdp_refuse("$label field '$key' is not implemented by IVRSDP")
    end
end

function _sdp_check(net)
    tables = ("bus", "line", "linecode", "load", "generator", "voltage_source", "shunt", "transformer")
    for (key,value) in net
        key in tables && continue
        key in ("name", "meta", "terminal_conventions", "_meta") && continue
        isempty(value) || _sdp_refuse("table '$key' is not implemented by IVRSDP")
    end
    for (subtype,table) in get(net,"transformer",Dict())
        subtype in _SDP_TRANSFORMERS || _sdp_refuse("transformer/$subtype is not implemented")
        for (id,d) in table
            _sdp_transformer_plan(subtype,d,"transformer/$subtype/$id")
        end
    end
    length(get(net,"voltage_source",Dict())) == 1 || _sdp_refuse("exactly one voltage source is required")
    for (id,b) in get(net,"bus",Dict())
        _sdp_fields(b,("terminal_names","perfectly_grounded_terminals","neutral_terminal","v_min","v_max"),"bus/$id")
        tm = b["terminal_names"]
        !isempty(tm) && allunique(tm) || _sdp_refuse("bus/$id has empty or repeated terminals")
        all(t -> t in tm, get(b,"perfectly_grounded_terminals",[])) || _sdp_refuse("bus/$id has an undeclared ground terminal")
    end
    for (id,l) in get(net,"line",Dict())
        _sdp_fields(l,("bus_from","bus_to","terminal_map_from","terminal_map_to","linecode","length","i_max","s_max"),"line/$id";matrix=("R_series_","X_series_","G_from_","B_from_","G_to_","B_to_"))
        coded = haskey(l,"linecode")
        inline = haskey(l,"R_series_1_1") || haskey(l,"X_series_1_1")
        coded != inline || _sdp_refuse("line/$id must declare exactly one impedance source")
        coded && !haskey(get(net,"linecode",Dict()),l["linecode"]) &&
            _sdp_refuse("line/$id references an unknown linecode")
    end
    for (id,l) in get(net,"linecode",Dict())
        _sdp_fields(l,("i_max","s_max","source"),"linecode/$id";matrix=("R_series_","X_series_","G_from_","B_from_","G_to_","B_to_"))
    end
    for family in ("load","generator","voltage_source")
        allowed = family == "load" ? ("bus","terminal_map","configuration","model","p_nom","q_nom","v_nom") :
            family == "generator" ? ("bus","terminal_map","configuration","p_min","p_max","q_min","q_max","s_max","i_max","cost") :
            ("bus","terminal_map","configuration","v_magnitude","v_angle","p_min","p_max","q_min","q_max","s_max","i_max","cost")
        for (id,d) in get(net,family,Dict())
            _sdp_fields(d,allowed,"$family/$id")
            family == "load" && lowercase(get(d,"model","constant_power")) ∉ ("constant_power","constant_impedance") &&
                _sdp_refuse("load/$id voltage law is not implemented")
        end
    end
    for (id,s) in get(net,"shunt",Dict())
        _sdp_fields(s,("bus","terminal_map"),"shunt/$id";matrix=("G_","B_"))
    end
end

struct SDPBuild
    model::JuMP.Model
    moment::Any
    nullspace::Matrix{ComplexF64}
    voltage_indices::Dict{Tuple{String,String},Int}
    powers::Dict{Tuple{Symbol,String},Vector{Any}}
    network::Dict{String,Any}
    options::SDPOptions
    voltage_base::Float64
    anchor::Int
    anchor_voltage::ComplexF64
end

"""Build the dense IVRSDP reference, eliminating homogeneous electrical equalities.

For the scaled electrical state z=[v;i], A*z=0 is eliminated as z=N*y.
The model uses H ≽ 0 in place of y*yᴴ. Thus every rank-one feasible electrical
state lifts to a feasible SDP point. Fixed source phasor ratios are in A; one
source magnitude anchors the lifted model. No neutral is Kron-reduced.
"""
function build_sdp_opf(input, optimizer=default_optimizer(); options::SDPOptions=SDPOptions())
    isfinite(options.s_base) && options.s_base > 0 || throw(ArgumentError("s_base must be positive and finite"))
    options.objective in (:cost,:source_import,:feasibility) || throw(ArgumentError("unknown SDP objective"))
    net = _l3f_input(input)
    _sdp_check(net)
    source = only(values(net["voltage_source"]))
    source_v = Float64.(source["v_magnitude"]) .* cis.(Float64.(source["v_angle"]))
    vb = maximum(abs,source_v); sb = options.s_base
    isfinite(vb) && vb > 0 || _sdp_refuse("source voltages must be finite with a nonzero magnitude")
    all(isfinite,source_v) || _sdp_refuse("nonfinite source voltage")
    ib = sb/vb; zb = vb/ib
    count = Ref(0)
    newvar() = (count[] += 1)
    voltage = Dict{Tuple{String,String},Int}()
    for (b,d) in sort!(collect(net["bus"]);by=first), t in d["terminal_names"]
        voltage[(b,t)] = t in get(d,"perfectly_grounded_terminals",[]) ? 0 : newvar()
    end
    function terminal_rows(bus,tm)
        !isempty(tm) && allunique(tm) || _sdp_refuse("empty or repeated terminal map at $bus")
        all(haskey(voltage,(bus,t)) for t in tm) || _sdp_refuse("undeclared terminal at $bus")
        [_sdp_e(voltage[(bus,t)]) for t in tm]
    end
    kcl = Dict(key => _SDPRow() for (key,i) in voltage if i != 0)
    equations = _SDPRow[]
    function inject(bus,tm,rows,sign=1)
        for (t,row) in zip(tm,rows)
            haskey(kcl,(bus,t)) && _sdp_add!(kcl[(bus,t)],row,sign)
        end
    end
    function matrows(A,rows)
        out = [_SDPRow() for _ in axes(A,1)]
        for i in axes(A,1),j in axes(A,2)
            _sdp_add!(out[i],rows[j],A[i,j])
        end
        out
    end
    function values_for(d,key,n; default=nothing)
        haskey(d,key) || return default
        raw=d[key]; v=raw isa Number ? [Float64(raw)] : Float64.(raw)
        length(v)==n && all(isfinite,v) || _sdp_refuse("$key must have $n finite entries")
        v
    end
    # Constraints recorded as physical channel voltage/current pairs.
    devices = []
    limits = []
    for (id,l) in sort!(collect(get(net,"line",Dict()));by=first)
        tmf=l["terminal_map_from"]; tmt=l["terminal_map_to"]; n=length(tmf)
        n==length(tmt) || _sdp_refuse("line/$id endpoint arity mismatch")
        vf=terminal_rows(l["bus_from"],tmf); vt=terminal_rows(l["bus_to"],tmt)
        code=haskey(l,"linecode") ? net["linecode"][l["linecode"]] : l
        len=haskey(l,"linecode") ? Float64(get(l,"length",1.0)) : 1.0
        isfinite(len) && len>0 || _sdp_refuse("line/$id length must be positive")
        function matrix(prefix)
            M=_kr_matrix(code,prefix;label="line/$id")
            M===nothing && return zeros(n,n)
            size(M,1)<=n || _sdp_refuse("line/$id matrix exceeds terminal arity")
            out=zeros(n,n);out[1:size(M,1),1:size(M,2)].=M;out
        end
        Z=(matrix("R_series_")+im*matrix("X_series_"))*len/zb
        Yf=(matrix("G_from_")+im*matrix("B_from_"))*len*zb
        Yt=(matrix("G_to_")+im*matrix("B_to_"))*len*zb
        current=[_sdp_e(newvar()) for _ in 1:n]
        drop=matrows(Z,current)
        for k in 1:n
            push!(equations,_sdp_add!(_sdp_add!(copy(vf[k]),vt[k],-1),drop[k],-1))
        end
        cf=matrows(Yf,vf); ct=matrows(Yt,vt)
        for k in 1:n;_sdp_add!(cf[k],current[k]);_sdp_add!(ct[k],current[k],-1);end
        inject(l["bus_from"],tmf,cf);inject(l["bus_to"],tmt,ct)
        ratings=Dict(k=>get(l,k,get(code,k,nothing)) for k in ("i_max","s_max") if haskey(l,k)||haskey(code,k))
        push!(limits,(vf,cf,ratings));push!(limits,(vt,ct,ratings))
        push!(devices,(:line_from,id,vf,cf,Dict()));push!(devices,(:line_to,id,vt,ct,Dict()))
    end
    _sdp_stamp_transformers!(net,newvar,terminal_rows,matrows,inject,equations,devices,limits,zb)
    for (id,d) in get(net,"shunt",Dict())
        rows=terminal_rows(d["bus"],d["terminal_map"])
        Y=_l3f_shunt_matrix(d,length(rows))*zb
        inject(d["bus"],d["terminal_map"],matrows(Y,rows))
    end
    for family in ("load","generator"), (id,d) in sort!(collect(get(net,family,Dict()));by=first)
        tm=d["terminal_map"]; vr=terminal_rows(d["bus"],tm)
        n=length(d[family=="load" ? "p_nom" : "p_min"])
        cfg=uppercase(d["configuration"])
        neutral = get(net["bus"][d["bus"]],"neutral_terminal",nothing)
        neutral===nothing && (neutral = length(tm)==n+1 ? last(tm) : nothing)
        D = if cfg=="WYE" && length(tm)==n+1
            # BMOPF's explicit wye neutral is the trailing terminal.
            neutral==last(tm) || _sdp_refuse("wye/$id neutral must be the trailing terminal")
            hcat(Matrix{Float64}(I,n,n),-ones(n))
        else
            _l3f_connection_incidence(cfg,length(tm),n)
        end
        vc=matrows(D,vr); ic=[_sdp_e(newvar()) for _ in 1:n]
        inject(d["bus"],tm,matrows(transpose(D),ic),family=="load" ? 1 : -1)
        if family=="load" && lowercase(get(d,"model","constant_power"))=="constant_impedance"
            p=values_for(d,"p_nom",n);q=values_for(d,"q_nom",n);vn=values_for(d,"v_nom",n)
            vn===nothing && _sdp_refuse("load/$id requires v_nom")
            all(>(0),vn) || _sdp_refuse("load/$id requires positive v_nom")
            for k in 1:n
                y=conj(complex(p[k],q[k]))/vn[k]^2*zb
                push!(equations,_sdp_add!(copy(ic[k]),vc[k],-y))
            end
        end
        push!(devices,(Symbol(family),id,vc,ic,d))
        family=="generator" && push!(limits,(vc,ic,d))
    end
    tm=source["terminal_map"]; vs=terminal_rows(source["bus"],tm)
    length(source_v)==length(tm) || _sdp_refuse("source phasor arity mismatch")
    anchor_k=findfirst(v -> !iszero(v),source_v)
    anchor=voltage[(source["bus"],tm[anchor_k])]
    anchor!=0 || _sdp_refuse("nonzero prescribed source voltage on a grounded terminal")
    for k in eachindex(tm)
        k==anchor_k && continue # Avoid normalizing roundoff in the tautology v_anchor=v_anchor.
        push!(equations,_sdp_add!(copy(vs[k]),vs[anchor_k],-source_v[k]/source_v[anchor_k]))
    end
    # Ground currents are supplied by ideal earth connections and not assigned
    # to a particular grounded source terminal. Do not pretend to rate them.
    any(isempty,vs) && haskey(source,"i_max") && _sdp_refuse("source ground-terminal current allocation is not implemented")
    is=[isempty(v) ? _SDPRow() : _sdp_e(newvar()) for v in vs]
    inject(source["bus"],tm,is,-1)
    push!(devices,(:voltage_source,only(keys(net["voltage_source"])),vs,is,source))
    push!(limits,(vs,is,source))
    append!(equations,values(kcl))
    A=zeros(ComplexF64,length(equations),count[])
    for (r,row) in enumerate(equations), (c,value) in row;A[r,c]=value;end
    # Row equilibration affects neither the nullspace nor the feasible set.
    for r in axes(A,1)
        scale=norm(A[r,:]);iszero(scale) || (A[r,:]./=scale)
    end
    N=nullspace(A)
    size(N,2)>0 || _sdp_refuse("electrical equations leave no nonzero source state")
    model=optimizer===nothing ? JuMP.Model() : JuMP.Model(optimizer)
    m=size(N,2)
    H=@variable(model,[1:m,1:m] in HermitianPSDCone())
    function lift(a,b)
        ca=zeros(ComplexF64,m);cb=similar(ca);fill!(cb,0)
        for (i,c) in a;ca .+= c.*N[i,:];end
        for (i,c) in b;cb .+= c.*N[i,:];end
        sum((ca[i]*conj(cb[j]))*H[i,j] for i in 1:m,j in 1:m)
    end
    @constraint(model,real(lift(vs[anchor_k],vs[anchor_k]))==abs2(source_v[anchor_k]/vb))
    for ((b,t),i) in voltage
        d=net["bus"][b]; k=findfirst(==(t),d["terminal_names"]);n=length(d["terminal_names"])
        w=real(lift(_sdp_e(i),_sdp_e(i)))
        for (field,lower) in (("v_min",true),("v_max",false))
            bound=values_for(d,field,n);bound===nothing && continue
            bound[k]>=0 || _sdp_refuse("negative voltage magnitude bound")
            lower ? @constraint(model,w >= (bound[k]/vb)^2) : @constraint(model,w <= (bound[k]/vb)^2)
        end
    end
    powers=Dict{Tuple{Symbol,String},Vector{Any}}()
    objective=JuMP.AffExpr(0.0)
    for (family,id,v,i,d) in devices
        s=Any[lift(v[k],i[k]) for k in eachindex(v)];powers[(family,id)]=s;n=length(s)
        if family==:load && lowercase(get(d,"model","constant_power"))=="constant_power"
            p=values_for(d,"p_nom",n);q=values_for(d,"q_nom",n)
            for k in 1:n
                @constraint(model,real(s[k])==p[k]/sb);@constraint(model,imag(s[k])==q[k]/sb)
            end
        elseif family in (:generator,:voltage_source)
            for (field,lower,active) in (("p_min",true,true),("p_max",false,true),("q_min",true,false),("q_max",false,false))
                bound=values_for(d,field,n);bound===nothing && continue
                for k in 1:n
                    f=active ? real(s[k]) : imag(s[k])
                    lower ? @constraint(model,f>=bound[k]/sb) : @constraint(model,f<=bound[k]/sb)
                end
            end
            priced = d
            if family==:voltage_source && haskey(d,"cost") && length(d["cost"])==Base.count(x -> !isempty(x),v) && length(d["cost"])!=n
                priced=copy(d); expanded=zeros(n); cursor=1
                for k in eachindex(v)
                    isempty(v[k]) && continue
                    expanded[k]=d["cost"][cursor];cursor+=1
                end
                priced["cost"]=expanded
            end
            cost=values_for(priced,"cost",n;default=zeros(n))
            for k in 1:n
                coefficient=options.objective==:cost ? cost[k]*sb/1000 :
                    options.objective==:source_import && family==:voltage_source ? sb : 0.0
                JuMP.add_to_expression!(objective,coefficient*real(s[k]))
            end
        end
    end
    for (v,i,d) in limits
        n=length(v);imax=values_for(d,"i_max",n);smax=values_for(d,"s_max",n)
        for k in 1:n
            if imax!==nothing
                imax[k]>=0 || _sdp_refuse("negative current limit")
                @constraint(model,real(lift(i[k],i[k])) <= (imax[k]/ib)^2)
            end
            if smax!==nothing
                smax[k]>=0 || _sdp_refuse("negative apparent-power limit")
                s=lift(v[k],i[k]);@constraint(model,[smax[k]/sb,real(s),imag(s)] in SecondOrderCone())
            end
        end
    end
    @objective(model,Min,objective)
    SDPBuild(model,H,N,voltage,powers,net,options,vb,anchor,source_v[anchor_k])
end

struct SDPResult <: AbstractSolveResult
    objective::Float64
    solver_objective_bound::Float64
    moment::Matrix{ComplexF64}
    voltage_candidate::Dict{Tuple{String,String},ComplexF64}
    relaxed_powers::Dict{Tuple{Symbol,String},Vector{ComplexF64}}
    rank_ratio::Float64
    solve::SolveStatus
end
solve_status(r::SDPResult)=r.solve
solve_diagnostics(r::SDPResult)=(model_kind=:relaxation, rank_ratio=r.rank_ratio,
    physical_feasibility_certified=false, bound_certified=false)

"""Solve IVRSDP. The dominant-eigenvector voltage candidate is not an AC certificate.

`solver_objective_bound` is reported as numerical solver evidence only. It is
not a rigorous, residual-corrected certificate. A feasible AC upper bound is
required before reporting an OPF optimality gap.
"""
function solve_sdp_opf(input, optimizer=default_optimizer(); options=SDPOptions(),solver_options=())
    build=build_sdp_opf(input,optimizer;options)
    _set_solver_options!(build.model,solver_options);JuMP.optimize!(build.model)
    outcome=_solve_outcome(build.model);status=SolveStatus(outcome)
    if !outcome.optimal
        return SDPResult(NaN,NaN,fill(ComplexF64(NaN),size(build.moment)),
            Dict(k=>ComplexF64(NaN) for k in keys(build.voltage_indices)),
            Dict(k=>fill(ComplexF64(NaN),length(v)) for (k,v) in build.powers),NaN,status)
    end
    H=Matrix{ComplexF64}(JuMP.value.(build.moment));eig=eigen(Hermitian(H))
    # Recover from the voltage Gram: free auxiliary current completions must
    # not select the voltage candidate through the largest eigenvalue of H.
    rows=[i for i in values(build.voltage_indices) if i!=0]
    sort!(rows)
    NV=build.nullspace[rows,:]
    veig=eigen(Hermitian(NV*H*NV'))
    vv=sqrt(max(0,last(veig.values)))*veig.vectors[:,end]
    z=zeros(ComplexF64,size(build.nullspace,1));z[rows]=vv
    phase=iszero(z[build.anchor]) ? 1.0+0im : cis(angle(build.anchor_voltage)-angle(z[build.anchor]))
    v=Dict(k=>(i==0 ? 0.0im : build.voltage_base*z[i]*phase) for (k,i) in build.voltage_indices)
    ratio=length(eig.values)>1 ? max(0,eig.values[end-1])/max(eps(),eig.values[end]) : 0.0
    bound=try JuMP.objective_bound(build.model) catch; NaN end
    powers=Dict(k=>ComplexF64.(JuMP.value.(s)).*options.s_base for (k,s) in build.powers)
    SDPResult(JuMP.objective_value(build.model),bound,H,v,powers,ratio,status)
end
