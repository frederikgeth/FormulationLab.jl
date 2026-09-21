# Focused regression benchmark for line-local BranchFlowSDP LNCs.
#
# julia --project=test/integration examples/benchmark_branch_flow_local_lnc.jl \
#   ../BMOPFDraftData/benchmarks/ENWLbenchmark/reduced output.json
include("benchmark_enwl_sdp_ladder.jl")

const LOCAL_LNC_CASE = "network_18_Feeder_9.json"
const LOCAL_LNC_BASES = [3e3, 1e4, 3e4]

function _local_lnc_markdown(data, output)
    markdown = splitext(output)[1] * ".md"
    rows = data["runs"]
    nlp = get(data["nlp"], "source_W", nothing)
    tolerance = nlp isa Real ? max(0.01, 1e-5 * abs(nlp)) : nothing
    open(markdown, "w") do io
        println(io, "# BranchFlowSDP line-local LNC regression")
        println(io)
        println(io, "The input and objective use SI units. BranchFlowSDP uses per-unit ",
            "coordinates internally. An SDP row is accepted only after an `OPTIMAL` ",
            "termination and a maximum scaled JuMP residual no larger than `1e-7`. ",
            "Ipopt is a locally feasible AC reference, not a global certificate.")
        println(io)
        println(io, "## 10 kVA ablation")
        println(io)
        println(io, "| Configuration | Accepted | Objective (W) | NLP−SDP (W) | Residual | Variables | Constraints | Solve (s) | LNC applied/skipped |")
        println(io, "|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for name in ("baseline", "line_lnc", "all")
            index = findfirst(row -> get(row, "configuration", "") == name &&
                get(row, "s_base_VA", 0.0) == ENWL_LADDER_PRIMARY_BASE, rows)
            index === nothing && continue
            row = rows[index]
            objective = get(row, "objective_W", nothing)
            gap = nlp isa Real && objective isa Real ? nlp - objective : nothing
            println(io, "| ", name, " | ", get(row, "accepted", false), " | ",
                _ladder_fmt(objective), " | ", _ladder_fmt(gap), " | ",
                _ladder_fmt(get(row, "max_scaled_violation", nothing)), " | ",
                get(row, "variables", "—"), " | ", get(row, "constraints", "—"), " | ",
                _ladder_fmt(get(row, "solve_seconds", nothing)), " | ",
                get(row, "lnc_applied", 0), "/", get(row, "lnc_skipped", 0), " |")
        end
        println(io)
        println(io, "## Power-base sensitivity with all strengthening")
        println(io)
        println(io, "| Base (VA) | Accepted | Objective (W) | NLP−SDP (W) | Within ordering tolerance | Residual | Solve (s) |")
        println(io, "|---:|---:|---:|---:|---:|---:|---:|")
        objectives = Float64[]
        for s_base in LOCAL_LNC_BASES
            index = findfirst(row -> get(row, "configuration", "") == "all" &&
                get(row, "s_base_VA", 0.0) == s_base, rows)
            index === nothing && continue
            row = rows[index]
            objective = get(row, "objective_W", nothing)
            objective isa Real && get(row, "accepted", false) && push!(objectives, objective)
            gap = nlp isa Real && objective isa Real ? nlp - objective : nothing
            within = tolerance isa Real && objective isa Real ? objective <= nlp + tolerance : nothing
            println(io, "| ", Int(s_base), " | ", get(row, "accepted", false), " | ",
                _ladder_fmt(objective), " | ", _ladder_fmt(gap), " | ", within, " | ",
                _ladder_fmt(get(row, "max_scaled_violation", nothing)), " | ",
                _ladder_fmt(get(row, "solve_seconds", nothing)), " |")
        end
        println(io)
        span = isempty(objectives) ? nothing : maximum(objectives) - minimum(objectives)
        println(io, "Accepted-objective span: ", _ladder_fmt(span), " W. ",
            "The ordering tolerance is ", _ladder_fmt(tolerance), " W.")
    end
    markdown
end

function run_branch_flow_local_lnc(data_dir, output; time_limit=180.0)
    path = joinpath(data_dir, LOCAL_LNC_CASE)
    net, _, changes, provenance, reduction = _prepare_enwl_case(path)
    data = Dict{String,Any}(
        "julia" => string(VERSION),
        "mosek" => string(pkgversion(MosekTools.Mosek)),
        "mosek_tools" => string(pkgversion(MosekTools)),
        "ipopt" => string(pkgversion(Ipopt)),
        "formulationlab_revision" => _git_revision(pwd()),
        "bmopftools_revision" => _git_revision(dirname(dirname(pathof(BMOPFTools)))),
        "bmopf_draft_data_revision" =>
            _git_revision(abspath(joinpath(data_dir, "..", "..", ".."))),
        "case" => LOCAL_LNC_CASE,
        "path" => abspath(path),
        "sha256" => bytes2hex(sha256(read(path))),
        "normalized_sha256" => bytes2hex(sha256(JSON3.write(net))),
        "buses" => length(net["bus"]),
        "normalization_changes" => changes,
        "parser_provenance" => provenance,
        "kron_reduction" => reduction,
        "units" => Dict("input" => "SI", "model" => "per_unit", "results" => "SI"),
        "objective" => "source active-power import (W)",
        "acceptance_residual_limit" => ENWL_LADDER_RESIDUAL_LIMIT,
        "time_limit_seconds" => time_limit,
        "threads" => 1,
        "nlp" => _capture(() -> nlp_run(net, ENWL_LADDER_PRIMARY_BASE)),
        "runs" => Any[],
    )
    save() = open(io -> JSON3.write(io, finite(data)), output, "w")
    save()

    configs = ENWL_LADDER_CONFIGS[:branch_flow]
    selected = [only(filter(c -> c.name == name, configs)) for
        name in (:baseline, :line_lnc, :all)]
    for config in selected
        push!(data["runs"], _capture(() -> _ladder_sdp_run(net, :branch_flow, config;
            s_base=ENWL_LADDER_PRIMARY_BASE, time_limit)))
        save()
    end
    all_config = last(selected)
    for s_base in (first(LOCAL_LNC_BASES), last(LOCAL_LNC_BASES))
        push!(data["runs"], _capture(() -> _ladder_sdp_run(net, :branch_flow, all_config;
            s_base, time_limit)))
        save()
    end
    markdown = _local_lnc_markdown(finite(data), output)
    println("WROTE ", output, " and ", markdown)
    data
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("Usage: julia --project=test/integration " *
        "examples/benchmark_branch_flow_local_lnc.jl ENWL_REDUCED_DIR OUTPUT.json")
    run_branch_flow_local_lnc(ARGS[1], ARGS[2])
end
