default_soc_optimizer()=default_optimizer(Val(:clarabel_soc))

"""SOC outer relaxation options. `electrical` selects the matching SDP layout and cuts."""
Base.@kwdef struct SOCOptions
    electrical::SDPOptions=SDPOptions()
    physical_projections::Bool=true
end

"""Budgets and relative spectral tolerance for optional PSD separation."""
Base.@kwdef struct PSDSeparationOptions
    max_rounds::Int=30
    max_cuts::Int=2000
    time_limit::Float64=60.0
    tolerance::Float64=1e-6
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
    policy=(blocks=Any[],physical=options.physical_projections)
    b=build_sdp_opf(input,optimizer;options=options.electrical,_soc=policy)
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

function _soc_eigencut!(model,H,u)
    f=JuMP.AffExpr(0.0)
    for i in eachindex(u),j in eachindex(u)
        JuMP.add_to_expression!(f,real(conj(u[i])*u[j]*H[i,j]))
    end
    scale=max(1.0,maximum(abs,values(f.terms);init=0.0))
    @constraint(model,f/scale>=0)
end

function solve_soc_opf(input,optimizer=default_soc_optimizer();options=SOCOptions(),kwargs...)
    solve_soc_opf(build_soc_opf(input,optimizer;options);kwargs...)
end

"""Solve once, or tighten by valid linear eigenvector cuts. No PSD cones are added."""
function solve_soc_opf(b::SOCBuild;separation::Union{Nothing,PSDSeparationOptions}=nothing,solver_options=())
    o=separation===nothing ? PSDSeparationOptions(max_rounds=0,time_limit=Inf) : separation
    o.max_rounds>=0 && o.max_cuts>=0 && o.time_limit>0 && isfinite(o.tolerance) && o.tolerance>0 || throw(ArgumentError("invalid separation budget or tolerance"))
    metadata=(omitted_controls=copy(b.electrical.omitted_controls),
        load_envelopes=copy(b.electrical.load_envelopes),
        lnc_diagnostics=copy(b.electrical.lnc_diagnostics),
        numerics=copy(b.electrical.numerical_diagnostics))
    make_result(args...)=SOCResult(args...,metadata)
    model=b.model;_set_solver_options!(model,solver_options)
    solver_limit=JuMP.time_limit_sec(model)
    start=time_ns(); elapsed()=(time_ns()-start)/1e9
    history=NamedTuple[]; cuts=0; directions=Dict{Int,Vector{Vector{ComplexF64}}}()
    result=nothing
    try
        for round in 0:o.max_rounds
            remaining=o.time_limit-elapsed()
            remaining>0 || break
            isfinite(remaining) && JuMP.set_time_limit_sec(model,solver_limit===nothing ? remaining : min(remaining,solver_limit))
            JuMP.optimize!(model); status=SolveStatus(_solve_outcome(model))
            if !status.publishable
                return make_result(NaN,NaN,Matrix{ComplexF64}[],Dict{Tuple{Symbol,String},Vector{ComplexF64}}(),status,:solver_failure,history,cuts,NaN)
            end
            values=[Matrix{ComplexF64}(JuMP.value.(H)) for H in b.blocks]
            candidates=Tuple{Float64,Int,Vector{ComplexF64}}[]; residual=0.0
            for (k,H) in enumerate(values)
                isempty(H) && continue
                e=eigen(Hermitian(H)); scale=max(1.0,maximum(abs,e.values))
                residual=max(residual,max(0.0,-minimum(e.values))/scale)
                for j in eachindex(e.values)
                    e.values[j] < -o.tolerance*scale || continue
                    push!(candidates,(e.values[j]/scale,k,e.vectors[:,j]))
                end
            end
            objective=JuMP.objective_value(model)*b.electrical.objective_scale
            bound=try JuMP.objective_bound(model) catch; NaN end
            isfinite(bound) || (bound=try JuMP.dual_objective_value(model) catch; NaN end)
            bound*=b.electrical.objective_scale
            push!(history,(round=round,objective=objective,bound=bound,psd_residual=residual,cuts=cuts,elapsed=elapsed(),optimizer_seconds=try JuMP.solve_time(model) catch; NaN end))
            powers=Dict(k=>ComplexF64.(JuMP.value.(s)).*b.options.electrical.s_base for (k,s) in b.electrical.powers)
            reason= isempty(candidates) ? :psd_tolerance : separation===nothing ? :one_shot : round==o.max_rounds ? :round_limit : cuts>=o.max_cuts ? :cut_limit : elapsed()>=o.time_limit ? :time_limit : :continue
            result=make_result(objective,bound,values,powers,status,reason,copy(history),cuts,residual)
            reason==:continue || return result
            added=0
            for (_,k,u) in sort!(candidates;by=first)
                cuts>=o.max_cuts && break
                prior=get!(directions,k,Vector{ComplexF64}[])
                any(v->abs(dot(v,u))>1-1e-10,prior) && continue
                _soc_eigencut!(model,b.blocks[k],u);push!(prior,u);cuts+=1;added+=1
            end
            added==0 && return make_result(objective,bound,values,powers,status,:stalled,history,cuts,residual)
        end
        # A budget expiry after cut insertion retains the last solved iterate.
        if result===nothing
            status=SolveStatus("TIME_LIMIT","NO_SOLUTION",false,false,false,false)
            return make_result(NaN,NaN,Matrix{ComplexF64}[],Dict{Tuple{Symbol,String},Vector{ComplexF64}}(),status,:time_limit,history,0,NaN)
        end
        make_result(result.objective,result.solver_objective_bound,result.blocks,result.relaxed_powers,
            result.solve,:time_limit,result.history,result.cuts,result.psd_residual)
    finally
        # A per-call OA budget must not shorten subsequent solves of this build.
        JuMP.set_time_limit_sec(model,solver_limit)
    end
end
