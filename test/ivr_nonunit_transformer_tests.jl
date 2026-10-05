module IVRNonunitTransformerTests
using Test, FormulationLab, JuMP, Ipopt, JSON3, SHA
include("../examples/benchmark_ivr_nonunit_transformers.jl")
const H=IVRNonunitTransformerStudy
shape(x::AbstractDict)=Dict(k=>shape(v) for (k,v) in x)
shape(x::AbstractVector)=shape.(x)
shape(x)=nothing

function solve_profile(net,profile)
    b=build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer)
    start=ivr_nlp_point_report(b,H.E.S.U.G.H.S.L.start_point(net))
    @test length(start.variable_values)==num_variables(b.model)
    @test max(start.max_binding_residual_pu,start.max_reconstruction_residual_pu)<1e-10
    for (v,x) in start.variable_values;set_start_value(v,x);end
    r=solve_ivr_nlp_opf(b;solver_options=merge(H.P.STRICT,profile.solver_options))
    @test r.solve.optimal && physical_residuals(net,r).passed
    b,r,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
end

@testset "Non-unit transformer profiles isolate threshold and sharing" begin
    net=H.case();ps=H.profiles(net,:quadratic_cost)
    @test length(ps)==8 && allunique(p.name for p in ps)
    for a in ps[3:end],b in ps[3:end]
        changed=Set(k for k in fieldnames(IVRNLPOptions) if JSON3.write(getfield(a.options,k))!=JSON3.write(getfield(b.options,k)))
        expected=Set(k for k in (:observation_sharing,:observation_support_threshold) if getfield(a.options,k)!=getfield(b.options,k))
        @test changed==expected
    end
    ps[3].options.generator_power_bases["r1_der"]=123.
    @test all(p.options.generator_power_bases["r1_der"]==1e4 for p in ps[[1,2,4,5,6,7,8]])
    for kwargs in ((;branches=0),(;segments=1),(;ratio=Inf),(;ratio=.5),(;limit_side=:bad))
        @test_throws ArgumentError H.case(;kwargs...)
    end
    @test_throws ArgumentError H.profiles(net,:exchange_tracking)
end

@testset "Physical winding sharing, original bounds, powers and SI exports" begin
    scenarios=[(;ratio=1.,leakage=false,reverse=false,limit_side=:none),
        (;ratio=8.,leakage=false,reverse=false,limit_side=:from),
        (;ratio=8.,leakage=true,reverse=false,limit_side=:to),
        (;ratio=8.,leakage=true,reverse=true,limit_side=:to)]
    for scenario in scenarios,workload in (:quadratic_cost,:exchange_tracking),policy in ("none","gradient-based")
        net=H.case(;segments=4,scenario...)
        ps=H.profiles(net,workload;exchange_target_W=500.,nlp_scaling_method=policy)
        reference,rf,anchor=solve_profile(net,first(ps));reference_export=result_dict(reference,rf)
        for profile in ps
            b,r,p=solve_profile(net,profile)
            @test ivr_nlp_point_report(reference,p).passed && ivr_nlp_point_report(b,anchor).passed
            @test r.objective≈rf.objective atol=1e-7 rtol=1e-7
            @test Set(keys(r.powers))==Set(keys(rf.powers))
            @test all(isapprox(s,rf.powers[key];atol=1e-3,rtol=1e-6) for (key,s) in r.powers)
            report=H.observation_audit(b)
            @test report.max_relative_error<1e-12
            if profile.name ∉ ("full_powers","reduced_powers")
                for w in report.windings
                    @test w.factor_to_from==(scenario.reverse ? -inv(scenario.ratio) : -scenario.ratio)
                    @test w.both_lifted==(profile.options.observation_support_threshold==0)
                    @test w.shared_auxiliary==(profile.options.observation_support_threshold==0 &&
                        (profile.options.observation_sharing==:proportional ||
                         scenario.ratio==1 && profile.options.observation_sharing==:signed))
                end
            end
            exported=result_dict(b,r);io=IOBuffer();write_result(exported,io);seekstart(io)
            @test isequal(read_result(io),exported)
            for family in ("bus","line","transformer","generator","voltage_source","ground","load")
                @test shape(exported[family])==shape(reference_export[family])
            end
            for (id,tx) in net["transformer"]["single_phase"],side in ("from","to")
                current=abs(p.currents[(Symbol("transformer_",side),"single_phase/$id")][1])
                @test current>1e-4
                tight=deepcopy(net);tight["transformer"]["single_phase"][id]["i_max_$side"][1]=.9current
                @test !physical_residuals(tight,p;delta_dispatch=:coil).passed
                @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(profile.options)),p).passed
            end
            if workload==:quadratic_cost && scenario.limit_side!=:none
                side=string(scenario.limit_side);id="r1_downstream"
                @test abs(p.currents[(Symbol("transformer_",side),"single_phase/$id")][1])≈
                    net["transformer"]["single_phase"][id]["i_max_$side"][1] atol=1e-5
            end
            # Neutral-voltage proportional observations retain original limits too.
            for (bus,field,k) in (("r1_b2","vn_max",1),("r1_b2","vpn_max",1))
                tight=deepcopy(net)
                magnitude=field=="vn_max" ? abs(p.voltage[(bus,"n")]) : abs(p.voltage[(bus,"a")]-p.voltage[(bus,"n")])
                @test magnitude>1e-4
                tight["bus"][bus][field][k]=.9magnitude
                @test !physical_residuals(tight,p;delta_dispatch=:coil).passed
                @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(profile.options)),p).passed
            end
        end
    end
