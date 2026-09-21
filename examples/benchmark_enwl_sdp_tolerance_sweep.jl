# Numerical tolerance sensitivity for the largest ENWL bound-diagnostic case.
#
# julia --project=test/integration \
#   examples/benchmark_enwl_sdp_tolerance_sweep.jl ENWL_REDUCED_DIR OUTPUT.json
include("benchmark_enwl_sdp_bound_diagnostics.jl")

const SDP_TOLERANCE_CASE = ("Network_8_Feeder_2.json", 538)
const SDP_TOLERANCE_LEVELS = [1e-8, 1e-10, 1e-12]
const SDP_TOLERANCE_CONFIGS = [
    first(BOUND_DIAGNOSTIC_CONFIGS),
    BOUND_DIAGNOSTIC_CONFIGS[2],
]

function _sdp_tolerance_run(net, kind, config, s_base, feasible_objective,
                            reference_voltage, tolerance; time_limit=180.0)
    formulation = _bound_diagnostic_formulation(kind, config, s_base)
    build_seconds = @elapsed build = build_opf(net, formulation;
        optimizer=MosekTools.Optimizer)
    model = build.model
    set_silent(model)
    set_time_limit_sec(model, time_limit)
    set_optimizer_attribute(model, "MSK_IPAR_NUM_THREADS", 1)
    for key in ("MSK_DPAR_INTPNT_CO_TOL_PFEAS",
                "MSK_DPAR_INTPNT_CO_TOL_DFEAS",
                "MSK_DPAR_INTPNT_CO_TOL_REL_GAP")
        set_optimizer_attribute(model, key, tolerance)
    end
    solve_seconds = @elapsed result = kind == :ivr ?
        solve_sdp_opf(build) : solve_branch_flow_sdp(build)
    report = validate_relaxation_solution(build, result;
        feasible_objective, model_atol=SCALABLE_RESIDUAL_LIMIT,
        bound_atol=0.01, bound_rtol=1e-6,
        physical_atol=(voltage=1e-3, current=1e-3, power=0.1))
    merge(_scalable_validation_dict(report), Dict(
        "formulation" => string(kind),
        "configuration" => string(config.name),
        "requested_tolerance" => tolerance,
        "termination_status" => string(termination_status(model)),
        "raw_status" => raw_status(model),
        "primal_status" => string(primal_status(model)),
        "accepted" => report.bound_usable,
        "build_seconds" => build_seconds,
        "solve_seconds" => solve_seconds,
        "variables" => num_variables(model),
        "constraints" => num_constraints(model;
            count_variable_in_set_constraints=false),
        "lnc_reference_audit" =>
            _bound_diagnostic_lnc_audit(build, reference_voltage),
    ))
end

_sdp_tolerance_key(row) = (get(row, "formulation", ""),
    get(row, "configuration", ""), get(row, "requested_tolerance", nothing))

function _sdp_tolerance_markdown(data, output)
    path = splitext(output)[1] * ".md"
    open(path, "w") do io
        println(io, "# ENWL SDP tolerance sensitivity")
        println(io)
        println(io, "The Ipopt point satisfies every automatically derived line LNC. ",
            "The table tests whether tighter requested Mosek conic tolerances make ",
            "the reported dual objective a reliable lower bound.")
        println(io)
        usable = count(row -> get(row, "accepted", false), data["runs"])
        println(io, "Only `", usable, "` of `", length(data["runs"]),
            "` runs passed the complete usability gate. Requested tolerances did ",
            "not produce monotone achieved dual feasibility or termination status; ",
            "they must be treated as solver requests rather than certificates.")
        println(io)
        println(io, "| Formulation | LNC | Requested tolerance | Status | Usable | NLP−bound (W) | Model residual | Mosek PFEAS | Mosek DFEAS | Solve (s) |")
        println(io, "|---|---|---:|---|---:|---:|---:|---:|---:|---:|")
        for row in data["runs"]
            metrics = get(row, "solver_metrics", Dict())
            println(io, "| ", row["formulation"], " | ", row["configuration"],
                " | ", _ladder_fmt(row["requested_tolerance"]), " | ",
                row["termination_status"], " | ", row["accepted"], " | ",
                _ladder_fmt(row["bound_margin_W"]), " | ",
                _ladder_fmt(row["model_violation"]), " | ",
                _ladder_fmt(get(metrics, "interior_point_primal_feasibility", nothing)),
                " | ",
                _ladder_fmt(get(metrics, "interior_point_dual_feasibility", nothing)),
                " | ", _ladder_fmt(row["solve_seconds"]), " |")
        end
    end
    path
end

function run_enwl_sdp_tolerance_sweep(data_dir, output; time_limit=180.0)
    filename, expected_buses = SDP_TOLERANCE_CASE
    net, _, changes, provenance, reduction =
        _prepare_enwl_case(joinpath(data_dir, filename))
    length(net["bus"]) == expected_buses || error("unexpected bus count")
    s_base = _scalable_power_base(net)
    nlp = nlp_run(net, s_base)
    reference_voltage = _bound_diagnostic_reference_voltage(net, s_base)
    data = isfile(output) ?
        JSON3.read(read(output, String), Dict{String,Any}) :
        Dict{String,Any}(
            "schema_version" => 1,
            "case" => filename,
            "buses" => expected_buses,
            "s_base_VA" => s_base,
            "nlp" => nlp,
            "normalization_changes" => changes,
            "parser_provenance" => provenance,
            "kron_reduction" => reduction,
            "formulationlab_revision" => _git_revision(pwd()),
            "time_limit_seconds" => time_limit,
            "threads" => 1,
            "runs" => Any[],
        )
    save() = open(io -> JSON3.write(io, finite(data)), output, "w")
    for kind in (:ivr, :branch_flow), config in SDP_TOLERANCE_CONFIGS,
        tolerance in SDP_TOLERANCE_LEVELS
        key = (string(kind), string(config.name), tolerance)
        any(row -> _sdp_tolerance_key(row) == key, data["runs"]) && continue
        println("RUN ", kind, " ", config.name, " tolerance=", tolerance)
        flush(stdout)
        row = _scalable_capture(() -> _sdp_tolerance_run(net, kind, config,
            s_base, nlp["source_W"], reference_voltage, tolerance; time_limit))
        push!(data["runs"], row)
        save()
        GC.gc()
    end
    markdown = _sdp_tolerance_markdown(finite(data), output)
    println("WROTE ", output, " and ", markdown)
    data
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("Usage: julia --project=test/integration " *
        "examples/benchmark_enwl_sdp_tolerance_sweep.jl ENWL_REDUCED_DIR OUTPUT.json")
    run_enwl_sdp_tolerance_sweep(ARGS[1], ARGS[2])
end
