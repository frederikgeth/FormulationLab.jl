module IVRNWindingVoltageScalingTests
using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra, JSON3
include("../examples/benchmark_ivr_nwinding_coordinates.jl")
include("ac_validation_fixtures.jl")
const C=IVRNWindingCoordinateStudy
const U=C.U
const N=U.N
const F=FormulationLab
clone(o;kwargs...)=IVRNLPOptions(;merge((; (k=>deepcopy(getfield(o,k)) for k in fieldnames(IVRNLPOptions))...), (;kwargs...))...)

@testset "Prospective coordinate/cap factorial keeps other options fixed" begin
    net,_=N.network(2)
    for workload in (:cost,:tracking),representation in [p.name for p in N.profiles(net,workload,1e5)]
        ps=C.profiles(net,workload,representation)
        @test length(ps)==4 && length(unique(p.name for p in ps))==4
        for a in ps,b in ps
            changed=Set(k for k in fieldnames(IVRNLPOptions) if JSON3.write(getfield(a.options,k))!=JSON3.write(getfield(b.options,k)))
            expected=Set{Symbol}()
            a.factors.nominal_policy!=b.factors.nominal_policy && push!(expected,:transformer_scaling)
            a.factors.kcl_row_max_base_A!==b.factors.kcl_row_max_base_A && push!(expected,:kcl_row_max_base)
            @test changed==expected
        end
        @test all(p.options.current_power_bases==U.seeds(net,1e3,1e3) for p in ps)
    end
    @test_throws ArgumentError C.profiles(net,:cost,"unknown")
end

@testset "Multiwinding characteristic units and conservative graph fallbacks" begin
    net,_=N.network(4);e=(;vb=2300.)
    old=F._ivrn_region_bases(net,e)
    rep=F._ivrn_region_bases(net,e;multiwinding=true)
    @test isempty(rep.retained_buses) && isempty(rep.skipped_transformers)
    @test rep.bases["grid"]==2300. && rep.bases["hub"]==230.
    for u in 1:4,k in 2:4,suffix in ("","_mid","_end")
        @test rep.bases["u$(u)_b$k"*suffix]≈230/2.0^(k-1)
        @test old.bases["u$(u)_b$k"*suffix]==2300.
    end
    taps=deepcopy(net)
    for tx in values(taps["transformer"]["n_winding"]),w in tx["windings"]
        w["tap_ratio"]=1.04;w["delta_roll"]=-1
    end
    @test F._ivrn_region_bases(taps,e;multiwinding=true)==rep
    conflict=deepcopy(net)
    conflict["line"]["conflict"]=Dict("bus_from"=>"u1_b1","bus_to"=>"u1_b2")
    r=F._ivrn_region_bases(conflict,e;multiwinding=true)
    @test all(==("inconsistent_nominal_cycle"),values(r.retained_buses))
    @test length(r.retained_buses)==length(net["bus"])
    unseeded=deepcopy(net);empty!(unseeded["voltage_source"])
    @test all(==("no_nonzero_source_base"),values(F._ivrn_region_bases(unseeded,e;multiwinding=true).retained_buses))
    conflict=deepcopy(net)
    conflict["voltage_source"]["extra"]=Dict("bus"=>"u1_b2","v_magnitude"=>[116.])
    @test all(==("inconsistent_source_bases"),values(F._ivrn_region_bases(conflict,e;multiwinding=true).retained_buses))
    # A bad last winding must not leave the first two edges installed.
    for bad in (0.,Inf,NaN)
        invalid=deepcopy(net);invalid["transformer"]["n_winding"]["u1_tx"]["windings"][4]["v_nom"]=bad
        r=F._ivrn_region_bases(invalid,e;multiwinding=true)
        @test r.skipped_transformers["n_winding/u1_tx"]=="invalid_multiwinding_nominal_contract"
        @test all(r.bases["u1_b$k"]==2300. for k in 2:4)
        @test r.bases["u2_b2"]≈115.
    end
end

@testset "Floating delta common mode remains a physical degree of freedom" begin
    net,p=_audit_nwinding_state()
    net["bus"]["b3"]["perfectly_grounded_terminals"]=String[]
    shifted=deepcopy(p.voltage)
    for t in ("a","b","c");shifted[("b3",t)]+=17+9im;end
    q=ACPoint(voltage=shifted,currents=p.currents)
    @test physical_residuals(net,q;delta_dispatch=:coil).passed
    rep=F._ivrn_region_bases(net,(;vb=230.);multiwinding=true)
    @test rep.bases["b3"]≈57.5/sqrt(3.)
    @test isempty(rep.retained_buses)
    # A numerical base does not repair an absent physical reference. The
    # existing no-load initializer refuses this gauge in both policies.
    for mode in (:nominal,:nominal_multiwinding),elim in (:off,:all_transformer_currents)
        @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP(transformer_scaling=mode,device_elimination=elim,row_scaling=:composed))
    end
    @test isempty(net["bus"]["b3"]["perfectly_grounded_terminals"])

