# Optional environment:
# julia --project=test/integration examples/benchmark_enwl_sdp_scaling.jl \
#   ../BMOPFDraftData/benchmarks/ENWLbenchmark/reduced output.json
include("benchmark_nlp_sdp_enwl.jl")

const ENWL_SCALING_BASES = [1e3, 3e3, 1e4, 3e4, 1e5]
const ENWL_SCALING_WITNESS = "network_10_Feeder_2.json"

function _scaling_sdp_run(net, formulation; s_base, scale_objective=true,
                          state_scaling=:global, mosek_scaling=:free,
                          time_limit=90.0)
    f = if formulation == :ivr
        IVRSDP(; profile=:reference, cone=:real, objective=:source_import,
                 s_base, scale_objective, state_scaling)
    elseif formulation == :branch_flow
        BranchFlowSDP(; cone=:real, objective=:source_import,
                        s_base, scale_objective)
    else
        throw(ArgumentError("unknown formulation: $formulation"))
    end
    mosek_scaling in (:free, :none) ||
        throw(ArgumentError("Mosek scaling must be :free or :none"))

    build_seconds = @elapsed build = build_opf(net, f; optimizer=MosekTools.Optimizer)
    set_silent(build.model)
    set_time_limit_sec(build.model, time_limit)
    set_optimizer_attribute(build.model, "MSK_IPAR_NUM_THREADS", 1)
    set_optimizer_attribute(build.model, "MSK_IPAR_INTPNT_SCALING",
        mosek_scaling == :free ? MosekTools.Mosek.MSK_SCALING_FREE :
                                 MosekTools.Mosek.MSK_SCALING_NONE)
    solve_seconds = @elapsed result = formulation == :ivr ?
        solve_sdp_opf(build) : solve_branch_flow_sdp(build)
    status = solve_status(result)
    accepted = status.optimal && isfinite(result.objective)
    has_primal = has_values(build.model)
    raw_objective = has_primal ?
        try objective_value(build.model) * build.objective_scale catch; nothing end : nothing
    violation = has_primal ? try
        maximum(values(primal_feasibility_report(build.model; atol=0.0)); init=0.0)
    catch
        nothing
    end : nothing
    vb = build.voltage_base
    diagnostics = result.numerical_diagnostics
    Dict(
        "formulation" => string(formulation),
        "s_base_VA" => s_base,
        "v_base_V" => vb,
        "i_base_A" => s_base / vb,
        "z_base_ohm" => vb^2 / s_base,
        "scale_objective" => scale_objective,
        "objective_divisor" => build.objective_scale,
        "state_scaling" => formulation == :ivr ? string(state_scaling) : "not_applicable",
        "state_scaling_diagnostics" => formulation == :ivr ?
            get(diagnostics, :state_scaling, nothing) : nothing,
        "mosek_scaling" => string(mosek_scaling),
        "termination_status" => status.termination_status,
        "raw_status" => raw_status(build.model),
        "primal_status" => status.primal_status,
        "accepted" => accepted,
        "objective_W" => accepted ? result.objective : nothing,
        "solver_bound_W" => accepted && isfinite(result.solver_objective_bound) ?
            result.solver_objective_bound : nothing,
        "unaccepted_raw_objective_W" => accepted ? nothing : raw_objective,
        "rank_ratio" => accepted && isfinite(result.rank_ratio) ? result.rank_ratio : nothing,
        "max_scaled_violation" => violation,
        "variables" => num_variables(build.model),
        "build_seconds" => build_seconds,
        "solve_seconds" => solve_seconds,
    )
end

function _scaling_summary(rows)
    accepted = [row for row in rows if get(row, "accepted", false)]
    objectives = Float64[row["objective_W"] for row in accepted]
    violations = Float64[row["max_scaled_violation"] for row in accepted
                         if get(row, "max_scaled_violation", nothing) isa Real]
    Dict(
        "runs" => length(rows),
        "optimal_runs" => length(accepted),
        "statuses" => Dict(status => count(row ->
            get(row, "termination_status", "error") == status, rows)
            for status in unique(get(row, "termination_status", "error") for row in rows)),
        "minimum_objective_W" => isempty(objectives) ? nothing : minimum(objectives),
        "maximum_objective_W" => isempty(objectives) ? nothing : maximum(objectives),
        "objective_span_W" => isempty(objectives) ? nothing : maximum(objectives) - minimum(objectives),
        "maximum_scaled_violation" => isempty(violations) ? nothing : maximum(violations),
    )
end

