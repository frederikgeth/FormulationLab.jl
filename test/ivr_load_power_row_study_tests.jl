module IVRLoadPowerRowStudyTests
using Test,FormulationLab,JSON3
include("../examples/benchmark_ivr_load_power_rows.jl")
const R=IVRLoadPowerRowStudy
changed(a,b)=Set(k for k in fieldnames(IVRNLPOptions) if JSON3.write(getfield(a,k))!=JSON3.write(getfield(b,k)))
@testset "Load row/column factorial isolates numerical factors" begin
    net=first(R.T.scenario(R.P.ivr_compiler_case(conductors=4,segments=4);load_law=:voltage_dependent))
    original=deepcopy(net)
    for work in (:quadratic_cost,:exchange_tracking),policy in ("none","gradient-based")
        ps=R.profiles(net,work;exchange_target_W=500.,nlp_scaling_method=policy)
        @test length(ps)==8 && allunique(p.name for p in ps)
        @test all(p.formulation_name==(work==:quadratic_cost ? "reduced_powers" : "reduced_reuse") for p in ps)
        for k in 1:4
            @test changed(ps[k].options,ps[k+4].options)==Set([:load_power_bases])
            @test ps[k].solver_options==ps[k+4].solver_options
        end
        for col in (0,4),k in 2:4
            @test changed(ps[col+1].options,ps[col+k].options)==Set([:load_power_row_scaling,:load_power_row_bases])
            @test ps[col+1].solver_options==ps[col+k].solver_options
        end
        @test changed(ps[2].options,ps[3].options)==Set([:load_power_row_scaling])
        mktempdir() do dir
            start=R.T.M.E.S.U.G.H.S.L.start_point(net)
            report=R.P.benchmark(net,joinpath(dir,"smoke.json");candidates=ps,repetitions=1,checkpoint=:sweep,initial_point=start)
            @test report["ranking"]["objective_comparable"]
            @test length(report["ranking"]["eligible"])==8
        end
        empty!(ps[2].options.load_power_row_bases);empty!(ps[2].options.load_power_bases)
        @test all(!isempty(ps[k].options.load_power_row_bases) for k in (3,4,6,7,8))
        @test all(!isempty(ps[k].options.load_power_bases) for k in (1,3,4,5,6,7,8))
        @test !isempty(ps[2].factors.load_power_row_bases)
    end
    @test net==original
end
@testset "Declared transfer subsets preserve controls" begin
    net=first(R.T.scenario(R.P.ivr_compiler_case(conductors=4,segments=4);load_law=:voltage_dependent))
    columns=(:uniform_1k,:voltage_class,:nominal_max);modes=(:off,:laws)
    for work in (:quadratic_cost,:exchange_tracking)
        ps=R.profiles(net,work;column_treatments=columns,row_modes=modes,exchange_target_W=500.)
        defaults=R.profiles(net,work;exchange_target_W=500.)
        @test length(ps)==6
        @test [p.name for p in ps]==[string(c)*"__"*string(m) for c in columns for m in modes]
        for p in ps
            @test p.options.load_power_bases==R.U.assignments(net,p.factors.column_treatment)
            @test p.options.load_power_row_bases==(p.factors.row_mode==:off ? Dict() : R.U.assignments(net,:nominal_max))
            if p.factors.column_treatment!=:voltage_class
                original=only(q for q in defaults if q.name==p.name)
                @test isempty(changed(p.options,original.options))
                @test p.solver_options==original.solver_options
            end
        end
    end
    for columns in ((),(:uniform_1k,:uniform_1k),(:unknown,))
        @test_throws ArgumentError R.profiles(net,:quadratic_cost;column_treatments=columns)
    end
    for modes in ((),(:laws,:laws),(:unknown,))
        @test_throws ArgumentError R.profiles(net,:quadratic_cost;row_modes=modes)
    end
    mktempdir() do dir
        input=joinpath(dir,"input.json");output=joinpath(dir,"report.json")
        open(io->JSON3.write(io,net),input,"w")
        report=R.benchmark(input,output;column_treatments=columns,row_modes=modes,exchange_target_W=500.)
        @test length(report["ranking"]["eligible"])==6
        @test report["position_balanced"] && report["source_unchanged"] && report["network_unchanged"]
        @test Set(keys(report["factors"]))==Set(string(c)*"__"*string(m) for c in columns for m in modes)
    end
end
end
