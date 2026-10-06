using Test, FormulationLab, JuMP, JSON3
isdefined(@__MODULE__,:_loadlaw_witness) || include("ivr_load_law_tests.jl")
include("../examples/ivr_nonlinear_residual_trace.jl")
const NLRT=IVRNonlinearResidualTrace
include("../examples/benchmark_ivr_voltage_dependencies.jl")

@testset "Load-law physical provenance under coordinate and row scaling" begin
    for m in (2,3,4),law in ("constant_current","zip","exponential"),
        mode in (:direct,:lifted,:scaled),reduced in (false,true)
        net,point=_loadlaw_witness(m,law)
        opts=IVRNLPOptions(s_base=1e5,load_power_lifting=mode!=:direct,
            load_power_base=mode==:direct ? nothing : 500.,
            load_power_row_scaling=mode==:scaled ? :both : :off,
            load_power_row_base=mode==:scaled ? 100. : nothing,
            lifting=:bounded_observations,specialization=reduced ? :conductor_difference : :off,
            linear_elimination=reduced ? :passive_blocks : :off)
        b=build_opf(net,IVRNLP(opts));c=NLRT.catalog(b);r=NLRT.trace(b,point)
        @test length(r.loads)==2length(net["load"]["d1"]["p_nom"])
        @test !r.complete_model_coverage && r.outside_scope_constraint_count>0
        @test c.covered_constraint_count+length(c.outside_scope_constraints)==num_constraints(b.model;count_variable_in_set_constraints=true)
        @test all(q->abs(q.physical_residual_SI)<1e-9 && abs(q.native_residual_SI)<1e-9,r.loads)
        @test all(q->abs(q.reconciliation_error_SI)<1e-9,r.loads)
        @test all(q->q.physical_scale==(mode==:scaled ? 100. : 1e5),r.loads)
        @test all(q->q.violation_V<1e-9,r.bounds)
        @test length(unique(q.label for q in r.bounds))==length(r.bounds)
        @test JSON3.read(JSON3.write(r)).complete_model_coverage==false
        # An auxiliary-only perturbation changes the native rows but leaves
        # the original physical state and its laws unchanged.
        assignment=ivr_nlp_point_report(b,point).variable_values
        record=first(values(b.model.ext[:ivr_load_law_rows]))
        bad=copy(assignment);bad[record.voltage_coordinate]*=1.01
        shifted=NLRT.trace(b;variable_values=bad)
        @test [q.physical_residual_SI for q in shifted.loads]==[q.physical_residual_SI for q in r.loads]
        @test maximum(abs(q.native_residual_SI) for q in shifted.loads)>1e-3
        @test maximum(abs(q.demand_auxiliary_gap_SI) for q in shifted.loads)>1e-3
        @test maximum(abs(q.reconciliation_error_SI) for q in shifted.loads)<1e-9
        if mode!=:direct
            lift=first(filter(q->first(q.key)==:load_law_power,b.model.ext[:ivr_lifting].records))
            bad=copy(assignment);bad[lift.real]+=.01
            shifted=NLRT.trace(b;variable_values=bad)
            @test maximum(abs(q.power_auxiliary_gap_SI) for q in shifted.loads)≈5. atol=1e-9
            @test maximum(abs(q.reconciliation_error_SI) for q in shifted.loads)<1e-9
            @test [q.physical_residual_SI for q in shifted.loads]==[q.physical_residual_SI for q in r.loads]
        end
        bad=copy(assignment);bad[record.voltage_coordinate]=-1.
        @test_throws DomainError NLRT.trace(b;variable_values=bad)
        delete!(bad,record.voltage_coordinate)
        @test_throws ArgumentError NLRT.trace(b;variable_values=bad)
    end
end

