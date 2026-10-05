using Test, FormulationLab, JuMP, Ipopt
isdefined(@__MODULE__,:IVRTransformerStressCases) || include("../examples/ivr_transformer_stress_cases.jl")
isdefined(@__MODULE__,:IVRTransformerScalingStudy) || include("../examples/benchmark_ivr_transformer_scaling.jl")

@testset "Transformer cascades with independent active-limit optima" begin
    C=IVRTransformerStressCases;S=IVRTransformerScalingStudy
    for limit in (:capability,:current,:voltage)
        net=C.case(;limit,segments=6);expected=C.expected(limit)
        start=S.L.start_point(net)
        full=build_opf(net,IVRNLP(objective=:source_import))
        for local_scaling in (:off,:nominal),reduction in (:off,:passive_blocks,:transformer_currents)
            b=build_opf(net,IVRNLP(objective=:source_import,transformer_scaling=local_scaling,
                row_scaling=:composed,ground_scaling=:voltage,
                specialization=reduction==:passive_blocks ? :conductor_regions : :off,
                linear_elimination=reduction==:passive_blocks ? :passive_blocks : :off,
                device_elimination=reduction==:transformer_currents ? :transformer_currents : :off);optimizer=Ipopt.Optimizer)
            encoded=ivr_nlp_point_report(b,start)
            @test isempty(encoded.missing_channels)
            @test length(encoded.variable_values)==num_variables(b.model)
            @test max(encoded.max_binding_residual_pu,encoded.max_reconstruction_residual_pu)<1e-10
            for (v,x) in encoded.variable_values;set_start_value(v,x);end
            r=solve_ivr_nlp_opf(b;solver_options=merge(S.P.STRICT,(nlp_scaling_method="none",)))
            @test r.solve.optimal
            @test physical_residuals(net,r).passed
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(full,point).passed
            @test r.objective≈expected.source_W atol=1e-4
            @test real(only(r.powers[(:generator,"der")]))≈expected.generator_W atol=1e-4
            @test abs(point.voltage[("b6","a")]-point.voltage[("b6","n")])≈expected.voltage_V atol=1e-5
            @test real(point.currents[(:line_from,"l6")][1])≈expected.current_A atol=1e-6
            # Tightening precisely the declared active physical limit rejects the
            # accepted original point in both independent SI and encoded audits.
            tight=deepcopy(net)
            limit==:capability && (tight["generator"]["der"]["s_max"][1]-=1.)
            limit==:current && (tight["line"]["l6"]["i_max"][1]-=.1)
            limit==:voltage && (tight["bus"]["b6"]["vpn_max"][1]-=.1)
            @test !physical_residuals(tight,point;delta_dispatch=:coil).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(b.options)),point).passed
        end
    end
    @test_throws ArgumentError C.case(limit=:invalid)
    @test_throws ArgumentError C.case(segments=0)
    @test_throws ArgumentError C.case(ratio=Inf)
end

include("../examples/benchmark_ivr_transformer_stress.jl")
@testset "Analytical benchmark admission and physical input export" begin
    H=IVRTransformerStressStudy
    mktempdir() do dir
        output=joinpath(dir,"pilot.json")
        r=H.benchmark(output;limit=:current,segments=2)
        @test r["analytical_admission"] && r["position_balanced"]
        @test length(r["ranking"]["eligible"])==4
        @test isfile(output*".witness.json") && isfile(output*".input.json")
        saved=H.JSON3.read(read(output,String))
        @test saved.analytical_admission
        @test saved.analytical_expected.source_W==-1150.
    end
end
