# Loaded after ivr_load_law_tests.jl: reuse independent SI witness construction.
@testset "Voltage-law power auxiliaries preserve physical states and recovery" begin
    for m in (2,3,4),law in ("constant_current","zip","exponential"),direction in (-1.,0.,1.),
        sb in (1e3,1e5),lifting in (:off,:powers,:bounded_observations),reduced in (false,true)
        net,point=_loadlaw_witness(m,law;direction);n=m==2 ? 1 : 3
        opts=IVRNLPOptions(;s_base=sb,lifting,lifted_power_base=1e3,load_power_lifting=true,
            specialization=reduced ? :conductor_difference : :off,
            linear_elimination=reduced ? :passive_blocks : :off,observation_sharing=:signed)
        b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
        report=ivr_nlp_point_report(b,point)
        @test report.passed && length(report.variable_values)==num_variables(b.model)
        @test b.numerical_diagnostics[:load_power_lift_count]==n
        @test b.numerical_diagnostics[:load_power_lifting]
        # Graph equations must reject independently corrupted auxiliary powers.
        lift=first(b.model.ext[:ivr_lifting].records)
        corrupt=copy(report.variable_values);corrupt[lift.real]+=.01
        @test !isempty(primal_feasibility_report(b.model,corrupt;atol=1e-7))
        r=_loadlaw_solve(b)
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test all(isapprox(r.voltage_candidate[k],v;atol=1e-5) for (k,v) in point.voltage)
        @test r.current_candidate[(:load,"d1")]≈point.currents[(:load,"d1")] atol=1e-5
        p=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        old=build_opf(net,IVRNLP(;s_base=sb))
        @test ivr_nlp_point_report(old,p).passed && ivr_nlp_point_report(b,p).passed
        d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
        @test isequal(read_result(io),d)
        @test [complex(x["p"],x["q"]) for x in d["_formulationlab"]["native_powers"]["load"]["d1"]]≈r.powers[(:load,"d1")]
        tight=deepcopy(net);tm=net["bus"]["b1"]["terminal_names"]
        u=point.voltage[("b1",tm[1])]-point.voltage[("b1",tm[m==3 ? 2 : m])]
        tight["bus"]["b1"][m==3 ? "vpp_min" : "vpn_min"][1]=1.01abs(u)
        @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(opts)),point).passed
        @test !physical_residuals(tight,point;delta_dispatch=:coil).passed
    end
end

@testset "Load power lifting preserves defaults and constant-power models" begin
    @test !IVRNLPOptions().load_power_lifting
    for m in (2,3,4),lifting in (:off,:powers,:bounded_observations)
        net=ivr_compiler_case(conductors=m,segments=2)
        a=build_opf(net,IVRNLP(;lifting));b=build_opf(net,IVRNLP(;lifting,load_power_lifting=true))
        @test b.numerical_diagnostics[:load_power_lift_count]==0
        @test num_variables(a.model)==num_variables(b.model)
        @test num_constraints(a.model;count_variable_in_set_constraints=true)==num_constraints(b.model;count_variable_in_set_constraints=true)
    end
end
