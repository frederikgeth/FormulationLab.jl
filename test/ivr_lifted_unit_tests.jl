module IVRLiftedUnitTests
using Test, FormulationLab, JuMP, Ipopt
include("../examples/benchmark_ivr_power_objectives.jl")
include("../examples/ivr_transformer_stress_cases.jl")
const S=IVRPowerObjectiveStudy
const C=IVRTransformerStressCases
point(r)=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)

@testset "Lifted power units preserve inverse maps, objective and bounds" begin
    for workload in (:quadratic_cost,:exchange_tracking),lb in (1e2,1e4,1e6),lifting in (:powers,:bounded_observations)
        net=S.case(workload;segments=2)
        terms=S.terms(net,workload)
        opts=IVRNLPOptions(;objective=:power,power_terms=terms,objective_scale=1.,
            lifted_power_base=lb,generator_power_bases=Dict(id=>1e3 for id in keys(net["generator"])),
            transformer_scaling=:nominal,current_power_bases=Dict("lv1_b0"=>1e3),
            specialization=:conductor_regions,linear_elimination=:passive_blocks,
            device_elimination=:transformer_currents,lifting,observation_sharing=:exact)
        b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
        start=ivr_nlp_point_report(b,S.U.G.H.S.L.start_point(net))
        @test isempty(start.missing_channels) && length(start.variable_values)==num_variables(b.model)
        for (v,x) in start.variable_values;set_start_value(v,x);end
        r=solve_ivr_nlp_opf(b;solver_options=S.P.STRICT)
        @test r.solve.optimal && physical_residuals(net,r).passed
        report=ivr_nlp_point_report(b,point(r))
        @test report.passed && isapprox(report.objective,r.objective;atol=1e-7)
        reference=build_opf(net,IVRNLP(objective=:power,power_terms=terms,objective_scale=1.))
        @test ivr_nlp_point_report(reference,point(r)).passed
        @test r.objective≈S.physical_objective(net,workload,r.powers) atol=1e-7
        powers=filter(x->x.kind==:power,b.model.ext[:ivr_lifting].records)
        @test !isempty(powers) && all(x->x.scale==lb/b.electrical.sb,powers)
        @test all(x->x.kind==:power || x.scale==1.,b.model.ext[:ivr_lifting].records)
        ref=first(powers);bad=copy(report.variable_values);bad[ref.real]+=1/ref.scale
        @test maximum(values(primal_feasibility_report(b.model,bad;atol=0.)))>.99
        @test b.numerical_diagnostics[:lifted_power_base]==lb
        d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
        @test isequal(read_result(io),d)
    end
end

@testset "Lifted units retain active original limits and reusable updates" begin
    for limit in (:capability,:current,:voltage),lb in (1e2,1e6)
        net=C.case(;limit,segments=3)
        opts=IVRNLPOptions(objective=:source_import,lifting=:bounded_observations,lifted_power_base=lb,
            generator_power_bases=Dict("der"=>1e3),specialization=:conductor_regions,
            linear_elimination=:passive_blocks,transformer_scaling=:nominal,ground_scaling=:voltage)
        b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
        r=solve_ivr_nlp_opf(b;solver_options=S.P.STRICT)
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test r.objective≈C.expected(limit).source_W atol=1e-4
        tight=deepcopy(net)
        limit==:capability && (tight["generator"]["der"]["s_max"][1]-=1.)
        limit==:current && (tight["line"]["l3"]["i_max"][1]-=.1)
        limit==:voltage && (tight["bus"]["b3"]["vpn_max"][1]-=.1)
        @test !physical_residuals(tight,point(r);delta_dispatch=:coil).passed
        @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(opts)),point(r)).passed
        update_ivr_loads!(b,Dict("demand"=>(p=[1000.],q=[0.])))
        update_ivr_generators!(b,Dict("der"=>(p_min=[200.],p_max=[200.],cost=[.5])))
        rr=solve_ivr_nlp_opf(b;solver_options=S.P.STRICT)
        @test rr.solve.optimal && physical_residuals(b.network,rr).passed
        @test ivr_nlp_point_report(build_opf(b.network,IVRNLP(opts)),point(rr)).passed
    end
    for lb in (0.,-1.,NaN,Inf,nextfloat(0.))
        @test_throws ArgumentError build_opf(C.case(segments=1),IVRNLP(lifted_power_base=lb))
    end
    b=build_opf(C.case(segments=1),IVRNLP(lifted_power_base=1e3))
    @test isempty(b.model.ext[:ivr_lifting].records) # No implicit lifting.
