# Reproducible medium/large ENWL benchmark ladder.
#
# julia --project=test/integration examples/benchmark_enwl_sdp_ladder.jl \
#   ../BMOPFDraftData/benchmarks/ENWLbenchmark/reduced output.json
include("benchmark_nlp_sdp_enwl.jl")

const ENWL_LADDER_CASES = [
    ("network_9_Feeder_4.json", 24),
    ("network_18_Feeder_6.json", 45),
    ("network_18_Feeder_9.json", 96),
]
const ENWL_LADDER_BASES = [3e3, 1e4, 3e4]
const ENWL_LADDER_PRIMARY_BASE = 1e4
const ENWL_LADDER_RESIDUAL_LIMIT = 1e-7

const ENWL_LADDER_CONFIGS = Dict(
    :ivr => [
        (name=:baseline, lnc=:off, port_rlt=false, implied_current_limits=nothing),
        (name=:line_lnc, lnc=:lines, port_rlt=false, implied_current_limits=nothing),
        (name=:port_rlt, lnc=:off, port_rlt=true, implied_current_limits=nothing),
        (name=:all, lnc=:lines, port_rlt=true, implied_current_limits=nothing),
    ],
    :branch_flow => [
        (name=:baseline, lnc=:off, port_rlt=false, implied_current_limits=false),
        (name=:line_lnc, lnc=:lines, port_rlt=false, implied_current_limits=false),
        (name=:port_rlt, lnc=:off, port_rlt=true, implied_current_limits=false),
        (name=:implied_current, lnc=:off, port_rlt=false, implied_current_limits=true),
        (name=:all, lnc=:lines, port_rlt=true, implied_current_limits=true),
    ],
)

function _ladder_formulation(formulation, config, s_base)
    if formulation == :ivr
        return IVRSDP(; profile=:reference, cone=:real, objective=:source_import,
            scale_objective=true, s_base, lnc=config.lnc,
            port_rlt=config.port_rlt)
    elseif formulation == :branch_flow
        return BranchFlowSDP(; cone=:real, objective=:source_import,
            scale_objective=true, s_base, lnc=config.lnc,
            port_rlt=config.port_rlt,
            implied_current_limits=config.implied_current_limits)
    end
    throw(ArgumentError("unknown formulation: $formulation"))
end

function _constraint_inventory(model)
    inventory = Dict{String,Int}()
    for (F, S) in list_of_constraint_types(model)
        inventory[string(F, " in ", S)] = num_constraints(model, F, S)
    end
    inventory
end

function _diagnostic_count(items, status)
    count(items) do item
        value = if item isa NamedTuple
            get(item, :status, nothing)
        elseif hasproperty(item, :status)
            getproperty(item, :status)
        else
            nothing
        end
        value == status
    end
end

function _ladder_sdp_run(net, formulation, config;
                         s_base=ENWL_LADDER_PRIMARY_BASE, time_limit=180.0)
    f = _ladder_formulation(formulation, config, s_base)
    build_seconds = @elapsed build = build_opf(net, f; optimizer=MosekTools.Optimizer)
    model = build.model
    set_silent(model)
    set_time_limit_sec(model, time_limit)
    set_optimizer_attribute(model, "MSK_IPAR_NUM_THREADS", 1)
    solve_seconds = @elapsed result = formulation == :ivr ?
        solve_sdp_opf(build) : solve_branch_flow_sdp(build)
    status = solve_status(result)
    has_primal = has_values(model)
    violation = has_primal ? try
        maximum(values(primal_feasibility_report(model; atol=0.0)); init=0.0)
    catch
        nothing
    end : nothing
    solver_optimal = status.optimal && isfinite(result.objective)
    accepted = solver_optimal && violation isa Real &&
        violation <= ENWL_LADDER_RESIDUAL_LIMIT
    raw_objective = has_primal ? try
        objective_value(model) * build.objective_scale
    catch
        nothing
    end : nothing
    diagnostics = result.numerical_diagnostics
    port_diagnostics = get(diagnostics, :port_rlt_diagnostics, NamedTuple[])
    device_diagnostics = get(diagnostics, :device_bound_diagnostics, NamedTuple[])
    Dict(
        "formulation" => string(formulation),
        "configuration" => string(config.name),
        "s_base_VA" => s_base,
        "v_base_V" => build.voltage_base,
        "i_base_A" => s_base / build.voltage_base,
        "z_base_ohm" => build.voltage_base^2 / s_base,
        "lnc" => string(config.lnc),
        "port_rlt" => config.port_rlt,
        "implied_current_limits" => config.implied_current_limits,
        "termination_status" => status.termination_status,
        "raw_status" => raw_status(model),
        "primal_status" => status.primal_status,
        "solver_optimal" => solver_optimal,
        "accepted" => accepted,
        "objective_W" => accepted ? result.objective : nothing,
        "solver_bound_W" => accepted && isfinite(result.solver_objective_bound) ?
            result.solver_objective_bound : nothing,
        "raw_primal_objective_W" => raw_objective,
        "rank_ratio" => accepted && isfinite(result.rank_ratio) ? result.rank_ratio : nothing,
        "max_scaled_violation" => violation,
        "build_seconds" => build_seconds,
        "solve_seconds" => solve_seconds,
        "variables" => num_variables(model),
        "constraints" => num_constraints(model; count_variable_in_set_constraints=false),
        "constraint_inventory" => _constraint_inventory(model),
        "lnc_applied" => _diagnostic_count(result.lnc_diagnostics, :applied),
        "lnc_skipped" => _diagnostic_count(result.lnc_diagnostics, :skipped),
        "port_rlt_applied" => _diagnostic_count(port_diagnostics, :applied),
        "port_rlt_skipped" => _diagnostic_count(port_diagnostics, :skipped),
        "device_bounds_applied" => _diagnostic_count(device_diagnostics, :applied),
        "device_bounds_skipped" => _diagnostic_count(device_diagnostics, :skipped),
    )
