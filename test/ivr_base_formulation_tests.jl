module IVRBaseFormulationTests
using Test, FormulationLab, JSON3
include("../examples/benchmark_ivr_base_formulations.jl")
const F=IVRBaseFormulationStudy

@testset "Matched base/formulation controls and cyclic position balance" begin
    net=F.E.S.case(:quadratic_cost;segments=2)
    ps=F.profiles(net,:quadratic_cost)
    @test length(ps)==12 && allunique(p.name for p in ps) && length(unique(p.factors for p in ps))==12
    for p in ps
        o=p.options;f=p.factors
        @test o.s_base==f.s_base && o.objective_scale==1.
        @test isempty(o.current_power_bases) && o.observation_sharing==:exact
        @test o.specialization==(f.reduced ? :conductor_regions : :off)
        @test o.linear_elimination==(f.reduced ? :passive_blocks : :off)
        @test o.device_elimination==(f.reduced ? :transformer_currents : :off) && o.lifting==f.lifting
        @test JSON3.write(o.power_terms)==JSON3.write(ps[1].options.power_terms)
    end
    empty!(ps[1].options.power_terms)
    @test !isempty(ps[2].options.power_terms)
    for blocks in (1,2)
        os=F.orders(12;blocks)
        @test os==F.orders(12;blocks) && length(os)==12blocks
        @test all(sort(o)==collect(1:12) for o in os)
        @test all(count(o->o[k]==j,os)==blocks for j in 1:12 for k in 1:12)
        @test all(all(count(o->o[k]==j,os[(b-1)*12+1:b*12])==1 for j in 1:12 for k in 1:12) for b in 1:blocks)
    end
    @test F.orders(12)!=F.orders(12;seed=1)
    for n in (0,-1,true,1.5)
        @test_throws ArgumentError F.orders(n)
    end
    @test_throws ArgumentError F.orders(12;blocks=0)
    @test_throws ArgumentError F.orders(12;blocks=true)
    @test_throws ArgumentError F.profiles(net,:quadratic_cost;nlp_scaling_method="unknown")
end

@testset "Matched bases preserve physical objectives and complete starts" begin
    for workload in (:quadratic_cost,:exchange_tracking)
        net=F.E.S.case(:quadratic_cost;segments=2)
        profiles=F.profiles(net,workload;exchange_target_W=4500.)
        reference=build_opf(net,IVRNLP(objective=:power,power_terms=first(profiles).options.power_terms))
        start=F.E.S.U.G.H.S.L.start_point(net);anchor=nothing;objectives=Float64[]
        for p in profiles
            row,point=F.P.trial(net,p,reference,anchor;initial_point=start)
            @test row["accepted"]
            point===nothing && continue
            @test row["physical_power_objective"]≈row["objective"] atol=1e-7
            @test row["shared_start"].encoded_variables==row["variables"]
            anchor===nothing && (anchor=point)
            push!(objectives,row["objective"])
        end
        @test length(objectives)==12 && maximum(objectives)-minimum(objectives)<1e-6
    end
    mktempdir() do dir
        net=F.E.S.case(:quadratic_cost;segments=1)
        path=joinpath(dir,"source.json");open(io->JSON3.write(io,net),path,"w")
        raw=read(path);output=joinpath(dir,"report.json")
        @test_throws ArgumentError F.benchmark(path,path)
        report=F.benchmark(path,output)
        @test report["source_unchanged"] && report["network_unchanged"] && read(path)==raw
        @test report["position_balanced"] && length(report["orders"])==12 && length(report["factors"])==12
        @test report["ranking"]["objective_comparable"] && length(report["ranking"]["eligible"])==12
        @test isfile(output*".manifest.json") && isfile(output*".input.json")
        @test !report["global_optimum_certified"]
    end
end
end
