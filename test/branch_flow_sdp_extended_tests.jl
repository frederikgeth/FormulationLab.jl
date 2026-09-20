using Test, FormulationLab, Clarabel, LinearAlgebra, JuMP
isdefined(@__MODULE__, :_L3F_FIXTURES_LOADED) || include("lindist3flow_fixtures.jl")
isdefined(@__MODULE__, :_sdp_tx_case) || include("sdp_transformer_fixtures.jl")

function _bfm_three_phase_delta_case(; model="constant_power")
    net = _l3f_case()
    phases = ["a", "b", "c"]
    for bus in values(net["bus"])
        bus["terminal_names"] = copy(phases)
        haskey(bus, "v_min") && (bus["v_min"] = fill(180.0, 3))
        haskey(bus, "v_max") && (bus["v_max"] = fill(250.0, 3))
    end
    net["terminal_conventions"] = Dict("phase" => copy(phases), "neutral" => String[])
    source = net["voltage_source"]["source"]
    merge!(source, Dict("terminal_map" => copy(phases), "configuration" => "WYE",
        "v_magnitude" => fill(230.0, 3),
        "v_angle" => [0.0, -2pi / 3, 2pi / 3], "cost" => ones(3)))
    line = net["line"]["line"]
    line["terminal_map_from"] = copy(phases)
    line["terminal_map_to"] = copy(phases)
    merge!(net["linecode"]["lc"], Dict(
        "R_series_2_2" => 0.22, "X_series_2_2" => 0.11,
        "R_series_3_3" => 0.18, "X_series_3_3" => 0.09,
        "R_series_1_2" => 0.01, "X_series_1_2" => 0.004,
        "R_series_1_3" => 0.008, "X_series_1_3" => 0.003,
        "R_series_2_3" => 0.012, "X_series_2_3" => 0.005))
    load = net["load"]["load"]
    merge!(load, Dict("terminal_map" => copy(phases), "configuration" => "DELTA",
        "model" => model, "p_nom" => [10_000.0, 7_000.0, 4_000.0],
        "q_nom" => [2_000.0, 1_000.0, -500.0]))
    model == "constant_impedance" &&
        (load["v_nom"] = fill(sqrt(3) * 230.0, 3))
    net
end

function _bfm_solve(net; sb=1e4, cone=:real, objective=:source_import,
                    solver_options=(verbose=false,))
    solve_branch_flow_sdp(net;
        options=BranchFlowSDPOptions(s_base=sb, cone=cone, objective=objective),
        solver_options)
end

function _bfm_physical(net, result; atol=(voltage=1e-3, current=1e-3, power=0.1))
    physical_residuals(net, ACPoint(
        voltage=result.voltage_candidate, currents=result.current_candidate); atol)
end

@testset "Branch-flow SDP three-phase delta load laws" begin
    for law in ("constant_power", "constant_impedance")
        net = _bfm_three_phase_delta_case(; model=law)
        build = build_branch_flow_sdp(net;
            options=BranchFlowSDPOptions(objective=:source_import))
        @test build.numerical_diagnostics[:matrix_kcl_entries] == 12
        @test law == "constant_impedance" ||
              size(build.component_blocks[(:load, "load")], 1) == 6
        result = solve_branch_flow_sdp(build; solver_options=(verbose=false,))
        @test result.solve.optimal
        balance = build.model.ext[:branch_flow_balance]
        @test maximum(abs(JuMP.value(balance["load"][a, b]))
            for a in 1:3, b in 1:3) < 2e-7
        if law == "constant_power"
            @test result.relaxed_powers[(:load, "load")] ≈
                  complex.([10_000.0, 7_000.0, 4_000.0], [2_000.0, 1_000.0, -500.0])
                  rtol=2e-8
        else
            reference = solve_sdp_opf(net;
                options=SDPOptions(objective=:source_import),
                solver_options=(verbose=false,))
            @test reference.solve.optimal
            @test result.objective ≈ reference.objective rtol=2e-5
            @test _bfm_physical(net, result).passed
        end
    end
end

@testset "Branch-flow SDP explicit-neutral matrix KCL" begin
    net = _l3f_case(explicit_neutral=true)
    build = build_branch_flow_sdp(net;
        options=BranchFlowSDPOptions(objective=:source_import))
    refs = build.model.ext[:branch_flow_matrix_kcl]
    @test all(key[3] == 1 for key in keys(refs) if key[1] == "load")
    @test count(key -> key[1] == "load", keys(refs)) == 4
    result = solve_branch_flow_sdp(build; solver_options=(verbose=false,))
    @test result.solve.optimal
    @test _bfm_physical(net, result;
        atol=(voltage=1e-4, current=2e-4, power=0.05)).passed
    balance = build.model.ext[:branch_flow_balance]["load"]
    @test maximum(abs(JuMP.value(balance[a, 1])) for a in 1:2) < 2e-7
