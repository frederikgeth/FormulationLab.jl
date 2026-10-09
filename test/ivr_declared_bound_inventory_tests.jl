module DeclaredBoundInventoryTests
using Test, FormulationLab, JuMP, JSON3
include("../examples/ivr_declared_bound_inventory.jl")
include("../examples/ivr_compiler_cases.jl")
include("sdp_transformer_fixtures.jl")
include("ivr_nwinding_limit_fixtures.jl")
const D=IVRDeclaredBoundInventory

function check(b)
    before=(num_variables(b.model),num_constraints(b.model;count_variable_in_set_constraints=true),deepcopy(b.network))
    c=D.catalog(b);r=D.report(b)
    @test c.complete_declared_bound_coverage && c.complete_emitted_coverage
    @test !c.complete_input_coverage
    @test isempty(c.missing) && isempty(c.mismatched) && isempty(c.unexpected)
    @test c.expected_channel_count==length(c.matched)
    @test JSON3.read(JSON3.write(r)).complete_declared_bound_coverage
    @test JSON3.write(r)==JSON3.write(D.report(b))
    @test before==(num_variables(b.model),num_constraints(b.model;count_variable_in_set_constraints=true),b.network)
    c
end

function fixture(m)
    net=ivr_compiler_case(conductors=m,segments=2);np=m==2 ? 1 : 3
    tm=net["bus"]["b1"]["terminal_names"];bus=net["bus"]["b1"]
    bus["v_min"]=zeros(m);bus["v_max"]=fill(500.,m)
    bus["vpn_min"]=zeros(np);bus["vpn_max"]=fill(500.,np)
    if np==3
        bus["vpp_min"]=zeros(3);bus["vpp_max"]=fill(800.,3)
        bus["vpos_min"]=[0.]
        for field in ("vpos_max","vneg_max","vzero_max");bus[field]=[500.];end
    end
    net["linecode"]["wire"]["s_max"]=fill(1e5,np)
    net["linecode"]["unused"]=deepcopy(net["linecode"]["wire"])
    net["line"]["l1"]["i_max"]=fill(100.,m)
    net["generator"]=Dict("g"=>Dict("bus"=>"b1","terminal_map"=>copy(tm),
        "configuration"=>m==2 ? "SINGLE_PHASE" : m==3 ? "DELTA" : "WYE",
        "p_min"=>zeros(np),"p_max"=>fill(1000.,np),"q_min"=>zeros(np),"q_max"=>zeros(np),
        "s_max"=>fill(1200.,np),"i_max"=>fill(100.,m)))
    source=net["voltage_source"]["source"]
    for field in D.BOX_FIELDS;source[field]=fill(endswith(field,"min") ? -1e5 : 1e5,np);end
    source["s_max"]=fill(1e5,np)
    m==3 && (source["i_max"]=fill(1e3,m))
    net
end

@testset "Scalar declarations and full-terminal source boxes" begin
    for m in (2,3,4)
        net=fixture(m);source=net["voltage_source"]["source"]
        source["p_min"]=fill(-1e5,m);source["p_max"]=fill(1e5,m)
        source["s_max"]=1e5
        if m==2
            net["linecode"]["wire"]["s_max"]=1e5
            source["q_min"]=-1e4
            net["generator"]["g"]["s_max"]=1000.
            net["generator"]["g"]["i_max"]=[100.]
            net["bus"]["b1"]["vpn_min"]=0.
        end
        c=check(build_opf(net,IVRNLP(objective=:feasibility)))
        @test count(q->q.source_path==("voltage_source","source","p_min"),c.matched)==m
        @test all(q->q.source_channel===nothing,filter(q->last(q.source_path)=="s_max" && q.family==:voltage_source,c.matched))
    end
    # Multi-coil generator/line ratings and source currents require explicit
    # arrays; source apparent caps use their separate scalar-broadcast contract.
    net=fixture(3);net["generator"]["g"]["s_max"]=1000.
    @test_throws FormulationLab.IVRNLPInapplicableError build_opf(net,IVRNLP())
    net=fixture(3);net["voltage_source"]["source"]["i_max"]=1000.
    @test_throws FormulationLab.IVRNLPInapplicableError build_opf(net,IVRNLP())
    net=fixture(3);net["linecode"]["wire"]["s_max"]=1000.
    @test_throws FormulationLab.IVRNLPInapplicableError build_opf(net,IVRNLP())
    net=_sdp_tx_case("single_phase");tx=net["transformer"]["single_phase"]["tx"]
    tx["tap_ratio"]=pop!(tx,"tap");tx["tap_ratio_min"]=.9;tx["tap_ratio_max"]=1.1
    c=check(build_opf(net,IVRNLP()))
    @test Set(last(q.source_path) for q in c.fixed_setting_checks)==Set(("tap_min","tap_max","tap_ratio_min","tap_ratio_max"))
    b=build_opf(net,IVRNLP());b.network["transformer"]["single_phase"]["tx"]["tap_ratio_max"]=1.2
    @test_throws ArgumentError D.catalog(b)
