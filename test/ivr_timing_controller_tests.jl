module IVRTimingControllerTests
using Test,JSON3
include("../examples/ivr_timing_controller.jl")
const C=IVRTimingController
function fixture()
    arms=[Dict("name"=>n,"options"=>Dict("objective"=>"power","power_terms"=>[])) for n in ("control","candidate")]
    orders=[[1,2],[2,1]];events=Any[]
    for (sweep,order) in enumerate(vcat([[1,2]],orders)), (position,i) in enumerate(order)
        push!(events,Dict("sequence"=>length(events)+1,"stage"=>sweep==1 ? "warmup" : "measurement",
            "sweep"=>sweep-1,"position"=>position,"arm_index"=>i,"arm"=>arms[i]["name"]))
    end
    Dict("schema"=>"FormulationLab.native_timing_job.v1","timing_authorized"=>false,"execution_ready"=>false,
        "admission"=>Dict("correctness_qualified"=>true,"arms"=>arms,"solver_settings"=>[Dict(),Dict()],
            "sweeps"=>orders,"counts"=>Dict("warmup"=>2,"measured"=>4,"total"=>6)),
        "reference"=>Dict("objective"=>"power","power_terms"=>[]),"events"=>events)
end
function fake_row(;mode="native")
    Dict{String,Any}((k=>true for k in C.GATES)...,"objective"=>1.,
        "timing"=>Dict{String,Any}("schema"=>"FormulationLab.native_trial_timing.v1","mode"=>mode,
            "sample_status"=>"completed","native_ipopt_wall_s"=>1.,"clock_error"=>nothing))
end
accepted_group(x)=Dict("passed"=>true)

@testset "Finite order and fail-closed preconditions, no optimizer" begin
    j=fixture();@test C.validate_job(j)==2
    calls=Ref(0);solve=(e,s)->(calls[]+=1;(fake_row(),:point,:shape))
    mktempdir() do d
        protected=joinpath(d,"archive");mkdir(protected)
        alias=joinpath(d,"alias");symlink(protected,alias)
        @test_throws ArgumentError C.check_output(joinpath(alias,"runs"),[protected])
        folder=joinpath(d,"refused")
        @test_throws ArgumentError C.run_schedule(j,folder,solve,accepted_group;mode=:native)
        @test calls[]==0 && !ispath(folder)
        for bad in (:event,:count,:arm,:objective)
            q=deepcopy(j)
            if bad==:event;q["events"][3]["arm_index"]=2
            elseif bad==:count;q["admission"]["counts"]["total"]=7
            elseif bad==:arm;q["admission"]["arms"][2]["name"]="control"
            else;q["reference"]["power_terms"]=["changed"]
            end
            @test_throws ArgumentError C.run_schedule(q,folder,solve,accepted_group)
            @test calls[]==0 && !ispath(folder)
        end
    end
end

@testset "Synthetic event callbacks never constitute a timing campaign" begin
    mktempdir() do d
        visited=Int[]
        solve=(e,s)->(push!(visited,e["arm_index"]);(fake_row(;mode="synthetic"),:point,:shape))
        r=C.run_schedule(fixture(),joinpath(d,"synthetic"),solve,accepted_group;mode=:synthetic)
        @test visited==[1,2,1,2,2,1]
        @test r["status"]=="completed" && r["pending_event"]===nothing
        @test r["correctness_admitted"] && !r["native_samples_complete"]
        @test !r["provisional_admitted"] && !r["campaign_eligible"] && r["ranking"]===nothing
        @test count(t->t["excluded_warmup"],r["trials"])==2
        @test length(r["groups"])==3
        # Fabricated rows only; even a complete native-mode worker is provisional.
        good=C.run_schedule(fixture(),joinpath(d,"fake_native"),(e,s)->(fake_row(),:point,:shape),accepted_group;
            mode=:native,timing_authorized=true)
        @test good["provisional_admitted"] && !good["campaign_eligible"] && good["ranking"]===nothing
    end
end

@testset "Failures and cross-arm disagreement retain all planned calls" begin
    for failure in (:warmup,:endpoint,:cross,:exception,:clock,:synthetic_sample)
        mktempdir() do d
            seen=Int[];groups=Ref(0)
            solve=function(e,s)
                push!(seen,e["sequence"])
                failure==:exception && e["sequence"]==3 && error("manufactured solver callback failure")
                row=fake_row()
                if (failure==:warmup && e["sequence"]==1) || (failure==:endpoint && e["sequence"]==4)
                    row["physical_passed"]=false
                elseif failure==:clock && e["sequence"]==4
                    row["timing"]["native_ipopt_wall_s"]=NaN
                elseif failure==:synthetic_sample && e["sequence"]==4
                    row["timing"]["mode"]="synthetic"
                end
                row,:point,:shape
            end
            compare=x->(groups[]+=1;Dict("passed"=>!(failure==:cross && groups[]==2)))
            # Fake rows only: this exercises native admission logic without a clock or solver.
            r=C.run_schedule(fixture(),joinpath(d,"case"),solve,compare;mode=:native,timing_authorized=true)
            @test seen==collect(1:6)
            @test r["status"]=="completed" && length(r["trials"])==6
            @test !r["provisional_admitted"] && !r["campaign_eligible"]
            @test r["ranking"]===nothing
        end
    end
end

@testset "Every mandatory correctness gate and interruption remains explicit" begin
    for key in C.GATES
        row=fake_row();row[key]=false;@test !C.row_accepted(row)
        delete!(row,key);@test !C.row_accepted(row)
    end
    for x in (nothing,NaN,Inf,0.,-1.,true)
        row=fake_row();row["timing"]["native_ipopt_wall_s"]=x
        @test !C.native_sample_valid(row)
    end
    mktempdir() do d
        count=Ref(0);folder=joinpath(d,"interrupted")
        solve=(e,s)->(count[]+=1;count[]==2 && throw(InterruptException());(fake_row(),:point,:shape))
        @test_throws InterruptException C.run_schedule(fixture(),folder,solve,accepted_group)
        r=JSON3.read(read(joinpath(folder,"REPORT.json"),String),Dict{String,Any})
        @test r["status"]=="interrupted" && r["pending_event"]["sequence"]==2
        @test count[]==2 && length(r["trials"])==1 && !r["campaign_eligible"]
    end
end
end