end

@testset "Branch-flow SDP all fixed transformer connections" begin
    cases = ("single_phase", "center_tap", "single_phase_autotransformer",
             "open_delta_regulator")
    for kind in cases
        net = _sdp_tx_case(kind; tap=1.04)
        if kind == "center_tap"
            _sdp_zload!(net, "l1", ["x1", "n"], 0.12 - 0.03im)
            _sdp_zload!(net, "l2", ["x2", "n"], 0.05 - 0.01im)
        elseif kind == "open_delta_regulator"
            for (k, terminal) in enumerate(["a", "b", "c"])
                _sdp_zload!(net, "l$k", [terminal], 0.01k - 0.002im)
            end
        else
            _sdp_zload!(net, "l", ["p", "n"], 0.08 - 0.02im)
        end
        result = _bfm_solve(net)
        reference = solve_sdp_opf(net;
            options=SDPOptions(objective=:source_import),
            solver_options=(verbose=false,))
        @test result.solve.optimal
        @test reference.solve.optimal
        @test result.objective ≈ reference.objective rtol=3e-6 atol=2e-4
        @test maximum(abs(result.voltage_candidate[key] - reference.voltage_candidate[key])
                      for key in keys(result.voltage_candidate)) < 2e-3
        @test _bfm_physical(net, result;
            atol=(voltage=3e-3, current=3e-3, power=0.2)).passed
    end
end

@testset "Branch-flow SDP transformer excitation, grounding, bonds and limits" begin
    net = _sdp_tx_case("single_phase"; tap=1.02)
    tx = net["transformer"]["single_phase"]["tx"]
    merge!(tx, Dict("r_series_from" => 0.3, "x_series_from" => 0.15,
        "r_series_to" => 0.1, "x_series_to" => 0.05,
        "no_load_shunt" => Dict("winding" => 2, "g" => 0.001,
                                 "b" => -0.0005),
        "r_neutral_to" => 0.5, "x_neutral_to" => 0.1))
    empty!(net["bus"]["t"]["perfectly_grounded_terminals"])
    _sdp_zload!(net, "l", ["p", "n"], 0.08 - 0.02im)
    result = _bfm_solve(net)
    reference = solve_sdp_opf(net;
        options=SDPOptions(objective=:source_import), solver_options=(verbose=false,))
    @test result.solve.optimal
    @test result.objective ≈ reference.objective rtol=4e-6
    @test maximum(abs(result.voltage_candidate[key] - reference.voltage_candidate[key])
                  for key in keys(result.voltage_candidate)) < 2e-3
    @test _bfm_physical(net, result;
        atol=(voltage=3e-3, current=3e-3, power=0.2)).passed

    center = _sdp_tx_case("center_tap")
    center_tx = center["transformer"]["center_tap"]["tx"]
    center_tx["r_neutral_to"] = 0.0
    center_tx["x_neutral_to"] = 0.0
    _sdp_zload!(center, "l1", ["x1", "n"], 0.1 - 0.02im)
    _sdp_zload!(center, "l2", ["x2", "n"], 0.04 - 0.01im)
    grounded = _bfm_solve(center)
    @test grounded.solve.optimal
    @test _bfm_physical(center, grounded;
        atol=(voltage=3e-3, current=3e-3, power=0.2)).passed

    for kind in ("single_phase_autotransformer", "open_delta_regulator")
        bonded = _sdp_tx_case(kind; tap=1.03)
        if kind == "single_phase_autotransformer"
            _sdp_zload!(bonded, "l", ["p", "n"], 0.05 - 0.01im)
        else
            for (k, terminal) in enumerate(["a", "b", "c"])
                _sdp_zload!(bonded, "l$k", [terminal], 0.01k)
            end
        end
        result = _bfm_solve(bonded)
        @test result.solve.optimal
        @test _bfm_physical(bonded, result;
            atol=(voltage=3e-3, current=3e-3, power=0.2)).passed
    end

    limited = _sdp_tx_case("delta_wye")
    for (k, terminal) in enumerate(["a", "b", "c"])
        _sdp_zload!(limited, "l$k", [terminal, "n"], 0.03k)
    end
    baseline = _bfm_solve(limited)
    @test baseline.solve.optimal
    coil = baseline.current_candidate[(:transformer_coil_from, "delta_wye/tx")]
    limited["transformer"]["delta_wye"]["tx"]["i_max_from"] =
        fill(0.5minimum(abs, coil), 3)
    @test !_bfm_solve(limited).solve.optimal
end

