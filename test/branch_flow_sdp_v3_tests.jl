using Test, FormulationLab, Clarabel, LinearAlgebra
isdefined(@__MODULE__, :_L3F_FIXTURES_LOADED) || include("lindist3flow_fixtures.jl")

function _bfm_mesh_case(; second_source=false)
    buses = Dict(id => Dict{String,Any}(
        "terminal_names" => ["a"], "v_min" => [180.0], "v_max" => [250.0])
        for id in ("source", "middle", "load"))
    lines = Dict{String,Any}()
    for (id, from, to) in (("sm", "source", "middle"),
                           ("ml", "middle", "load"),
                           ("sl", "source", "load"))
        lines[id] = Dict{String,Any}(
            "bus_from" => from, "bus_to" => to,
            "terminal_map_from" => ["a"], "terminal_map_to" => ["a"],
            "linecode" => "lc")
    end
    sources = Dict("s1" => Dict{String,Any}(
        "bus" => "source", "terminal_map" => ["a"],
        "configuration" => "WYE", "v_magnitude" => [230.0],
        "v_angle" => [0.0], "cost" => [1.0]))
    second_source && (sources["s2"] = Dict{String,Any}(
        "bus" => "middle", "terminal_map" => ["a"],
        "configuration" => "WYE", "v_magnitude" => [229.0],
        "v_angle" => [0.002], "cost" => [1.0]))
    Dict{String,Any}(
        "bus" => buses,
        "linecode" => Dict("lc" => Dict{String,Any}(
            "R_series_1_1" => 0.1, "X_series_1_1" => 0.05,
            "G_from_1_1" => 1e-4, "B_from_1_1" => -2e-4,
            "G_to_1_1" => 2e-4, "B_to_1_1" => 1e-4)),
        "line" => lines, "voltage_source" => sources,
        "load" => Dict("load" => Dict{String,Any}(
            "bus" => "load", "terminal_map" => ["a"],
            "configuration" => "WYE", "model" => "constant_impedance",
            "v_nom" => [230.0], "p_nom" => [10_000.0], "q_nom" => [2_000.0])))
end

function _bfm_paper_line(z, y; smax)
    Dict{String,Any}(
        "bus_from" => "i", "bus_to" => "j",
        "terminal_map_from" => ["a"], "terminal_map_to" => ["a"],
        "R_series_1_1" => real(z), "X_series_1_1" => imag(z),
        "B_from_1_1" => imag(y), "B_to_1_1" => imag(y),
        "s_max" => [smax])
end

function _bfm_parallel_paper_case()
    Dict{String,Any}(
        "bus" => Dict(
            "i" => Dict{String,Any}("terminal_names" => ["a"],
                "v_min" => [0.9], "v_max" => [1.1]),
            "j" => Dict{String,Any}("terminal_names" => ["a"],
                "v_min" => [0.9], "v_max" => [1.1])),
        "line" => Dict(
            "l" => _bfm_paper_line(0.065 + 0.62im, 0.225im; smax=90.0),
            "k" => _bfm_paper_line(0.025 - 0.75im, 0.35im; smax=0.5)),
        "voltage_source" => Dict("g1" => Dict{String,Any}(
            "bus" => "i", "terminal_map" => ["a"], "configuration" => "WYE",
            "v_magnitude" => [0.94], "v_angle" => [0.0],
            "p_min" => [0.0], "p_max" => [2.0],
            "q_min" => [-10.0], "q_max" => [10.0], "cost" => [1_000.0])),
        "generator" => Dict("g2" => Dict{String,Any}(
            "bus" => "j", "terminal_map" => ["a"], "configuration" => "WYE",
            "p_min" => [0.0], "p_max" => [2.0],
            "q_min" => [-10.0], "q_max" => [10.0], "cost" => [5_000.0])),
        "load" => Dict("d" => Dict{String,Any}(
            "bus" => "j", "terminal_map" => ["a"], "configuration" => "WYE",
            "model" => "constant_power", "p_nom" => [1.1], "q_nom" => [0.4])))
