using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
include("lindist3flow_fixtures.jl")
if !isdefined(@__MODULE__,:linivr_case)
    include("../examples/linivr_cases.jl")
end

function _ivrn_two_wire()
    net=_l3f_case(explicit_neutral=true)
    b=net["bus"]["load"];b["perfectly_grounded_terminals"]=String[]
    delete!(b,"v_min");delete!(b,"v_max")
    b["vpn_min"]=[180.];b["vpn_max"]=[250.];b["vn_max"]=[20.]
    net
end
_ivrn_solve(net;kwargs...)=solve_opf(net,IVRNLP(;kwargs...);optimizer=Ipopt.Optimizer,
    solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10))
_ivrn_audit(net,r)=physical_residuals(net,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate);delta_dispatch=:coil)

@testset "Exact IVR manufactured two-wire state" begin
    Z=[.2+.1im .02+.01im;.02+.01im .1+.05im]
    current=20-3im;currents=[current,-current]
    expected=[230.,0.]-Z*currents
    demand=(expected[1]-expected[2])*conj(current)
    for sb in (1e3,1e5)
        net=_ivrn_two_wire();net["load"]["load"]["p_nom"]=[real(demand)]
        net["load"]["load"]["q_nom"]=[imag(demand)]
        original=deepcopy(net)
        # Evaluate the independently manufactured state without solving or
        # least-squares repair. The full-space encoder has direct coordinates.
        build=build_opf(net,IVRNLP(s_base=sb,objective=:source_import))
        e=build.electrical;state=fill(ComplexF64(NaN),e.coordinate_count[])
        for (key,k) in e.voltage
            k==0 && continue
            state[k]=(key[1]=="source" ? 230. : expected[key[2]=="a" ? 1 : 2])/e.vb
        end
        for (row,value) in zip(only(e.lnc_lines).current,currents)
            state[only(keys(row))]=value/e.ib
        end
        for (f,_,_,rows,_) in e.devices
            f in (:load,:voltage_source) || continue
            for row in rows
                isempty(row) || (state[only(keys(row))]=current/e.ib)
            end
        end
        @test all(isfinite,state)
        supplied=Dict{VariableRef,Float64}()
        for k in eachindex(state)
            supplied[only(keys(real(build.state[k]).terms))]=real(state[k])
            supplied[only(keys(imag(build.state[k]).terms))]=imag(state[k])
        end
        @test isempty(primal_feasibility_report(build.model,supplied;atol=1e-10))
        @test value(x->supplied[x],objective_function(build.model))*sb ≈ 230real(current)
        r=_ivrn_solve(net;s_base=sb,objective=:source_import)
        @test r.solve.optimal
        @test r.voltage_candidate[("load","a")] ≈ expected[1] atol=1e-6
        @test r.voltage_candidate[("load","n")] ≈ expected[2] atol=1e-6
        @test r.current_candidate[(:line_from,"line")] ≈ currents atol=1e-6
        @test r.powers[(:load,"load")] ≈ [demand] atol=1e-5
        @test r.objective ≈ 230real(current) atol=1e-5
        @test _ivrn_audit(net,r).passed
        @test net==original
        @test !solve_diagnostics(r).bound_certified
    end
    build=build_opf(_ivrn_two_wire(),IVRNLP())
    @test build isa IVRNLPBuild
    @test formulation_kind(IVRNLP())==:exact
    @test build.numerical_diagnostics[:specialization]==:off
    @test build.numerical_diagnostics[:source_mode]==:affine
end

@testset "Exact IVR coupled four-wire and three-wire delta" begin
    for delta in (false,true),ground in (Inf,2.)
        net=linivr_case(segments=2,loading=.4;delta,ground)
        net["linecode"]["wire"]["B_from_1_1"]=1e-5
        net["linecode"]["wire"]["B_to_2_2"]=2e-5
        net["line"]["parallel"]=deepcopy(net["line"]["l1"])
        r=_ivrn_solve(net)
        @test r.solve.optimal
        @test _ivrn_audit(net,r).passed
        @test r.powers[(:load,"d2")] ≈ complex.([1600.,600.,200.],[400.,150.,50.]) atol=1e-5
    end
    # Manufacture an unbalanced three-wire delta state independently.
    tm=["a","b","c"];v0=230cis.([0.,-2pi/3,2pi/3])
    Z=[.2+.1im .02+.01im .03+.01im;.02+.01im .25+.12im .01+.02im;.03+.01im .01+.02im .3+.14im]
    D=[1. -1. 0.;0. 1. -1.;-1. 0. 1.]
    legs=ComplexF64[8-2im,-4-6im,-3+5im]
    terminal=transpose(D)*legs;v=v0-Z*terminal;s=(D*v).*conj.(legs)
    code=Dict{String,Any}()
    for a in 1:3,b in a:3
        code["R_series_$(a)_$(b)"]=real(Z[a,b]);code["X_series_$(a)_$(b)"]=imag(Z[a,b])
    end
    net=Dict{String,Any}("bus"=>Dict("s"=>Dict("terminal_names"=>tm),"t"=>Dict("terminal_names"=>tm,"vpp_min"=>fill(300.,3),"vpp_max"=>fill(440.,3))),
        "linecode"=>Dict("z"=>code),"line"=>Dict("l"=>Dict("bus_from"=>"s","bus_to"=>"t","terminal_map_from"=>tm,"terminal_map_to"=>tm,"linecode"=>"z","i_max"=>fill(100.,3))),
        "voltage_source"=>Dict("s"=>Dict("bus"=>"s","terminal_map"=>tm,"v_magnitude"=>abs.(v0),"v_angle"=>angle.(v0))),
        "load"=>Dict("d"=>Dict("bus"=>"t","terminal_map"=>tm,"configuration"=>"DELTA","p_nom"=>real.(s),"q_nom"=>imag.(s))))
    r=_ivrn_solve(net)
    @test r.solve.optimal
    @test [r.voltage_candidate[("t",t)] for t in tm] ≈ v atol=1e-6
    @test r.current_candidate[(:load,"d")] ≈ legs atol=1e-6
    @test _ivrn_audit(net,r).passed
    # Exact impedance load law on the two-wire circuit.
    net=_ivrn_two_wire();d=net["load"]["load"];d["model"]="constant_impedance";d["v_nom"]=[230.]
    r=_ivrn_solve(net);y=conj(10_000+2000im)/230^2
    @test r.solve.optimal
    @test r.voltage_candidate[("load","a")]-r.voltage_candidate[("load","n")] ≈ 230/(1+(.26+.13im)*y) atol=1e-6
    @test _ivrn_audit(net,r).passed
