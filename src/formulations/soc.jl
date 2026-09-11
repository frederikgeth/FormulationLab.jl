default_soc_optimizer()=default_optimizer(Val(:clarabel_soc))

"""SOC outer relaxation options. `electrical` selects the matching SDP layout and cuts."""
Base.@kwdef struct SOCOptions
    profile::Symbol=:custom # provenance label; IVRSOC resolves presets
    electrical::SDPOptions=SDPOptions()
    physical_projections::Bool=true
    voltage_recovery::Symbol=:voltage_tree
    strengthening::Symbol=:linear
    max_triplets::Int=16
    directions::Tuple=(1.0+0im,1.0im)
end

struct SOCBuild
    electrical::SDPBuild
    blocks::Vector{Any}
    options::SOCOptions
end
# The JuMP model is intentionally directly inspectable.
Base.propertynames(::SOCBuild,private::Bool=false)=(fieldnames(SOCBuild)...,:model)
function Base.getproperty(b::SOCBuild,k::Symbol)
    k===:model && return getfield(b,:electrical).model
    getfield(b,k)
end

phasor_products(b::SOCBuild,u::VoltagePhasor,v::VoltagePhasor)=phasor_products(b.electrical,u,v)
add_voltage_lnc!(b::SOCBuild,spec::VoltageLNC)=add_voltage_lnc!(b.electrical,spec)

function _soc_block!(model,H)
    push!(model.ext[:soc_policy].blocks,H)
    for i in axes(H,1)
        @constraint(model,real(H[i,i])>=0)
        for j in 1:i-1
            @constraint(model,[real(H[i,i]),real(H[j,j]),sqrt(2)*real(H[i,j]),sqrt(2)*imag(H[i,j])] in RotatedSecondOrderCone())
        end
    end
end

function _soc_physical!(model,lift,devices,limits,voltage,policy)
    policy.physical || return
    # These consequences of PSD are not implied by coordinate-wise minors.
    seen=Set{Any}()
    function pair(v,i)
        key=(sort!(collect(v);by=first),sort!(collect(i);by=first))
        key in seen && return
        push!(seen,key)
        w=real(lift(v,v)); l=real(lift(i,i)); s=lift(v,i)
        ws=max(maximum(abs,values(w.terms);init=0.0),abs(w.constant))
        ls=max(maximum(abs,values(l.terms);init=0.0),abs(l.constant))
        if iszero(ws) || iszero(ls)
            @constraint(model,w>=0); @constraint(model,l>=0)
        else
            cross_scale=sqrt(ws*ls)
            isfinite(cross_scale) && cross_scale>0 || (cross_scale=sqrt(ws)*sqrt(ls))
            x=@variable(model,[1:4])
            for (y,f) in zip(x,(w/ws,l/ls,real(s)/cross_scale,imag(s)/cross_scale))
                @constraint(model,y==f)
            end
            @constraint(model,[x[1],x[2],sqrt(2)*x[3],sqrt(2)*x[4]] in RotatedSecondOrderCone())
        end
    end
    for (_,_,v,i,_) in devices, k in eachindex(v); pair(v[k],i[k]);end
    for (v,i,_) in limits, k in eachindex(v);pair(v[k],i[k]);end
    for idx in values(voltage)
        idx==0 && continue
        v=_SDPRow(idx=>1.0+0im)
        @constraint(model,real(lift(v,v))>=0)
    end
end

