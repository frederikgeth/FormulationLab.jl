module IVRZeroLoadObservationTests
using Test, FormulationLab, JSON3
include("../examples/benchmark_ivr_zero_load_observations.jl")
include("sdp_transformer_fixtures.jl")
const O=IVRZeroLoadObservationStudy
@testset "Zero-load observation protocol controls and balanced orders" begin
    for batch in ("exploration","confirmation")
        schedule=O.orders(batch)
        @test length(schedule)==10
        @test all(sort(o)==collect(1:5) for o in schedule)
        @test all(count(o->o[k]==j,schedule)==2 for j in 1:5 for k in 1:5)
        @test all(sum(count(==((j,k)),zip(o[1:end-1],o[2:end])) for o in schedule)==2
            for j in 1:5 for k in 1:5 if j!=k)
    end
    @test O.orders("confirmation")==reverse(O.orders("exploration"))
    @test_throws ArgumentError O.orders("invalid")
    n=_sdp_tx_case("delta_wye")
    n["bus"]["t"]["vpn_min"]=fill(10.,3)
    n["load"]=Dict("zero"=>Dict("bus"=>"t","terminal_map"=>["a","b","c","n"],
        "configuration"=>"WYE","p_nom"=>zeros(3),"q_nom"=>zeros(3)),
        "positive"=>Dict("bus"=>"t","terminal_map"=>["a","b","c","n"],
        "configuration"=>"WYE","p_nom"=>fill(100.,3),"q_nom"=>fill(10.,3)))
    n["transformer"]["delta_wye"]["tx"]["s_rating"]=1e3
    net,_=O.E.T.scenario(n;filter_level=:low,load_law=:voltage_dependent)
    before=deepcopy(net)
    for work in (:quadratic_cost,:exchange_tracking),mode in (:off,:transformer_currents)
        ps=O.profiles(net,work,mode;exchange_target_W=100.)
        @test [p.name for p in ps]==["powers","coil_voltages","coil_currents","coils","all"]
        @test all(p.options.zero_load_elimination && p.options.device_elimination==mode for p in ps)
        for p in ps[2:end]
            changed=Set(k for k in fieldnames(IVRNLPOptions) if JSON3.write(getfield(p.options,k))!=JSON3.write(getfield(first(ps).options,k)))
            @test changed ⊆ Set([:lifting,:observation_selection])
        end
    end
    @test net==before
    @test_throws ArgumentError O.profiles(net,:quadratic_cost,:all_transformer_currents;exchange_target_W=100.)
    mktempdir() do folder
        input=joinpath(folder,"input.json");O.E.save(input,net)
        out=joinpath(folder,"evidence");report=O.run(input,out)
        @test report["all_trials_accepted"] && report["objectives_comparable"]
        @test report["source_unchanged"] && report["network_unchanged"]
        @test length(report["trials"])==20
        @test report["pending_trial"]===nothing && !report["timing_eligible"] && report["ranking"]===nothing
        saved=read(joinpath(out,"REPORT.json"))
        @test_throws ArgumentError O.run(input,out)
        @test read(joinpath(out,"REPORT.json"))==saved
        for path in filter(p->endswith(p,".result.json"),readdir(out;join=true))
            d=JSON3.read(read(path,String),Dict{String,Any})
            @test d["_formulationlab"]["zero_load_elimination_report"]["eliminated_complex_coordinates"]==3
            @test all(q["p"]==q["q"]==0 for q in d["_formulationlab"]["devices"]["load"]["zero"]["coil_power"])
        end
    end
end
end
