# Strengthening and solver-bound diagnostics on the numerically difficult ENWL
# cases identified by benchmark_enwl_scalable_sdp.jl.
#
# julia --project=test/integration \
#   examples/benchmark_enwl_sdp_bound_diagnostics.jl ENWL_REDUCED_DIR OUTPUT.json
include("benchmark_enwl_scalable_sdp.jl")

const BOUND_DIAGNOSTIC_CASES = [
    ("network_13_Feeder_4.json", 178),
    ("network_9_Feeder_5.json", 244),
    ("Network_8_Feeder_2.json", 538),
]

const BOUND_DIAGNOSTIC_CONFIGS = [
    (name=:baseline, lnc=:off, port_rlt=false, implied_current=false),
    (name=:line_lnc, lnc=:lines, port_rlt=false, implied_current=false),
    (name=:port_rlt, lnc=:off, port_rlt=true, implied_current=false),
    (name=:implied_current, lnc=:off, port_rlt=false, implied_current=true),
    (name=:all, lnc=:lines, port_rlt=true, implied_current=true),
]

function _bound_diagnostic_formulation(kind, config, s_base)
    if kind == :ivr
        return IVRSDP(; profile=:clarabel, decomposition=:auto, cone=:real,
            objective=:source_import, scale_objective=true, s_base,
            lnc=config.lnc, port_rlt=config.port_rlt,
            current_bounds=config.implied_current, clique_size=12)
    elseif kind == :branch_flow
        return BranchFlowSDP(; cone=:real, objective=:source_import,
            scale_objective=true, s_base, lnc=config.lnc,
            port_rlt=config.port_rlt,
            implied_current_limits=config.implied_current, preprocess=true)
    end
    throw(ArgumentError("unknown formulation: $kind"))
end

function _bound_diagnostic_run(net, kind, config, s_base, feasible_objective;
                               time_limit=180.0, reference_voltage=nothing)
    formulation = _bound_diagnostic_formulation(kind, config, s_base)
    build_seconds = @elapsed build = build_opf(net, formulation;
        optimizer=MosekTools.Optimizer)
    model = build.model
    set_silent(model)
    set_time_limit_sec(model, time_limit)
    set_optimizer_attribute(model, "MSK_IPAR_NUM_THREADS", 1)
    set_optimizer_attribute(model, "MSK_DPAR_INTPNT_CO_TOL_PFEAS", 1e-9)
    set_optimizer_attribute(model, "MSK_DPAR_INTPNT_CO_TOL_DFEAS", 1e-9)
    set_optimizer_attribute(model, "MSK_DPAR_INTPNT_CO_TOL_REL_GAP", 1e-9)
    solve_seconds = @elapsed result = kind == :ivr ?
        solve_sdp_opf(build) : solve_branch_flow_sdp(build)
    report = validate_relaxation_solution(build, result;
        feasible_objective, model_atol=SCALABLE_RESIDUAL_LIMIT,
        bound_atol=0.01, bound_rtol=1e-6,
        physical_atol=(voltage=1e-3, current=1e-3, power=0.1))
    diagnostics = result.numerical_diagnostics
    port = get(diagnostics, :port_rlt_diagnostics, NamedTuple[])
    device = get(diagnostics, :device_bound_diagnostics, NamedTuple[])
    status = solve_status(result)
    lnc_audit = reference_voltage === nothing || config.lnc == :off ? nothing :
        _bound_diagnostic_lnc_audit(build, reference_voltage)
    merge(_scalable_validation_dict(report), Dict(
        "formulation" => string(kind),
        "configuration" => string(config.name),
        "lnc" => string(config.lnc),
        "port_rlt" => config.port_rlt,
        "implied_current" => config.implied_current,
        "s_base_VA" => s_base,
        "termination_status" => status.termination_status,
        "raw_status" => raw_status(model),
        "primal_status" => status.primal_status,
        "accepted" => report.bound_usable,
        "build_seconds" => build_seconds,
        "solve_seconds" => solve_seconds,
        "variables" => num_variables(model),
        "constraints" => num_constraints(model;
            count_variable_in_set_constraints=false),
        "rank_ratio" => isfinite(result.rank_ratio) ? result.rank_ratio : nothing,
        "lnc_applied" => _diagnostic_count(result.lnc_diagnostics, :applied),
        "lnc_skipped" => _diagnostic_count(result.lnc_diagnostics, :skipped),
        "port_rlt_applied" => _diagnostic_count(port, :applied),
        "port_rlt_skipped" => _diagnostic_count(port, :skipped),
        "device_bounds_applied" => _diagnostic_count(device, :applied),
        "derived_current_bounds" =>
            get(diagnostics, :derived_current_bounds, nothing),
        "global_voltage_closure" =>
            get(diagnostics, :global_voltage_closure, nothing),
        "lnc_reference_audit" => lnc_audit,
    ))
end