@testset "Every original bus-voltage declaration remains traceable" begin
    net,point=_loadlaw_witness(4,"zip")
    d=net["bus"]["b1"]
    for key in ("v_min","vpn_min","vpp_min");d[key]=fill(1e-6,3);end
    for key in ("v_max","vpn_max","vpp_max");d[key]=fill(1000.,3);end
    d["vn_max"]=[100.];d["vpos_min"]=[1e-6]
    for key in ("vpos_max","vneg_max","vzero_max");d[key]=[1000.];end
    # One tightened bound from every family must appear in SI with the same
    # aggregate violation as the independent original-network physical audit.
    for key in ("v_min","v_max","vpn_min","vpn_max","vpp_min","vpp_max",
                "vn_max","vpos_min","vpos_max","vneg_max","vzero_max")
        tight=deepcopy(net)
        tight["bus"]["b1"][key].=endswith(key,"min") ? 500. : 0.01
        b=build_opf(tight,IVRNLP(lifting=:bounded_observations));r=NLRT.trace(b,point)
        audit=physical_residuals(tight,point;delta_dispatch=:coil)
        matches=filter(q->q.bus=="b1" && q.field==key,r.bounds)
        original=only(filter(q->q.label=="bus/b1/$key",audit.records))
        @test maximum(q.violation_V for q in matches)≈original.residual atol=1e-10
        @test original.residual>0
        @test all(q->q.form in (:magnitude_lower,:magnitude_upper),matches)
    end
    # Zero lower bounds and zero observations retain original declarations
    # without inventing constraints for tautologies.
    net,point=_loadlaw_witness(2,"zip")
    net["bus"]["b0"]=Dict{String,Any}(net["bus"]["b0"])
    net["bus"]["b0"]["vn_max"]=[0.]
    net["bus"]["b1"]["v_min"]=[0.]
    b=build_opf(net,IVRNLP());r=NLRT.trace(b,point)
    @test any(q->q.form==:identically_zero_upper && isempty(q.native),r.bounds)
    @test any(q->q.form==:nonnegative_magnitude && isempty(q.native),r.bounds)
    net["bus"]["b1"]["vn_max"]=[0.]
    b=build_opf(net,IVRNLP());r=NLRT.trace(b,point)
    @test any(q->q.form==:zero_upper && length(q.native)==2,r.bounds)
end

@testset "Coincident declarations, constant laws and reusable targets" begin
    net,point=_loadlaw_witness(2,"zip")
    magnitude=abs(point.voltage[("b1","a")]-point.voltage[("b1","n")])
    net["bus"]["b1"]["vpn_min"]=[magnitude];net["bus"]["b1"]["vpn_max"]=[magnitude]
    b=build_opf(net,IVRNLP(coincident_voltage_bounds=:equality));r=NLRT.trace(b,point)
    refs=filter(q->q.b=="b1" && q.key in ("vpn_min","vpn_max"),NLRT.catalog(b).bounds)
    @test length(refs)==2 && refs[1].constraints==refs[2].constraints
    @test all(q->q.form==:coincident_equality,refs)
    @test all(q->q.voltage_definition===nothing,r.loads)
    @test maximum(abs(q.physical_residual_SI) for q in r.loads)<1e-9
    # CP updates must use current targets, not snapshots of the original data.
    net,point=_loadlaw_witness(2,"zip");d=net["load"]["d1"]
    power=(point.voltage[("b1","a")]-point.voltage[("b1","n")])*conj(only(point.currents[(:load,"d1")]))
    for k in ("v_nom","alpha_z","alpha_i","alpha_p","beta_z","beta_i","beta_p");delete!(d,k);end
    d["model"]="constant_power";d["p_nom"]=[real(power)];d["q_nom"]=[imag(power)]
    b=build_opf(net,IVRNLP());r=NLRT.trace(b,point)
    @test maximum(abs(q.physical_residual_SI) for q in r.loads)<1e-9
    update_ivr_loads!(b,Dict("d1"=>(p=[real(power)+100.],q=[imag(power)-25.])))
    r=NLRT.trace(b,point)
    @test [q.physical_residual_SI for q in r.loads]≈[-100.,25.] atol=1e-9
    @test [q.native_residual_SI for q in r.loads]≈[-100.,25.] atol=1e-9
    d["model"]="constant_impedance";d["v_nom"]=[230.]
    c=NLRT.catalog(build_opf(net,IVRNLP()))
    @test isempty(c.loads) && c.linear_loads==["d1"]
    net,point=_loadlaw_witness(2,"zip");delete!(net["bus"]["b1"],"vpn_max")
    r=NLRT.trace(build_opf(net,IVRNLP()),point)
    @test all(q->q.voltage_domain_V.upper===nothing,r.loads)
    @test JSON3.read(JSON3.write(r)).loads[1].voltage_domain_V.upper===nothing
    # Distinct original declarations can share a single guarded equality.
    for n in (2,4)
        net=IVRVoltageDependencyStudy.scenario(;conductors=n,treatment=:duplicate)
        b=build_opf(net,IVRNLP(coincident_voltage_bounds=:guarded_equality))
        refs=filter(q->q.b=="b1" && q.form in (:coincident_equality,:shared_equality),NLRT.catalog(b).bounds)
        @test length(refs)==4*(n==2 ? 1 : 3)
        @test length(Set(only(q.constraints) for q in refs))==(n==2 ? 1 : 3)
        @test count(q->q.form==:shared_equality,refs)==2*(n==2 ? 1 : 3)
    end
end
