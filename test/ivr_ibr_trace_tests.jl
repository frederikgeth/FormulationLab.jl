using Test, FormulationLab, JuMP, JSON3, LinearAlgebra
isdefined(@__MODULE__,:NLRT) || include("ivr_nonlinear_trace_tests.jl")
isdefined(@__MODULE__,:_ibr_state) || include("ivr_ibr_tests.jl")
include("ivr_ibr_provenance_fixtures.jl")

function _ibr_trace_check(b,p)
    c=NLRT.catalog(b);r=NLRT.trace(b,p)
    audit=physical_residuals(b.network,p;delta_dispatch=:coil,ibr_delta_dispatch=:conductor)
    @test !r.complete_model_coverage
    @test c.covered_constraint_count+length(c.outside_scope_constraints)==num_constraints(b.model;count_variable_in_set_constraints=true)
    @test length(unique(q.label for q in c.ibr))==length(c.ibr)
    @test JSON3.read(JSON3.write(r)).complete_model_coverage==false
    for q in r.ibr_power
        expected=only(x.residual for x in audit.records if x.label==q.audit_label)
        @test q.violation_W≈expected atol=1e-8
        @test q.total_power_W≈sum(q.channel_powers_W) atol=1e-8
        @test abs(q.power_expression_gap_W)<1e-8
        @test abs(q.reconciliation_error_W)<1e-8
        @test q.limit_SI==b.network["ibr"][q.id][q.field]
        @test q.source_path==("ibr",q.id,q.field) && q.source_channel===nothing
    end
    for label in unique(q.audit_label for q in r.ibr_voltage)
        @test maximum(q.violation_V for q in r.ibr_voltage if q.audit_label==label)≈
            only(x.residual for x in audit.records if x.label==label) atol=1e-8
    end
    for q in r.ibr_voltage
        @test q.limit_V==b.network["ibr"][q.id]["v_ref_internal"]
        @test q.source_path==("ibr",q.id,"v_ref_internal") && q.source_channel===nothing
        @test q.basis==:filter_internal_coil && q.port==:ibr_internal
        @test q.observation_gap_V<1e-8
        @test q.squared_reconciliation_error===nothing || abs(q.squared_reconciliation_error)<1e-10
    end
    r
end

@testset "IBR availability and DC budgets retain original port totals" begin
    for m in (2,3,4),reverse in (false,true),sb in (1e3,1e5),reduced in (false,true),lifting in (:off,:powers)
        net,p,sp,si=_ibr_state(m;reverse)
        opts=IVRNLPOptions(;s_base=sb,lifting,lifted_power_base=500.,
            specialization=reduced ? :conductor_difference : :off,
            linear_elimination=reduced ? :passive_blocks : :off)
        for field in ("p_avail","p_dc_min","p_dc_max")
            bad=deepcopy(net);d=bad["ibr"]["g"]
            total=sum(real,field=="p_avail" ? sp : si)
            d[field]=field=="p_avail" && reverse ? 0. : total+(field=="p_dc_min" ? 10. : -10.)
            b=build_opf(bad,IVRNLP(opts));r=_ibr_trace_check(b,p)
            q=only(q for q in r.ibr_power if q.field==field)
            @test q.total_power_W≈total atol=1e-8
            @test q.violation_W≈(field=="p_avail" && reverse ? 0. : 10.) atol=1e-8
            @test q.port==(field=="p_avail" ? :ibr : :ibr_internal)
            @test q.basis==(field=="p_avail" ? (m==3 ? :conductor_pcc : :connection_coil) : :filter_internal_coil)
            @test length(q.channel_powers_W)==(m==2 ? 1 : 3)
            @test abs(sum(real,si)-sum(real,sp))>0.1 # Filter losses are observable.
        end
        for offset in (-10.,0.,10.)
            same=deepcopy(net);d=same["ibr"]["g"]
            d["p_dc_min"]=d["p_dc_max"]=sum(real,si)+offset
            b=build_opf(same,IVRNLP(opts));r=_ibr_trace_check(b,p)
            rows=filter(q->startswith(q.field,"p_dc"),NLRT.catalog(b).ibr)
            @test length(rows)==2 && rows[1].constraints==rows[2].constraints
            @test all(q->q.form==:shared_equality,rows)
            @test only(q.violation_W for q in r.ibr_power if q.field=="p_dc_min")≈max(offset,0.) atol=1e-8
            @test only(q.violation_W for q in r.ibr_power if q.field=="p_dc_max")≈max(-offset,0.) atol=1e-8
        end
    end
