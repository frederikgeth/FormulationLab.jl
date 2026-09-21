"""Current–voltage SDP with Clarabel and dense reference profiles; a relaxation, with no rank-one constraint.

Supports static AC lines, sources, loads, generators, inverters, shunts,
capacitors, switches, and fixed-tap transformers/regulators, including general
multiwinding units and explicit neutrals. Nonlinear load laws use additional
power-cone envelopes. Controls are not evaluated. `s_base` is in VA.
`lnc=:lines` enables derived line-voltage cuts; `:off` is the default.
`voltage_lncs` adds explicit domains/cuts independently of that setting.
`port_rlt=true` derives voltage-current RLT/LNC cuts from finite P/Q boxes that
exclude the origin and from matching physical voltage bounds.
`basis=:auto` uses guarded structural physical elimination up to 32 independent
coordinates and sparse QR above that; `:physical` retains the legacy basis.
`clique_merge=:cost` uses a reduced-rank cone/separator cost surrogate instead
of the default original-coordinate size heuristic. `clique_size` then caps
the reduced order of proposed merges (default 12 instead of 32).
The Clarabel profile uses `state_scaling=:voltage_region` to precondition
electrical elimination; `:global` retains the previous coordinates. Outputs
and physical bounds keep their original units. Cost merging is experimental;
both transformations preserve the SDP.
"""
Base.@kwdef struct SDPOptions
    audit::Bool = false
    bound_sweeps::Int = 8
    profile::Symbol = :clarabel
    decomposition::Symbol = profile==:clarabel ? :auto : :dense
    s_base::Float64 = 1e4
    objective::Symbol = :cost
    basis::Symbol = profile==:clarabel ? :auto : :orthonormal
    cone::Symbol = profile==:clarabel ? :real : :hermitian
    shunt_coordinates::Symbol = profile==:clarabel ? :current : :admittance
    scale_objective::Bool = profile==:clarabel
    current_bounds::Bool = profile==:clarabel
    preprocess::Bool = profile==:clarabel
    clique_merge::Symbol = :size
    clique_size::Int = clique_merge==:cost ? 12 : 32
    clique_overlap_weight::Float64 = 1.0
    state_scaling::Symbol = profile==:clarabel ? :voltage_region : :global
    consistency::Symbol = :auto
    recovery::Symbol = profile==:clarabel ? :anchor : :dominant
    lnc::Symbol = :off
    voltage_lncs::Vector{VoltageLNC} = VoltageLNC[]
    port_rlt::Bool = true
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
    tables = ("bus", "line", "linecode", "load", "generator", "voltage_source", "shunt", "transformer", "switch", "capacitor", "ibr", "control_profile")
    for (key,value) in net
        key in tables && continue
        key in ("name", "meta", "terminal_conventions", "_meta", "extras", "wire_data", "line_geometry") && continue
        isempty(value) || _sdp_refuse("table '$key' is not implemented by IVRSDP")
    end
    for (subtype,table) in get(net,"transformer",Dict())
        subtype in (_SDP_TRANSFORMERS...,"n_winding") || _sdp_refuse("transformer/$subtype is not implemented")
        for (id,d) in table
            subtype=="n_winding" ? _sdp_nwinding_plan(net,id,d) : _sdp_transformer_plan(subtype,d,"transformer/$subtype/$id")
        end
    end
    !isempty(get(net,"voltage_source",Dict())) || _sdp_refuse("at least one voltage source is required")
    for (id,b) in get(net,"bus",Dict())
        _sdp_fields(b,("terminal_names","perfectly_grounded_terminals","neutral_terminal","v_min","v_max","vn_max","vpn_min","vpn_max","vpp_min","vpp_max","vpos_min","vpos_max","vneg_max","vzero_max"),"bus/$id")
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
        _sdp_fields(l,("i_max","s_max","source","line_geometry","derivation"),"linecode/$id";matrix=("R_series_","X_series_","G_from_","B_from_","G_to_","B_to_"))
    end
    for family in ("load","generator","voltage_source")
        allowed = family == "load" ? ("bus","terminal_map","configuration","model","p_nom","q_nom","v_nom","alpha_z","alpha_i","alpha_p","beta_z","beta_i","beta_p","gamma_p","gamma_q") :
            family == "generator" ? ("bus","terminal_map","configuration","p_min","p_max","q_min","q_max","s_max","i_max","cost","energy_cost_rate") :
            ("bus","terminal_map","configuration","v_magnitude","v_angle","p_min","p_max","q_min","q_max","s_max","i_max","cost","energy_cost_rate")
        for (id,d) in get(net,family,Dict())
            _sdp_fields(d,allowed,"$family/$id")
            family == "load" && lowercase(get(d,"model","constant_power")) ∉ ("constant_power","constant_impedance","constant_current","zip","exponential") &&
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
    omitted_controls::Vector{String}
    load_envelopes::Vector{String}
    lnc_diagnostics::Vector{LNCDiagnostic}
    objective_scale::Float64
    numerical_diagnostics::Dict{Symbol,Any}