end

@testset "Exact IVR limits and applicability" begin
    for bound in (:neutral_voltage,:neutral_current,:line_power,:lower_voltage)
        net=_ivrn_two_wire()
        bound==:neutral_voltage && (net["bus"]["load"]["vn_max"]=[.1])
        bound==:neutral_current && (net["line"]["line"]["i_max"]=[100.,1.])
        bound==:line_power && (net["line"]["line"]["s_max"]=[100.])
        bound==:lower_voltage && (net["bus"]["load"]["vpn_min"]=[229.])
        @test !_ivrn_solve(net).solve.optimal
    end
    net=_ivrn_two_wire();net["line"]["line"]["s_max"]=[20_000.]
    net["voltage_source"]["source"]["s_max"]=[20_000.]
    r=_ivrn_solve(net)
    @test r.solve.optimal
    @test _ivrn_audit(net,r).passed
    net=_l3f_case(explicit_neutral=true)
    r=_ivrn_solve(net)
    @test r.solve.optimal && _ivrn_audit(net,r).passed
    for family in ("transformer","ibr","switch","control_profile")
        net=_ivrn_two_wire();net[family]=Dict("unsupported"=>Dict())
        @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
    end
    for law in ("zip","constant_current","exponential")
        net=_ivrn_two_wire();net["load"]["load"]["model"]=law
        @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
    end
    net=_ivrn_two_wire();net["voltage_source"]["source"]["i_max"]=[100.,100.]
    @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
    net=_ivrn_two_wire();net["voltage_source"]["other"]=deepcopy(net["voltage_source"]["source"])
    net["voltage_source"]["other"]["v_magnitude"][1]=231.
    @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
    net=_ivrn_two_wire();net["voltage_source"]["source"]["v_magnitude"][2]=1.
    @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
    @test_throws ArgumentError build_opf(_ivrn_two_wire(),IVRNLP(s_base=0))
end

@testset "Exact IVR dispatch with binding neutral limits" begin
    for which in (:current,:voltage)
        net=_ivrn_two_wire()
        net["voltage_source"]["source"]["cost"]=[0.]
        net["generator"]=Dict("g"=>Dict("bus"=>"load","terminal_map"=>["a","n"],
            "configuration"=>"SINGLE_PHASE","p_min"=>[0.],"p_max"=>[20_000.],
            "q_min"=>[2000.],"q_max"=>[2000.],"cost"=>[-1.],"s_max"=>[25_000.],"i_max"=>[150.]))
        if which==:current
            net["line"]["line"]["i_max"]=[100.,1.]
        else
            net["bus"]["load"]["vn_max"]=[.1]
        end
        r=_ivrn_solve(net)
        @test r.solve.optimal
        @test _ivrn_audit(net,r).passed
        @test real(only(r.powers[(:generator,"g")]))>10_000.
        if which==:current
            @test abs(r.current_candidate[(:line_from,"line")][2]) ≈ 1. atol=1e-5
        else
            @test abs(r.voltage_candidate[("load","n")]) ≈ .1 atol=1e-6
        end
    end
end

@testset "Exact IVR load updates preserve one built instance" begin
    net=_ivrn_two_wire();original=deepcopy(net)
    build=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
    model=build.model;refs=copy(build.load_constraints);variables=all_variables(model)
    # Zero demand and reverse flow cannot alter structural coordinates.
    for factor in (1.,.5,0.,-.25,1.2)
        p=[factor*10_000.];q=[factor*2000.]
        @test update_ivr_loads!(build,Dict("load"=>(;p,q)))===build
        reused=solve_ivr_nlp_opf(build;solver_options=(print_level=0,tol=1e-10))
        fresh=_ivrn_solve(build.network;objective=:source_import)
        @test reused.solve.optimal && fresh.solve.optimal
        @test reused.objective ≈ fresh.objective atol=1e-5
        @test _ivrn_audit(build.network,reused).passed
        @test build.model===model && all_variables(model)==variables
        @test build.load_constraints==refs
        @test build.numerical_diagnostics[:assembly_count]==1
    end
    before=deepcopy(build.network);rhs=normalized_rhs(only(refs["load"].p))
    @test_throws ArgumentError update_ivr_loads!(build,Dict("load"=>(p=[3.],q=[NaN])))
    @test_throws ArgumentError update_ivr_loads!(build,Dict("load"=>(p=[3.],q=[1.]),"missing"=>(p=[1.],q=[2.])))
    @test build.network==before
    @test normalized_rhs(only(refs["load"].p))==rhs
    @test build.numerical_diagnostics[:update_count]==5
    @test net==original
    r=solve_ivr_nlp_opf(build;solver_options=(print_level=0,tol=1e-10))
    @test r.solve.optimal && _ivrn_audit(build.network,r).passed
end
