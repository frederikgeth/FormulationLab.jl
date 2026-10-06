module IVRNWindingGroundTests
using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra, JSON3
include("../examples/benchmark_ivr_nwinding_ground.jl")
const G=IVRNWindingGroundStudy
const N=G.N
const F=FormulationLab

@testset "Independent multiwinding finite-ground units" begin
    for y in (.5+0im,1e8+2e8im),sb in (1e3,1e5),txmode in (:off,:nominal_multiwinding)
        net,_=G.network(4;admittance=y);original=deepcopy(net)
        old=build_opf(net,IVRNLP(s_base=sb,ground_scaling=:regional_voltage,transformer_scaling=txmode))
        b=build_opf(net,IVRNLP(s_base=sb,ground_scaling=:regional_multiwinding_voltage,transformer_scaling=txmode))
        report=b.numerical_diagnostics[:ground_scaling_report]
        @test isempty(report.region_assignment.retained_buses)
        @test b.electrical.equations==old.electrical.equations && b.electrical.kcl==old.electrical.kcl
        @test num_variables(b.model)==num_variables(old.model)
        @test num_constraints(b.model;count_variable_in_set_constraints=true)==num_constraints(old.model;count_variable_in_set_constraints=true)
        scales=Dict((q.bus,q.terminal)=>q.scale for q in report.scaled_terminals)
        for (id,s) in net["shunt"]
            k=parse(Int,last(s["bus"]));v=230/2.0^(k-1);key=(s["bus"],only(s["terminal_map"]))
            @test report.region_assignment.bases[s["bus"]]≈v
            @test old.numerical_diagnostics[:ground_scaling_report].region_assignment.bases[s["bus"]]==2300.
            expected=abs(y)*v^2/sb
            @test haskey(scales,key)==(expected>1)
            expected>1 && (@test scales[key]≈expected)
        end
        native=ComplexF64[sin(k)+im*cos(k) for k in eachindex(b.coordinates.projection)]
        z=[F._linivr_eval(row,native) for row in b.coordinates.reconstruction]
        @test [F._linivr_eval(row,z) for row in b.coordinates.projection]≈native atol=1e-10
        @test net==original
    end
    net,_=G.network(2)
    for workload in (:cost,:tracking),representation in [p.name for p in N.profiles(net,:cost,1e5)]
        ps=G.profiles(net,workload,representation)
        @test [p.options.ground_scaling for p in ps]==collect(G.MODES)
        for a in ps,b in ps
            changed=Set(k for k in fieldnames(IVRNLPOptions) if JSON3.write(getfield(a.options,k))!=JSON3.write(getfield(b.options,k)))
            @test changed==(a.name==b.name ? Set{Symbol}() : Set([:ground_scaling]))
        end
    end
    for y in (0.,Inf,NaN,-1.)
        @test_throws ArgumentError G.network(2;admittance=y)
    end
end

@testset "References, conservative fallback and representability" begin
    net,_=G.network(2;admittance=1e8)
    base=build_opf(net,IVRNLP())
    conflict=deepcopy(net)
    conflict["voltage_source"]["extra"]=Dict("bus"=>"u1_b2","v_magnitude"=>[116.])
    _,rep=F._ivrn_ground_coordinates(conflict,base.electrical,base.coordinates,:regional_multiwinding_voltage)
    @test all(==("inconsistent_source_bases"),values(rep.region_assignment.retained_buses))
    @test all(q->q.scale≈1e8*base.electrical.zb,rep.scaled_terminals)
    floating,_=G.network(2);delete!(floating["shunt"],"finite_u2_b2_c")
    before=deepcopy(floating)
    for mode in G.MODES
        @test_throws IVRNLPInapplicableError build_opf(floating,IVRNLP(ground_scaling=mode,transformer_scaling=:nominal_multiwinding))
    end
    @test floating==before
    bad=deepcopy(net);bad["shunt"]["finite_u1_b2_n"]["G_1_1"]=floatmax(Float64)
    @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP(ground_scaling=:regional_multiwinding_voltage,s_base=1e3))
    k=base.electrical.voltage[("u1_b2","n")];j=only(keys(base.coordinates.reconstruction[k]))
    maps=(;projection=base.coordinates.projection,reconstruction=deepcopy(base.coordinates.reconstruction))
    maps.reconstruction[end]=F._SDPRow(j=>nextfloat(0.))
    @test_throws IVRNLPInapplicableError F._ivrn_ground_coordinates(net,base.electrical,maps,:regional_multiwinding_voltage)
    # The multiplier uses assembly S_b, not user-selected regional current units.
    p=last(G.profiles(net,:tracking,"all_transformer_currents__powers"))
    b=build_opf(net,IVRNLP(p.options))
    seeds=Dict(k=>10v for (k,v) in p.options.current_power_bases)
    changed=build_opf(net,IVRNLP(G.clone(p.options;current_power_bases=seeds)))
    @test b.numerical_diagnostics[:ground_scaling_report]==changed.numerical_diagnostics[:ground_scaling_report]
end

