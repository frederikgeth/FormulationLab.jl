using Test, FormulationLab, JuMP, Ipopt
isdefined(@__MODULE__,:IVRTransformerStressCases) || include("../examples/ivr_transformer_stress_cases.jl")
isdefined(@__MODULE__,:IVRTransformerScalingStudy) || include("../examples/benchmark_ivr_transformer_scaling.jl")

@testset "Power bases preserve analytical optima and original bounds" begin
    C=IVRTransformerStressCases;S=IVRTransformerScalingStudy
    for limit in (:capability,:current,:voltage),sb in (1e3,1e4,1e5,1e6),regional in (false,true)
        net=C.case(;limit,segments=4);w=C.expected(limit)
        seeds=regional ? Dict("hv"=>1e6,"mv"=>1e5,"b0"=>1e3) : Dict{String,Float64}()
        options=IVRNLPOptions(;s_base=sb,objective_scale=1e4,current_power_bases=seeds,
            objective=:source_import,transformer_scaling=:nominal,row_scaling=:composed,ground_scaling=:voltage,
            specialization=:conductor_regions,linear_elimination=:passive_blocks,
            device_elimination=:transformer_currents,lifting=:bounded_observations,observation_sharing=:exact)
        b=build_opf(net,IVRNLP(options);optimizer=Ipopt.Optimizer)
        empty!(seeds) # The build owns its declaration, independently of the caller.
        @test isempty(b.options.current_power_bases)==!regional
        rp=b.numerical_diagnostics[:transformer_scaling_report].power_bases
        @test rp["b4"]==(regional ? 1e3 : sb)
        @test rp["mv"]==(regional ? 1e5 : sb)
        start=ivr_nlp_point_report(b,S.L.start_point(net))
        @test isempty(start.missing_channels) && length(start.variable_values)==num_variables(b.model)
        @test max(start.max_binding_residual_pu,start.max_reconstruction_residual_pu)<1e-10
        for (v,x) in start.variable_values;set_start_value(v,x);end
        r=solve_ivr_nlp_opf(b;solver_options=merge(S.P.STRICT,(nlp_scaling_method="none",)))
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test r.objective≈w.source_W atol=1e-4
        @test objective_value(b.model)*1e4≈r.objective
        p=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        report=ivr_nlp_point_report(b,p)
        @test report.passed && report.objective≈r.objective
        @test ivr_nlp_point_report(build_opf(net,IVRNLP(objective=:source_import)),p).passed
        @test real(only(r.powers[(:generator,"der")]))≈w.generator_W atol=1e-4
        @test real(p.currents[(:line_from,"l4")][1])≈w.current_A atol=1e-6
        d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
        @test d["bus"]["b4"]["a"]["vr"]≈real(p.voltage[("b4","a")])
        tight=deepcopy(net)
        limit==:capability && (tight["generator"]["der"]["s_max"][1]-=1.)
        limit==:current && (tight["line"]["l4"]["i_max"][1]-=.1)
        limit==:voltage && (tight["bus"]["b4"]["vpn_max"][1]-=.1)
        @test !physical_residuals(tight,p;delta_dispatch=:coil).passed
        @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(b.options)),p).passed
        update_ivr_loads!(b,Dict("demand"=>(p=[1000.],q=[0.])))
        update_ivr_generators!(b,Dict("der"=>(p_min=[200.],p_max=[200.])))
        rr=solve_ivr_nlp_opf(b;solver_options=S.P.STRICT)
        @test rr.solve.optimal && physical_residuals(b.network,rr).passed
    end
end

include("../examples/benchmark_ivr_power_bases.jl")
@testset "Aggregate MV/LV power-base study" begin
    P=IVRPowerBaseStudy
    @test_throws ArgumentError P.case(branches=0)
    @test_throws ArgumentError P.case(branches=1000)
    net=P.case(branches=4,segments=2)
    @test length(net["generator"])==4 && length(net["transformer"]["single_phase"])==5
    @test sum(only(d["p_nom"]) for d in values(net["load"]))==8000.
    @test all(p->p.options.objective_scale==1e4,P.profiles(net))
    mktempdir() do dir
        r=P.benchmark(joinpath(dir,"smoke.json");limit=:current,branches=2,segments=2)
        @test r["analytical_admission"] && r["position_balanced"]
        @test length(r["ranking"]["eligible"])==6
    end
end

@testset "Objective divisor, cost updates and power-base region guards" begin
    C=IVRTransformerStressCases;S=IVRTransformerScalingStudy
    for sb in (1e3,1e6),scale in (1.,1e4)
        net=C.case(segments=2);net["voltage_source"]["grid"]["cost"]=[.2,.2]
        net["generator"]["der"]["cost"]=[.1]
        b=build_opf(net,IVRNLP(;s_base=sb,objective_scale=scale,objective=:cost,
            transformer_scaling=:nominal,current_power_bases=Dict("b0"=>1e3));optimizer=Ipopt.Optimizer)
        for cost in (.1,.5)
            update_ivr_generators!(b,Dict("der"=>(cost=[cost],)))
            # Currency/h divided by 1e4 is much smaller than the source-import
            # study objective; tighten solver accuracy for this cost-update test.
            r=solve_ivr_nlp_opf(b;solver_options=merge(S.P.STRICT,(tol=1e-12,)))
            @test r.solve.optimal && physical_residuals(net,r).passed
            pg=real(only(r.powers[(:generator,"der")]))
            ps=sum(real,r.powers[(:voltage_source,"grid")])
            @test r.objective≈(.2ps+cost*pg)/1000 atol=1e-8
            @test objective_value(b.model)*scale≈r.objective
            @test cost==.1 ? isapprox(pg,250.;atol=1e-3) : abs(pg)<1e-3
            p=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(b,p).objective≈r.objective atol=1e-8
        end
    end
    net=C.case(segments=2)
    @test_throws ArgumentError build_opf(net,IVRNLP(objective_scale=0.))
    @test_throws ArgumentError build_opf(net,IVRNLP(objective_scale=Inf))
    @test_throws ArgumentError build_opf(net,IVRNLP(transformer_scaling=:off,current_power_bases=Dict("b0"=>1e3)))
    for seeds in (Dict("absent"=>1e3),Dict("b0"=>0.),Dict("b0"=>Inf),Dict("b0"=>1e3,"b2"=>2e3))
        @test_throws ArgumentError build_opf(net,IVRNLP(transformer_scaling=:nominal,current_power_bases=seeds))
    end
    b=build_opf(net,IVRNLP())
    # A closed switch joins regions; an open one does not.
    net["switch"]=Dict("bridge"=>Dict("bus_from"=>"hv","bus_to"=>"mv","open_switch"=>true))
    bases=FormulationLab._ivrn_current_power_bases(net,b.electrical,Dict("hv"=>1e6,"mv"=>1e5))
    @test bases["hv"]==1e6 && bases["mv"]==1e5 && bases["b2"]==1e4
    net["switch"]["bridge"]["open_switch"]=false
    @test_throws ArgumentError FormulationLab._ivrn_current_power_bases(net,b.electrical,Dict("hv"=>1e6,"mv"=>1e5))
end
