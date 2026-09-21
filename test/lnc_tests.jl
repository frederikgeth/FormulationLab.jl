@testset "LNC normalized coefficients and unbalanced rank-one validity" begin
    m=Model();@variable(m,x);@variable(m,y);@variable(m,re);@variable(m,imagpart)
    for scale in (1.0,230.0),phi in (0.0,2pi/3,pi,-pi/2),delta in (0.0,0.2)
        b=LNCBounds(scale.*(0.9,1.1),scale.*(0.8,1.3),(phi-delta,phi+delta))
        refs=add_lnc!(m,x,y,re,imagpart,b)
        # Independently evaluate the original, unnormalized PowerModels formulas.
        for ru in scale.*[0.9,1.0,1.1],rv in scale.*[0.8,1.05,1.3],theta in (phi-delta,phi,phi+delta)
            uv=ru*rv*cis(theta);point=Dict(x=>ru^2,y=>rv^2,re=>real(uv),imagpart=>imag(uv))
            lu,hu=b.u;lv,hv=b.v;su=lu+hu;sv=lv+hv;k=cos(delta);c=real(cis(-phi)*uv)
            original=(su*sv*c-hv*k*sv*ru^2-hu*k*su*rv^2-hu*hv*k*(lu*lv-hu*hv),
                      su*sv*c-lv*k*sv*ru^2-lu*k*su*rv^2-lu*lv*k*(hu*hv-lu*lv))
            for (ref,expected) in zip(refs.cuts,original)
                obj=constraint_object(ref);res=value(v->point[v],obj.func)-obj.set.lower
                @test res ≈ expected/(hu^2*hv^2) atol=2e-14
                @test res >= -2e-14
            end
        end
    end
    for args in (((0,1),(1,2),(0,.1)),((1,Inf),(1,2),(0,.1)),((1,2),(1,2),(0,pi)),((1,2),(1,2),(.1,-.1)))
        @test_throws ArgumentError LNCBounds(args...)
    end
    @test_throws ArgumentError add_lnc!(m,x^2,y,re,imagpart,LNCBounds((1,2),(1,2),(0,.1)))
    @test_throws ArgumentError VoltagePhasor("b","n";return_terminal="n")
end

@testset "Operational P/Q boxes derive valid port RLT domains" begin
    derived,reason=FormulationLab._port_rlt_bounds(
        (200.0,250.0),3_000.0,4_000.0,1_000.0,2_000.0;
        imax=30.0,smax=5_000.0)
    @test isempty(reason)
    @test derived.current_magnitude[1] ≈ hypot(3_000.0,1_000.0)/250.0
    @test derived.current_magnitude[2] ≈ hypot(4_000.0,2_000.0)/200.0
    @test derived.bounds.angle[1] ≈ atan(1_000.0,4_000.0) atol=2e-12
    @test derived.bounds.angle[2] ≈ atan(2_000.0,3_000.0) atol=2e-12
    @test FormulationLab._port_rlt_bounds(
        (200.0,250.0),0.0,4_000.0,-1_000.0,2_000.0)[1] === nothing
    @test FormulationLab._port_rlt_bounds(
        (0.0,250.0),3_000.0,4_000.0,1_000.0,2_000.0)[1] === nothing
end

@testset "LNC excludes a feasible SOC point without changing cone types" begin
    optimizer=isdefined(@__MODULE__,:SDP_TEST_OPTIMIZER) ? SDP_TEST_OPTIMIZER : Clarabel.Optimizer
    m=Model(optimizer);set_silent(m)
    @variable(m,c>=0);@constraint(m,[1.0,c,0.0] in SecondOrderCone())
    @objective(m,Min,c);optimize!(m)
    @test termination_status(m)==JuMP.MOI.OPTIMAL
    @test objective_value(m) ≈ 0 atol=1e-6
    vars=num_variables(m);cones=num_constraints(m;count_variable_in_set_constraints=true)
    add_lnc!(m,1.0,1.0,c,0.0,LNCBounds((0.9,1.1),(0.9,1.1),(-0.1,0.1));include_domain=false)
    @test num_variables(m)==vars
    @test num_constraints(m;count_variable_in_set_constraints=true)==cones+2
    optimize!(m)
    @test termination_status(m)==JuMP.MOI.OPTIMAL
    @test objective_value(m) ≈ 0.981cos(0.1) atol=1e-6
end

