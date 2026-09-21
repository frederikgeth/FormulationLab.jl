# Gated medium/large ENWL comparison of chordal IVRSDP and local BranchFlowSDP.
#
# julia --project=test/integration examples/benchmark_enwl_scalable_sdp.jl \
#   ../BMOPFDraftData/benchmarks/ENWLbenchmark/reduced output.json
include("benchmark_enwl_sdp_ladder.jl")

const SCALABLE_ENWL_CASES = [
    ("network_18_Feeder_9.json", 96),
    ("Network_14_Feeder_1.json", 134),
    ("network_13_Feeder_4.json", 178),
    ("network_9_Feeder_5.json", 244),
]
const SCALABLE_ENWL_BASES = [3e3, 1e4, 3e4]
const SCALABLE_PRIMARY_BASE = 1e4
const SCALABLE_RESIDUAL_LIMIT = 1e-7
const SCALABLE_VARIABLE_LIMIT = 250_000

function _scalable_formulation(kind, s_base)
    if kind == :ivr
        return IVRSDP(; profile=:clarabel, decomposition=:auto, cone=:real,
            objective=:source_import, scale_objective=true, s_base,
            lnc=:lines, port_rlt=true, clique_size=12)
    elseif kind == :branch_flow
        return BranchFlowSDP(; cone=:real, objective=:source_import,
            scale_objective=true, s_base, lnc=:lines, port_rlt=true,
            implied_current_limits=true)
    end
    throw(ArgumentError("unknown formulation: $kind"))
end

function _scalable_sdp_run(net, kind, s_base; time_limit=180.0)
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
    has_primal = has_values(build.model)
    violation = has_primal ? try
        maximum(values(primal_feasibility_report(build.model; atol=0.0)); init=0.0)
    catch
        nothing
    end : nothing
    accepted = status.optimal && isfinite(result.objective) &&
        violation isa Real && violation <= SCALABLE_RESIDUAL_LIMIT
    merge(common, Dict(
        "termination_status" => status.termination_status,
        "raw_status" => raw_status(build.model),
        "primal_status" => status.primal_status,
        "accepted" => accepted,
        "objective_W" => accepted ? result.objective : nothing,
        "candidate_objective_W" => isfinite(result.objective) ? result.objective : nothing,
        "solver_bound_W" => accepted && isfinite(result.solver_objective_bound) ?
            result.solver_objective_bound : nothing,
        "max_scaled_violation" => violation,
        "rank_ratio" => accepted && isfinite(result.rank_ratio) ?
            result.rank_ratio : nothing,
        "solve_seconds" => solve_seconds,
    ))
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

function _scalable_run!(case, save, net, kind, s_base, time_limit)
    key = (string(kind), s_base)
    any(row -> _scalable_key(row) == key, case["runs"]) && return
    row = _scalable_capture(() -> _scalable_sdp_run(net, kind, s_base; time_limit))
    push!(case["runs"], row)
    save()
    println("SDP ", kind, " base=", s_base,
        " status=", get(row, "termination_status", "error"),
        " accepted=", get(row, "accepted", false),
        " residual=", get(row, "max_scaled_violation", nothing))
    flush(stdout)
end

function _scalable_primary_gate(case)
    all(kind -> any(row -> get(row, "formulation", "") == string(kind) &&
        get(row, "s_base_VA", 0.0) == SCALABLE_PRIMARY_BASE &&
        get(row, "accepted", false), case["runs"]), (:ivr, :branch_flow))
end

