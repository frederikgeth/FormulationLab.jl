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
        @test_throws ErrorException F.factor_solve(bridge,z,z.a,[b];permutation=fill(1,7))
        singular=copy(z.a);fill!(singular,0.)
        failed=F.factor_solve(bridge,z,singular,[b])
        @test !failed.passed && failed.info[1]<0
    end
end
