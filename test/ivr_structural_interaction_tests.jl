module IVRStructuralInteractionTests
using Test, FormulationLab, JuMP, JSON3, SHA
include("../examples/benchmark_ivr_structural_interactions.jl")
const I=IVRStructuralInteractionStudy

@testset "Structural factorial changes only its declared factors" begin
    net=I.A.H.case(conductors=3,segments=8)
    profiles=I.profiles(net,:quadratic_cost);arms=profiles[3:end]
    @test length(profiles)==10 && allunique(p.name for p in profiles)
    @test Set((p.options.linear_elimination,p.options.observation_sharing,p.options.power_sharing) for p in arms)==
        Set((l,s,r) for l in (:passive_blocks,:passive_hybrid) for s in (:exact,:signed) for r in (:off,:generators))
    fields=(:linear_elimination,:observation_sharing,:power_sharing)
    for a in arms,b in arms
        actual=Set(k for k in fieldnames(IVRNLPOptions) if JSON3.write(getfield(a.options,k))!=JSON3.write(getfield(b.options,k)))
        expected=Set(k for k in fields if getfield(a.options,k)!=getfield(b.options,k))
        @test actual==expected
    end
    @test all(p.options.lifting==:bounded_observations && p.options.passive_component_limit==4 &&
        p.options.s_base==1e4 && p.options.lifted_power_base==1e3 && p.options.objective_scale==1 for p in arms)
    @test profiles[1].options.lifting==profiles[2].options.lifting==:powers
    @test profiles[1].options.linear_elimination==:off && profiles[2].options.linear_elimination==:passive_blocks
    @test_throws ArgumentError I.profiles(net,:exchange_tracking)
    @test_throws ArgumentError I.profiles(net,:quadratic_cost;nlp_scaling_method="unknown")
    first(arms).options.generator_power_bases["der"]=123.
    @test all(p.options.generator_power_bases["der"]==1e4 for p in arms[2:end])
end

@testset "Combined structural choices preserve physical workloads and original limits" begin
    for m in (2,3),workload in (:quadratic_cost,:exchange_tracking),policy in ("none","gradient-based")
        net=I.A.H.case(conductors=m,segments=8)
        ps=I.profiles(net,workload;exchange_target_W=m==2 ? 1000. : 1500.,nlp_scaling_method=policy)
        full=build_opf(net,IVRNLP(objective=:power,power_terms=first(ps).options.power_terms));anchor=nothing;objectives=Float64[]
        start=I.E.S.U.G.H.S.L.start_point(net)
        for profile in ps
            row,p=I.P.trial(net,profile,full,anchor;initial_point=start)
            @test row["accepted"]
            row["accepted"] || continue
            anchor===nothing && (anchor=p);push!(objectives,row["objective"])
            @test row["shared_start"].encoded_variables==row["variables"]
            @test row["objective"]≈row["physical_power_objective"] atol=1e-7
            @test row["reused_generator_power_count"]==(profile.options.power_sharing==:generators ? (m==2 ? 1 : 3) : 0)
            @test length(row["observation_sharing_report"])==row["shared_observation_count"]
            if profile.options.linear_elimination==:passive_hybrid
                @test row["elimination"].max_component_buses<=4
                @test !isempty(row["elimination"].component_limit_rejections)
            end
            # A point which passed the unchanged model must fail both audits
            # after an original voltage or line-end rating is tightened.
            for family in (:voltage,:current,:power)
                tight=deepcopy(net)
                if family==:voltage
                    v=abs(p.voltage[("b2","a")]);tight["bus"]["b2"]["v_max"]=fill(1e6,m==2 ? 1 : 3)
                    tight["bus"]["b2"]["v_max"][1]=.9v
                elseif family==:current
                    tight["line"]["l2"]["i_max"]=fill(1e-9,m)
                else
                    tight["line"]["l2"]["s_max"]=fill(1e-9,m==2 ? 1 : 3)
                end
                @test !physical_residuals(tight,p;delta_dispatch=:coil).passed
                @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(profile.options)),p).passed
            end
        end
        @test length(objectives)==10 && maximum(objectives)-minimum(objectives)<1e-6
    end
end

@testset "Structural runner source safety and provenance" begin
    mktempdir() do dir
        net=I.A.H.case(conductors=2,segments=4);path=joinpath(dir,"source.json")
        open(io->JSON3.write(io,net),path,"w")
        @test_throws ArgumentError I.benchmark(path,path)
        r=I.benchmark(path,joinpath(dir,"report.json"))
        @test r["source_unchanged"] && r["network_unchanged"] && r["position_balanced"]
        @test r["ranking"]["objective_comparable"] && length(r["ranking"]["eligible"])==10
        @test r["feeder_input"].runner_sha256==bytes2hex(sha256(read(joinpath(@__DIR__,"../examples/benchmark_ivr_structural_interactions.jl"))))
    end
end
end
