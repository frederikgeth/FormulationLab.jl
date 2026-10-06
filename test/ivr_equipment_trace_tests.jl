using Test, FormulationLab, JuMP, JSON3
isdefined(@__MODULE__,:NLRT) || include("ivr_nonlinear_trace_tests.jl")
isdefined(@__MODULE__,:_bound_case) || include("ivr_bound_coverage_tests.jl")
isdefined(@__MODULE__,:_switch_state) || include("ivr_switch_tests.jl")
isdefined(@__MODULE__,:_ibr_state) || include("ivr_ibr_tests.jl")
isdefined(@__MODULE__,:_nwinding_limit_case) || include("ivr_nwinding_limit_fixtures.jl")

function _equipment_correspondence(net,point;kwargs...)
    b=build_opf(net,IVRNLP(;kwargs...));c=NLRT.catalog(b);r=NLRT.trace(b,point)
    audit=physical_residuals(net,point;delta_dispatch=:coil,ibr_delta_dispatch=:conductor,
        transformer_nameplate=b.options.transformer_nameplate)
    @test !r.complete_model_coverage
    @test length(unique(q.label for q in r.equipment))==length(r.equipment)
    @test c.covered_constraint_count+length(c.outside_scope_constraints)==num_constraints(b.model;count_variable_in_set_constraints=true)
    @test JSON3.read(JSON3.write(r)).complete_model_coverage==false
    for label in unique(q.audit_label for q in r.equipment)
        rows=filter(q->q.audit_label==label,r.equipment)
        original=only(q for q in audit.records if q.label==label)
        @test maximum(q.violation_SI for q in rows)≈original.residual atol=1e-8
    end
    for q in r.equipment
        @test q.limit_SI≈q.declared_value/q.divisor
        @test q.observation_gap_SI<1e-8
        declaration=net
        for key in q.source_path;declaration=declaration[key];end
        @test q.declared_value==(q.source_channel===nothing ? declaration : declaration[q.source_channel])
    end
    b,r
end

@testset "Equipment provenance: inheritance, overrides and supported channel conventions" begin
    for m in (2,3,4)
        net,p=_bound_case(m;shunts=true);n=m==2 ? 1 : 3
        net["linecode"]["wire"]["i_max"]=fill(.1,m)
        net["linecode"]["wire"]["s_max"]=fill(1.,n)
        net["line"]["l1"]["i_max"]=fill(.2,m)
        net["generator"]["g"]["s_max"]=fill(1.,n)
        net["generator"]["g"]["i_max"]=fill(.1,m)
        net["voltage_source"]["source"]["s_max"]=fill(1.,n)
        # Grounded source neutral allocation is intentionally unsupported.
        m==3 && (net["voltage_source"]["source"]["i_max"]=fill(.1,m))
        for reduced in (false,true),lifting in (:off,:bounded_observations),sb in (1e3,1e5)
            b,r=_equipment_correspondence(net,p;s_base=sb,lifting,
                specialization=reduced ? :conductor_difference : :off,
                linear_elimination=reduced ? :passive_blocks : :off)
            @test any(q->q.violation_SI>0,r.equipment)
            @test all(q->q.source_path==("line","l1","i_max"),filter(q->q.family==:line && q.id=="l1" && q.field=="i_max",r.equipment))
            @test all(q->q.source_path==("linecode","wire","s_max"),filter(q->q.family==:line && q.field=="s_max",r.equipment))
            gen=only(q for q in r.equipment if q.family==:generator && q.field=="i_max" && q.channel==1)
            @test gen.current_basis==(m==3 ? :connection_coil : :terminal)
            # Optional provenance must not change the electrical assembly.
            args=(;s_base=sb,delta_dispatch=:coil,ibr_delta_dispatch=:conductor,source_mode=:affine)
            e=FormulationLab._ivr_electrical_data(net;args...,record_limits=true)
            old=FormulationLab._ivr_electrical_data(net;args...)
            @test old.limit_metadata===nothing
            @test e.limits==old.limits && e.equations==old.equations && e.devices==old.devices && e.kcl==old.kcl
            @test [q.index for q in e.limit_metadata]==collect(eachindex(e.limits))
        end
        for reverse in (false,true)
            net,p,_,_=_ibr_state(m;reverse)
            net["ibr"]["g"]["i_max"].=.1;net["ibr"]["g"]["s_max"].=1.
            _,r=_equipment_correspondence(net,p;lifting=:bounded_observations)
            q=only(q for q in r.equipment if q.family==:ibr && q.field=="s_max" && q.channel==1)
            @test q.voltage_basis==(m==3 ? :terminal_to_ground : :connection_coil)
            net,p=_switch_state(m;reverse)
            net["switch"]["s"]["i_max"].=.1;net["switch"]["s"]["s_max"].=1.
            _equipment_correspondence(net,p;lifting=:bounded_observations)
        end
    end
