module IVRIterateCaptureTests
using Test, JuMP, Ipopt, LinearAlgebra, SparseArrays
include("../examples/ivr_iterate_capture.jl")
const C=IVRIterateCapture
@testset "Ipopt intermediate states and derivative conventions" begin
    for scaling in ("none","gradient-based")
        m=Model(Ipopt.Optimizer)
        @variable(m,.1<=x<=4,start=1.2)
        @variable(m,.1<=y<=4,start=1.1)
        @variable(m,z==.5)
        @constraint(m,balance,x+y==3)
        @constraint(m,curve,x^2+y^2<=8)
        @constraint(m,nonlinear,exp(x)+x*y+y<=20)
        @objective(m,Min,1000*(x-1)^2+2000*(y-2)^2+z^2+7x*y)
        for (k,v) in ("print_level"=>0,"tol"=>1e-10,"bound_relax_factor"=>0.,"nlp_scaling_method"=>scaling)
            set_optimizer_attribute(m,k,v)
        end
        trace=C.attach!(m)
        @test_throws ArgumentError C.attach!(m)
        optimize!(m)
        @test is_solved_and_feasible(m)
        report=C.finish(m,trace)
        @test !report.timing_eligible
        @test length(report.columns)==3 && length(report.rows)==3
        @test report.endpoint_max_gap<=1e-10
        @test first(trace.records).iteration==0
        @test [r.iteration for r in trace.records]==collect(0:length(trace.records)-1)
        for rec in (first(trace.records),last(trace.records))
            d=C.derivatives(m,rec)
            @test d.value_gap<1e-12 && d.objective_gap<1e-12
            jx=Ipopt.column(optimizer_index(x)); jy=Ipopt.column(optimizer_index(y)); jz=Ipopt.column(optimizer_index(z))
            opt=unsafe_backend(m)
            ib=C.EXT.row(opt,optimizer_index(balance)); ic=C.EXT.row(opt,optimizer_index(curve))
            ie=C.EXT.row(opt,optimizer_index(nonlinear))
            J=sparse(d.jacobian.rows,d.jacobian.columns,d.jacobian.values,3,3)
            H=Matrix{Float64}(Symmetric(sparse(d.hessian.rows,d.hessian.columns,d.hessian.values,3,3),:L))
            px,py=rec.unscaled.x[jx],rec.unscaled.x[jy]
            @test J[ib,[jx,jy]]≈[1.,1.]
            @test J[ic,[jx,jy]]≈[2px,2py]
            @test J[ie,[jx,jy]]≈[exp(px)+py,1+px]
            @test H[jx,jx]≈2000+2rec.unscaled.lambda[ic]+exp(px)*rec.unscaled.lambda[ie]
            @test H[jy,jy]≈4000+2rec.unscaled.lambda[ic]
            @test H[jz,jz]≈2.
            @test H[jx,jy]≈7+rec.unscaled.lambda[ie]
        end
        @test C.derivatives(m,last(trace.records)).stationarity_max<1e-6
        bad=(;last(trace.records)...,objective=1e50)
        @test_throws ErrorException C.derivatives(m,bad)
        if scaling=="none"
            @test last(trace.records).unscaled.lambda≈last(trace.records).scaled.lambda
        else
            @test norm(first(trace.records).unscaled.z_L-first(trace.records).scaled.z_L)>1
        end
        pop!(trace.records)
        @test_throws ErrorException C.finish(m,trace)
        set_objective_sense(m,JuMP.MOI.MAX_SENSE)
        @test_throws ArgumentError C.derivatives(m,last(trace.records))
    end
end
end
