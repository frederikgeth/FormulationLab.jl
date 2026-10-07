module IVRZeroLoadTests
using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/ivr_compiler_cases.jl")
include("../examples/ivr_constraint_inventory.jl")
const I=IVRConstraintInventory
const F=FormulationLab
const SETTINGS=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.)
function fixture(m,law)
    net=ivr_compiler_case(conductors=m,segments=2)
    d=net["load"]["d1"];n=length(d["p_nom"])
    d["p_nom"].=0.;d["q_nom"].=0.
    m==4 && (d["p_nom"][2]=100.;d["q_nom"][2]=20.)
    d["model"]=law
    if law!="constant_power"
        d["v_nom"]=fill(m==3 ? 230sqrt(3) : 230.,n)
        if law=="zip"
            for (pre,values) in (("alpha",(.2,.3,.5)),("beta",(.4,.5,.1))),(s,x) in zip(("z","i","p"),values)
                d[pre*"_"*s]=fill(x,n)
            end
        elseif law=="exponential"
            d["gamma_p"]=fill(.4,n);d["gamma_q"]=fill(-.5,n)
        end
    end
    net
end
shape(x::AbstractDict)=Dict(k=>shape(v) for (k,v) in x)
shape(x::AbstractVector)=shape.(x)
shape(x)=nothing

@testset "Certified zero coil currents preserve laws, bounds, starts and exports" begin
    for m in (2,3,4),law in ("constant_power","constant_current","zip","exponential"),
        lifting in (:off,:powers,:bounded_observations),sb in (1e3,1e5)
        net=fixture(m,law);original=deepcopy(net)
        terms=[IVRPowerTerm(channels=[(:voltage_source,"source",1)],linear=1e-3),
            IVRPowerTerm(channels=[(:load,"d1",1)],quantity=:q,quadratic=1e-6)]
        ref=build_opf(net,IVRNLP(;s_base=sb,objective=:power,power_terms=terms))
        opts=IVRNLPOptions(;s_base=sb,objective=:power,power_terms=terms,lifting,zero_load_elimination=true,
            specialization=:conductor_regions,linear_elimination=:passive_blocks,
            load_power_lifting=true,load_power_row_scaling=:both,load_power_row_base=100.)
        b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
        expected=m==2 ? 1 : m==3 ? 3 : 2
        @test b.numerical_diagnostics[:zero_load_elimination_report].eliminated_complex_coordinates==expected
        @test net==original && b.network==ref.network
        @test I.catalog(b).complete_emitted_coverage
        @test count(q->q.status==:eliminated_zero_power,I.catalog(b).declarations)==2expected
        r=solve_ivr_nlp_opf(b;solver_options=SETTINGS)
        @test r.solve.optimal && physical_residuals(net,r).passed
        p=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        @test ivr_nlp_point_report(ref,p).passed && ivr_nlp_point_report(b,p).passed
        badcurrents=deepcopy(p.currents);badcurrents[(:load,"d1")][1]+=.1
        bad=ACPoint(voltage=p.voltage,currents=badcurrents)
        @test !ivr_nlp_point_report(b,bad).passed && !physical_residuals(net,bad;delta_dispatch=:coil).passed
        @test all(iszero,r.current_candidate[(:load,"d1")][m==4 ? [1,3] : 1:expected])
        trace=I.N.trace(b,p)
        @test all(q->abs(q.reconciliation_error_SI)<1e-6,trace.loads)
        @test all(q->abs(q.physical_residual_SI)<1e-3,trace.loads)
        d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
        @test isequal(read_result(io),d)
        @test d["_formulationlab"]["zero_load_elimination_report"]["eliminated_complex_coordinates"]==expected
        # Identical physical state exported through the full formulation.
        for (v,x) in ivr_nlp_point_report(ref,p).variable_values;set_start_value(v,x);end
        set_optimizer(ref.model,Ipopt.Optimizer)
        rr=solve_ivr_nlp_opf(ref;solver_options=SETTINGS)
        @test rr.solve.optimal && physical_residuals(net,rr).passed
        dd=result_dict(ref,rr)
        @test all(shape(d[k])==shape(dd[k]) for k in F._RESULT_TABLES)
        @test isapprox(r.objective,rr.objective;atol=1e-6,rtol=1e-8)
        @test ivr_nlp_point_report(b,ACPoint(voltage=rr.voltage_candidate,currents=rr.current_candidate)).passed
        # The voltage certificate is an enforced bound, not a removed condition.
        tight=deepcopy(net);key=m==3 ? "vpp_min" : "vpn_min"
        tight["bus"]["b1"][key].=m==3 ? 410. : 245.
        @test !physical_residuals(tight,p;delta_dispatch=:coil).passed
        @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(opts)),p).passed
    end
