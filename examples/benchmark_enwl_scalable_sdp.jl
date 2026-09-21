# Bounded medium/large ENWL comparison of chordal IVRSDP and local BranchFlowSDP.
#
# julia --project=test/integration examples/benchmark_enwl_scalable_sdp.jl \
#   ../BMOPFDraftData/benchmarks/ENWLbenchmark/reduced output.json
include("benchmark_enwl_sdp_ladder.jl")

const SCALABLE_ENWL_CASES = [
    ("network_18_Feeder_9.json", 96),
    ("Network_14_Feeder_1.json", 134),
    ("network_13_Feeder_4.json", 178),
    ("network_9_Feeder_5.json", 244),
    ("network_15_Feeder_3.json", 302),
    ("network_17_Feeder_1.json", 376),
    ("Network_8_Feeder_2.json", 538),
]
const SCALABLE_ENWL_BASE_FACTORS = [1 / 3, 1.0, 3.0]
const SCALABLE_PRIMARY_REPETITIONS = 3
const SCALABLE_RESIDUAL_LIMIT = 1e-7
const SCALABLE_VARIABLE_LIMIT = 250_000

function _scalable_power_base(net)
    load = sum((sum(abs.(complex.(d["p_nom"], d["q_nom"])))
                for d in values(get(net, "load", Dict()))); init=0.0)
    generation = sum((sum(abs.(d["p_max"]))
                      for d in values(get(net, "generator", Dict()))); init=0.0)
    max(load, generation, 3_000.0) / 3
end

function _scalable_formulation(kind, s_base)
    if kind == :ivr
        return IVRSDP(; profile=:clarabel, decomposition=:auto, cone=:real,
            objective=:source_import, scale_objective=true, s_base,
            lnc=:lines, port_rlt=true, clique_size=12)
    elseif kind == :branch_flow
        return BranchFlowSDP(; cone=:real, objective=:source_import,
            scale_objective=true, s_base, lnc=:lines, port_rlt=true,
            implied_current_limits=true, preprocess=true)
    end
    throw(ArgumentError("unknown formulation: $kind"))
end

function _scalable_validation_dict(report)
    physical = report.physical
    Dict(
        "bound_usable" => report.bound_usable,
        "reasons" => report.reasons,
        "dual_status" => report.dual_status,
        "primal_objective_W" => report.primal_objective,
        "solver_bound_W" => report.solver_bound,
        "primal_dual_gap_W" => report.primal_dual_gap,
        "model_violation" => report.model_violation,
        "model_feasible" => report.model_feasible,
        "constraint_maxima" => report.constraint_maxima,
        "constraint_violations" => report.constraint_violations,
        "feasible_objective_W" => report.feasible_objective,
        "bound_margin_W" => report.bound_margin,
        "bound_ordering_passed" => report.bound_ordering_passed,
        "recovery_feasible" => report.recovery_feasible,
        "recovery_maxima" => physical === nothing ? nothing : physical.maxima,
        "recovery_unassessed" => physical === nothing ? nothing : physical.unassessed,
        "recovery_error" => report.physical_error,
    )
end

