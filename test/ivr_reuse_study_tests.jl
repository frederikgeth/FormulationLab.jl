using Test, FormulationLab, JSON3
include("../examples/benchmark_ivr_reuse.jl")

@testset "Sequence ranking compares objectives within each scenario" begin
    scenario(t,obj;accepted=true)=Dict("ipopt_wall_s"=>t,"objective"=>obj,"accepted"=>accepted)
    trial(ts;accepted=true)=Dict("scenarios"=>ts,"accepted"=>accepted,"total_ipopt_wall_s"=>sum(x["ipopt_wall_s"] for x in ts))
    row(name,ts;warm=true)=Dict("name"=>name,"warmup"=>Dict("accepted"=>warm),"trials"=>ts)
    a=trial([scenario(1.,10.),scenario(2.,20.)]);b=trial([scenario(.5,10.),scenario(1.,20.)])
    rows=[row("slow",[deepcopy(a),deepcopy(a)]),row("fast",[deepcopy(b),deepcopy(b)]),
          row("partial",[trial([scenario(.01,10.)]),trial([scenario(.01,10.)])]),
          row("failed",[trial([scenario(.01,10.),scenario(.01,20.)];accepted=false),deepcopy(b)]),
          row("warm_failed",[deepcopy(b),deepcopy(b)];warm=false)]
    r=IVRReuseStudy.rank_workflows(rows,2,2)
    @test r["objective_comparable"] && r["fastest_ipopt"]=="fast"
    @test Set(x["name"] for x in r["eligible"])==Set(["slow","fast"])
    rows[2]["trials"][2]["scenarios"][2]["objective"]=21.
    r=IVRReuseStudy.rank_workflows(rows,2,2)
    @test !r["objective_comparable"] && r["fastest_ipopt"]===nothing
    @test r["scenario_objective_comparable"]==[true,false]
    @test isempty(IVRReuseStudy.rank_workflows(rows[3:5],2,2)["eligible"])
end

@testset "Independent updates, explicit starts and fixed-AMD model reuse" begin
    net=IVRReuseStudy.P.ivr_compiler_case(conductors=2,segments=4)
    delete!(net["load"],"d1");delete!(net["load"],"d3")
    net["generator"]=Dict("der"=>Dict("bus"=>"b4","terminal_map"=>["a","n"],
        "configuration"=>"SINGLE_PHASE","p_min"=>[0.],"p_max"=>[600.],
        "q_min"=>[0.],"q_max"=>[0.],"s_max"=>[1000.],"i_max"=>[200.,200.],"cost"=>[.2]))
    schedule=[(label="base",loads=Dict{String,Any}(),generators=Dict{String,Any}()),
        (label="price",loads=Dict("d2"=>(p=[400.],q=[100.])),generators=Dict("der"=>(cost=[2.],))),
        (label="fixed_zero",loads=Dict{String,Any}(),generators=Dict("der"=>(p_max=[0.],))),
        (label="restore",loads=Dict{String,Any}(),generators=Dict("der"=>(p_max=[600.],cost=[.2])))]
    original=deepcopy(net);inputs=IVRReuseStudy.scenario_inputs(net,schedule)
    @test net==original
    @test inputs[3]["load"]["d2"]["p_nom"]==[400.]
    @test inputs[3]["generator"]["der"]["cost"]==[2.]
    @test inputs[4]["generator"]["der"]["p_max"]==[600.]
    @test_throws ArgumentError IVRReuseStudy.scenario_inputs(net,[(label="bad",loads=Dict("d2"=>(x=[1.],)),generators=Dict())])
    candidates=IVRReuseStudy.workflows()
    mktempdir() do directory
        output=joinpath(directory,"reuse.json")
        report=IVRReuseStudy.benchmark(net,schedule,output;repetitions=2,candidates,
            solver_options=merge(IVRReuseStudy.SETTINGS,(obj_scaling_factor=1000.,)))
        saved=JSON3.read(read(output,String))
        @test length(saved.profiles)==8
        @test report["orders"][2]==reverse(report["orders"][1])
        @test report["ranking"]["objective_comparable"]
        @test length(report["ranking"]["eligible"])==8
        for r in report["profiles"]
            @test r["warmup"]["accepted"]
            for t in r["trials"]
                @test t["accepted"] && t["completed_N"]==4
                @test t["scenario_model_builds"]==(r["reuse"] ? 1 : 4)
                @test t["solver_options"]["mumps_pivot_order"]==0 && t["solver_options"]["warm_start_init_point"]=="no"
                @test all(x->x["physical_passed"] && x["anchor_passed"] && x["fresh_same_formulation_passed"] &&
                    x["variable_identity_preserved"] && x["start_matches_policy"],t["scenarios"])
                @test t["scenarios"][1]["start_source"]=="fixed"
                if r["start"]==:fixed
                    @test all(x->x["start_sha256"]==t["scenarios"][1]["start_sha256"],t["scenarios"])
                else
                    @test all(k->t["scenarios"][k]["start_sha256"]==t["scenarios"][k-1]["solution_sha256"],2:4)
                end
            end
        end
        @test net==original
        @test_throws ArgumentError IVRReuseStudy.benchmark(net,[],output)
        @test_throws ArgumentError IVRReuseStudy.benchmark(net,schedule,output;repetitions=0)
    end
end
