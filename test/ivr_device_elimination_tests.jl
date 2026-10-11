using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
isdefined(@__MODULE__,:_sdp_tx_case) || include("sdp_transformer_fixtures.jl")
isdefined(@__MODULE__,:_audit_transformer_state) || include("ac_validation_fixtures.jl")
isdefined(@__MODULE__,:_ivr_regulator_state) || include("ivr_regulator_tests.jl")
const _DE_SETTINGS=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.,max_iter=500)
isdefined(@__MODULE__,:strict_solve) || include("strict_solve.jl")
_de_solve(b)=strict_solve(b,_DE_SETTINGS)
_de_point(r)=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
function _de_compare(a,b)
    if a isa AbstractDict
        @test keys(a)==keys(b)
        for k in keys(a);_de_compare(a[k],b[k]);end
    elseif a isa AbstractVector
        @test length(a)==length(b)
        for (x,y) in zip(a,b);_de_compare(x,y);end
    elseif a isa Real && b isa Real
        @test (isnan(a)&&isnan(b)) || isapprox(a,b;atol=3e-5,rtol=1e-7)
    else
        @test isequal(a,b)
    end
end

@testset "Delta circulation is retained rather than inferred from terminals" begin
    net=_sdp_tx_case("wye_delta")
    _sdp_zload!(net,"z",["a","b"],.01-.002im)
    full=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);r=_de_solve(full)
    b=build_opf(net,IVRNLP(device_elimination=:transformer_currents))
    @test r.solve.optimal
    key="wye_delta/tx";cs=deepcopy(r.current_candidate);delta=.7+.3im
    # Ideal delta secondary: equal coil-current increments cancel at its
    # terminals. The wye primary and source supply the corresponding currents.
    gain=sqrt(3)/2
    cs[(:transformer_coil_to,key)] .+= delta
    cs[(:transformer_coil_from,key)] .-= gain*delta
    cs[(:transformer_from,key)][1:3] .-= gain*delta
    cs[(:transformer_from,key)][4] += 3gain*delta
    cs[(:voltage_source,"s")][1:3] .-= gain*delta
    p=ACPoint(voltage=r.voltage_candidate,currents=cs)
    @test physical_residuals(net,p;delta_dispatch=:coil).passed
    @test ivr_nlp_point_report(full,p).passed
    @test ivr_nlp_point_report(b,p).passed
    @test p.currents[(:transformer_to,key)]==r.current_candidate[(:transformer_to,key)]
    @test p.currents[(:transformer_coil_to,key)]!=r.current_candidate[(:transformer_coil_to,key)]
end

@testset "Device substitution composes with actual charged-chain elimination" begin
    isdefined(@__MODULE__,:IVRLiftingBlockStudy) || include("../examples/benchmark_ivr_lifting_blocks.jl")
    L=IVRLiftingBlockStudy
    for charged in (false,true),lifting in (:off,:powers,:bounded_observations),ground_scaling in (:off,:voltage)
        net=L.case(segments=8,charged=charged,transformers=true,tight=true)
        shared=L.start_point(net)
        opts=(;objective=:source_import,specialization=:conductor_regions,
            linear_elimination=:passive_blocks,lifting,ground_scaling)
        full=build_opf(net,IVRNLP(;opts...);optimizer=Ipopt.Optimizer)
        b=build_opf(net,IVRNLP(;opts...,device_elimination=:transformer_currents);optimizer=Ipopt.Optimizer)
        @test !isempty(b.numerical_diagnostics[:linear_elimination_report].series_buses)
        @test length(b.numerical_diagnostics[:device_elimination_report].transformers)==2
        @test b.numerical_diagnostics[:solver_state_dimension]==full.numerical_diagnostics[:solver_state_dimension]-2
        for build in (full,b)
            encoded=ivr_nlp_point_report(build,shared)
            @test isempty(encoded.missing_channels)
            @test max(encoded.max_binding_residual_pu,encoded.max_reconstruction_residual_pu)<1e-10
            for (v,x) in encoded.variable_values;set_start_value(v,x);end
        end
        rf=_de_solve(full);r=_de_solve(b)
        @test r.solve.optimal && rf.solve.optimal && physical_residuals(net,r).passed
        @test ivr_nlp_point_report(full,_de_point(r)).passed
        @test ivr_nlp_point_report(b,_de_point(rf)).passed
        @test r.objective ≈ rf.objective atol=1e-5
        variables=all_variables(b.model)
        update_ivr_generators!(b,Dict("g"=>(p_min=[0.],p_max=[0.],q_min=[0.],q_max=[0.])))
        changed=_de_solve(b)
        @test changed.solve.optimal && physical_residuals(b.network,changed).passed
        @test ivr_nlp_point_report(build_opf(b.network,IVRNLP()),_de_point(changed)).passed
        @test all_variables(b.model)==variables
    end