end

function _bfm_total_current_paper_case()
    net = Dict{String,Any}(
        "bus" => Dict(
            "i" => Dict{String,Any}("terminal_names" => ["a"],
                "v_min" => [0.94], "v_max" => [1.1]),
            "j" => Dict{String,Any}("terminal_names" => ["a"],
                "v_min" => [0.94], "v_max" => [1.1])),
        "line" => Dict("l" => _bfm_paper_line(
            0.065 + 0.62im, 0.9im; smax=0.8)),
        "voltage_source" => Dict("g1" => Dict{String,Any}(
            "bus" => "i", "terminal_map" => ["a"], "configuration" => "WYE",
            "v_magnitude" => [0.94], "v_angle" => [0.0],
            "p_min" => [0.0], "p_max" => [2.0],
            "q_min" => [-1.0], "q_max" => [1.0], "cost" => [20_000.0])),
        "generator" => Dict("g2" => Dict{String,Any}(
            "bus" => "j", "terminal_map" => ["a"], "configuration" => "WYE",
            "p_min" => [0.0], "p_max" => [2.0],
            "q_min" => [-1.0], "q_max" => [1.0], "cost" => [-10_000.0])),
        "load" => Dict(
            "di" => Dict{String,Any}(
                "bus" => "i", "terminal_map" => ["a"],
                "configuration" => "WYE", "model" => "constant_power",
                "p_nom" => [0.11], "q_nom" => [0.4]),
            "dj" => Dict{String,Any}(
                "bus" => "j", "terminal_map" => ["a"],
                "configuration" => "WYE", "model" => "constant_power",
                "p_nom" => [0.9], "q_nom" => [0.5])))
    net
end

function _bfm_nwinding_case()
    net = Dict{String,Any}(
        "bus" => Dict("b" => Dict{String,Any}(
            "terminal_names" => ["p", "n"],
            "perfectly_grounded_terminals" => ["n"])),
        "voltage_source" => Dict("s" => Dict{String,Any}(
            "bus" => "b", "terminal_map" => ["p", "n"],
            "configuration" => "WYE", "v_magnitude" => [230.0, 0.0],
            "v_angle" => [0.0, 0.0], "cost" => [1.0])))
    windings = Dict{String,Any}[]
    for (k, voltage) in enumerate((230.0, 115.0, 57.5))
        bus = k == 1 ? "b" : "b$k"
        net["bus"][bus] = Dict{String,Any}(
            "terminal_names" => ["p", "n"],
            "perfectly_grounded_terminals" => ["n"])
        push!(windings, Dict{String,Any}(
            "bus" => bus, "terminal_map" => ["p", "n"],
            "configuration" => "WYE", "v_nom" => voltage,
            "r_winding" => 0.01 * (voltage / 230)^2, "tap_ratio" => 1.0,
            "i_max" => [100.0], "s_max" => [20_000.0]))
    end
    net["transformer"] = Dict("n_winding" => Dict("t" => Dict{String,Any}(
        "windings" => windings,
        "x_sc" => Dict("1_2" => 0.04, "1_3" => 0.04, "2_3" => 0.04),
        "s_rating" => 10_000.0)))
    net["load"] = Dict(
        "l2" => Dict{String,Any}(
            "bus" => "b2", "terminal_map" => ["p", "n"],
            "configuration" => "WYE", "model" => "constant_impedance",
            "v_nom" => [115.0], "p_nom" => [1_000.0], "q_nom" => [200.0]),
        "l3" => Dict{String,Any}(
            "bus" => "b3", "terminal_map" => ["p", "n"],
            "configuration" => "WYE", "model" => "constant_impedance",
            "v_nom" => [57.5], "p_nom" => [300.0], "q_nom" => [50.0]))
    net
end

