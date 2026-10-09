#= Explicit source-root / B-or-C / instrumented-Ipopt arguments are required.
This manufactured four-call mini-schedule uses only a synthetic clock. It is not
one of the admitted network jobs and produces no performance evidence.
=#
using Test,FormulationLab,JSON3,Ipopt
include("../examples/ivr_timing_controller.jl")
include("sdp_transformer_fixtures.jl")
const C=IVRTimingController
length(ARGS)==3 || error("expected source root, B/C and instrumented Ipopt directory")
root,freeze,ipopt_copy=ARGS
realpath(dirname(dirname(pathof(Ipopt))))==realpath(ipopt_copy) || error("wrong Ipopt loaded")
json(x)=JSON3.read(JSON3.write(x),Dict{String,Any})

@testset "Complete synthetic worker and mutual membership: $freeze" begin
    loaded=C.A.load_preflight(root,freeze);P=loaded.executor
    mktempdir() do dir
        net=_sdp_tx_case("single_phase");_sdp_zload!(net,"d",["p","n"],.01-.002im)
        o=IVRNLPOptions(s_base=1e4,transformer_nameplate=:bmopftools,
            transformer_scaling=:nominal,ground_scaling=:voltage,row_scaling=:composed)
        input=joinpath(dir,"input.json");P.save(input,net)
        prepared=joinpath(dir,"prepared")
        pre=P.prepare(input,prepared;common=o,exchange_target_W=100.)
        @test pre["ready"]
        workloads=JSON3.read(read(joinpath(prepared,"WORKLOADS.json"),String),Vector{Dict{String,Any}})
        w=first(workloads);arms=w["candidates"][1:2]
        events=Any[]
        for (sweep,order) in enumerate([[1,2],[2,1]]), (position,i) in enumerate(order)
            push!(events,Dict("sequence"=>length(events)+1,"stage"=>sweep==1 ? "warmup" : "measurement",
                "sweep"=>sweep-1,"position"=>position,"arm_index"=>i,"arm"=>arms[i]["name"]))
        end
        job=Dict("schema"=>"FormulationLab.native_timing_job.v1","timing_authorized"=>false,"execution_ready"=>false,
            "admission"=>Dict("correctness_qualified"=>true,"source_archive"=>root,"freeze"=>freeze,
                "inputs"=>Dict("preparation"=>joinpath(prepared,"PREPARATION.json"),
                    "preparation_sha256"=>P.hashfile(joinpath(prepared,"PREPARATION.json"))),
                "arms"=>arms,"solver_settings"=>[json(P.SETTINGS),json(P.SETTINGS)],"sweeps"=>[[2,1]],
                "counts"=>Dict("warmup"=>2,"measured"=>2,"total"=>4)),
            "reference"=>w["reference"],"tolerances"=>json(P.TOLERANCES),
            "preparation_files_sha256"=>pre["files"],"events"=>events)
        folder=joinpath(dir,"worker");ticks=Ref(0)
        report=C.run_job(job,folder;mode=:synthetic,synthetic_clock=()->(ticks[]+=100))
        @test report["status"]=="completed" && report["correctness_admitted"]
        @test !report["provisional_admitted"] && !report["campaign_eligible"]
        @test ticks[]==800
        @test [t["event"]["arm_index"] for t in report["trials"]]==[1,2,2,1]
        @test all(t->t["trial"]["timing"]["mode"]=="synthetic" &&
            t["trial"]["timing"]["native_ipopt_wall_s"]===nothing,report["trials"])
        @test all(g->all(g["comparison"]["control_in_each_arm"]) &&
            all(g["comparison"]["each_arm_in_control"]),report["groups"])
        @test count(t->t["excluded_warmup"],report["trials"])==2
        @test all(isfile(joinpath(folder,"event_"*lpad(string(i),4,'0')*".point.json")) for i in 1:4)
        @test P.readjson(joinpath(folder,"REPORT.json"))["correctness_admitted"]
        @test report["worker_pid"]==getpid() && report["julia_threads"]==report["blas_threads"]==1
        @test_throws ArgumentError C.run_job(job,folder;mode=:synthetic,synthetic_clock=()->1)

        # Recheck actual accepted points; then corrupt one condition at a time.
        models=[build_opf(net,IVRNLP(P.read_options(a["options"]))) for a in arms]
        outcomes=[(report["trials"][i]["trial"],P.read_point(P.readjson(joinpath(folder,
            "event_"*lpad(string(i),4,'0')*".point.json"))),:same_export_shape) for i in 1:2]
        tol=job["tolerances"]
        @test C.compare_group(models,outcomes,tol)["passed"]
        bad=deepcopy(outcomes);bad[2][1]["objective"]+=1
        @test !C.compare_group(models,bad,tol)["passed"]
        bad=copy(outcomes);bad[2]=(bad[2][1],bad[2][2],:different_export_shape)
        @test !C.compare_group(models,bad,tol)["passed"]
        bad=deepcopy(outcomes);point=bad[2][2];voltage=copy(point.voltage)
        voltage[first(keys(voltage))]+=100
        bad[2]=(bad[2][1],ACPoint(voltage=voltage,currents=point.currents),bad[2][3])
        @test !C.compare_group(models,bad,tol)["passed"]
        @test P.hashfile(input)==pre["source_sha256"]
    end
end
