using Test, LinearAlgebra
include("../examples/ivr_kkt_fixed_observations.jl")
const X=IVRKKTFirstOrderElimination
@testset "Paired KKT elimination and full-direction recovery" begin
    # Order is (two retained coordinates, two observations, two multipliers).
    B=[4. 1.;1. -3.];E=[2. -1.;.5 3.];A=[5. 2.;2. -7.];D=diagm([2.,-.25])
    K=[B E zeros(2,2);E' A D;zeros(2,2) D zeros(2,2)]
    rows=[i for i in 1:6 for j in 1:i];columns=[j for i in 1:6 for j in 1:i]
    data=Dict("dimension"=>6,"rows"=>rows,"columns"=>columns,
        "values"=>[K[i,j] for (i,j) in zip(rows,columns)],"coordinate_map"=>ones(6),"rhs"=>ones(6))
    c=X.control(data,[(3,5),(4,6)])
    @test c.keep==[1,2]
    @test c.reduced["rhs"]==X.reduce_rhs(c,data["rhs"])
    for b in ([1.,2.,3.,4.,5.,6.],[1.,2.,3.,4.,0.,0.],[1.,2.,3.,4.,1e-30,-2e-30])
        br=X.reduce_rhs(c,b);q=X.recover(c,B\br,b)
        @test br≈b[1:2]-E*(D\b[5:6])
        @test q≈K\b atol=1e-12 rtol=1e-12
        @test K*q≈b atol=1e-12 rtol=1e-12
        @test q[3:4]==D\b[5:6]
    end
    identity=X.control(data,Tuple{Int,Int}[])
    @test X.reduce_rhs(identity,data["rhs"])==data["rhs"]
    @test X.recover(identity,ones(6),data["rhs"])==ones(6)
    @test_throws ArgumentError X.control(data,[(3,5),(3,6)])
    @test_throws ArgumentError X.control(data,[(0,5)])
    @test_throws ArgumentError X.control(data,[(1,2)])
    @test_throws ArgumentError X.reduce_rhs(c,ones(5))
    @test_throws ArgumentError X.recover(c,[NaN,1.],ones(6))
    for (i,j) in ((5,5),(6,5),(5,1))
        bad=deepcopy(data);bad["values"][findfirst(==((i,j)),collect(zip(rows,columns)))]=.01
        @test_throws ArgumentError X.control(bad,[(3,5),(4,6)])
    end
    # Independent MUMPS solve, including signed pair coefficients and RHS correction.
    mktempdir() do dir
        bridge=X.F.bridge(dir);b=[1.,2.,3.,4.,5.,6.];br=X.reduce_rhs(c,b)
        z=X.F.input(c.reduced);f=X.F.factor_solve(bridge,z,z.a,[br])
        @test f.passed
        q=X.recover(c,f.rhs[1].solution,b)
        @test q≈K\b atol=1e-12
        @test X.F.metrics(6,rows,columns,data["values"],q,b).backward_error<1e-14
    end
end
