# External baseline: BMOPFTools' independent IVR-EN implementation (PMD
# IVRENPowerModel convention) against FormulationLab arms on the same instance,
# same Ipopt settings, same process.
#
#   julia --project=examples/ivrbench examples/ivrbench/baseline.jl OUT.jsonl CASE.json [...] [--reps 3] [--factors 1.0]
using LinearAlgebra
include(joinpath(@__DIR__, "IVRBench.jl"))
using .IVRBench, BMOPFTools, Ipopt, JuMP, JSON3

const ARMS = ["full", "powers", "reduced_scaled"]

function bmopf_trial(net)
    row = Dict{String,Any}("arm" => "bmopftools", "solver" => "ipopt", "success" => false)
    try
        res = BMOPFTools.solve_opf(net; optimizer=Ipopt.Optimizer, per_unit=true, s_base=IVRBench.COMMON.s_base,
                                   solver_options=collect(pairs(IVRBench.SOLVERS["ipopt"])))
        prof = res["opt_profile"]
        row["solve_s"] = prof["solve_time_s"]; row["iterations"] = prof["barrier_iterations"]
        row["variables"] = prof["n_variables"]
        row["status"] = string(get(res, "termination_status", get(res, "status", "")))
        row["objective"] = get(res, "objective", nothing)
        row["success"] = occursin("LOCALLY_SOLVED", row["status"]) || occursin("OPTIMAL", row["status"])
    catch err
        err isa InterruptException && rethrow()
        row["error"] = first(sprint(showerror, err), 500)
    end
    row
end

function main(args)
    pos = [a for (k, a) in enumerate(args) if !startswith(a, "--") && (k == 1 || !startswith(args[k-1], "--"))]
    opt(name, default) = (i = findfirst(==("--" * name), args); i === nothing ? default : args[i+1])
    out, cases = pos[1], pos[2:end]
    reps = parse(Int, opt("reps", "3")); factors = parse.(Float64, split(opt("factors", "1.0"), ","))
    BLAS.set_num_threads(1)
    emit(row) = open(io -> (JSON3.write(io, row); println(io)), out, "a")
    for path in cases, factor in factors
        net = IVRBench.instance(IVRBench.load_case(path); load_factor=factor)
        meta = Dict("case" => basename(path), "buses" => length(net["bus"]), "load_factor" => factor)
        bmopf_trial(net); foreach(a -> IVRBench.trial(net, a, "ipopt"), ARMS)   # warm-up
        for rep in 1:reps
            r = bmopf_trial(net); r["kind"] = "timed"; r["rep"] = rep; emit(merge(r, meta))
            for a in ARMS
                r = IVRBench.trial(net, a, "ipopt"); r["kind"] = "timed"; r["rep"] = rep; emit(merge(r, meta))
            end
        end
    end
end

main(ARGS)
