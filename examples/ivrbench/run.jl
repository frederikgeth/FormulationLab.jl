# Usage:
#   julia --project=examples/ivrbench examples/ivrbench/run.jl OUT.jsonl CASE.json [CASE.json ...] \
#       [--reps 5] [--factors 1.0,1.5] [--solvers ipopt,madnlp] [--arms full,powers,...] [--der-every 5]
#
# Appends one JSON line per solve to OUT.jsonl. Rerunning appends; delete the
# file to start over. Analyse with analyze.jl.
using LinearAlgebra
const SOLVER_ARG = let i = findfirst(==("--solvers"), ARGS); i === nothing ? "ipopt" : ARGS[i+1] end
occursin("madnlp", SOLVER_ARG) && (using MadNLP)
include(joinpath(@__DIR__, "IVRBench.jl"))
using .IVRBench, JSON3, JuMP, Ipopt

function parse_args(args)
    opts = Dict("reps" => "5", "factors" => "1.0", "solvers" => "ipopt",
                "arms" => join(IVRBench.DEFAULT_ARMS, ","), "der-every" => "5")
    positional = String[]
    i = 1
    while i <= length(args)
        if startswith(args[i], "--")
            opts[args[i][3:end]] = args[i+1]; i += 2
        else
            push!(positional, args[i]); i += 1
        end
    end
    length(positional) >= 2 || error("usage: run.jl OUT.jsonl CASE.json [CASE.json ...] [options]")
    positional[1], positional[2:end], opts
end

function main(args)
    out, cases, opts = parse_args(args)
    BLAS.set_num_threads(1)
    reps = parse(Int, opts["reps"])
    factors = parse.(Float64, split(opts["factors"], ","))
    solvers = String.(split(opts["solvers"], ","))
    arms = String.(split(opts["arms"], ","))
    der_every = parse(Int, opts["der-every"])
    env = Dict("kind" => "environment", "julia" => string(VERSION), "cpu" => Sys.CPU_NAME,
               "ipopt" => string(pkgversion(Ipopt)), "jump" => string(pkgversion(JuMP)),
               "threads" => Threads.nthreads(), "blas_threads" => BLAS.get_num_threads(),
               "solver_settings" => Dict(s => IVRBench.SOLVERS[s] for s in solvers), "args" => args)
    open(io -> (JSON3.write(io, env); println(io)), out, "a")
    for path in cases
        base = IVRBench.load_case(path)
        for factor in factors
            net = IVRBench.instance(base; load_factor=factor, der_every)
            meta = Dict("case" => basename(path), "buses" => length(net["bus"]),
                        "load_factor" => factor, "ders" => length(get(net, "generator", Dict())))
            @info "instance" meta
            IVRBench.run_instance(out, net, meta; arms, solvers, reps)
        end
    end
end

main(ARGS)
