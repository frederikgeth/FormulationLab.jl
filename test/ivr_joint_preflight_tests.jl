module IVRJointPreflightTests
using Test, FormulationLab, JSON3, SHA
include("../examples/benchmark_ivr_joint_reductions.jl")
include("sdp_transformer_fixtures.jl")
const J=IVRJointReductionStudy
load(path)=JSON3.read(read(path,String),Dict{String,Any})
save(path,x)=J.E.save(path,x)

@testset "Joint preflight admission inspects every required artifact" begin
    net=_sdp_tx_case("delta_wye")
    net["bus"]["t"]["vpn_min"]=fill(10.,3)
    net["load"]=Dict("zero"=>Dict("bus"=>"t","terminal_map"=>["a","b","c","n"],
        "configuration"=>"WYE","p_nom"=>zeros(3),"q_nom"=>zeros(3)),
        "positive"=>Dict("bus"=>"t","terminal_map"=>["a","b","c","n"],
        "configuration"=>"WYE","p_nom"=>fill(100.,3),"q_nom"=>fill(10.,3)))
    net["transformer"]["delta_wye"]["tx"]["s_rating"]=1e3
    net,_=J.E.T.scenario(net;filter_level=:low,load_law=:voltage_dependent)
    mktempdir() do dir
        input=joinpath(dir,"input.json");save(input,net)
        folder=joinpath(dir,"preflight");pre=J.Z.run(input,folder)
        @test pre["all_trials_accepted"] && pre["objectives_comparable"]
        validation=J.validate_preflight(folder)
        @test validation.passed && validation.trial_count==16
        @test !validation.timing_eligible && !validation.complete_input_coverage
        @test length(validation.artifact_sha256)==66 # report + input + 4 artifacts/trial
        @test all(bytes2hex(sha256(read(p)))==hash for (p,hash) in validation.artifact_sha256)
        @test J.validate_preflight(folder).artifact_sha256==validation.artifact_sha256
        reportpath=joinpath(folder,"REPORT.json")
        pre=load(reportpath)
        function reject_report(edit)
            bad=deepcopy(pre);edit(bad);save(reportpath,bad)
            @test_throws ArgumentError J.validate_preflight(folder)
            save(reportpath,pre)
        end
        reject_report(r->empty!(r["trials"]))
        reject_report(r->pop!(r["trials"]))
        reject_report(r->push!(r["trials"],deepcopy(first(r["trials"]))))
        reject_report(r->(r["trials"][2]=deepcopy(first(r["trials"]))))
        reject_report(r->reverse!(r["trials"]))
        reject_report(r->(r["pending_trial"]="unfinished"))
        reject_report(r->(r["source_sha256"]="0"^64))
        reject_report(r->(r["exchange_target_W"]+=1.))
        reject_report(r->(r["trials"][2]["anchor_in_profile"]=nothing))
        reject_report(r->(r["trials"][1]["solver_options"]["tol"]=1e-3))
        reject_report(r->(r["trials"][1]["options"]["s_base"]=1e3))
        reject_report(r->delete!(r["trials"][1]["options"],"fixed_observation_elimination"))
        reject_report(r->(r["trials"][1]["physical_power_objective"]+=1.))
        for key in ("accepted","start_representable","physical_passed","own_model_passed",
                    "full_model_passed","objective_reconciled","native_reader_equal",
                    "complete_emitted_coverage","complete_declared_bound_coverage")
            reject_report(r->(r["trials"][1][key]=false))
        end
        stem=joinpath(folder,"quadratic_cost__"*first(J.arms()))
        function reject_artifact(edit,suffix;result=false)
            path=stem*suffix;original=read(path)
            data=result ? read_result(path) : load(path);edit(data)
            result ? write_result(data,path) : save(path,data)
            @test_throws ArgumentError J.validate_preflight(folder)
            write(path,original)
        end
        reject_artifact(r->(r["variables"]+=1),".trial.json")
        reject_artifact(r->(r["covered_constraint_count"]-=1),".inventory.json")
        reject_artifact(r->pop!(r["matched"]),".bounds.json")
        reject_artifact(r->(r["objective"]+=1),".result.json";result=true)
        reject_artifact(r->(r["_formulationlab"]["network_sha256"]="0"^64),".result.json";result=true)
        # Modify a non-anchor export to test cross-profile path/start consistency.
        stem=joinpath(folder,"quadratic_cost__"*J.arms()[2])
        reject_artifact(r->delete!(r["bus"],first(keys(r["bus"]))),".result.json";result=true)
        reject_artifact(r->(first(values(first(values(r["initialisation"]))))["vr_init"]+=1),".result.json";result=true)
        path=stem*".bounds.json";bytes=read(path);rm(path)
        @test_throws ArgumentError J.validate_preflight(folder)
        write(path,bytes)
        # The timing entry point must fail before creating output on bad evidence.
        bad=deepcopy(pre);empty!(bad["trials"]);save(reportpath,bad)
        output=joinpath(dir,"must_not_exist")
        @test_throws ArgumentError J.run_timing(folder,output,"exploration")
        @test !ispath(output)
        save(reportpath,pre)
        @test J.validate_preflight(folder).passed
        # Retain a reproducible diagnostic fixture only when explicitly requested
        # by the external correctness driver; normal tests use a temporary folder.
        if haskey(ENV,"FORMULATIONLAB_PREFLIGHT_EVIDENCE")
            target=ENV["FORMULATIONLAB_PREFLIGHT_EVIDENCE"]
            @test !ispath(target)
            cp(folder,target)
            archived_input=joinpath(dirname(target),"INPUT.json")
            cp(input,archived_input)
            archived=load(joinpath(target,"REPORT.json"));archived["input"]=archived_input
            save(joinpath(target,"REPORT.json"),archived)
            @test J.validate_preflight(target).passed
        end
    end
end
end
