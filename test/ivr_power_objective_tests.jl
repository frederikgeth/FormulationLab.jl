module IVRPowerObjectiveTests
using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/benchmark_ivr_power_objectives.jl")
const S=IVRPowerObjectiveStudy

# Fixed voltage and zero source P/Q leave two dispatches with affine balances.
# The convex separable quadratic has an independent closed-form optimum.
function dispatch_case()
    Dict{String,Any}("bus"=>Dict("b"=>Dict("terminal_names"=>["a","n"],"perfectly_grounded_terminals"=>["n"])),
        "voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>["a","n"],"v_magnitude"=>[230.,0.],"v_angle"=>[0.,0.],
            "p_min"=>[0.,0.],"p_max"=>[0.,0.],"q_min"=>[0.,0.],"q_max"=>[0.,0.])),
        "load"=>Dict("d"=>Dict("bus"=>"b","terminal_map"=>["a","n"],"configuration"=>"SINGLE_PHASE","model"=>"constant_power","p_nom"=>[3000.],"q_nom"=>[600.])),
        "generator"=>Dict(id=>Dict("bus"=>"b","terminal_map"=>["a","n"],"configuration"=>"SINGLE_PHASE",
            "p_min"=>[0.],"p_max"=>[3000.],"q_min"=>[-2000.],"q_max"=>[2000.],"cost"=>[.1]) for id in ("g1","g2")))
end
const TERMS=[IVRPowerTerm(channels=[(:generator,"g1",1)],linear=.001,quadratic=1e-6),
    IVRPowerTerm(channels=[(:generator,"g2",1)],quadratic=2e-6),
    IVRPowerTerm(channels=[(:generator,"g1",1)],quantity=:q,quadratic=1e-6),
    IVRPowerTerm(channels=[(:generator,"g2",1)],quantity=:q,quadratic=3e-6)]

@testset "Independent P/Q economic dispatch and reusable physical objectives" begin
    for sb in (1e3,1e6),divisor in (1.,100.),lifting in (:off,:powers,:bounded_observations)
        net=dispatch_case();terms=deepcopy(TERMS)
        options=IVRNLPOptions(;objective=:power,power_terms=terms,s_base=sb,objective_scale=divisor,lifting)
        b=build_opf(net,IVRNLP(options);optimizer=Ipopt.Optimizer)
        empty!(terms[1].channels);empty!(terms) # The build owns nested declarations.
        @test length(b.options.power_terms)==4 && length(b.options.power_terms[1].channels)==1
        for (step,pd,qd,maximum_p1) in ((1,3000.,600.,3000.),(2,3000.,600.,1000.),(3,2000.,400.,1000.))
            step==2 && update_ivr_generators!(b,Dict("g1"=>(p_max=[1000.],cost=[99.])))
            step==3 && update_ivr_loads!(b,Dict("d"=>(p=[pd],q=[qd])))
            r=solve_ivr_nlp_opf(b;solver_options=S.P.STRICT)
            @test r.solve.optimal && physical_residuals(b.network,r).passed
            p1=min(maximum_p1,(4e-6pd-.001)/6e-6);p2=pd-p1;q1=.75qd;q2=.25qd
            expected=.001p1+1e-6p1^2+2e-6p2^2+1e-6q1^2+3e-6q2^2
            @test r.powers[(:generator,"g1")][1]≈p1+im*q1 atol=1e-4
            @test r.powers[(:generator,"g2")][1]≈p2+im*q2 atol=1e-4
            @test r.objective≈expected atol=1e-8
            @test objective_value(b.model)*divisor≈expected atol=1e-8
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(b,point).objective≈expected atol=1e-8
            fresh=build_opf(b.network,IVRNLP(b.options))
            @test ivr_nlp_point_report(fresh,point).passed
            @test ivr_nlp_point_report(fresh,point).objective≈expected atol=1e-8
            d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
            @test isequal(read_result(io),d)
            @test d["_formulationlab"]["objective_units"]=="user_defined"
            @test length(d["_formulationlab"]["objective_definition"])==4
        end
    end
end