@testset "SDP explicit voltage-map LNCs and provenance" begin
    net=_sdp_tx_case("delta_wye")
    u=VoltagePhasor("t","a";return_terminal="n");v=VoltagePhasor("t","b";return_terminal="n")
    bounds=LNCBounds((110,120),(110,120),(2pi/3-.1,2pi/3+.1))
    spec=VoltageLNC("phase-pair",u,v,bounds;provenance="explicit interphase operating sector")
    options=SDPOptions(objective=:source_import,voltage_lncs=[spec])
    r=_sdp_test_solve(net;options,solver_options=(verbose=false,))
    @test r.solve.optimal
    @test only(solve_diagnostics(r).lnc_diagnostics).origin==:operating_limit
    @test only(r.lnc_diagnostics).status==:applied
    build=build_sdp_opf(net,nothing;options)
    @test_throws ArgumentError add_voltage_lnc!(build,spec)
    @test_throws ArgumentError phasor_products(build,VoltagePhasor("missing","a"),v)
    coil=VoltagePhasor(Dict(("f","a")=>1,("f","c")=>-1))
    winding=VoltageLNC("delta-wye",coil,u,LNCBounds((390,410),(110,120),(-.1,.1));provenance="referred winding operating domain")
    @test _sdp_test_solve(net;options=SDPOptions(voltage_lncs=[winding]),solver_options=(verbose=false,)).solve.optimal
    # Reversing a winding changes the center by π; magnitude bounds are unchanged.
    reversed=VoltagePhasor(Dict(("t","a")=>-1,("t","n")=>1))
    spec2=VoltageLNC("reversed",reversed,v,LNCBounds((110,120),(110,120),(2pi/3+pi-.1,2pi/3+pi+.1));provenance="reversed coil")
    @test _sdp_test_solve(net;options=SDPOptions(voltage_lncs=[spec2]),solver_options=(verbose=false,)).solve.optimal
    wrong=VoltageLNC("wrong",u,v,LNCBounds((110,120),(110,120),(-.1,.1));provenance="incompatible operating limit")
    r=_sdp_test_solve(net;options=SDPOptions(voltage_lncs=[wrong]),solver_options=(verbose=false,))
    @test !r.solve.optimal
    @test length(r.lnc_diagnostics)==1
end

@testset "Automatic line LNCs use derived bounds and report missing data" begin
    net=_l3f_case();net["line"]["line"]["i_max"]=[100.0]
    for sb in (1e4,1e5)
        r=_sdp_test_solve(net;options=SDPOptions(lnc=:lines,objective=:source_import,s_base=sb),solver_options=(verbose=false,))
        @test r.solve.optimal
        @test count(d->d.status==:applied,r.lnc_diagnostics)==1
        @test all(d->d.origin==:derived,r.lnc_diagnostics)
        base=_tx_solve(net;sb)
        @test r.objective ≈ base.objective atol=0.03
    end
    build=build_sdp_opf(net,nothing;options=SDPOptions(lnc=:lines))
    b=only(build.lnc_diagnostics).bounds
    @test b.angle[1]<0<b.angle[2]<pi/2
    # Enabling a pi shunt must increase the conservative series-current bound.
    net["linecode"]["lc"]["B_from_1_1"]=0.01
    net["linecode"]["lc"]["B_to_1_1"]=0.01
    sh=build_sdp_opf(net,nothing;options=SDPOptions(lnc=:lines))
    @test only(sh.lnc_diagnostics).bounds.angle[2] > b.angle[2]
    delete!(net["line"]["line"],"i_max")
    missing=build_sdp_opf(net,nothing;options=SDPOptions(lnc=:lines))
    @test only(missing.lnc_diagnostics).status==:skipped
    @test occursin("current ratings",only(missing.lnc_diagnostics).reason)
    net["linecode"]["lc"]["s_max"]=[20_000.0]
    inferred=build_sdp_opf(net,nothing;options=SDPOptions(lnc=:lines))
    @test only(inferred.lnc_diagnostics).status==:applied
    @test only(inferred.lnc_diagnostics).bounds.angle[2] > 0
    @test isempty(build_sdp_opf(net,nothing).lnc_diagnostics)
    @test_throws ArgumentError build_sdp_opf(net,nothing;options=SDPOptions(lnc=:unknown))
end

@testset "IVR SDP operational-box RLT cuts are optional and diagnosed" begin
    net=_l3f_case(generator=true)
    generator=net["generator"]["pv"]
    generator["p_min"]=[12_000.0];generator["p_max"]=[15_000.0]
    generator["q_min"]=[1_000.0];generator["q_max"]=[2_000.0]
    generator["i_max"]=[100.0]
    with_cuts=build_sdp_opf(net,nothing;options=SDPOptions(port_rlt=true))
    without_cuts=build_sdp_opf(net,nothing;options=SDPOptions(port_rlt=false))
    applied=filter(d->d.status==:applied,
        with_cuts.numerical_diagnostics[:port_rlt_diagnostics])
    @test any(d->d.id=="generator/pv/1",applied)
    @test isempty(without_cuts.numerical_diagnostics[:port_rlt_diagnostics])
    @test num_constraints(with_cuts.model;count_variable_in_set_constraints=true) >
          num_constraints(without_cuts.model;count_variable_in_set_constraints=true)
end

@testset "Line LNC voltage-drop bound retains neutral and mutual coupling" begin
    net=_l3f_case(;explicit_neutral=true)
    net["line"]["line"]["i_max"]=[100.0,200.0]
    bus=net["bus"]["load"];bus["perfectly_grounded_terminals"]=String[]
    bus["vpn_min"]=[180.0];bus["vpn_max"]=[250.0];bus["vn_max"]=10.0
    build=build_sdp_opf(net,nothing;options=SDPOptions(lnc=:lines))
    record=only(build.lnc_diagnostics)
    @test record.status==:applied
    epsilon=abs((.2+.1im)-(.02+.01im))*100+abs((.02+.01im)-(.1+.05im))*200
    @test record.bounds.angle[2] <= 2asin(epsilon/(2sqrt(230*180)))*(1+1e-10)
    # Electrical propagation can now derive phase-neutral bounds from phase-ground bounds.
    delete!(bus,"vpn_min");delete!(bus,"vpn_max")
    @test only(build_sdp_opf(net,nothing;options=SDPOptions(lnc=:lines)).lnc_diagnostics).status==:applied
    @test only(build_sdp_opf(net,nothing;options=SDPOptions(lnc=:lines,bound_sweeps=0)).lnc_diagnostics).status==:skipped
end
