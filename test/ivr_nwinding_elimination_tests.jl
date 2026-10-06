module IVRNWindingEliminationTests
using Test,FormulationLab,JuMP,Ipopt,LinearAlgebra
include("ivr_nwinding_limit_fixtures.jl")
include("sdp_transformer_fixtures.jl")
include("ac_validation_fixtures.jl")
const F=FormulationLab
const SETTINGS=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.,max_iter=500,nlp_scaling_method="gradient-based")
options(sb,lifting)=let o=_nwinding_nonstar_options(sb,lifting)
 IVRNLPOptions(;(k=>(k==:device_elimination ? :all_transformer_currents : getfield(o,k)) for k in fieldnames(IVRNLPOptions))...)
end
function map_certificate(b)
    rep=b.numerical_diagnostics[:device_elimination_report]
    for seed in (1,3)
        y=ComplexF64[sin(seed*k)+im*cos((seed+1)*k) for k in eachindex(b.coordinates.projection)]
        z=[F._linivr_eval(row,y) for row in b.coordinates.reconstruction]
        @test [F._linivr_eval(row,z) for row in b.coordinates.projection]≈y atol=1e-11
        @test all(abs(F._linivr_eval(b.electrical.equations[i],z))<=1e-10*max(1.,sum(abs(a*z[k]) for (k,a) in b.electrical.equations[i])) for i in rep.equation_indices)
    end
