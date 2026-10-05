module IVRMixedDeviceTests
using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/benchmark_ivr_mixed_devices.jl")
include("../examples/benchmark_ivr_hybrid.jl")
const M=IVRMixedDeviceStudy
const H=IVRHybridStudy
shape(x::AbstractDict)=Dict(k=>shape(v) for (k,v) in x)
shape(x::AbstractVector)=shape.(x)
shape(x)=nothing
function fixture(m)
    n=H.case(conductors=m,segments=4)
    g=n["generator"]["der"];d=deepcopy(g);delete!(d,"configuration")
    d["topology"]=m==2 ? "SINGLE_PHASE" : m==3 ? "THREE_LEG" : "FOUR_LEG"
    nc=length(d["p_max"])
    merge!(d,Dict("r_filter"=>fill(.2,nc),"x_filter"=>fill(.08,nc),"b_filter_shunt"=>.001,
        "dc_link_coupled"=>true,"p_dc_min"=>0.,"p_dc_max"=>.3sum(d["p_max"]),"p_avail"=>.5sum(d["p_max"])))
    n["ibr"]=Dict("converter"=>d)
    l=n["load"]["d4"];l["model"]="exponential";l["v_nom"]=fill(m==3 ? 230sqrt(3) : 230.,nc)
    l["gamma_p"]=fill(.4,nc);l["gamma_q"]=fill(-.5,nc)
    n
end
@testset "Mixed objectives price PCC and internal powers explicitly" begin
    n=fixture(4);before=deepcopy(n)
    src,dispatch=M.channels(n)
    @test length(src)==4 && length(dispatch)==6
    ts=M.terms(n,:quadratic_cost)
    @test count(t->first(t.channels)[1]==:ibr_internal,ts)==3
    @test all(t.linear==.0001 for t in ts if first(t.channels)[1]==:ibr_internal)
    @test !any(t->first(t.channels)[1]==:ibr_internal,M.terms(n,:exchange_tracking;exchange_target_W=500.))
    for family in ("generator","ibr");n[family][first(keys(n[family]))]["cost"]=[-999.,-999.,-999.];end
    @test JSON3.write(M.terms(n,:quadratic_cost))==JSON3.write(ts)
    for family in ("generator","ibr"), mode in (:missing,:nan,:inverted,:bool,:scalar,:length)
        bad=deepcopy(n);d=first(values(bad[family]))
        mode==:missing && delete!(d,"q_min")
        mode==:nan && (d["p_max"][1]=NaN)
        mode==:inverted && (d["p_min"][1]=1e9)
        mode==:bool && (d["p_max"]=Any[true,1.,1.])
        mode==:scalar && (d["q_max"]=1.)
        mode==:length && (d["q_max"]=[1.])
        @test_throws ArgumentError M.terms(bad,:quadratic_cost)
    end
    for target in (nothing,Inf,true)
        @test_throws ArgumentError M.terms(n,:exchange_tracking;exchange_target_W=target)
    end
    @test_throws ArgumentError M.terms(n,:unknown)
    @test_throws ArgumentError M.profiles(n,:quadratic_cost;nlp_scaling_method="bad")
    ps=M.profiles(before,:quadratic_cost)
    @test length(ps)==6 && allunique(p.name for p in ps)
    empty!(ps[1].options.power_terms)
    @test all(!isempty(p.options.power_terms) for p in ps[2:end])
    ibronly=deepcopy(before);empty!(ibronly["generator"])
    @test length(last(M.channels(ibronly)))==3
    for d in values(ibronly["ibr"]);d["p_max"]=copy(d["p_min"]);end
    @test_throws ArgumentError M.channels(ibronly)
end

@testset "Source-preserving additions and load laws" begin
    original=M.P.ivr_compiler_case(conductors=2,segments=4);before=deepcopy(original)
    for mixed in (false,true)
        net,manifest=M.scenario(original;mixed)
        @test original==before
        @test length(manifest.selected_loads)==4
        @test length(net["generator"])==(mixed ? 2 : 4)
        @test length(get(net,"ibr",Dict()))==(mixed ? 2 : 0)
        @test all(net["load"][id]==d for (id,d) in original["load"])
        replay=deepcopy(original)
        for c in manifest.changes
            @test get(get(replay,c.family,Dict()),c.id,nothing)==c.before
            get!(replay,c.family,Dict{String,Any}())[c.id]=deepcopy(c.after)
        end
        @test replay==net
        mixed && @test Set(d["model"] for (id,d) in net["load"] if startswith(id,"study_"))==Set(["constant_current","zip","exponential"])
    end
    @test_throws ArgumentError M.scenario(fixture(2))
    zero=deepcopy(original);foreach(d->d["p_nom"].=0.,values(zero["load"]))
    @test_throws ArgumentError M.scenario(zero)
