"""Finite timing worker with complete correctness checks and provisional output.

No optimizer runs on inclusion. A worker never certifies campaign isolation or
publishes a ranking; a separate campaign audit must admit its entire output.
"""
module IVRTimingController
using JSON3, FormulationLab, JuMP, LinearAlgebra, SHA
include("ivr_timing_adapter.jl")
const A=IVRTimingAdapter
const GATES=("accepted","complete_declared_bound_coverage","complete_emitted_coverage",
    "start_representable","physical_passed","own_model_passed","full_model_passed",
    "objective_reconciled","native_reader_equal")
require(ok,message)=ok || throw(ArgumentError("timing controller: "*message))
finite_real(x)=x isa Real && !(x isa Bool) && isfinite(x)
json_safe(x::AbstractDict)=Dict(string(k)=>json_safe(v) for (k,v) in x)
json_safe(x::AbstractVector)=json_safe.(x)
json_safe(x::Tuple)=json_safe.(collect(x))
json_safe(x::NamedTuple)=Dict(string(k)=>json_safe(v) for (k,v) in pairs(x))
json_safe(x)=x isa Real && !isfinite(x) ? nothing : x

function destination(path)
    p=abspath(path);suffix=String[]
    while !ispath(p)
        pushfirst!(suffix,basename(p));p=dirname(p)
    end
    normpath(joinpath(realpath(p),suffix...))
end
function check_output(folder,protected=String[])
    require(!ispath(folder),"output must be a new directory")
    dest=destination(folder)
    for root in [dirname(@__DIR__);protected]
        root=realpath(root)
        require(dest!=root && !startswith(dest,root*"/"),"output lies inside protected source/preparation")
    end
end

function save(path,x)
    temporary=path*".tmp"
    # Invalid numerical diagnostics remain inadmissible and are encoded as JSON
    # null, rather than preventing the remaining planned failures from being saved.
    open(io->JSON3.write(io,json_safe(x)),temporary,"w")
    mv(temporary,path;force=true)
end

"""Validate the complete event order before creating any output or calling a solver."""
function validate_job(job)
    require(get(job,"schema",nothing)=="FormulationLab.native_timing_job.v1","unknown job schema")
    require(get(job,"timing_authorized",nothing)===false && get(job,"execution_ready",nothing)===false,
        "expected immutable preparation-only job")
    j=job["admission"];n=length(j["arms"])
    require(get(j,"correctness_qualified",false)===true,"missing prior correctness admission")
    require(n>0 && length(j["solver_settings"])==n,"incomplete arms/settings")
    names=[a["name"] for a in j["arms"]]
    require(length(unique(names))==n,"duplicate arm identity")
    require(job["reference"]["objective"]=="power" && all(a->a["options"]["objective"]=="power" &&
        a["options"]["power_terms"]==job["reference"]["power_terms"],j["arms"]),"objective semantics changed")
    expected=Any[]
    orders=collect(1:n) # Warmup order is independent of measured ordering.
    groups=vcat([orders],j["sweeps"])
    require(length(groups)>1,"empty measured schedule")
    for (group,order) in enumerate(groups)
        require(all(i->i isa Integer && !(i isa Bool),order) && sort(order)==collect(1:n),"invalid sweep permutation")
        for (position,i) in enumerate(order)
            push!(expected,Dict("sequence"=>length(expected)+1,"stage"=>group==1 ? "warmup" : "measurement",
                "sweep"=>group-1,"position"=>position,"arm_index"=>i,"arm"=>names[i]))
        end
    end
    require(job["events"]==expected,"event order differs from frozen schedule")
    require(j["counts"]==Dict("warmup"=>n,"measured"=>n*length(j["sweeps"]),"total"=>length(expected)),
        "call counts changed")
    n
end

row_accepted(row)=all(k->get(row,k,false)===true,GATES) &&
    get(row,"anchor_in_profile",nothing)!==false && !haskey(row,"error") && finite_real(get(row,"objective",nothing))
function native_sample_valid(row)
    timing=get(row,"timing",Dict())
    get(timing,"schema",nothing)=="FormulationLab.native_trial_timing.v1" &&
        get(timing,"mode",nothing)=="native" && get(timing,"sample_status",nothing)=="completed" &&
        get(timing,"clock_error",nothing)===nothing &&
        finite_real(get(timing,"native_ipopt_wall_s",nothing)) && timing["native_ipopt_wall_s"]>0
end

