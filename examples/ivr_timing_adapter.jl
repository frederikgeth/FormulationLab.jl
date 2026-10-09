"""Read-only adapter for the two frozen correctness executors.

Loading this module does not run an optimizer. The adapter leaves the archived
source untouched and adds only a post-solve observer to its in-memory copy.
Campaign authorization, source/runtime freezing and isolation belong to the
calling runner; a synthetic-clock result can never become a native-time sample.
"""
module IVRTimingAdapter
using SHA, FormulationLab, JuMP, Ipopt

const PREFLIGHT_SHA256=Dict(
    "B"=>"bfcd767fd8cb5640f5aa23f05c664345f7582b2190d584c0b561c64e5276f5fc",
    "C"=>"5d3a89107d390115265f4bf8047c6587cd4a3c5574fdb4628951fe9244414047")
const SOLVE="        r=solve_ivr_nlp_opf(b;solver_options=solver_settings(settings))\n"
require(ok,message)=ok || throw(ArgumentError("timing adapter: "*message))

function adapted_source(bytes,freeze)
    require(haskey(PREFLIGHT_SHA256,freeze),"unknown source freeze")
    require(bytes2hex(sha256(bytes))==PREFLIGHT_SHA256[freeze],"correctness source changed")
    source=String(copy(bytes))
    signature=freeze=="B" ? "function trial(net,p,reference,start,anchor,stem,settings,tol)" :
        "function trial(net,p,reference,start,anchor,stem,settings,tol;save_failed_primal=false)"
    replacement=chop(signature)* (freeze=="B" ? ";" : ",") * "timing_observer=(b,row)->nothing)"
    observed=SOLVE*"        timing_observer(b,row)\n"
    require(count(signature,source)==1 && count(SOLVE,source)==1,"ambiguous instrumentation anchors")
    result=replace(replace(source,signature=>replacement),SOLVE=>observed)
    restored=replace(replace(result,observed=>SOLVE),replacement=>signature)
    require(Vector{UInt8}(codeunits(restored))==bytes,"source restoration failed")
    result
end

"""Load the matching archived executor, refusing a different loaded compiler."""
function load_preflight(source_root,freeze)
    root=realpath(source_root)
    require(realpath(dirname(dirname(pathof(FormulationLab))))==root,"loaded compiler is not the declared source archive")
    path=joinpath(root,"examples","ivr_transfer_preflight.jl")
    adapted=adapted_source(read(path),freeze)
    host=Module(gensym(:FrozenTimingHost))
    # include_string's filename alone does not set the nested include directory.
    # Match Base.include's source-path context and restore it on success/error.
    task_local_storage(:SOURCE_PATH,path) do
        Base.include_string(host,adapted,path)
    end
    (;executor=Base.invokelatest(getfield,host,:IVRTransferPreflight),source_sha256=PREFLIGHT_SHA256[freeze],
        adapted_sha256=bytes2hex(sha256(Vector{UInt8}(codeunits(adapted)))),source_root=root)
end

function recorder()
    ext=Base.get_extension(Ipopt,:IpoptMathOptInterfaceExt)
    require(ext!==nothing && isdefined(ext,:_formulationlab_native_recorder),"instrumented Ipopt copy required")
    ext.IVRNativeTimer,ext._formulationlab_native_recorder
end

"""Execute one existing correctness trial, adding a separate timing record.

Modes: disabled (default), synthetic (injected test clock), native (requires
explicit authorization). This function does not enforce process isolation or
certify campaign admission. The caller must do so before requesting native mode.
All correctness fields and physical exports come from the archived executor.
"""
function trial(P,args...;mode=:disabled,timing_authorized=false,synthetic_clock=nothing)
    require(mode in (:disabled,:synthetic,:native),"unknown measurement mode")
    require(mode!=:native || timing_authorized===true,"native measurement requires explicit authorization")
    require(mode==:synthetic ? synthetic_clock!==nothing : synthetic_clock===nothing,"clock/mode mismatch")
    T,r=recorder()
    require(!r.enabled,"recorder already active; serial execution required")
    old_clock=r.clock
    empty!(r.samples)
    r.enabled=mode!=:disabled
    r.clock=mode==:synthetic ? synthetic_clock : time_ns
    observer=function (b,row)
        optimizer=JuMP.unsafe_backend(b.model)
        sample=T.sample(r,optimizer)
        completed=sample!==nothing && sample.status==:completed
        row["timing"]=Dict{String,Any}(
            "schema"=>"FormulationLab.native_trial_timing.v1",
            "mode"=>string(mode),
            "sample_status"=>sample===nothing ? "absent" : string(sample.status),
            "native_ipopt_wall_s"=>mode==:native && completed ? sample.native_call_s : nothing,
            "synthetic_elapsed_ns"=>mode==:synthetic && completed ? string(sample.native_call_ns) : nothing,
            "optimizer_wrapper_wall_s"=>mode==:native ? JuMP.solve_time(b.model) : nothing,
            "clock_error"=>sample===nothing ? nothing : sample.clock_error)
    end
    try
        Base.invokelatest(P.trial,args...;timing_observer=observer)
    finally
        r.enabled=false
        r.clock=old_clock
        empty!(r.samples)
    end
end
end
