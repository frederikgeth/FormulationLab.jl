using Test, FormulationLab, JuMP, Ipopt

_gen_solve(b)=solve_ivr_nlp_opf(b;solver_options=(print_level=0,tol=1e-10,
    bound_relax_factor=0.,obj_scaling_factor=1000.))
_gen_point(r)=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)

@testset "Generator boxes and prices preserve reusable equations" begin
    for specialization in (:off,:conductor_difference),sb in (1e3,1e5)
        net=_ivrn_two_wire();net["voltage_source"]["source"]["cost"]=[.25]
        net["generator"]=Dict("g"=>Dict("bus"=>"load","terminal_map"=>["a","n"],
            "configuration"=>"SINGLE_PHASE","p_min"=>[5000.],"p_max"=>[5000.],
            "q_min"=>[1000.],"q_max"=>[1000.],"energy_cost_rate"=>[.1],"s_max"=>[20_000.]))
        original=deepcopy(net);f=IVRNLP(;specialization,s_base=sb)
        b=build_opf(net,f;optimizer=Ipopt.Optimizer)
        model=b.model;variables=all_variables(model);refs=b.generator_variables["g"]
        for (change,expected) in (
            ((cost=[.1],),5000.),
            ((p_min=[0.],p_max=[8000.],q_min=[-2000.],q_max=[2000.],cost=[.05]),8000.),
            ((cost=[2.],),0.),
            ((p_min=[3000.],p_max=[3000.],q_min=[500.],q_max=[500.],cost=[0.]),3000.),
            ((p_min=nothing,p_max=nothing,q_min=nothing,q_max=nothing,cost=[.05]),nothing),
            ((p_min=[-1000.],p_max=[-1000.],q_min=[0.],q_max=[0.],cost=[.1]),-1000.))
            @test update_ivr_generators!(b,Dict("g"=>change))===b
            fresh=build_opf(b.network,f;optimizer=Ipopt.Optimizer)
            r=_gen_solve(b);a=_gen_solve(fresh)
            @test r.solve.optimal && a.solve.optimal
            @test r.objective ≈ a.objective atol=1e-6
            @test physical_residuals(b.network,_gen_point(r);delta_dispatch=:coil).passed
            @test ivr_nlp_point_report(fresh,_gen_point(r)).passed
            @test ivr_nlp_point_report(b,_gen_point(a)).passed
            expected===nothing || @test real(only(r.powers[(:generator,"g")])) ≈ expected atol=1e-3
            @test b.model===model && all_variables(model)==variables
            @test b.generator_variables["g"]===refs
            @test all(is_valid(model,c) for c in [refs.p_equations;refs.q_equations])
            @test b.numerical_diagnostics[:assembly_count]==1
            @test b.numerical_diagnostics[:structure_analysis_count]==(specialization==:off ? 0 : 1)
            @test b.network["generator"]["g"]["cost"]==b.network["generator"]["g"]["energy_cost_rate"]
        end
        @test net==original
        @test b.numerical_diagnostics[:generator_update_count]==6
        # Loads and dispatch can change on the same compiled instance.
        update_ivr_loads!(b,Dict("load"=>(p=[8000.],q=[1500.])))
        @test physical_residuals(b.network,_gen_point(_gen_solve(b));delta_dispatch=:coil).passed
    end
end

