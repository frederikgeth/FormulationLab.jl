"""Experimental no-load explicit-neutral approximation; powers remain decision variables.

`objective` is `:cost`, `:source_import`, `:feasibility`, or `:losses` (passive
line, shunt, transformer and inverter-filter dissipation). `voltage_radius` optionally bounds
each power port's complex voltage displacement relative to its no-load voltage.
"""
Base.@kwdef struct LinIVROptions
    s_base::Float64 = 1e4
    objective::Symbol = :cost
    voltage_radius::Union{Nothing,Float64} = nothing
end

struct LinIVRInapplicableError <: Exception
    message::String
end
Base.showerror(io::IO, e::LinIVRInapplicableError) = print(io, "LinIVR: ", e.message)
_linivr_refuse(message) = throw(LinIVRInapplicableError(message))
_linivr_eval(row, z) = sum((c*z[k] for (k,c) in row); init=0.0im)

struct LinIVRBuild
    model::JuMP.Model
    state::Any
    reference::Vector{ComplexF64}
    powers::Dict{Tuple{Symbol,String},Vector{Any}}
    electrical::Any
    network::Dict{String,Any}
    options::LinIVROptions
    loss_expression::Any
    numerical_diagnostics::Dict{Symbol,Any}
end

function _linivr_check(net, options)
    _sdp_check(net)
    isempty(get(net,"control_profile",Dict())) || _linivr_refuse("control profiles are not evaluated")
    for (id,d) in get(net,"ibr",Dict())
        haskey(d,"control_profile") && _linivr_refuse("ibr/$id control profiles are not evaluated")
        (get(d,"grid_forming",false) || haskey(d,"v_ref_internal")) &&
            _linivr_refuse("ibr/$id grid-forming/internal voltage regulation is not yet supported")
    end
    for (id,d) in get(net,"load",Dict())
        lowercase(get(d,"model","constant_power")) in ("constant_power","constant_impedance") ||
            _sdp_is_impedance_load(d) ||
            _linivr_refuse("load/$id requires constant power or an exactly constant-impedance law")
    end
end

# A sparse linear no-load circuit solve, with all constant-power port currents
# set to zero. Impedance loads, shunts and excitation stay in the circuit.
# All conductor voltages must be unique. Current-only freedom is retained in
# the optimization; minimum-norm reference currents merely choose its expansion
# point. Never add a zero-circulation constraint to the operating circuit.
function _linivr_reference(e)
    rows = vcat(e.equations, collect(values(e.kcl)))
    for (family,_,_,i,d) in e.devices
        (family in (:generator,:ibr) || (family==:load && !_sdp_is_impedance_load(d))) && append!(rows,i)
    end
    push!(rows,_sdp_e(e.anchor))
    n=e.coordinate_count[]
    ri=Int[];ci=Int[];av=ComplexF64[]
    rhs=zeros(ComplexF64,length(rows));rhs[end]=e.source_v[e.anchor_k]/e.vb
    for (r,row) in enumerate(rows)
        scale=norm(collect(values(row)))
        iszero(scale) && continue
        for (c,a) in row
            push!(ri,r);push!(ci,c);push!(av,a/scale)
        end
        rhs[r]/=scale
    end
    A=sparse(ri,ci,av,length(rows),n)
    F=qr(A;tol=1e-10)
    pivots=abs.(diag(F.R))
    rank_estimate=count(>(1e-10),pivots)
    z=Vector{ComplexF64}(F\rhs)
    nullity=n-rank_estimate
    ambiguous=String[]
    if nullity>0
        r=rank_estimate
        # SPQR moves dependent columns to the end. Verify this ordering and
        # the resulting nullspace rather than trusting a numerical rank alone.
        all(>(1e-10),pivots[1:r]) || _linivr_refuse("ill-conditioned no-load factorization")
        N=zeros(ComplexF64,n,nullity)
        N[F.pcol[r+1:n],:]=Matrix{ComplexF64}(I,nullity,nullity)
        if r>0
            N[F.pcol[1:r],:]=-(UpperTriangular(F.R[1:r,1:r])\Matrix(F.R[1:r,r+1:n]))
        end
        for k in axes(N,2);N[:,k]/=norm(N[:,k]);end
        norm(A*N,Inf)<=1e-8 || _linivr_refuse("ill-conditioned no-load nullspace")
        live=[k for k in values(e.voltage) if k!=0]
        maximum(abs,N[live,:];init=0.0)<=1e-9 ||
            _linivr_refuse("no-load conductor voltages are not unique; check grounding and islands")
        z-=N*(N\z)
        for (family,id,_,currents,_) in e.devices,(k,row) in enumerate(currents)
            variation=[_linivr_eval(row,view(N,:,c)) for c in axes(N,2)]
            maximum(abs,variation;init=0.0)>1e-9 && push!(ambiguous,"$family/$id/$k")
        end
    end
    residual=norm(A*z-rhs,Inf)
    all(isfinite,z) && residual<=1e-8 ||
        _linivr_refuse("inconsistent no-load circuit (scaled residual $residual)")
    z,residual,(;nullity,ambiguous_currents=ambiguous)
