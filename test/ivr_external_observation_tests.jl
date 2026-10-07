module IVRExternalObservationTests
using Test, FormulationLab, JSON3
include("../examples/benchmark_ivr_external_observations.jl")
include("sdp_transformer_fixtures.jl")
const E=IVRExternalObservationStudy

@testset "External transfer screen preserves evidence and rejects unsupported scope" begin
    n=_sdp_tx_case("delta_wye")
    # Positive voltage domain is required by the added current/ZIP/exponential laws.
    n["bus"]["t"]["vpn_min"]=fill(10.,3)
    n["load"]=Dict("d"=>Dict("bus"=>"t","terminal_map"=>["a","b","c","n"],
        "configuration"=>"WYE","p_nom"=>fill(100.,3),"q_nom"=>fill(10.,3)))
    n["transformer"]["delta_wye"]["tx"]["s_rating"]=1e3
    before=deepcopy(n)
    net,_=E.T.scenario(n;filter_level=:low,load_law=:voltage_dependent)
    @test n==before
    mktempdir() do folder
        input=joinpath(folder,"source.json");E.save(input,n)
        out=joinpath(folder,"evidence")
        report=E.run(input,out)
        @test report["all_trials_accepted"] && report["objectives_comparable"]
        @test report["source_unchanged"] && report["network_unchanged"]
        @test !report["timing_eligible"] && report["ranking"]===nothing
        @test length(report["trials"])==8
        # An existing evidence folder must never be overwritten by a rerun.
        saved=read(joinpath(out,"REPORT.json"))
        @test_throws ArgumentError E.run(input,out)
        @test read(joinpath(out,"REPORT.json"))==saved
        # A failed build is retained as a rejected trial, not silently dropped.
        p=first(E.profiles(net,:quadratic_cost;exchange_target_W=100.))
        ref=build_opf(net,IVRNLP(p.options));start=E.start_point(net)
        bad=deepcopy(net);bad["transformer"]["delta_wye"]["tx"]["s_rating"]=0.
        stem=joinpath(folder,"rejected")
        row,point=E.preflight_trial(bad,p,ref,nothing,start,stem)
        @test !row["accepted"] && point===nothing && haskey(row,"error")
        @test !JSON3.read(read(stem*".trial.json",String))["accepted"]
    end
    unsupported=deepcopy(net);unsupported["transformer"]["n_winding"]=Dict("x"=>Dict())
    @test_throws ArgumentError E.profiles(unsupported,:quadratic_cost;exchange_target_W=100.)
    stepup=deepcopy(net);stepup["transformer"]["delta_wye"]["tx"]["v_nom_to"]=1e4
    @test_throws ArgumentError E.profiles(stepup,:quadratic_cost;exchange_target_W=100.)
end
end
