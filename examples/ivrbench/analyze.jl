# Usage: julia --project=examples/ivrbench examples/ivrbench/analyze.jl RESULTS.jsonl [RESULTS.jsonl ...] > report.md
#
# Produces a Markdown report: noise floor, per-arm time ratios against the
# `powers` control, success rates, Dolan–Moré performance profiles (failures
# count as unsolved), the Ipopt cost decomposition and a fitted cost model.
using JSON3, Statistics, LinearAlgebra, Printf

const CONTROL = "powers"
const TAUS = (1.0, 1.1, 1.25, 1.5, 2.0, 4.0)

load(paths) = [Dict{String,Any}(String(k) => v for (k, v) in JSON3.read(l))
               for p in paths for l in eachline(p) if !isempty(strip(l))]
fmt(x; d=3) = x === nothing || (x isa Real && !isfinite(x)) ? "–" : @sprintf("%.*f", d, x)
gmean(x) = isempty(x) ? NaN : exp(mean(log.(x)))
key(r) = (r["case"], r["load_factor"])

function summarize(rows)
    timed = [r for r in rows if get(r, "kind", "") == "timed"]
    diag = [r for r in rows if get(r, "kind", "") == "diagnostic"]
    cells = Dict{Any,Dict{String,Any}}()
    for r in timed
        c = get!(cells, (r["solver"], key(r), r["arm"]), Dict{String,Any}("times" => Float64[], "ok" => 0, "n" => 0,
                 "iters" => Int[], "obj" => Float64[], "buses" => r["buses"]))
        c["n"] += 1
        if r["success"]
            c["ok"] += 1; push!(c["times"], r["solve_s"]); push!(c["iters"], r["iterations"])
            haskey(r, "objective") && push!(c["obj"], r["objective"])
        end
    end
    # An arm "solves" an instance only if every timed repetition succeeded.
    for c in values(cells)
        c["solved"] = c["ok"] == c["n"] && c["n"] > 0
        c["median"] = c["solved"] ? median(c["times"]) : Inf
        c["iqr"] = c["solved"] && length(c["times"]) > 1 ? quantile(c["times"], 0.75) - quantile(c["times"], 0.25) : NaN
    end
    diagcells = Dict((r["solver"], key(r), r["arm"]) => r for r in diag)
    cells, diagcells
end

solvers(cells) = sort!(unique(k[1] for k in keys(cells)))
instances(cells, s) = sort!(unique(k[2] for k in keys(cells) if k[1] == s); by=x -> (x[2], x[1]))
arms(cells, s) = sort!(unique(k[3] for k in keys(cells) if k[1] == s))

function noise_floor(io, cells)
    println(io, "## Noise floor\n")
    println(io, "`powers_dup` builds the identical model as `powers`. The spread of their median ratio is the smallest arm difference worth interpreting.\n")
    println(io, "| Solver | Instances | Median abs. deviation | 90th pct abs. deviation | Max abs. deviation |")
    println(io, "|---|---:|---:|---:|---:|")
    for s in solvers(cells)
        d = Float64[]
        for i in instances(cells, s)
            a = get(cells, (s, i, CONTROL), nothing); b = get(cells, (s, i, "powers_dup"), nothing)
            a !== nothing && b !== nothing && a["solved"] && b["solved"] && push!(d, abs(b["median"] / a["median"] - 1))
        end
        isempty(d) && continue
        println(io, "| $s | $(length(d)) | $(fmt(100median(d);d=1))% | $(fmt(100quantile(d,0.9);d=1))% | $(fmt(100maximum(d);d=1))% |")
    end
    println(io)
end

function arm_summary(io, cells)
    println(io, "## Arms relative to the `$CONTROL` control\n")
    println(io, "Geometric-mean ratio of median solve time over instances both arms solve (below 1 = faster). Success counts every instance.\n")
    for s in solvers(cells)
        println(io, "### $s\n")
        println(io, "| Arm | Solved | Geo-mean time ratio | Faster >5% | Slower >5% | Median iterations | Geo-mean iteration ratio |")
        println(io, "|---|---:|---:|---:|---:|---:|---:|")
        is = instances(cells, s)
        for arm in arms(cells, s)
            solved = count(i -> haskey(cells, (s, i, arm)) && cells[(s, i, arm)]["solved"], is)
            ratios = Float64[]; iratios = Float64[]; its = Float64[]
            for i in is
                a = get(cells, (s, i, arm), nothing); c = get(cells, (s, i, CONTROL), nothing)
                (a === nothing || !a["solved"]) && continue
                push!(its, median(a["iters"]))
                if c !== nothing && c["solved"]
                    push!(ratios, a["median"] / c["median"])
                    push!(iratios, median(a["iters"]) / max(1, median(c["iters"])))
                end
            end
            println(io, "| `$arm` | $solved/$(length(is)) | $(fmt(gmean(ratios))) | $(count(<(0.95),ratios)) | $(count(>(1.05),ratios)) | $(isempty(its) ? "–" : fmt(median(its);d=0)) | $(fmt(gmean(iratios))) |")
        end
        println(io)
    end
