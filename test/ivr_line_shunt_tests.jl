module IVRLineShuntTests
using Test,FormulationLab,JuMP,Ipopt,JSON3,LinearAlgebra
include("../examples/benchmark_ivr_line_transfer.jl")
const L=IVRLineTransferStudy

@testset "SI endpoint activity, positional ratings and invalid observations" begin
    net=L.shunt_fixture(conductors=3)
    point=(;currents=Dict((:line_from,"l1")=>ComplexF64[200,199,201],(:line_to,"l1")=>ComplexF64[198,200,199]))
    before=deepcopy(net);a=L.current_activity(net,point)
    @test net==before && length(a.records)==6
    @test count(x->x.active,a.records)==2 && count(x->x.violated,a.records)==1
    @test all(x.origin==:line && x.limit_A==200 for x in a.records)
    @test [x.terminal for x in a.records if x.side==:to]==["b","c","a"]
    @test only(x for x in a.records if x.slack_A<0).active==false
    delete!(net["line"]["l1"],"i_max")
    @test all(x.origin==:linecode && x.limit_A==250 && !x.active && !x.violated for x in L.current_activity(net,point).records)
    net["linecode"]["wire"]["i_max"]=fill(Inf,3)
    @test isempty(L.current_activity(net,point).records)
    for values in ([NaN,200,200],[-1,200,200],[200,200],Any[true,200,200])
        bad=deepcopy(before);bad["line"]["l1"]["i_max"]=values
        @test_throws ArgumentError L.current_activity(bad,point)
    end
    for tol in (-1.,NaN,Inf,true)
        @test_throws ArgumentError L.current_activity(before,point;atol_A=tol)
    end
    badpoint=deepcopy(point);badpoint.currents[(:line_to,"l1")][1]=NaN
    @test_throws ArgumentError L.current_activity(before,badpoint)
    for n in (1,4,2.,true)
        @test_throws ArgumentError L.shunt_fixture(conductors=n)
    end
    @test_throws ArgumentError L.shunt_fixture(storage=:unknown)
end

@testset "Shunt-loaded line caps act on each terminal current" begin
    for n in (2,3),storage in (:linecode,:inline),direction in (-1,1),policy in ("none","gradient-based")
        original=L.shunt_fixture(;conductors=n,storage);before=deepcopy(original)
        net,m=L.scenario(original;line_id="l1",terminal_indices=1:n,q_capacity_VAR=1.2e6)
        @test original==before && net["line"]==before["line"] && net["linecode"]==before["linecode"]
        # Independent physical matrices, including the declared length 0.5.
        C=n==2 ? [1. -1.;-1. 1.] : Matrix{Float64}(I,n,n).-ones(n,n)/3
        Z=.5 .* [i==j ? .004+.002im : .001+.0003im for i in 1:n,j in 1:n]
        Yf=.5*(.001+.02im)*C;Yt=.5*(.002+.08im)*C
        ps=L.profiles(net,m;target_VAR=direction*6e5,nlp_scaling_method=policy)
        ref=build_opf(net,IVRNLP(objective=:power,power_terms=first(ps).options.power_terms,transformer_nameplate=:bmopftools))
        start=L.M.E.S.U.G.H.S.L.start_point(net);anchor=nothing;objective=nothing
        for profile in ps
            b=build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer)
            enc=ivr_nlp_point_report(b,start)
            @test isempty(enc.missing_channels) && length(enc.variable_values)==num_variables(b.model)
            for (v,x) in enc.variable_values;set_start_value(v,x);end
            r=solve_ivr_nlp_opf(b;solver_options=merge(L.P.STRICT,profile.solver_options))
            @test r.solve.optimal && physical_residuals(net,r).passed
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(ref,point).passed && ivr_nlp_point_report(b,point).passed
            if anchor===nothing;anchor=point;objective=r.objective;end
            @test ivr_nlp_point_report(b,anchor).passed && isapprox(r.objective,objective;rtol=1e-8,atol=1e-6)
            l=net["line"]["l1"]
            vf=[point.voltage[("b0",t)] for t in l["terminal_map_from"]]
            vt=[point.voltage[("b1",t)] for t in l["terminal_map_to"]]
            cf=point.currents[(:line_from,"l1")];ct=point.currents[(:line_to,"l1")]
            series=cf-Yf*vf
            @test maximum(abs,vf-vt-Z*series)<1e-8
            @test maximum(abs,cf+ct-Yf*vf-Yt*vt)<1e-8
            @test maximum(abs,ct+series-Yt*vt)<1e-8
            @test minimum(abs.(cf+ct))>1
            active_side=direction>0 ? :to : :from
            a=L.current_activity(net,point)
            @test all(!x.violated && x.active==(x.side==active_side) for x in a.records)
            peakf=maximum(abs,cf);peakt=maximum(abs,ct);cap=(peakf+peakt)/2
            @test abs(peakf-peakt)>1
            @test all(x.side==active_side ? x.current_A>cap : x.current_A<cap for x in a.records)
            tight=deepcopy(net);tight["line"]["l1"]["i_max"]=fill(cap,n)
            @test !physical_residuals(tight,r).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(profile.options)),point).passed
            d=result_dict(b,r);device=d["_formulationlab"]["devices"]["line"]["l1"]
            for (field,expected) in (("series_current",series),("from_shunt_current",Yf*vf),("to_shunt_current",Yt*vt))
                exported=[complex(x["cr"],x["ci"]) for x in device[field]]
                @test maximum(abs,exported-expected)<1e-8
            end
            io=IOBuffer();write_result(d,io);seekstart(io)
            @test isequal(read_result(io),d)
        end
    end
end
end
