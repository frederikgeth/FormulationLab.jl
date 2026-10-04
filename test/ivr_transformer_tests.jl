using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
isdefined(@__MODULE__,:_sdp_tx_case) || include("sdp_transformer_fixtures.jl")
isdefined(@__MODULE__,:_audit_transformer_state) || include("ac_validation_fixtures.jl")

@testset "Exact IVR fixed winding supplied states and solves" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta"),
        reverse in (false,true), sb in (1e3,1e5)
        net,point=_audit_transformer_state(kind;tap=1.03,rotation=.21,reverse)
        # The balanced winding return can be roundoff-sized (~1e-16 A).
        # Give that channel a finite microamp rating, rather than turn
        # floating-point cancellation into an artificial relative tolerance.
        tx=net["transformer"][kind]["tx"]
        for side in ("from","to");tx["i_max_$side"]=max.(tx["i_max_$side"],1e-6);end
        original=deepcopy(net)
        build=build_opf(net,IVRNLP(s_base=sb,objective=:source_import,
            specialization=:conductor_difference);optimizer=Ipopt.Optimizer)
        @test build.numerical_diagnostics[:specialization]==:off
        @test build.numerical_diagnostics[:specialization_report].code==:transformer_boundary
        @test build.numerical_diagnostics[:initialization]==:linear_circuit
        @test ivr_nlp_point_report(build,point).passed
        @test physical_residuals(net,point;delta_dispatch=:coil).passed
        result=solve_ivr_nlp_opf(build;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10))
        @test result.solve.optimal
        result.solve.optimal || continue
        actual=ACPoint(voltage=result.voltage_candidate,currents=result.current_candidate)
        @test physical_residuals(net,actual;delta_dispatch=:coil).passed
        @test ivr_nlp_point_report(build,actual).passed
        for (key,v) in point.voltage
            @test actual.voltage[key] ≈ v atol=2e-5
        end
        for side in (:transformer_coil_from,:transformer_coil_to)
            key=(side,"$kind/tx")
            @test actual.currents[key] ≈ point.currents[key] atol=2e-5
        end
        # Ratings and coil/terminal bindings must reject perturbed supplied
        # points; no projection may silently repair transformer currents.
        changed=deepcopy(point.currents)
        changed[(:transformer_coil_to,"$kind/tx")][1]+=1.
        @test !ivr_nlp_point_report(build,ACPoint(voltage=point.voltage,currents=changed)).passed
        tight=deepcopy(net);tight["transformer"][kind]["tx"]["i_max_to"] .*= .5
        @test !ivr_nlp_point_report(build_opf(tight,IVRNLP()),point).passed
        @test net==original
    end
end

@testset "Exact IVR ideal winding ratios and reverse supply" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta")
        tap=.97;net=_sdp_tx_case(kind;tap)
        if kind=="single_phase"
            expected=Dict("p"=>115/tap,"n"=>0im);connections=[["p","n"]]
        elseif kind=="center_tap"
            expected=Dict("x1"=>120/tap,"x2"=>-120/tap,"n"=>0im)
            connections=[["x1","n"],["x2","n"]]
        elseif kind=="delta_wye"
            vf=230cis.([0.,-2pi/3,2pi/3])
            expected=Dict(t=>(vf[k]-vf[mod1(k-1,3)])/(2sqrt(3)*tap) for (k,t) in enumerate(["a","b","c"]))
            expected["n"]=0im;connections=[[t,"n"] for t in ["a","b","c"]]
        else
            u=sqrt(3)/(2tap)*230cis.([0.,-2pi/3,2pi/3])
            expected=Dict("a"=>-u[3],"b"=>u[2],"c"=>0im)
            connections=[["a","b"],["b","c"],["c","a"]]
        end
        for (k,tm) in enumerate(connections);_sdp_zload!(net,"l$k",tm,.01k-.002im);end
        build=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer)
        r=solve_ivr_nlp_opf(build;solver_options=(print_level=0,tol=1e-10))
        @test r.solve.optimal
        r.solve.optimal || continue
        for (t,v) in expected;@test r.voltage_candidate[("t",t)] ≈ v atol=1e-6;end
        point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        @test physical_residuals(net,point;delta_dispatch=:coil).passed
        @test ivr_nlp_point_report(build,point).passed
    end
    net=_sdp_tx_case("single_phase")
    net["voltage_source"]["s"]["bus"]="t"
    net["voltage_source"]["s"]["v_magnitude"]=[115.,0.]
    _sdp_zload!(net,"l",["p","n"],.01-.002im)
    net["load"]["l"]["bus"]="f"
    r=solve_opf(net,IVRNLP();optimizer=Ipopt.Optimizer,solver_options=(print_level=0,tol=1e-10))
    @test r.solve.optimal
    @test r.voltage_candidate[("f","p")] ≈ 230 atol=1e-6
    @test physical_residuals(net,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate);delta_dispatch=:coil).passed
    # All affine source phasors must enter the starting circuit, not just one
    # chosen anchor. This incompatible ideal ratio must fail before optimizing.
    net["voltage_source"]["other"]=Dict("bus"=>"f","terminal_map"=>["p","n"],"v_magnitude"=>[231.,0.],"v_angle"=>[0.,0.])
    @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