end

@testset "Transformer current graph substitution and original bounds" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta"),reverse in (false,true)
        net,point=_audit_transformer_state(kind;reverse,rotation=.21)
        if reverse
            # Fixture terminal arrays are shared with component maps. Reassign
            # rather than mutate, and permute the bus-indexed limits with them.
            for d in values(net["bus"]),field in ("terminal_names","v_min","v_max")
                d[field]=Base.reverse(d[field])
            end
        end
        tx=net["transformer"][kind]["tx"]
        for side in ("from","to");tx["i_max_$side"]=max.(tx["i_max_$side"],1e-6);end
        original=deepcopy(net);key="$kind/tx"
        full=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
        rf=_de_solve(full);@test rf.solve.optimal
        for specialization in (:off,:conductor_regions),linear_elimination in (:off,:passive_blocks),
            lifting in (:off,:bounded_observations),sb in (1e3,1e5)
            b=build_opf(net,IVRNLP(;s_base=sb,objective=:source_import,specialization,linear_elimination,lifting,
                device_elimination=:transformer_currents);optimizer=Ipopt.Optimizer)
            rep=b.numerical_diagnostics[:device_elimination_report]
            @test rep.transformers==[key] && isempty(rep.retained_transformers)
            @test rep.eliminated_complex_coordinates==length(point.currents[(:transformer_coil_from,key)])
            @test ivr_nlp_point_report(b,point).passed
            y=ComplexF64[sin(k)+im*cos(2k) for k in eachindex(b.coordinates.projection)]
            ev(row,x)=FormulationLab._linivr_eval(row,x)
            z=[ev(row,y) for row in b.coordinates.reconstruction]
            @test [ev(row,z) for row in b.coordinates.projection] ≈ y atol=1e-11
            @test all(i->abs(ev(b.electrical.equations[i],z))<1e-11,rep.equation_indices)
            r=_de_solve(b);@test r.solve.optimal
            @test physical_residuals(net,r).passed
            @test ivr_nlp_point_report(full,_de_point(r)).passed
            @test ivr_nlp_point_report(b,_de_point(rf)).passed
            @test r.objective ≈ rf.objective atol=3e-5 rtol=1e-7
            d=result_dict(b,r);f=result_dict(full,rf)
            for family in ("bus","transformer","load","voltage_source","ground","losses")
                haskey(f,family) && _de_compare(d[family],f[family])
            end
            io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
            changed=deepcopy(point.currents);changed[(:transformer_coil_from,key)][1]+=.1
            @test !ivr_nlp_point_report(b,ACPoint(voltage=point.voltage,currents=changed)).passed
        end
        # Independently constructed feasible point, then tighten each nonzero
        # winding/conductor rating separately on both sides.
        for side in ("from","to"),k in eachindex(tx["i_max_$side"])
            tx["i_max_$side"][k]>1e-5 || continue
            tight=deepcopy(net);tight["transformer"][kind]["tx"]["i_max_$side"][k]*=.5
            b=build_opf(tight,IVRNLP(device_elimination=:transformer_currents,lifting=:bounded_observations))
            @test !ivr_nlp_point_report(b,point).passed
        end
        @test net==original
    end
end

@testset "Independent nonzero regulator bonds and excitation" begin
    for connection in ("ABBC","BCAC","CABA"),rt in ("A","B"),reverse in (false,true),excitation in (1,2)
        net,p=_ivr_regulator_state("open_delta_regulator";connection,rt,reverse,excitation,four=true)
        b=build_opf(net,IVRNLP(device_elimination=:transformer_currents,ground_scaling=:voltage);optimizer=Ipopt.Optimizer)
        @test ivr_nlp_point_report(b,p).passed
        r=_de_solve(b);@test r.solve.optimal && physical_residuals(net,r).passed
        key=(:transformer_bond,"open_delta_regulator/tx")
        @test r.current_candidate[key] ≈ p.currents[key] atol=1e-5
        changed=deepcopy(p.currents);changed[key][1]+=.1
        @test !ivr_nlp_point_report(b,ACPoint(voltage=p.voltage,currents=changed)).passed
    end