end

@testset "Ordinary transformer limits retain coil, terminal and nameplate meaning" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta","single_phase_autotransformer","open_delta_regulator")
        net,p=_audit_transformer_state(kind;tap=1.03,reverse=true,rotation=.23)
        if kind in ("single_phase_autotransformer","open_delta_regulator")
            p=ACPoint(voltage=p.voltage,currents=merge(p.currents,Dict((:transformer_bond,"$kind/tx")=>ComplexF64[0.])))
        end
        d=net["transformer"][kind]["tx"];d["s_rating"]=1.
        for side in (:from,:to)
            delta=(kind=="delta_wye" && side==:from)||(kind=="wye_delta" && side==:to)
            d["i_max_$side"]=fill(.01,delta ? 3 : length(d["terminal_map_$side"]))
        end
        for policy in (:ignore,:bmopftools),lifting in (:off,:bounded_observations)
            _,r=_equipment_correspondence(net,p;transformer_nameplate=policy,lifting)
            @test length(r.inactive_nameplates)==(policy==:ignore ? 1 : 0)
            caps=filter(q->last(q.source_path)=="s_rating",r.equipment)
            @test isempty(caps)==(policy==:ignore)
            for q in caps
                @test q.current_basis==(kind in ("delta_wye","wye_delta") ? :wye_phase_terminal : :series_coil)
                @test q.divisor==(kind in ("delta_wye","wye_delta") ? 3 : 1)
            end
            for q in filter(q->q.family==:transformer && q.field=="i_max",r.equipment)
                delta=(kind=="delta_wye" && q.side==:from)||(kind=="wye_delta" && q.side==:to)
                @test q.current_basis==(delta ? :series_coil : :terminal)
            end
        end
    end
end

@testset "Winding scalar/vector rating provenance under both policies" begin
    for phases in (1,3),rating in (300.,fill(300.,phases)),policy in (:ignore,:bmopftools)
        net,_=_nwinding_limit_case(;phases,rating)
        net["transformer"]["n_winding"]["tx"]["windings"][2]["i_max"]=1.
        b=build_opf(net,IVRNLP(transformer_nameplate=policy,lifting=:bounded_observations))
        caps=filter(q->q.winding==2,NLRT.catalog(b).equipment)
        @test length(caps)==2phases
        for q in caps
            total=q.field=="s_max" && rating isa Real && policy==:bmopftools
            @test q.divisor==(total ? phases : 1)
            @test q.limit_SI≈q.declared_value/q.divisor
            @test q.current_basis==:series_coil && q.voltage_basis==:connection_coil
            @test q.source_path==("transformer","n_winding","tx","windings",2,q.field)
        end
    end
end

@testset "Zero limits, open-switch tautologies and observation discrepancies" begin
    net,p=_switch_state(2)
    net["switch"]["s"]["i_max"].=0.
    b,r=_equipment_correspondence(net,p)
    @test all(q->q.form==:zero_upper && length(q.native)==2,filter(q->q.family==:switch && q.field=="i_max",r.equipment))
    net["switch"]["s"]["open_switch"]=true
    # Keep the load connected by its line; the open switch is a parallel branch.
    net["line"]["l1"]["bus_to"]="b1";net["switch"]["s"]["bus_from"]="b0"
    delete!(net["bus"],"mid")
    b=build_opf(net,IVRNLP());caps=filter(q->q.family==:switch,NLRT.catalog(b).equipment)
    @test length(caps)==8
    @test all(q->q.form==:identically_zero_upper && isempty(q.constraints),caps)
    net,p=_switch_state(2)
    b,r=_equipment_correspondence(net,p;lifting=:bounded_observations,observation_sharing=:signed,lifted_power_base=500.)
    values=ivr_nlp_point_report(b,p).variable_values
    # Perturb only an auxiliary used by an equipment bound, never the electrical state.
    q=first(q for q in NLRT.catalog(b).equipment if q.field=="s_max")
    variable=only(v for (_,v) in linear_terms(real(q.observation)))
    bad=copy(values);bad[variable]+=.1
    shifted=NLRT.trace(b;variable_values=bad)
    @test [q.magnitude_SI for q in shifted.equipment]==[q.magnitude_SI for q in r.equipment]
    @test maximum(q.observation_gap_SI for q in shifted.equipment)>1.
    @test any(a.native!=z.native for (a,z) in zip(r.equipment,shifted.equipment))
end