function _finalize_scaling_summary!(data)
    base_rows = [row for case in data["cases"] for row in case["base_sweep"]]
    ivr_base = [row for row in base_rows if row["formulation"] == "ivr"]
    bfm_base = [row for row in base_rows if row["formulation"] == "branch_flow"]
    witness_ivr = [row for row in data["witness"] if row["formulation"] == "ivr"]
    witness_bfm = [row for row in data["witness"] if row["formulation"] == "branch_flow"]
    bfm_3k_scaled = [row for row in witness_bfm if row["s_base_VA"] == 3e3 &&
        row["scale_objective"] && row["accepted"]]
    solver_scaling_delta = length(bfm_3k_scaled) == 2 ?
        abs(bfm_3k_scaled[1]["objective_W"] - bfm_3k_scaled[2]["objective_W"]) : nothing
    ivr_region_pairs = Float64[]
    for row in witness_ivr
        row["state_scaling"] == "global" && row["accepted"] || continue
        match = findfirst(other -> other["state_scaling"] == "voltage_region" &&
            other["s_base_VA"] == row["s_base_VA"] &&
            other["scale_objective"] == row["scale_objective"] &&
            other["mosek_scaling"] == row["mosek_scaling"] && other["accepted"],
            witness_ivr)
        match === nothing || push!(ivr_region_pairs,
            abs(row["objective_W"] - witness_ivr[match]["objective_W"]))
    end
    data["summary"] = Dict(
        "ivr_base_optimal_runs" => count(row -> row["accepted"], ivr_base),
        "ivr_base_total_runs" => length(ivr_base),
        "branch_flow_base_optimal_runs" => count(row -> row["accepted"], bfm_base),
        "branch_flow_base_total_runs" => length(bfm_base),
        "branch_flow_witness_without_objective_scaling_optimal_runs" =>
            count(row -> !row["scale_objective"] && row["accepted"], witness_bfm),
        "branch_flow_witness_without_objective_scaling_total_runs" =>
            count(row -> !row["scale_objective"], witness_bfm),
        "branch_flow_3k_mosek_scaling_objective_difference_W" => solver_scaling_delta,
        "ivr_global_vs_voltage_region_maximum_difference_W" =>
            isempty(ivr_region_pairs) ? nothing : maximum(ivr_region_pairs),
    )
    data
end

function _scaling_markdown(data, output)
    markdown = splitext(output)[1] * ".md"
    open(markdown, "w") do io
        println(io, "# ENWL per-unit scaling study")
        println(io)
        println(io, "BMOPF inputs and published results are in SI units. Each optimization model is ",
            "internally per-unit with `V_base` equal to the largest source-voltage magnitude, ",
            "`I_base = S_base/V_base`, and `Z_base = V_base²/S_base`. Changing `S_base` is an ",
            "algebraically equivalent coordinate change; a stable solve should preserve the SI objective.")
        println(io)
        println(io, "All runs use Mosek, one thread, real PSD embeddings, and the same normalized ",
            "Kron-reduced ENWL dictionaries. Only runs terminating `OPTIMAL` contribute to objective spans.")
        println(io)
        println(io, "## Power-base sweep")
        println(io)
        println(io, "| Case | Formulation | Optimal | Objective interval (W) | Span (W) | Worst accepted residual |")
        println(io, "|---|---|---:|---:|---:|---:|")
        for case in data["cases"], formulation in ("ivr", "branch_flow")
            rows = [row for row in case["base_sweep"] if row["formulation"] == formulation]
            summary = _scaling_summary(rows)
            lo, hi = summary["minimum_objective_W"], summary["maximum_objective_W"]
            interval = lo isa Real ? string(_fmt(lo), " to ", _fmt(hi)) : "—"
            println(io, "| ", case["name"], " | ", formulation, " | ",
                summary["optimal_runs"], "/", summary["runs"], " | ", interval, " | ",
                _fmt(summary["objective_span_W"]), " | ",
                _fmt(summary["maximum_scaled_violation"]), " |")
        end
        println(io)
        println(io, "A large span or changing termination status is numerical scaling sensitivity, ",
            "not a physical change in the feeder or a valid relaxation-strength comparison.")
        println(io)
        println(io, "## Ten-bus scaling controls")
        println(io)
        println(io, "The witness grid separately varies objective normalization, IVR state scaling, ",
            "and Mosek's internal interior-point scaling over 3, 10, and 30 kVA bases.")
        println(io)
        println(io, "| Formulation | Objective scaling | State scaling | Mosek scaling | Optimal | Objective span (W) | Worst accepted residual |")
        println(io, "|---|---|---|---|---:|---:|---:|")
        witness = data["witness"]
        keys = unique((row["formulation"], row["scale_objective"],
                       row["state_scaling"], row["mosek_scaling"]) for row in witness)
        for key in sort!(collect(keys); by=string)
            rows = [row for row in witness if
                (row["formulation"], row["scale_objective"],
                 row["state_scaling"], row["mosek_scaling"]) == key]
            summary = _scaling_summary(rows)
            println(io, "| ", key[1], " | ", key[2], " | ", key[3], " | ", key[4], " | ",
                summary["optimal_runs"], "/", summary["runs"], " | ",
                _fmt(summary["objective_span_W"]), " | ",
                _fmt(summary["maximum_scaled_violation"]), " |")
        end
        println(io)
        println(io, "Failed iterates and their raw objectives remain in the JSON only as diagnostics; ",
            "they are not bounds and are excluded from every interval above.")
        println(io)
        println(io, "## Findings")
        println(io)
        summary = data["summary"]
        println(io, "- IVR is optimal in ", summary["ivr_base_optimal_runs"], "/",
            summary["ivr_base_total_runs"], " power-base runs; BranchFlow is optimal in ",
            summary["branch_flow_base_optimal_runs"], "/",
            summary["branch_flow_base_total_runs"], ".")
        println(io, "- Without objective normalization, BranchFlow is optimal in ",
            summary["branch_flow_witness_without_objective_scaling_optimal_runs"], "/",
            summary["branch_flow_witness_without_objective_scaling_total_runs"],
            " ten-bus witness runs.")
        println(io, "- At 3 kVA with objective normalization enabled, toggling only Mosek's ",
            "interior-point scaling changes two solver-accepted BranchFlow objectives by ",
            _fmt(summary["branch_flow_3k_mosek_scaling_objective_difference_W"]),
            " W. Those runs have scaled residuals near `1e-5`; their `OPTIMAL` labels are ",
            "not sufficient evidence of a stable bound.")
        println(io, "- IVR `global` and `voltage_region` scaling differ by at most ",
            _fmt(summary["ivr_global_vs_voltage_region_maximum_difference_W"]),
            " W here. Each feeder is a single voltage region, so both modes select unit state scales.")
        println(io)
        println(io, "The practical conclusion is that the current IVR formulation is stable across ",
            "the tested per-unit coordinates, while BranchFlow needs additional row/state scaling ",
            "before its Mosek objective should be used quantitatively on the ten-bus witness.")
    end
    markdown
