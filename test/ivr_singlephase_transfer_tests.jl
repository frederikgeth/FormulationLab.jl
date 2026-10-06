module IVRSinglePhaseTransferTests
using Test, FormulationLab, JSON3
include("../examples/benchmark_ivr_singlephase_transfer.jl")
const S=IVRSinglePhaseTransferStudy
function original()
    net=S.P.ivr_compiler_case(conductors=2,segments=3)
    for b in values(net["bus"]),field in ("vpn_min","vpn_max");pop!(b,field,nothing);end
    net
end
changed(a,b)=Set(k for k in fieldnames(IVRNLPOptions) if JSON3.write(getfield(a,k))!=JSON3.write(getfield(b,k)))
@testset "Single-phase additions preserve physical inputs and exact provenance" begin
    input=original();before=deepcopy(input)
    for band in (:wide,:tight,:narrow)
        net,m=S.scenario(input;voltage_band=band)
        @test input==before
        @test length(m.selected_loads)==3 && length(m.voltage_additions)==6
        @test length(net["generator"])==2 && length(net["ibr"])==1
        @test Set(d["model"] for (id,d) in net["load"] if startswith(id,"study_"))==Set(["constant_current","zip","exponential"])
        for (f,table) in input
            if f in ("load","bus")
                @test all(all(net[f][id][k]==v for (k,v) in d) for (id,d) in table)
            else
                @test net[f]==table
            end
        end
        replay=deepcopy(input)
        for c in m.changes
            @test isequal(get(get(replay,c.family,Dict()),c.id,nothing),c.before)
            get!(replay,c.family,Dict{String,Any}())[c.id]=deepcopy(c.after)
        end
        @test replay==net
        width=band==:narrow ? .005 : .02
        @test all(x.limits_V≈(band==:wide ? fill(x.field=="vpn_min" ? 200. : 260.,length(x.terminals)) :
            (x.field=="vpn_min" ? 1-width : 1+width).*x.unloaded_voltage_V) for x in m.voltage_additions)
        point=S.M.E.S.U.G.H.S.L.start_point(net)
        activity=S.voltage_activity(net,point,m)
        @test length(activity.records)==6 && all(r.origin==:added && !r.active && !r.violated for r in activity.records)
        net["bus"]["b1"]["vpn_min"][1]=230.
        @test only(r for r in S.voltage_activity(net,point,m).records if r.bus=="b1" && r.field=="vpn_min").active
        net["bus"]["b1"]["vpn_min"][1]=231.
        @test only(r for r in S.voltage_activity(net,point,m).records if r.bus=="b1" && r.field=="vpn_min").violated
        @test all(x.limits_V[1]!=231. for x in m.voltage_additions)
        for tol in (-1.,NaN,Inf,true);@test_throws ArgumentError S.voltage_activity(net,point,m;atol_V=tol);end
    end
    input["bus"]["b1"]["vpn_min"]=[180.]
    net,m=S.scenario(input;voltage_band=:tight)
    @test net["bus"]["b1"]["vpn_min"]==[180.]
    @test length(m.voltage_additions)==5
    @test only(r for r in S.voltage_activity(net,S.M.E.S.U.G.H.S.L.start_point(net),m).records if r.bus=="b1" && r.field=="vpn_min").origin==:inherited
    @test_throws ArgumentError S.scenario(input;voltage_band=:unknown)
    bad=original();bad["bus"]["b1"]["perfectly_grounded_terminals"]=["5"]
    @test_throws FormulationLab.SDPInapplicableError S.scenario(bad)
end
@testset "Single-phase full controls and independent load scales" begin
    for band in (:wide,:tight,:narrow),work in (:quadratic_cost,:exchange_tracking),policy in ("none","gradient-based")
        net,m=S.scenario(original();voltage_band=band);before=deepcopy(net)
        ps=S.profiles(net,work;exchange_target_W=1000.,nlp_scaling_method=policy)
        @test length(ps)==9 && allunique(p.name for p in ps)
        for offset in (0,3,6)
            @test changed(ps[offset+1].options,ps[offset+2].options)==Set([:load_power_bases])
            @test changed(ps[offset+2].options,ps[offset+3].options)==Set([:load_power_row_scaling,:load_power_row_bases])
        end
        @test all(p.options.transformer_nameplate==:bmopftools && p.options.load_power_lifting for p in ps)
        mktempdir() do dir
            report=S.P.benchmark(net,joinpath(dir,"smoke.json");candidates=ps,repetitions=1,checkpoint=:sweep,
                initial_point=S.M.E.S.U.G.H.S.L.start_point(net))
            @test report["ranking"]["objective_comparable"] && length(report["ranking"]["eligible"])==9
            for r in report["profiles"],t in [r["warmup"];r["trials"]]
                @test Set(keys(t["vpn_min_slack_V"]))==Set(keys(t["vpn_max_slack_V"]))==Set(["b1","b2","b3"])
            end
        end
        empty!(ps[3].options.load_power_bases);empty!(ps[3].options.load_power_row_bases)
        @test !isempty(ps[6].options.load_power_bases) && !isempty(ps[6].options.load_power_row_bases)
        @test !isempty(ps[3].factors.load_power_row_bases)
        @test net==before
    end
end
end
