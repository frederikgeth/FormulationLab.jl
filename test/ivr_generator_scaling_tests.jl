module IVRGeneratorScalingTests
using Test, FormulationLab, JuMP, Ipopt
include("../examples/benchmark_ivr_power_objectives.jl")
include("../examples/ivr_transformer_stress_cases.jl")
const S=IVRPowerObjectiveStudy
const C=IVRTransformerStressCases
point(r)=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)

# Fixed voltage and zero source exchange give an independently solvable convex
# economic dispatch. Heterogeneous generator units must not change its optimum.
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

@testset "Independent dispatch units: oracle, ownership, inverse and updates" begin
    for sb in (1e3,1e5),gb in (1e2,1e4),divisor in (1.,100.)
        net=dispatch_case();bases=Dict("g1"=>gb,"g2"=>10gb)
        b=build_opf(net,IVRNLP(;s_base=sb,generator_power_bases=bases,objective=:power,power_terms=TERMS,objective_scale=divisor);optimizer=Ipopt.Optimizer)
        empty!(bases)
        @test b.options.generator_power_bases==Dict("g1"=>gb,"g2"=>10gb)
        @test b.numerical_diagnostics[:generator_power_bases]==Dict("g1"=>gb,"g2"=>10gb)
        variables=all_variables(b.model)
        for cap in (3000.,1000.)
            update_ivr_generators!(b,Dict("g1"=>(p_max=[cap],cost=[99.])))
            r=solve_ivr_nlp_opf(b;solver_options=S.P.STRICT)
            @test r.solve.optimal && physical_residuals(b.network,r).passed
            p1=min(cap,11000/6);p2=3000-p1
            expected=.001p1+1e-6p1^2+2e-6p2^2+1e-6*450^2+3e-6*150^2
            @test r.powers[(:generator,"g1")][1]≈p1+450im atol=1e-4
            @test r.powers[(:generator,"g2")][1]≈p2+150im atol=1e-4
            @test r.objective≈expected atol=1e-8
            report=ivr_nlp_point_report(b,point(r))
            @test report.passed && isapprox(report.objective,expected;atol=1e-8)
            @test report.variable_values[only(b.generator_variables["g1"].p)]≈p1/gb atol=1e-6
            @test report.variable_values[only(b.generator_variables["g2"].q)]≈150/(10gb) atol=1e-6
            @test upper_bound(only(b.generator_variables["g1"].p))==cap/gb
            reference=build_opf(b.network,IVRNLP(;s_base=sb,objective=:power,power_terms=TERMS,objective_scale=divisor))
            @test ivr_nlp_point_report(reference,point(r)).passed
            @test ivr_nlp_point_report(reference,point(r)).objective≈expected atol=1e-8
            @test b.coordinates.reconstruction==reference.coordinates.reconstruction
            @test all_variables(b.model)==variables
            d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
            @test isequal(read_result(io),d)
        end
    end
end

@testset "Dispatch units compose with current regions and retain original limits" begin
    for limit in (:capability,:current,:voltage),gb in (1e2,1e5),reduced in (false,true)
        net=C.case(;limit,segments=3);w=C.expected(limit)
        opts=IVRNLPOptions(;objective=:source_import,objective_scale=1e4,
            generator_power_bases=Dict("der"=>gb),current_power_bases=Dict("b0"=>1e3),
            transformer_scaling=:nominal,row_scaling=:composed,ground_scaling=:voltage,
            specialization=reduced ? :conductor_regions : :off,
            linear_elimination=reduced ? :passive_blocks : :off,
            device_elimination=reduced ? :transformer_currents : :off,
            lifting=:bounded_observations,observation_sharing=:exact)
        b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
        start=ivr_nlp_point_report(b,S.U.G.H.S.L.start_point(net))
        @test isempty(start.missing_channels) && length(start.variable_values)==num_variables(b.model)
        for (v,x) in start.variable_values;set_start_value(v,x);end
        r=solve_ivr_nlp_opf(b;solver_options=S.P.STRICT)
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test r.objective≈w.source_W atol=1e-4
        @test ivr_nlp_point_report(b,point(r)).passed
        @test ivr_nlp_point_report(build_opf(net,IVRNLP(objective=:source_import)),point(r)).passed
        tight=deepcopy(net)
        limit==:capability && (tight["generator"]["der"]["s_max"][1]-=1.)
        limit==:current && (tight["line"]["l3"]["i_max"][1]-=.1)
        limit==:voltage && (tight["bus"]["b3"]["vpn_max"][1]-=.1)
        @test !physical_residuals(tight,point(r);delta_dispatch=:coil).passed
        @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(opts)),point(r)).passed
        # Reduce demand before the fixed 200 W update: 2 kW demand would
        # violate the manufactured 5 A import limit independently of units.
        update_ivr_loads!(b,Dict("demand"=>(p=[1000.],q=[0.])))
        refs=b.generator_variables["der"];vars=all_variables(b.model)
        for change in ((p_min=[200.],p_max=[200.],q_min=[0.],q_max=[0.]),
                       (p_min=nothing,p_max=[200.],q_min=nothing,q_max=[0.]),
                       (p_min=[0.],p_max=nothing,q_min=[0.],q_max=nothing))
            update_ivr_generators!(b,Dict("der"=>change))
            rr=solve_ivr_nlp_opf(b;solver_options=S.P.STRICT)
            @test rr.solve.optimal && physical_residuals(b.network,rr).passed
            @test ivr_nlp_point_report(build_opf(b.network,IVRNLP(opts)),point(rr)).passed
            @test b.generator_variables["der"]===refs && all_variables(b.model)==vars
        end
    end
