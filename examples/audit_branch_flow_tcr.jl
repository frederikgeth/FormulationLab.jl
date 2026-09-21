# Audit the experimental BranchFlowSDP first-order voltage skeleton against an
# independently solved BMOPFTools/Ipopt AC point.
#
# julia --project=test/integration examples/audit_branch_flow_tcr.jl \
#   ../BMOPFDraftData/benchmarks/ENWLbenchmark/reduced output.json
include("benchmark_enwl_sdp_ladder.jl")

const TCR_AUDIT_CASE = "network_18_Feeder_9.json"

function _tcr_nlp_point(net, s_base)
    ctx = BMOPFTools.build_opf_model(net; optimizer=Ipopt.Optimizer,
        per_unit=true, s_base)
    BMOPFTools.enforce_kcl!(ctx)
    model = BMOPFTools.opf_model(ctx)
    for (key, value) in ("print_level" => 0, "tol" => 1e-8,
                         "constr_viol_tol" => 1e-8,
                         "bound_relax_factor" => 0.0,
                         "max_iter" => 1500, "max_cpu_time" => 90.0)
        set_optimizer_attribute(model, key, value)
    end
    solve_seconds = @elapsed optimize!(model)
    result = BMOPFTools.extract_result(ctx)
    accepted = termination_status(model) in (MOI.LOCALLY_SOLVED, MOI.OPTIMAL)
    accepted || error("Ipopt did not return a locally feasible point")
    voltage = Dict{Tuple{String,String},ComplexF64}()
    for (bus, terminals) in result["bus"], (terminal, entry) in terminals
        voltage[(String(bus), String(terminal))] =
            complex(Float64(entry["vr"]), Float64(entry["vi"]))
    end
    source = sum(sum(terminal["ps"] for terminal in values(source))
                 for source in values(result["voltage_source"]))
    violation = maximum(values(primal_feasibility_report(model; atol=0.0)); init=0.0)
    summary = Dict(
        "termination_status" => string(termination_status(model)),
        "primal_status" => string(primal_status(model)),
        "objective_W" => source,
        "max_model_residual" => violation,
        "solve_seconds" => solve_seconds,
    )
    summary, voltage
end

function _tcr_exact_block_audit(build, voltage)
    rows = Any[]
    minimum_eigenvalue = Inf
    maximum_rank_tail = 0.0
    for label in sort!(collect(keys(build.tcr_voltage_keys)))
        keys = build.tcr_voltage_keys[label]
        u = ComplexF64[voltage[key] / build.voltage_base for key in keys]
        lifted = vcat(1.0 + 0im, u)
        block = lifted * lifted'
        eigenvalues = eigvals(Hermitian(block))
        mineig = minimum(eigenvalues)
        tail = length(eigenvalues) > 1 ? maximum(abs, eigenvalues[1:end-1]) : 0.0
        minimum_eigenvalue = min(minimum_eigenvalue, mineig)
        maximum_rank_tail = max(maximum_rank_tail, tail)
        push!(rows, Dict(
            "block" => label,
            "order" => size(block, 1),
            "minimum_eigenvalue" => mineig,
            "largest_nonleading_abs_eigenvalue" => tail,
        ))
    end
    anchor_mismatch = maximum((abs(voltage[(String(build.network["voltage_source"][id]["bus"]),
                                               String(terminal))] - value)
        for (id, values) in build.source_voltages
        for (terminal, value) in zip(build.network["voltage_source"][id]["terminal_map"], values));
        init=0.0)
    Dict(
        "block_count" => length(rows),
        "minimum_eigenvalue" => minimum_eigenvalue,
        "largest_nonleading_abs_eigenvalue" => maximum_rank_tail,
        "maximum_source_anchor_mismatch_V" => anchor_mismatch,
        "blocks" => rows,
    )
end

function _tcr_fixed_voltage_solve(net, voltage; s_base=1e4,
                                  fix_first_order=true,
                                  fix_second_order=false,
                                  time_limit=180.0)
    formulation = BranchFlowSDP(; cone=:real, objective=:source_import,
        scale_objective=true, s_base, lnc=:off, port_rlt=false,
        implied_current_limits=false, tcr_voltage=true)
    build_seconds = @elapsed build = build_opf(net, formulation;
        optimizer=MosekTools.Optimizer)
    if fix_first_order
        for (key, expression) in build.voltage_first_order
            value = voltage[key] / build.voltage_base
            @constraint(build.model, real(expression) == real(value))
            @constraint(build.model, imag(expression) == imag(value))
        end
    end
    if fix_second_order
        for (bus, moment) in build.voltage_moments
            terms = string.(net["bus"][bus]["terminal_names"])
            values = ComplexF64[voltage[(String(bus), terminal)] /
                                build.voltage_base for terminal in terms]
            for a in eachindex(values), b in a:length(values)
                @constraint(build.model,
                    moment[a, b] == values[a] * conj(values[b]))
            end
        end
    end
    set_silent(build.model)
    set_time_limit_sec(build.model, time_limit)
    set_optimizer_attribute(build.model, "MSK_IPAR_NUM_THREADS", 1)
    solve_seconds = @elapsed result = solve_branch_flow_sdp(build)
    status = solve_status(result)
    has_primal = has_values(build.model)
    violation = has_primal ?
        maximum(values(primal_feasibility_report(build.model; atol=0.0)); init=0.0) :
        nothing
    Dict(
        "fix_first_order" => fix_first_order,
        "fix_second_order" => fix_second_order,
        "termination_status" => status.termination_status,
        "primal_status" => status.primal_status,
        "accepted" => status.optimal && violation isa Real && violation <= 1e-7,
        "objective_W" => status.optimal ? result.objective : nothing,
        "solver_bound_W" => status.optimal ? result.solver_objective_bound : nothing,
        "max_scaled_violation" => violation,
        "build_seconds" => build_seconds,
        "solve_seconds" => solve_seconds,
        "variables" => num_variables(build.model),
        "constraints" => num_constraints(build.model;
            count_variable_in_set_constraints=false),
    )