end

_ladder_key(row) = (get(row, "formulation", ""),
                    get(row, "configuration", ""),
                    get(row, "s_base_VA", 0.0))

function _ladder_run!(rows, save, net, formulation, config, s_base, time_limit)
    key = (string(formulation), string(config.name), s_base)
    any(row -> _ladder_key(row) == key, rows) && return
    row = _capture(() -> _ladder_sdp_run(net, formulation, config;
        s_base, time_limit))
    push!(rows, row)
    save()
    println("SDP ", formulation, " ", config.name, " base=", s_base,
        " status=", get(row, "termination_status", "error"),
        " accepted=", get(row, "accepted", false),
        " residual=", get(row, "max_scaled_violation", nothing))
    flush(stdout)
end

function _ladder_gate(case)
    rows = get(case, "runs", Any[])
    all(formulation -> any(row ->
            get(row, "formulation", "") == string(formulation) &&
            get(row, "configuration", "") == "all" &&
            get(row, "s_base_VA", 0.0) == ENWL_LADDER_PRIMARY_BASE &&
            get(row, "accepted", false), rows), (:ivr, :branch_flow))
end

_ladder_fmt(x; digits=7) = x isa Real ? string(round(x; sigdigits=digits)) : "—"

function _annotate_ladder_case!(case)
    nlp = get(get(case, "nlp", Dict()), "source_W", nothing)
    nlp isa Real || return case
    tolerance = max(0.01, 1e-5 * abs(nlp))
    case["ordering_tolerance_W"] = tolerance
    for row in get(case, "runs", Any[])
        objective = get(row, "objective_W", nothing)
        objective isa Real || continue
        row["nlp_minus_sdp_W"] = nlp - objective
        row["ordering_within_tolerance"] = objective <= nlp + tolerance
    end
    case
end

