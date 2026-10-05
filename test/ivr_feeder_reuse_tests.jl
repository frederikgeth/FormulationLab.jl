using Test, FormulationLab, JSON3
include("../examples/benchmark_ivr_feeder_reuse.jl")
@testset "External feeder demand sequence and provenance" begin
    F=IVRFeederReuseStudy
    net=F.R.P.ivr_compiler_case(conductors=2,segments=2)
    net["load"]["d2"]["model"]="constant_impedance"
    original=deepcopy(net);s=F.demand_schedule(net)
    @test net==original
    @test length(s)==4 && s[1].loads==s[2].loads==s[4].loads
    @test s[3].loads["d1"].p==.9net["load"]["d1"]["p_nom"]
    @test all(x->!haskey(x.loads,"d2") && isempty(x.generators),s)
    inputs=F.R.scenario_inputs(net,s)
    @test all(x->x["load"]["d2"]==original["load"]["d2"],inputs)
    @test inputs[4]==original
    @test_throws ArgumentError F.demand_schedule(net;factors=(NaN,))
    @test_throws ArgumentError F.demand_schedule(net;factors=(-1.,),labels=("bad",))
    @test_throws ArgumentError F.demand_schedule(net;factors=(true,),labels=("bad",))
    @test_throws ArgumentError F.demand_schedule(net;factors=(1.,1.),labels=("same","same"))
    @test_throws ArgumentError F.demand_schedule(Dict("load"=>Dict()))
    candidates=F.reused_workflows()
    @test length(candidates)==4 && all(w->w.reuse && w.profile.options.objective==:feasibility,candidates)
    mktempdir() do dir
        input=joinpath(dir,"input.json");output=joinpath(dir,"study.json")
        net=F.R.P.ivr_compiler_case(conductors=2,segments=2)
        net["_simplification_log"]=Dict("note"=>"legacy provenance only")
        write(input,JSON3.write(net));before=read(input)
        report=F.benchmark(input,output;repetitions=8)
        @test read(input)==before
        @test report["ranking"]["objective_comparable"] && length(report["ranking"]["eligible"])==4
        @test all(p->p["warmup"]["accepted"] && all(t->t["accepted"],p["trials"]),report["profiles"])
        @test report["feeder_input"]["detached_provenance_paths"]==["/_simplification_log"]
        @test report["feeder_input"]["updated_load_ids"]==["d1","d2"]
        @test isempty(report["feeder_input"]["unchanged_load_ids"])
        @test startswith(report["feeder_input"]["accounting"]["note"],"Feasibility objective;")
        @test JSON3.read(read(output*".input.json",String)).source_sha256==report["source_sha256"]
        @test all(count(o->o[k]==w.name,report["orders"])==2 for w in candidates for k in 1:4)
        @test_throws ArgumentError F.benchmark(input,input)
        @test_throws ArgumentError F.benchmark(input,output;candidates=F.R.workflows())
        @test read(input)==before
    end
end
