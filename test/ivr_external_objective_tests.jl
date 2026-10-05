module IVRExternalObjectiveTests
using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/benchmark_ivr_external_objectives.jl")
const E=IVRExternalObjectiveStudy
const BASES=Dict("hv"=>1e5,"mv"=>1e4,"lv1_b0"=>1e3,"lv2_b0"=>1e3)
function fixture()
    n=E.S.case(:quadratic_cost;segments=2)
    n["generator"]["wye"]=Dict("bus"=>"lv1_b0","terminal_map"=>["a","b","c","n"],"configuration"=>"WYE",
        "p_min"=>[100.,0.,0.],"p_max"=>fill(1200.,3),"q_min"=>fill(-500.,3),"q_max"=>fill(500.,3),"cost"=>fill(-99.,3))
    n
end

@testset "External objective declarations and provenance" begin
    net=fixture();before=deepcopy(net)
    src,gen=E.channels(net)
    @test length(src)==4 && length(gen)==9
    @test count(c->c[2]=="wye",gen)==3
    ts=E.terms(net,:exchange_tracking;exchange_target_W=4500.)
    @test only(t.target for t in ts if t.channels==[(:generator,"wye",1)] && t.quantity==:p)==650.
    prices=deepcopy(net)
    for d in values(prices["generator"]);d["cost"].*=100;end
    @test JSON3.write(E.terms(prices,:quadratic_cost))==JSON3.write(E.terms(net,:quadratic_cost))
    for w in (:quadratic_cost,:exchange_tracking)
        ps=E.profiles(net,w;regional_bases=BASES,exchange_target_W=4500.)
        @test length(ps)==6 && allunique(p.name for p in ps)
        @test all(p->p.options.objective_scale==1. && p.options.objective==:power,ps)
        @test all(p->JSON3.write(p.options.power_terms)==JSON3.write(ps[1].options.power_terms),ps)
        empty!(ps[1].options.power_terms)
        @test !isempty(ps[2].options.power_terms)
    end
    @test net==before
    @test_throws ArgumentError E.terms(net,:exchange_tracking)
    @test_throws ArgumentError E.terms(net,:exchange_tracking;exchange_target_W=Inf)
    @test_throws ArgumentError E.terms(net,:unknown)
    for seeds in (Dict{String,Float64}(),Dict("missing"=>1e3),Dict("hv"=>0.))
        @test_throws ArgumentError E.profiles(net,:quadratic_cost;regional_bases=seeds)
    end
    @test_throws ArgumentError E.profiles(net,:quadratic_cost;regional_bases=BASES,nlp_scaling_method="unknown")
    for mode in (:empty,:fixed,:missing,:infinite,:inverted,:ibr)
        bad=deepcopy(net)
        mode==:empty && empty!(bad["generator"])
        mode==:fixed && foreach(d->d["p_max"]=copy(d["p_min"]),values(bad["generator"]))
        mode==:missing && delete!(bad["generator"]["wye"],"q_min")
        mode==:infinite && (bad["generator"]["wye"]["p_max"][1]=Inf)
        mode==:inverted && (bad["generator"]["wye"]["p_min"][1]=2000.)
        mode==:ibr && (bad["ibr"]=Dict("unpriced"=>Dict()))
        @test_throws ArgumentError E.terms(bad,:quadratic_cost)
    end
    mktempdir() do dir
        file=joinpath(dir,"input.json");open(io->JSON3.write(io,net),file,"w")
        @test_throws ArgumentError E.benchmark(file,file;regional_bases=BASES)
        @test_throws ArgumentError E.benchmark(file,joinpath(dir,"out");regional_bases=BASES,repetitions=1)
        @test JSON3.read(read(file,String),Dict{String,Any})==net
    end
end

@testset "External shortlist physical objectives and exports" begin
    net=fixture();start=E.S.U.G.H.S.L.start_point(net)
    for workload in (:quadratic_cost,:exchange_tracking)
        profiles=E.profiles(net,workload;regional_bases=BASES,exchange_target_W=4500.)
        reference=build_opf(net,IVRNLP(objective=:power,power_terms=first(profiles).options.power_terms))
        anchor=nothing;objectives=Float64[]
        for profile in profiles
            b=build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer)
            enc=ivr_nlp_point_report(b,start)
            @test length(enc.variable_values)==num_variables(b.model)
            @test max(enc.max_binding_residual_pu,enc.max_reconstruction_residual_pu)<=1e-10
            for (v,x) in enc.variable_values;set_start_value(v,x);end
            r=solve_ivr_nlp_opf(b;solver_options=merge(E.P.STRICT,profile.solver_options))
            @test r.solve.optimal && physical_residuals(net,r).passed
            p=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(reference,p).passed
            @test anchor===nothing || ivr_nlp_point_report(b,anchor).passed
            anchor===nothing && (anchor=p)
            source=sum(sum(s) for ((f,_),s) in r.powers if f==:voltage_source)
            generation=[(id,k,s) for ((f,id),ss) in r.powers if f==:generator for (k,s) in enumerate(ss)]
            expected=if workload==:quadratic_cost
                .25real(source)/1000+sum(.10real(s)/1000+.02real(s)^2/1e6+.002imag(s)^2/1e6 for (_,_,s) in generation)
            else
                ((real(source)-4500.)^2+imag(source)^2)/1e6+sum(((real(s)-(net["generator"][id]["p_min"][k]+net["generator"][id]["p_max"][k])/2)^2+imag(s)^2)/1e8 for (id,k,s) in generation)
            end
            @test r.objective≈expected atol=1e-7
            push!(objectives,r.objective)
            d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
            @test isequal(read_result(io),d)
            @test d["_formulationlab"]["objective_units"]=="user_defined"
            @test length(d["_formulationlab"]["objective_definition"])==length(profile.options.power_terms)
        end
        @test maximum(objectives)-minimum(objectives)<1e-6
    end
end

@testset "External runner input ownership and balanced report" begin
    mktempdir() do dir
        net=fixture();net["voltage_source"]["grid"]["_pmd"]=Dict("legacy_note"=>"retained provenance")
        path=joinpath(dir,"input.json");open(io->JSON3.write(io,net),path,"w")
        original=read(path)
        output=joinpath(dir,"study.json")
        report=E.benchmark(path,output;regional_bases=BASES)
        @test read(path)==original
        @test report["source_unchanged"] && report["network_unchanged"] && report["position_balanced"]
        @test report["ranking"]["objective_comparable"] && length(report["ranking"]["eligible"])==6
        @test report["feeder_input"]["electrical_changes"]==[]
        @test !report["feeder_input"]["legacy_prices_used"]
        @test "/voltage_source/grid/_pmd" in report["feeder_input"]["detached_provenance_paths"]
        @test isfile(output*".manifest.json") && isfile(output*".input.json")
        @test report["global_optimum_certified"]===false
    end
end
end
