using Test, FormulationLab, JSON3, SHA
include("../examples/benchmark_ivr_feeder_lifting.jl")
@testset "External lifting transfer provenance and admission" begin
    F=IVRFeederLiftingStudy
    @test all(p->p.options.objective==:feasibility && p.options.ground_scaling==:voltage &&
        p.solver_options.mumps_pivot_order==0,F.profiles())
    mktempdir() do dir
        input=joinpath(dir,"input.json");output=joinpath(dir,"study.json")
        net=F.L.case(segments=4,charged=true,tight=true)
        net["_simplification_log"]=Dict("note"=>"legacy provenance only")
        write(input,JSON3.write(net));before=read(input)
        report=F.benchmark(input,output)
        @test read(input)==before
        @test report["source_unchanged"] && report["network_unchanged"] && report["position_balanced"]
        @test length(report["ranking"]["eligible"])==6
        @test report["feeder_input"]["source_sha256"]==bytes2hex(sha256(before))
        @test report["feeder_input"]["detached_provenance_paths"]==["/_simplification_log"]
        @test all(p->p["warmup"]["accepted"] && all(t->t["accepted"],p["trials"]),report["profiles"])
        owned=JSON3.read(read(output*".input.json",String),Dict{String,Any})
        @test pop!(owned,"_meta")["detached_legacy_provenance"]["/_simplification_log"]==pop!(net,"_simplification_log")
        @test owned==net
        @test_throws ArgumentError F.benchmark(input,input)
        @test_throws ArgumentError F.benchmark(input,output;repetitions=6)
        symlink(input,joinpath(dir,"alias.json"))
        @test_throws ArgumentError F.benchmark(input,joinpath(dir,"alias.json"))
        # Unsupported physics is reported before timing; no silent simplification.
        net["unknown_physical_element"]=Dict("x"=>Dict("bus"=>"b0"))
        write(input,JSON3.write(net));failed_before=read(input)
        failed=F.benchmark(input,output)
        @test failed["status"]=="preflight_failed"
        @test failed["ranking"]===nothing && isempty(failed["profiles"])
        @test !failed["feeder_input"]["preflight"].passed
        @test read(input)==failed_before
    end
end
