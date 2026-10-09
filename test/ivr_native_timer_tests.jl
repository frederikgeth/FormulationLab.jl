module IVRNativeTimerTests
using Test
include("../examples/ivr_native_timer.jl")
const T=IVRNativeTimer

@testset "Native boundary excludes surrounding work and preserves results" begin
    t=Ref(0);key=Ref(nothing);events=Symbol[]
    clock=()->(push!(events,:tick);t[])
    r=T.Recorder(;enabled=true,clock)
    t[]+=1000 # Wrapper preparation outside capture.
    token=Ref(:result)
    result=T.capture!(r,key) do
        push!(events,:native);t[]+=250;token
    end
    t[]+=9000 # Extraction/audits outside capture.
    @test result===token
    @test events==[:tick,:native,:tick]
    @test T.sample(r,key).native_call_ns==250
    @test T.sample(r,key).native_call_s==250e-9
    @test T.sample(r,key).status==:completed
    T.reset!(r,key);@test T.sample(r,key)===nothing
end

@testset "Disabled timing, failures and invalid clocks never produce a duration" begin
    key=Ref(nothing);calls=Ref(0)
    r=T.Recorder(;clock=()->error("disabled clock must not be called"))
    @test T.capture!(() -> (calls[]+=1;42),r,key)==42
    @test calls[]==1 && T.sample(r,key)===nothing
    r.enabled=true;r.clock=()->10
    failure=ErrorException("native failure")
    caught=try T.capture!(() -> throw(failure),r,key);nothing catch err;err;end
    @test caught===failure
    @test T.sample(r,key).status==:operation_failed
    @test T.sample(r,key).native_call_s===nothing
    for ticks in ([10,10],[10,9],[-1,2],[1.0,2.0],[false,true])
        i=Ref(0);r.clock=()->ticks[i[]+=1]
        @test T.capture!(() -> :ok,r,key)==:ok
        @test T.sample(r,key).status==:invalid_clock
        @test T.sample(r,key).native_call_s===nothing
    end
    for failing_tick in (1,2)
        i=Ref(0);r.clock=()->((i[]+=1)==failing_tick ? error("clock failure") : 100)
        calls[]=0
        @test T.capture!(() -> (calls[]+=1;:ok),r,key)==:ok
        @test calls[]==1 && T.sample(r,key).status==:invalid_clock
    end
    # A later unsuccessful or disabled call must not reuse a previous sample.
    i=Ref(0);r.clock=()->(i[]+=100)
    T.capture!(() -> :ok,r,key);@test T.sample(r,key).status==:completed
    r.enabled=false
    T.capture!(() -> :ok,r,key);@test T.sample(r,key)===nothing
end
end
