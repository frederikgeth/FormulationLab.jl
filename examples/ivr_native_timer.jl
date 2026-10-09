"""Opt-in native-call measurement for a separately instrumented Ipopt copy.

No solver dependency or solver invocation occurs when this module is loaded.
Recording does not confer timing authorization. Use one recorder per serial
study process; the study must enforce isolation and physical admission separately.
"""
module IVRNativeTimer

mutable struct Recorder
    enabled::Bool
    clock::Function
    samples::WeakKeyDict{Any,Any}
end
Recorder(;enabled=false,clock=time_ns)=Recorder(enabled,clock,WeakKeyDict{Any,Any}())
reset!(r::Recorder,key)=(delete!(r.samples,key);nothing)
sample(r::Recorder,key)=get(r.samples,key,nothing)

function tick(clock)
    try
        (;value=clock(),error=nothing)
    catch err
        err isa InterruptException && rethrow()
        (;value=nothing,error=sprint(showerror,err))
    end
end

"""Invoke `operation` once; time only its call and propagate its result/error.

Bookkeeping and duration validation occur after the second tick. Broken clocks
invalidate timing without suppressing the operation or its exception. Invalid
or failed samples never contain an admissible duration. The two clock reads and
ordinary dispatch have unavoidable overhead; exclude declared warmups in studies.
"""
function capture!(operation::F,r::Recorder,key) where F
    reset!(r,key)
    r.enabled || return operation()
    start=tick(r.clock)
    result=try
        operation()
    catch err
        r.samples[key]=(;status=:operation_failed,native_call_s=nothing,
            native_call_ns=nothing,clock_error=start.error)
        rethrow()
    end
    finish=tick(r.clock)
    reason=start.error!==nothing ? start.error : finish.error
    valid=reason===nothing && start.value isa Integer && !(start.value isa Bool) &&
        finish.value isa Integer && !(finish.value isa Bool) && start.value>=0 && finish.value>=0
    elapsed=valid ? BigInt(finish.value)-BigInt(start.value) : nothing
    seconds=elapsed===nothing ? nothing : Float64(elapsed)/1e9
    valid=valid && elapsed>0 && isfinite(seconds)
    r.samples[key]=valid ? (;status=:completed,native_call_s=seconds,native_call_ns=elapsed,clock_error=nothing) :
        (;status=:invalid_clock,native_call_s=nothing,native_call_ns=nothing,
            clock_error=reason===nothing ? "clock ticks must be nonnegative integers with a positive finite interval" : reason)
    result
end
end