end

@testset "Input declarations across channels, units, lifting and inheritance" begin
    for m in (2,3,4),lifting in (:off,:powers,:bounded_observations),reduced in (false,true)
        b=build_opf(fixture(m),IVRNLP(;objective=:feasibility,lifting,
            s_base=reduced ? 1e3 : 1e5,lifted_power_base=500.,
            specialization=reduced ? :conductor_difference : :off))
        c=check(b)
        @test count(q->q.status==:unused_linecode,c.inactive)==2
        @test count(q->q.status==:overridden,c.inactive)==1
        @test count(q->q.source_path==("linecode","wire","i_max"),c.matched)==2m
        @test count(q->q.source_path==("line","l1","i_max"),c.matched)==2m
        @test any(q->q.form==:nonnegative_magnitude && isempty(q.constraints),c.matched)
        update_ivr_generators!(b,Dict("g"=>(p_min=nothing,p_max=fill(200.,m==2 ? 1 : 3))))
        current=check(b)
        @test !any(q->q.source_path==("generator","g","p_min"),current.matched)
        @test all(q->q.limit_SI==200.,filter(q->q.source_path==("generator","g","p_max"),current.matched))
    end
end

@testset "IBR budgets and switches retain scalar and both-end declarations" begin
    for m in (2,3,4),open in (false,true),lifting in (:off,:bounded_observations)
        net=fixture(m);np=m==2 ? 1 : 3;g=deepcopy(net["generator"]["g"])
        delete!(g,"configuration");g["topology"]=m==2 ? "SINGLE_PHASE" : m==3 ? "THREE_LEG" : "FOUR_LEG"
        merge!(g,Dict("p_avail"=>1000.,"dc_link_coupled"=>true,"p_dc_min"=>0.,"p_dc_max"=>0.,
            "grid_forming"=>true,"v_ref_internal"=>230.,"r_filter"=>.2,"x_filter"=>.1))
        net["ibr"]=Dict("i"=>g)
        tm=copy(net["bus"]["b1"]["terminal_names"])
        net["switch"]=Dict("s"=>Dict("bus_from"=>"b0","bus_to"=>"b1", "terminal_map_from"=>tm,
            "terminal_map_to"=>copy(tm),"open_switch"=>open,"i_max"=>zeros(m),"s_max"=>zeros(m)))
        c=check(build_opf(net,IVRNLP(;objective=:feasibility,lifting)))
        @test count(q->q.category==:ibr_limit,c.matched)==np+3
        @test count(q->q.family==:switch,c.matched)==4m
        @test all(q->open ? q.form==:identically_zero_upper : q.form in (:zero_upper,:identically_zero_upper),filter(q->q.family==:switch,c.matched))
        # Closed-switch power on the grounded source neutral is identically zero,
        # while the corresponding current rating still emits a zero equality.
        @test all(q->q.form==(open ? :identically_zero_upper : :zero_upper),
            filter(q->q.family==:switch && last(q.source_path)=="i_max",c.matched))
        budgets=filter(q->q.source_path in (("ibr","i","p_dc_min"),("ibr","i","p_dc_max")),c.matched)
        @test length(budgets)==2 && budgets[1].constraints==budgets[2].constraints
    end
end

@testset "Ordinary nameplate policies and fixed taps are explicit" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta","single_phase_autotransformer","open_delta_regulator"),
            policy in (:ignore,:bmopftools),lifting in (:off,:bounded_observations)
        net=_sdp_tx_case(kind);tx=net["transformer"][kind]["tx"];tx["s_rating"]=1000.
        for side in (:from,:to)
            delta=kind=="delta_wye" && side==:from || kind=="wye_delta" && side==:to
            tx["i_max_$side"]=fill(100.,delta ? 3 : length(tx["terminal_map_$side"]))
        end
        key=kind in ("single_phase_autotransformer","open_delta_regulator") ? "tap_ratio" : "tap"
        tx[key*"_min"]=.9 .* tx[key];tx[key*"_max"]=1.1 .* tx[key]
        b=build_opf(net,IVRNLP(;objective=:feasibility,transformer_nameplate=policy,lifting,
            device_elimination=:transformer_currents,transformer_scaling=:nominal))
        c=check(b)
        @test length(c.fixed_setting_checks)==(kind=="open_delta_regulator" ? 4 : 2)
        @test count(q->q.status==:ignored_nameplate,c.inactive)==(policy==:ignore ? 1 : 0)
        @test any(q->last(q.source_path)=="s_rating",c.matched)==(policy==:bmopftools)
        # Current normalized fixed-setting data is checked, not treated as a solver row.
        b.network["transformer"][kind]["tx"][key*"_max"]=.5 .* tx[key]
        bad=D.report(b)
        @test !bad.complete_declared_bound_coverage && any(q->!q.satisfied,bad.fixed_setting_checks)
    end