@testset "Single-phase ground, analytical power optimum and SI JSON" begin
    for config in ("WYE","SINGLE_PHASE"),reverse in (false,true)
        net,_=N.S._nwinding_limit_case(phases=1,reverse=reverse,rating=100.)
        for w in net["transformer"]["n_winding"]["tx"]["windings"];w["configuration"]=config;end
        net["bus"]["b2"]["perfectly_grounded_terminals"]=String[]
        net["shunt"]=Dict("finite"=>Dict("bus"=>"b2","terminal_map"=>["n"],"G_1_1"=>1e8,"B_1_1"=>0.))
        opts=IVRNLPOptions(objective=:power,power_terms=[IVRPowerTerm(channels=[(:generator,"g",1)],linear=reverse ? -1. : 1.)],
            transformer_nameplate=:bmopftools,transformer_scaling=:nominal_multiwinding,
            ground_scaling=:regional_multiwinding_voltage,row_scaling=:composed,kcl_row_max_base=1000.)
        b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer);r=solve_ivr_nlp_opf(b;solver_options=N.SETTINGS)
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test r.objective≈100. atol=1e-5
        point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        @test ivr_nlp_point_report(build_opf(net,IVRNLP(G.clone(opts;ground_scaling=:off))),point).passed
        d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
        @test isequal(read_result(io),d)
        @test d["bus"]["b2"]["n"]["vr"]≈real(point.voltage[("b2","n")])
        bad=copy(point.voltage);bad[("b2","n")]+=1e-3/1e8
        @test !physical_residuals(net,ACPoint(voltage=bad,currents=point.currents);delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed
    end
end

@testset "Finite-ground network power objectives and full model membership" begin
    net,templates=G.network(2;admittance=1e8);start=N.S.start_point(net)
    for workload in (:cost,:tracking)
        full=build_opf(net,IVRNLP(objective=:power,power_terms=N.terms(net,workload),transformer_nameplate=:bmopftools))
        anchor=nothing;objective=nothing
        for p in G.profiles(net,workload,"all_transformer_currents__bounded_observations")
            b=build_opf(net,IVRNLP(p.options);optimizer=Ipopt.Optimizer)
            encoded=ivr_nlp_point_report(b,start)
            @test isempty(encoded.missing_channels) && length(encoded.variable_values)==num_variables(b.model)
            for (v,x) in encoded.variable_values;set_start_value(v,x);end
            r=solve_ivr_nlp_opf(b;solver_options=N.SETTINGS)
            @test r.solve.optimal && physical_residuals(net,r).passed
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(full,point).passed && ivr_nlp_point_report(b,point).passed
            if anchor===nothing;anchor=point;objective=r.objective;end
            @test ivr_nlp_point_report(b,anchor).passed
            @test r.objective≈objective atol=1e-7 rtol=1e-6
            @test all(q.ampere_turn_A<1e-6 && q.leakage_V<1e-6 && q.loss_identity_VA<1e-3 for q in N.equations(templates,point))
            d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
            @test isequal(read_result(io),d)
            for s in values(net["shunt"])
                b0=s["bus"];t=only(s["terminal_map"])
                @test complex(d["bus"][b0][t]["vr"],d["bus"][b0][t]["vi"])≈point.voltage[(b0,t)]
            end
            tight=deepcopy(net);tight["transformer"]["n_winding"]["u2_tx"]["windings"][2]["i_max"]=0.
            @test !physical_residuals(tight,point;delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(p.options)),point).passed
        end
    end
end

@testset "Live earth return remains finite and auditable" begin
    for invalid in (-1.,Inf,NaN,1im)
        @test_throws ArgumentError G.network(2;earth_return_S=invalid)
    end
    for y in (.5,1e8),workload in (:cost,:tracking)
        net,templates=G.network(2;admittance=y,earth_return_S=1e-3)
        start=N.S.start_point(net);anchor=nothing;objective=nothing
        for p in G.profiles(net,workload,"all_transformer_currents__bounded_observations")[[3,4]]
            b=build_opf(net,IVRNLP(p.options);optimizer=Ipopt.Optimizer)
            for (v,x) in ivr_nlp_point_report(b,start).variable_values;set_start_value(v,x);end
            r=solve_ivr_nlp_opf(b;solver_options=N.SETTINGS)
            @test r.solve.optimal && physical_residuals(net,r).passed
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            if anchor===nothing;anchor=point;objective=r.objective;end
            @test ivr_nlp_point_report(b,anchor).passed
            @test r.objective≈objective atol=1e-7 rtol=1e-6
            @test all(q.ampere_turn_A<1e-6 && q.leakage_V<1e-6 for q in N.equations(templates,point))
            for (id,s) in net["shunt"]
                startswith(id,"finite_") || continue
                key=(s["bus"],only(s["terminal_map"]));v=point.voltage[key]
                @test abs(y*v)>.01 # A physical earth-return path, not just a reference.
                @test abs(v)>0 # Even a stiff ground is not replaced by zero voltage.
            end
            bad=copy(point.voltage);bad[("u1_b2","n")]+=1e-3/y
            @test !physical_residuals(net,ACPoint(voltage=bad,currents=point.currents);delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed
        end
    end
end
end