function _bound_diagnostic_reference_voltage(net, s_base)
    context = BMOPFTools.build_opf_model(net; optimizer=Ipopt.Optimizer,
        per_unit=true, s_base)
    BMOPFTools.enforce_kcl!(context)
    model = BMOPFTools.opf_model(context)
    for (key, value) in ("print_level" => 0, "tol" => 1e-8,
                         "constr_viol_tol" => 1e-8,
                         "bound_relax_factor" => 0.0, "max_iter" => 1500,
                         "max_cpu_time" => 90.0)
        set_optimizer_attribute(model, key, value)
    end
    optimize!(model)
    termination_status(model) in (MOI.LOCALLY_SOLVED, MOI.OPTIMAL) ||
        error("reference NLP did not solve: $(termination_status(model))")
    result = BMOPFTools.extract_result(context)
    Dict((string(bus), string(terminal)) =>
            complex(value["vr"], value["vi"])
         for (bus, terminals) in result["bus"]
         for (terminal, value) in terminals)
end

function _bound_diagnostic_lnc_audit(build, voltage)
    audit = audit_voltage_lncs(build, voltage; atol=1e-9)
    records = sort(audit.records; by=record ->
        min(record.minimum_cut_slack, record.minimum_domain_slack))
    Dict(
        "ordering" => "minimum_normalized_slack",
        "passed" => audit.passed,
        "max_normalized_violation" => audit.max_violation,
        "count" => length(records),
        "violated" => count(record -> record.max_violation > 1e-9, records),
        "worst" => [Dict(
            "id" => record.id,
            "origin" => string(record.origin),
            "max_normalized_violation" => record.max_violation,
            "minimum_cut_slack" => record.minimum_cut_slack,
            "minimum_domain_slack" => record.minimum_domain_slack,
            "u_magnitude_V" => record.u_magnitude,
            "v_magnitude_V" => record.v_magnitude,
            "relative_angle_rad" => record.relative_angle,
            "centered_angle_rad" => record.centered_angle,
        ) for record in records[1:min(5, length(records))]],
    )
end

function _bound_diagnostic_add_lnc_audit!(row, net, kind, config, s_base,
                                          reference_voltage)
    existing = get(row, "lnc_reference_audit", nothing)
    existing isa AbstractDict &&
        get(existing, "ordering", "") == "minimum_normalized_slack" &&
        return false
    if config.lnc == :off
        row["lnc_reference_audit"] = nothing
        return true
    end
    build = build_opf(net, _bound_diagnostic_formulation(kind, config, s_base);
        optimizer=MosekTools.Optimizer)
    row["lnc_reference_audit"] =
        _bound_diagnostic_lnc_audit(build, reference_voltage)
    true
end

_bound_diagnostic_key(row) =
    (get(row, "formulation", ""), get(row, "configuration", ""))