end

@testset "Zero-voltage counterexample, exact selection and atomic reuse" begin
    net=Dict{String,Any}("bus"=>Dict("b"=>Dict("terminal_names"=>["a","b","n"],"perfectly_grounded_terminals"=>["n"])),
        "voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>["a","b","n"],"v_magnitude"=>[0.,230.,0.],"v_angle"=>zeros(3))),
        "load"=>Dict("d"=>Dict("bus"=>"b","terminal_map"=>["a","n"],"configuration"=>"SINGLE_PHASE","p_nom"=>[0.],"q_nom"=>[0.])))
    p=ACPoint(voltage=Dict(("b","a")=>0im,("b","b")=>230+0im,("b","n")=>0im),
        currents=Dict((:load,"d")=>ComplexF64[1],(:voltage_source,"s")=>ComplexF64[1,0,0]))
    for enabled in (false,true)
        b=build_opf(net,IVRNLP(zero_load_elimination=enabled))
        @test b.numerical_diagnostics[:zero_load_elimination_report].eliminated_complex_coordinates==0
        @test ivr_nlp_point_report(b,p).passed
        @test physical_residuals(net,p;delta_dispatch=:coil).passed
    end
    positive=deepcopy(net);positive["voltage_source"]["s"]["v_magnitude"][1]=230.
    b=build_opf(positive,IVRNLP(zero_load_elimination=true))
    @test only(b.numerical_diagnostics[:zero_load_elimination_report].channels).source==:fixed_source
    n=fixture(4,"constant_power");b=build_opf(n,IVRNLP(zero_load_elimination=true));before=deepcopy(b.network)
    @test_throws ArgumentError update_ivr_loads!(b,Dict("d2"=>(p=zeros(3),q=zeros(3)),"d1"=>(p=[1.,100.,0.],q=[0.,20.,0.])))
    @test b.network==before && b.numerical_diagnostics[:update_count]==0
    update_ivr_loads!(b,Dict("d1"=>(p=[0.,200.,0.],q=[0.,30.,0.])))
    @test b.network["load"]["d1"]["p_nom"]==[0.,200.,0.] && I.catalog(b).complete_emitted_coverage
    for demand in (1e-200,-1e-200)
        n=fixture(2,"constant_power");n["load"]["d1"]["p_nom"][1]=demand
        @test isempty(build_opf(n,IVRNLP(zero_load_elimination=true)).model.ext[:ivr_zero_loads])
    end
    n=fixture(2,"constant_power");delete!(n["bus"]["b1"],"vpn_min")
    @test isempty(build_opf(n,IVRNLP(zero_load_elimination=true)).model.ext[:ivr_zero_loads])
    n=fixture(4,"constant_power");delete!(n["bus"]["b1"],"vpn_min");n["bus"]["b1"]["vpp_min"]=fill(300.,3)
    @test isempty(build_opf(n,IVRNLP(zero_load_elimination=true)).model.ext[:ivr_zero_loads])
    # Missing/changed provenance cannot be reported as covered.
    b=build_opf(fixture(2,"constant_power"),IVRNLP(zero_load_elimination=true))
    empty!(b.model.ext[:ivr_zero_loads])
    @test_throws ArgumentError I.catalog(b)
end
end
