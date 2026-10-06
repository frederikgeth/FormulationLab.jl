module IVRLoadPowerUnitStudyTests
using Test,FormulationLab,JSON3
include("../examples/benchmark_ivr_load_power_units.jl")
const U=IVRLoadPowerUnitStudy
@testset "Declared load-unit treatments isolate column units" begin
    net=first(U.T.scenario(U.P.ivr_compiler_case(conductors=4,segments=4);load_law=:voltage_dependent))
    original=deepcopy(net)
    for work in (:quadratic_cost,:exchange_tracking),policy in ("none","gradient-based")
        ps=U.profiles(net,work;exchange_target_W=500.,nlp_scaling_method=policy)
        @test length(ps)==12 && allunique(p.name for p in ps)
        for k in 1:3,j in (3,6,9)
            a=ps[k];b=ps[k+j]
            changed=Set(f for f in fieldnames(IVRNLPOptions) if JSON3.write(getfield(a.options,f))!=JSON3.write(getfield(b.options,f)))
            @test changed ⊆ Set([:load_power_bases])
            @test a.solver_options==b.solver_options && a.formulation_name==b.formulation_name
        end
        mktempdir() do dir
            start=U.T.M.E.S.U.G.H.S.L.start_point(net)
            report=U.P.benchmark(net,joinpath(dir,"smoke.json");candidates=ps,repetitions=1,checkpoint=:sweep,initial_point=start)
            @test report["ranking"]["objective_comparable"]
            @test length(report["ranking"]["eligible"])==12
        end
        empty!(ps[1].options.load_power_bases)
        @test all(!isempty(p.options.load_power_bases) for p in ps[2:end])
        @test !isempty(ps[1].factors.load_power_bases)
    end
    @test net==original
    d=Dict("model"=>"constant_current","v_nom"=>[230.,230.],"p_nom"=>[-3.,0.],"q_nom"=>[4.,0.])
    tiny=Dict("load"=>Dict("a"=>deepcopy(d),"b"=>merge(deepcopy(d),Dict("v_nom"=>[2e4,2e4])),"c"=>merge(deepcopy(d),Dict("p_nom"=>zeros(2),"q_nom"=>zeros(2)))))
    @test U.assignments(tiny,:voltage_class)==Dict("a"=>1e3,"b"=>1e4,"c"=>1e3)
    @test U.assignments(tiny,:nominal_max)==Dict("a"=>5.,"b"=>5.,"c"=>1.)
    tiny["load"]["b"]["v_nom"]=[230.,2e4]
    @test_throws ArgumentError U.assignments(tiny,:voltage_class)
    @test_throws ArgumentError U.assignments(tiny,:unknown)
end
end