function _scalable_sdp_run(net, kind, s_base;
                           feasible_objective=nothing, time_limit=180.0)
    formulation = _scalable_formulation(kind, s_base)
    println("BUILD ", kind, " base=", s_base)
    flush(stdout)
    build_seconds = @elapsed build = build_opf(net, formulation;
        optimizer=MosekTools.Optimizer)
    println("BUILT ", kind, " base=", s_base, " seconds=", build_seconds,
        " variables=", num_variables(build.model))
    flush(stdout)
    diagnostics = build.numerical_diagnostics
    clique_orders = get(diagnostics, :clique_orders, Int[])
    variables = num_variables(build.model)
    common = Dict(
        "formulation" => string(kind),
        "s_base_VA" => s_base,
        "v_base_V" => build.voltage_base,
        "build_seconds" => build_seconds,
        "variables" => variables,
        "constraints" => num_constraints(build.model;
            count_variable_in_set_constraints=false),
        "decomposition" => string(get(diagnostics, :decomposition, :local)),
        "consistency" => string(get(diagnostics, :consistency, :not_applicable)),
        "reduced_dimension" => get(diagnostics, :reduced_dimension, nothing),
        "clique_count" => get(diagnostics, :cliques, nothing),
        "clique_order_min" => isempty(clique_orders) ? nothing : minimum(clique_orders),
        "clique_order_max" => isempty(clique_orders) ? nothing : maximum(clique_orders),
        "electrical_residual" => get(diagnostics, :electrical_residual, nothing),
        "global_voltage_closure" => get(diagnostics, :global_voltage_closure, nothing),
        "max_kcl_support" => get(diagnostics, :max_kcl_support, nothing),
        "split_kcl_rows" => get(diagnostics, :split_kcl_rows, nothing),
        "kcl_auxiliary_coordinates" =>
            get(diagnostics, :kcl_auxiliary_coordinates, nothing),
        "removed_affine_constraints" =>
            get(diagnostics, :removed_affine_constraints, 0),
        "split_complex_equalities" =>
            get(diagnostics, :split_complex_equalities, 0),
    )
    if variables > SCALABLE_VARIABLE_LIMIT
        return merge(common, Dict(
            "termination_status" => "SKIPPED_MODEL_SIZE",
            "raw_status" => "model has $variables variables; experiment limit is $SCALABLE_VARIABLE_LIMIT",
            "primal_status" => "NO_SOLUTION",
            "accepted" => false,
            "objective_W" => nothing,
            "candidate_objective_W" => nothing,
            "solver_bound_W" => nothing,
            "max_scaled_violation" => nothing,
            "rank_ratio" => nothing,
            "solve_seconds" => 0.0,
        ))
    end
    set_silent(build.model)
    set_time_limit_sec(build.model, time_limit)
    set_optimizer_attribute(build.model, "MSK_IPAR_NUM_THREADS", 1)
    set_optimizer_attribute(build.model, "MSK_DPAR_INTPNT_CO_TOL_PFEAS", 1e-9)
    set_optimizer_attribute(build.model, "MSK_DPAR_INTPNT_CO_TOL_DFEAS", 1e-9)
    set_optimizer_attribute(build.model, "MSK_DPAR_INTPNT_CO_TOL_REL_GAP", 1e-9)
    solve_seconds = @elapsed result = kind == :ivr ?
        solve_sdp_opf(build) : solve_branch_flow_sdp(build)
    status = solve_status(result)
    validation = validate_relaxation_solution(build, result;
        feasible_objective, model_atol=SCALABLE_RESIDUAL_LIMIT,
        bound_atol=0.01, bound_rtol=1e-6,
        physical_atol=(voltage=1e-3, current=1e-3, power=0.1))
    audit = _scalable_validation_dict(validation)
    merge(common, audit, Dict(
        "termination_status" => status.termination_status,
        "raw_status" => raw_status(build.model),
        "primal_status" => status.primal_status,
        "accepted" => validation.bound_usable,
        "objective_W" => validation.bound_usable ? validation.solver_bound : nothing,
        "candidate_objective_W" => isfinite(validation.primal_objective) ?
            validation.primal_objective : nothing,
        "max_scaled_violation" => validation.model_violation,
        "rank_ratio" => status.optimal && isfinite(result.rank_ratio) ?
            result.rank_ratio : nothing,
        "solve_seconds" => solve_seconds,
    ))
end

function _scalable_median(values)
    ordered = sort!(Float64[values...])
    n = length(ordered)
    isodd(n) ? ordered[(n + 1) ÷ 2] :
        (ordered[n ÷ 2] + ordered[n ÷ 2 + 1]) / 2
end

function _scalable_repeated(net, kind, s_base;
                            feasible_objective=nothing, repetitions=1,
                            time_limit=180.0)
    repetitions >= 1 || throw(ArgumentError("repetitions must be positive"))
    samples = Any[]
    for repetition in 1:repetitions
        println("  repetition ", repetition, "/", repetitions)
        flush(stdout)
        sample = _scalable_sdp_run(net, kind, s_base;
            feasible_objective, time_limit)
        push!(samples, sample)
        GC.gc()
        get(sample, "termination_status", "") == "SKIPPED_MODEL_SIZE" && break
    end
    structural = ("formulation", "variables", "constraints", "decomposition",
        "reduced_dimension", "clique_count", "clique_order_max")
    for key in structural
        all(get(sample, key, nothing) == get(first(samples), key, nothing)
            for sample in samples) || error("$kind changed $key across repetitions")
    end
    row = copy(first(samples))
    row["repetitions"] = length(samples)
    row["requested_repetitions"] = repetitions
    row["samples"] = samples
    row["build_seconds"] = _scalable_median(s["build_seconds"] for s in samples)
    row["solve_seconds"] = _scalable_median(s["solve_seconds"] for s in samples)
    residuals = Float64[s["max_scaled_violation"] for s in samples
                        if get(s, "max_scaled_violation", nothing) isa Real]
    row["max_scaled_violation"] = isempty(residuals) ? nothing : maximum(residuals)
    row["model_violation"] = row["max_scaled_violation"]
    row["accepted"] = all(get(s, "accepted", false) for s in samples)
    row["bound_usable"] = row["accepted"]
    row["recovery_feasible"] = all(get(s, "recovery_feasible", false)
        for s in samples)
    statuses = unique(String(s["termination_status"]) for s in samples)
    row["termination_status"] = length(statuses) == 1 ? only(statuses) :
        join(statuses, ", ")
    for key in ("primal_objective_W", "solver_bound_W", "candidate_objective_W")
        values = Float64[get(s, key, nothing) for s in samples
                         if get(s, key, nothing) isa Real]
        row[key] = isempty(values) ? nothing : _scalable_median(values)
        row[key * "_span"] = isempty(values) ? nothing : maximum(values) - minimum(values)
    end
    row["objective_W"] = row["accepted"] ? row["solver_bound_W"] : nothing
    row
