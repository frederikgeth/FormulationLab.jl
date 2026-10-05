module IVRObjectiveFactorTests
using Test, FormulationLab, JuMP
include("../examples/benchmark_ivr_objective_factors.jl")
const F=IVRObjectiveFactorStudy

@testset "Power-objective factorial controls and ordering" begin
    net=F.S.case(:quadratic_cost;segments=2)
    ps=F.profiles(net,:quadratic_cost)
    @test length(ps)==24 && allunique(p.name for p in ps)
    @test length(unique(p.factors for p in ps))==24
    for p in ps
        o=p.options;f=p.factors
        @test o.s_base==1e4 && o.objective_scale==1.
        @test o.specialization==:conductor_regions && o.observation_sharing==:exact
        @test o.linear_elimination==(f.passive_blocks ? :passive_blocks : :off)
        @test o.device_elimination==(f.transformer_currents ? :transformer_currents : :off)
        @test isempty(o.current_power_bases)==!f.regional_current && o.lifting==f.lifting
    end
    orders=F.orders(24)
    @test orders==F.orders(24) && length(orders)==8
    for k in 1:2:8
        @test sort(orders[k])==collect(1:24)
        @test orders[k+1]==reverse(orders[k])
        @test all(findfirst(==(j),orders[k])+findfirst(==(j),orders[k+1])==25 for j in 1:24)
    end
    @test_throws ArgumentError F.orders(0)
    @test_throws ArgumentError F.orders(24;blocks=0)
    @test_throws ArgumentError F.profiles(net,:quadratic_cost;nlp_scaling_method="unknown")
    mktempdir() do dir
        for bad in ([[1]],[[1,1]],[[1,3]],[Any[true,2]],[[1,2],[2,1]])
            @test_throws ArgumentError F.S.P.benchmark(net,joinpath(dir,"bad.json");repetitions=1,candidates=ps[1:2],trial_orders=bad)
        end
    end
end

@testset "Factorial candidates preserve power objective and physical states" begin
    for workload in (:quadratic_cost,:exchange_tracking)
        net=F.S.case(workload;segments=2);ps=F.profiles(net,workload)
        start=F.S.U.G.H.S.L.start_point(net)
        reference=build_opf(net,IVRNLP(objective=:power,power_terms=F.S.terms(net,workload)))
        anchor=nothing;objectives=Float64[]
        for profile in ps
            row,p=F.S.P.trial(net,profile,reference,anchor;initial_point=start)
            @test row["accepted"]
            p===nothing && continue
            anchor===nothing && (anchor=p)
            @test row["physical_power_objective"]≈row["objective"] atol=1e-7
            @test row["shared_start"].encoded_variables==row["variables"]
            push!(objectives,row["objective"])
        end
        @test length(objectives)==24 && maximum(objectives)-minimum(objectives)<1e-6
    end
    mktempdir() do dir
        r=F.benchmark(joinpath(dir,"smoke.json");segments=1,blocks=1)
        @test length(r["ranking"]["eligible"])==24 && r["ranking"]["objective_comparable"]
        @test r["mean_position_balanced"]
        @test r["orders"][2]==reverse(r["orders"][1])
        @test length(r["factors"])==24
    end
end
end