end

@testset "Exact IVR winding grounding and excitation" begin
    for ground in (0.,2.), excitation in (false,true)
        net=_sdp_tx_case("single_phase")
        empty!(net["bus"]["t"]["perfectly_grounded_terminals"])
        tx=net["transformer"]["single_phase"]["tx"]
        tx["r_neutral_to"]=ground
        tx["r_series_to"]=.2;tx["x_series_to"]=.1
        excitation && (tx["no_load_shunt"]=Dict("winding"=>2,"g"=>.002,"b"=>-.001))
        # Earth-return load makes the winding grounding impedance observable.
        _sdp_zload!(net,"l",["p"],.02-.005im)
        build=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer)
        r=solve_ivr_nlp_opf(build;solver_options=(print_level=0,tol=1e-11,constr_viol_tol=1e-11))
        @test r.solve.optimal
        point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        @test physical_residuals(net,point;delta_dispatch=:coil).passed
        @test ivr_nlp_point_report(build,point).passed
        y=.02-.005im;ye=excitation ? .002-.001im : 0im;z=.2+.1im
        # Coil voltage = phase voltage + grounding drop; excitation is across
        # the winding, so it contributes leakage loss but no earth current.
        vp=115/(1+ground*y+z*(y+ye*(1+ground*y)))
        @test r.voltage_candidate[("t","p")] ≈ vp atol=1e-6
        @test r.voltage_candidate[("t","n")] ≈ -ground*y*vp atol=1e-6
    end
    floating=_sdp_tx_case("wye_delta")
    empty!(floating["bus"]["t"]["perfectly_grounded_terminals"])
    @test_throws IVRNLPInapplicableError build_opf(floating,IVRNLP())
    net=_sdp_tx_case("single_phase");tx=net["transformer"]["single_phase"]["tx"]
    delete!(tx,"tap");tx["tap_min"]=.9;tx["tap_max"]=1.1
    @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
end

@testset "Exact IVR multiwinding and demand reuse" begin
    net,point=_audit_nwinding_state()
    build=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer)
    @test ivr_nlp_point_report(build,point).passed
    r=solve_ivr_nlp_opf(build;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10))
    @test r.solve.optimal
    actual=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
    @test physical_residuals(net,actual;delta_dispatch=:coil).passed
    @test ivr_nlp_point_report(build,actual).passed
    for (key,v) in point.voltage
        @test actual.voltage[key] ≈ v atol=2e-5
    end
    net,_=_audit_transformer_state("delta_wye")
    # Leave headroom for the demand sweep; binding limits are tested above.
    tx=net["transformer"]["delta_wye"]["tx"]
    tx["i_max_from"] .*= 2;tx["i_max_to"] .*= 2
    build=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
    variables=all_variables(build.model)
    for factor in (1.,0.,-.5,.7)
        update_ivr_loads!(build,Dict(id=>(p=factor*d["p_nom"],q=factor*d["q_nom"]) for (id,d) in net["load"]))
        r=solve_ivr_nlp_opf(build;solver_options=(print_level=0,tol=1e-10))
        fresh=build_opf(build.network,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
        f=solve_ivr_nlp_opf(fresh;solver_options=(print_level=0,tol=1e-10))
        @test r.solve.optimal && f.solve.optimal
        @test r.objective ≈ f.objective atol=1e-5
        actual=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        @test physical_residuals(build.network,actual;delta_dispatch=:coil).passed
        @test ivr_nlp_point_report(fresh,actual).passed
        @test all_variables(build.model)==variables
        @test build.numerical_diagnostics[:assembly_count]==1
    end
end