end

function profiles(io, cells)
    println(io, "## Performance profiles\n")
    println(io, "Fraction of instances an arm solves within τ × the best arm's median time (Dolan–Moré). Unsolved instances never count. Instances no arm solves are excluded.\n")
    for s in solvers(cells)
        is = instances(cells, s); as = arms(cells, s)
        best = Dict(i => minimum((haskey(cells, (s, i, a)) ? cells[(s, i, a)]["median"] : Inf) for a in as) for i in is)
        is = [i for i in is if isfinite(best[i])]
        println(io, "### $s ($(length(is)) instances)\n")
        println(io, "| Arm | " * join(("τ=$(t)" for t in TAUS), " | ") * " |")
        println(io, "|---|" * repeat("---:|", length(TAUS)))
        for a in as
            r = [haskey(cells, (s, i, a)) ? cells[(s, i, a)]["median"] / best[i] : Inf for i in is]
            println(io, "| `$a` | " * join((fmt(count(<=(t + 1e-12), r) / length(is); d=2) for t in TAUS), " | ") * " |")
        end
        println(io)
    end
end

function per_instance(io, cells)
    println(io, "## Median solve time per instance (ms)\n")
    for s in solvers(cells)
        as = arms(cells, s)
        println(io, "### $s\n")
        println(io, "| Case | Buses | Load | " * join(("`$a`" for a in as), " | ") * " |")
        println(io, "|---|---:|---:|" * repeat("---:|", length(as)))
        for i in instances(cells, s)
            buses = first(c["buses"] for (k, c) in cells if k[1] == s && k[2] == i)
            vals = [haskey(cells, (s, i, a)) ? (cells[(s, i, a)]["solved"] ? fmt(1000cells[(s, i, a)]["median"]; d=1) :
                    "fail $(cells[(s, i, a)]["n"]-cells[(s, i, a)]["ok"])/$(cells[(s, i, a)]["n"])") : "–" for a in as]
            println(io, "| $(i[1]) | $buses | $(i[2]) | " * join(vals, " | ") * " |")
        end
        println(io)
    end
end

function objectives(io, cells)
    println(io, "## Objective consistency\n")
    println(io, "Largest relative objective spread among solved arms per instance (local optima or loose termination).\n")
    println(io, "| Solver | Instances | Median spread | Max spread | Instances with spread > 1e-4 |")
    println(io, "|---|---:|---:|---:|---:|")
    for s in solvers(cells)
        spreads = Float64[]
        for i in instances(cells, s)
            o = [median(c["obj"]) for (k, c) in cells if k[1] == s && k[2] == i && c["solved"] && !isempty(c["obj"])]
            length(o) > 1 && push!(spreads, (maximum(o) - minimum(o)) / max(abs(minimum(o)), 1e-9))
        end
        isempty(spreads) && continue
        println(io, "| $s | $(length(spreads)) | $(@sprintf("%.1e", median(spreads))) | $(@sprintf("%.1e", maximum(spreads))) | $(count(>(1e-4), spreads)) |")
    end
    println(io)
end