end

"""Build the dense IVRSDP reference, eliminating homogeneous electrical equalities.

For the scaled electrical state z=[v;i], A*z=0 is eliminated as z=N*y.
The model uses H ≽ 0 in place of y*yᴴ. Thus every rank-one feasible electrical
state lifts to a feasible SDP point. Fixed source phasor ratios are in A; one
source magnitude anchors the lifted model. No neutral is Kron-reduced.
"""
function build_sdp_opf(input, optimizer=default_sdp_optimizer(); options::SDPOptions=SDPOptions(), _soc=nothing)
    options.bound_sweeps>=0 || throw(ArgumentError("bound_sweeps must be nonnegative"))
    options.profile in (:clarabel,:reference) || throw(ArgumentError("unknown SDP profile"))
    isfinite(options.s_base) && options.s_base > 0 || throw(ArgumentError("s_base must be positive and finite"))
    options.objective in (:cost,:source_import,:feasibility) || throw(ArgumentError("unknown SDP objective"))
    options.lnc in (:off,:lines) || throw(ArgumentError("lnc must be :off or :lines"))
    options.decomposition in (:auto,:dense,:chordal) || throw(ArgumentError("unknown SDP decomposition"))
    options.consistency in (:auto,:local,:shared) || throw(ArgumentError("unknown clique consistency"))
    options.clique_size>=1 || throw(ArgumentError("clique_size must be positive"))
    options.clique_merge in (:size,:cost) || throw(ArgumentError("unknown clique merge policy"))
    isfinite(options.clique_overlap_weight) && options.clique_overlap_weight>=0 || throw(ArgumentError("clique_overlap_weight must be finite and nonnegative"))
    options.state_scaling in (:global,:voltage_region) || throw(ArgumentError("unknown state scaling"))
    options.recovery in (:anchor,:dominant) || throw(ArgumentError("unknown SDP recovery"))
    options.basis in (:auto,:orthonormal,:physical,:physical_sparse,:sparse) || throw(ArgumentError("unknown SDP basis"))
    options.cone in (:hermitian,:real) || throw(ArgumentError("unknown SDP cone"))
    options.shunt_coordinates in (:admittance,:current) || throw(ArgumentError("unknown shunt coordinates"))
    net = _l3f_input(input)
    _sdp_check(net)
    candidates=[d for (_,d) in sort!(collect(net["voltage_source"]);by=first) if any(!iszero,d["v_magnitude"])]
    isempty(candidates) && _sdp_refuse("at least one nonzero reference phasor is required")
    source = first(candidates)
    source_v = Float64.(source["v_magnitude"]) .* cis.(Float64.(source["v_angle"]))
    vb = maximum(abs,source_v); sb = options.s_base
    isfinite(vb) && vb > 0 || _sdp_refuse("source voltages must be finite with a nonzero magnitude")
    all(isfinite,source_v) || _sdp_refuse("nonfinite source voltage")
    vb = maximum(maximum(abs,Float64.(d["v_magnitude"])) for d in values(net["voltage_source"]))
    ib = sb/vb; zb = vb/ib
    coordinate_count = Ref(0)
    newvar() = (coordinate_count[] += 1)
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
    lnc_lines = []
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
        current_ratings=Dict(k=>ratings[k] for k in ("i_max",) if haskey(ratings,k))
        push!(limits,(vf,cf,current_ratings));push!(limits,(vt,ct,current_ratings))
        if haskey(ratings,"s_max")
            neutral=get(_kr_neutral_map(net),l["bus_from"],nothing)
            phases=findall(!=(neutral),tmf)
            push!(limits,(vf[phases],cf[phases],Dict("s_max"=>ratings["s_max"])))
            push!(limits,(vt[phases],ct[phases],Dict("s_max"=>ratings["s_max"])))
        end
        options.lnc==:lines && push!(lnc_lines,(;id,from=l["bus_from"],to=l["bus_to"],tmf,tmt,vf,vt,
            Z=Z*zb,Yf=Yf/zb,Yt=Yt/zb,ratings))
        passive=all(M->minimum(eigvals(Hermitian((M+M')/2));init=0.0)>=0,(Z,Yf,Yt))
        push!(devices,(:line_from,id,vf,cf,Dict("passive"=>passive)));push!(devices,(:line_to,id,vt,ct,Dict()))
    end
    _sdp_stamp_transformers!(net,newvar,terminal_rows,matrows,inject,equations,devices,limits,zb)
    _sdp_stamp_nwinding!(net,newvar,terminal_rows,matrows,inject,equations,devices,limits,zb)
    _sdp_stamp_static!(net,newvar,terminal_rows,matrows,inject,equations,devices,limits,zb)
    for (id,d) in get(net,"shunt",Dict())
        rows=terminal_rows(d["bus"],d["terminal_map"])
        Y=_l3f_shunt_matrix(d,length(rows))*zb
        if options.shunt_coordinates==:current
            currents=_SDPRow[]
            for k in eachindex(rows)
                scale=maximum(abs,Y[k,:];init=0.0)
                if iszero(scale)
                    push!(currents,_SDPRow())
                else
                    j=_sdp_e(newvar());push!(currents,j)
                    equation=_sdp_add!(_SDPRow(),j,1/scale)
                    for h in eachindex(rows);_sdp_add!(equation,rows[h],-Y[k,h]/scale);end
                    push!(equations,equation)
                end
            end
            inject(d["bus"],d["terminal_map"],currents)
        else
            inject(d["bus"],d["terminal_map"],matrows(Y,rows))
        end
    end
    for family in ("load","generator","ibr"), (id,d) in sort!(collect(get(net,family,Dict()));by=first)
        tm=d["terminal_map"]; vr=terminal_rows(d["bus"],tm)
        if family=="ibr"
            _sdp_fields(d,("bus","terminal_map","topology","prime_mover","s_max","i_max","p_avail","p_min","p_max","q_min","q_max",
                "cost","energy_cost_rate","control_profile","voltage_aggregation","dc_link_coupled","p_dc_min","p_dc_max",
                "r_filter","x_filter","b_filter_shunt","grid_forming","v_ref_internal"),"ibr/$id")
            cfg=get(Dict("FOUR_LEG"=>"WYE","THREE_LEG"=>"DELTA","SINGLE_PHASE"=>"SINGLE_PHASE"),get(d,"topology",""),nothing)
            cfg===nothing && _sdp_refuse("ibr/$id unknown topology")
            n=length(d["s_max"])
        else
            cfg=uppercase(d["configuration"])
            nt=get(_kr_neutral_map(net),d["bus"],nothing)
            n=family=="load" ? length(d["p_nom"]) : cfg=="SINGLE_PHASE" ? 1 :
                cfg=="DELTA" ? (length(tm)==2 ? 1 : 3) : count(!=(nt),tm)
        end
        D=_sdp_connection(net,d["bus"],tm,cfg,n)
        vc=matrows(D,vr); ic=[_sdp_e(newvar()) for _ in 1:n]
        terminal_current=matrows(transpose(D),ic)
        if family=="ibr"
            rf=_sdp_vector(d,"r_filter",n;default=zeros(n));xf=_sdp_vector(d,"x_filter",n;default=zeros(n))
            all(>=(0),rf) || _sdp_refuse("ibr/$id negative filter resistance")
            bf=_sdp_scalar(d,"b_filter_shunt")
            # Port powers are measured at PCC. Filter current also supplies the
            # shunt at PCC; internal voltage is U + Z*(I + jB*U).
            jf=[_sdp_add!(copy(ic[k]),vc[k],im*bf*zb) for k in 1:n]
            internal=[_sdp_add!(copy(vc[k]),jf[k],complex(rf[k],xf[k])/zb) for k in 1:n]
            push!(devices,(:ibr_internal,id,internal,jf,d))
        end
        inject(d["bus"],tm,terminal_current,family=="load" ? 1 : -1)
        if family=="load" && _sdp_is_impedance_load(d)
            p=values_for(d,"p_nom",n);q=values_for(d,"q_nom",n);vn=values_for(d,"v_nom",n)
            vn===nothing && _sdp_refuse("load/$id requires v_nom")
            all(>(0),vn) || _sdp_refuse("load/$id requires positive v_nom")
            for k in 1:n
                y=conj(complex(p[k],q[k]))/vn[k]^2*zb
                push!(equations,_sdp_add!(copy(ic[k]),vc[k],-y))
            end
        end
        # BMOPF generator/converter dispatch is per phase conductor; unlike
        # load powers it is not per delta sub-load. Keep winding coordinates
        # for KCL/filter laws and use terminal products for a three-wire port.
        port_v,port_i = family in ("generator","ibr") && cfg=="DELTA" && length(tm)==3 ?
            (vr,terminal_current) : (vc,ic)
        push!(devices,(Symbol(family),id,port_v,port_i,d))
        if family in ("generator","ibr")
            bounds=Dict(k=>d[k] for k in ("s_max",) if haskey(d,k))
            if haskey(d,"i_max")
                imax=d["i_max"]
                if length(imax)==length(tm)
                    push!(limits,(vr,terminal_current,Dict("i_max"=>imax)))
                elseif length(imax)==n
                    bounds["i_max"]=imax
                else
                    _sdp_refuse("$family/$id current ratings must match coils or terminals")
                end
            end
            push!(limits,(port_v,port_i,bounds))
        end
    end
    tm=source["terminal_map"]; vs=terminal_rows(source["bus"],tm)
    length(source_v)==length(tm) || _sdp_refuse("source phasor arity mismatch")
    anchor_k=findfirst(v -> !iszero(v),source_v)
    anchor=voltage[(source["bus"],tm[anchor_k])]
    anchor!=0 || _sdp_refuse("nonzero prescribed source voltage on a grounded terminal")
    fixed_source_coordinates=Dict{Int,ComplexF64}()
    for (source_id,d) in sort!(collect(net["voltage_source"]);by=first)
        dvolts=Float64.(d["v_magnitude"]).*cis.(Float64.(d["v_angle"]))
        rows=terminal_rows(d["bus"],d["terminal_map"])
        length(rows)==length(dvolts) && all(isfinite,dvolts) || _sdp_refuse("source/$source_id invalid phasors")
        for k in eachindex(rows)
            idx=voltage[(d["bus"],d["terminal_map"][k])]
            idx!=0 && (fixed_source_coordinates[idx]=dvolts[k]/vb)
            # The first anchor equation is an algebraic tautology.
            d===source && k==anchor_k && continue
            push!(equations,_sdp_add!(copy(rows[k]),vs[anchor_k],-dvolts[k]/source_v[anchor_k]))
        end
        # Ideal source ground-terminal current allocation is underdetermined in
        # a common-earth model. Do not manufacture a neutral rating certificate.
        any(isempty,rows) && haskey(d,"i_max") && _sdp_refuse("source ground-terminal current allocation is not implemented")
        is=[isempty(v) ? _SDPRow() : _sdp_e(newvar()) for v in rows]
        inject(d["bus"],d["terminal_map"],is,-1)
        # Power boxes are per phase; current limits, where supported, are per conductor.
        neutral=get(_kr_neutral_map(net),d["bus"],nothing)
        phases=findall(!=(neutral),d["terminal_map"])
        powerdata=copy(d)
        for key in ("p_min","p_max","q_min","q_max")
            haskey(d,key) || continue
            raw=values_for(d,key,length(d[key])==length(rows) ? length(rows) : length(phases))
            # Preserve the full terminal powers for result reporting, including neutral power.
            expanded=fill(key in ("p_min","q_min") ? -Inf : Inf,length(rows))
            length(raw)==length(rows) ? (expanded=raw) : (expanded[phases]=raw)
            powerdata[key]=expanded
        end
        for key in ("cost","energy_cost_rate")
            haskey(d,key) && length(d[key])==length(phases) || continue
            expanded=zeros(length(rows));expanded[phases]=values_for(d,key,length(phases));powerdata[key]=expanded
        end
        push!(devices,(:voltage_source,source_id,rows,is,powerdata));push!(limits,(rows,is,Dict(k=>d[k] for k in ("i_max",) if haskey(d,k))))
    end
    fixed_physical=Dict(k=>v*vb for (k,v) in fixed_source_coordinates)
    declared_voltage_range=_sdp_voltage_ranges(net,terminal_rows,fixed_physical)
    range_pu,bound_info=_sdp_bound_profile(net,terminal_rows,fixed_source_coordinates,
        vcat(equations,collect(values(kcl))),devices,limits,coordinate_count[],vb,ib;sweeps=options.bound_sweeps)
    voltage_range(row)=begin
        lo,hi=declared_voltage_range(row);a,b=range_pu(row)
        (max(lo,a*vb),min(hi,b*vb))
    end
    derived=options.current_bounds ? _sdp_current_bounds(devices,limits,voltage_range) : []
    # Exact zero upper bounds expose a face of the PSD cone. Eliminate the
    # corresponding linear state maps before lifting, including sequence maps.
    face_rows=0
    for (bus,_) in net["bus"], rows in values(_sdp_voltage_maps(net,bus,terminal_rows)), row in rows
        _,hi=voltage_range(row)
        if iszero(hi) && !isempty(row)
            push!(equations,copy(row));face_rows+=1
        end
    end
    for (v,i,d) in limits
        imax=values_for(d,"i_max",length(i))
        imax===nothing && continue
        for k in eachindex(i)
            if iszero(imax[k]) && !isempty(i[k]);push!(equations,copy(i[k]));face_rows+=1;end
        end
    end
    for (i,imax,_) in derived
        if iszero(imax) && !isempty(i);push!(equations,copy(i));face_rows+=1;end
    end
    append!(equations,values(kcl))
    A=zeros(ComplexF64,length(equations),coordinate_count[])
    for (r,row) in enumerate(equations), (c,value) in row;A[r,c]=value;end
    # Row equilibration affects neither the nullspace nor the feasible set.
    for r in axes(A,1)
        scale=norm(A[r,:]);iszero(scale) || (A[r,:]./=scale)
    end
    diagnostics=Dict{Symbol,Any}(:basis=>options.basis,:cone=>options.cone,
        :decomposition=>options.decomposition,:state_dimension=>size(A,2),
        :bound_report=>bound_info,:face_equations=>face_rows,:derived_current_bounds=>length(derived))
    diagnostics[:port_rlt_diagnostics]=NamedTuple[]
    scales,scaling_info=_sdp_state_scales(net,voltage,devices,limits,size(A,2),vb,options.state_scaling)
    diagnostics[:state_scaling]=scaling_info
    model=optimizer===nothing || optimizer isa _SDPDefaultOptimizer ? JuMP.Model() : JuMP.Model(optimizer)
    _soc===nothing || (model.ext[:soc_policy]=_soc)
    model.ext[:state_channels]=devices
    if options.audit
        model.ext[:ac_audit]=(equations=A,devices=deepcopy(devices),limits=deepcopy(limits),
            voltage=copy(voltage),real_embeddings=Any[],envelopes=Any[])
    end
    if options.decomposition==:dense
        N=_sdp_scaled_basis(A,options.basis,scales;diagnostics)
        size(N,2)>0 || _sdp_refuse("electrical equations leave no nonzero source state")
        diagnostics[:basis]=options.basis==:auto ? (size(N,2)<=32 ? :physical_sparse : :sparse) : options.basis
        diagnostics[:electrical_residual]=norm(A*N,Inf)
        diagnostics[:reduced_dimension]=size(N,2)
        H=_sdp_psd(model,size(N,2),options.cone)
    else
        supports=[collect(keys(row)) for row in equations]
        for (_,_,v,i,_) in devices, k in eachindex(v)
            push!(supports,union(collect(keys(v[k])),collect(keys(i[k]))))
        end
        for (v,i,_) in limits,k in eachindex(v)
            push!(supports,union(collect(keys(v[k])),collect(keys(i[k]))))
        end
        for (bus,_) in net["bus"], rows in values(_sdp_voltage_maps(net,bus,terminal_rows)),row in rows
            push!(supports,collect(keys(row)))
        end
        for spec in options.voltage_lncs
            push!(supports,union(collect(keys(_lnc_row(spec.u,voltage))),collect(keys(_lnc_row(spec.v,voltage)))))
        end
        for line in lnc_lines
            push!(supports,unique([k for row in [line.vf;line.vt] for k in keys(row)]))
        end
        H,N=_sdp_sparse_moment(model,A,supports,options,diagnostics;scales)
    end
    lift(a,b)=_lnc_lift(H,N,a,b)
    _soc===nothing || _soc_physical!(model,lift,devices,limits,voltage,_soc)
    _soc===nothing || _soc_strengthen!(model,H,N,lift,devices,range_pu,sb,diagnostics,_soc;fixed=fixed_source_coordinates)
    @constraint(model,real(lift(vs[anchor_k],vs[anchor_k]))==abs2(source_v[anchor_k]/vb))
    _sdp_bus_limits!(model,net,terminal_rows,lift,vb;fixed=fixed_physical)
    powers=Dict{Tuple{Symbol,String},Vector{Any}}()
    objective=JuMP.AffExpr(0.0)
    for (family,id,v,i,d) in devices
        s=Any[lift(v[k],i[k]) for k in eachindex(v)];powers[(family,id)]=s;n=length(s)
        if family==:load
            _sdp_load_law!(model,net,id,d,v,s,lift,terminal_rows,vb,sb;voltage_range)
        elseif family==:ibr_internal
            if get(d,"dc_link_coupled",false)
                for (key,lower) in (("p_dc_min",true),("p_dc_max",false))
                    haskey(d,key) || continue
                    lim=_sdp_scalar(d,key)/sb
                    lower ? @constraint(model,sum(real,s)>=lim) : @constraint(model,sum(real,s)<=lim)
                end
            elseif any(haskey(d,k) for k in ("p_dc_min","p_dc_max"))
                _sdp_refuse("ibr/$id shared-link bounds require dc_link_coupled=true")
            end
            if get(d,"grid_forming",false)
                ref=_sdp_scalar(d,"v_ref_internal");ref>0 || _sdp_refuse("ibr/$id grid forming requires positive v_ref_internal")
                for u in v
                    # A filter-free PCC on a prescribed source already has its
                    # exact magnitude. Avoid duplicating that equality with
                    # independently rounded nullspace coefficients.
                    if all(haskey(fixed_source_coordinates,k) for k in keys(u))
                        known=sum((c*fixed_source_coordinates[k] for (k,c) in u);init=0.0im)
                        isapprox(abs2(known),(ref/vb)^2;rtol=1e-12,atol=0) && continue
                    end
                    @constraint(model,real(lift(u,u))==(ref/vb)^2)
                end
            elseif haskey(d,"v_ref_internal")
                _sdp_refuse("ibr/$id v_ref_internal requires grid_forming=true")
            end
        elseif family in (:generator,:voltage_source,:ibr)
            if family==:ibr
                if haskey(d,"p_avail")
                    avail=_sdp_scalar(d,"p_avail");avail>=0 || _sdp_refuse("ibr/$id negative availability")
                    @constraint(model,sum(real,s)<=avail/sb)
                end
            end
            boxes=Dict{Symbol,Any}()
            for (lowkey,highkey,active,name) in (("p_min","p_max",true,:p),("q_min","q_max",false,:q))
                low=family==:voltage_source ? get(d,lowkey,nothing) : values_for(d,lowkey,n);high=family==:voltage_source ? get(d,highkey,nothing) : values_for(d,highkey,n)
                boxes[name]=(low,high)
                for k in 1:n
                    f=active ? real(s[k]) : imag(s[k])
                    if low!==nothing && high!==nothing && low[k]==high[k]
                        # A fixed dispatch is one equality, avoiding a pair of
                        # opposing cone inequalities with no strict interior.
                        @constraint(model,f==low[k]/sb)
                    else
                        low===nothing || !isfinite(low[k]) || @constraint(model,f>=low[k]/sb)
                        high===nothing || !isfinite(high[k]) || @constraint(model,f<=high[k]/sb)
                    end
                end
            end
            if _soc === nothing && options.port_rlt &&
               family in (:generator,:voltage_source)
                pl,pu=boxes[:p];ql,qu=boxes[:q]
                if all(x->x!==nothing,(pl,pu,ql,qu))
                    function port_limits(key)
                        haskey(d,key) || return fill(Inf,n)
                        raw=d[key]
                        values=raw isa Real ? fill(Float64(raw),n) : Float64.(raw)
                        length(values)==n && all(isfinite,values) ? values : fill(Inf,n)
                    end
                    imax=port_limits("i_max");smax=port_limits("s_max")
                    for k in 1:n
                        idk="$family/$id/$k"
                        port_bounds,reason=_port_rlt_bounds(voltage_range(v[k]),
                            pl[k],pu[k],ql[k],qu[k];imax=imax[k],smax=smax[k])
                        if port_bounds===nothing
                            push!(diagnostics[:port_rlt_diagnostics],
                                (;id=idk,status=:skipped,reason))
                            continue
                        end
                        _add_port_rlt!(model,lift(v[k],v[k]),lift(i[k],i[k]),
                            s[k],port_bounds,vb,ib)
                        push!(diagnostics[:port_rlt_diagnostics],
                            (;id=idk,status=:applied,reason="",
                             voltage_magnitude=port_bounds.bounds.u,
                             current_magnitude=port_bounds.current_magnitude,
                             power_magnitude=port_bounds.power_magnitude,
                             angle=port_bounds.bounds.angle))
                    end
                end
            end
            priced = copy(d)
            if haskey(d,"energy_cost_rate")
                haskey(d,"cost") && d["cost"]!=d["energy_cost_rate"] && _sdp_refuse("$family/$id conflicting cost aliases")
                priced["cost"]=d["energy_cost_rate"]
            end
            if family==:voltage_source && haskey(priced,"cost") && length(priced["cost"])==Base.count(x -> !isempty(x),v) && length(priced["cost"])!=n
                expanded=zeros(n); cursor=1
                for k in eachindex(v)
                    isempty(v[k]) && continue
                    expanded[k]=priced["cost"][cursor];cursor+=1
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
    if _soc!==nothing && _soc.physical
        for (family,id,_,_,d) in devices
            family==:line_from && get(d,"passive",false) || continue
            @constraint(model,sum(real,powers[(:line_from,id)])+sum(real,powers[(:line_to,id)])>=0)
        end
    end
    for (v,i,d) in limits
        n=length(v);imax=values_for(d,"i_max",n);smax=values_for(d,"s_max",n)
        for k in 1:n
            if imax!==nothing
                imax[k]>=0 || _sdp_refuse("negative current limit")
                iszero(imax[k]) || @constraint(model,real(lift(i[k],i[k])) <= (imax[k]/ib)^2)
            end
            if smax!==nothing
                smax[k]>=0 || _sdp_refuse("negative apparent-power limit")
                s=lift(v[k],i[k]);@constraint(model,[smax[k]/sb,real(s),imag(s)] in SecondOrderCone())
            end
        end
    end
    for (i,imax,_) in derived
        iszero(imax) && continue # already removed through the electrical basis
        @constraint(model,real(lift(i,i)) <= (imax/ib)^2)
    end
    objective_scale=options.scale_objective ? max(maximum(abs,values(objective.terms);init=0.0),1e-12) : 1.0
    diagnostics[:objective_scale]=objective_scale
    @objective(model,Min,objective/objective_scale)
    omitted=sort!(["ibr/$id/$(d["control_profile"])" for (id,d) in get(net,"ibr",Dict()) if haskey(d,"control_profile")])
    envelopes=sort!([id for (id,d) in get(net,"load",Dict()) if _sdp_has_load_envelope(d)])
    build=SDPBuild(model,H,N,voltage,powers,net,options,vb,anchor,source_v[anchor_k],omitted,envelopes,LNCDiagnostic[],objective_scale,diagnostics)
    for spec in options.voltage_lncs;add_voltage_lnc!(build,spec);end
    if options.lnc==:lines
        fixed=Dict(k=>value*vb for (k,value) in fixed_source_coordinates)
        _add_line_lncs!(build,lnc_lines,terminal_rows,fixed;voltage_range)
    end
    diagnostics[:removed_affine_constraints]=options.preprocess ? _sdp_preprocess_affine!(model) : 0
    if optimizer isa _SDPDefaultOptimizer
        local_cliques=diagnostics[:decomposition]==:chordal && get(diagnostics,:consistency,:shared)==:local
        JuMP.set_optimizer(model,default_sdp_optimizer(local_cliques ? :chordal : :dense))
        diagnostics[:optimizer_profile]=local_cliques ? :clarabel_chordal : :clarabel_dense
    else
        diagnostics[:optimizer_profile]=:caller_supplied
    end
    build
end

struct SDPResult <: AbstractSolveResult
    objective::Float64
    solver_objective_bound::Float64
    moment::Matrix{ComplexF64}
    voltage_candidate::Dict{Tuple{String,String},ComplexF64}
    current_candidate::Dict{Tuple{Symbol,String},Vector{ComplexF64}}
    relaxed_powers::Dict{Tuple{Symbol,String},Vector{ComplexF64}}
    rank_ratio::Float64
    solve::SolveStatus
    omitted_controls::Vector{String}
    load_envelopes::Vector{String}
    lnc_diagnostics::Vector{LNCDiagnostic}
    numerical_diagnostics::Dict{Symbol,Any}
end
solve_status(r::SDPResult)=r.solve
solve_diagnostics(r::SDPResult)=(model_kind=:relaxation, rank_ratio=r.rank_ratio,
    omitted_controls=r.omitted_controls, load_envelopes=r.load_envelopes,
    lnc_diagnostics=r.lnc_diagnostics, numerical=r.numerical_diagnostics,
    physical_feasibility_certified=false, bound_certified=false)

"""Solve IVRSDP. The recovered voltage candidate is not an AC certificate.

`solver_objective_bound` is reported as numerical solver evidence only. It is
not a rigorous, residual-corrected certificate. A feasible AC upper bound is
required before reporting an OPF optimality gap.
"""
function solve_sdp_opf(input, optimizer=default_sdp_optimizer(); options=SDPOptions(),solver_options=())
    build=build_sdp_opf(input,optimizer;options)
    solve_sdp_opf(build;solver_options)
end

"""Solve an already-built SDP without rebuilding its constraints or cuts."""
function solve_sdp_opf(build::SDPBuild;solver_options=())
    haskey(build.model.ext,:soc_policy) && throw(ArgumentError("use solve_soc_opf for an SOC build; PSD completion is not valid for indefinite moments"))
    options=build.options
    _set_solver_options!(build.model,solver_options);JuMP.optimize!(build.model)
    outcome=_solve_outcome(build.model);status=SolveStatus(outcome)
    if !outcome.optimal
        return SDPResult(NaN,NaN,fill(ComplexF64(NaN),size(build.moment)),
            Dict(k=>ComplexF64(NaN) for k in keys(build.voltage_indices)),
            Dict{Tuple{Symbol,String},Vector{ComplexF64}}(),
            Dict(k=>fill(ComplexF64(NaN),length(v)) for (k,v) in build.powers),NaN,status,build.omitted_controls,build.load_envelopes,copy(build.lnc_diagnostics),copy(build.numerical_diagnostics))
    end
    H=Matrix{ComplexF64}(JuMP.value.(build.moment));eig=eigen(Hermitian(H))
    # Recover from the voltage Gram: free auxiliary current completions must
    # not select the voltage candidate through the largest eigenvalue of H.
    rows=[i for i in values(build.voltage_indices) if i!=0]
    sort!(rows)
    NV=build.nullspace[rows,:]
    veig=eigen(Hermitian(NV*H*NV'))
    build.numerical_diagnostics[:voltage_rank_ratio]=length(veig.values)>1 ? max(0,veig.values[end-1])/max(eps(),veig.values[end]) : 0.0
    if options.recovery==:anchor
        # Conditional mean relative to the prescribed source phasor preserves
        # homogeneous electrical equations and the reference, even when free
        # floating-current/voltage modes dominate the Gram's eigenvectors.
        z=build.nullspace*H*conj.(build.nullspace[build.anchor,:])/conj(build.anchor_voltage/build.voltage_base)
        v=Dict(k=>(i==0 ? 0.0im : build.voltage_base*z[i]) for (k,i) in build.voltage_indices)
    else
        vv=sqrt(max(0,last(veig.values)))*veig.vectors[:,end]
        z=zeros(ComplexF64,size(build.nullspace,1));z[rows]=vv
        phase=iszero(z[build.anchor]) ? 1.0+0im : cis(angle(build.anchor_voltage)-angle(z[build.anchor]))
        v=Dict(k=>(i==0 ? 0.0im : build.voltage_base*z[i]*phase) for (k,i) in build.voltage_indices)
    end
    build.numerical_diagnostics[:recovery]=options.recovery
    ratio=length(eig.values)>1 ? max(0,eig.values[end-1])/max(eps(),eig.values[end]) : 0.0
    bound=try JuMP.objective_bound(build.model) catch; NaN end
    if !isfinite(bound)
        bound=try JuMP.dual_objective_value(build.model) catch; NaN end
    end
    bound*=build.objective_scale
    powers=Dict(k=>ComplexF64.(JuMP.value.(s)).*options.s_base for (k,s) in build.powers)
    SDPResult(JuMP.objective_value(build.model)*build.objective_scale,bound,H,v,_candidate_state(build).currents,powers,ratio,status,build.omitted_controls,build.load_envelopes,copy(build.lnc_diagnostics),copy(build.numerical_diagnostics))
end

"""Inspect declared/derived physical magnitude bounds and missing capability data."""
bound_report(b::SDPBuild)=b.numerical_diagnostics[:bound_report]