end

@testset "Internal-voltage reference channels and source-fixed checks" begin
    for m in (2,3,4),sb in (1e3,1e5),lifting in (:off,:bounded_observations)
        net,p,e=_ibr_voltage_witness(m)
        for multiplier in (.9,1.,1.1)
            bad=deepcopy(net);bad["ibr"]["g"]["v_ref_internal"]*=multiplier
            b=build_opf(bad,IVRNLP(;s_base=sb,lifting));r=_ibr_trace_check(b,p)
            @test length(r.ibr_voltage)==length(e)
            for (k,q) in enumerate(r.ibr_voltage)
                @test q.channel==k && q.form==:magnitude_equality && length(q.native)==1
                @test q.magnitude_V≈abs(e[k]) atol=1e-8
                @test q.violation_V≈abs(abs(e[k])-abs(e[1])*multiplier) atol=1e-8
            end
        end
        fixed,p,e=_ibr_voltage_witness(m;filtered=false)
        b=build_opf(fixed,IVRNLP(;s_base=sb,lifting));r=_ibr_trace_check(b,p)
        @test all(q->q.form==:source_fixed_check && isempty(q.native),r.ibr_voltage)
        @test maximum(q.violation_V for q in r.ibr_voltage)<1e-8
        @test all(q->isempty(q.constraints),filter(q->q.kind==:voltage,NLRT.catalog(b).ibr))
        # The omitted voltage row is conditional on source-coordinate fixes.
        # A native assignment violating a fix must expose a physical discrepancy.
        assignment=ivr_nlp_point_report(b,p).variable_values
        k=b.electrical.voltage[("b0","a")]
        row=b.coordinates.reconstruction[k];j,a=only(row)
        assignment[b.coordinates.real_variables[j]]+=.1/real(a)
        shifted=NLRT.trace(b;variable_values=assignment)
        @test maximum(q.violation_V for q in shifted.ibr_voltage)>1.
        @test all(q->isempty(q.native),shifted.ibr_voltage)
        conflict=deepcopy(fixed);conflict["ibr"]["g"]["v_ref_internal"]*=1.01
        @test_throws IVRNLPInapplicableError build_opf(conflict,IVRNLP(;s_base=sb,lifting))
    end
end

@testset "Absent, one-sided, zero and refused IBR declarations" begin
    net,p,_,_=_ibr_state(2);d=net["ibr"]["g"]
    for field in ("p_avail","p_dc_min","p_dc_max");delete!(d,field);end
    d["dc_link_coupled"]=false
    @test isempty(NLRT.catalog(build_opf(net,IVRNLP())).ibr)
    for field in ("p_dc_min","p_dc_max")
        one=deepcopy(net);one["ibr"]["g"]["dc_link_coupled"]=true;one["ibr"]["g"][field]=0.
        b=build_opf(one,IVRNLP());r=_ibr_trace_check(b,p)
        @test length(r.ibr_power)==1 && only(r.ibr_power).field==field
    end
    for field in ("p_avail","p_dc_min","p_dc_max")
        bad=deepcopy(net);bad["ibr"]["g"]["dc_link_coupled"]=true;bad["ibr"]["g"][field]=NaN
        @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    end
    bad=deepcopy(net);bad["ibr"]["g"]["p_dc_max"]=0.
    @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    bad=deepcopy(net);bad["ibr"]["g"]["v_ref_internal"]=230.
    @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
end