end

@testset "Single-phase unequal turns, analytical power optimum and recovery" begin
    for configuration in ("WYE","SINGLE_PHASE"),reverse in (false,true)
        net,demand=N.S._nwinding_limit_case(phases=1,reverse=reverse,rating=100.)
        for w in net["transformer"]["n_winding"]["tx"]["windings"];w["configuration"]=configuration;end
        opts=IVRNLPOptions(objective=:power,objective_scale=1.,
            power_terms=[IVRPowerTerm(channels=[(:generator,"g",1)],linear=reverse ? -1. : 1.)],
            transformer_nameplate=:bmopftools,transformer_scaling=:nominal_multiwinding,
            row_scaling=:composed,kcl_row_max_base=1000.,lifting=:powers)
        b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
        r=solve_ivr_nlp_opf(b;solver_options=N.SETTINGS)
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test r.objective≈100. atol=1e-5
        @test b.numerical_diagnostics[:transformer_scaling_report].bases["b3"]≈57.5
        p=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        @test ivr_nlp_point_report(build_opf(net,IVRNLP(clone(opts;transformer_scaling=:nominal))),p).passed
    end
end

@testset "Mixed four-unit network: power objectives, maps, bounds and JSON" begin
    net,templates=N.network(4);original=deepcopy(net);start=N.S.start_point(net)
    for workload in (:cost,:tracking)
        full=build_opf(net,IVRNLP(objective=:power,power_terms=N.terms(net,workload),transformer_nameplate=:bmopftools))
        anchor=nothing;objective=nothing
        for representation in [p.name for p in N.profiles(net,workload,1e5)]
            control=clone(first(U.profiles(net,workload,representation)).options;kcl_row_max_base=1000.)
            base=build_opf(net,IVRNLP(control))
            for mode in (:nominal,:nominal_multiwinding)
                opts=clone(control;transformer_scaling=mode)
                b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
                @test b.electrical.equations==base.electrical.equations && b.electrical.kcl==base.electrical.kcl
                @test num_variables(b.model)==num_variables(base.model)
                @test num_constraints(b.model;count_variable_in_set_constraints=true)==num_constraints(base.model;count_variable_in_set_constraints=true)
                @test b.numerical_diagnostics[:ground_scaling_report]==base.numerical_diagnostics[:ground_scaling_report]
                encoded=ivr_nlp_point_report(b,start)
                @test isempty(encoded.missing_channels) && length(encoded.variable_values)==num_variables(b.model)
                for (v,x) in encoded.variable_values;set_start_value(v,x);end
                r=solve_ivr_nlp_opf(b;solver_options=N.SETTINGS)
                @test r.solve.optimal && physical_residuals(net,r).passed
                p=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
                @test ivr_nlp_point_report(full,p).passed && ivr_nlp_point_report(b,p).passed && ivr_nlp_point_report(base,p).passed
                if anchor===nothing;anchor=p;objective=r.objective;end
                @test ivr_nlp_point_report(b,anchor).passed
                @test r.objective≈objective atol=1e-7 rtol=1e-6
                @test all(q.ampere_turn_A<1e-6 && q.leakage_V<1e-6 && q.loss_identity_VA<1e-3 for q in N.equations(templates,p))
                ev(row,x)=F._linivr_eval(row,x)
                y=ComplexF64[sin(k)+im*cos(2k) for k in eachindex(b.coordinates.projection)]
                z=[ev(row,y) for row in b.coordinates.reconstruction]
                @test [ev(row,z) for row in b.coordinates.projection]≈y atol=1e-9
                d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
                @test isequal(read_result(io),d)
                @test d["transformer"]["u2_tx"]["w2"]["1"]["s"]≈abs((p.voltage[("u2_b2","a")]-p.voltage[("u2_b2","b")])*conj(p.currents[(:transformer_coil,"n_winding/u2_tx/2")][1])) atol=1e-7
                for field in ("i_max","s_max")
                    tight=deepcopy(net);w=tight["transformer"]["n_winding"]["u2_tx"]["windings"][2]
                    w[field]=0.
                    @test !physical_residuals(tight,p;delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed
                    @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(opts)),p).passed
                end
            end
        end
    end
    @test net==original
end
end
