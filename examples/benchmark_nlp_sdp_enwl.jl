# Optional environment:
# julia --project=test/integration examples/benchmark_nlp_sdp_enwl.jl \
#   ../BMOPFDraftData/benchmarks/ENWLbenchmark/reduced output.json
using FormulationLab, BMOPFTools, JuMP, Ipopt, MosekTools, JSON3, LinearAlgebra, SHA

include("benchmark_nlp_soc.jl")

BLAS.set_num_threads(1)

const SMALL_ENWL_CASES = [
    "network_23_Feeder_3.json", # 5 buses
    "network_13_Feeder_3.json", # 6 buses
    "network_11_Feeder_2.json", # 8 buses
    "network_10_Feeder_2.json", # 10 buses
    "network_5_Feeder_1.json",  # 11 buses
]
const ENWL_S_BASE = 1e4

function _git_revision(path)
    readchomp(`git -C $path rev-parse HEAD`)
end

function _prepare_enwl_case(path)
    net, _, changes, parser_provenance = prepare_case(path)
    reduced = kron_reduce_bmopf(net)
    reduction = deepcopy(reduced["_meta"]["kron_reduction"])
    # The audit records above remain in the result file. Neither solver should
    # receive implementation metadata as an electrical component table.
    clean = panel_clean(reduced)
    pop!(clean, "extras", nothing)
    clean, ENWL_S_BASE, changes, parser_provenance, reduction
end

function _sdp_run(net, s_base, formulation; time_limit=90.0)
    f = if formulation == :ivr
        # Dense reference IVR coordinates avoid making this comparison about a
        # chordal heuristic. Real cones give both SDP formulations the same
        # JuMP-to-Mosek PSD representation.
        IVRSDP(; profile=:reference, cone=:real, scale_objective=true,
                 s_base, objective=:source_import)
    elseif formulation == :branch_flow
        BranchFlowSDP(; cone=:real, scale_objective=true,
                        s_base, objective=:source_import)
    else
        throw(ArgumentError("unknown SDP formulation: $formulation"))
    end

    build_seconds = @elapsed build = build_opf(net, f; optimizer=MosekTools.Optimizer)
    set_silent(build.model)
    set_time_limit_sec(build.model, time_limit)
    set_optimizer_attribute(build.model, "MSK_IPAR_NUM_THREADS", 1)
    solve_seconds = @elapsed result = formulation == :ivr ?
        solve_sdp_opf(build) : solve_branch_flow_sdp(build)
    status = solve_status(result)
    accepted = status.optimal && isfinite(result.objective)
    max_violation = has_values(build.model) ?
        maximum(values(primal_feasibility_report(build.model; atol=0.0)); init=0.0) : nothing
    Dict(
        "formulation" => string(formulation),
        "termination_status" => status.termination_status,
        "primal_status" => status.primal_status,
        "accepted" => accepted,
        "objective_W" => accepted ? result.objective : nothing,
        "solver_bound_W" => accepted && isfinite(result.solver_objective_bound) ?
            result.solver_objective_bound : nothing,
        "rank_ratio" => accepted && isfinite(result.rank_ratio) ? result.rank_ratio : nothing,
        "max_scaled_violation" => max_violation,
        "build_seconds" => build_seconds,
        "solve_seconds" => solve_seconds,
        "variables" => num_variables(build.model),
        "optimizer_profile" => string(get(result.numerical_diagnostics,
                                           :optimizer_profile, :unknown)),
        "lncs" => "off",
    )
end

function _capture(f)
    try
        f()
    catch err
        Dict("error" => sprint(showerror, err), "exception" => string(typeof(err)))
    end
end

function _annotate_comparison!(row)
    nlp = get(get(row, "nlp", Dict()), "source_W", nothing)
    ivr = get(get(row, "ivr", Dict()), "objective_W", nothing)
    bfm = get(get(row, "branch_flow", Dict()), "objective_W", nothing)
    comparison = Dict{String,Any}()
    if nlp isa Real
        for (name, value) in ("ivr" => ivr, "branch_flow" => bfm)
            value isa Real || continue
            gap = nlp - value
            comparison["nlp_minus_$(name)_W"] = gap
            comparison["nlp_minus_$(name)_percent"] = 100 * gap / max(abs(nlp), 1.0)
            comparison["$(name)_lower_than_nlp"] =
                value <= nlp + max(1e-3, 1e-7 * abs(nlp))
        end
    end
    if ivr isa Real && bfm isa Real
        comparison["ivr_minus_branch_flow_W"] = ivr - bfm
        comparison["ivr_minus_branch_flow_percent_of_nlp"] =
            nlp isa Real ? 100 * (ivr - bfm) / max(abs(nlp), 1.0) : nothing
    end
    row["comparison"] = comparison
end

_fmt(x; digits=6) = x isa Real ? string(round(x; digits)) : "—"