@testset "Branch-flow SDP mixed line-transformer orientation" begin
    net = _sdp_tx_case("single_phase")
    source = pop!(net["voltage_source"], "s")
    source["bus"] = "t"
    source["terminal_map"] = ["p", "n"]
    source["v_magnitude"] = [115.0, 0.0]
    net["voltage_source"]["s"] = source
    net["bus"]["l"] = Dict{String,Any}(
        "terminal_names" => ["p", "n"], "perfectly_grounded_terminals" => ["n"])
    net["linecode"] = Dict("lc" => Dict{String,Any}(
        "R_series_1_1" => 0.1, "X_series_1_1" => 0.04,
        "R_series_2_2" => 0.05, "X_series_2_2" => 0.02))
    net["line"] = Dict("line" => Dict{String,Any}(
        "bus_from" => "f", "bus_to" => "l",
        "terminal_map_from" => ["p", "n"],
        "terminal_map_to" => ["p", "n"], "linecode" => "lc"))
    net["load"] = Dict("l" => Dict{String,Any}(
        "bus" => "l", "terminal_map" => ["p", "n"],
        "configuration" => "SINGLE_PHASE", "model" => "constant_impedance",
        "v_nom" => [230.0], "p_nom" => [1500.0], "q_nom" => [300.0]))
    build = build_branch_flow_sdp(net;
        options=BranchFlowSDPOptions(objective=:source_import))
    @test any(edge.kind == :transformer && edge.reversed for edge in build.topology)
    @test any(edge.kind == :line for edge in build.topology)
    result = solve_branch_flow_sdp(build; solver_options=(verbose=false,))
    reference = solve_sdp_opf(net;
        options=SDPOptions(objective=:source_import), solver_options=(verbose=false,))
    @test result.solve.optimal
    @test result.objective ≈ reference.objective rtol=5e-6
    @test _bfm_physical(net, result;
        atol=(voltage=3e-3, current=3e-3, power=0.2)).passed
end

@testset "Matrix KCL excludes a diagonal-only delta relaxation" begin
    net = _bfm_three_phase_delta_case()
    full = build_branch_flow_sdp(net;
        options=BranchFlowSDPOptions(objective=:source_import))
    full_result = solve_branch_flow_sdp(full; solver_options=(verbose=false,))
    @test full_result.solve.optimal

    diagonal = build_branch_flow_sdp(net;
        options=BranchFlowSDPOptions(objective=:source_import))
    for constraint in values(diagonal.model.ext[:branch_flow_matrix_kcl])
        JuMP.delete(diagonal.model, constraint)
    end
    balance = diagonal.model.ext[:branch_flow_balance]
    for (bus, data) in net["bus"]
        grounded = Set(string.(get(data, "perfectly_grounded_terminals", String[])))
        for (k, terminal) in enumerate(data["terminal_names"])
            terminal in grounded && continue
            @constraint(diagonal.model, real(balance[bus][k, k]) == 0)
            @constraint(diagonal.model, imag(balance[bus][k, k]) == 0)
        end
    end
    diagonal_result = solve_branch_flow_sdp(diagonal; solver_options=(verbose=false,))
    @test diagonal_result.solve.optimal
    off_diagonal = maximum(abs(JuMP.value(balance["load"][a, b]))
        for a in 1:3, b in 1:3 if a != b)
    @test off_diagonal > 1e-3
    @test diagonal_result.objective < full_result.objective - 0.1
end

@testset "Branch-flow SDP keeps device limits and costs in terminal-map order" begin
    net = _bfm_three_phase_delta_case(; model="constant_impedance")
    target = [1_000.0, 2_000.0, 3_000.0]
    costs = [2.0, 3.0, 5.0]
    net["generator"] = Dict("g" => Dict{String,Any}(
        "bus" => "load", "terminal_map" => ["b", "c", "a"],
        "configuration" => "WYE", "p_min" => copy(target),
        "p_max" => copy(target), "q_min" => zeros(3), "q_max" => zeros(3),
        "s_max" => [1_100.0, 2_100.0, 3_100.0],
        "i_max" => [10.0, 15.0, 20.0], "cost" => copy(costs)))
    result = _bfm_solve(net; objective=:cost)
    @test result.solve.optimal
    @test real.(result.relaxed_powers[(:generator, "g")]) ≈ target atol=1e-5
    expected = sum(real, result.relaxed_powers[(:voltage_source, "source")]) / 1_000 +
               dot(costs, target) / 1_000
    @test result.objective ≈ expected atol=1e-5
    @test _bfm_physical(net, result;
        atol=(voltage=2e-3, current=2e-3, power=0.2)).passed

    partial = deepcopy(net)
    partial["generator"]["g"] = Dict{String,Any}(
        "bus" => "load", "terminal_map" => ["b", "c"],
        "configuration" => "WYE", "p_min" => [500.0, 750.0],
        "p_max" => [500.0, 750.0], "q_min" => zeros(2), "q_max" => zeros(2),
        "s_max" => [5_000.0, 6_000.0], "i_max" => [100.0, 200.0],
        "cost" => [7.0, 11.0])
    partial_result = _bfm_solve(partial; objective=:cost)
    @test partial_result.solve.optimal
    @test real.(partial_result.relaxed_powers[(:generator, "g")]) ≈
          [500.0, 750.0] atol=1e-5
