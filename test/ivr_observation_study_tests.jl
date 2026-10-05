using Test, FormulationLab, JSON3
include("../examples/benchmark_ivr_observations.jl")
@testset "Matched observation ablations" begin
    S=IVRObservationStudy;profiles=S.profiles()
    @test length(profiles)==6
    @test [(p.options.observation_support_threshold,p.options.observation_sharing) for p in profiles[3:6]]==[(2,:off),(2,:exact),(8,:off),(8,:exact)]
    @test all(p->p.options.device_elimination==:off && p.options.ground_scaling==:voltage,profiles)
    mktempdir() do dir
        net=S.L.case(conductors=3,segments=4,charged=true,tight=true)
        report=S.benchmark(net,joinpath(dir,"study.json"))
        @test report["position_balanced"]
        @test length(report["ranking"]["eligible"])==6
        @test all(p->p["warmup"]["accepted"] && all(t->t["accepted"],p["trials"]),report["profiles"])
        @test all(t->haskey(t,"shared_observation_count"),[t for p in report["profiles"] for t in p["trials"]])
        @test_throws ArgumentError S.benchmark(net,joinpath(dir,"bad.json");repetitions=6)
    end
end
