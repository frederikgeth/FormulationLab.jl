module IVRPowerInteractionTests
using Test, FormulationLab, JuMP, JSON3, SHA
include("../examples/benchmark_ivr_power_interactions.jl")
const I=IVRPowerInteractionStudy
const S=I.E.S

@testset "Power interaction panel isolates each factor" begin
    net=S.case(:quadratic_cost;segments=1)
    ps=I.profiles(net,:quadratic_cost)
    arms=ps[3:end]
    @test length(ps)==10 && allunique(p.name for p in ps)
    @test Set((p.factors.generator_base,p.factors.lifted_power_base,p.factors.power_sharing) for p in arms)==
        Set((g,l,r) for g in (1e4,1e5) for l in (1e3,1e4) for r in (:off,:generators))
    changed(a,b)=Set(k for k in fieldnames(IVRNLPOptions) if
        JSON3.write(getfield(a.options,k))!=JSON3.write(getfield(b.options,k)))
    for a in arms,b in arms
        expected=Set{Symbol}()
        a.factors.generator_base!=b.factors.generator_base && push!(expected,:generator_power_bases)
        a.factors.lifted_power_base!=b.factors.lifted_power_base && push!(expected,:lifted_power_base)
        a.factors.power_sharing!=b.factors.power_sharing && push!(expected,:power_sharing)
        @test changed(a,b)==expected
    end
    @test_throws ArgumentError I.profiles(net,:exchange_tracking)
    @test_throws ArgumentError I.profiles(net,:quadratic_cost;nlp_scaling_method="unknown")
    # Candidate terms and option dictionaries are independently owned.
    first(arms).options.generator_power_bases[first(keys(net["generator"]))]=123.
    @test all(all(!=(123.),values(p.options.generator_power_bases)) for p in arms[2:end])
end

@testset "Joint units and reuse preserve physical power objectives" begin
    for workload in (:quadratic_cost,:exchange_tracking),policy in ("none","gradient-based")
        net=S.case(workload;segments=1)
        ps=I.profiles(net,workload;exchange_target_W=4500.,nlp_scaling_method=policy)
        reference=build_opf(net,IVRNLP(objective=:power,power_terms=first(ps).options.power_terms))
        anchor=nothing;objectives=Float64[]
        for p in ps
            row,point=I.P.trial(net,p,reference,anchor;initial_point=S.U.G.H.S.L.start_point(net))
            @test row["accepted"]
            row["accepted"] || continue
            anchor===nothing && (anchor=point)
            push!(objectives,row["objective"])
            @test row["shared_start"].encoded_variables==row["variables"]
            @test row["generator_power_bases"]==p.options.generator_power_bases
            @test row["lifted_power_base"]==p.options.lifted_power_base
            @test row["reused_generator_power_count"]==(p.options.power_sharing==:generators ? length(net["generator"]) : 0)
            @test row["objective"]≈row["physical_power_objective"] atol=1e-7
        end
        @test length(objectives)==10 && maximum(objectives)-minimum(objectives)<1e-6
    end
end

@testset "Interaction runner preserves sources and records its provenance" begin
    mktempdir() do dir
        path=joinpath(dir,"source.json");net=S.case(:quadratic_cost;segments=1)
        open(io->JSON3.write(io,net),path,"w")
        @test_throws ArgumentError I.benchmark(path,path)
        r=I.benchmark(path,joinpath(dir,"report.json"))
        @test r["source_unchanged"] && r["network_unchanged"] && r["position_balanced"]
        @test r["ranking"]["objective_comparable"] && length(r["ranking"]["eligible"])==10
        @test r["feeder_input"].runner_sha256==bytes2hex(sha256(read(joinpath(@__DIR__,"../examples/benchmark_ivr_power_interactions.jl"))))
    end
end
end