"""Where Ipopt spends time, and how well size × iterations predicts it."""
function cost_model(io, cells, diagcells)
    rows = NamedTuple[]
    for ((s, i, a), c) in cells
        startswith(s, "ipopt") && c["solved"] || continue
        d = get(diagcells, (s, i, a), nothing)
        (d === nothing || get(d, "factor_doubles_max", nothing) === nothing ||
         get(d, "ipopt_internal_s", nothing) === nothing) && continue
        # Diagnostic solves that absorbed JIT compilation misstate the shares.
        get(d, "solve_s", Inf) > 3c["median"] && continue
        fe = something(get(d, "function_eval_s", nothing), NaN); tot = something(get(d, "ipopt_internal_s", nothing), NaN) + fe
        lin = something(get(d, "PDSystemSolverTotal_s", nothing), NaN)
        nnz = sum(something(get(d, k, nothing), 0) for k in ("nnz_jac_eq", "nnz_jac_ineq", "nnz_hess"))
        push!(rows, (; s, a, buses=c["buses"], t=c["median"], it=median(c["iters"]), factor=Float64(d["factor_doubles_max"]),
                       nnz=Float64(nnz), fe_frac=fe / tot, lin_frac=lin / tot, nfac=d["factorizations"], diag_it=d["iterations"]))
    end
    isempty(rows) && return
    println(io, "## Where Ipopt spends time\n")
    println(io, "From the diagnostic solve of each (instance, arm). Shares of Ipopt's own total (internal + function evaluations).\n")
    println(io, "| Statistic | Median | 10th pct | 90th pct |")
    println(io, "|---|---:|---:|---:|")
    for (lab, v) in (("Function-evaluation share", [r.fe_frac for r in rows]),
                     ("Primal-dual system solve share", [r.lin_frac for r in rows]),
                     ("Factorizations per iteration", [r.nfac / max(1, r.diag_it) for r in rows]))
        v = filter(isfinite, v)
        isempty(v) || println(io, "| $lab | $(fmt(median(v))) | $(fmt(quantile(v,0.1))) | $(fmt(quantile(v,0.9))) |")
    end
    println(io)
    # log t = b0 + b1 log(iterations) + b2 log(factor doubles) (+ b3 log nnz)
    y = log.([r.t for r in rows])
    fits = (("iterations only", hcat(ones(length(rows)), log.([r.it for r in rows]))),
            ("factor size only", hcat(ones(length(rows)), log.([r.factor for r in rows]))),
            ("iterations + factor size", hcat(ones(length(rows)), log.([r.it for r in rows]), log.([r.factor for r in rows]))),
            ("factorizations + factor size", hcat(ones(length(rows)), log.([max(1, r.nfac) for r in rows]), log.([r.factor for r in rows]))),
            ("iterations + factor size + derivative nnz", hcat(ones(length(rows)), log.([r.it for r in rows]), log.([r.factor for r in rows]), log.([r.nnz for r in rows]))))
    println(io, "### Cost model\n")
    println(io, "Least squares on log median solve time over $(length(rows)) (instance, arm) cells.\n")
    println(io, "| Predictors | R² | Coefficients (intercept, …) |")
    println(io, "|---|---:|---|")
    for (lab, X) in fits
        b = X \ y; res = y - X * b
        r2 = 1 - sum(abs2, res) / sum(abs2, y .- mean(y))
        println(io, "| $lab | $(fmt(r2)) | $(join(fmt.(b), ", ")) |")
    end
    println(io)
end

function solver_compare(io, cells)
    ss = solvers(cells)
    ("ipopt" in ss && "madnlp" in ss) || return
    println(io, "## MadNLP relative to Ipopt (same models, both MUMPS)\n")
    println(io, "| Arm | Instances | Geo-mean time ratio MadNLP/Ipopt | Geo-mean iteration ratio |")
    println(io, "|---|---:|---:|---:|")
    for a in arms(cells, "ipopt")
        r = Float64[]; it = Float64[]
        for i in instances(cells, "ipopt")
            x = get(cells, ("ipopt", i, a), nothing); y = get(cells, ("madnlp", i, a), nothing)
            if x !== nothing && y !== nothing && x["solved"] && y["solved"]
                push!(r, y["median"] / x["median"]); push!(it, median(y["iters"]) / max(1, median(x["iters"])))
            end
        end
        isempty(r) || println(io, "| `$a` | $(length(r)) | $(fmt(gmean(r))) | $(fmt(gmean(it))) |")
    end
    println(io)
end

function main(paths)
    rows = load(paths)
    cells, diagcells = summarize(rows)
    io = stdout
    println(io, "# IVR benchmark report\n")
    println(io, "Sources: " * join(basename.(paths), ", ") * ". Times are optimizer-call wall time; build excluded.\n")
    noise_floor(io, cells)
    arm_summary(io, cells)
    profiles(io, cells)
    solver_compare(io, cells)
    cost_model(io, cells, diagcells)
    objectives(io, cells)
    per_instance(io, cells)
end

main(ARGS)
