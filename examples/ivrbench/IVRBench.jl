"""Lightweight exact-IVR benchmark harness.

Answers one question: which formulation arms solve fastest and most reliably,
and *why* (iterations vs per-iteration linear algebra vs function evaluation).

Design, deliberately simple:
- each (instance, arm, solver) gets one diagnostic solve (MUMPS factor size,
  structure) followed by `reps` timed cold solves on fresh builds;
- solver time is Ipopt's/MadNLP's optimizer-call wall time; build is excluded
  but recorded;
- a duplicate control arm (`powers_dup`) measures the noise floor;
- a trial succeeds when the solver accepts and the SI physical residuals pass;
  failures are kept and count against the arm in performance profiles.

Results are appended as JSON lines so interrupted runs keep what finished.
"""
module IVRBench
using FormulationLab, JuMP, Ipopt, JSON3, LinearAlgebra, Statistics

const PROVENANCE_KEYS = ("_pmd", "_simplification_log", "_merged_from")

"""Read a BMOPF JSON file into the compiler's input dictionary."""
function load_case(path)
    net = FormulationLab._l3f_input(JSON3.read(read(path, String), Dict{String,Any}))
    strip!(x) = x isa AbstractDict ? (foreach(k -> k in PROVENANCE_KEYS ? delete!(x, k) : strip!(x[k]), collect(keys(x))); x) : x
    strip!(net)
end

"""Copy `net`, scale load P/Q by `load_factor` and add priced DER generators.

Every `der_every`-th three-coil load (stable ID order) receives a generator on
the same terminals with P in [0, 2 p_nom], |Q| <= p_max/2. Prices make DER
cheaper than import (0.10 vs 0.25 per kWh), so DER pushes voltages to their
limits as load falls and the OPF has real dispatch freedom.
"""
function instance(net; load_factor=1.0, der_every=5, source_price=0.25, der_price=0.10)
    x = deepcopy(net)
    gens = get!(x, "generator", Dict{String,Any}())
    for (k, id) in enumerate(sort!(collect(keys(get(x, "load", Dict())))))
        d = x["load"][id]
        p = Float64.(d["p_nom"])
        if der_every > 0 && k % der_every == 0 && length(p) == 3 && sum(p) > 0 &&
           get(d, "configuration", "") in ("WYE", "DELTA")
            pmax = 2 .* p
            gens["der_"*id] = Dict{String,Any}("bus" => d["bus"], "terminal_map" => copy(d["terminal_map"]),
                "configuration" => d["configuration"], "p_min" => zeros(3), "p_max" => pmax,
                "q_min" => -pmax ./ 2, "q_max" => pmax ./ 2, "cost" => fill(der_price, 3))
        end
        d["p_nom"] = load_factor .* p
        d["q_nom"] = load_factor .* Float64.(d["q_nom"])
    end
    for s in values(x["voltage_source"])
        s["cost"] = fill(source_price, length(s["terminal_map"]))
    end
    x
end

const COMMON = (objective=:cost, s_base=1e5, transformer_nameplate=:bmopftools)
const SCALED = (transformer_scaling=:nominal, row_scaling=:composed, ground_scaling=:voltage)
const REDUCED = (specialization=:conductor_regions, linear_elimination=:passive_blocks,
                 lifting=:powers, zero_load_elimination=true)

"""Named arms. One factor changes at a time relative to `powers` or `reduced`."""
const ARMS = Dict{String,NamedTuple}(
    "full" => (;),
    "powers" => (lifting=:powers,),
    "powers_dup" => (lifting=:powers,),
    "powers_zero" => (lifting=:powers, zero_load_elimination=true),
    "reduced" => REDUCED,
    "reduced_broad" => merge(REDUCED, (lifting=:bounded_observations,)),
    "reduced_txelim" => merge(REDUCED, (device_elimination=:transformer_currents,)),
    "reduced_scaled" => merge(REDUCED, SCALED),
    # Scaling ablations: which coordinate choice carries the effect?
    "full_scaled" => SCALED,
    "powers_scaled" => merge((lifting=:powers,), SCALED),
    "reduced_tscale" => merge(REDUCED, (transformer_scaling=:nominal,)),
    "reduced_rscale" => merge(REDUCED, (row_scaling=:composed,)),
    "reduced_gscale" => merge(REDUCED, (ground_scaling=:voltage,)),
    "reduced_tr" => merge(REDUCED, (transformer_scaling=:nominal, row_scaling=:composed)),
)
const DEFAULT_ARMS = ["full", "powers", "powers_dup", "powers_zero", "reduced",
                      "reduced_broad", "reduced_txelim", "reduced_scaled"]
options(arm) = IVRNLPOptions(; COMMON..., ARMS[arm]...)

"""Solver configurations. `ipopt` is near-default and is the ranking setting;
`ipopt_strict` reproduces the historical campaign settings for comparison."""
const SOLVERS = Dict{String,NamedTuple}(
    "ipopt" => (print_level=0, max_iter=3000, max_wall_time=600.0),
    "ipopt_strict" => (print_level=0, tol=1e-10, constr_viol_tol=1e-10, acceptable_iter=0,
                       bound_relax_factor=0.0, max_iter=3000, max_wall_time=600.0),
    "madnlp" => (max_iter=3000, max_wall_time=600.0),
    # Mechanism check: larger initial MUMPS pivot tolerance avoids pivot retries.
    "ipopt_pivtol" => (print_level=0, max_iter=3000, max_wall_time=600.0, mumps_pivtol=1e-3),
)