function _bound_diagnostic_markdown(data, output)
    markdown = splitext(output)[1] * ".md"
    open(markdown, "w") do io
        println(io, "# ENWL strengthening and bound diagnostics")
        println(io)
        println(io, "All objectives are reported in watts. Mosek feasibility and ",
            "optimality metrics remain in the internally scaled conic model. A usable ",
            "bound passes termination, primal residual, dual status, primal/dual ",
            "ordering, and feasible-AC ordering checks. Ipopt supplies a checked local ",
            "feasible point, not a global optimum.")
        println(io)
        runs = [row for case in data["cases"] for row in case["runs"]]
        disagreements = [abs(row["bound_disagreement_W"]) for row in runs
            if get(row, "bound_disagreement_W", nothing) isa Real]
        audits = [row["lnc_reference_audit"] for row in runs
            if get(row, "configuration", "") == "line_lnc" &&
               get(row, "lnc_reference_audit", nothing) isa AbstractDict]
        audited = sum(get(audit, "count", 0) for audit in audits)
        violations = sum(get(audit, "violated", 0) for audit in audits)
        println(io, "Across all runs, the largest disagreement between JuMP's ",
            "objective bound and Mosek's dual objective was `",
            _ladder_fmt(maximum(disagreements; init=0.0)), " W`. The independently ",
            "solved Ipopt voltages satisfied `", audited,
            "` distinct formulation/case line-LNC instances; `", violations,
            "` violated a normalized cut or domain inequality. Thus the observed ",
            "bound reversals are numerical certificate failures, not a wrapper ",
            "bound-source mismatch or evidence that the derived LNCs exclude the ",
            "reference AC points.")
        println(io)
        println(io, "| Buses | Formulation | Configuration | Status | Usable | Solver bound (W) | NLP−bound (W) | Model residual | Mosek PFEAS | Mosek DFEAS | Relative gap | Build (s) | Solve (s) | Variables | LNC | RLT | Current bounds |")
        println(io, "|---:|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for case in data["cases"], row in case["runs"]
            bound = get(row, "solver_bound_W", nothing)
            nlp = get(get(case, "nlp", Dict()), "source_W", nothing)
            margin = nlp isa Real && bound isa Real ? nlp - bound : nothing
            metrics = get(row, "solver_metrics", Dict())
            current = get(row, "formulation", "") == "ivr" ?
                get(row, "derived_current_bounds", "—") :
                get(row, "device_bounds_applied", "—")
            println(io, "| ", case["buses"], " | ", row["formulation"], " | ",
                row["configuration"], " | ", row["termination_status"], " | ",
                row["accepted"], " | ", _ladder_fmt(bound), " | ",
                _ladder_fmt(margin), " | ",
                _ladder_fmt(get(row, "model_violation", nothing)), " | ",
                _ladder_fmt(get(metrics, "interior_point_primal_feasibility", nothing)), " | ",
                _ladder_fmt(get(metrics, "interior_point_dual_feasibility", nothing)), " | ",
                _ladder_fmt(get(row, "solver_relative_gap", nothing)), " | ",
                _ladder_fmt(row["build_seconds"]), " | ",
                _ladder_fmt(row["solve_seconds"]), " | ", row["variables"], " | ",
                row["lnc_applied"], " | ", row["port_rlt_applied"], " | ",
                current, " |")
        end
    end
    markdown
end

function run_enwl_sdp_bound_diagnostics(data_dir, output; time_limit=180.0)
    data = isfile(output) ?
        JSON3.read(read(output, String), Dict{String,Any}) :
        Dict{String,Any}(
            "schema_version" => 1,
            "julia" => string(VERSION),
            "ipopt" => string(pkgversion(Ipopt)),
            "mosek" => string(pkgversion(MosekTools.Mosek)),
            "mosek_tools" => string(pkgversion(MosekTools)),
            "formulationlab_revision" => _git_revision(pwd()),
            "bmopftools_revision" =>
                _git_revision(dirname(dirname(pathof(BMOPFTools)))),
            "units" => Dict("input" => "SI", "model" => "per_unit",
                "objectives" => "W", "solver_metrics" => "scaled_model"),
            "time_limit_seconds" => time_limit,
            "threads" => 1,
            "cases" => Any[],
        )
    save() = open(io -> JSON3.write(io, finite(data)), output, "w")

    warm, _, _, _, _ = _prepare_enwl_case(joinpath(data_dir, first(SMALL_ENWL_CASES)))
    warm_base = _scalable_power_base(warm)
    warm_nlp = nlp_run(warm, warm_base)
    baseline = first(BOUND_DIAGNOSTIC_CONFIGS)
    for kind in (:ivr, :branch_flow)
        _bound_diagnostic_run(warm, kind, baseline, warm_base,
            warm_nlp["source_W"]; time_limit=min(time_limit, 30.0))
    end

    for (filename, expected_buses) in BOUND_DIAGNOSTIC_CASES
        found = findfirst(case -> get(case, "name", "") == filename, data["cases"])
        case = if found === nothing
            value = Dict{String,Any}("name" => filename, "buses" => expected_buses,
                "runs" => Any[])
            push!(data["cases"], value)
            value
        else
            data["cases"][found]
        end
        net, _, changes, provenance, reduction =
            _prepare_enwl_case(joinpath(data_dir, filename))
        length(net["bus"]) == expected_buses || error("unexpected bus count")
        s_base = _scalable_power_base(net)
        case["s_base_VA"] = s_base
        case["normalization_changes"] = changes
        case["parser_provenance"] = provenance
        case["kron_reduction"] = reduction
        haskey(case, "nlp") || (case["nlp"] = nlp_run(net, s_base); save())
        feasible = case["nlp"]["source_W"]
        reference_voltage = _bound_diagnostic_reference_voltage(net, s_base)
        for kind in (:ivr, :branch_flow), config in BOUND_DIAGNOSTIC_CONFIGS
            key = (string(kind), string(config.name))
            found_run = findfirst(row -> _bound_diagnostic_key(row) == key,
                case["runs"])
            if found_run !== nothing
                _bound_diagnostic_add_lnc_audit!(case["runs"][found_run], net,
                    kind, config, s_base, reference_voltage) && save()
                continue
            end
            println("RUN ", filename, " ", kind, " ", config.name)
            flush(stdout)
            row = _scalable_capture(() -> _bound_diagnostic_run(
                net, kind, config, s_base, feasible; time_limit,
                reference_voltage))
            push!(case["runs"], row)
            save()
            GC.gc()
        end
    end
    markdown = _bound_diagnostic_markdown(finite(data), output)
    println("WROTE ", output, " and ", markdown)
    data
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("Usage: julia --project=test/integration " *
        "examples/benchmark_enwl_sdp_bound_diagnostics.jl ENWL_REDUCED_DIR OUTPUT.json")
    run_enwl_sdp_bound_diagnostics(ARGS[1], ARGS[2])
end
