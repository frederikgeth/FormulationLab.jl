# A launcher-held process. Inspect mode never builds or solves a network.
using JSON3,SHA,LinearAlgebra
include("ivr_timing_controller.jl")
include("ivr_timing_runtime.jl")
const C=IVRTimingController
function valid_permit(permit,command,expected,pid,parent)
    get(permit,"schema",nothing)=="FormulationLab.native_launch_permit.v1" &&
        get(permit,"authorized",false)===true && get(permit,"job_sha256",nothing)==expected &&
        get(permit,"worker_pid",nothing)==pid && get(permit,"launcher_pid",nothing)==parent &&
        get(command,"command",nothing)=="run" &&
        get(permit,"nonce",nothing) isa String && !isempty(permit["nonce"]) &&
        permit["nonce"]==get(command,"nonce",nothing)
end
function worker_main(args)
    length(args)==6 || error("expected job, digest, output, ready, inspect/native, permit")
    job_path,expected,folder,ready,mode,permit_path=args
    mode in ("inspect","native") || error("unknown worker mode")
    bytes=read(job_path);bytes2hex(sha256(bytes))==expected || error("job bytes changed")
    job=JSON3.read(bytes,Dict{String,Any});C.validate_job(job)
    j=job["admission"]
    C.check_output(folder,[j["source_archive"],dirname(j["inputs"]["preparation"])])
    realpath(dirname(dirname(pathof(C.FormulationLab))))==realpath(j["source_archive"]) || error("wrong compiler loaded")
    BLAS.set_num_threads(1)
    C.A.load_preflight(j["source_archive"],j["freeze"]) # Load executor dependencies, without building a model.
    runtime=IVRTimingRuntime.capture()
    packet=Dict("schema"=>"FormulationLab.waiting_timing_worker.v1","pid"=>getpid(),
        "parent_pid"=>Int(ccall(:getppid,Cint,())),"job_sha256"=>expected,
        "mode"=>mode,"optimizer_invoked"=>false,"runtime"=>runtime)
    ispath(ready) && error("ready packet already exists")
    C.save(ready,packet)
    # No model construction or solve may precede this launcher release.
    command=JSON3.read(readline(stdin),Dict{String,Any})
    get(command,"command",nothing)=="run" || error("worker was not released")
    if mode=="inspect"
        mkpath(folder)
        C.save(joinpath(folder,"REPORT.json"),Dict("schema"=>"FormulationLab.timing_worker_inspection.v1",
            "optimizer_invoked"=>false,"worker_pid"=>getpid(),"job_sha256"=>expected,"runtime"=>runtime))
        return
    end
    permit=JSON3.read(read(permit_path,String),Dict{String,Any})
    valid_permit(permit,command,expected,getpid(),packet["parent_pid"]) || error("invalid native launch permit")
    C.run_job(job,folder;mode=:native,timing_authorized=true)
    # New libraries or source/cache drift after solving must remain auditable.
    C.save(joinpath(folder,"RUNTIME_AFTER.json"),IVRTimingRuntime.capture())
end
abspath(PROGRAM_FILE)==(@__FILE__) && worker_main(ARGS)
