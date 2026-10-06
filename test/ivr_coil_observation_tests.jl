module IVRCoilObservationTests
using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/benchmark_ivr_coil_observations.jl")
const O=IVRCoilObservationStudy
const N=O.N
const F=FormulationLab

@testset "Five-arm timing schedule and interruption checkpoints" begin
    a=O.orders("exploration");b=O.orders("confirmation")
    @test length(a)==10
    @test b==reverse(a)
    @test_throws ArgumentError O.orders("unknown")
    for schedule in (a,b)
        @test all(sort(o)==collect(1:5) for o in schedule)
        @test all(count(o->o[k]==j,schedule)==2 for j in 1:5 for k in 1:5)
        @test all(sum(count(==((j,k)),zip(o[1:end-1],o[2:end])) for o in schedule)==2
            for j in 1:5 for k in 1:5 if j!=k)
    end
    mktempdir() do dir
        path=joinpath(dir,"case.json")
        report=Dict{String,Any}("complete"=>false,"ranking"=>nothing,"ledger"=>Any[],
            "profiles"=>[Dict{String,Any}("name"=>"powers","warmup"=>nothing,"trials"=>Any[])])
        O.record_trial!(path,report,1,"warmup",0) do
            before=JSON3.read(read(path,String),Dict{String,Any})
            @test only(before["ledger"])["status"]=="started"
            @test before["profiles"][1]["warmup"]===nothing
            Dict("accepted"=>true,"ipopt_wall_s"=>1.),:point
        end
        O.record_trial!(path,report,1,"measured",1) do
            Dict("accepted"=>false,"ipopt_wall_s"=>2.),nothing
        end
        @test_throws ErrorException O.record_trial!(path,report,1,"measured",2) do
            error("simulated interrupted solve")
        end
        saved=JSON3.read(read(path,String),Dict{String,Any})
        @test [e["status"] for e in saved["ledger"]]==["completed","completed","started"]
        @test saved["profiles"][1]["warmup"]["accepted"]
        @test !only(saved["profiles"][1]["trials"])["accepted"]
        @test !saved["complete"] && saved["ranking"]===nothing
        @test !isfile(path*".pending")
        @test_throws ArgumentError O.run_timing(dir,"exploration")
        @test_throws ArgumentError O.run_timing(dir,"invalid")
    end
end

@testset "Selection follows original coil rows before affine sharing" begin
    for selection in (:all,:coil_voltages,:coil_currents,:coils)
        m=Model();@variable(m,x[1:8],start=.1)
        row(k)=Dict(k=>1.0+0im)
        e=(;devices=[(:transformer_coil,"n_winding/t/1",[row(1)],[row(2)],Dict()),
                     (:load,"d",[row(3)],[row(4)],Dict())])
        m.ext[:ivr_lifting]=F._ivrn_lifting_policy(IVRNLPOptions(lifting=:bounded_observations,
            observation_selection=selection,observation_sharing=:exact),e)
        u=x[1]+x[2]+im*(x[3]+x[4]);v=x[5]+x[6]+im*(x[7]+x[8])
        # A different physical row can compose to the same expression. It does
        # not gain eligibility merely because a selected auxiliary exists.
        z=[u,v,u,v]
        result=[F._ivrn_bound_observation(m,row(k),z) for k in 1:4]
        expected=selection==:all ? 2 : selection==:coils ? 2 : 1
        @test length(m.ext[:ivr_lifting].records)==expected
        @test isequal(result[1],result[3])==(selection in (:all,:coil_currents))
        @test isequal(result[2],result[4])==(selection in (:all,:coil_voltages))
        # Original voltage/current rows shared by another bound stay eligible.
        @test isequal(F._ivrn_bound_observation(m,row(1),z),result[1])
        F._ivrn_bound_power(m,row(3),row(4),z)
        @test count(r->r.kind==:power,m.ext[:ivr_lifting].records)==1
    end
    e=(;devices=[(:transformer_coil_from,"single_phase/t",[Dict(1=>1im)],[Dict(2=>1im)],Dict()),
                 (:transformer_coil_to,"single_phase/t",[Dict(3=>1im)],[Dict(4=>1im)],Dict())])
    p=F._ivrn_lifting_policy(IVRNLPOptions(lifting=:bounded_observations,observation_selection=:coils),e)
    @test length(p.selection_rows)==4
    @test_throws ArgumentError F._ivrn_lifting_policy(IVRNLPOptions(lifting=:bounded_observations,observation_selection=:coils))
