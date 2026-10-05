module IVRUnbalancedPowerBaseTests
using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
include("../examples/benchmark_ivr_unbalanced_power_bases.jl")
include("sdp_transformer_fixtures.jl")
include("ac_validation_fixtures.jl")
const U=IVRUnbalancedPowerBaseStudy

@testset "Unequal winding SI witnesses under power-base changes" begin
    # Prescribed SI currents and voltages are constructed without a formulation
    # builder. Both directions and both delta orientations exercise leakage,
    # turns ratios and the schema's winding-versus-terminal rating convention.
    for kind in ("single_phase","delta_wye","wye_delta"),reverse in (false,true),sb in (1e3,1e6)
        net,p=_audit_transformer_state(kind;reverse,current_scale=3.)
        tx=net["transformer"][kind]["tx"]
        for key in ("i_max_from","i_max_to");tx[key]=max.(tx[key],1e-6);end
        @test physical_residuals(net,p;delta_dispatch=:coil).passed
        options=IVRNLPOptions(;s_base=sb,objective_scale=1e4,objective=:source_import,
            transformer_scaling=:nominal,current_power_bases=Dict("f"=>1e5,"t"=>1e3),
            row_scaling=:composed,linear_elimination=:passive_blocks,
            device_elimination=:transformer_currents,lifting=:bounded_observations,observation_sharing=:exact)
        b=build_opf(net,IVRNLP(options));encoded=ivr_nlp_point_report(b,p)
        @test encoded.passed && isempty(encoded.missing_channels)
        @test max(encoded.max_binding_residual_pu,encoded.max_reconstruction_residual_pu)<1e-10
        @test encoded.objective≈ivr_nlp_point_report(build_opf(net,IVRNLP(objective=:source_import)),p).objective
        for side in ("from","to")
            tight=deepcopy(net);tight["transformer"][kind]["tx"]["i_max_$side"][1]*=.9
            @test !physical_residuals(tight,p;delta_dispatch=:coil).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(options)),p).passed
        end
    end
end

@testset "Coupled unbalanced leakage transfer panel" begin
    @test_throws ArgumentError U.case(branches=0)
    @test_throws ArgumentError U.case(segments=0)
    @test_throws ArgumentError U.case(limit=:unknown)
    for limit in (:capability,:current,:voltage)
        net=U.case(;limit,segments=2);start=U.G.H.S.L.start_point(net)
        @test sum(sum(d["p_nom"]) for d in values(net["load"]))≈12600.
        reference=build_opf(net,IVRNLP(objective=:source_import));anchor=nothing;objectives=Float64[]
        for profile in U.G.profiles(net)
            row,p=U.P.trial(net,profile,reference,anchor;initial_point=start)
            @test row["accepted"]
            p===nothing && continue
            anchor===nothing && (anchor=p)
            push!(objectives,row["objective"])
            @test row["objective_scale"]==1e4
            @test row["shared_start"].encoded_variables==row["variables"]
            # Each manufactured case must actually encounter its intended limit.
            if limit==:capability
                @test maximum(abs,Iterators.flatten(values(row["generator_s_max_slack_VA"])))<1e-4
            elseif limit==:current
                @test abs(abs(p.currents[(:line_from,"lv1_l2")][1])-5.)<1e-5
            else
                @test minimum(minimum(v) for v in values(row["vpn_max_slack_V"]))<1e-5
            end
            tight=deepcopy(net)
            # An original receiving-bus voltage bound must survive every map.
            tight["bus"]["lv1_b2"]["vpn_max"][1]=abs(p.voltage[("lv1_b2","a")]-p.voltage[("lv1_b2","n")])-.1
            @test !physical_residuals(tight,p;delta_dispatch=:coil).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(profile.options)),p).passed
        end
        @test length(objectives)==6
        @test maximum(objectives)-minimum(objectives)<1e-4
        # Compose regional current units with exact reductions on the coupled
        # feeder, then recover SI export quantities and check the full model.
        options=IVRNLPOptions(;objective=:source_import,objective_scale=1e4,
            transformer_scaling=:nominal,current_power_bases=Dict("hv"=>1e6,"mv"=>1e5,"lv1_b0"=>1e3,"lv2_b0"=>1e3),
            row_scaling=:composed,ground_scaling=:voltage,specialization=:conductor_regions,
            linear_elimination=:passive_blocks,device_elimination=:transformer_currents,
            lifting=:bounded_observations,observation_sharing=:exact)
        reduced=build_opf(net,IVRNLP(options);optimizer=Ipopt.Optimizer)
        @test ivr_nlp_point_report(reduced,anchor).passed
        encoded=ivr_nlp_point_report(reduced,start)
        @test isempty(encoded.missing_channels) && length(encoded.variable_values)==num_variables(reduced.model)
        for (v,x) in encoded.variable_values;set_start_value(v,x);end
        result=solve_ivr_nlp_opf(reduced;solver_options=U.P.STRICT)
        @test result.solve.optimal && physical_residuals(net,result).passed
        @test isapprox(result.objective,first(objectives);atol=1e-4,rtol=0.)
        point=ACPoint(voltage=result.voltage_candidate,currents=result.current_candidate)
        @test ivr_nlp_point_report(reference,point).passed
        exported=result_dict(reduced,result);io=IOBuffer();write_result(exported,io);seekstart(io)
        @test isequal(read_result(io),exported)
        @test exported["bus"]["lv1_b2"]["a"]["vr"]≈real(point.voltage[("lv1_b2","a")])
    end
end
end