end

@testset "Scalar/vector multiwinding caps and base metadata" begin
    for n in (1,3),rating in (300.,fill(300.,n)),policy in (:ignore,:bmopftools)
        net,_=_nwinding_limit_case(;phases=n,rating);d=net["transformer"]["n_winding"]["tx"]
        d["s_rating"]=1000.;w=d["windings"][2];w["s_rating"]=500.;w["i_max"]=10.
        w["tap_ratio_min"]=w["tap_ratio_max"]=1.
        c=check(build_opf(net,IVRNLP(;objective=:feasibility,transformer_nameplate=policy,
            lifting=:bounded_observations,device_elimination=:all_transformer_currents)))
        @test count(q->q.status==:base_metadata,c.inactive)==2
        caps=filter(q->last(q.source_path)=="s_max" && q.family==:transformer,c.matched)
        @test length(caps)==n
        @test all(q->q.limit_SI==(rating isa Real && policy==:bmopftools ? 300/n : 300.),caps)
        @test length(c.fixed_setting_checks)==2
    end
end

@testset "Missing input declarations cannot hide behind emitted completeness" begin
    fresh()=build_opf(fixture(4),IVRNLP(objective=:feasibility))
    b=fresh();rows=b.model.ext[:ivr_bus_limit_rows]
    index=findfirst(q->q.b=="b1" && q.key=="v_max",rows);q=popat!(rows,index)
    foreach(ref->delete(b.model,ref),q.constraints)
    @test D.I.catalog(b).complete_emitted_coverage
    r=D.report(b)
    @test !r.complete_declared_bound_coverage && length(r.missing)==1
    @test only(r.missing).source_path==("bus","b1","v_max")
    @test !JSON3.read(JSON3.write(r)).complete_declared_bound_coverage
    # A declaration with no emitted row is still mandatory provenance.
    b=fresh();rows=b.model.ext[:ivr_bus_limit_rows]
    popat!(rows,findfirst(q->q.form==:nonnegative_magnitude,rows))
    @test D.I.catalog(b).complete_emitted_coverage
    @test !D.catalog(b).complete_declared_bound_coverage
    b=fresh();push!(b.model.ext[:ivr_bus_limit_rows],first(b.model.ext[:ivr_bus_limit_rows]))
    @test_throws ArgumentError D.catalog(b)
    b=fresh();b.network["bus"]["b1"]["v_max"][1]=499.
    @test length(D.report(b).mismatched)==1
    b=fresh();delete!(b.network["bus"]["b1"],"v_max")
    @test length(D.report(b).unexpected)==4
    b=fresh();b.network["bus"]["b1"]["vuf_max"]=.02
    @test_throws ArgumentError D.catalog(b)
    b=fresh();rows=b.model.ext[:ivr_equipment_limit_rows];q=rows[1]
    rows[1]=merge(q,(;divisor=2q.divisor))
    @test length(D.report(b).mismatched)==1
    b=fresh();delete(b.model,first(first(b.model.ext[:ivr_equipment_limit_rows]).constraints))
    @test_throws ArgumentError D.catalog(b)
    # Extra user constraints affect emitted coverage, not the input declarations.
    b=fresh();@constraint(b.model,b.coordinates.real_variables[1]<=500.)
    c=D.catalog(b)
    @test c.complete_declared_bound_coverage && !c.complete_emitted_coverage
    # Two original voltage fields may share one equality without losing either.
    net=fixture(2);net["bus"]["b1"]["vpn_min"]=net["bus"]["b1"]["vpn_max"]=[230.]
    c=check(build_opf(net,IVRNLP(coincident_voltage_bounds=:equality)))
    eq=filter(q->q.source_path in (("bus","b1","vpn_min"),("bus","b1","vpn_max")),c.matched)
    @test length(eq)==2 && eq[1].constraints==eq[2].constraints
    net["bus"]["b1"]["perfectly_grounded_terminals"]=["n"]
    net["bus"]["b1"]["v_min"]=net["bus"]["b1"]["v_max"]=[230.]
    c=check(build_opf(net,IVRNLP(coincident_voltage_bounds=:guarded_equality)))
    shared=filter(q->q.source_path[1:2]==("bus","b1") && last(q.source_path) in
        ("v_min","v_max","vpn_min","vpn_max"),c.matched)
    @test length(shared)==4 && length(Set(only(q.constraints) for q in shared))==1
end
end