end

@testset "Default and inactive selections preserve existing models" begin
    net,_=N.network(2)
    @test_throws ArgumentError build_opf(net,IVRNLP(observation_selection=:approximate))
    for mode in (:off,:powers)
        a=build_opf(net,IVRNLP(lifting=mode))
        for selection in (:coil_voltages,:coil_currents,:coils)
            b=build_opf(net,IVRNLP(lifting=mode,observation_selection=selection))
            @test sprint(show,a.model)==sprint(show,b.model)
            @test b.model.ext[:ivr_lifting].selection_rows===nothing
        end
    end
    p=last(O.profiles(net,:tracking,:all_transformer_currents)).options
    a=build_opf(net,IVRNLP(p));b=build_opf(net,IVRNLP(O.clone(p;observation_selection=:all)))
    @test sprint(show,a.model)==sprint(show,b.model)
    @test a.numerical_diagnostics[:observation_selection]==:all
    for mode in (:transformer_currents,:all_transformer_currents),workload in (:cost,:tracking)
        ps=O.profiles(net,workload,mode)
        for a in ps[2:end],b in ps[2:end]
            changed=Set(k for k in fieldnames(IVRNLPOptions) if JSON3.write(getfield(a.options,k))!=JSON3.write(getfield(b.options,k)))
            @test changed==(a.name==b.name ? Set{Symbol}() : Set([:observation_selection]))
        end
    end
end

@testset "Power objectives, original bounds, starts and auxiliary definitions" begin
    net,templates=N.network(2);start=N.S.start_point(net)
    for workload in (:cost,:tracking),mode in (:transformer_currents,:all_transformer_currents)
        full=build_opf(net,IVRNLP(s_base=1e5,objective=:power,power_terms=N.terms(net,workload),transformer_nameplate=:bmopftools))
        anchor=nothing;objective=nothing
        for p in O.profiles(net,workload,mode)
            b=build_opf(net,IVRNLP(p.options);optimizer=Ipopt.Optimizer)
            @test b.electrical.equations==full.electrical.equations && b.electrical.kcl==full.electrical.kcl
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
            for field in ("i_max","s_max")
                tight=deepcopy(net);tight["transformer"]["n_winding"]["u2_tx"]["windings"][2][field]=0.
                @test !physical_residuals(tight,point;delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed
                @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(p.options)),point).passed
            end
            # Bounds on unselected line observations remain enforced too.
            tight=deepcopy(net);tight["line"]["trunk"]["i_max"]=fill(1e-8,4)
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(p.options)),point).passed
            supplied=ivr_nlp_point_report(b,point)
            observations=filter(q->q.kind==:observation,b.model.ext[:ivr_lifting].records)
            if !isempty(observations)
                q=first(observations);bad=copy(supplied.variable_values);bad[q.real]+=.1
                @test maximum(values(primal_feasibility_report(b.model,bad;atol=0.)))>.09
                selected=b.model.ext[:ivr_lifting].selection_rows
                @test selected===nothing || all(q->q.key[2] in selected,observations)
            end
        end
    end
end

@testset "Single-phase coil-power objectives with selected observations" begin
    for config in ("WYE","SINGLE_PHASE"),selection in (:all,:coil_voltages,:coil_currents,:coils)
        net,_=N.S._nwinding_limit_case(phases=1,rating=100.)
        for w in net["transformer"]["n_winding"]["tx"]["windings"];w["configuration"]=config;end
        opts=IVRNLPOptions(objective=:power,objective_scale=1.,
            power_terms=[IVRPowerTerm(channels=[(:transformer_coil,"n_winding/tx/2",1)],target=50.,quadratic=1.)],
            transformer_nameplate=:bmopftools,lifting=:bounded_observations,
            observation_selection=selection,observation_support_threshold=0)
        b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer);r=solve_ivr_nlp_opf(b;solver_options=N.SETTINGS)
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test r.objective≈0. atol=1e-7
        @test real(only(r.powers[(:transformer_coil,"n_winding/tx/2")]))≈50. atol=1e-5
        p=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        @test ivr_nlp_point_report(build_opf(net,IVRNLP(O.clone(opts;lifting=:off))),p).passed
    end
end
end