"""Build the shared electrical relaxation using only pairwise SOC moment cones."""
function build_soc_opf(input,optimizer=default_soc_optimizer();options::SOCOptions=SOCOptions())
    options.voltage_recovery in (:voltage_tree,:conditional) || throw(ArgumentError("voltage_recovery must be :voltage_tree or :conditional"))
    options.strengthening in (:none,:linear,:kim) || throw(ArgumentError("strengthening must be :none, :linear or :kim"))
    options.max_triplets>=0 || throw(ArgumentError("max_triplets must be nonnegative"))
    all(c->c isa Number && isfinite(c),options.directions) || throw(ArgumentError("directions must be finite constants"))
    policy=(blocks=Any[],physical=options.physical_projections,options=options)
    b=build_sdp_opf(input,optimizer;options=options.electrical,_soc=policy)
    b.numerical_diagnostics[:soc_profile]=options.profile
    b.numerical_diagnostics[:soc_options]=(physical_projections=options.physical_projections,
        strengthening=options.strengthening,max_triplets=options.max_triplets,
        directions=options.directions,voltage_recovery=options.voltage_recovery)
    b.numerical_diagnostics[:cone]=:soc
    b.numerical_diagnostics[:physical_projections]=options.physical_projections
    SOCBuild(b,policy.blocks,options)
end

"""SOC result, without assuming an indefinite moment admits PSD completion."""
struct SOCResult <: AbstractSolveResult
    objective::Float64
    solver_objective_bound::Float64
    blocks::Vector{Matrix{ComplexF64}}
    relaxed_powers::Dict{Tuple{Symbol,String},Vector{ComplexF64}}
    solve::SolveStatus
    stop_reason::Symbol
    history::Vector{NamedTuple}
    cuts::Int
    psd_residual::Float64
    metadata::NamedTuple
end
solve_status(r::SOCResult)=r.solve
solve_diagnostics(r::SOCResult)=(;r.metadata...,psd_residual=r.psd_residual,stop_reason=r.stop_reason,
    cuts=r.cuts,physical_feasibility_certified=false,bound_certified=false)

bound_report(b::SOCBuild)=bound_report(b.electrical)

function solve_soc_opf(input,optimizer=default_soc_optimizer();options=SOCOptions(),kwargs...)
    solve_soc_opf(build_soc_opf(input,optimizer;options);kwargs...)
end

"""Solve the fixed conic formulation once. Spectral diagnostics never select constraints."""
function solve_soc_opf(b::SOCBuild;solver_options=())
    metadata=(omitted_controls=copy(b.electrical.omitted_controls),
        load_envelopes=copy(b.electrical.load_envelopes),lnc_diagnostics=copy(b.electrical.lnc_diagnostics),
        numerics=copy(b.electrical.numerical_diagnostics))
    model=b.model;_set_solver_options!(model,solver_options)
    start=time_ns();JuMP.optimize!(model);status=SolveStatus(_solve_outcome(model))
    if !status.publishable
        return SOCResult(NaN,NaN,Matrix{ComplexF64}[],Dict{Tuple{Symbol,String},Vector{ComplexF64}}(),status,:solver_failure,NamedTuple[],0,NaN,metadata)
    end
    blocks=[Matrix{ComplexF64}(JuMP.value.(H)) for H in b.blocks]
    residual=maximum((begin
        e=eigvals(Hermitian(H));isempty(e) ? 0.0 : max(0.0,-minimum(e))/max(1.0,maximum(abs,e))
    end for H in blocks);init=0.0)
    objective=JuMP.objective_value(model)*b.electrical.objective_scale
    bound=try JuMP.objective_bound(model) catch;NaN end
    isfinite(bound) || (bound=try JuMP.dual_objective_value(model) catch;NaN end)
    bound*=b.electrical.objective_scale
    powers=Dict(k=>ComplexF64.(JuMP.value.(s)).*b.options.electrical.s_base for (k,s) in b.electrical.powers)
    history=NamedTuple[(round=0,objective=objective,bound=bound,psd_residual=residual,cuts=0,
        elapsed=(time_ns()-start)/1e9,optimizer_seconds=try JuMP.solve_time(model) catch;NaN end)]
    candidate=b.options.voltage_recovery==:voltage_tree ? _soc_voltage_state(b.electrical) : _candidate_state(b.electrical)
    metadata=(metadata...,candidate=candidate,recovery=b.options.voltage_recovery,
        unanchored_voltage_coordinates=get(b.electrical.numerical_diagnostics,:recovery_unanchored_coordinates,0))
    SOCResult(objective,bound,blocks,powers,status,:one_shot,history,0,residual,metadata)
end
