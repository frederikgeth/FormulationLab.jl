# Optional cross-package oracle. Run after the ordinary suite has defined fixtures.
# BMOPFTools is deliberately absent from the package and ordinary test environment.
import BMOPFTools
_bmopf_replay(net; optimizer=nothing, kwargs...) =
    BMOPFTools.solve_pf(net; optimizer=optimizer === nothing ? Ipopt.Optimizer : optimizer, kwargs...)

@testset "LinDist3Flow power-flow reference" begin
    net = _l3f_two_bus()
    reference = l3f_reference_from_powerflow(net; powerflow=_bmopf_replay, solver_options=_l3f_ipopt())
    @test reference isa L3FReferenceState
    @test reference.provenance == :power_flow
    @test reference.nonlinear_status in (:OPTIMAL, :LOCALLY_SOLVED)
    @test length(reference.source_hash) == 64

    # The helper can create an explicit reference independently of whether a
    # caller elects to require neutral-reduction provenance on a later build.
    explicit_required = l3f_reference_from_powerflow(net; powerflow=_bmopf_replay,
        options=L3FOptions(reference_policy=:explicit),
        solver_options=_l3f_ipopt())
    @test explicit_required.provenance == :power_flow
    explicit_build = solve_l3f_opf(net, Clarabel.Optimizer; powerflow=_bmopf_replay,
        options=L3FOptions(validate_nonlinear=false, reference_policy=:explicit),
        reference=explicit_required, solver_options=_l3f_clarabel())
    @test explicit_build.solve.optimal
    @test explicit_build.formulation["reference_provenance"] == "power_flow"

    # The source is fixed data and is restored exactly; the load bus carries the
    # real drop, which the flat profile by construction does not.
    @test reference.voltage[("source", "a")] ≈ 230.0 + 0im
    @test abs(reference.voltage[("load", "a")]) < 230.0
    @test abs(reference.voltage[("load", "a")]) ≈ 220.2 atol=0.5

    flat = build_l3f_opf(net, Clarabel.Optimizer;
        options=L3FOptions(validate_nonlinear=false))
    @test abs(flat.reference.voltage[("load", "a")]) ≈ 230.0

    # It feeds straight back in and is recorded in the published provenance.
    refined = solve_l3f_opf(net, Clarabel.Optimizer; powerflow=_bmopf_replay, options=_L3F_FEASIBLE,
        reference=reference, solver_options=_l3f_clarabel())
    @test refined.solve.optimal
    @test refined.formulation["reference_provenance"] == "power_flow"
    @test refined.formulation["reference_hash"] == reference.source_hash
    # Linearizing elsewhere changes the answer; both remain close to the truth.
    @test refined.buses["load"]["a"]["w"] != flat.reference.voltage[("load", "a")]
    @test abs(refined.buses["load"]["a"]["vm"] - 220.2) < 1.0

    # `:source_propagated` still refuses to be displaced, even by a real
    # power-flow reference — the policy names the profile, not the quality.
    forced = build_l3f_opf(net, Clarabel.Optimizer;
        options=L3FOptions(validate_nonlinear=false, reference_policy=:source_propagated),
        reference=reference)
    @test forced.reference.provenance == :source_propagated

    # A power flow is determined, so an unpinned generator range is refused with
    # an actionable message rather than a solver failure.
    ranged = _l3f_two_bus()
    ranged["generator"] = Dict("pv" => Dict{String,Any}(
        "bus" => "load", "terminal_map" => ["a"], "configuration" => "SINGLE_PHASE",
        "p_min" => [0.0], "p_max" => [4_000.0], "q_min" => [0.0], "q_max" => [0.0],
        "cost" => [0.0]))
    err = try
        l3f_reference_from_powerflow(ranged; powerflow=_bmopf_replay, solver_options=_l3f_ipopt()); nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("dispatch", sprint(showerror, err))

    # Pinning it at a previous solution is the successive-linearization loop.
    first_pass = solve_l3f_opf(ranged, Clarabel.Optimizer; powerflow=_bmopf_replay,
        options=L3FOptions(validate_nonlinear=false, objective=:cost),
        solver_options=_l3f_clarabel())
    @test first_pass.generators["pv"]["pg"] ≈ [4_000.0] atol=1e-3
    looped = l3f_reference_from_powerflow(ranged; powerflow=_bmopf_replay, dispatch=first_pass,
        solver_options=_l3f_ipopt())
    @test looped.provenance == :power_flow
    # The generator lifts the load-bus voltage, so this reference sits above the
    # one taken without any dispatch.
    @test abs(looped.voltage[("load", "a")]) > abs(reference.voltage[("load", "a")])
    second_pass = solve_l3f_opf(ranged, Clarabel.Optimizer; powerflow=_bmopf_replay,
        options=L3FOptions(validate_nonlinear=false, objective=:cost),
        reference=looped, solver_options=_l3f_clarabel())
    @test second_pass.solve.optimal
    @test second_pass.formulation["reference_provenance"] == "power_flow"

    # An inapplicable network is refused before any solver runs.
    @test_throws L3FInapplicableError l3f_reference_from_powerflow(
        _l3f_two_bus(load_extra=Dict{String,Any}("configuration" => "ZIGZAG")))