end

function _tcr_audit_markdown(data, output)
    markdown = splitext(output)[1] * ".md"
    exact = data["exact_lift"]
    open(markdown, "w") do io
        println(io, "# BranchFlowSDP TCR voltage-skeleton audit")
        println(io)
        println(io, "BMOPFTools/Ipopt supplies a locally feasible AC point on the same ",
            "normalized, Kron-reduced input. The exact lift uses `[1;v][1;v]ᴴ` ",
            "for every local TCR block; it tests validity of the new voltage ",
            "constraints, not every pre-existing BranchFlow equation.")
        println(io)
        println(io, "- Ipopt objective: ", _ladder_fmt(data["nlp"]["objective_W"]), " W")
        println(io, "- Ipopt maximum model residual: ",
            _ladder_fmt(data["nlp"]["max_model_residual"]))
        println(io, "- Exact local blocks: ", exact["block_count"])
        println(io, "- Minimum exact-lift eigenvalue: ",
            _ladder_fmt(exact["minimum_eigenvalue"]))
        println(io, "- Maximum source-anchor mismatch: ",
            _ladder_fmt(exact["maximum_source_anchor_mismatch_V"]), " V")
        println(io)
        println(io, "| Fixed quantities | Status | Accepted | Objective (W) | NLP−SDP (W) | Residual |")
        println(io, "|---|---|---:|---:|---:|---:|")
        for row in data["fixed_voltage_solves"]
            objective = get(row, "objective_W", nothing)
            gap = objective isa Real ? data["nlp"]["objective_W"] - objective : nothing
            label = row["fix_second_order"] ? "first and second voltage moments" :
                row["fix_first_order"] ? "first-order voltage" : "none"
            println(io, "| ", label, " | ", row["termination_status"], " | ",
                row["accepted"], " | ", _ladder_fmt(objective), " | ",
                _ladder_fmt(gap), " | ",
                _ladder_fmt(get(row, "max_scaled_violation", nothing)), " |")
        end
        println(io)
        println(io, "A PSD exact lift establishes that the TCR voltage block itself does ",
            "not exclude the Ipopt voltage point. A failure after fixing all voltage ",
            "moments instead points to a mismatch elsewhere in the BranchFlow and ",
            "BMOPFTools component models; a feasible solve with unstable ordering ",
            "points toward conic conditioning or solver accuracy. For a minimization, ",
            "the free model cannot have a higher true optimum than the same model with ",
            "the first-order voltages fixed; a reported reversal is therefore a direct ",
            "numerical monotonicity failure.")
    end
    markdown
end

function run_branch_flow_tcr_audit(data_dir, output; time_limit=180.0)
    path = joinpath(data_dir, TCR_AUDIT_CASE)
    net, _, changes, provenance, reduction = _prepare_enwl_case(path)
    nlp, voltage = _tcr_nlp_point(net, ENWL_LADDER_PRIMARY_BASE)
    audit_build = build_opf(net, BranchFlowSDP(; cone=:real,
        objective=:source_import, s_base=ENWL_LADDER_PRIMARY_BASE,
        implied_current_limits=false, port_rlt=false, tcr_voltage=true);
        optimizer=nothing)
    data = Dict{String,Any}(
        "julia" => string(VERSION),
        "formulationlab_revision" => _git_revision(pwd()),
        "bmopftools_revision" => _git_revision(dirname(dirname(pathof(BMOPFTools)))),
        "bmopf_draft_data_revision" =>
            _git_revision(abspath(joinpath(data_dir, "..", "..", ".."))),
        "case" => TCR_AUDIT_CASE,
        "path" => abspath(path),
        "sha256" => bytes2hex(sha256(read(path))),
        "normalized_sha256" => bytes2hex(sha256(JSON3.write(net))),
        "normalization_changes" => changes,
        "parser_provenance" => provenance,
        "kron_reduction" => reduction,
        "s_base_VA" => ENWL_LADDER_PRIMARY_BASE,
        "units" => Dict("input" => "SI", "model" => "per_unit", "results" => "SI"),
        "nlp" => nlp,
        "exact_lift" => _tcr_exact_block_audit(audit_build, voltage),
        "fixed_voltage_solves" => Any[
            _tcr_fixed_voltage_solve(net, voltage;
                s_base=ENWL_LADDER_PRIMARY_BASE, fix_first_order=false,
                fix_second_order=false, time_limit),
            _tcr_fixed_voltage_solve(net, voltage;
                s_base=ENWL_LADDER_PRIMARY_BASE, fix_second_order=false, time_limit),
            _tcr_fixed_voltage_solve(net, voltage;
                s_base=ENWL_LADDER_PRIMARY_BASE, fix_second_order=true, time_limit),
        ],
    )
    open(io -> JSON3.write(io, finite(data)), output, "w")
    markdown = _tcr_audit_markdown(finite(data), output)
    println("WROTE ", output, " and ", markdown)
    data
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("Usage: julia --project=test/integration " *
        "examples/audit_branch_flow_tcr.jl ENWL_REDUCED_DIR OUTPUT.json")
    run_branch_flow_tcr_audit(ARGS[1], ARGS[2])
end
