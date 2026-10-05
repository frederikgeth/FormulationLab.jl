using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
isdefined(@__MODULE__,:IVRTransformerStressCases) || include("../examples/ivr_transformer_stress_cases.jl")
isdefined(@__MODULE__,:IVRTransformerScalingStudy) || include("../examples/benchmark_ivr_transformer_scaling.jl")
isdefined(@__MODULE__,:_ground_scaling_case) || include("ivr_ground_scaling_tests.jl")

@testset "Regional ground multiplier and conservative base assignment" begin
    C=IVRTransformerStressCases
    for s_base in (1e3,1e4,1e5),transformer_scaling in (:off,:nominal)
        net=C.case(segments=4)
        b=build_opf(net,IVRNLP(;s_base,transformer_scaling,ground_scaling=:regional_voltage))
        g=b.numerical_diagnostics[:ground_scaling_report]
        @test g.region_assignment.bases["b4"]≈230.
        expected=.5*230^2/s_base
        @test length(g.scaled_terminals)==(expected>1 ? 1 : 0)
        expected>1 && (@test only(g.scaled_terminals).scale≈expected)
        old=build_opf(net,IVRNLP(;s_base,transformer_scaling,ground_scaling=:voltage))
        @test only(old.numerical_diagnostics[:ground_scaling_report].scaled_terminals).scale≈.5*11000^2/s_base
        # A second shunt at the same terminal selects the largest multiplier,
        # without replacing either physical ground law.
        net["shunt"]["second"]=deepcopy(net["shunt"]["finite_ground"])
        net["shunt"]["second"]["G_1_1"]=2.
        b=build_opf(net,IVRNLP(;s_base,ground_scaling=:regional_voltage))
        @test only(b.numerical_diagnostics[:ground_scaling_report].scaled_terminals).scale≈2*230^2/s_base
    end
    net=C.case(segments=2)
    b=build_opf(net,IVRNLP())
    net["voltage_source"]["conflict"]=Dict("bus"=>"mv","terminal_map"=>["a"],"v_magnitude"=>[1000.],"v_angle"=>[0.])
    # Test unit selection separately: this deliberately contradictory source
    # assignment is correctly refused by the full no-load circuit builder.
    _,g=FormulationLab._ivrn_ground_coordinates(net,b.electrical,b.coordinates,:regional_voltage)
    @test all(==("inconsistent_source_bases"),values(g.region_assignment.retained_buses))
    @test only(g.scaled_terminals).scale≈.5*b.electrical.zb
    @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP(ground_scaling=:regional_voltage))
    net=C.case(segments=2);net["shunt"]["finite_ground"]["G_1_1"]=floatmax(Float64)
    @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP(ground_scaling=:regional_voltage))
    net=C.case(segments=2);b=build_opf(net,IVRNLP())
    j=only(keys(b.coordinates.reconstruction[b.electrical.voltage[("b2","n")]]))
    maps=(;projection=b.coordinates.projection,reconstruction=deepcopy(b.coordinates.reconstruction))
    maps.reconstruction[end]=FormulationLab._SDPRow(j=>nextfloat(0.))
    @test_throws IVRNLPInapplicableError FormulationLab._ivrn_ground_coordinates(net,b.electrical,maps,:regional_voltage)
    # Without a voltage transition, regional and legacy policies agree.
    for y in (.5+1im,-1e10im,1e10+2e10im,-1e5+0im)
        net,p=_ground_scaling_case(y)
        b=build_opf(net,IVRNLP(ground_scaling=:regional_voltage))
        old=build_opf(net,IVRNLP(ground_scaling=:voltage))
        @test ivr_nlp_point_report(b,p).passed
        @test only(b.numerical_diagnostics[:ground_scaling_report].scaled_terminals).scale≈only(old.numerical_diagnostics[:ground_scaling_report].scaled_terminals).scale
        bad=copy(p.voltage);bad[("b0","n")]+=.01/y
        @test !ivr_nlp_point_report(b,ACPoint(voltage=bad,currents=p.currents)).passed
    end
end