end

@testset "LinDist3Flow nonlinear replay contract" begin
    net = _l3f_two_bus()
    result = solve_l3f_opf(net, Ipopt.Optimizer; powerflow=_bmopf_replay,
        options=L3FOptions(objective=:feasibility, validate_nonlinear=true),
        solver_options=_l3f_ipopt())
    validation = result.validation
    # `status` describes the replay, not the accuracy: the linearization omits
    # series losses, so a converged replay still differs from the linear answer.
    @test validation["status"] == "replayed"
    @test validation["nonlinear_solve_status"] in ("OPTIMAL", "LOCALLY_SOLVED")
    @test validation["compared_terminals"] == 2
    @test validation["physical_limits"] == "unassessed"
    @test isfinite(validation["maximum_voltage_magnitude_error"])
    @test validation["maximum_voltage_magnitude_error"] > 0.0
    @test !haskey(validation, "within_tolerance")
    @test result.reference.nonlinear_status == :replayed
    @test solve_diagnostics(result).validation == "replayed"

    # An explicit tolerance is what turns the replay into a judgement.
    loose = solve_l3f_opf(net, Ipopt.Optimizer; powerflow=_bmopf_replay,
        options=L3FOptions(objective=:feasibility, validate_nonlinear=true), solver_options=_l3f_ipopt(),
        voltage_tolerance=5.0)
    @test loose.validation["within_tolerance"] == true
    tight = solve_l3f_opf(net, Ipopt.Optimizer; powerflow=_bmopf_replay,
        options=L3FOptions(objective=:feasibility, validate_nonlinear=true), solver_options=_l3f_ipopt(),
        voltage_tolerance=1e-6)
    @test tight.validation["within_tolerance"] == false
    @test tight.validation["voltage_tolerance"] == 1e-6

    # The replay is skipped, not faked, when the linear solve is not optimal.
    # An unreachable voltage floor keeps the model an LP so Ipopt can take it.
    infeasible = _l3f_two_bus()
    infeasible["bus"]["load"]["v_min"] = [259.0]
    skipped = solve_l3f_opf(infeasible, Ipopt.Optimizer; powerflow=_bmopf_replay,
        options=L3FOptions(objective=:feasibility, validate_nonlinear=true),
        solver_options=_l3f_ipopt())
    @test !skipped.solve.optimal
    @test skipped.validation["status"] == "not_run"
    @test isnan(skipped.objective)
    @test all(isnan, skipped.lines["line"]["p"])

    # `validate_l3f_solution` operates on the result's own snapshot.
    standalone = validate_l3f_solution(result; powerflow=_bmopf_replay, voltage_tolerance=5.0)
    @test standalone["status"] == "replayed"
    @test standalone["within_tolerance"] == true
end

@testset "LinDist3Flow projection is flagged in the replay" begin
    exact = _l3f_low_case()
    exact["capacitor"] = Dict("c" => Dict{String,Any}(
        "bus" => "l", "terminal_map" => ["a"], "configuration" => "SINGLE_PHASE",
        "q_rated" => [3_000.0], "v_nom" => 230.0))
    result = solve_l3f_opf(exact, Ipopt.Optimizer; powerflow=_bmopf_replay,
        options=L3FOptions(unsupported=:lower, objective=:feasibility,
                           validate_nonlinear=true),
        solver_options=("print_level" => 0,))
    # A canonical lowering leaves the replay meaningful for the supported model.
    @test result.validation["replayed_network"] == "as_supplied"

    projected = _l3f_low_case()
    merge!(projected["load"]["d"], Dict{String,Any}(
        "model" => "constant_current", "v_nom" => [230.0]))
    approximate = solve_l3f_opf(projected, Ipopt.Optimizer; powerflow=_bmopf_replay,
        options=L3FOptions(unsupported=:approximate, objective=:feasibility,
                           validate_nonlinear=true),
        solver_options=("print_level" => 0,))
    # Here both the model and the replay describe the substituted load, so the
    # reported error does not include the projection error. The flag says so.
    @test approximate.validation["replayed_network"] == "projected"
    @test approximate.validation["status"] == "replayed"
end
