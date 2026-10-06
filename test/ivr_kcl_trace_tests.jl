using Test, FormulationLab, JuMP, Ipopt
include("../examples/ivr_kcl_residual_trace.jl")
const _KTRACE=IVRKCLResidualTrace

@testset "KCL trace separates physical gain from arithmetic loss" begin
    # A solved two-real-coordinate toy isolates the diagnostic itself from OPF.
    m=Model(Ipopt.Optimizer);set_silent(m)
    @variable(m,xr[1:1],start=1.);@variable(m,xi[1:1],start=0.)
    @objective(m,Min,(xr[1]-1)^2+xi[1]^2);optimize!(m)
    y=xr+im*xi
    function toy(R,row;omitted=false)
        (;model=m,electrical=(;kcl=Dict(("b","a")=>row),ib=10.),
          coordinates=(;reconstruction=R,real_variables=xr,imaginary_variables=xi),
          state=[FormulationLab._linivr_eval(r,y) for r in R],
          numerical_diagnostics=Dict(:composed_row_normalization=>true,
            :specialization_report=>(;omitted_kcl=omitted ? [("b","a")] : Tuple{String,String}[]),
            :linear_elimination_report=>(;series_buses=String[])))
    end
    b=toy([Dict(1=>2.0+0im)],[(1,1.0+0im)])
    a=only(_KTRACE.trace(b))
    @test a.retained_constraint
    @test a.divisor==2. && a.gain_A==20.
    @test a.float_nested_A≈20. && a.big_nested_A≈20. && a.native_residual_A≈20.
    @test a.complex_target==1e-6/20 && a.sufficient_scalar_target≈1e-6/(sqrt(2)*20)
    @test a.nested_roundoff_A==a.composition_roundoff_A==0.
    @test !only(_KTRACE.trace(toy([Dict(1=>2.0+0im)],[(1,1.0+0im)];omitted=true))).retained_constraint
    # Ordered terms force cancellation: Float64 loses the +1 between +/-1e16.
    c=toy([Dict(1=>1e16+0im),Dict(1=>1.0+0im),Dict(1=>1e16+0im)],[(1,1.0+0im),(2,1.0+0im),(3,-1.0+0im)])
    q=only(_KTRACE.trace(c));h=only(_KTRACE.trace(c;bits=384))
    @test q.big_nested_A≈10. && h.big_nested_A==q.big_nested_A
    @test q.big_composed_A==0. && q.composition_roundoff_A≈10.
    @test q.float_nested_A==0. && q.nested_roundoff_A≈10.
    @test_throws ArgumentError _KTRACE.trace(b;bits=64)
    @test_throws ArgumentError _KTRACE.trace(b;atol_A=0.)
    @test_throws ArgumentError _KTRACE.trace(b;keys=[("missing","a")])
end

isdefined(@__MODULE__,:IVRNWindingRegionalStudy) || include("../examples/benchmark_ivr_nwinding_regional.jl")
@testset "KCL trace agrees with independent multiwinding SI audit" begin
    U=IVRNWindingRegionalStudy;N=U.N;net,_=N.network(2)
    p=first(U.profiles(net,:tracking,"all_transformer_currents__powers"))
    b=build_opf(net,IVRNLP(p.options);optimizer=Ipopt.Optimizer)
    for (v,x) in ivr_nlp_point_report(b,N.S.start_point(net)).variable_values;set_start_value(v,x);end
    r=solve_ivr_nlp_opf(b;solver_options=N.SETTINGS)
    @test r.solve.optimal && physical_residuals(net,r).passed
    audit=Dict(x.label=>x.residual for x in physical_residuals(net,r).records)
    rows=_KTRACE.trace(b);@test length(rows)==length(b.electrical.kcl)
    for q in rows
        @test isapprox(q.float_nested_A,audit["kcl/$(q.bus)/$(q.terminal)"];atol=1e-8,rtol=1e-5)
        @test abs(q.big_nested_A-q.float_nested_A)<=q.nested_roundoff_A+1e-15
        @test q.native_residual_A≈q.gain_A*q.normalized_complex_residual
        @test q.normalized_scalar_residual<=q.normalized_complex_residual+1e-20
    end
    @test any(!q.retained_constraint for q in rows)
    @test only(_KTRACE.trace(b;keys=[("u1_b4","a")])).retained_constraint
end
