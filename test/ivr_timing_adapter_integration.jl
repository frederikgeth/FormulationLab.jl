#= Run explicitly with source root, B/C, and copied Ipopt directory arguments.
No timing campaign: one manufactured physical case, one disabled trial and one
synthetic-clock trial. No real wall-clock samples are returned by the adapter.
=#
using Test,FormulationLab,JSON3,Ipopt
include("../examples/ivr_timing_adapter.jl")
include("sdp_transformer_fixtures.jl")
const A=IVRTimingAdapter
length(ARGS)==3 || error("expected source root, freeze B/C, copied Ipopt directory")
root,freeze,ipopt_copy=ARGS
realpath(dirname(dirname(pathof(Ipopt))))==realpath(ipopt_copy) || error("wrong Ipopt loaded")
json(x)=JSON3.read(JSON3.write(x),Dict{String,Any})

@testset "Archived correctness executor and native observer: $freeze" begin
    file=joinpath(root,"examples","ivr_transfer_preflight.jl")
    original=read(file)
    loaded=A.load_preflight(root,freeze);P=loaded.executor
    @test read(file)==original
    @test loaded.source_sha256==A.PREFLIGHT_SHA256[freeze]
    @test_throws ArgumentError A.adapted_source([original;0x20],freeze)
    @test_throws ArgumentError A.adapted_source(original,"unknown")
    mktempdir() do wrong
        @test_throws ArgumentError A.load_preflight(wrong,freeze)
    end
    @test_throws ArgumentError A.trial(P;mode=:native)
    @test_throws ArgumentError A.trial(P;mode=:synthetic)
    @test_throws ArgumentError A.trial(P;mode=:disabled,synthetic_clock=()->1)

    net=_sdp_tx_case("single_phase")
    _sdp_zload!(net,"d",["p","n"],.01-.002im)
    source_id=only(keys(net["voltage_source"]))
    o=IVRNLPOptions(s_base=1e4,transformer_nameplate=:bmopftools,
        transformer_scaling=:nominal,ground_scaling=:voltage,row_scaling=:composed,
        objective=:power,power_terms=[IVRPowerTerm(channels=[(:voltage_source,source_id,1)],quadratic=1e-6)])
    profile=json((;name="manufactured_control",options=P.record(o)))
    reference=build_opf(net,IVRNLP(o));start=P.linear_start(reference)
    settings=json(P.SETTINGS);tol=json(P.TOLERANCES)
    mktempdir() do dir
        plain,point,shape=A.trial(P,net,profile,reference,start,nothing,joinpath(dir,"plain"),settings,tol)
        @test plain["accepted"]
        @test plain["timing"]["native_ipopt_wall_s"]===nothing
        ticks=Ref(0)
        measured,second,shape2=A.trial(P,net,profile,reference,start,point,joinpath(dir,"synthetic"),settings,tol;
            mode=:synthetic,synthetic_clock=()->(ticks[]+=100))
        @test measured["accepted"]
        @test ticks[]==200
        @test measured["timing"]["synthetic_elapsed_ns"]=="100"
        @test measured["timing"]["native_ipopt_wall_s"]===nothing
        @test measured["timing"]["optimizer_wrapper_wall_s"]===nothing
        @test shape==shape2
        @test isapprox(plain["objective"],measured["objective"];atol=1e-8)
        @test P.readjson(joinpath(dir,"synthetic.physical.json"))["passed"]
        @test measured["native_reader_equal"] && measured["complete_declared_bound_coverage"]
        T,r=A.recorder();@test !r.enabled && isempty(r.samples)
        @test_throws MethodError A.trial(P;mode=:synthetic,synthetic_clock=()->1)
        @test !r.enabled && isempty(r.samples)
    end
    @test read(file)==original
end