end

function _linivr_norm_limit!(model,z,bound)
    iszero(bound) ? (@constraint(model,real(z)==0); @constraint(model,imag(z)==0)) :
        @constraint(model,[bound,real(z),imag(z)] in SecondOrderCone())
end

function _linivr_bus_limits!(model,net,e,z,z0)
    for (b,d) in net["bus"]
        maps=_sdp_voltage_maps(net,b,e.terminal_rows)
        for key in ("v_min","v_max","vpn_min","vpn_max","vpp_min","vpp_max",
                    "vn_max","vpos_min","vpos_max","vneg_max","vzero_max")
            haskey(d,key) || continue
            prefix=startswith(key,"v_") ? key : first(split(key,"_"))
            haskey(maps,prefix) || _linivr_refuse("bus/$b $key requires corresponding terminals")
            rows=maps[prefix];bounds=_sdp_vector(d,key,length(rows))
            for (row,bound) in zip(rows,bounds)
                bound>=0 || _linivr_refuse("bus/$b negative voltage limit")
                u=_linivr_eval(row,z);u0=_linivr_eval(row,z0)
                if endswith(key,"max")
                    _linivr_norm_limit!(model,u,bound/e.vb)
                elseif bound>0
                    abs(u0)>1e-10 || _linivr_refuse("bus/$b positive $key on a zero no-load voltage")
                    # Supporting halfspace: conservative for the approximate
                    # phasor, but not an AC-feasibility certificate.
                    @constraint(model,real(conj(u0)*u)/abs(u0)>=bound/e.vb)
                end
            end
        end
    end
end

