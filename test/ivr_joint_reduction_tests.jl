module IVRJointReductionTests
using Test, FormulationLab, JSON3
include("../examples/benchmark_ivr_joint_reductions.jl")
include("sdp_transformer_fixtures.jl")
const J=IVRJointReductionStudy
@testset "Eight-arm within-block factorial and interaction contrasts" begin
    @test length(unique(J.arms()))==8
    @test J.orders("confirmation")==reverse(J.orders("exploration"))
    @test_throws ArgumentError J.orders("unknown")
    for batch in ("exploration","confirmation")
        schedule=J.orders(batch)
        @test length(schedule)==16 && all(sort(o)==collect(1:8) for o in schedule)
        for arm in 1:8,position in 1:8
            @test count(o->o[position]==arm,schedule)==2
        end
        for a in 1:8,b in 1:8
            a==b && continue
            @test sum(count(==((a,b)),zip(o[1:end-1],o[2:end])) for o in schedule)==2
        end
    end
    base=Dict(J.arm(m,l,z)=>(m==:off ? 1. : .9)*(l==:powers ? 1. : 1.2)*(z ? .8 : 1.)
        for m in (:off,:transformer_currents) for l in (:powers,:bounded_observations) for z in (false,true))
    for scale in (1e-6,1.,1e6)
        c=J.contrasts(Dict(k=>scale*v for (k,v) in base))
        @test all(x≈.8 for x in values(c.zero_over_retained))
        @test all(x≈1.2 for x in values(c.broad_over_powers))
        @test all(x≈.9 for x in values(c.eliminated_over_explicit))
        @test all(x≈1. for x in values(c.zero_lifting_interaction))
        @test c.three_way_interaction≈1.
    end
    coupled=copy(base)
    coupled[J.arm(:off,:bounded_observations,true)]*=.75
    coupled[J.arm(:transformer_currents,:bounded_observations,true)]*=.5
    c=J.contrasts(coupled)
    @test c.zero_lifting_interaction["off"]≈.75
    @test c.zero_lifting_interaction["transformer_currents"]≈.5
    @test c.three_way_interaction≈2/3
    for bad in (0.,-1.,NaN,Inf)
        d=copy(base);d[first(J.arms())]=bad;@test_throws ArgumentError J.contrasts(d)
    end
    d=copy(base);delete!(d,first(J.arms()));@test_throws ArgumentError J.contrasts(d)
    d=copy(base);d["extra"]=1.;@test_throws ArgumentError J.contrasts(d)
    net=_sdp_tx_case("delta_wye")
    net["generator"]=Dict("g"=>Dict("bus"=>"t","terminal_map"=>["a","b","c","n"],
        "configuration"=>"WYE","p_min"=>zeros(3),"p_max"=>fill(200.,3),
        "q_min"=>fill(-100.,3),"q_max"=>fill(100.,3),"s_max"=>fill(250.,3)))
    before=deepcopy(net);ps=J.profiles(net;exchange_target_W=100.)
    @test [p.name for p in ps]==J.arms() && net==before
    @test length(Set((p.options.device_elimination,p.options.lifting,p.options.zero_load_elimination) for p in ps))==8
    for p in ps
        @test Set(k for k in fieldnames(IVRNLPOptions) if JSON3.write(getfield(p.options,k))!=JSON3.write(getfield(first(ps).options,k))) ⊆
            Set([:device_elimination,:lifting,:zero_load_elimination])
    end
    mktempdir() do dir
        write(joinpath(dir,"keep.txt"),"existing evidence")
        @test_throws ArgumentError J.run_timing("missing-preflight",dir,"exploration")
        @test read(joinpath(dir,"keep.txt"),String)=="existing evidence"
        @test_throws ArgumentError J.run_timing("missing-preflight",dir,"unknown")
    end
end
end