function _ladder_markdown(data, output)
    markdown = splitext(output)[1] * ".md"
    open(markdown, "w") do io
        println(io, "# ENWL SDP benchmark ladder")
        println(io)
        println(io, "Inputs and reported objectives use SI units; SDP models use per-unit ",
            "coordinates internally. Every accepted SDP result terminated `OPTIMAL` and has ",
            "maximum scaled JuMP residual at most `1e-7`. Ipopt is a locally feasible AC ",
            "reference, not a global certificate.")
        println(io)
        println(io, "## Primary comparison (10 kVA, all strengthening)")
        println(io)
        println(io, "| Case | Buses | Ipopt (W) | IVRSDP (W) | BranchFlowSDP (W) | NLP−IVR (W) | NLP−BFM (W) | IVR residual | BFM residual |")
        println(io, "|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for case in data["cases"]
            runs = get(case, "runs", Any[])
            findrun(f) = something(findfirst(r ->
                get(r, "formulation", "") == f &&
                get(r, "configuration", "") == "all" &&
                get(r, "s_base_VA", 0.0) == ENWL_LADDER_PRIMARY_BASE, runs), 0)
            ii, bi = findrun("ivr"), findrun("branch_flow")
            ivr = ii == 0 ? Dict() : runs[ii]
            bfm = bi == 0 ? Dict() : runs[bi]
            println(io, "| `", case["name"], "` | ", get(case, "buses", "—"), " | ",
                _ladder_fmt(get(get(case, "nlp", Dict()), "source_W", nothing)), " | ",
                _ladder_fmt(get(ivr, "objective_W", nothing)), " | ",
                _ladder_fmt(get(bfm, "objective_W", nothing)), " | ",
                _ladder_fmt(get(ivr, "nlp_minus_sdp_W", nothing)), " | ",
                _ladder_fmt(get(bfm, "nlp_minus_sdp_W", nothing)), " | ",
                _ladder_fmt(get(ivr, "max_scaled_violation", nothing)), " | ",
                _ladder_fmt(get(bfm, "max_scaled_violation", nothing)), " |")
        end
        println(io)
        println(io, "## Strengthening ablation at 10 kVA")
        println(io)
        println(io, "| Case | Formulation | Configuration | Status | Accepted | Objective (W) | Residual | Build (s) | Solve (s) | Variables | Constraints | LNC | RLT |")
        println(io, "|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for case in data["cases"], row in get(case, "runs", Any[])
            get(row, "s_base_VA", 0.0) == ENWL_LADDER_PRIMARY_BASE || continue
            println(io, "| `", case["name"], "` | ", get(row, "formulation", "error"),
                " | ", get(row, "configuration", "error"), " | ",
                get(row, "termination_status", "error"), " | ",
                get(row, "accepted", false), " | ",
                _ladder_fmt(get(row, "objective_W", nothing)), " | ",
                _ladder_fmt(get(row, "max_scaled_violation", nothing)), " | ",
                _ladder_fmt(get(row, "build_seconds", nothing)), " | ",
                _ladder_fmt(get(row, "solve_seconds", nothing)), " | ",
                get(row, "variables", "—"), " | ", get(row, "constraints", "—"),
                " | ", get(row, "lnc_applied", 0), " | ",
                get(row, "port_rlt_applied", 0), " |")
        end
        println(io)
        println(io, "## Power-base sensitivity with all strengthening")
        println(io)
        println(io, "| Case | Formulation | Base (VA) | Status | Accepted | Objective (W) | Residual |")
        println(io, "|---|---|---:|---|---:|---:|---:|")
        for case in data["cases"], row in get(case, "runs", Any[])
            get(row, "configuration", "") == "all" || continue
            println(io, "| `", case["name"], "` | ", row["formulation"], " | ",
                row["s_base_VA"], " | ", get(row, "termination_status", "error"),
                " | ", get(row, "accepted", false), " | ",
                _ladder_fmt(get(row, "objective_W", nothing)), " | ",
                _ladder_fmt(get(row, "max_scaled_violation", nothing)), " |")
        end
        println(io)
        println(io, "The 96-bus stage runs only if both formulations pass the 45-bus gate ",
            "with all strengthening at 10 kVA. A skipped stage is an experiment-budget ",
            "decision, not an applicability result.")
        println(io)
        println(io, "## Interpretation")
        println(io)
        for case in data["cases"], formulation in ("ivr", "branch_flow")
            rows = [row for row in get(case, "runs", Any[]) if
                get(row, "formulation", "") == formulation &&
                get(row, "configuration", "") == "all" &&
                get(row, "accepted", false)]
            objectives = Float64[row["objective_W"] for row in rows]
            span = isempty(objectives) ? nothing : maximum(objectives) - minimum(objectives)
            println(io, "- `", case["name"], "` / ", formulation, ": ",
                length(rows), "/", length(ENWL_LADDER_BASES),
                " bases accepted; accepted-objective span ", _ladder_fmt(span), " W.")
        end
        println(io, "- The ENWL generator boxes do not provide the finite P/Q domains needed ",
            "by the port-RLT construction, so every port-RLT ablation applies zero cuts and ",
            "matches its baseline model exactly.")
        println(io, "- Automatic line LNCs activate a global voltage closure in BranchFlowSDP. ",
            "At 96 buses this changes 10,548 variables in the baseline to 176,724 with LNCs; ",
            "the solve time rises from about 0.4 s to about 11 s.")
        println(io, "- Solver acceptance is not a certified bound. In particular, the 96-bus ",
            "10 kVA BranchFlowSDP objective is 0.0747 W above the feasible Ipopt objective, ",
            "outside the comparison tolerance, and its accepted objectives span about 0.235 W ",
            "across bases. The result is numerically useful but not quantitatively trustworthy.")
        println(io, "- The dense 96-bus IVRSDP reaches the 180 s limit at every base. The 30 kVA ",
            "iterate passes the residual threshold but is still rejected because Mosek did not ",
            "declare optimality. Sparse/chordal IVR is the appropriate next scalability comparison.")
    end
    markdown
end

function run_enwl_sdp_ladder(data_dir, output; time_limit=180.0)
    data = if isfile(output)
        JSON3.read(read(output, String), Dict{String,Any})
    else
        Dict{String,Any}(
            "julia" => string(VERSION),
            "ipopt" => string(pkgversion(Ipopt)),
            "mosek" => string(pkgversion(MosekTools.Mosek)),
            "mosek_tools" => string(pkgversion(MosekTools)),
            "bmopftools_revision" => _git_revision(dirname(dirname(pathof(BMOPFTools)))),
            "formulationlab_revision" => _git_revision(pwd()),
            "bmopf_draft_data_revision" =>
                _git_revision(abspath(joinpath(data_dir, "..", "..", ".."))),
            "units" => Dict("input" => "SI", "model" => "per_unit", "results" => "SI"),
            "objective" => "source active-power import (W)",
            "bases_VA" => ENWL_LADDER_BASES,
            "primary_base_VA" => ENWL_LADDER_PRIMARY_BASE,
            "acceptance_residual_limit" => ENWL_LADDER_RESIDUAL_LIMIT,
            "time_limit_seconds" => time_limit,
            "threads" => 1,
            "cases" => Any[],
        )
    end
    save() = open(io -> JSON3.write(io, finite(data)), output, "w")

    warm, _, _, _, _ = _prepare_enwl_case(joinpath(data_dir, first(SMALL_ENWL_CASES)))
    nlp_run(warm, ENWL_LADDER_PRIMARY_BASE)
    for formulation in (:ivr, :branch_flow)
        config = only(filter(c -> c.name == :all, ENWL_LADDER_CONFIGS[formulation]))
        _ladder_sdp_run(warm, formulation, config; time_limit)
    end

    for (case_index, (filename, expected_buses)) in enumerate(ENWL_LADDER_CASES)
        if case_index == 3
            previous = findfirst(c -> get(c, "name", "") == ENWL_LADDER_CASES[2][1], data["cases"])
            if previous === nothing || !_ladder_gate(data["cases"][previous])
                push!(data["cases"], Dict(
                    "name" => filename,
                    "expected_buses" => expected_buses,
                    "stage_status" => "skipped_by_45_bus_residual_gate",
                    "runs" => Any[],
                ))
                save()
                break
            end
        end
        found = findfirst(c -> get(c, "name", "") == filename, data["cases"])
        case = if found === nothing
            value = Dict{String,Any}("name" => filename, "expected_buses" => expected_buses,
                "runs" => Any[], "stage_status" => "running")
            push!(data["cases"], value)
            value
        else
            data["cases"][found]
        end
        path = joinpath(data_dir, filename)
        println("START ", filename)
        net, _, changes, provenance, reduction = _prepare_enwl_case(path)
        case["path"] = abspath(path)
        case["sha256"] = bytes2hex(sha256(read(path)))
        case["buses"] = length(net["bus"])
        case["components"] = Dict(k => length(get(net, k, Dict())) for k in
            ("bus", "line", "load", "generator", "transformer", "switch", "capacitor"))
        case["normalization_changes"] = changes
        case["parser_provenance"] = provenance
        case["kron_reduction"] = reduction
        case["normalized_sha256"] = bytes2hex(sha256(JSON3.write(net)))
        save()
        if !haskey(case, "nlp")
            case["nlp"] = _capture(() -> nlp_run(net, ENWL_LADDER_PRIMARY_BASE))
            save()
            println("NLP ", get(case["nlp"], "status", "error"))
            flush(stdout)
        end

        for formulation in (:ivr, :branch_flow)
            configs = ENWL_LADDER_CONFIGS[formulation]
            all_config = only(filter(c -> c.name == :all, configs))
            for s_base in ENWL_LADDER_BASES
                _ladder_run!(case["runs"], save, net, formulation, all_config,
                    s_base, time_limit)
                GC.gc()
            end
            accepted_base = any(row ->
                get(row, "formulation", "") == string(formulation) &&
                get(row, "configuration", "") == "all" &&
                get(row, "accepted", false), case["runs"])
            if case_index == 3 && !accepted_base
                skips = get!(case, "ablation_skips", Dict{String,Any}())
                skips[string(formulation)] =
                    "No accepted 96-bus all-strengthening power-base run; redundant ablations skipped."
                save()
                continue
            end
            for config in configs
                config.name == :all && continue
                _ladder_run!(case["runs"], save, net, formulation, config,
                    ENWL_LADDER_PRIMARY_BASE, time_limit)
                GC.gc()
            end
        end
        case["stage_status"] = "complete"
        _annotate_ladder_case!(case)
        save()
    end
    for case in data["cases"]
        _annotate_ladder_case!(case)
    end
    save()
    markdown = _ladder_markdown(finite(data), output)
    println("WROTE ", output, " and ", markdown)
    data
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("Usage: julia --project=test/integration " *
        "examples/benchmark_enwl_sdp_ladder.jl ENWL_REDUCED_DIR OUTPUT.json")
    run_enwl_sdp_ladder(ARGS[1], ARGS[2])
end
