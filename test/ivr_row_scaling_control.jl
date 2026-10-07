using Test,JuMP,Ipopt
include(joinpath(@__DIR__,"..","examples","ivr_row_scaling_control.jl"))
include(joinpath(@__DIR__,"..","examples","ivr_iterate_capture.jl"))
const R=IVRRowScalingControl;const C=IVRIterateCapture
@testset "Nonlinear row-only calibration" begin
    @test_throws ArgumentError R.settings(target=0.)
    @test_throws ArgumentError R.settings(target=Inf)
    runs=[]
    for arm in (:baseline,:held,:unit)
        m=Model(Ipopt.Optimizer)
        @variable(m,.1<=x<=4,start=2.5)
        @variable(m,y<=5,start=3.)
        @variable(m,z==.5)
        @constraint(m,balance,x+y+z==3.5)
        @constraint(m,circle,x^2+y^2<=8.)
        @constraint(m,scaled_bound,200x>=40.)
        @constraint(m,nonlinear,exp(.1x)+y>=1.)
        @objective(m,Min,1000*(x-1)^2+2000*(y-2)^2+7*x*y+z^2)
        for (k,v) in pairs((;print_level=0,tol=1e-10,bound_relax_factor=0.,max_iter=100,acceptable_iter=0))
            set_optimizer_attribute(m,String(k),v)
        end
        if arm!=:baseline
            for (k,v) in pairs(R.settings(unit_rows=arm==:unit));set_optimizer_attribute(m,String(k),v);end
        end
        trace=C.attach!(m);optimize!(m);capture=C.finish(m,trace)
        @test is_solved_and_feasible(m)
        # Fixed z is removed; the initial objective gradient is [3021,4017.5].
        scale=100/4017.5
        rows=ones(length(capture.rows))
        if arm!=:unit
            rows[C.EXT.row(unsafe_backend(m),optimizer_index(balance))]=1.
            rows[C.EXT.row(unsafe_backend(m),optimizer_index(scaled_bound))]=.5
        end
        for rec in trace.records;@test R.verify(rec,scale,rows).passed;end
        @test_throws ErrorException R.verify(first(trace.records),2scale,rows)
        push!(runs,(;records=trace.records,objective=objective_value(m),point=value.([x,y,z])))
    end
    @test runs[1].records==runs[2].records
    @test isapprox(runs[1].objective,runs[3].objective;atol=1e-8,rtol=1e-8)
    @test runs[1].point≈runs[3].point atol=1e-7
end
