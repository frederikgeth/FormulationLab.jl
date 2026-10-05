using Test, FormulationLab, JSON3
include("../examples/benchmark_ivr_profiles.jl")

@testset "Profile ranking excludes failure and incompatible objectives" begin
    trial(build,solve;accepted=true,objective=0.,ipopt=solve)=Dict{String,Any}("build_s"=>build,"solve_s"=>solve,
        "ipopt_wall_s"=>ipopt,"build_bytes"=>100,"accepted"=>accepted,"objective"=>objective)
    row(name,trials;warm=true)=Dict("name"=>name,"warmup"=>Dict("accepted"=>warm),"trials"=>trials)
    rows=[row("total",[trial(1.,2.),trial(1.,2.)]),
          row("solve",[trial(4.,1.),trial(4.,1.)]),
          row("ipopt",[trial(100.,3.;ipopt=.5),trial(100.,3.;ipopt=.5)]),
          row("failed_fast",[trial(.01,.01),trial(.01,.01;accepted=false)]),
          row("missing",[trial(.01,.01)]),
          row("warmup_failed",[trial(.01,.01),trial(.01,.01)];warm=false)]
    r=IVRProfileStudy.rank_profiles(rows,2)
    @test r["fastest_total"]=="total"
    @test r["fastest_solve"]=="solve"
    @test Set(x["name"] for x in r["eligible"])==Set(["total","solve","ipopt"])
    @test r["objective_comparable"]
    @test r["fastest_ipopt"]=="ipopt"
    @test r["primary_metric"]=="ipopt_wall_s"
    @test r["ipopt_timing_complete"]
    rows[2]["trials"][1]["objective"]=1.
    r=IVRProfileStudy.rank_profiles(rows,2)
    @test !r["objective_comparable"]
    @test r["fastest_total"]===nothing && r["fastest_solve"]===nothing && r["fastest_ipopt"]===nothing
    r=IVRProfileStudy.rank_profiles(rows[4:6],2)
    @test isempty(r["eligible"]) && r["fastest_total"]===nothing
    for timing in (nothing,NaN,Inf,-1.)
        rows[1]["trials"][1]["ipopt_wall_s"]=timing
        r=IVRProfileStudy.rank_profiles(rows[[1,3]],2)
        @test !r["ipopt_timing_complete"] && r["fastest_ipopt"]===nothing
    end
    delete!(rows[1]["trials"][1],"ipopt_wall_s")
    @test IVRProfileStudy.rank_profiles(rows[[1,3]],2)["fastest_ipopt"]===nothing
end

@testset "Measured profile records preserve raw evidence and mapping gates" begin
    net=IVRProfileStudy.ivr_compiler_case(conductors=2,segments=2)
    candidates=IVRProfileStudy.profiles()[[1,3,6]]
    original=deepcopy(net)
    mktempdir() do directory
        output=joinpath(directory,"profiles.json")
        report=IVRProfileStudy.benchmark(net,output;repetitions=2,candidates)
        saved=JSON3.read(read(output,String))
        @test length(saved.profiles)==3
        @test length(report["orders"])==2
        @test report["orders"][2]==reverse(report["orders"][1])
        @test report["anchor_profile"]=="full"
        @test report["ranking"]["objective_comparable"]
        @test length(report["ranking"]["eligible"])==3
        @test report["ranking"]["fastest_ipopt"]!==nothing
        @test report["primary_metric"]=="ipopt_wall_s"
        for row in report["profiles"]
            @test row["warmup"]["accepted"]
            @test all(t->isfinite(t["ipopt_wall_s"]) && 0 <= t["ipopt_wall_s"] <= t["solve_s"]+1e-3,row["trials"])
            @test length(row["trials"])==2
            @test all(t->t["accepted"]&&t["anchor_in_profile"]&&t["full_model_passed"],row["trials"])
        end
        @test net==original
        @test_throws ArgumentError IVRProfileStudy.benchmark(net,output;repetitions=0)
        @test_throws ArgumentError IVRProfileStudy.benchmark(net,output;candidates=[first(candidates),first(candidates)])
        @test_throws ArgumentError IVRProfileStudy.benchmark(net,output;candidates=[first(candidates),(name="cost",options=IVRNLPOptions(objective=:cost))])
    end
end