end

@testset "Branch-flow SDP transformer maps control ratings and result order" begin
    net = _sdp_tx_case("single_phase"; tap=1.01)
    net["bus"]["f"]["terminal_names"] = ["x", "p", "n"]
    source = net["voltage_source"]["s"]
    source["terminal_map"] = ["x", "p", "n"]
    source["v_magnitude"] = [120.0, 230.0, 0.0]
    source["v_angle"] = [pi / 2, 0.0, 0.0]
    tx = net["transformer"]["single_phase"]["tx"]
    tx["terminal_map_from"] = ["n", "p"]
    tx["i_max_from"] = [100.0, 100.0]
    tx["i_max_to"] = [100.0, 100.0]
    _sdp_zload!(net, "l", ["p", "n"], 0.08 - 0.02im)

    result = _bfm_solve(net)
    reference = solve_sdp_opf(net;
        options=SDPOptions(objective=:source_import), solver_options=(verbose=false,))
    @test result.solve.optimal
    @test reference.solve.optimal
    @test result.objective ≈ reference.objective rtol=5e-6 atol=2e-4
    @test length(result.current_candidate[(:transformer_from, "single_phase/tx")]) == 2
    @test result.current_candidate[(:transformer_from, "single_phase/tx")] ≈
          reference.current_candidate[(:transformer_from, "single_phase/tx")] rtol=5e-5 atol=2e-4
    @test length(result.relaxed_powers[(:transformer_from, "single_phase/tx")]) == 2
    @test _bfm_physical(net, result;
        atol=(voltage=3e-3, current=3e-3, power=0.2)).passed
    @test result.rank_ratio ≈
          result.numerical_diagnostics[:local_rank_ratios]["transformer/single_phase/tx"]
end

@testset "Branch-flow SDP applicability covers builder assumptions" begin
    missing_map = _l3f_case()
    delete!(missing_map["line"]["line"], "terminal_map_from")
    @test !is_branch_flow_sdp_applicable(
        check_branch_flow_sdp_applicability(missing_map))

    malformed_shunt = _l3f_case()
    malformed_shunt["shunt"] = Dict("bad" => Dict{String,Any}(
        "bus" => "load", "terminal_map" => ["a"], "G_2_2" => 0.1))
    @test !is_branch_flow_sdp_applicable(
        check_branch_flow_sdp_applicability(malformed_shunt))

    scalar_wye = _bfm_three_phase_delta_case()
    load = scalar_wye["load"]["load"]
    load["configuration"] = "WYE"
    load["p_nom"] = 1_000.0
    load["q_nom"] = 100.0
    @test is_branch_flow_sdp_applicable(
        check_branch_flow_sdp_applicability(scalar_wye))
    @test build_branch_flow_sdp(scalar_wye; options=BranchFlowSDPOptions(
        objective=:source_import)) isa BranchFlowSDPBuild

    bad_wye = deepcopy(scalar_wye)
    bad_wye["load"]["load"]["p_nom"] = [1_000.0, 2_000.0]
    @test !is_branch_flow_sdp_applicable(
        check_branch_flow_sdp_applicability(bad_wye))

    negative_rating = _l3f_case()
    negative_rating["linecode"]["lc"]["i_max"] = [-400.0]
    @test !is_branch_flow_sdp_applicable(
        check_branch_flow_sdp_applicability(negative_rating))
    @test_throws BranchFlowSDPInapplicableError build_branch_flow_sdp(negative_rating)
end

@testset "Branch-flow SDP cone, scaling and feasibility variants" begin
    delta = _bfm_three_phase_delta_case(; model="constant_impedance")
    transformer = _sdp_tx_case("single_phase"; tap=1.02)
    _sdp_zload!(transformer, "l", ["p", "n"], 0.07 - 0.02im)
    for net in (delta, transformer), cone in (:real, :hermitian), sb in (1e4, 1e6)
        result = _bfm_solve(net; sb, cone, objective=:feasibility,
            solver_options=(verbose=false, tol_feas=1e-6,
                tol_gap_abs=1e-6, tol_gap_rel=1e-6))
        @test result.solve.optimal
        @test isfinite(result.rank_ratio)
        @test maximum(abs, values(result.voltage_candidate)) > 0
    end
end