@testset "Branch-flow SDP meshes, sources and line endpoint shunts" begin
    for second_source in (false, true)
        net = _bfm_mesh_case(; second_source)
        report = check_branch_flow_sdp_applicability(net)
        @test is_branch_flow_sdp_applicable(report)
        build = build_branch_flow_sdp(net;
            options=BranchFlowSDPOptions(objective=:source_import))
        @test build.numerical_diagnostics[:cycle_count] == 1
        @test build.numerical_diagnostics[:source_count] == (second_source ? 2 : 1)
        @test build.numerical_diagnostics[:global_voltage_closure]
        result = solve_branch_flow_sdp(build; solver_options=(verbose=false,))
        reference = solve_sdp_opf(net;
            options=SDPOptions(objective=:source_import), solver_options=(verbose=false,))
        @test result.solve.optimal
        @test reference.solve.optimal
        @test result.objective ≈ reference.objective rtol=2e-5
        second_source && @test result.voltage_candidate[("middle", "a")] ≈
            229cis(0.002) atol=2e-6
        @test physical_residuals(net, ACPoint(
            voltage=result.voltage_candidate, currents=result.current_candidate);
            atol=(voltage=2e-3, current=2e-3, power=0.2)).passed
    end

    parallel = _bfm_parallel_paper_case()
    build = build_branch_flow_sdp(parallel; options=BranchFlowSDPOptions(
        s_base=1.0, objective=:cost))
    @test build.numerical_diagnostics[:cycle_count] == 1
    result = solve_branch_flow_sdp(build; solver_options=(verbose=false,))
    reference = solve_sdp_opf(parallel;
        options=SDPOptions(s_base=1.0, objective=:cost),
        solver_options=(verbose=false,))
    @test result.solve.optimal
    @test reference.solve.optimal
    @test result.objective ≈ reference.objective rtol=3e-5
    cross = Dict(edge.id => JuMP.value(
        build.voltage_moments[edge.parent][1, 1] -
        edge.S[1, 1] * conj(edge.Z[1, 1])) for edge in build.edge_records)
    @test cross["l"] ≈ cross["k"] atol=2e-7
end


@testset "Branch-flow SDP paper-derived total and series current bounds" begin
    net = _bfm_total_current_paper_case()
    strengthened = build_branch_flow_sdp(net; options=BranchFlowSDPOptions(
        s_base=1.0, objective=:cost, implied_current_limits=true))
    diagnostic = only(strengthened.numerical_diagnostics[:line_bound_diagnostics])
    @test diagnostic.derived_endpoint_current_parent[1] ≈ 0.8 / 0.94
    @test diagnostic.derived_endpoint_current_child[1] ≈ 0.8 / 0.94
    @test diagnostic.effective_endpoint_current_parent[1] ≈ 0.8 / 0.94
    @test diagnostic.implied_series_current[1] ≈ 0.8 / 0.94 + 0.9 * 0.94
    improved = solve_branch_flow_sdp(strengthened; solver_options=(verbose=false,))
    canonical = solve_branch_flow_sdp(net; options=BranchFlowSDPOptions(
        s_base=1.0, objective=:cost, implied_current_limits=false),
        solver_options=(verbose=false,))
    @test improved.solve.optimal
    @test canonical.solve.optimal
    @test improved.objective > canonical.objective + 1e-3

    lnc_build = build_branch_flow_sdp(net; options=BranchFlowSDPOptions(
        s_base=1.0, objective=:cost, lnc=:lines))
    @test any(d -> d.status == :applied, lnc_build.lnc_diagnostics)

    grounded = _l3f_case(explicit_neutral=true)
    delete!(grounded["bus"]["load"], "v_min")
    delete!(grounded["bus"]["load"], "v_max")
    merge!(grounded["bus"]["load"], Dict(
        "vpn_min" => [180.0], "vpn_max" => [250.0], "vn_max" => 0.0))
    grounded["line"]["line"]["s_max"] = [20_000.0]
    grounded_build = build_branch_flow_sdp(grounded)
    grounded_bounds = only(
        grounded_build.numerical_diagnostics[:line_bound_diagnostics])
    @test grounded_bounds.derived_endpoint_current_child[1] ≈ 20_000 / 180
    @test isinf(grounded_bounds.derived_endpoint_current_child[2])