end

@testset "Dispatch scaling: delta coils, physical costs and refusal guards" begin
    for conductors in (3,4),gb in (1e2,1e5)
        net=S.P.ivr_compiler_case(;conductors,segments=2)
        net["generator"]=Dict("delta"=>Dict("bus"=>"b2","terminal_map"=>["a","b","c"],
            "configuration"=>"DELTA","p_min"=>zeros(3),"p_max"=>fill(1000.,3),
            "q_min"=>fill(-300.,3),"q_max"=>fill(300.,3)))
        target=ComplexF64[500+100im,300-50im,200+40im]
        terms=[IVRPowerTerm(channels=[(:generator,"delta",k)];quantity,
            target=quantity==:p ? real(target[k]) : imag(target[k]),quadratic=1e-6) for k in 1:3 for quantity in (:p,:q)]
        b=build_opf(net,IVRNLP(;objective=:power,power_terms=terms,objective_scale=1.,
            generator_power_bases=Dict("delta"=>gb),specialization=:conductor_difference,
            linear_elimination=:passive_blocks,lifting=:powers);optimizer=Ipopt.Optimizer)
        r=solve_ivr_nlp_opf(b;solver_options=S.P.STRICT)
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test r.powers[(:generator,"delta")]≈target atol=1e-3
        @test ivr_nlp_point_report(b,point(r)).passed
    end
    for gb in (1e2,1e5)
        net=C.case(segments=2);net["voltage_source"]["grid"]["cost"]=[.2,.2]
        net["generator"]["der"]["cost"]=[.1]
        b=build_opf(net,IVRNLP(;objective=:cost,objective_scale=1.,generator_power_bases=Dict("der"=>gb));optimizer=Ipopt.Optimizer)
        for cost in (.1,.5)
            update_ivr_generators!(b,Dict("der"=>(cost=[cost],)))
            r=solve_ivr_nlp_opf(b;solver_options=S.P.STRICT)
            @test r.solve.optimal && physical_residuals(b.network,r).passed
            pg=real(only(r.powers[(:generator,"der")]));ps=sum(real,r.powers[(:voltage_source,"grid")])
            @test r.objective≈(.2ps+cost*pg)/1000 atol=1e-8
            @test cost==.1 ? isapprox(pg,250.;atol=1e-3) : abs(pg)<1e-3
            @test ivr_nlp_point_report(b,point(r)).objective≈r.objective atol=1e-8
        end
    end
    net=dispatch_case()
    for bases in (Dict("absent"=>1e3),Dict("g1"=>0.),Dict("g1"=>-1.),Dict("g1"=>NaN),Dict("g1"=>Inf),Dict("g1"=>nextfloat(0.)))
        @test_throws ArgumentError build_opf(net,IVRNLP(generator_power_bases=bases))
    end
    b=build_opf(net,IVRNLP(generator_power_bases=Dict("g1"=>1e3)))
    @test b.generator_variables["g2"].power_base==b.electrical.sb
    @test b.generator_variables["g1"].power_base==1e3
end
include("../examples/benchmark_ivr_generator_units.jl")
@testset "Generator-unit study holds other coordinates fixed" begin
    G=IVRGeneratorUnitStudy;net=S.case(:quadratic_cost;segments=1)
    ps=G.profiles(net,:quadratic_cost)
    @test length(ps)==6 && allunique(p.name for p in ps)
    for reduced in (false,true)
        group=filter(p->p.factors.reduced==reduced,ps)
        for p in group[2:end]
            changed=[k for k in fieldnames(IVRNLPOptions) if
                G.JSON3.write(getfield(p.options,k))!=G.JSON3.write(getfield(first(group).options,k))]
            @test changed==[:generator_power_bases]
        end
    end
    mktempdir() do dir
        path=joinpath(dir,"source.json");open(io->G.JSON3.write(io,net),path,"w")
        @test_throws ArgumentError G.benchmark(path,path)
        r=G.benchmark(path,joinpath(dir,"report.json");blocks=1)
        @test r["source_unchanged"] && r["network_unchanged"] && r["position_balanced"]
        @test r["ranking"]["objective_comparable"] && length(r["ranking"]["eligible"])==6
    end
end

end
