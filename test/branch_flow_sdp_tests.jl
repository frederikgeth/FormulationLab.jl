using Test, FormulationLab, Clarabel, LinearAlgebra, JuMP
include("lindist3flow_fixtures.jl")
isdefined(@__MODULE__, :_sdp_tx_case) || include("sdp_transformer_fixtures.jl")

function _bfm_test_solve(input; solver_options=(verbose=false,), kwargs...)
    solve_branch_flow_sdp(input; solver_options, kwargs...)
end

@testset "Branch-flow affine preprocessing is exact and optional" begin
    net = _l3f_case()
    raw = build_branch_flow_sdp(net;
        options=BranchFlowSDPOptions(objective=:source_import, preprocess=false))
    processed = build_branch_flow_sdp(net;
        options=BranchFlowSDPOptions(objective=:source_import, preprocess=true))
    F = GenericAffExpr{ComplexF64,VariableRef}
    S = MOI.EqualTo{ComplexF64}
    @test num_constraints(raw.model, F, S) > 0
    @test num_constraints(processed.model, F, S) == 0
    @test processed.numerical_diagnostics[:split_complex_equalities] > 0
    raw_result = solve_branch_flow_sdp(raw; solver_options=(verbose=false,))
    processed_result = solve_branch_flow_sdp(processed; solver_options=(verbose=false,))
    @test raw_result.solve.optimal && processed_result.solve.optimal
    @test processed_result.objective ≈ raw_result.objective rtol=1e-7
end

@testset "Branch-flow SDP local moments support delta loads" begin
    net = _l3f_case()
    for bus in values(net["bus"])
        bus["terminal_names"] = ["a", "b"]
        for field in ("v_min", "v_max")
            haskey(bus, field) && (bus[field] = fill(only(bus[field]), 2))
        end
    end
    source = net["voltage_source"]["source"]
    merge!(source, Dict("terminal_map" => ["a", "b"],
        "configuration" => "WYE", "v_magnitude" => [230.0, 230.0],
        "v_angle" => [0.0, pi], "cost" => [1.0, 1.0]))
    line = net["line"]["line"]
    line["terminal_map_from"] = ["a", "b"]
    line["terminal_map_to"] = ["a", "b"]
    merge!(net["linecode"]["lc"], Dict(
        "R_series_2_2" => 0.2, "X_series_2_2" => 0.1))
    load = net["load"]["load"]
    load["terminal_map"] = ["a", "b"]
    load["configuration"] = "DELTA"

    build = build_branch_flow_sdp(net;
        options=BranchFlowSDPOptions(objective=:source_import))
    @test haskey(build.component_blocks, (:load, "load"))
    @test build.numerical_diagnostics[:matrix_kcl_entries] == 6
    result = solve_branch_flow_sdp(build; solver_options=(verbose=false,))
    reference = solve_sdp_opf(net;
        options=SDPOptions(objective=:source_import), solver_options=(verbose=false,))
    @test result.solve.optimal
    @test result.objective ≈ reference.objective rtol=3e-6
    @test result.relaxed_powers[(:load, "load")] ≈ [10_000 + 2_000im] rtol=1e-8
    physical = physical_residuals(net, ACPoint(
        voltage=result.voltage_candidate, currents=result.current_candidate);
        atol=(voltage=1e-4, current=1e-4, power=0.05))
    @test physical.passed
end

@testset "Branch-flow SDP transformer local blocks preserve winding connections" begin
    for kind in ("delta_wye", "wye_delta")
        net = _sdp_tx_case(kind; tap=1.03)
        transformer = net["transformer"][kind]["tx"]
        transformer["r_series"] = 0.1
        transformer["x_series"] = 0.05
        if kind == "delta_wye"
            for (k, terminal) in enumerate(["a", "b", "c"])
                _sdp_zload!(net, terminal, [terminal, "n"], 0.02k - 0.005im)
            end
        else
            for (k, (from, to)) in enumerate([("a", "b"), ("b", "c"), ("c", "a")])
                _sdp_zload!(net, from, [from, to], 0.02k - 0.005im)
            end
        end
        @test is_branch_flow_sdp_applicable(
            check_branch_flow_sdp_applicability(net))
        build = build_branch_flow_sdp(net;
            options=BranchFlowSDPOptions(objective=:source_import))
        @test haskey(build.transformer_blocks, "$kind/tx")
        @test build.numerical_diagnostics[:transformer_count] == 1
        result = solve_branch_flow_sdp(build; solver_options=(verbose=false,))
        reference = solve_sdp_opf(net;
            options=SDPOptions(objective=:source_import), solver_options=(verbose=false,))
        @test result.solve.optimal
        @test result.objective ≈ reference.objective rtol=2e-6
        @test maximum(abs(result.voltage_candidate[key] - reference.voltage_candidate[key])
                      for key in keys(result.voltage_candidate)) < 1e-4
        physical = physical_residuals(net, ACPoint(
            voltage=result.voltage_candidate, currents=result.current_candidate);
            atol=(voltage=1e-3, current=1e-3, power=0.1))
        @test physical.passed
    end