end

@testset "Branch-flow SDP switches, capacitors and delta generators" begin
    net = _l3f_case()
    line = pop!(net["line"], "line")
    net["switch"] = Dict("sw" => Dict{String,Any}(
        key => line[key] for key in ("bus_from", "bus_to",
            "terminal_map_from", "terminal_map_to")))
    net["switch"]["sw"]["open_switch"] = false
    net["capacitor"] = Dict("c" => Dict{String,Any}(
        "bus" => "load", "terminal_map" => ["a"],
        "configuration" => "SINGLE_PHASE", "q_rated" => [2_000.0],
        "v_nom" => 230.0))
    result = solve_branch_flow_sdp(net;
        options=BranchFlowSDPOptions(objective=:source_import),
        solver_options=(verbose=false,))
    @test result.solve.optimal
    @test only(result.relaxed_powers[(:capacitor, "c")]) ≈ -2_000im atol=0.02
    @test physical_residuals(net, ACPoint(
        voltage=result.voltage_candidate, currents=result.current_candidate);
        atol=(voltage=1e-3, current=1e-3, power=0.1)).passed
    net["switch"]["sw"]["open_switch"] = true
    open_build = build_branch_flow_sdp(net;
        options=BranchFlowSDPOptions(objective=:source_import))
    @test open_build.numerical_diagnostics[:source_free_components] == 1
    @test !solve_branch_flow_sdp(open_build;
        solver_options=(verbose=false,)).solve.optimal

    phases = ["a", "b", "c"]
    delta_voltage = 230.0 .* cis.([0.0, -2pi / 3, 2pi / 3])
    delta_current = ComplexF64[0.7 + 0.2im, -0.3 + 0.1im, -0.4 - 0.3im]
    @test sum(delta_current) ≈ 0.0 + 0.0im atol=1e-14
    delta_power = delta_voltage .* conj.(delta_current)
    delta_map = ["b", "c", "a"]
    delta_positions = [2, 3, 1]
    ordered_power = delta_power[delta_positions]
    delta = Dict{String,Any}(
        "bus" => Dict("b" => Dict{String,Any}("terminal_names" => phases)),
        "terminal_conventions" => Dict("phase" => phases, "neutral" => String[]),
        "voltage_source" => Dict("s" => Dict{String,Any}(
            "bus" => "b", "terminal_map" => phases, "configuration" => "WYE",
            "v_magnitude" => fill(230.0, 3),
            "v_angle" => [0.0, -2pi / 3, 2pi / 3], "cost" => ones(3))),
        "generator" => Dict("g" => Dict{String,Any}(
            "bus" => "b", "terminal_map" => delta_map, "configuration" => "DELTA",
            "p_min" => real.(ordered_power), "p_max" => real.(ordered_power),
            "q_min" => imag.(ordered_power), "q_max" => imag.(ordered_power),
            "s_max" => abs.(ordered_power) .+ 1.0,
            "i_max" => abs.(delta_current[delta_positions]) .+ 0.01,
            "cost" => [7.0, 11.0, 13.0])))
    result = solve_branch_flow_sdp(delta;
        options=BranchFlowSDPOptions(objective=:source_import),
        solver_options=(verbose=false, tol_feas=1e-7, tol_gap_abs=1e-7))
    @test result.solve.optimal
    @test result.relaxed_powers[(:generator, "g")] ≈ ordered_power atol=2e-4
    for (k, terminal) in enumerate(delta_map)
        @test result.relaxed_powers[(:generator, "g")][k] ≈
              result.voltage_candidate[("b", terminal)] *
              conj(result.current_candidate[(:generator, "g")][k]) atol=1e-2
    end
    @test abs(sum(result.current_candidate[(:generator, "g")])) < 1e-8
    @test physical_residuals(delta, ACPoint(
        voltage=result.voltage_candidate, currents=result.current_candidate);
        atol=(voltage=1e-3, current=1e-3, power=0.1)).passed
