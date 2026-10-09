#= Opt-in integration test in an environment containing the copied Ipopt package.

Run with one argument: the expected copied package directory. This test solves a
manufactured scalar quadratic with recording disabled and with a virtual clock.
It collects no native wall-clock samples and makes no performance comparison.
It is separate from runtests.jl, which must keep using the installed solver.
=#
using Test, JuMP, Ipopt
const MOI=JuMP.MOI
length(ARGS)==1 || error("expected instrumented Ipopt directory")
realpath(dirname(dirname(pathof(Ipopt))))==realpath(ARGS[1]) || error("wrong Ipopt package loaded")
ext=Base.get_extension(Ipopt,:IpoptMathOptInterfaceExt)
T=ext.IVRNativeTimer
r=ext._formulationlab_native_recorder

@testset "Copied Ipopt hook, synthetic clock only" begin
    @test !r.enabled
    clock_calls=Ref(0)
    r.clock=()->error("disabled recorder called the clock")
    model=direct_model(Ipopt.Optimizer())
    set_silent(model)
    @variable(model,x,start=-1)
    @objective(model,Min,(x-2)^2)
    optimizer=backend(model)
    optimize!(model)
    @test termination_status(model)==MOI.LOCALLY_SOLVED
    @test value(x)≈2 atol=1e-7
    @test T.sample(r,optimizer)===nothing
    reference=(value(x),objective_value(model))

    r.enabled=true
    r.clock=()->(clock_calls[]+=1;100*clock_calls[])
    optimize!(model)
    @test termination_status(model)==MOI.LOCALLY_SOLVED
    @test value(x)≈reference[1] atol=1e-10
    @test objective_value(model)≈reference[2] atol=1e-10
    @test clock_calls[]==2
    @test T.sample(r,optimizer).status==:completed
    @test T.sample(r,optimizer).native_call_ns==100

    # Exercise the actual wrapper's pre-native early return with a stale sample.
    optimizer.invalid_model=true
    MOI.optimize!(optimizer)
    @test T.sample(r,optimizer)===nothing
    @test clock_calls[]==2
    optimizer.invalid_model=false

    # Exercise a wrapper setup failure after another completed sample.
    MOI.optimize!(optimizer)
    @test T.sample(r,optimizer).status==:completed
    optimizer.options["tol"]=nothing
    @test_throws ErrorException MOI.optimize!(optimizer)
    @test T.sample(r,optimizer)===nothing
    @test clock_calls[]==4
    delete!(optimizer.options,"tol")

    r.enabled=false
    optimize!(model)
    @test termination_status(model)==MOI.LOCALLY_SOLVED
    @test T.sample(r,optimizer)===nothing
    @test clock_calls[]==4
end