end

@testset "Independent ideal-cascade optimum and reusable physical updates" begin
    expected=H.IVRTransformerStressCases.expected(:capability)
    for ratio in (1.,8.),reverse in (false,true)
        net=H.case(;branches=2,segments=4,ratio,reverse)
        # The benchmark profile builder requires dispatch freedom. Freeze its
        # objective/options before fixing dispatch for this analytical check.
        profiles=filter(p->p.name in ("full_powers","proportional_t0"),H.profiles(net,:quadratic_cost))
        for g in values(net["generator"])
            g["p_min"]=g["p_max"]=[250.];g["q_min"]=g["q_max"]=[0.]
        end
        for profile in profiles
            b,r,p=solve_profile(net,profile)
            @test sum(real,r.powers[(:voltage_source,"grid")])≈2expected.source_W atol=1e-4
            for branch in 1:2
                @test real(only(r.powers[(:generator,"r$(branch)_der")]))≈250. atol=1e-5
                @test real(p.currents[(:line_from,"r$(branch)_l4")][1])≈expected.current_A atol=1e-6
            end
        end
    end
    net=H.case(;leakage=true,reverse=true)
    profile=only(p for p in H.profiles(net,:quadratic_cost) if p.name=="proportional_t0")
    b,r,p=solve_profile(net,profile);vars=all_variables(b.model)
    update_ivr_loads!(b,Dict("r1_demand"=>(p=[1800.],q=[100.])))
    update_ivr_generators!(b,Dict("r1_der"=>(p_min=[500.],p_max=[500.],q_min=[0.],q_max=[0.])))
    updated=solve_ivr_nlp_opf(b;solver_options=merge(H.P.STRICT,profile.solver_options))
    @test updated.solve.optimal && physical_residuals(b.network,updated).passed
    @test vars==all_variables(b.model)
    @test H.observation_audit(b).max_relative_error<1e-12
    @test all(w.shared_auxiliary for w in H.observation_audit(b).windings)
end

@testset "Non-unit runner preserves source and named provenance" begin
    mktempdir() do dir
        path=joinpath(dir,"source.json");open(io->JSON3.write(io,H.case(segments=2)),path,"w")
        @test_throws ArgumentError H.benchmark(path,path)
        r=H.benchmark(path,joinpath(dir,"result.json"))
        @test r["source_unchanged"] && r["network_unchanged"] && r["position_balanced"]
        @test length(r["ranking"]["eligible"])==8
        @test r["feeder_input"].runner_sha256==bytes2hex(sha256(read(joinpath(@__DIR__,"../examples/benchmark_ivr_nonunit_transformers.jl"))))
    end
end
end