end

function _scalable_capture(f)
    try
        f()
    catch err
        err isa InterruptException && rethrow()
        Dict("error" => sprint(showerror, err),
             "exception" => string(typeof(err)))
    end
end

_scalable_key(row) = (get(row, "formulation", ""), get(row, "s_base_VA", 0.0))

function _scalable_run!(case, save, net, kind, s_base, time_limit;
                        repetitions=1)
    key = (string(kind), s_base)
    any(row -> _scalable_key(row) == key, case["runs"]) && return
    feasible = get(get(case, "nlp", Dict()), "source_W", nothing)
    row = _scalable_capture(() -> _scalable_repeated(net, kind, s_base;
        feasible_objective=feasible, repetitions, time_limit))
    push!(case["runs"], row)
    save()
    println("SDP ", kind, " base=", s_base,
        " status=", get(row, "termination_status", "error"),
        " accepted=", get(row, "accepted", false),
        " residual=", get(row, "max_scaled_violation", nothing))
    flush(stdout)
end

function _scalable_markdown(data, output)
    markdown = splitext(output)[1] * ".md"
    open(markdown, "w") do io
        println(io, "# Scalable ENWL SDP ladder")
        println(io)
        println(io, "Inputs and reported objectives use SI units; both SDP formulations ",
            "use per-unit coordinates internally. IVRSDP uses its automatic chordal ",
            "profile, while BranchFlowSDP uses component-local moments. A usable bound ",
            "requires optimal termination, a feasible dual status, a finite lower bound, ",
            "original-model residual at most `1e-7`, consistent primal/dual ordering, ",
            "and lower-bound ordering against the feasible Ipopt objective. Ipopt remains ",
            "a local feasible reference, not a global certificate. AC feasibility of the ",
            "recovered rank-one candidate is reported separately.")
        println(io)
        println(io, "| Case | Buses | Formulation | Base (VA) | Reps | Status | Usable bound | Lower bound (W) | NLP−bound (W) | Residual | AC recovery | Build (s) | Solve (s) | Variables | Decomposition | Cliques / order |")
        println(io, "|---|---:|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|")
        for case in data["cases"], row in get(case, "runs", Any[])
            nlp = get(get(case, "nlp", Dict()), "source_W", nothing)
            bound = get(row, "solver_bound_W", nothing)
            gap = nlp isa Real && bound isa Real ? nlp - bound : nothing
            clique = get(row, "clique_count", nothing)
            orders = clique isa Real ? string(clique, " / ",
                get(row, "clique_order_min", "—"), "–",
                get(row, "clique_order_max", "—")) : "—"
            println(io, "| `", case["name"], "` | ", get(case, "buses", "—"),
                " | ", get(row, "formulation", "error"), " | ",
                get(row, "s_base_VA", "—"), " | ",
                get(row, "repetitions", "—"), " | ",
                get(row, "termination_status", "error"), " | ",
                get(row, "accepted", false), " | ",
                _ladder_fmt(bound), " | ", _ladder_fmt(gap), " | ",
                _ladder_fmt(get(row, "max_scaled_violation", nothing)), " | ",
                get(row, "recovery_feasible", false), " | ",
                _ladder_fmt(get(row, "build_seconds", nothing)), " | ",
                _ladder_fmt(get(row, "solve_seconds", nothing)), " | ",
                get(row, "variables", "—"), " | ",
                get(row, "decomposition", "—"), " | ", orders, " |")
        end
        println(io)
        println(io, "Each case uses a data-derived per-phase power base and factors ",
            join(data["base_factors"], ", "), ". The primary-base rows are medians of ",
            data["primary_repetitions"], " fresh builds and solves; sensitivity rows ",
            "run once. A failure does not suppress later cases. Models above ",
            SCALABLE_VARIABLE_LIMIT, " variables are built and diagnosed but not sent ",
            "to the solver. This is an experiment-budget decision, not an ",
            "applicability finding.")
    end
    markdown
end