end
@testset "Exact generator power reuse preserves native coils and ratings" begin
    for m in (2,3,4),gb in (1e3,1e5),lb in (1e2,1e6),lifting in (:powers,:bounded_observations)
        net=S.P.ivr_compiler_case(conductors=m,segments=2)
        tm=m==2 ? ["a","n"] : ["a","b","c"];n=m==2 ? 1 : 3
        net["generator"]=Dict("g"=>Dict("bus"=>"b2","terminal_map"=>tm,
            "configuration"=>m==2 ? "SINGLE_PHASE" : "DELTA",
            "p_min"=>zeros(n),"p_max"=>fill(1000.,n),"q_min"=>zeros(n),"q_max"=>zeros(n),"s_max"=>fill(400.,n)))
        opts=(;objective=:source_import,lifting,lifted_power_base=lb,
            generator_power_bases=Dict("g"=>gb),specialization=:conductor_regions,linear_elimination=:passive_blocks)
        plain=build_opf(net,IVRNLP(;opts...))
        reused=build_opf(net,IVRNLP(;opts...,power_sharing=:generators);optimizer=Ipopt.Optimizer)
        @test reused.numerical_diagnostics[:reused_generator_power_count]==n
        @test num_variables(plain.model)-num_variables(reused.model)>=2n
        r=solve_ivr_nlp_opf(reused;solver_options=S.P.STRICT)
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test real.(r.powers[(:generator,"g")])≈fill(400.,n) atol=1e-4
        @test ivr_nlp_point_report(plain,point(r)).passed
        @test ivr_nlp_point_report(reused,point(r)).passed
        tight=deepcopy(net);tight["generator"]["g"]["s_max"][1]=399.
        @test !physical_residuals(tight,point(r);delta_dispatch=:coil).passed
        @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(;opts...,power_sharing=:generators)),point(r)).passed
        update_ivr_generators!(reused,Dict("g"=>(p_min=fill(100.,n),p_max=fill(100.,n))))
        rr=solve_ivr_nlp_opf(reused;solver_options=S.P.STRICT)
        @test rr.solve.optimal && physical_residuals(reused.network,rr).passed
        @test ivr_nlp_point_report(build_opf(reused.network,IVRNLP(;opts...)),point(rr)).passed
        d=result_dict(reused,rr);io=IOBuffer();write_result(d,io);seekstart(io)
        @test isequal(read_result(io),d)
    end
    @test_throws ArgumentError build_opf(C.case(segments=1),IVRNLP(power_sharing=:unknown))
    b=build_opf(C.case(segments=1),IVRNLP(power_sharing=:generators))
    @test b.numerical_diagnostics[:reused_generator_power_count]==0
end

include("../examples/benchmark_ivr_power_finalists.jl")
@testset "Finalist comparisons isolate lifting units and reuse" begin
    G=IVRPowerFinalistStudy;net=S.case(:quadratic_cost;segments=1)
    ps=G.profiles(net,:quadratic_cost)
    @test length(ps)==10 && allunique(p.name for p in ps)
    by=Dict(p.name=>p for p in ps)
    # Equal dictionaries can serialize keys in different orders; sort them first.
    canonical(x)=x isa AbstractDict ? sort!(collect(x);by=first) : x
    changed(a,b)=[k for k in fieldnames(IVRNLPOptions) if
        G.JSON3.write(canonical(getfield(a.options,k)))!=G.JSON3.write(canonical(getfield(b.options,k)))]
    @test changed(by["reduced_lifts_1k"],by["reduced_lifts_10k"])==[:lifted_power_base]
    @test changed(by["reduced_lifts_100k"],by["reduced_lifts_10k"])==[:lifted_power_base]
    @test changed(by["reduced_reuse"],by["reduced_lifts_10k"])==[:power_sharing]
    @test changed(by["reduced_nonadjacent"],by["reduced_10k"])==[:linear_elimination]
    mktempdir() do dir
        path=joinpath(dir,"source.json");open(io->G.JSON3.write(io,net),path,"w")
        @test_throws ArgumentError G.benchmark(path,path)
        r=G.benchmark(path,joinpath(dir,"report.json"))
        @test r["source_unchanged"] && r["network_unchanged"] && r["position_balanced"]
        @test r["ranking"]["objective_comparable"] && length(r["ranking"]["eligible"])==10
    end
end

end
