module IVRCandidateFollowupTests
using Test,FormulationLab,JSON3
include("../examples/ivr_candidate_followup.jl")
include("sdp_transformer_fixtures.jl")
const C=IVRCandidateFollowup
const P=C.P
json(x)=JSON3.read(JSON3.write(x),Dict{String,Any})
function common()
    IVRNLPOptions(s_base=1e4,transformer_nameplate=:bmopftools,transformer_scaling=:nominal,
        ground_scaling=:voltage,row_scaling=:composed,lifting=:off,lifted_power_base=500.,
        load_power_lifting=true,observation_sharing=:signed)
end
function declared(net,kind)
    w=P.W.profiles(net,kind;common=common(),exchange_target_W=100.)
    json((;kind,reference=P.record(w.reference),candidates=[(;name=p.name,options=P.record(p.options)) for p in w.candidates]))
end
function passing_report()
    trials=[Dict{String,Any}("workload"=>w,"profile"=>p,"objective"=>1.,"anchor_in_profile"=>true,
        (k=>true for k in C.GATES)...) for w in C.WORKLOADS for p in C.PROFILES]
    Dict{String,Any}("schema"=>"FormulationLab.transfer_preflight.v1","pending_trial"=>nothing,
        "inputs_unchanged"=>true,"trials"=>trials,"all_trials_accepted"=>true,"objectives_comparable"=>true)
end
@testset "Admission never replaces incomplete or failed baseline outcomes" begin
    r=passing_report();@test C.admission(r).eligible
    for key in C.GATES
        q=deepcopy(r);q["trials"][1][key]=false;@test !C.admission(q).eligible
        delete!(q["trials"][1],key);@test !C.admission(q).eligible
    end
    for key in ("all_trials_accepted","objectives_comparable","inputs_unchanged")
        q=deepcopy(r);q[key]=false;@test !C.admission(q).eligible
    end
    for change in (:duplicate,:missing,:wrong_objective,:null_objective,:pending,:refused)
        q=deepcopy(r)
        if change==:duplicate;q["trials"][2]=deepcopy(q["trials"][1])
        elseif change==:missing;pop!(q["trials"])
        elseif change==:wrong_objective;q["trials"][1]["objective"]=2.
        elseif change==:null_objective;q["trials"][1]["objective"]=nothing
        elseif change==:pending;q["pending_trial"]="next"
        else;q["preparation_refusal"]="invalid original";end
        @test !C.admission(q).eligible
    end
end
@testset "Finite contrasts preserve objectives and isolate one candidate" begin
    net=_sdp_tx_case("single_phase");_sdp_zload!(net,"d",["p","n"],.01-.002im)
    for kind in C.WORKLOADS
        w=declared(net,Symbol(kind));original=deepcopy(w)
        ps=C.candidate_pairs(w,json(P.SETTINGS));@test length(ps)==6 && w==original
        @test length(Set(x["name"] for x in ps))==6
        for x in ps
            a=x["control"]["options"];b=x["candidate"]["options"]
            changed=Set(k for k in keys(a) if a[k]!=b[k])
            expected=startswith(x["name"],"fixed_") ? Set(["fixed_bound_elimination"]) :
                x["name"]=="complex_sharing" ? Set(["observation_sharing"]) :
                x["name"]=="expression_support" ? Set(["series_selection"]) : Set{String}()
            @test changed==expected
            @test a["power_terms"]==b["power_terms"]==x["reference"]["power_terms"]
            @test P.solver_settings(x["control_solver"])["mumps_pivtol"]==1e-6
            solver_changed=Set(k for k in keys(x["control_solver"]) if x["control_solver"][k]!=x["candidate_solver"][k])
            @test solver_changed==(startswith(x["name"],"pivot_") ? Set(["mumps_pivtol"]) : Set{String}())
            @test !x["timing_eligible"]
        end
        raw=deepcopy(w["reference"]);delete!(raw,"fixed_bound_elimination")
        @test C.migrate_options(raw)["fixed_bound_elimination"]===false
        @test !haskey(raw,"fixed_bound_elimination")
        delete!(raw,"s_base");@test_throws ArgumentError C.migrate_options(raw)
        bad=deepcopy(w["reference"]);bad["fixed_bound_elimination"]=true
        @test_throws ArgumentError C.migrate_options(bad)
    end
    @test_throws ArgumentError P.W.profiles(net,:quadratic_cost;common=P.W.clone(common();fixed_bound_elimination=true))
end
@testset "Paired correctness execution and failed-primal retention" begin
    mktempdir() do dir
        net=_sdp_tx_case("single_phase");_sdp_zload!(net,"d",["p","n"],.01-.002im)
        w=declared(net,:quadratic_cost);pairs=C.candidate_pairs(w,json(P.SETTINGS))
        reference=build_opf(net,IVRNLP(P.read_options(w["reference"])))
        start=P.linear_start(reference);tol=json(P.TOLERANCES)
        invalid=deepcopy(first(pairs));invalid["candidate"]["options"]["power_terms"][1]["linear"]+=1.
        @test_throws ArgumentError C.run_pair(net,start,invalid,tol,joinpath(dir,"bad_objective"))
        invalid=deepcopy(first(pairs));invalid["candidate_solver"]["tol"]=1e-5
        @test_throws ArgumentError C.run_pair(net,start,invalid,tol,joinpath(dir,"bad_solver"))
        invalid=deepcopy(first(pairs));invalid["candidate"]["options"]["s_base"]*=2
        @test_throws ArgumentError C.run_pair(net,start,invalid,tol,joinpath(dir,"bad_options"))
        invalid=deepcopy(first(pairs))
        invalid["control"],invalid["candidate"]=invalid["candidate"],invalid["control"]
        @test_throws ArgumentError C.run_pair(net,start,invalid,tol,joinpath(dir,"reversed"))
        for x in pairs
            out=joinpath(dir,x["name"]);r=C.run_pair(net,start,x,tol,out)
            @test r["correctness_admitted"] && r["candidate_in_control"] && r["physical_export_shape_equal"]
            @test !r["timing_eligible"] && r["ranking"]===nothing
            @test P.readjson(joinpath(out,"REPORT.json"))==r
            @test P.readjson(joinpath(out,"control.trial.json"))==r["control"]
            @test P.readjson(joinpath(out,"candidate.trial.json"))==r["candidate"]
        end
        # A source supplying a fixed positive impedance load cannot satisfy
        # a negative active-power upper bound.
        bad=deepcopy(net)
        bad["voltage_source"]["s"]["p_max"]=[-1.]
        b=build_opf(bad,IVRNLP(P.read_options(w["reference"])))
        stem=joinpath(dir,"failed")
        row,point,shape=P.trial(bad,first(pairs)["control"],b,P.linear_start(b),nothing,stem,json(P.SETTINGS),tol;save_failed_primal=true)
        @test !row["accepted"] && point===nothing && shape===nothing
        @test haskey(row,"status") && row["failed_primal_available"]
        @test isfile(stem*".failed.result.json") && isfile(stem*".failed.point.json")
        @test P.readjson(stem*".failed.physical.json")["passed"]===false
    end
end
end
