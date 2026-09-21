using Test, FormulationLab, MosekTools, JuMP
include(joinpath(@__DIR__, "..", "lindist3flow_fixtures.jl"))

@testset "Mosek relaxation diagnostics extension" begin
    @test Base.get_extension(FormulationLab, :FormulationLabMosekToolsExt) !== nothing
    net = _l3f_case()
    build = build_opf(net, BranchFlowSDP(objective=:source_import,
        preprocess=true); optimizer=MosekTools.Optimizer)
    set_silent(build.model)
    result = solve_branch_flow_sdp(build)
    report = validate_relaxation_solution(build, result; model_atol=1e-6)
    @test report.bound_source == "objective_bound"
    @test report.objective_bound == report.dual_objective
    @test isfinite(report.relative_gap)
    @test haskey(report.solver_metrics,
        "interior_point_primal_feasibility")
    @test haskey(report.solver_metrics,
        "interior_point_dual_feasibility")
    @test haskey(report.solver_metrics,
        "solution_dual_cone_violation")
end
