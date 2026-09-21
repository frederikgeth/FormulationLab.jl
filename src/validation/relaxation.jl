"""Numerical and recovery checks for one solved SDP relaxation.

`bound_usable` is deliberately stricter than the solver's termination status:
it also requires a feasible dual status, a finite lower bound, a small residual
in the original JuMP model, and consistent primal/dual ordering. When a feasible
AC objective is supplied, the numerical lower bound must not exceed it beyond
the declared comparison tolerance.

`recovery_feasible` is reported separately. A high-rank relaxation can provide
a useful lower bound without its rank-one voltage/current recovery being AC
feasible, so recovery failure does not by itself invalidate `bound_usable`.
"""
struct RelaxationValidationReport
    solve::SolveStatus
    dual_status::String
    primal_objective::Float64
    objective_bound::Float64
    dual_objective::Float64
    solver_bound::Float64
    bound_source::String
    bound_disagreement::Float64
    relative_gap::Float64
    primal_dual_gap::Float64
    model_violation::Float64
    model_feasible::Bool
    constraint_maxima::Dict{String,Float64}
    constraint_violations::Dict{String,Int}
    physical::Any
    physical_error::Union{Nothing,String}
    recovery_feasible::Bool
    feasible_objective::Union{Nothing,Float64}
    bound_margin::Union{Nothing,Float64}
    bound_ordering_passed::Union{Nothing,Bool}
    solver_metrics::Dict{String,Float64}
    bound_usable::Bool
    reasons::Vector{String}
end

_solver_numerical_diagnostics(::Any) = Dict{String,Float64}()

function _relaxation_constraint_summary(model, raw, tolerance)
    maxima = Dict{String,Float64}()
    violations = Dict{String,Int}()
    for (F, S) in JuMP.list_of_constraint_types(model)
        refs = JuMP.all_constraints(model, F, S)
        values = Float64[get(raw, ref, 0.0) for ref in refs]
        key = string(F, " in ", S)
        maxima[key] = maximum(values; init=0.0)
        violations[key] = count(>(tolerance), values)
    end
    if haskey(model.ext, :branch_flow_matrix_kcl)
        refs = values(model.ext[:branch_flow_matrix_kcl])
        values_ = Float64[get(raw, ref, 0.0) for ref in refs]
        maxima["BranchFlowSDP matrix KCL"] = maximum(values_; init=0.0)
        violations["BranchFlowSDP matrix KCL"] = count(>(tolerance), values_)
    end
    maxima, violations
end

function _relaxation_objective(model, scale, accessor)
    value = try
        accessor(model) * scale
    catch
        NaN
    end
    isfinite(value) ? Float64(value) : NaN
end

function _relaxation_candidate(result)
    isempty(result.voltage_candidate) && return nothing
    all(isfinite, values(result.voltage_candidate)) || return nothing
    all(v -> all(isfinite, v), values(result.current_candidate)) || return nothing
    ACPoint(voltage=result.voltage_candidate, currents=result.current_candidate)
end