function _linivr_loss_expression(net,e,z;require_passive=false)
    loss=JuMP.QuadExpr(JuMP.AffExpr(0.0))
    function add_loss(rows,M,factor)
        H=Hermitian((M+M')/2)
        if require_passive && minimum(eigvals(H);init=0.0)<-1e-12
            _linivr_refuse(":losses requires passive circuit dissipation matrices")
        end
        x=[_linivr_eval(row,z) for row in rows]
        for a in eachindex(x),b in eachindex(x)
            JuMP.add_to_expression!(loss,factor*real(conj(x[a])*H[a,b]*x[b]))
        end
    end
    for l in e.lnc_lines
        add_loss(l.current,l.Z,e.ib^2)
        add_loss(l.vf,l.Yf,e.vb^2);add_loss(l.vt,l.Yt,e.vb^2)
    end
    for d in values(get(net,"shunt",Dict()))
        rows=e.terminal_rows(d["bus"],d["terminal_map"])
        add_loss(rows,_l3f_shunt_matrix(d,length(rows)),e.vb^2)
    end
    line_shunt_loss=copy(loss)
    channels=Dict((f,id)=>(v,i) for (f,id,v,i,_) in e.devices)
    function grounding_loss(d,rkey,xkey,bus,tm)
        haskey(d,rkey) || haskey(d,xkey) || return
        impedance=complex(get(d,rkey,0.),get(d,xkey,0.))
        iszero(impedance) && return
        neutral=get(_kr_neutral_map(net),bus,nothing)
        neutral===nothing && return # the electrical assembler validates it
        add_loss(e.terminal_rows(bus,[neutral]),reshape([inv(impedance)],1,1),e.vb^2)
    end
    for (kind,table) in get(net,"transformer",Dict()),(id,d) in table
        if kind=="n_winding"
            p=_sdp_nwinding_plan(net,id,d)
            for (k,w) in enumerate(p.ws)
                u,j=channels[(:transformer_coil,"n_winding/$id/$k")]
                # Z uses winding-1 referred impedances; J_k=turns_k*j_k.
                nominal=w["v_nom"]/p.ws[1]["v_nom"]
                resistance=get(w,"r_winding",0.)*(p.turns[k]/nominal)^2
                add_loss(j,Diagonal(fill(resistance,length(j))),e.ib^2)
                k==p.shunt && add_loss(u,Diagonal(fill(p.y,length(u))),e.vb^2)
                grounding_loss(w,"r_neutral","x_neutral",w["bus"],w["terminal_map"])
            end
        else
            p=_sdp_transformer_plan(kind,d,"transformer/$kind/$id")
            for (side,Z,Y) in ((:from,p.Zf,p.Yf),(:to,p.Zt,p.Yt))
                u,j=channels[(Symbol("transformer_coil_",side),"$kind/$id")]
                add_loss(j,Diagonal(Z),e.ib^2);add_loss(u,Diagonal(Y),e.vb^2)
                grounding_loss(d,"r_neutral_$side","x_neutral_$side",d["bus_$side"],d["terminal_map_$side"])
            end
        end
    end
    transformer_loss=loss-line_shunt_loss
    before_filters=copy(loss)
    for (id,d) in get(net,"ibr",Dict())
        _,j=channels[(:ibr_internal,id)]
        rf=_sdp_vector(d,"r_filter",length(j);default=zeros(length(j)))
        add_loss(j,Diagonal(rf),e.ib^2)
    end
    (;total=loss,line_shunt=line_shunt_loss,transformer=transformer_loss,
       ibr_filter=loss-before_filters)
end

"""Build LinIVR without Kron reduction or a loaded operating point.

Only device power products are approximated. Upper voltage/current magnitudes
are SOC constraints; positive lower voltage limits use reference-oriented
halfspaces. Build with `optimizer=nothing` to inspect or customize the model.
"""
function build_linivr_opf(input,optimizer=default_optimizer();options=LinIVROptions())
    try
        _build_linivr_opf(input,optimizer,options)
    catch err
        err isa SDPInapplicableError && _linivr_refuse(err.message)
        rethrow()
    end
end

function _build_linivr_opf(input,optimizer,options)
    isfinite(options.s_base) && options.s_base>0 || throw(ArgumentError("s_base must be positive and finite"))
    options.objective in (:cost,:source_import,:feasibility,:losses) || throw(ArgumentError("unknown LinIVR objective"))
    radius=options.voltage_radius
    radius===nothing || (isfinite(radius) && 0<radius<1) || throw(ArgumentError("voltage_radius must be between zero and one"))
    net=_l3f_input(input);_linivr_check(net,options)
    e=_ivr_electrical_data(net;s_base=options.s_base,line_records=true,delta_dispatch=:coil)
    z0,reference_residual,reference_info=_linivr_reference(e)
    model=optimizer===nothing ? JuMP.Model() : JuMP.Model(optimizer)
    n=e.coordinate_count[]
    xr=@variable(model,[1:n],base_name="state_real")
    xi=@variable(model,[1:n],base_name="state_imag")
    z=xr+im*xi
    for row in vcat(e.equations,collect(values(e.kcl)))
        isempty(row) && continue
        expression=_linivr_eval(row,z)/norm(collect(values(row)))
        @constraint(model,real(expression)==0);@constraint(model,imag(expression)==0)
    end
    @constraint(model,xr[e.anchor]==real(z0[e.anchor]))
    @constraint(model,xi[e.anchor]==imag(z0[e.anchor]))
    affine_power(v,i)=begin
        u0=_linivr_eval(v,z0);j0=_linivr_eval(i,z0)
        u0*conj(_linivr_eval(i,z))+conj(j0)*_linivr_eval(v,z)-u0*conj(j0)
    end
    powers=Dict{Tuple{Symbol,String},Vector{Any}}()
    objective=JuMP.AffExpr(0.0)
    for (family,id,v,i,d) in e.devices
        count=length(v)
        p=@variable(model,[1:count],base_name="$(family)_$(id)_p")
        q=@variable(model,[1:count],base_name="$(family)_$(id)_q")
        s=Any[p[k]+im*q[k] for k in 1:count];powers[(family,id)]=s
        for k in 1:count
            a=affine_power(v[k],i[k])
            @constraint(model,p[k]==real(a));@constraint(model,q[k]==imag(a))
        end
        if family in (:generator,:ibr) || (family==:load && !_sdp_is_impedance_load(d))
            for row in v
                u0=_linivr_eval(row,z0)
                abs(u0)>1e-8 || _linivr_refuse("$family/$id has a zero no-load connection voltage")
                radius===nothing || _linivr_norm_limit!(model,_linivr_eval(row,z)-u0,radius*abs(u0))
            end
        end
        if family==:load && !_sdp_is_impedance_load(d)
            pn=e.values_for(d,"p_nom",count);qn=e.values_for(d,"q_nom",count)
            for k in 1:count
                @constraint(model,p[k]==pn[k]/e.sb);@constraint(model,q[k]==qn[k]/e.sb)
            end
        elseif family==:ibr_internal
            if get(d,"dc_link_coupled",false)
                for (key,lower) in (("p_dc_min",true),("p_dc_max",false))
                    haskey(d,key) || continue
                    bound=_sdp_scalar(d,key)/e.sb
                    lower ? @constraint(model,sum(p)>=bound) : @constraint(model,sum(p)<=bound)
                end
            elseif any(haskey(d,k) for k in ("p_dc_min","p_dc_max"))
                _linivr_refuse("ibr/$id shared-link bounds require dc_link_coupled=true")
            end
        elseif family in (:generator,:voltage_source,:ibr)
            if family==:ibr && haskey(d,"p_avail")
                available=_sdp_scalar(d,"p_avail")
                available>=0 || _linivr_refuse("ibr/$id negative availability")
                @constraint(model,sum(p)<=available/e.sb)
            end
            for (lo,hi,x) in (("p_min","p_max",p),("q_min","q_max",q))
                low=family==:voltage_source ? get(d,lo,nothing) : e.values_for(d,lo,count)
                high=family==:voltage_source ? get(d,hi,nothing) : e.values_for(d,hi,count)
                for k in 1:count
                    if low!==nothing && high!==nothing && low[k]==high[k]
                        @constraint(model,x[k]==low[k]/e.sb)
                    else
                        low===nothing || !isfinite(low[k]) || @constraint(model,x[k]>=low[k]/e.sb)
                        high===nothing || !isfinite(high[k]) || @constraint(model,x[k]<=high[k]/e.sb)
                    end
                end
            end
            priced=copy(d)
            if haskey(d,"energy_cost_rate")
                haskey(d,"cost") && d["cost"]!=d["energy_cost_rate"] && _linivr_refuse("$family/$id conflicting cost aliases")
                priced["cost"]=d["energy_cost_rate"]
            end
            cost=e.values_for(priced,"cost",count;default=zeros(count))
            for k in 1:count
                coefficient=options.objective==:cost ? cost[k]*e.sb/1000 :
                    options.objective==:source_import && family==:voltage_source ? e.sb : 0.0
                JuMP.add_to_expression!(objective,coefficient,p[k])
            end
            if family==:voltage_source && haskey(d,"s_max")
                tm=d["terminal_map"];nt=get(_kr_neutral_map(net),d["bus"],nothing)
                phases=findall(!=(nt),tm);bounds=_sdp_vector(d,"s_max",length(phases))
                for (k,b) in zip(phases,bounds)
                    b>=0 || _linivr_refuse("source/$id negative apparent-power limit")
                    _linivr_norm_limit!(model,s[k],b/e.sb)
                end
            end
        end
    end
    for (v,i,d) in e.limits
        imax=e.values_for(d,"i_max",length(i));smax=e.values_for(d,"s_max",length(v))
        for k in eachindex(v)
            if imax!==nothing
                imax[k]>=0 || _linivr_refuse("negative current limit")
                _linivr_norm_limit!(model,_linivr_eval(i[k],z),imax[k]/e.ib)
            end
            if smax!==nothing
                smax[k]>=0 || _linivr_refuse("negative apparent-power limit")
                _linivr_norm_limit!(model,affine_power(v[k],i[k]),smax[k]/e.sb)
            end
        end
    end
    _linivr_bus_limits!(model,net,e,z,z0)
    losses=_linivr_loss_expression(net,e,z;require_passive=options.objective==:losses)
    obj=options.objective==:losses ? losses.total : objective
    @objective(model,Min,obj/e.sb)
    diagnostics=Dict{Symbol,Any}(:reference=>:no_load,:reference_residual=>reference_residual,
        :state_dimension=>n,:kron_reduction=>false,:voltage_radius=>radius,
        :power_model=>:first_order,:upper_voltage_limits=>:soc,
        :delta_dispatch=>:coil,
        :lower_voltage_limits=>:reference_halfspace,:loss_objective=>options.objective==:losses,
        :reference_current_nullity=>reference_info.nullity,
        :reference_current_choice=>reference_info.nullity==0 ? :unique : :minimum_norm,
        :ambiguous_reference_currents=>reference_info.ambiguous_currents)
    LinIVRBuild(model,z,z0,powers,e,net,options,losses,diagnostics)
end

struct LinIVRResult <: AbstractSolveResult
    objective::Float64
    voltage_candidate::Dict{Tuple{String,String},ComplexF64}
    current_candidate::Dict{Tuple{Symbol,String},Vector{ComplexF64}}
    powers::Dict{Tuple{Symbol,String},Vector{ComplexF64}}
    physical_powers::Dict{Tuple{Symbol,String},Vector{ComplexF64}}
    solve::SolveStatus
    numerical_diagnostics::Dict{Symbol,Any}
end
solve_status(r::LinIVRResult)=r.solve
solve_diagnostics(r::LinIVRResult)=(model_kind=:approximation,numerical=r.numerical_diagnostics,
    physical_feasibility_certified=false,bound_certified=false)

function solve_linivr_opf(input,optimizer=default_optimizer();options=LinIVROptions(),solver_options=())
    solve_linivr_opf(build_linivr_opf(input,optimizer;options);solver_options)
end

"""Solve LinIVR and report actual connection products separately from modeled powers."""
function solve_linivr_opf(build::LinIVRBuild;solver_options=())
    _set_solver_options!(build.model,solver_options);JuMP.optimize!(build.model)
    outcome=_solve_outcome(build.model);e=build.electrical
    diagnostic=copy(build.numerical_diagnostics)
    voltage=Dict{Tuple{String,String},ComplexF64}()
    currents=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    powers=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    physical=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    if !outcome.optimal
        return LinIVRResult(NaN,voltage,currents,powers,physical,SolveStatus(outcome),diagnostic)
    end
    z=ComplexF64.(JuMP.value.(build.state))
    for (key,k) in e.voltage;voltage[key]=k==0 ? 0im : z[k]*e.vb;end
    max_mismatch=0.0;max_relative=0.0;max_displacement=0.0
    for (family,id,v,i,d) in e.devices
        key=(family,id)
        currents[key]=ComplexF64[_linivr_eval(row,z)*e.ib for row in i]
        powers[key]=ComplexF64.(JuMP.value.(build.powers[key])).*e.sb
        physical[key]=ComplexF64[_linivr_eval(v[k],z)*conj(_linivr_eval(i[k],z))*e.sb for k in eachindex(v)]
        if family in (:load,:generator,:ibr,:ibr_internal)
            max_mismatch=max(max_mismatch,maximum(abs,physical[key]-powers[key];init=0.0))
            for k in eachindex(v)
                abs(powers[key][k])>1e-6 && (max_relative=max(max_relative,abs(physical[key][k]-powers[key][k])/abs(powers[key][k])))
                u0=_linivr_eval(v[k],build.reference)
                abs(u0)>1e-8 && (max_displacement=max(max_displacement,abs(_linivr_eval(v[k],z)-u0)/abs(u0)))
            end
        end
    end
    diagnostic[:max_device_power_mismatch_VA]=max_mismatch
    diagnostic[:max_relative_device_power_mismatch]=max_relative
    diagnostic[:max_relative_connection_voltage_displacement]=max_displacement
    diagnostic[:line_shunt_losses_W]=JuMP.value(build.loss_expression.line_shunt)
    diagnostic[:transformer_losses_W]=JuMP.value(build.loss_expression.transformer)
    diagnostic[:ibr_filter_losses_W]=JuMP.value(build.loss_expression.ibr_filter)
    diagnostic[:passive_losses_W]=JuMP.value(build.loss_expression.total)
    LinIVRResult(JuMP.objective_value(build.model)*e.sb,voltage,currents,powers,physical,SolveStatus(outcome),diagnostic)
end