function run_enwl_scalable_sdp(data_dir, output; time_limit=180.0)
    data = isfile(output) ? begin
        previous = JSON3.read(read(output, String), Dict{String,Any})
        get(previous, "schema_version", 0) == 2 || error(
            "refusing to resume a legacy scalable-SDP artifact; choose a new output path")
        previous
    end :
        Dict{String,Any}(
            "schema_version" => 2,
            "julia" => string(VERSION),
            "ipopt" => string(pkgversion(Ipopt)),
            "mosek" => string(pkgversion(MosekTools.Mosek)),
            "mosek_tools" => string(pkgversion(MosekTools)),
            "formulationlab_revision" => _git_revision(pwd()),
            "bmopftools_revision" => _git_revision(dirname(dirname(pathof(BMOPFTools)))),
            "bmopf_draft_data_revision" =>
                _git_revision(abspath(joinpath(data_dir, "..", "..", ".."))),
            "units" => Dict("input" => "SI", "model" => "per_unit", "results" => "SI"),
            "objective" => "source active-power import (W)",
            "base_policy" => "max(total nominal apparent load, installed active generation, 3000 VA) / 3",
            "base_factors" => SCALABLE_ENWL_BASE_FACTORS,
            "primary_repetitions" => SCALABLE_PRIMARY_REPETITIONS,
            "acceptance_residual_limit" => SCALABLE_RESIDUAL_LIMIT,
            "model_variable_limit" => SCALABLE_VARIABLE_LIMIT,
            "time_limit_seconds" => time_limit,
            "threads" => 1,
            "cases" => Any[],
        )
    save() = open(io -> JSON3.write(io, finite(data)), output, "w")

    # Warm compilation and both solver interfaces on a tiny case before any
    # reported timing. This does not contribute a row to the experiment.
    warm, _, _, _, _ = _prepare_enwl_case(joinpath(data_dir, first(SMALL_ENWL_CASES)))
    warm_base = _scalable_power_base(warm)
    nlp_run(warm, warm_base)
    for kind in (:ivr, :branch_flow)
        _scalable_sdp_run(warm, kind, warm_base; time_limit=min(time_limit, 30.0))
    end

    for (filename, expected_buses) in SCALABLE_ENWL_CASES
        found = findfirst(case -> get(case, "name", "") == filename, data["cases"])
        case = if found === nothing
            value = Dict{String,Any}("name" => filename,
                "expected_buses" => expected_buses, "runs" => Any[],
                "stage_status" => "running")
            push!(data["cases"], value)
            value
        else
            data["cases"][found]
        end
        path = joinpath(data_dir, filename)
        net, _, changes, provenance, reduction = _prepare_enwl_case(path)
        actual_buses = length(net["bus"])
        actual_buses == expected_buses || error(
            "$filename has $actual_buses prepared buses; expected $expected_buses")
        case["path"] = abspath(path)
        case["sha256"] = bytes2hex(sha256(read(path)))
        case["normalized_sha256"] = bytes2hex(sha256(JSON3.write(net)))
        case["buses"] = actual_buses
        case["components"] = Dict(k => length(get(net, k, Dict())) for k in
            ("bus", "line", "load", "generator", "transformer", "switch", "capacitor"))
        incidence = Dict(id => 0 for id in keys(net["bus"]))
        parallel = Dict{Tuple{String,String},Int}()
        for line in values(get(net, "line", Dict()))
            incidence[line["bus_from"]] += 1
            incidence[line["bus_to"]] += 1
            pair = minmax(string(line["bus_from"]), string(line["bus_to"]))
            parallel[pair] = get(parallel, pair, 0) + 1
        end
        case["max_line_incidence"] = maximum(values(incidence); init=0)
        case["max_parallel_lines"] = maximum(values(parallel); init=0)
        case["normalization_changes"] = changes
        case["parser_provenance"] = provenance
        case["kron_reduction"] = reduction
        primary_base = _scalable_power_base(net)
        bases = primary_base .* SCALABLE_ENWL_BASE_FACTORS
        case["primary_base_VA"] = primary_base
        case["bases_VA"] = bases
        save()
        haskey(case, "nlp") || begin
            case["nlp"] = _capture(() -> nlp_run(net, primary_base))
            save()
        end
        for kind in (:ivr, :branch_flow)
            _scalable_run!(case, save, net, kind, primary_base, time_limit;
                repetitions=SCALABLE_PRIMARY_REPETITIONS)
            GC.gc()
        end
        for s_base in (first(bases), last(bases)),
            kind in (:ivr, :branch_flow)
            _scalable_run!(case, save, net, kind, s_base, time_limit)
            GC.gc()
        end
        case["stage_status"] = "complete"
        save()
    end
    markdown = _scalable_markdown(finite(data), output)
    println("WROTE ", output, " and ", markdown)
    data
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("Usage: julia --project=test/integration " *
        "examples/benchmark_enwl_scalable_sdp.jl ENWL_REDUCED_DIR OUTPUT.json")
    run_enwl_scalable_sdp(ARGS[1], ARGS[2])
end