@testset "Regional ground coordinates compose with charged passive blocks" begin
    net=IVRTransformerStressCases.case(segments=6)
    for line in values(net["line"]),side in ("from","to"),j in 1:2
        line["B_$(side)_$(j)_$(j)"]=j*1e-4
    end
    full=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
    rf=solve_ivr_nlp_opf(full;solver_options=IVRTransformerScalingStudy.P.STRICT)
    @test rf.solve.optimal && physical_residuals(net,rf).passed
    b=build_opf(net,IVRNLP(objective=:source_import,ground_scaling=:regional_voltage,
        transformer_scaling=:nominal,specialization=:conductor_regions,linear_elimination=:passive_blocks,
        device_elimination=:transformer_currents,lifting=:bounded_observations);optimizer=Ipopt.Optimizer)
    @test !isempty(b.numerical_diagnostics[:linear_elimination_report].series_buses)
    p=ACPoint(voltage=rf.voltage_candidate,currents=rf.current_candidate)
    @test ivr_nlp_point_report(b,p).passed
    r=solve_ivr_nlp_opf(b;solver_options=IVRTransformerScalingStudy.P.STRICT)
    @test r.solve.optimal && physical_residuals(net,r).passed
    @test r.objective≈rf.objective atol=1e-4
    @test ivr_nlp_point_report(full,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
end

include("../examples/benchmark_ivr_regional_ground.jl")
@testset "Factorial regional-ground benchmark admission" begin
    G=IVRRegionalGroundStudy
    @test length(G.profiles())==6
    @test_throws ArgumentError G.profiles(nlp_scaling_method="unknown")
    mktempdir() do dir
        path=joinpath(dir,"smoke.json")
        @test_throws ArgumentError G.benchmark(path;repetitions=6)
        r=G.benchmark(path;limit=:current,segments=2)
        @test r["position_balanced"] && r["analytical_admission"]
        @test length(r["ranking"]["eligible"])==6
        @test isfile(path*".input.json") && isfile(path*".manifest.json")
    end
end

@testset "Regional grounds preserve active limits, maps, exports and updates" begin
    C=IVRTransformerStressCases;S=IVRTransformerScalingStudy
    for limit in (:capability,:current,:voltage),transformer_scaling in (:off,:nominal),
        reduction in (:off,:passive_blocks,:transformer_currents)
        net=C.case(;limit,segments=6);expected=C.expected(limit)
        options=IVRNLPOptions(;objective=:source_import,transformer_scaling,ground_scaling=:regional_voltage,
            row_scaling=:composed,lifting=:bounded_observations,observation_sharing=:exact,
            specialization=reduction==:passive_blocks ? :conductor_regions : :off,
            linear_elimination=reduction==:passive_blocks ? :passive_blocks : :off,
            device_elimination=reduction==:transformer_currents ? :transformer_currents : :off)
        b=build_opf(net,IVRNLP(options);optimizer=Ipopt.Optimizer)
        full=build_opf(net,IVRNLP(objective=:source_import))
        start=ivr_nlp_point_report(b,S.L.start_point(net))
        @test isempty(start.missing_channels) && length(start.variable_values)==num_variables(b.model)
        @test max(start.max_binding_residual_pu,start.max_reconstruction_residual_pu)<1e-10
        for (v,x) in start.variable_values;set_start_value(v,x);end
        r=solve_ivr_nlp_opf(b;solver_options=merge(S.P.STRICT,(nlp_scaling_method="none",)))
        @test r.solve.optimal && physical_residuals(net,r).passed
        p=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        @test ivr_nlp_point_report(full,p).passed
        @test r.objective≈expected.source_W atol=1e-4
        @test real(only(r.powers[(:generator,"der")]))≈expected.generator_W atol=1e-4
        @test abs(p.voltage[("b6","a")]-p.voltage[("b6","n")])≈expected.voltage_V atol=1e-5
        @test real(p.currents[(:line_from,"l6")][1])≈expected.current_A atol=1e-6
        y=ComplexF64[sin(k)+im*cos(2k) for k in eachindex(b.coordinates.projection)]
        ev(row,x)=FormulationLab._linivr_eval(row,x)
        z=[ev(row,y) for row in b.coordinates.reconstruction]
        @test [ev(row,z) for row in b.coordinates.projection]≈y atol=1e-10
        d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
        @test isequal(read_result(io),d)
        @test d["bus"]["b6"]["a"]["vr"]≈real(p.voltage[("b6","a")])
        tight=deepcopy(net)
        limit==:capability && (tight["generator"]["der"]["s_max"][1]-=1.)
        limit==:current && (tight["line"]["l6"]["i_max"][1]-=.1)
        limit==:voltage && (tight["bus"]["b6"]["vpn_max"][1]-=.1)
        @test !physical_residuals(tight,p;delta_dispatch=:coil).passed
        @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(options)),p).passed
        variables=all_variables(b.model);maps=deepcopy(b.coordinates.reconstruction)
        # Keep the updated import below the unchanged 5 A line rating.
        update_ivr_loads!(b,Dict("demand"=>(p=[1000.],q=[0.])))
        update_ivr_generators!(b,Dict("der"=>(p_min=[200.],p_max=[200.])))
        rr=solve_ivr_nlp_opf(b;solver_options=S.P.STRICT)
        @test rr.solve.optimal && physical_residuals(b.network,rr).passed
        @test all_variables(b.model)==variables && b.coordinates.reconstruction==maps
    end
end
