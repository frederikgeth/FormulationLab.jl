using Test, JSON3
include("../examples/benchmark_ivr_transformer_currents.jl")
@testset "Matched transformer-current experiment" begin
    S=IVRTransformerCurrentStudy
    net=S.L.case(segments=4,charged=true,transformers=true,tight=true);original=deepcopy(net)
    @test_throws ArgumentError S.benchmark(net,"unused.json";repetitions=4)
    mktempdir() do dir
        path=joinpath(dir,"study.json");report=S.benchmark(net,path)
        @test report["position_balanced"] && report["shared_physical_start"]
        @test length(report["ranking"]["eligible"])==4
        @test all(r->r["warmup"]["accepted"] && all(t->t["accepted"],r["trials"]),report["profiles"])
        @test net==original
        @test JSON3.read(read(path*".input.json",String),Dict{String,Any})==original
        for row in report["profiles"]
            count=row["options"].device_elimination==:off ? 0 : 1
            @test all(t->t["device_elimination"].eliminated_complex_coordinates==count,row["trials"])
        end
    end
end