end

function run_enwl_scaling_study(data_dir, output; time_limit=90.0)
    data = Dict{String,Any}(
        "julia" => string(VERSION),
        "mosek" => string(pkgversion(MosekTools.Mosek)),
        "mosek_tools" => string(pkgversion(MosekTools)),
        "formulationlab_revision" => _git_revision(pwd()),
        "bmopf_draft_data_revision" =>
            _git_revision(abspath(joinpath(data_dir, "..", "..", ".."))),
        "units" => Dict("input" => "SI", "model" => "per_unit", "results" => "SI"),
        "voltage_base_policy" => "largest source-voltage magnitude",
        "s_base_values_VA" => ENWL_SCALING_BASES,
        "time_limit_seconds" => time_limit,
        "cases" => Any[],
        "witness_case" => ENWL_SCALING_WITNESS,
        "witness" => Any[],
    )
    save() = open(io -> JSON3.write(io, finite(data)), output, "w")

    warm, _, _, _, _ = _prepare_enwl_case(joinpath(data_dir, first(SMALL_ENWL_CASES)))
    _scaling_sdp_run(warm, :ivr; s_base=1e4, time_limit)
    _scaling_sdp_run(warm, :branch_flow; s_base=1e4, time_limit)

    for filename in SMALL_ENWL_CASES
        net, _, _, _, reduction = _prepare_enwl_case(joinpath(data_dir, filename))
        case = Dict{String,Any}(
            "name" => filename,
            "buses" => length(net["bus"]),
            "kron_reduction_classification" => reduction["classification"],
            "base_sweep" => Any[],
        )
        push!(data["cases"], case)
        for formulation in (:ivr, :branch_flow), s_base in ENWL_SCALING_BASES
            row = _capture(() -> _scaling_sdp_run(net, formulation;
                s_base, scale_objective=true, state_scaling=:global,
                mosek_scaling=:free, time_limit))
            push!(case["base_sweep"], row)
            save()
            println("BASE ", filename, " ", formulation, " ", s_base, " ",
                get(row, "termination_status", "error"))
            flush(stdout)
        end
    end

    witness, _, _, _, _ = _prepare_enwl_case(joinpath(data_dir, ENWL_SCALING_WITNESS))
    for formulation in (:ivr, :branch_flow), s_base in (3e3, 1e4, 3e4),
        scale_objective in (true, false), mosek_scaling in (:free, :none)
        state_modes = formulation == :ivr ? (:global, :voltage_region) : (:global,)
        for state_scaling in state_modes
            row = _capture(() -> _scaling_sdp_run(witness, formulation;
                s_base, scale_objective, state_scaling, mosek_scaling, time_limit))
            push!(data["witness"], row)
            save()
            println("WITNESS ", formulation, " ", s_base, " objective=", scale_objective,
                " state=", state_scaling, " mosek=", mosek_scaling, " ",
                get(row, "termination_status", "error"))
            flush(stdout)
        end
    end
    _finalize_scaling_summary!(data)
    save()
    markdown = _scaling_markdown(finite(data), output)
    println("WROTE ", output, " and ", markdown)
    data
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("Usage: julia --project=test/integration " *
        "examples/benchmark_enwl_sdp_scaling.jl ENWL_REDUCED_DIR OUTPUT.json")
    run_enwl_scaling_study(ARGS[1], ARGS[2])
end