end
@testset "Atomic multiwinding block certificates and fallback" begin
    net=_nwinding_nonstar_case();full=build_opf(net,IVRNLP())
    e=full.electrical;maps=F._ivrn_coordinates(e,nothing);device=only(e.nwinding_current_blocks)
    b=build_opf(net,IVRNLP(device_elimination=:all_transformer_currents))
    rep=b.numerical_diagnostics[:device_elimination_report]
    @test rep.transformers==["n_winding/tx"] && isempty(rep.retained_transformers)
    @test rep.eliminated_complex_coordinates==12 && length(rep.equation_indices)==12
    @test rep.block_diagnostics["n_winding/tx"].condition<1e8
    @test rep.block_diagnostics["n_winding/tx"].relative_residual<=1e-12
    map_certificate(b)
    for (record,omitted,reason) in ((device,Set([first(device.equation_indices)]),"current_block_equation_already_consumed"),
        (merge(device,(;equation_indices=device.equation_indices[1:end-1])),Set{Int}(),"incomplete_current_block_record"),
        (merge(device,(;current=fill(first(device.current),length(device.current)))),Set{Int}(),"current_block_not_retained_coordinates"))
        bad=merge(e,(;nwinding_current_blocks=[record]))
        m,o,r=F._ivrn_device_coordinates(net,bad,maps,copy(omitted),:all_transformer_currents)
        @test m==maps && o==omitted && r.eliminated_complex_coordinates==0
        @test r.retained_transformers[device.id]==reason
    end
    for small in (0.,1e-14)
        singular=deepcopy(net);tx=singular["transformer"]["n_winding"]["tx"]
        for w in tx["windings"];w["r_winding"]=0.;end
        # One weak independent leakage direction; no tolerance truncates it.
        tx["x_sc"]=Dict("1_2"=>.1,"1_3"=>.2,"1_4"=>small,"2_3"=>.3,"2_4"=>.1+small,"3_4"=>.2+small)
        full=build_opf(singular,IVRNLP());candidate=build_opf(singular,IVRNLP(device_elimination=:all_transformer_currents))
        r=candidate.numerical_diagnostics[:device_elimination_report]
        @test r.eliminated_complex_coordinates==0 && isempty(r.equation_indices)
        @test r.retained_transformers["n_winding/tx"] in ("singular_local_block","ill_conditioned_local_block","large_current_reconstruction")
        @test candidate.coordinates.projection==full.coordinates.projection && candidate.coordinates.reconstruction==full.coordinates.reconstruction
    end
    ideal,_=_nwinding_limit_case()
    base=build_opf(ideal,IVRNLP(lifting=:powers);optimizer=Ipopt.Optimizer)
    r=solve_ivr_nlp_opf(base;solver_options=SETTINGS)
    retained=build_opf(ideal,IVRNLP(device_elimination=:all_transformer_currents))
    @test r.solve.optimal && ivr_nlp_point_report(retained,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
    @test retained.numerical_diagnostics[:device_elimination_report].eliminated_complex_coordinates==0
end
@testset "Four-winding recovery and lifted solves after current elimination" begin
    for (connection,roll) in ((:YYYY,1),(:YDYY,1),(:YDYY,-1),(:YYYD,1),(:YYYD,-1),(:DYYY,1),(:DYYY,-1)),
        reverse in (false,true),excitation in (false,true),sb in (1e3,1e5)
        net=_nwinding_nonstar_case(;connection,roll,reverse,excitation);original=deepcopy(net)
        full=build_opf(net,IVRNLP(_nwinding_nonstar_options(sb,:powers));optimizer=Ipopt.Optimizer)
        rf=solve_ivr_nlp_opf(full;solver_options=SETTINGS);@test rf.solve.optimal
        anchor=ACPoint(voltage=rf.voltage_candidate,currents=rf.current_candidate)
        for lifting in (:off,:powers,:bounded_observations)
            opts=options(sb,lifting);b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
            @test b.numerical_diagnostics[:device_elimination_report].eliminated_complex_coordinates==12
            @test b.numerical_diagnostics[:solver_state_dimension]==full.numerical_diagnostics[:solver_state_dimension]-12
            @test ivr_nlp_point_report(b,anchor).passed
            map_certificate(b)
            # Unlifted solver failures belong to the optional measurement panel;
            # their exact coordinate/feasible-point certificates still apply.
            lifting==:off && continue
            r=solve_ivr_nlp_opf(b;solver_options=SETTINGS)
            @test r.solve.optimal && physical_residuals(net,r).passed
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(full,point).passed
            @test isapprox(r.objective,rf.objective;atol=1e-7,rtol=1e-6)
            eq=_nwinding_nonstar_equations(net,point)
            @test eq.ampere_turn_A<1e-7 && eq.leakage_V<1e-7 && eq.loss_identity_VA<1e-5
            d=result_dict(b,r);decoded=_nwinding_connection_point(net,d)
            for (k,current) in r.current_candidate
                k[1]==:voltage_source && continue
                @test decoded.currents[k]≈current atol=1e-8
            end
            @test d["_formulationlab"]["device_elimination"]=="all_transformer_currents"
            @test d["_formulationlab"]["device_elimination_report"]["eliminated_complex_coordinates"]==12
            for k in (2,4)
                tight=deepcopy(net);tight["transformer"]["n_winding"]["tx"]["windings"][k]["s_max"]*=.9
                @test !physical_residuals(tight,r).passed && !ivr_nlp_point_report(build_opf(tight,IVRNLP(opts)),point).passed
            end
            bad=deepcopy(r.current_candidate);bad[(:transformer_coil,"n_winding/tx/4")][1]+=.01
            @test !ivr_nlp_point_report(b,ACPoint(voltage=r.voltage_candidate,currents=bad)).passed
            @test net==original
        end
    end
end
@testset "Two/three-winding, fixed taps, finite grounding and updates" begin
    for n in (2,3),phases in (1,3),ground in (0.,2.)
        net,_=_nwinding_limit_case(;phases,rating=nothing)
        tx=net["transformer"]["n_winding"]["tx"]
        if n==2;pop!(tx["windings"]);delete!(net["bus"],"b3");end
        tx["x_sc"]=Dict("$(i)_$j"=>.05 for i in 1:n for j in i+1:n)
        for w in tx["windings"];w["r_winding"]=.01;end
        tx["windings"][2]["tap_ratio"]=1.02
        if ground>0;empty!(net["bus"]["b2"]["perfectly_grounded_terminals"]);tx["windings"][2]["r_neutral"]=ground;end
        b=build_opf(net,IVRNLP(device_elimination=:all_transformer_currents,lifting=:powers,ground_scaling=:voltage);optimizer=Ipopt.Optimizer)
        @test b.numerical_diagnostics[:device_elimination_report].eliminated_complex_coordinates==n*phases
        map_certificate(b);variables=all_variables(b.model)
        for factor in (1.,.8)
            update_ivr_loads!(b,Dict("d"=>(p=factor*net["load"]["d"]["p_nom"],q=zeros(phases))))
            r=solve_ivr_nlp_opf(b;solver_options=SETTINGS)
            @test r.solve.optimal && physical_residuals(b.network,r).passed
            @test ivr_nlp_point_report(build_opf(b.network,IVRNLP()),ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
            @test all_variables(b.model)==variables
        end
    end
    for kind in ("single_phase","center_tap","delta_wye","wye_delta","single_phase_autotransformer","open_delta_regulator")
        net=_sdp_tx_case(kind)
        a=build_opf(net,IVRNLP(device_elimination=:transformer_currents))
        b=build_opf(net,IVRNLP(device_elimination=:all_transformer_currents))
        @test a.coordinates.projection==b.coordinates.projection && a.coordinates.reconstruction==b.coordinates.reconstruction
        @test a.numerical_diagnostics[:device_elimination_report]==b.numerical_diagnostics[:device_elimination_report]
    end
end
@testset "Independent tapped mixed-winding point and every coil bound" begin
    net,point=_audit_nwinding_state()
    @test physical_residuals(net,point;delta_dispatch=:coil).passed
    for sb in (1e3,1e5),lifting in (:off,:powers,:bounded_observations)
        opts=options(sb,lifting);b=build_opf(net,IVRNLP(opts))
        @test b.numerical_diagnostics[:device_elimination_report].eliminated_complex_coordinates==12
        @test ivr_nlp_point_report(b,point).passed
        map_certificate(b)
        for k in 1:4,c in 1:3,field in ("i_max","s_max")
            tight=deepcopy(net);w=tight["transformer"]["n_winding"]["tx"]["windings"][k]
            current=point.currents[(:transformer_coil,"n_winding/tx/$k")]
            tm=w["terminal_map"]
            u=[point.voltage[(w["bus"],tm[j])]-point.voltage[(w["bus"],tm[w["configuration"]=="DELTA" ? mod1(j+1,3) : 4])] for j in 1:3]
            rating=field=="i_max" ? abs.(current) : abs.(u.*conj.(current))
            w[field]=rating.*1.01;w[field][c]=.9rating[c]
            @test !physical_residuals(tight,point;delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(opts)),point).passed
        end
    end
end
end