"""
    validate_relaxation_solution(build, result; kwargs...)

Audit an `IVRSDP` or `BranchFlowSDP` result in the original JuMP model and,
where available, independently evaluate its recovered AC point in SI units.

The optional `feasible_objective` is an externally obtained feasible objective
for the same minimization problem. It is used only to check lower-bound ordering;
it is never treated as a global optimum. `model_atol` applies to JuMP's original
constraint residuals. `bound_atol` and `bound_rtol` set the numerical ordering
tolerance for primal/dual and lower/upper-bound comparisons.
"""
function validate_relaxation_solution(
    build::Union{SDPBuild,BranchFlowSDPBuild},
    result::Union{SDPResult,BranchFlowSDPResult};
    feasible_objective::Union{Nothing,Real}=nothing,
    model_atol::Real=1e-7,
    bound_atol::Real=1e-3,
    bound_rtol::Real=1e-7,
    physical_atol=(voltage=1e-5, current=1e-6, power=1e-3),
)
    compatible = (build isa SDPBuild && result isa SDPResult) ||
        (build isa BranchFlowSDPBuild && result isa BranchFlowSDPResult)
    compatible || throw(ArgumentError(
        "build and result must come from the same SDP formulation"))
    model_atol >= 0 || throw(ArgumentError("model_atol must be nonnegative"))
    bound_atol >= 0 || throw(ArgumentError("bound_atol must be nonnegative"))
    bound_rtol >= 0 || throw(ArgumentError("bound_rtol must be nonnegative"))
    feasible_objective === nothing || isfinite(feasible_objective) ||
        throw(ArgumentError("feasible_objective must be finite"))

    model = build.model
    status = solve_status(result)
    scale = build.objective_scale
    has_primal = JuMP.has_values(model)
    raw = has_primal ? try
        JuMP.primal_feasibility_report(model; atol=0.0)
    catch
        Dict{Any,Float64}()
    end : Dict{Any,Float64}()
    model_violation = has_primal && !isempty(raw) ? maximum(values(raw)) : Inf
    model_feasible = has_primal && isfinite(model_violation) &&
        model_violation <= model_atol
    maxima, violations = _relaxation_constraint_summary(model, raw, model_atol)

    primal = has_primal ? _relaxation_objective(model, scale, JuMP.objective_value) : NaN
    objective_bound = _relaxation_objective(model, scale, JuMP.objective_bound)
    dual_objective = _relaxation_objective(model, scale, JuMP.dual_objective_value)
    bound, bound_source = if isfinite(objective_bound)
        objective_bound, "objective_bound"
    elseif isfinite(dual_objective)
        dual_objective, "dual_objective"
    else
        NaN, "unavailable"
    end
    bound_disagreement = isfinite(objective_bound) && isfinite(dual_objective) ?
        objective_bound - dual_objective : NaN
    relative_gap = try
        Float64(JuMP.relative_gap(model))
    catch
        NaN
    end
    gap = isfinite(primal) && isfinite(bound) ? primal - bound : NaN
    dual = string(JuMP.dual_status(model))
    dual_feasible = JuMP.dual_status(model) == JuMP.MOI.FEASIBLE_POINT
    comparison_scale = max(abs(primal), abs(bound), 1.0)
    gap_tolerance = max(Float64(bound_atol), Float64(bound_rtol) * comparison_scale)
    primal_dual_consistent = isfinite(gap) && gap >= -gap_tolerance

    feasible = feasible_objective === nothing ? nothing : Float64(feasible_objective)
    margin = feasible === nothing || !isfinite(bound) ? nothing : feasible - bound
    ordering_tolerance = feasible === nothing ? nothing :
        max(Float64(bound_atol), Float64(bound_rtol) * max(abs(feasible), abs(bound), 1.0))
    ordering = margin === nothing ? nothing : margin >= -ordering_tolerance
    solver_metrics = try
        _solver_numerical_diagnostics(JuMP.unsafe_backend(model))
    catch
        Dict{String,Float64}()
    end

    physical = nothing
    physical_error = nothing
    candidate = _relaxation_candidate(result)
    if candidate !== nothing
        try
            physical = physical_residuals(build.network, candidate; atol=physical_atol)
        catch err
            physical_error = sprint(showerror, err)
        end
    end
    recovery_feasible = physical !== nothing && physical.passed

    reasons = String[]
    status.optimal || push!(reasons, "solver termination is not optimal")
    has_primal || push!(reasons, "no primal point is available")
    model_feasible || push!(reasons,
        "original-model residual $(model_violation) exceeds $(model_atol)")
    dual_feasible || push!(reasons, "dual status is not feasible")
    isfinite(bound) || push!(reasons, "solver lower bound is not finite")
    isfinite(primal) || push!(reasons, "primal relaxation objective is not finite")
    primal_dual_consistent || push!(reasons,
        "solver lower bound exceeds the primal relaxation objective")
    ordering === false && push!(reasons,
        "solver lower bound exceeds the supplied feasible AC objective")
    usable = isempty(reasons)

    RelaxationValidationReport(status, dual, primal, objective_bound,
        dual_objective, bound, bound_source, bound_disagreement, relative_gap, gap,
        model_violation, model_feasible, maxima, violations, physical,
        physical_error, recovery_feasible, feasible, margin, ordering,
        solver_metrics, usable, reasons)
end
