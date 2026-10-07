using Test
include(joinpath(@__DIR__,"..","examples","ivr_kkt_residuals.jl"))
const R=IVRKKTResiduals
@testset "Mixed KKT residual diagnostics" begin
    # Diagonal equations isolate tiny-row relative error from significant error.
    d=Dict("dimension"=>4,"rows"=>[1,2,3,4],"columns"=>[1,2,3,4],
           "values"=>[1.,1.,1.,0.],"coordinate_map"=>[2.,.5,4.,1.])
    q=[1.,1e-30,2.,0.];b=[1.,0.,2.,0.]
    a=R.diagnose(d,q,b;dimensions=(1,1,1,1))
    @test a.backward_error==1.
    @test a.strict_worst[1].row==2
    @test !a.thresholds[1].passed
    @test a.thresholds[2].passed
    @test a.thresholds[1].failing_by_block[:slack]==1
    t=d["coordinate_map"]
    z=R.diagnose(d,q./t,b;transformed=true,dimensions=(1,1,1,1))
    @test [x.maximum_ratio for x in a.thresholds]==[x.maximum_ratio for x in z.thresholds]
    @test a.strict_worst[1].reference_absolute_residual==z.strict_worst[1].reference_absolute_residual
    bad=R.diagnose(d,[1.,1e-30,2.01,0.],b;dimensions=(1,1,1,1))
    @test !bad.thresholds[end].passed
    @test bad.thresholds[end].worst[1].block==:equality
    # Off-diagonal entries must contribute symmetrically, with cancellation.
    c=Dict("dimension"=>2,"rows"=>[1,2,2],"columns"=>[1,1,2],"values"=>[2.,3.,-1.],"coordinate_map"=>[1.,1.])
    exact=R.diagnose(c,[1.,2.],[8.,1.];dimensions=(1,0,1,0))
    @test exact.residual_max==0.
    @test exact.backward_error==0.
    @test all(x.passed for x in exact.thresholds)
    @test_throws ErrorException R.diagnose(d,[NaN,0.,0.,0.],b;dimensions=(1,1,1,1))
    @test_throws ErrorException R.diagnose(d,q,b;dimensions=(1,1,1,0))
    @test_throws ErrorException R.diagnose(d,q,b;dimensions=(1,1,1,1),absolute_tolerances=(-1.,))
    @test_throws ErrorException R.diagnose(d,q,b;dimensions=(1,1,1,1),relative_tolerance=0.)
end
