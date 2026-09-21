using Test, FormulationLab, Clarabel, JuMP
isdefined(@__MODULE__, :_l3f_case) || include("lindist3flow_fixtures.jl")

@testset "SDP relaxation validation separates bounds from recovery" begin
    for formulation in (
        IVRSDP(objective=:source_import),
        BranchFlowSDP(objective=:source_import),
    )
        net = _l3f_case()
        build = build_opf(net, formulation)
        result = formulation isa IVRSDP ?
            solve_sdp_opf(build; solver_options=(verbose=false,)) :
            solve_branch_flow_sdp(build; solver_options=(verbose=false,))
        @test result.solve.optimal

        report = validate_relaxation_solution(build, result;
            feasible_objective=result.objective + 1.0,
            model_atol=1e-6,
            physical_atol=(voltage=1e-3, current=1e-3, power=0.1))
        @test report.bound_usable
        @test report.model_feasible
        @test report.bound_ordering_passed
        @test report.bound_margin > 0
        @test report.primal_dual_gap >= -1e-3
        @test !isempty(report.constraint_maxima)
        @test report.physical !== nothing
        @test report.recovery_feasible

        reversed = validate_relaxation_solution(build, result;
            feasible_objective=report.solver_bound - 1.0,
            model_atol=1e-6)
        @test !reversed.bound_ordering_passed
        @test !reversed.bound_usable
        @test any(contains("feasible AC objective"), reversed.reasons)
    end
end

@testset "SDP relaxation validation rejects unpublished solves" begin
    net = _l3f_case()
    net["line"]["line"]["i_max"] = [1.0]
    build = build_sdp_opf(net)
    result = solve_sdp_opf(build; solver_options=(verbose=false,))
    @test !result.solve.optimal
    report = validate_relaxation_solution(build, result)
    @test !report.bound_usable
    @test !report.solve.optimal
    @test !isempty(report.reasons)
    @test_throws ArgumentError validate_relaxation_solution(build, result;
        model_atol=-1.0)
end

@testset "SDP relaxation validation rejects mismatched result types" begin
    net = _l3f_case()
    ivr_build = build_opf(net, IVRSDP(objective=:source_import))
    ivr_result = solve_sdp_opf(ivr_build; solver_options=(verbose=false,))
    bfm_build = build_opf(net, BranchFlowSDP(objective=:source_import))
    bfm_result = solve_branch_flow_sdp(bfm_build; solver_options=(verbose=false,))
    @test_throws ArgumentError validate_relaxation_solution(ivr_build, bfm_result)
    @test_throws ArgumentError validate_relaxation_solution(bfm_build, ivr_result)
end