@testset "Generator update validation and ownership" begin
    net=_ivrn_two_wire()
    net["generator"]=Dict(id=>Dict("bus"=>"load","terminal_map"=>["a","n"],
        "configuration"=>"SINGLE_PHASE","p_min"=>[0.],"p_max"=>[2000.],
        "q_min"=>[0.],"q_max"=>[0.],"cost"=>[.1]) for id in ("g1","g2"))
    b=build_opf(net,IVRNLP()) # Validation and coefficient updates need no optimizer.
    before=deepcopy(b.network);objective=copy(objective_function(b.model))
    refs=b.generator_variables["g1"]
    for bad in ((p_min=[3000.],),(p_max=[-1.],),(q_min=[1.],),(cost=[NaN],),
                (p_max=[Inf],),(cost=nothing,),(cost=[true],),(cost=1.,),
                (p_max=[1.,2.],),(energy_cost_rate=[.2],),(i_max=[2.],),NamedTuple())
        @test_throws ArgumentError update_ivr_generators!(b,Dict("g1"=>(cost=[.5],),"g2"=>bad))
        @test b.network==before
        @test isequal(objective_function(b.model),objective)
        @test lower_bound(only(refs.p))==0.
        @test upper_bound(only(refs.p))==.2
        @test b.numerical_diagnostics[:update_count]==0
    end
    @test_throws ArgumentError update_ivr_generators!(b,Dict("missing"=>(cost=[1.],)))
    @test_throws ArgumentError update_ivr_generators!(b,Dict(:g1=>(cost=[1.],)))
    @test update_ivr_generators!(b,Dict())===b
    @test b.numerical_diagnostics[:update_count]==0
    price=[.2];bound=[1500.]
    update_ivr_generators!(b,Dict("g1"=>(cost=price,p_max=bound)))
    price[1]=99.;bound[1]=99.
    @test b.network["generator"]["g1"]["cost"]==[.2]
    @test upper_bound(only(refs.p))==.15
    # Removing only one side, then restoring it, must preserve the other side.
    update_ivr_generators!(b,Dict("g1"=>(p_min=nothing,)))
    @test !has_lower_bound(only(refs.p)) && upper_bound(only(refs.p))==.15
    update_ivr_generators!(b,Dict("g1"=>(p_min=[100.],)))
    @test lower_bound(only(refs.p))==.01
    for objective in (:source_import,:feasibility)
        c=build_opf(net,IVRNLP(;objective));old=copy(objective_function(c.model))
        update_ivr_generators!(c,Dict("g1"=>(cost=[9.],)))
        @test isequal(objective_function(c.model),old)
        @test c.network["generator"]["g1"]["cost"]==[9.]
    end
end

@testset "Reused delta dispatch preserves coil bounds and prices" begin
    for m in (3,4),specialization in (:off,:conductor_difference)
        net=ivr_compiler_case(conductors=m,segments=2)
        net["generator"]=Dict("delta"=>Dict("bus"=>"b2","terminal_map"=>["a","b","c"],
            "configuration"=>"DELTA","p_min"=>zeros(3),"p_max"=>zeros(3),
            "q_min"=>zeros(3),"q_max"=>zeros(3),"cost"=>ones(3),"i_max"=>fill(10.,3)))
        f=IVRNLP(;specialization);b=build_opf(net,f;optimizer=Ipopt.Optimizer)
        for (bound,prices) in (([700.,400.,300.],[.05,.1,.2]),(zeros(3),[.2,.1,.05]))
            update_ivr_generators!(b,Dict("delta"=>(p_max=bound,cost=prices)))
            r=_gen_solve(b);fresh=build_opf(b.network,f;optimizer=Ipopt.Optimizer);a=_gen_solve(fresh)
            @test r.solve.optimal && a.solve.optimal
            @test r.objective ≈ a.objective atol=1e-6
            @test physical_residuals(b.network,_gen_point(r);delta_dispatch=:coil).passed
            @test ivr_nlp_point_report(fresh,_gen_point(r)).passed
            @test ivr_nlp_point_report(b,_gen_point(a)).passed
            @test real.(r.powers[(:generator,"delta")]) ≈ bound atol=1e-3
        end
    end
end

@testset "Shared linecodes retain per-line length and build ownership" begin
    net=ivr_compiler_case(conductors=2,segments=2)
    net["line"]["l1"]["length"]=.5;net["line"]["l2"]["length"]=1.75
    code=net["linecode"]["wire"];code["G_from_1_1"]=1e-5
    b=build_opf(net,IVRNLP())
    lines=Dict(l.id=>l for l in b.electrical.lnc_lines)
    @test lines["l2"].Z ≈ 3.5lines["l1"].Z
    @test lines["l2"].Yf ≈ 3.5lines["l1"].Yf
    @test lines["l1"].Yf[1,1] ≈ .5e-5
    code["R_series_1_1"]*=2
    a=build_opf(net,IVRNLP())
    firstline=only(l for l in a.electrical.lnc_lines if l.id=="l1")
    @test real(firstline.Z[1,1]) ≈ 2real(lines["l1"].Z[1,1])
    @test b.network["linecode"]["wire"]["R_series_1_1"]!=code["R_series_1_1"]
end
