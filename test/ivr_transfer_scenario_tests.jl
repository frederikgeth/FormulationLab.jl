module IVRTransferScenarioTests
using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/ivr_transfer_scenarios.jl")
include("../examples/ivr_transfer_specification.jl")
include("../examples/benchmark_ivr_lifting_blocks.jl")
include("../examples/ivr_declared_bound_inventory.jl")
const S=IVRTransferScenarios
const W=IVRTransferSpecification
const L=IVRLiftingBlockStudy
const D=IVRDeclaredBoundInventory

function fixture()
    loads=Dict{String,Any}()
    for cfg in ("WYE","DELTA"),k in 1:3
        id="$(cfg)_$k"
        loads[id]=Dict("bus"=>"b","configuration"=>cfg,
            "terminal_map"=>cfg=="WYE" ? ["a","b","c","n"] : ["a","b","c"],
            "p_nom"=>[1000.,1200.,800.],"q_nom"=>[200.,250.,150.],"model"=>"constant_power")
    end
    Dict{String,Any}("bus"=>Dict("b"=>Dict("terminal_names"=>["a","b","c","n"],
        "perfectly_grounded_terminals"=>["n"],"vpn_min"=>fill(200.,3),"vpn_max"=>fill(260.,3))),
        "load"=>loads,"voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>["a","b","c","n"],
            "v_magnitude"=>[230.,230.,230.,0.],"v_angle"=>[0.,-2pi/3,2pi/3,0.])),
        "meta"=>Dict("note"=>"retained annotation"))
end
scales(n)=Dict(s.load=>fill(s.configuration=="WYE" ? 230. : 230sqrt(3),3) for s in S.select_sites(n))

@testset "Supplemental selection and lossless additions" begin
    n=fixture();before=deepcopy(n);vn=scales(n)
    net,m=S.scenario(n;coil_voltage_V=vn)
    @test n==before && length(m.sites)==length(m.changes)==4
    @test m.original_fields_preserved && m.original_bounds_preserved
    @test !m.active_limits_guaranteed && !m.compiler_invoked && !m.optimizer_invoked
    @test all(net[k]==v for (k,v) in n)
    @test length(net["generator"])==length(net["ibr"])==2
    replay=deepcopy(n)
    for c in m.changes
        @test !haskey(get(replay,c.family,Dict()),c.id) && c.before===nothing
        get!(replay,c.family,Dict{String,Any}())[c.id]=deepcopy(c.after)
    end
    @test replay==net
    for c in reverse(m.changes);delete!(replay[c.family],c.id);end
    for f in m.added_tables;delete!(replay,f);end
    @test replay==n
    perm=deepcopy(n);perm["load"]=Dict(reverse(collect(n["load"])))
    @test S.select_sites(perm)==S.select_sites(n)
    @test first(S.scenario(perm;coil_voltage_V=vn))==net
    # Existing empty tables and unrelated device declarations survive unchanged.
    original=deepcopy(n);original["generator"]=Dict("existing"=>Dict("note"=>"do not alter"));original["ibr"]=Dict()
    augmented,manifest=S.scenario(original;coil_voltage_V=vn)
    @test isempty(manifest.added_tables) && augmented["generator"]["existing"]==original["generator"]["existing"]
    for change in (d->(d[first(keys(d))]=[NaN,230.,230.]),d->pop!(d,first(keys(d))),
                   d->(d[first(keys(d))]=[230.,230.]),d->(d["extra"]=[230.,230.,230.]),
                   d->(d[first(keys(d))]=Any[true,230.,230.]))
        bad=Dict{String,Any}(k=>copy(v) for (k,v) in vn);change(bad)
        @test_throws ArgumentError S.scenario(n;coil_voltage_V=bad)
        @test n==before
    end
    @test_throws ArgumentError S.scenario(net;coil_voltage_V=vn)
    missing=deepcopy(n);filter!(p->p.second["configuration"]!="DELTA",missing["load"])
    @test_throws ArgumentError S.select_sites(missing)
    invalid=deepcopy(n);first(values(invalid["load"]))["p_nom"]=[-1.,1.,1.]
    @test_throws ArgumentError S.select_sites(invalid)
end

@testset "Supplemental mixed-device physical and bound recovery" begin
    original=fixture();net,manifest=S.scenario(original;coil_voltage_V=scales(original))
    # The compiler consumes the same unchanged original records plus additions.
    start=L.start_point(net)
    common=IVRNLPOptions(s_base=1e4,transformer_nameplate=:bmopftools,
        transformer_scaling=:nominal,row_scaling=:composed,ground_scaling=:voltage,
        lifting=:off,lifted_power_base=500.,load_power_lifting=true,observation_sharing=:signed)
    for kind in (:quadratic_cost,:exchange_tracking)
        declaration=W.profiles(net,kind;common,exchange_target_W=5000.)
        reference=build_opf(net,IVRNLP(declaration.reference));anchor=nothing;objective=nothing
        # Full control and both reduced lifting modes with current/zero elimination.
        for profile in declaration.candidates[[1,7,9]]
            b=build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer)
            inventory=D.report(b)
            @test inventory.complete_declared_bound_coverage && inventory.complete_emitted_coverage
            encoded=ivr_nlp_point_report(b,start)
            @test isempty(encoded.missing_channels) && length(encoded.variable_values)==num_variables(b.model)
            @test max(encoded.max_binding_residual_pu,encoded.max_reconstruction_residual_pu)<=1e-10
            for (v,x) in encoded.variable_values;set_start_value(v,x);end
            r=solve_ivr_nlp_opf(b;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,
                acceptable_iter=0,bound_relax_factor=0.,max_iter=200))
            @test r.solve.optimal && physical_residuals(net,r).passed
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(b,point).passed && ivr_nlp_point_report(reference,point).passed
            anchor===nothing && (anchor=point;objective=r.objective)
            @test ivr_nlp_point_report(b,anchor).passed
            @test r.objective≈objective atol=1e-6 rtol=1e-8
            source=sum(r.powers[(:voltage_source,"s")]);p0=real(source)/1000;q0=imag(source)/1000
            expected=kind==:quadratic_cost ? .25p0+.02p0^2+.002q0^2 : (p0-5)^2+q0^2
            for (f,id,k) in declaration.workload.channels.dispatch
                v=r.powers[(f,id)][k]/1000;internal=r.powers[(f==:ibr ? :ibr_internal : f,id)][k]/1000
                midpoint=(net[string(f)][id]["p_min"][k]+net[string(f)][id]["p_max"][k])/2000
                expected+=kind==:quadratic_cost ? .10real(internal)+.02real(v)^2+.002imag(v)^2 :
                    .01*((real(v)-midpoint)^2+imag(v)^2)
            end
            @test r.objective≈expected atol=1e-8
            for (id,d) in net["ibr"]
                loss=sum(real,r.powers[(:ibr_internal,id)])-sum(real,r.powers[(:ibr,id)])
                @test loss≈sum(d["r_filter"].*abs2.(r.current_candidate[(:ibr_internal,id)])) atol=1e-5
                @test loss>0
            end
            exported=result_dict(b,r);io=IOBuffer();write_result(exported,io);seekstart(io)
            @test isequal(read_result(io),exported)
            @test all(net[k]==v for (k,v) in original)
        end
    end
end
end
