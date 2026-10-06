module IVRThreePhaseTransferTests
using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/benchmark_ivr_threephase_transfer.jl")
include("../examples/benchmark_ivr_hybrid.jl")
const T=IVRThreePhaseTransferStudy
function original(m)
    n=IVRHybridStudy.case(conductors=m,segments=4,charged=true)
    n["load"]=T.P.ivr_compiler_case(conductors=m,segments=4)["load"]
    empty!(n["generator"])
    n
end
shape(x::AbstractDict)=Dict(k=>shape(v) for (k,v) in x)
shape(x::AbstractVector)=shape.(x)
shape(x)=nothing
@testset "Three-phase factorial scenarios isolate physical interventions" begin
    for m in (3,4)
        n=original(m);before=deepcopy(n);scenarios=Dict()
        for filter_level in (:low,:high),load_law in (:constant_power,:voltage_dependent)
            net,manifest=T.scenario(n;filter_level,load_law);scenarios[(filter_level,load_law)]=net
            @test n==before
            @test all(net[k]==v for (k,v) in n if !(k in ("load","generator","ibr")))
            @test all(net["load"][id]==d for (id,d) in n["load"])
            @test length(manifest.sites)==4
            @test all(d["topology"]==(m==3 ? "THREE_LEG" : "FOUR_LEG") for d in values(net["ibr"]))
            replay=deepcopy(n)
            for c in manifest.changes
                @test c.before===nothing
                get!(replay,c.family,Dict{String,Any}())[c.id]=deepcopy(c.after)
            end
            get!(replay,"generator",Dict{String,Any}());get!(replay,"ibr",Dict{String,Any}())
            @test replay==net
        end
        for law in (:constant_power,:voltage_dependent)
            a=scenarios[(:low,law)];b=scenarios[(:high,law)]
            @test all(a[k]==b[k] for k in keys(a) if k!="ibr")
            for id in keys(a["ibr"])
                x=a["ibr"][id];y=b["ibr"][id]
                @test all(x[k]==y[k] for k in keys(x) if !(k in ("r_filter","x_filter")))
                @test y["r_filter"]≈10x["r_filter"] && y["x_filter"]≈10x["x_filter"]
            end
        end
        for level in (:low,:high)
            a=scenarios[(level,:constant_power)];b=scenarios[(level,:voltage_dependent)]
            @test all(a[k]==b[k] for k in keys(a) if k!="load")
            for id in keys(a["load"])
                @test all(a["load"][id][k]==b["load"][id][k] for k in ("bus","terminal_map","configuration","p_nom","q_nom"))
            end
        end
    end
    n=original(4)
    @test_throws ArgumentError T.scenario(n;filter_level=:zero)
    @test_throws ArgumentError T.scenario(n;load_law=:unknown)
    @test_throws ArgumentError T.scenario(first(T.scenario(n)))
    zero=deepcopy(n);foreach(d->d["p_nom"].=0.,values(zero["load"]))
    @test_throws ArgumentError T.scenario(zero)
    # An existing load must never be silently overwritten by a scenario name.
    collision=deepcopy(n);id=first(sort!(collect(keys(n["load"]))))
    collision["load"]["threephase_"*id]=deepcopy(n["load"][id])
    @test_throws ArgumentError T.scenario(collision)
end

@testset "Three-phase factorial recovery, internal losses and inherited bounds" begin
    for m in (3,4),level in (:low,:high),law in (:constant_power,:voltage_dependent),
        work in (:quadratic_cost,:exchange_tracking),policy in ("none","gradient-based")
        n=original(m);net,_=T.scenario(n;filter_level=level,load_law=law)
        ps=T.profiles(net,work;exchange_target_W=500.,nlp_scaling_method=policy)
        ref=build_opf(net,IVRNLP(first(ps).options));start=T.M.E.S.U.G.H.S.L.start_point(net)
        anchor=nothing;objective=nothing;export_ref=nothing
        for profile in ps
            b=build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer)
            enc=ivr_nlp_point_report(b,start)
            @test length(enc.variable_values)==num_variables(b.model)
            @test max(enc.max_binding_residual_pu,enc.max_reconstruction_residual_pu)<1e-10
            for (v,x) in enc.variable_values;set_start_value(v,x);end
            r=solve_ivr_nlp_opf(b;solver_options=merge(T.P.STRICT,profile.solver_options))
            @test r.solve.optimal && physical_residuals(net,r).passed
            p=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            if anchor===nothing;anchor=p;objective=r.objective;export_ref=result_dict(b,r);end
            @test ivr_nlp_point_report(ref,p).passed && ivr_nlp_point_report(b,anchor).passed
            @test r.objective≈objective atol=1e-7 rtol=1e-7
            source=sum(sum(s) for ((f,_),s) in r.powers if f==:voltage_source)
            expected=work==:quadratic_cost ? .25real(source)/1000 : ((real(source)-500)^2+imag(source)^2)/1e6
            for (f,id,k) in last(T.M.channels(net))
                s=r.powers[(f,id)][k];d=net[string(f)][id]
                expected+=work==:quadratic_cost ? .10real(r.powers[(f==:ibr ? :ibr_internal : f,id)][k])/1000+
                    .02real(s)^2/1e6+.002imag(s)^2/1e6 :
                    ((real(s)-(d["p_min"][k]+d["p_max"][k])/2)^2+imag(s)^2)/1e8
            end
            @test r.objective≈expected atol=1e-8
            d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
            @test isequal(read_result(io),d)
            @test all(shape(d[f])==shape(export_ref[f]) for f in FormulationLab._RESULT_TABLES)
            for (id,ibr) in net["ibr"]
                si=r.powers[(:ibr_internal,id)];sp=r.powers[(:ibr,id)]
                @test sum(real,si)-sum(real,sp)≈sum(ibr["r_filter"].*abs2.(r.current_candidate[(:ibr_internal,id)])) atol=1e-5
                rec=d["_formulationlab"]["devices"]["ibr"][id]
                @test [complex(x["p"],x["q"]) for x in rec["internal_power"]]≈si atol=1e-6
                @test [complex(x["cr"],x["ci"]) for x in rec["filter_current"]]≈r.current_candidate[(:ibr_internal,id)] atol=1e-6
            end
            # Tighten each inherited family around the unchanged recovered point.
            tight=deepcopy(net);line=first(sort!(collect(keys(n["line"]))))
            tight["line"][line]["i_max"]=.9abs.(p.currents[(:line_from,line)])
            @test !physical_residuals(tight,r).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(profile.options)),p).passed
            tight=deepcopy(net);field=m==3 ? "vpp_min" : "vpn_min";other=m==3 ? "b" : "n"
            tight["bus"]["b4"][field][1]=1.01abs(p.voltage[("b4","a")]-p.voltage[("b4",other)])
            @test !physical_residuals(tight,r).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(profile.options)),p).passed
        end
    end
end
end
