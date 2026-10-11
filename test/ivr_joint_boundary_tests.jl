module IVRJointBoundaryTests
using Test,FormulationLab,JuMP,Ipopt,JSON3
include("../examples/benchmark_ivr_joint_boundaries.jl")
const J=IVRJointBoundaryStudy
const L=J.L
# mumps_pivtol=1e-3 avoids platform-dependent pivot retries that ended these
# strict solves at ALMOST_LOCALLY_SOLVED on x86-64 Linux (see ivr_findings.md).
const PIVOT=(mumps_pivtol=1e-3,)
violations(r)=Set(x.label for x in r.records if x.residual>getproperty(r.tolerances,x.unit))

@testset "Declared joint-boundary interventions and reporting" begin
    for n in (2,3),direction in (-1,1),treatment in (:joint,:wide_voltage,:loose_current)
        original=L.shunt_fixture(conductors=n)
        net,m=J.scenario(;conductors=n,direction,treatment)
        @test net["linecode"]==original["linecode"] && net["load"]==original["load"]
        @test net["line"]["l1"]["i_max"]==fill(treatment==:loose_current ? 250. : 200.,n)
        replay=deepcopy(original)
        for c in m.changes
            @test isequal(get(get(replay,c.family,Dict()),c.id,nothing),c.before)
            get!(replay,c.family,Dict{String,Any}())[c.id]=deepcopy(c.after)
        end
        @test replay==net && !m.original_fields_preserved
        @test all(g["p_min"]==-g["p_max"] && g["p_max"]==g["q_max"] for g in values(net["generator"]))
        ps=J.profiles(net,m)
        @test length(ps)==6 && allunique(p.name for p in ps)
        @test all(p.options.transformer_nameplate==:bmopftools for p in ps)
        @test all(count(t->t.quantity==:p,p.options.power_terms)==count(t->t.quantity==:q,p.options.power_terms)==(n==2 ? 2 : 6) for p in ps)
        point=L.M.E.S.U.G.H.S.L.start_point(net)
        a=J.voltage_activity(net,point,m)
        @test length(a.records)==(n==2 ? 1 : 3)
        @test all(x.active==(0<=x.slack_V<=a.atol_V) && x.violated==(x.slack_V<0) for x in a.records)
        for cap in (NaN,Inf,-1.,true)
            bad=deepcopy(net);bad["bus"]["b1"][m.voltage_field]=fill(cap,n==2 ? 1 : 3)
            @test_throws ArgumentError J.voltage_activity(bad,point,m)
        end
        @test_throws ArgumentError J.voltage_activity(net,point,m;atol_V=-1.)
    end
    for d in (0,2,true,1.)
        @test_throws ArgumentError J.scenario(direction=d)
    end
    @test_throws ArgumentError J.scenario(treatment=:unknown)
end

@testset "Independent current and voltage restrictions on P/Q dispatch" begin
    for n in (2,3),direction in (-1,1),policy in ("none","gradient-based")
        cases=Dict{Symbol,Any}()
        for treatment in (:joint,:wide_voltage,:loose_current)
            net,m=J.scenario(;conductors=n,direction,treatment)
            ps=J.profiles(net,m;nlp_scaling_method=policy)
            ref=build_opf(net,IVRNLP(objective=:power,power_terms=first(ps).options.power_terms,transformer_nameplate=:bmopftools))
            start=L.M.E.S.U.G.H.S.L.start_point(net);anchor=nothing;objective=nothing;solves=Dict()
            for profile in ps
                b=build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer)
                enc=ivr_nlp_point_report(b,start)
                @test isempty(enc.missing_channels) && length(enc.variable_values)==num_variables(b.model)
                for (v,x) in enc.variable_values;set_start_value(v,x);end
                r=solve_ivr_nlp_opf(b;solver_options=merge(L.P.STRICT,profile.solver_options,PIVOT))
                @test r.solve.optimal && physical_residuals(net,r).passed
                point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
                @test ivr_nlp_point_report(ref,point).passed && ivr_nlp_point_report(b,point).passed
                if anchor===nothing;anchor=point;objective=r.objective;end
                @test ivr_nlp_point_report(b,anchor).passed && isapprox(r.objective,objective;rtol=1e-8,atol=1e-6)
                current=L.current_activity(net,point);voltage=J.voltage_activity(net,point,m)
                side=direction==1 ? :to : :from
                @test all(x.side==side ? abs(x.slack_A)<=1e-5 : x.slack_A>1. for x in current.records)
                @test all(treatment==:wide_voltage ? x.slack_V>1. : abs(x.slack_V)<=1e-5 for x in voltage.records)
                @test all(x.active==(0<=x.slack_A<=1e-5) && x.violated==(x.slack_A<0) for x in current.records)
                @test all(x.active==(0<=x.slack_V<=1e-5) && x.violated==(x.slack_V<0) for x in voltage.records)
                d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
                @test isequal(read_result(io),d)
                solves[profile.name]=(;b,r,point)
            end
            cases[treatment]=(;net,m,solves)
        end
        joint=cases[:joint]
        for treatment in (:wide_voltage,:loose_current),name in keys(joint.solves)
            a=joint.solves[name];r=cases[treatment].solves[name]
            @test r.r.objective<a.r.objective-1.
            physical=physical_residuals(joint.net,r.r)
            @test !physical.passed && isempty(physical.unassessed)
            labels=violations(physical)
            @test treatment==:wide_voltage ? labels==Set(["bus/b1/"*joint.m.voltage_field]) :
                !isempty(labels) && issubset(labels,Set(["line/l1/from/i_max","line/l1/to/i_max"]))
            @test !ivr_nlp_point_report(a.b,r.point).passed
            @test ivr_nlp_point_report(r.b,a.point).passed
        end
    end
end
end