function optimizer(solver)
    solver == "madnlp" || return Ipopt.Optimizer
    isdefined(Main, :MadNLP) || error("load MadNLP before requesting the madnlp solver")
    Main.MadNLP.Optimizer
end

function solver_options(solver, logfile, level)
    base = SOLVERS[solver]
    solver == "madnlp" && return (; base..., print_level=Main.MadNLP.ERROR)
    logfile === nothing && return base
    (; base..., output_file=logfile, file_print_level=level, print_timing_statistics="yes")
end

"""Parse the fields of an Ipopt output file that explain where time goes."""
function parse_ipopt_log(path)
    out = Dict{String,Any}()
    isfile(path) || return out
    text = read(path, String)
    num(rx) = (m = match(rx, text); m === nothing ? nothing : parse(Float64, m.captures[1]))
    for (key, label) in ("nnz_jac_eq" => "Number of nonzeros in equality constraint Jacobian",
                         "nnz_jac_ineq" => "Number of nonzeros in inequality constraint Jacobian",
                         "nnz_hess" => "Number of nonzeros in Lagrangian Hessian",
                         "n_var" => "Total number of variables",
                         "n_eq" => "Total number of equality constraints",
                         "n_ineq" => "Total number of inequality constraints")
        out[key] = num(Regex(label * "\\.*:\\s*(\\d+)"))
    end
    out["ipopt_internal_s"] = num(r"Total seconds in IPOPT \(w/o function evaluations\)\s*=\s*([0-9.]+)")
    out["function_eval_s"] = num(r"Total seconds in NLP function evaluations\s*=\s*([0-9.]+)")
    for key in ("PDSystemSolverTotal", "LinearSystemSymbolicFactorization",
                "LinearSystemFactorization", "LinearSystemBackSolve", "StdAugSystemSolverMultiSolve")
        out[key*"_s"] = num(Regex(key * "\\.*:.*?wall:\\s*([0-9.]+)"))
    end
    factors = [parse(Int, m.captures[1]) for m in eachmatch(r"\(INFO\(9\)\) = (-?\d+)", text)]
    # Negative INFO(9) means millions of entries.
    factors = [f < 0 ? -f * 10^6 : f for f in factors]
    out["factorizations"] = length(factors)
    out["factor_doubles_max"] = isempty(factors) ? nothing : maximum(factors)
    out
end

iterations(model) = try MOI.get(backend(model), MOI.BarrierIterations()) catch; nothing end

"""One build + solve. Returns a row dictionary; never throws."""
function trial(net, arm, solver; logfile=nothing, level=5)
    row = Dict{String,Any}("arm" => arm, "solver" => solver, "success" => false)
    try
        build_s = @elapsed b = build_opf(net, IVRNLP(options(arm)); optimizer=optimizer(solver))
        row["build_s"] = build_s
        row["variables"] = num_variables(b.model)
        r = solve_ivr_nlp_opf(b; solver_options=solver_options(solver, logfile, level))
        row["solve_s"] = solve_time(b.model)
        row["status"] = string(termination_status(b.model))
        row["iterations"] = iterations(b.model)
        row["optimal"] = r.solve.optimal
        if r.solve.optimal
            phys = physical_residuals(net, r)
            row["objective"] = r.objective
            row["physical_passed"] = phys.passed
            row["physical_max"] = Dict(string(k) => v for (k, v) in pairs(phys.maxima))
            row["success"] = phys.passed
        end
        logfile === nothing || merge!(row, parse_ipopt_log(logfile))
    catch err
        err isa InterruptException && rethrow()
        row["error"] = first(sprint(showerror, err), 500)
    end
    row
end

const WARMED = Set{String}()

"""Run every arm × solver on one instance, appending JSON lines to `out`.

Arm order rotates across repetitions so drift does not favour one arm.
"""
function run_instance(out, net, meta; arms=DEFAULT_ARMS, solvers=["ipopt"], reps=5, workdir=mktempdir())
    emit(row) = open(io -> (JSON3.write(io, merge(row, meta)); println(io)), out, "a")
    for solver in solvers
        # Untimed compile warm-up, so no recorded diagnostic includes JIT time.
        solver in WARMED || (trial(net, first(arms), solver); push!(WARMED, solver))
        # Diagnostic solve per arm: also serves as compile warm-up.
        for arm in arms
            log = startswith(solver, "ipopt") ? joinpath(workdir, "diag_$(arm).log") : nothing
            row = trial(net, arm, solver; logfile=log, level=6)
            row["kind"] = "diagnostic"; emit(row)
        end
        for rep in 1:reps
            for arm in circshift(isodd(rep) ? arms : reverse(arms), rep ÷ 2)
                log = startswith(solver, "ipopt") ? joinpath(workdir, "rep.log") : nothing
                row = trial(net, arm, solver; logfile=log, level=5)
                row["kind"] = "timed"; row["rep"] = rep; emit(row)
                log === nothing || rm(log; force=true)
            end
        end
    end
end

end
