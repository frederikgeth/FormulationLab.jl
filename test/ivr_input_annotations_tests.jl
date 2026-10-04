using Test, FormulationLab, JuMP, Ipopt, JSON3
isdefined(@__MODULE__,:_l3f_case) || include("lindist3flow_fixtures.jl")
isdefined(@__MODULE__,:_sdp_tx_case) || include("sdp_transformer_fixtures.jl")

@testset "IVR annotations retain the declared electrical problem" begin
    net=_l3f_case(explicit_neutral=true)
    net["generator"]=Dict("grid"=>Dict("bus"=>"source","terminal_map"=>["a","n"],
        "configuration"=>"SINGLE_PHASE","p_min"=>[1000.],"p_max"=>[1000.],
        "q_min"=>[0.],"q_max"=>[0.],"cost"=>[2.]))
    baseline=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer)
    result=solve_ivr_nlp_opf(baseline;solver_options=(print_level=0,tol=1e-10))
    @test result.solve.optimal
    point=ACPoint(voltage=result.voltage_candidate,currents=result.current_candidate)
    for slack in (false,true)
        annotated=deepcopy(net)
        annotated["generator"]["grid"]["_slack"]=slack
        for b in values(annotated["bus"])
            b["v_declared"]=400.;b["latitude"]=-27.5;b["longitude"]=153.
        end
        original=deepcopy(annotated)
        # Both raw dictionaries and the PowerIO source-preserving boundary.
        for input in (annotated,read_bmopf(JSON3.write(annotated)))
            build=build_opf(input,IVRNLP())
            @test build.network==annotated
            @test build.electrical.vb==baseline.electrical.vb
            @test num_variables(build.model)==num_variables(baseline.model)
            @test num_constraints(build.model;count_variable_in_set_constraints=true)==num_constraints(baseline.model;count_variable_in_set_constraints=true)
            report=ivr_nlp_point_report(build,point)
            @test report.passed
            @test report.objective ≈ result.objective atol=1e-8
            @test report.objective ≈ 2+real(sum(result.powers[(:voltage_source,"source")]))/1000 atol=1e-8
            @test physical_residuals(annotated,point;delta_dispatch=:coil).passed
            @test build.numerical_diagnostics[:legacy_slack_generators]==(slack ? ["grid"] : String[])
            # The label must not drop or bypass generator bounds/equations.
            @test lower_bound(only(build.generator_variables["grid"].p))==1000/build.electrical.sb
            @test real(only(result.powers[(:generator,"grid")])) ≈ 1000 atol=1e-6
            @test real(sum(result.powers[(:voltage_source,"source")]))>0
        end
        @test annotated==original
    end
    for (field,values) in (("v_declared",(0.,-1.,Inf,NaN,true,"230",[230.])),
                           ("latitude",(-91.,91.,Inf,true)),("longitude",(-181.,181.,NaN,false)))
        for value in values
            bad=deepcopy(net);bad["bus"]["source"][field]=value
            @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
        end
    end
    for value in (1,"true",nothing)
        bad=deepcopy(net);bad["generator"]["grid"]["_slack"]=value
        @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    end
    # Accepting named annotations never becomes a blanket unknown-field pass.
    bad=deepcopy(net);bad["bus"]["source"]["v_setpoint"]=230.
    @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    bad=deepcopy(net);bad["bus"]["source"]["perfectly_grounded_terminals"]=["missing"]
    @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
end

@testset "Exact IVR ordinary transformer schema tap aliases" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta"),bounded in (false,true)
        net=_sdp_tx_case(kind;tap=1.04)
        tx=net["transformer"][kind]["tx"]
        if bounded
            delete!(tx,"tap");tx["tap_min"]=tx["tap_max"]=1.04
        end
        baseline=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer)
        r=solve_ivr_nlp_opf(baseline;solver_options=(print_level=0,tol=1e-10))
        @test r.solve.optimal
        point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        alias=deepcopy(net);at=alias["transformer"][kind]["tx"]
        for suffix in ("","_min","_max")
            haskey(at,"tap"*suffix) && (at["tap_ratio"*suffix]=pop!(at,"tap"*suffix))
        end
        original=deepcopy(alias)
        for input in (alias,read_bmopf(JSON3.write(alias)))
            build=build_opf(input,IVRNLP())
            @test ivr_nlp_point_report(build,point).passed
            @test physical_residuals(alias,point;delta_dispatch=:coil).passed
            @test num_variables(build.model)==num_variables(baseline.model)
            @test build.network["transformer"][kind]["tx"][bounded ? "tap_min" : "tap"]==1.04
        end
        @test alias==original
        # Conflicting spellings are rejected before any model is built.
        at[bounded ? "tap_min" : "tap"]=.95
        @test_throws ArgumentError build_opf(alias,IVRNLP())
    end
    net=_sdp_tx_case("single_phase");tx=net["transformer"]["single_phase"]["tx"]
    delete!(tx,"tap");tx["tap_ratio_min"]=.9;tx["tap_ratio_max"]=1.1
    @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
    tx["tap_ratio"]=1.02
    @test build_opf(net,IVRNLP()) isa IVRNLPBuild
    tx["tap_ratio"]=1.2
    @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
end