@testset "Power objectives across unbalanced leakage, reductions and units" begin
    for workload in S.WORKLOADS
        net=S.case(workload;segments=2);start=S.U.G.H.S.L.start_point(net)
        profiles=S.profiles(net,workload);ref=build_opf(net,IVRNLP(objective=first(profiles).options.objective,power_terms=S.terms(net,workload)))
        anchor=nothing;objectives=Float64[]
        for profile in profiles
            b=build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer)
            encoded=ivr_nlp_point_report(b,start)
            @test isempty(encoded.missing_channels) && length(encoded.variable_values)==num_variables(b.model)
            @test max(encoded.max_binding_residual_pu,encoded.max_reconstruction_residual_pu)<1e-10
            for (v,x) in encoded.variable_values;set_start_value(v,x);end
            r=solve_ivr_nlp_opf(b;solver_options=merge(S.P.STRICT,profile.solver_options))
            @test r.solve.optimal && physical_residuals(net,r).passed
            p=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            expected=S.physical_objective(net,workload,r.powers)
            @test r.objective≈expected atol=1e-7
            @test ivr_nlp_point_report(b,p).objective≈expected atol=1e-7
            @test ivr_nlp_point_report(ref,p).passed
            @test ivr_nlp_point_report(ref,p).objective≈expected atol=1e-7
            anchor===nothing ? (anchor=p) : (@test ivr_nlp_point_report(b,anchor).passed)
            push!(objectives,r.objective)
            workload==:dispatch_tracking && (@test abs(r.objective)<1e-8)
            workload==:losses && (@test r.objective>=-1e-7)
            if workload==:losses
                # Different physical accounting: sum passive terminal powers.
                loss=sum(sum(real,s) for ((family,_),s) in r.powers if family in (:line_from,:line_to,:transformer_from,:transformer_to))
                # Finite grounds are stamped into KCL, not e.devices. Their
                # physical dissipation is nevertheless part of network loss.
                loss+=sum(d["G_1_1"]*abs2(r.voltage_candidate[(d["bus"],only(d["terminal_map"]))]) for d in values(net["shunt"]))
                @test r.objective≈loss atol=1e-6
            end
            d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
            @test isequal(read_result(io),d)
            @test d["bus"]["lv1_b2"]["a"]["vr"]≈real(p.voltage[("lv1_b2","a")])
        end
        @test maximum(objectives)-minimum(objectives)<1e-5
    end
end