end

@testset "Mixed full/reduced physical membership, bounds and SI export" begin
    for m in (2,3,4),workload in (:quadratic_cost,:exchange_tracking),policy in ("none","gradient-based")
        net=fixture(m);before=deepcopy(net);ps=M.profiles(net,workload;exchange_target_W=500.,nlp_scaling_method=policy)
        start=M.E.S.U.G.H.S.L.start_point(net);ref=nothing;anchor=nothing;reference_export=nothing;objective=nothing
        for profile in ps
            b=build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer)
            enc=ivr_nlp_point_report(b,start)
            @test length(enc.variable_values)==num_variables(b.model)
            @test max(enc.max_binding_residual_pu,enc.max_reconstruction_residual_pu)<1e-10
            for (v,x) in enc.variable_values;set_start_value(v,x);end
            r=solve_ivr_nlp_opf(b;solver_options=merge(M.P.STRICT,profile.solver_options))
            @test r.solve.optimal && physical_residuals(net,r).passed
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            ref===nothing && (ref=b;anchor=point;objective=r.objective;reference_export=result_dict(b,r))
            @test ivr_nlp_point_report(ref,point).passed && ivr_nlp_point_report(b,anchor).passed
            @test r.objective≈objective atol=1e-7 rtol=1e-7
            source=sum(sum(s) for ((f,_),s) in r.powers if f==:voltage_source)
            expected=workload==:quadratic_cost ? .25real(source)/1000 : ((real(source)-500)^2+imag(source)^2)/1e6
            for (f,id,k) in last(M.channels(net))
                s=r.powers[(f,id)][k];d=net[string(f)][id]
                expected+=workload==:quadratic_cost ? .10real(r.powers[(f==:ibr ? :ibr_internal : f,id)][k])/1000+
                    .02real(s)^2/1e6+.002imag(s)^2/1e6 :
                    ((real(s)-(d["p_min"][k]+d["p_max"][k])/2)^2+imag(s)^2)/1e8
            end
            @test r.objective≈expected atol=1e-8
            si=r.powers[(:ibr_internal,"converter")];sp=r.powers[(:ibr,"converter")]
            loss=sum(real,si)-sum(real,sp)
            @test loss≈sum(.2abs2(i) for i in r.current_candidate[(:ibr_internal,"converter")]) atol=1e-5
            @test loss>0
            if workload==:quadratic_cost
                @test sum(real,si)≈net["ibr"]["converter"]["p_dc_max"] atol=1e-3
            end
            exported=result_dict(b,r);io=IOBuffer();write_result(exported,io);seekstart(io)
            @test isequal(read_result(io),exported)
            for family in ("bus","line","load","generator","ibr","voltage_source","ground")
                @test shape(exported[family])==shape(reference_export[family])
            end
            record=exported["_formulationlab"]["devices"]["ibr"]["converter"]
            @test [complex(x["p"],x["q"]) for x in record["internal_power"]]≈si atol=1e-6
            @test [complex(x["cr"],x["ci"]) for x in record["filter_current"]]≈r.current_candidate[(:ibr_internal,"converter")] atol=1e-6
            for field in ("filter_current","internal_voltage","internal_power")
                @test length(exported["_formulationlab"]["devices"]["ibr"]["converter"][field])==(m==2 ? 1 : 3)
            end
            # Each named original bound must reject the unchanged recovered state.
            for family in ("ibr","generator")
                id=family=="ibr" ? "converter" : "der"
                tight=deepcopy(net);tight[family][id]["s_max"]=.9abs.(r.powers[(Symbol(family),id)])
                @test !physical_residuals(tight,r).passed
                @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(profile.options)),point).passed
            end
            tight=deepcopy(net);tight["ibr"]["converter"]["p_dc_max"]=sum(real,si)-1.
            @test !physical_residuals(tight,r).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(profile.options)),point).passed
            tight=deepcopy(net);field=m==3 ? "vpp_min" : "vpn_min"
            a=m==3 ? "b" : "n";tight["bus"]["b4"][field][1]=1.01abs(point.voltage[("b4","a")]-point.voltage[("b4",a)])
            @test !physical_residuals(tight,r).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(profile.options)),point).passed
        end
        @test net==before
    end
end
end