end

@testset "Branch-flow SDP nonlinear loads, voltage maps and LNCs" begin
    for (law, gp, gq) in (("constant_current", 1.0, 1.0),
                          ("zip", 0.0, 0.0),
                          ("exponential", 3.0, -1.0))
        net = Dict{String,Any}(
            "bus" => Dict("b" => Dict{String,Any}(
                "terminal_names" => ["p", "n"],
                "perfectly_grounded_terminals" => ["n"],
                "vpn_min" => [220.0], "vpn_max" => [220.0], "vn_max" => 0.0)),
            "voltage_source" => Dict("s" => Dict{String,Any}(
                "bus" => "b", "terminal_map" => ["p", "n"],
                "configuration" => "WYE", "v_magnitude" => [220.0, 0.0],
                "v_angle" => [0.0, 0.0], "cost" => [1.0])),
            "load" => Dict{String,Any}())
        load = Dict{String,Any}(
            "bus" => "b", "terminal_map" => ["p", "n"],
            "configuration" => "WYE", "model" => law, "v_nom" => [230.0],
            "p_nom" => [1_000.0], "q_nom" => [200.0])
        if law == "zip"
            for prefix in ("alpha", "beta"), suffix in ("z", "i", "p")
                load[prefix * "_" * suffix] = 1 / 3
            end
        elseif law == "exponential"
            load["gamma_p"], load["gamma_q"] = gp, gq
        end
        net["load"]["l"] = load
        result = solve_branch_flow_sdp(net;
            options=BranchFlowSDPOptions(objective=:source_import),
            solver_options=(verbose=false,))
        ratio = 220 / 230
        expected = law == "zip" ? (1_000 + 200im) * (ratio^2 + ratio + 1) / 3 :
                   1_000ratio^gp + 200im * ratio^gq
        @test result.solve.optimal
        @test only(result.relaxed_powers[(:load, "l")]) ≈ expected rtol=3e-5
        @test result.load_envelopes == ["l"]
    end

    phases = ["a", "b", "c"]
    bus = Dict{String,Any}(
        "terminal_names" => phases,
        "v_min" => fill(229.0, 3), "v_max" => fill(231.0, 3),
        "vpn_min" => fill(229.0, 3), "vpn_max" => fill(231.0, 3),
        "vpp_min" => fill(390.0, 3), "vpp_max" => fill(410.0, 3),
        "vpos_min" => 229.0, "vpos_max" => 231.0,
        "vneg_max" => 0.1, "vzero_max" => 0.1)
    mapped = Dict{String,Any}(
        "bus" => Dict("b" => bus),
        "terminal_conventions" => Dict("phase" => phases, "neutral" => String[]),
        "voltage_source" => Dict("s" => Dict{String,Any}(
            "bus" => "b", "terminal_map" => phases, "configuration" => "WYE",
            "v_magnitude" => fill(230.0, 3),
            "v_angle" => [0.0, -2pi / 3, 2pi / 3], "cost" => ones(3))),
        "load" => Dict("l" => Dict{String,Any}(
            "bus" => "b", "terminal_map" => phases, "configuration" => "WYE",
            "model" => "constant_impedance", "v_nom" => fill(230.0, 3),
            "p_nom" => fill(100.0, 3), "q_nom" => fill(20.0, 3))))
    mapped_result = solve_branch_flow_sdp(mapped;
        options=BranchFlowSDPOptions(objective=:source_import),
        solver_options=(verbose=false,))
    @test mapped_result.solve.optimal
    scalar_bounds = deepcopy(mapped)
    scalar_bounds["bus"]["b"]["v_min"] = 229.0
    scalar_bounds["bus"]["b"]["v_max"] = 231.0
    @test is_branch_flow_sdp_applicable(
        check_branch_flow_sdp_applicability(scalar_bounds))
    scalar_result = solve_branch_flow_sdp(scalar_bounds;
        options=BranchFlowSDPOptions(objective=:source_import),
        solver_options=(verbose=false,))
    @test scalar_result.solve.optimal
    mapped["bus"]["b"]["vpos_max"] = 200.0
    @test !solve_branch_flow_sdp(mapped;
        options=BranchFlowSDPOptions(objective=:source_import),
        solver_options=(verbose=false,)).solve.optimal

    net = _l3f_case()
    net["line"]["line"]["i_max"] = [100.0]
    explicit = VoltageLNC("edge", VoltagePhasor("source", "a"),
        VoltagePhasor("load", "a"),
        LNCBounds((229.0, 231.0), (180.0, 250.0), (-0.3, 0.3));
        provenance="declared feeder operating sector")
    build = build_branch_flow_sdp(net; options=BranchFlowSDPOptions(
        objective=:source_import, lnc=:lines, voltage_lncs=[explicit]))
    @test any(d -> d.id == "edge" && d.status == :applied, build.lnc_diagnostics)
    @test any(d -> startswith(d.id, "line/line/") && d.status == :applied,
              build.lnc_diagnostics)
    result = solve_branch_flow_sdp(build; solver_options=(verbose=false,))
    @test result.solve.optimal
    @test length(solve_diagnostics(result).lnc_diagnostics) >= 2