function _scalable_markdown(data, output)
    markdown = splitext(output)[1] * ".md"
    open(markdown, "w") do io
        println(io, "# Scalable ENWL SDP ladder")
        println(io)
        println(io, "Inputs and reported objectives use SI units; both SDP formulations ",
            "use per-unit coordinates internally. IVRSDP uses its automatic chordal ",
            "profile, while BranchFlowSDP uses component-local moments. Accepted rows ",
            "must terminate `OPTIMAL` and pass a `1e-7` scaled residual gate. This is ",
            "a numerical reporting gate, not a certified lower-bound test; a negative ",
            "NLP−candidate entry exposes reversed numerical ordering.")
        println(io)
        println(io, "| Case | Buses | Formulation | Base (VA) | Status | Accepted | Candidate objective (W) | NLP−candidate (W) | Residual | Build (s) | Solve (s) | Variables | Decomposition | Cliques / order |")
        println(io, "|---|---:|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---|---:|")
        for case in data["cases"], row in get(case, "runs", Any[])
            nlp = get(get(case, "nlp", Dict()), "source_W", nothing)
            objective = get(row, "candidate_objective_W", nothing)
            gap = nlp isa Real && objective isa Real ? nlp - objective : nothing
            clique = get(row, "clique_count", nothing)
            orders = clique isa Real ? string(clique, " / ",
                get(row, "clique_order_min", "—"), "–",
                get(row, "clique_order_max", "—")) : "—"
            println(io, "| `", case["name"], "` | ", get(case, "buses", "—"),
                " | ", get(row, "formulation", "error"), " | ",
                get(row, "s_base_VA", "—"), " | ",
                get(row, "termination_status", "error"), " | ",
                get(row, "accepted", false), " | ",
                _ladder_fmt(objective), " | ", _ladder_fmt(gap), " | ",
                _ladder_fmt(get(row, "max_scaled_violation", nothing)), " | ",
                _ladder_fmt(get(row, "build_seconds", nothing)), " | ",
                _ladder_fmt(get(row, "solve_seconds", nothing)), " | ",
                get(row, "variables", "—"), " | ",
                get(row, "decomposition", "—"), " | ", orders, " |")
        end
        println(io)
        println(io, "Every reached case is evaluated at 3, 10, and 30 kVA. A later ",
            "case is attempted only when both formulations pass the 10 kVA primary ",
            "gate on the preceding case. A skipped case is an experiment-budget ",
            "decision, not an applicability finding. Models above ",
            SCALABLE_VARIABLE_LIMIT, " variables are built and diagnosed but not sent ",
            "to the solver.")
    end
    markdown
end

function run_enwl_scalable_sdp(data_dir, output; time_limit=180.0)
    data = isfile(output) ?
        JSON3.read(read(output, String), Dict{String,Any}) :
        Dict{String,Any}(
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
            "bases_VA" => SCALABLE_ENWL_BASES,
            "primary_base_VA" => SCALABLE_PRIMARY_BASE,
            "acceptance_residual_limit" => SCALABLE_RESIDUAL_LIMIT,
            "model_variable_limit" => SCALABLE_VARIABLE_LIMIT,
            "time_limit_seconds" => time_limit,
            "threads" => 1,
            "cases" => Any[],
        )
    save() = open(io -> JSON3.write(io, finite(data)), output, "w")

    for (index, (filename, expected_buses)) in enumerate(SCALABLE_ENWL_CASES)
        if index > 1 && !_scalable_primary_gate(last(data["cases"]))
            push!(data["cases"], Dict("name" => filename,
                "expected_buses" => expected_buses,
                "stage_status" => "skipped_by_previous_primary_gate",
                "runs" => Any[]))
            save()
            break
        end
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
        case["path"] = abspath(path)
        case["sha256"] = bytes2hex(sha256(read(path)))
        case["normalized_sha256"] = bytes2hex(sha256(JSON3.write(net)))
        case["buses"] = length(net["bus"])
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
        save()
        haskey(case, "nlp") || begin
            case["nlp"] = _capture(() -> nlp_run(net, SCALABLE_PRIMARY_BASE))
            save()
        end
        for kind in (:ivr, :branch_flow)
            _scalable_run!(case, save, net, kind, SCALABLE_PRIMARY_BASE, time_limit)
            GC.gc()
        end
        for s_base in (first(SCALABLE_ENWL_BASES), last(SCALABLE_ENWL_BASES)),
            kind in (:ivr, :branch_flow)
            _scalable_run!(case, save, net, kind, s_base, time_limit)
            GC.gc()
        end
        case["stage_status"] = _scalable_primary_gate(case) ?
            "complete" : "failed_primary_gate"
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