"""Execute every predeclared event, retaining failures and excluding all warmups.

`solve_event(event,stem)` returns (row,point,shape). `compare_group(outcomes)`
checks cross-model membership, export shape and objective comparability. These
callbacks allow solver-free controller tests; the concrete worker below supplies
the archived physical executor. Results remain provisional even when complete.
"""
function run_schedule(job,folder,solve_event,compare_group;mode=:disabled,timing_authorized=false)
    require(mode in (:disabled,:synthetic,:native),"unknown mode")
    require(mode!=:native || timing_authorized===true,"native measurement is not authorized")
    n=validate_job(job)
    check_output(folder)
    mkpath(folder)
    report=Dict{String,Any}("schema"=>"FormulationLab.native_timing_worker.v1","mode"=>string(mode),
        "status"=>"running","job"=>job,"trials"=>Any[],"groups"=>Any[],"pending_event"=>nothing,
        "correctness_admitted"=>false,"native_samples_complete"=>false,"provisional_admitted"=>false,
        "campaign_eligible"=>false,"ranking"=>nothing)
    path=joinpath(folder,"REPORT.json");save(path,report)
    outcomes=Dict{Int,Any}()
    try
        for event in job["events"]
            report["pending_event"]=event;save(path,report)
            stem=joinpath(folder,"event_"*lpad(string(event["sequence"]),4,'0'))
            result=try
                solve_event(event,stem)
            catch err
                err isa InterruptException && rethrow()
                (Dict{String,Any}("accepted"=>false,"error"=>sprint(showerror,err)),nothing,nothing)
            end
            row,point,shape=result
            entry=Dict("event"=>event,"trial"=>row,"excluded_warmup"=>event["stage"]=="warmup")
            save(stem*".trial.json",entry);push!(report["trials"],entry)
            outcomes[event["arm_index"]]=result
            if event["position"]==n
                ordered=[outcomes[i] for i in 1:n]
                detail=try
                    compare_group(ordered)
                catch err
                    err isa InterruptException && rethrow()
                    Dict("passed"=>false,"error"=>sprint(showerror,err))
                end
                accepted=all(x->row_accepted(x[1]),ordered) && get(detail,"passed",false)===true
                push!(report["groups"],Dict("stage"=>event["stage"],"sweep"=>event["sweep"],
                    "correctness_admitted"=>accepted,"comparison"=>detail))
                empty!(outcomes)
            end
            report["pending_event"]=nothing;save(path,report)
        end
        report["status"]="completed"
        report["correctness_admitted"]=all(g->g["correctness_admitted"],report["groups"])
        measured=filter(t->!t["excluded_warmup"],report["trials"])
        report["native_samples_complete"]=mode==:native && all(t->native_sample_valid(t["trial"]),measured)
        report["provisional_admitted"]=report["correctness_admitted"] && report["native_samples_complete"]
        save(path,report)
    catch err
        report["status"]=err isa InterruptException ? "interrupted" : "worker_error"
        report["error"]=sprint(showerror,err);save(path,report)
        rethrow()
    end
    report
end

"""Mutual membership against arm 1, independent of execution order."""
function compare_group(models,outcomes,tol)
    n=length(models)
    require(n==length(outcomes) && n>0,"comparison cardinality")
    rows=[x[1] for x in outcomes];points=[x[2] for x in outcomes];shapes=[x[3] for x in outcomes]
    if !all(row_accepted,rows) || any(isnothing,points) || any(isnothing,shapes)
        return Dict("passed"=>false,"reason"=>"missing or unaccepted endpoint")
    end
    forward=[ivr_nlp_point_report(models[i],points[1];atol=tol["model_pu"]).passed for i in 1:n]
    reverse=[ivr_nlp_point_report(models[1],points[i];atol=tol["model_pu"]).passed for i in 1:n]
    shape_equal=all(s->isequal(s,shapes[1]),shapes)
    objectives=all(row->isapprox(row["objective"],rows[1]["objective"];
        atol=tol["objective_atol"],rtol=tol["objective_rtol"]),rows)
    Dict("passed"=>all(forward) && all(reverse) && shape_equal && objectives,
        "control_in_each_arm"=>forward,"each_arm_in_control"=>reverse,
        "physical_export_shape_equal"=>shape_equal,"objectives_comparable"=>objectives)
end

"""Concrete worker; timing authorization is necessary but not campaign admission.

The caller must first authenticate the job and its complete execution freeze.
This worker loads the exact archived compiler and keeps every optimizer call in
the declared order. Warmups exercise the same timer path but are always excluded
from comparison, including when their raw samples are retained.
"""
function run_job(job,folder;mode=:disabled,timing_authorized=false,synthetic_clock=nothing)
    require(mode in (:disabled,:synthetic,:native),"unknown mode")
    require(mode!=:native || timing_authorized===true,"native measurement is not authorized")
    require(mode==:synthetic ? synthetic_clock!==nothing : synthetic_clock===nothing,"clock/mode mismatch")
    require(Threads.nthreads()==1,"one Julia thread required")
    j=job["admission"]
    check_output(folder,[j["source_archive"],dirname(j["inputs"]["preparation"])])
    validate_job(job)
    loaded=A.load_preflight(j["source_archive"],j["freeze"]);P=loaded.executor
    # Invoke newly loaded methods in their definition world.
    Base.invokelatest() do
        prepared=dirname(j["inputs"]["preparation"])
        pre=P.load_prepared(prepared,j["inputs"]["preparation_sha256"])
        require(pre["ready"]===true && pre["files"]==job["preparation_files_sha256"],"prepared inputs changed")
        net=P.readjson(joinpath(prepared,"COMPILER_INPUT.json"))
        start=P.read_point(P.readjson(joinpath(prepared,"START.json")))
        reference=build_opf(net,IVRNLP(P.read_options(job["reference"])))
        models=[build_opf(net,IVRNLP(P.read_options(a["options"]))) for a in j["arms"]]
        BLAS.set_num_threads(1)
        solve=function (event,stem)
            i=event["arm_index"]
            trial_mode=mode
            row,point,shape=A.trial(P,net,j["arms"][i],reference,start,nothing,stem,j["solver_settings"][i],job["tolerances"];
                mode=trial_mode,timing_authorized,
                synthetic_clock=trial_mode==:synthetic ? synthetic_clock : nothing)
            point===nothing || P.save(stem*".point.json",P.point_record(point))
            row,point,shape
        end
        report=run_schedule(job,folder,solve,x->compare_group(models,x,job["tolerances"]);mode,timing_authorized)
        report["adapter_source_sha256"]=loaded.source_sha256
        report["adapter_in_memory_sha256"]=loaded.adapted_sha256
        report["worker_pid"]=getpid()
        report["julia_threads"]=Threads.nthreads()
        report["blas_threads"]=BLAS.get_num_threads()
        save(joinpath(folder,"REPORT.json"),report)
        report
    end
end
end