end

@testset "Branch-flow SDP general multiwinding transformer" begin
    net = _bfm_nwinding_case()
    @test is_branch_flow_sdp_applicable(check_branch_flow_sdp_applicability(net))
    build = build_branch_flow_sdp(net;
        options=BranchFlowSDPOptions(objective=:source_import))
    @test haskey(build.transformer_blocks, "n_winding/t")
    result = solve_branch_flow_sdp(build; solver_options=(verbose=false,))
    reference = solve_sdp_opf(net;
        options=SDPOptions(objective=:source_import), solver_options=(verbose=false,))
    @test result.solve.optimal
    @test reference.solve.optimal
    @test result.objective ≈ reference.objective rtol=2e-5
    for bus in ("b2", "b3")
        @test result.voltage_candidate[(bus, "p")] ≈
              reference.voltage_candidate[(bus, "p")] rtol=2e-4
    end
    @test all(haskey(result.current_candidate,
        (:transformer_winding, "n_winding/t/$k")) for k in 1:3)
    @test all(haskey(result.current_candidate,
        (:transformer_coil, "n_winding/t/$k")) for k in 1:3)

    mapped = _bfm_nwinding_case()
    mapped["bus"]["b2"]["terminal_names"] = ["x", "p", "n"]
    mapped["bus"]["b2"]["perfectly_grounded_terminals"] = ["x", "n"]
    mapped["transformer"]["n_winding"]["t"]["windings"][2]["terminal_map"] =
        ["n", "p"]
    mapped_result = solve_branch_flow_sdp(mapped;
        options=BranchFlowSDPOptions(objective=:source_import),
        solver_options=(verbose=false,))
    @test mapped_result.solve.optimal
    mapped_key = (:transformer_winding, "n_winding/t/2")
    @test length(mapped_result.current_candidate[mapped_key]) == 2
    @test length(mapped_result.relaxed_powers[mapped_key]) == 2
    @test physical_residuals(mapped, ACPoint(
        voltage=mapped_result.voltage_candidate,
        currents=mapped_result.current_candidate);
        atol=(voltage=3e-3, current=3e-3, power=0.2)).passed

    unsupported = _l3f_case()
    unsupported["ibr"] = Dict("pv" => Dict{String,Any}(
        "bus" => "load", "terminal_map" => ["a"],
        "topology" => "SINGLE_PHASE", "s_max" => [1_000.0]))
    @test !is_branch_flow_sdp_applicable(
        check_branch_flow_sdp_applicability(unsupported))
end
