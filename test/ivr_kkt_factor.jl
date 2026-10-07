using Test, LinearAlgebra
include(joinpath(@__DIR__,"..","examples","ivr_kkt_factor.jl"))
const F=IVRKKTOfflineFactor
@testset "Fresh MUMPS calibration" begin
    mktempdir() do dir
        bridge=F.bridge(dir)
        A=[4.5 1 0 0 1 3 5;1 6.2 0 0 2 4 6;0 0 2 0 0 -1 0;0 0 0 3 0 0 -1;
           1 2 0 0 -.1 0 0;3 4 -1 0 0 -.2 0;5 6 0 -1 0 0 -.3]
        rows=[i for i in 1:7 for j in 1:i];cols=[j for i in 1:7 for j in 1:i]
        q=[1.,-2.,3.,4.,-5.,6.,7.];b=A*q;t=[1.,1.,.25,4.,4.,4.,.25]
        data=Dict("dimension"=>7,"rows"=>rows,"columns"=>cols,"values"=>[A[i,j] for (i,j) in zip(rows,cols)],"rhs"=>b,"coordinate_map"=>t)
        result=F.experiment(bridge,data)
        @test result.passed && result.quality_passed
        @test F.action(7,rows,cols,data["values"],q)≈b
        for p in result.pairs
            @test p.original.rhs[1].solution≈A\b atol=1e-12
            @test p.transformed.rhs[1].solution.*t≈A\b atol=1e-12
            @test p.original.info[12]==count(<(0),eigvals(Symmetric(A)))
            @test p.original.info[12]==p.transformed.info[12]
            @test all(r->r.stages[end].backward_error<1e-14,p.original.rhs)
            if p.name=="fixed_unscaled"
                @test p.original.permutation==p.transformed.permutation
                @test p.original.info[33]==p.transformed.info[33]==0
            end
        end
        # A larger sparse example allows MUMPS to reorganize a supplied order.
        B=Matrix(SymTridiagonal([isodd(i) ? 3. : -2. for i in 1:60],fill(.3,59)))
        ri=[i for i in 1:60 for j in 1:i if B[i,j]!=0]
        cj=[j for i in 1:60 for j in 1:i if B[i,j]!=0]
        fixture=Dict("dimension"=>60,"rows"=>ri,"columns"=>cj,
            "values"=>[B[i,j] for (i,j) in zip(ri,cj)],"rhs"=>ones(60),
            "coordinate_map"=>[isodd(i) ? .8 : 1.25 for i in 1:60])
        larger=F.experiment(bridge,fixture)
        @test larger.passed && larger.quality_passed
        @test larger.pairs[2].original.permutation==larger.pairs[2].transformed.permutation
        bad=deepcopy(data);bad["values"][1]=NaN;@test_throws ErrorException F.input(bad)
        bad=deepcopy(data);bad["rows"][1]=0;@test_throws ErrorException F.input(bad)
        bad=deepcopy(data);bad["coordinate_map"][1]=0;@test_throws ErrorException F.input(bad)
        bad=deepcopy(data);bad["rows"][2]=bad["columns"][2]=1;@test_throws ErrorException F.input(bad)
        z=F.input(data)
        base=F.factor_solve(bridge,z,z.a,[b])
        deep=F.factor_solve(bridge,z,z.a,[b];refinement_steps=8,record_solutions=true)
        zero=F.factor_solve(bridge,z,z.a,[b];refinement_steps=0,record_solutions=true)
        @test base.passed && deep.passed && zero.passed
        @test length(base.rhs[1].stages)==3 && length(deep.rhs[1].stages)==9
        @test [s.stage for s in deep.rhs[1].stages]==collect(0:8)
        @test !hasproperty(base.rhs[1].stages[1],:solution)
        for stage in 1:3
            a=base.rhs[1].stages[stage];d=deep.rhs[1].stages[stage]
            @test (a.residual_max,a.backward_error,a.reference_gap)==(d.residual_max,d.backward_error,d.reference_gap)
        end
        @test deep.rhs[1].stages[3].solution==base.rhs[1].solution
        @test length(zero.rhs[1].stages)==1
        @test zero.rhs[1].solution==deep.rhs[1].stages[1].solution
        @test deep.rhs[1].solution==last(deep.rhs[1].stages).solution
        @test deep.rhs[1].solution!==last(deep.rhs[1].stages).solution
        @test all(i->deep.rhs[1].stages[i].solution!==deep.rhs[1].stages[i+1].solution,1:8)
        @test deep.rhs[1].solution≈A\b atol=1e-12
        @test_throws ArgumentError F.factor_solve(bridge,z,z.a,[b];refinement_steps=-1)
        @test_throws ArgumentError F.factor_solve(bridge,z,z.a,[b];references=[])
        paired=F.factor_solve(bridge,z,z.a,[b,b];refinement_steps=8,record_solutions=true,
            residual_precision=[:bigfloat,:float64])
        @test paired.passed
        @test paired.rhs[1]==deep.rhs[1]
        @test paired.rhs[1].stages[1].solution==paired.rhs[2].stages[1].solution
        low=F.factor_solve(bridge,z,z.a,[b];refinement_steps=8,record_solutions=true,residual_precision=:float64)
        @test low.rhs[1]==paired.rhs[2]
        for s in paired.rhs[2].stages
            check=F.metrics(z.n,z.i,z.j,z.a,s.solution,b)
            @test (s.residual_max,s.backward_error)==(check.residual_max,check.backward_error)
        end
        @test_throws ArgumentError F.factor_solve(bridge,z,z.a,[b];residual_precision=:half)
        @test_throws ArgumentError F.factor_solve(bridge,z,z.a,[b,b];residual_precision=[:float64])
        @test_throws ErrorException F.factor_solve(bridge,z,z.a,[b];permutation=fill(1,7))
        singular=copy(z.a);fill!(singular,0.)
        failed=F.factor_solve(bridge,z,singular,[b])
        @test !failed.passed && failed.info[1]<0
    end
end

@testset "Residual accumulation cancellation control" begin
    rows=[1,2,2,3,3,3];cols=[1,1,2,1,2,3]
    a=[1e16,1.,2.,-1e16,0.,3.];q=ones(3);b=zeros(3)
    hi=F.correction_residual(3,rows,cols,a,q,b)
    lo=F.correction_residual(3,rows,cols,a,q,b;precision=:float64)
    @test hi[1]==-1. && lo[1]==0.
    @test hi==F.metrics(3,rows,cols,a,q,b).residual
    @test_throws ArgumentError F.correction_residual(3,rows,cols,a,q,b;precision=:half)
end