@testset "Delta generator objectives use native coil powers" begin
    for conductors in (3,4),lifting in (:off,:powers,:bounded_observations)
        net=S.P.ivr_compiler_case(;conductors,segments=2)
        net["generator"]=Dict("delta"=>Dict("bus"=>"b2","terminal_map"=>["a","b","c"],
            "configuration"=>"DELTA","p_min"=>zeros(3),"p_max"=>fill(1000.,3),
            "q_min"=>fill(-300.,3),"q_max"=>fill(300.,3)))
        target=ComplexF64[500+100im,300-50im,200+40im]
        terms=[IVRPowerTerm(channels=[(:generator,"delta",k)];quantity,
            target=quantity==:p ? real(target[k]) : imag(target[k]),quadratic=1e-6) for k in 1:3 for quantity in (:p,:q)]
        b=build_opf(net,IVRNLP(;objective=:power,power_terms=terms,objective_scale=1.,s_base=1e3,
            specialization=:conductor_difference,linear_elimination=:passive_blocks,lifting);optimizer=Ipopt.Optimizer)
        r=solve_ivr_nlp_opf(b;solver_options=S.P.STRICT)
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test abs(r.objective)<1e-8
        @test r.powers[(:generator,"delta")]≈target atol=1e-3
        @test ivr_nlp_point_report(b,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
    end
end

@testset "Weighted native port powers and exact objective lifts" begin
    net=S.case(:quadratic_cost;segments=1)
    base=build_opf(net,IVRNLP(first(S.profiles(net,:quadratic_cost)).options);optimizer=Ipopt.Optimizer)
    r=solve_ivr_nlp_opf(base;solver_options=S.P.STRICT)
    @test r.solve.optimal && physical_residuals(net,r).passed
    point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
    channels=[(f,id,k) for ((f,id),v) in sort!(collect(r.powers);by=first) for k in eachindex(v)]
    weights=[isodd(k) ? .5 : -1. for k in eachindex(channels)]
    terms=[IVRPowerTerm(;channels,weights,quantity,target=quantity==:p ? 13. : 17.,linear=.002,quadratic=1e-6) for quantity in (:p,:q)]
    expected=sum(terms) do t
        x=sum(w*(t.quantity==:p ? real(r.powers[(f,id)][k]) : imag(r.powers[(f,id)][k]))
            for ((f,id,k),w) in zip(t.channels,t.weights))-t.target
        .002x+1e-6x^2
    end
    for sb in (1e3,1e6),lifting in (:off,:powers,:bounded_observations)
        b=build_opf(net,IVRNLP(;objective=:power,power_terms=terms,objective_scale=7.,s_base=sb,lifting,
            transformer_scaling=:nominal,device_elimination=:transformer_currents,
            linear_elimination=:passive_blocks,ground_scaling=:voltage);optimizer=Ipopt.Optimizer)
        report=ivr_nlp_point_report(b,point)
        @test report.passed && isempty(report.missing_channels)
        @test length(report.variable_values)==num_variables(b.model)
        @test report.objective≈expected atol=1e-7
    end
end

@testset "Unaccepted diagnostic exports retain physical objective normalization" begin
    for objective in (:power,:cost,:source_import),sb in (1e3,1e6)
        net=dispatch_case()
        for key in ("p_min","p_max","q_min","q_max");delete!(net["voltage_source"]["s"],key);end
        point=ACPoint(voltage=Dict(("b","a")=>230.0+0im,("b","n")=>0.0+0im),
            currents=Dict((:voltage_source,"s")=>ComplexF64[(1500-400im)/230,0],
                (:load,"d")=>ComplexF64[(3000-600im)/230],
                (:generator,"g1")=>ComplexF64[(1000-100im)/230],
                (:generator,"g2")=>ComplexF64[(500-100im)/230]))
        b=build_opf(net,IVRNLP(;objective,power_terms=objective==:power ? TERMS : IVRPowerTerm[],
            s_base=sb,objective_scale=7.);optimizer=Ipopt.Optimizer)
        encoded=ivr_nlp_point_report(b,point);@test encoded.passed
        for (v,x) in encoded.variable_values;set_start_value(v,x);end
        r=solve_ivr_nlp_opf(b;solver_options=merge(S.P.STRICT,(max_iter=0,)))
        @test !r.solve.optimal && isnan(r.objective)
        d=result_dict(b,r)
        @test isfinite(d["objective"]) && abs(d["objective"])>1e-6
        @test d["objective"]≈7objective_value(b.model) atol=1e-8
        @test d["_formulationlab"]["objective_units"]==(objective==:power ? "user_defined" : objective==:cost ? "currency/h" : "W")
        io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
    end
end

@testset "Power term validation and benchmark objective identity" begin
    net=dispatch_case()
    for terms in (IVRPowerTerm[],[IVRPowerTerm(channels=[])],
        [IVRPowerTerm(channels=[(:generator,"missing",1)],linear=1.)],
        [IVRPowerTerm(channels=[(:generator,"g1",0)])],
        [IVRPowerTerm(channels=[(:generator,"g1",2)])],
        [IVRPowerTerm(channels=[(:generator,"g1",1)],weights=[])],
        [IVRPowerTerm(channels=[(:generator,"g1",1)],weights=[Inf])],
        [IVRPowerTerm(channels=[(:generator,"g1",1)],target=NaN)],
        [IVRPowerTerm(channels=[(:generator,"g1",1)],linear=Inf)],
        [IVRPowerTerm(channels=[(:generator,"g1",1)],quadratic=-1.)],
        [IVRPowerTerm(channels=[(:generator,"g1",1)],quantity=:s)])
        @test_throws ArgumentError build_opf(net,IVRNLP(objective=:power,power_terms=terms))
    end
    @test_throws ArgumentError build_opf(net,IVRNLP(power_terms=TERMS))
    # Aggregation is squared after summing, with signed weights and SI offsets.
    term=IVRPowerTerm(channels=[(:generator,"g1",1),(:generator,"g2",1)],weights=[1.,-2.],target=50.,linear=.001,quadratic=1e-6)
    b=build_opf(net,IVRNLP(objective=:power,power_terms=[term]);optimizer=Ipopt.Optimizer)
    r=solve_ivr_nlp_opf(b;solver_options=S.P.STRICT)
    @test r.solve.optimal
    x=real(r.powers[(:generator,"g1")][1]-2r.powers[(:generator,"g2")][1])-50.
    @test x≈-500. atol=1e-4
    @test r.objective≈-.25 atol=1e-8
    mktempdir() do dir
        a=(name="a",options=IVRNLPOptions(objective=:power,power_terms=deepcopy(TERMS)))
        c=(name="b",options=IVRNLPOptions(objective=:power,power_terms=deepcopy(TERMS)))
        report=S.P.benchmark(net,joinpath(dir,"same.json");repetitions=2,candidates=[a,c])
        @test length(report["ranking"]["eligible"])==2 && report["ranking"]["objective_comparable"]
        c.options.power_terms[1].weights[1]=2.
        @test_throws ArgumentError S.P.benchmark(net,joinpath(dir,"different.json");candidates=[a,c])
    end
end
end
