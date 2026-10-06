module IVRLoadPowerStudyTests
using Test,FormulationLab,JSON3
include("../examples/benchmark_ivr_load_power_lifting.jl")
const L=IVRLoadPowerStudy
changed(a,b)=Set(k for k in fieldnames(IVRNLPOptions) if JSON3.write(getfield(a,k))!=JSON3.write(getfield(b,k)))
@testset "Load-power timing pairs isolate the representation and physical contract" begin
    net=first(L.T.scenario(L.P.ivr_compiler_case(conductors=4,segments=4);load_law=:voltage_dependent,filter_level=:high))
    original=deepcopy(net)
    for work in (:quadratic_cost,:exchange_tracking),policy in ("none","gradient-based")
        ps=L.profiles(net,work;exchange_target_W=500.,nlp_scaling_method=policy)
        @test length(ps)==12 && allunique(p.name for p in ps)
        for k in 1:6
            @test changed(ps[k].options,ps[k+6].options)==Set([:load_power_lifting])
            @test ps[k].solver_options==ps[k+6].solver_options
            @test ps[k].formulation_name==ps[k+6].formulation_name
            @test ps[k].options.transformer_nameplate==ps[k+6].options.transformer_nameplate==:bmopftools
        end
        mktempdir() do dir
            start=L.T.M.E.S.U.G.H.S.L.start_point(net)
            report=L.P.benchmark(net,joinpath(dir,"smoke.json");candidates=ps,repetitions=1,checkpoint=:sweep,initial_point=start)
            @test report["reference_transformer_nameplate"]=="bmopftools"
            @test report["ranking"]["objective_comparable"]
            @test length(report["ranking"]["eligible"])==12
            @test all(p["warmup"]["accepted"] && only(p["trials"])["accepted"] for p in report["profiles"])
            mismatch=[ps[1],merge(ps[2],(;options=IVRNLPOptions(;(k=>(k==:transformer_nameplate ? :ignore : getfield(ps[2].options,k)) for k in fieldnames(IVRNLPOptions))...)))]
            @test_throws ArgumentError L.P.benchmark(net,joinpath(dir,"bad.json");candidates=mismatch)
            @test !isfile(joinpath(dir,"bad.json"))
        end
        empty!(ps[1].options.power_terms);empty!(ps[1].options.generator_power_bases)
        @test all(!isempty(p.options.power_terms) && !isempty(p.options.generator_power_bases) for p in ps[2:end])
    end
    @test net==original
end
end
