using Test, FormulationLab
include("../examples/benchmark_ivr_transformer_scaling.jl")
@testset "Independent transformer-scaling experiment controls" begin
    S=IVRTransformerScalingStudy
    mktempdir() do dir
        net=S.L.case(segments=4,transformers=true,tight=true)
        for policy in ("none","gradient-based")
            ps=S.profiles(nlp_scaling_method=policy)
            @test length(ps)==4
            @test all(p->p.solver_options.nlp_scaling_method==policy && p.options.lifting==:off && p.options.device_elimination==:off,ps)
            r=S.benchmark(net,joinpath(dir,"$policy.json");nlp_scaling_method=policy)
            @test r["position_balanced"] && length(r["ranking"]["eligible"])==4
            @test all(p->p["warmup"]["accepted"] && all(t->t["accepted"],p["trials"]),r["profiles"])
            @test all(t->t["per_unit_bases"].power_VA==1e4,[t for p in r["profiles"] for t in p["trials"]])
        end
        @test_throws ArgumentError S.benchmark(net,joinpath(dir,"bad.json");repetitions=4)
        @test_throws ArgumentError S.profiles(nlp_scaling_method="unknown")
    end
end