end

@testset "Atomic refusal, rectangular ratio and retained multiwinding" begin
    net,_=_audit_transformer_state("delta_wye");b=build_opf(net,IVRNLP())
    e=b.electrical;maps=FormulationLab._ivrn_coordinates(e,nothing)
    rec=only(e.transformer_current_balances);omitted=Set([last(rec.equation_indices)])
    m,o,r=FormulationLab._ivrn_device_coordinates(net,e,maps,copy(omitted),:transformer_currents)
    @test m==maps && o==omitted && r.eliminated_complex_coordinates==0
    @test r.retained_transformers[rec.id]=="balance_equation_already_consumed"
    bad=merge(e,(;transformer_current_balances=[merge(rec,(;equation_indices=rec.equation_indices[1:1]))]))
    m,o,r=FormulationLab._ivrn_device_coordinates(net,bad,maps,Set{Int}(),:transformer_currents)
    @test m==maps && isempty(o) && r.retained_transformers[rec.id]=="incomplete_balance_record"
    net,p=_audit_nwinding_state();b=build_opf(net,IVRNLP(device_elimination=:transformer_currents))
    @test ivr_nlp_point_report(b,p).passed
    rep=b.numerical_diagnostics[:device_elimination_report]
    @test isempty(rep.transformers) && rep.eliminated_complex_coordinates==0
    @test all(==("separate_certificate_required"),values(rep.retained_transformers)) && !isempty(rep.retained_transformers)
    @test_throws ArgumentError build_opf(net,IVRNLP(device_elimination=:unknown))
end

@testset "Zero leakage, excitation, finite grounding, regulator bonds and reuse" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta","single_phase_autotransformer","open_delta_regulator")
        net=_sdp_tx_case(kind;tap=.97)
        tm=net["bus"]["t"]["terminal_names"]
        _sdp_zload!(net,"z",tm[1:2],.01-.002im)
        full=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);r=_de_solve(full);@test r.solve.optimal
        b=build_opf(net,IVRNLP(device_elimination=:transformer_currents,linear_elimination=:impedance_loads);optimizer=Ipopt.Optimizer)
        s=_de_solve(b);@test s.solve.optimal
        @test physical_residuals(net,s).passed
        @test ivr_nlp_point_report(b,_de_point(r)).passed
        @test ivr_nlp_point_report(full,_de_point(s)).passed
        @test b.numerical_diagnostics[:device_elimination_report].eliminated_complex_coordinates>0
    end
    for ground in (0.,2.),winding in (1,2)
        net=_sdp_tx_case("single_phase");empty!(net["bus"]["t"]["perfectly_grounded_terminals"])
        tx=net["transformer"]["single_phase"]["tx"]
        merge!(tx,Dict("r_neutral_to"=>ground,"r_series_to"=>.2,"x_series_to"=>.1,
            "no_load_shunt"=>Dict("winding"=>winding,"g"=>.002,"b"=>-.001)))
        _sdp_zload!(net,"z",["p"],.02-.005im)
        full=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);r=_de_solve(full)
        b=build_opf(net,IVRNLP(device_elimination=:transformer_currents,ground_scaling=:voltage);optimizer=Ipopt.Optimizer);s=_de_solve(b)
        @test r.solve.optimal && s.solve.optimal
        @test physical_residuals(net,s).passed
        @test ivr_nlp_point_report(full,_de_point(s)).passed
        @test ivr_nlp_point_report(b,_de_point(r)).passed
    end
    net,_=_audit_transformer_state("delta_wye")
    for side in ("from","to");net["transformer"]["delta_wye"]["tx"]["i_max_$side"] .*= 2;end
    b=build_opf(net,IVRNLP(device_elimination=:transformer_currents);optimizer=Ipopt.Optimizer)
    variables=all_variables(b.model)
    for factor in (0.,-.5,.7)
        update_ivr_loads!(b,Dict(id=>(p=factor*d["p_nom"],q=factor*d["q_nom"]) for (id,d) in net["load"]))
        r=_de_solve(b);@test r.solve.optimal && physical_residuals(b.network,r).passed
        full=build_opf(b.network,IVRNLP());@test ivr_nlp_point_report(full,_de_point(r)).passed
        @test all_variables(b.model)==variables && b.numerical_diagnostics[:assembly_count]==1
    end
end