end

@testset "Radial branch-flow SDP: analytical two-bus optimum" begin
    net = _l3f_case(); original = deepcopy(net)
    s = 10_000 + 2_000im; z = 0.2 + 0.1im; vs = 230.0
    a = 2real(z * conj(s)) - vs^2
    w = (-a + sqrt(a^2 - 4abs2(z * s))) / 2
    exact_v = conj((w + z * conj(s)) / vs)
    exact_p = real(s) + real(z) * abs2(s) / w
    for sb in (1e4, 1e6)
        result = _bfm_test_solve(net;
            options=BranchFlowSDPOptions(s_base=sb, objective=:source_import),
            solver_options=(verbose=false, tol_gap_abs=1e-8, tol_feas=1e-9))
        @test result.solve.optimal
        @test result.objective ≈ exact_p rtol=3e-6
        @test result.voltage_candidate[("load", "a")] ≈ exact_v rtol=3e-5
        @test result.rank_ratio < 1e-6
        @test result.relaxed_powers[(:load, "load")] ≈ [s] rtol=1e-9
        physical = physical_residuals(net, ACPoint(
            voltage=result.voltage_candidate, currents=result.current_candidate);
            atol=(voltage=1e-5, current=2e-5, power=1e-3))
        @test physical.passed
        @test !solve_diagnostics(result).physical_feasibility_certified
        @test !solve_diagnostics(result).bound_certified
    end
    @test net == original
end

@testset "Branch-flow SDP preserves input line orientation" begin
    net = _l3f_case()
    forward = _bfm_test_solve(net;
        options=BranchFlowSDPOptions(objective=:source_import))
    line = net["line"]["line"]
    line["bus_from"], line["bus_to"] = line["bus_to"], line["bus_from"]
    line["terminal_map_from"], line["terminal_map_to"] =
        line["terminal_map_to"], line["terminal_map_from"]
    reverse = _bfm_test_solve(net;
        options=BranchFlowSDPOptions(objective=:source_import))
    @test reverse.solve.optimal
    @test reverse.objective ≈ forward.objective rtol=2e-6
    @test reverse.relaxed_powers[(:line_from, "line")] ≈
          forward.relaxed_powers[(:line_to, "line")] rtol=2e-5
    @test reverse.relaxed_powers[(:line_to, "line")] ≈
          forward.relaxed_powers[(:line_from, "line")] rtol=2e-5
    physical = physical_residuals(net, ACPoint(
        voltage=reverse.voltage_candidate, currents=reverse.current_candidate))
    @test physical.passed
end

@testset "Branch-flow SDP matches IVRSDP on an unbalanced coupled feeder" begin
    net = _l3f_case()
    phases = ["a", "b", "c"]
    for bus in values(net["bus"])
        bus["terminal_names"] = copy(phases)
        haskey(bus, "v_min") && (bus["v_min"] = fill(180.0, 3))
        haskey(bus, "v_max") && (bus["v_max"] = fill(250.0, 3))
    end
    source = net["voltage_source"]["source"]
    source["terminal_map"] = copy(phases)
    source["configuration"] = "WYE"
    source["v_magnitude"] = fill(230.0, 3)
    source["v_angle"] = [0.0, -2pi / 3, 2pi / 3]
    source["cost"] = ones(3)
    line = net["line"]["line"]
    line["terminal_map_from"] = copy(phases)
    line["terminal_map_to"] = copy(phases)
    code = net["linecode"]["lc"]
    merge!(code, Dict(
        "R_series_2_2" => 0.22, "X_series_2_2" => 0.11,
        "R_series_3_3" => 0.18, "X_series_3_3" => 0.09,
        "R_series_1_2" => 0.01, "X_series_1_2" => 0.004,
        "R_series_1_3" => 0.008, "X_series_1_3" => 0.003,
        "R_series_2_3" => 0.012, "X_series_2_3" => 0.005))
    load = net["load"]["load"]
    load["terminal_map"] = copy(phases)
    load["configuration"] = "WYE"
    load["p_nom"] = [10_000.0, 7_000.0, 4_000.0]
    load["q_nom"] = [2_000.0, 1_000.0, -500.0]
    bfm = _bfm_test_solve(net;
        options=BranchFlowSDPOptions(objective=:source_import))
    ivr = solve_sdp_opf(net;
        options=SDPOptions(objective=:source_import),
        solver_options=(verbose=false,))
    @test bfm.solve.optimal
    @test ivr.solve.optimal
    @test bfm.objective ≈ ivr.objective rtol=2e-5
    @test [bfm.voltage_candidate[("load", p)] for p in phases] ≈
          [ivr.voltage_candidate[("load", p)] for p in phases] rtol=2e-4
