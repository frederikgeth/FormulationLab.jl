module IVRSinglePhaseTransferTests
using Test, FormulationLab, JSON3, JuMP, Ipopt
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
@testset "Added DER capacity is a declared physical intervention" begin
    input=original();input["bus"]["b1"]["vpn_min"]=[180.];before=deepcopy(input)
    control,_=S.scenario(input)
    scaled_fields=Set(["p_min","p_max","q_min","q_max","s_max","i_max","p_dc_min","p_dc_max","p_avail"])
    for scale in (.5,1.,10.),band in (:wide,:inherited)
        net,m=S.scenario(input;voltage_band=band,dispatch_scale=scale)
        @test input==before && m.dispatch_scale==scale
        @test net["load"]==control["load"] && net["line"]==input["line"] && net["linecode"]==input["linecode"]
        @test net["bus"]["b1"]["vpn_min"]==[180.]
        @test band==:inherited ? net["bus"]==input["bus"] && isempty(m.voltage_additions) : net["bus"]==control["bus"]
        for family in ("generator","ibr"),(id,d) in control[family],(field,value) in d
            @test net[family][id][field]==(field in scaled_fields ? scale.*value : value)
        end
        replay=deepcopy(input)
        for c in m.changes;get!(replay,c.family,Dict{String,Any}())[c.id]=deepcopy(c.after);end
        @test replay==net
    end
    for scale in (0.,-1.,NaN,Inf,true,"10",1e308,big"1e1000")
        @test_throws ArgumentError S.scenario(input;dispatch_scale=scale)
        @test input==before
    end
    integer_input=deepcopy(input)
    for d in values(integer_input["load"]);d["p_nom"]=[1000];d["q_nom"]=[0];end
    huge,_=S.scenario(integer_input;dispatch_scale=typemax(Int))
    @test all(only(d["p_max"])>0 for d in values(huge["generator"]))
    @test all(only(d["p_max"])≈2000Float64(typemax(Int)) for d in values(huge["generator"]))
    unbounded,_=S.scenario(original();voltage_band=:inherited)
    @test_throws IVRNLPInapplicableError build_opf(unbounded,IVRNLP(load_power_lifting=true))
    floor_net,floor_manifest=S.scenario(input;voltage_band=:positive_floor)
    @test floor_net["bus"]["b1"]["vpn_min"]==[180.]
    @test all(!haskey(b,"vpn_max") for b in values(floor_net["bus"]))
    @test length(floor_manifest.voltage_additions)==2
    @test all(x.field=="vpn_min" && x.limits_V==[1.] for x in floor_manifest.voltage_additions)
    @test build_opf(floor_net,IVRNLP(load_power_lifting=true)) isa IVRNLPBuild
end

@testset "Inherited single-phase nameplate remains active under export" begin
    input=original();tm=["a","n"]
    # An inherited positive floor certifies the non-polynomial load-law domain.
    for k in 1:3;input["bus"]["b$k"]["vpn_min"]=[1.];end
    input["bus"]["hv"]=Dict("terminal_names"=>copy(tm),"perfectly_grounded_terminals"=>["n"])
    input["voltage_source"]["source"]["bus"]="hv"
    input["transformer"]=Dict("single_phase"=>Dict("tx"=>Dict(
        "bus_from"=>"hv","bus_to"=>"b0","terminal_map_from"=>copy(tm),"terminal_map_to"=>copy(tm),
        "v_nom_from"=>230.,"v_nom_to"=>230.,"s_rating"=>5000.,
        "r_series_from"=>0.,"x_series_from"=>0.,"r_series_to"=>0.,"x_series_to"=>0.,"g_no_load"=>0.,"b_no_load"=>0.)))
    net,m=S.scenario(input;voltage_band=:inherited,dispatch_scale=10.)
    @test net["transformer"]==input["transformer"] && net["bus"]==input["bus"]
    @test isempty(m.voltage_additions)
    for policy in ("none","gradient-based")
        ps=S.profiles(net,:exchange_tracking;exchange_target_W=-10000.,nlp_scaling_method=policy)
        start=S.M.E.S.U.G.H.S.L.start_point(net);anchor=nothing;objective=nothing
        ref=build_opf(net,IVRNLP(objective=:power,power_terms=first(ps).options.power_terms,transformer_nameplate=:bmopftools))
        for profile in ps
            b=build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer)
            enc=ivr_nlp_point_report(b,start)
            @test length(enc.variable_values)==num_variables(b.model)
            for (v,x) in enc.variable_values;set_start_value(v,x);end
            r=solve_ivr_nlp_opf(b;solver_options=merge(S.P.STRICT,profile.solver_options))
            @test r.solve.optimal && physical_residuals(net,r).passed
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            s=(point.voltage[("hv","a")]-point.voltage[("hv","n")])*conj(only(point.currents[(:transformer_coil_from,"single_phase/tx")]))
            @test abs(s)≈5000. atol=1e-3
            @test real(s)<-4990.
            @test ivr_nlp_point_report(ref,point).passed
            if anchor===nothing;anchor=point;objective=r.objective;end
            @test ivr_nlp_point_report(b,anchor).passed && isapprox(r.objective,objective;atol=1e-6,rtol=1e-8)
            d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
            @test isequal(read_result(io),d)
            @test d["transformer"]["tx"]["fr"]["1"]["s_max"]==5000.
            tight=deepcopy(net);tight["transformer"]["single_phase"]["tx"]["s_rating"]=4990.
            @test !physical_residuals(tight,r).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(profile.options)),point).passed
        end
    end
end
end