function _write_markdown(data, output)
    markdown = splitext(output)[1] * ".md"
    open(markdown, "w") do io
        println(io, "# Small ENWL: Ipopt NLP versus Mosek SDP")
        println(io)
        println(io, "All three models receive the same normalized, Kron-reduced network. ",
            "Ipopt supplies a locally feasible AC point; it does not certify the global optimum. ",
            "The SDP objectives are numerical relaxation values, not rigorous residual-corrected bounds.")
        println(io)
        println(io, "The source ENWL files model the explicit neutral grounding with a finite, very large ",
            "shunt. The shared reduction instead fixes that neutral at ideal ground, so every case is ",
            "reported as `grounded_neutral_projection`, not as an exact reduction of the source file.")
        println(io)
        println(io, "| Case | Buses | Ipopt AC (W) | IVRSDP (W) | BranchFlowSDP (W) | NLP−IVR (W) | NLP−BFM (W) | IVR−BFM (W) |")
        println(io, "|---|---:|---:|---:|---:|---:|---:|---:|")
        for row in data["cases"]
            nlp = get(get(row, "nlp", Dict()), "source_W", nothing)
            ivr = get(get(row, "ivr", Dict()), "objective_W", nothing)
            bfm = get(get(row, "branch_flow", Dict()), "objective_W", nothing)
            cmp = get(row, "comparison", Dict())
            println(io, "| ", row["name"], " | ", get(row, "buses", "—"), " | ",
                _fmt(nlp), " | ", _fmt(ivr), " | ", _fmt(bfm), " | ",
                _fmt(get(cmp, "nlp_minus_ivr_W", nothing)), " | ",
                _fmt(get(cmp, "nlp_minus_branch_flow_W", nothing)), " | ",
                _fmt(get(cmp, "ivr_minus_branch_flow_W", nothing)), " |")
        end
        println(io)
        println(io, "`NLP−SDP ≥ 0` is the expected relaxation ordering when the implemented constraint ",
            "sets agree. `IVR−BFM` directly measures agreement between the two lifted formulations.")
        println(io)
        println(io, "## AC validation")
        println(io)
        for row in data["cases"]
            nlp = get(row, "nlp", Dict())
            check = get(nlp, "solution_check", Dict())
            println(io, "- `", row["name"], "`: Ipopt `", get(nlp, "status", "error"),
                "`; BMOPFTools `", get(check, "verification_status", "not run"),
                "`; maximum JuMP model residual ", _fmt(get(nlp, "max_model_residual", nothing)), ".")
        end
        println(io)
        println(io, "BMOPFTools' checker lists unassessed dimensions in the JSON record. A ",
            "`checks_passed` result therefore means that all implemented independent checks passed; ",
            "it is not a complete second implementation of every OPF equation.")
    end
    markdown
end

function run_enwl_panel(data_dir, output; time_limit=90.0)
    data = Dict{String,Any}(
        "julia" => string(VERSION),
        "ipopt" => string(pkgversion(Ipopt)),
        "mosek_tools" => string(pkgversion(MosekTools)),
        "bmopftools_revision" => _git_revision(dirname(dirname(pathof(BMOPFTools)))),
        "formulationlab_revision" => _git_revision(pwd()),
        "bmopf_draft_data_revision" => _git_revision(abspath(joinpath(data_dir, "..", "..", ".."))),
        "objective" => "source active-power import (W)",
        "s_base_VA" => ENWL_S_BASE,
        "time_limit_seconds" => time_limit,
        "threads" => 1,
        "input_policy" => [
            "remove generators colocated with a voltage source",
            "fix transformer taps and omit control profiles",
            "apply FormulationLab explicit-neutral Kron reduction",
            "use the same fixed 10 kVA power base for all three models",
            "give the identical derived dictionary and per-unit base to all models",
        ],
        "interpretation" => [
            "Ipopt is a local feasible reference, not a global certificate",
            "SDP bounds are numerical and not residual-corrected certificates",
            "grounded_neutral_projection is a declared model change",
        ],
        "cases" => Any[],
    )
    save() = open(io -> JSON3.write(io, finite(data)), output, "w")

    # Warm all execution paths so reported times do not include first-use
    # compilation or Mosek license initialization.
    warm, warm_base, _, _, _ = _prepare_enwl_case(joinpath(data_dir, first(SMALL_ENWL_CASES)))
    nlp_run(warm, warm_base)
    _sdp_run(warm, warm_base, :ivr; time_limit)
    _sdp_run(warm, warm_base, :branch_flow; time_limit)

    for filename in SMALL_ENWL_CASES
        path = joinpath(data_dir, filename)
        row = Dict{String,Any}(
            "name" => filename,
            "path" => abspath(path),
            "sha256" => bytes2hex(sha256(read(path))),
        )
        push!(data["cases"], row)
        save()
        println("START ", filename)
        flush(stdout)
        try
            net, s_base, changes, parser_provenance, reduction = _prepare_enwl_case(path)
            row["buses"] = length(net["bus"])
            row["components"] = Dict(k => length(get(net, k, Dict())) for k in
                ("bus", "line", "load", "generator", "transformer", "switch", "capacitor"))
            row["s_base_VA"] = s_base
            row["normalization_changes"] = changes
            row["parser_provenance"] = parser_provenance
            row["kron_reduction"] = reduction
            row["normalized_sha256"] = bytes2hex(sha256(JSON3.write(net)))
            report = check_branch_flow_sdp_applicability(net)
            row["branch_flow_applicability"] = Dict(
                "status" => string(report.status), "findings" => report.findings)
            save()

            row["nlp"] = _capture(() -> nlp_run(net, s_base))
            save()
            row["ivr"] = _capture(() -> _sdp_run(net, s_base, :ivr; time_limit))
            save()
            row["branch_flow"] = _capture(() ->
                _sdp_run(net, s_base, :branch_flow; time_limit))
            _annotate_comparison!(row)
            save()
            println("DONE ", filename, " NLP=", get(row["nlp"], "status", "error"),
                " IVR=", get(row["ivr"], "termination_status", "error"),
                " BFM=", get(row["branch_flow"], "termination_status", "error"))
        catch err
            row["input_error"] = sprint(showerror, err)
            save()
            println("INPUT ERROR ", filename, ": ", row["input_error"])
        end
        GC.gc()
        flush(stdout)
    end
    markdown = _write_markdown(finite(data), output)
    println("WROTE ", output, " and ", markdown)
    data
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("Usage: julia --project=test/integration " *
        "examples/benchmark_nlp_sdp_enwl.jl ENWL_REDUCED_DIR OUTPUT.json")
    run_enwl_panel(ARGS[1], ARGS[2])
end