end

@testset "Branch-flow SDP impedance loads, dispatch and limits" begin
    net = _l3f_case()
    load = net["load"]["load"]
    load["model"] = "constant_impedance"; load["v_nom"] = [230.0]
    exact = 230 / (1 + (0.2 + 0.1im) * conj(10_000 + 2_000im) / 230^2)
    result = _bfm_test_solve(net)
    @test result.solve.optimal
    @test result.voltage_candidate[("load", "a")] ≈ exact rtol=3e-5

    net["shunt"] = Dict("sh" => Dict("bus" => "load", "terminal_map" => ["a"],
        "G_1_1" => 0.001, "B_1_1" => -0.0005))
    shunted = _bfm_test_solve(net;
        options=BranchFlowSDPOptions(objective=:source_import))
    shunted_ivr = solve_sdp_opf(net;
        options=SDPOptions(objective=:source_import), solver_options=(verbose=false,))
    @test shunted.solve.optimal
    @test shunted.objective ≈ shunted_ivr.objective rtol=3e-5

    net = _l3f_case(generator=true)
    result = _bfm_test_solve(net;
        options=BranchFlowSDPOptions(objective=:source_import))
    @test result.solve.optimal
    @test real(only(result.relaxed_powers[(:generator, "pv")])) ≈ 15_000 atol=0.02
    @test result.objective < 0

    net = _l3f_case(); net["line"]["line"]["i_max"] = [1.0]
    @test !_bfm_test_solve(net).solve.optimal
end

@testset "Branch-flow SDP applicability and generic API" begin
    net = _l3f_case()
    report = check_branch_flow_sdp_applicability(net)
    @test is_branch_flow_sdp_applicable(report)
    @test formulation_kind(BranchFlowSDP()) == :relaxation
    @test build_opf(net, BranchFlowSDP(); optimizer=nothing) isa BranchFlowSDPBuild
    prepared = prepare_network(net; reduction=:off, warn=false)
    reduced = solve_opf(prepared, BranchFlowSDP(objective=:source_import);
        solver_options=(verbose=false,))
    reconstructed = reconstruct_solution(prepared, reduced; warn=false)
    @test reduced.solve.optimal
    @test reconstructed.point.voltage[("load", "a")] ≈
          reduced.voltage_candidate[("load", "a")]

    transformer = _l3f_case()
    transformer["transformer"] = Dict("single_phase" => Dict("t" => Dict()))
    report = check_branch_flow_sdp_applicability(transformer)
    @test !is_branch_flow_sdp_applicable(report)
    @test_throws BranchFlowSDPInapplicableError build_branch_flow_sdp(transformer)

    delta = _l3f_case()
    delta["load"]["load"]["configuration"] = "DELTA"
    @test_throws BranchFlowSDPInapplicableError build_branch_flow_sdp(delta)

    shunted = _l3f_case()
    shunted["linecode"]["lc"]["B_from_1_1"] = 1e-5
    @test is_branch_flow_sdp_applicable(
        check_branch_flow_sdp_applicability(shunted))
    @test build_branch_flow_sdp(shunted) isa BranchFlowSDPBuild

    meshed = _l3f_case()
    meshed["bus"]["third"] = Dict("terminal_names" => ["a"])
    meshed["line"]["second"] = Dict("bus_from" => "load", "bus_to" => "third",
        "terminal_map_from" => ["a"], "terminal_map_to" => ["a"], "linecode" => "lc")
    meshed["line"]["third"] = Dict("bus_from" => "third", "bus_to" => "source",
        "terminal_map_from" => ["a"], "terminal_map_to" => ["a"], "linecode" => "lc")
    @test is_branch_flow_sdp_applicable(
        check_branch_flow_sdp_applicability(meshed))
    @test build_branch_flow_sdp(meshed).numerical_diagnostics[:cycle_count] == 1
end
