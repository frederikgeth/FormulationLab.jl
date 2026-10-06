module IVRLineTransferTests
using Test,FormulationLab,JuMP,Ipopt,JSON3
include("../examples/benchmark_ivr_line_transfer.jl")
const L=IVRLineTransferStudy

@testset "Explicit line-transfer additions and provenance" begin
    for n in (2,3)
        original=L.P.ivr_compiler_case(conductors=n,segments=1);before=deepcopy(original)
        net,m=L.scenario(original;line_id="l1",terminal_indices=1:n,q_capacity_VAR=6e5)
        @test original==before
        @test all(net[k]==v for (k,v) in original)
        @test length(net["generator"])==2
        replay=deepcopy(original)
        for c in m.changes
            @test c.before===nothing
            get!(replay,c.family,Dict{String,Any}())[c.id]=deepcopy(c.after)
        end
        @test replay==net
        @test all(sum(d["q_max"])==6e5 && all(iszero,d["p_min"]) && all(iszero,d["p_max"]) for d in values(net["generator"]))
        for target in (-3e5,0.,3e5)
            ts=L.terms(m;target_VAR=target)
            @test sum(t.target for t in ts)==0
            @test sum(t.target for t in ts if only(t.channels)[2]=="line_transfer_from")==target
            @test all(t.quantity==:q && t.quadratic==1e-6 && t.linear==0 for t in ts)
        end
        for x in (0.,-1.,NaN,Inf,true,"600000",big"1e1000")
            @test_throws ArgumentError L.scenario(original;line_id="l1",terminal_indices=1:n,q_capacity_VAR=x)
        end
        for x in (NaN,Inf,true,"1",big"1e1000")
            @test_throws ArgumentError L.terms(m;target_VAR=x)
        end
        for ix in ([1],[1,1],[0,1],Any[true,2],(true,2),[1,2,3,4])
            @test_throws ArgumentError L.scenario(original;line_id="l1",terminal_indices=ix,q_capacity_VAR=1.)
        end
        @test_throws ArgumentError L.scenario(net;line_id="l1",terminal_indices=1:n,q_capacity_VAR=1.)
        @test_throws ArgumentError L.scenario(original;line_id="absent",terminal_indices=1:n,q_capacity_VAR=1.)
        ps=L.profiles(net,m;target_VAR=3e5)
        @test length(ps)==6 && allunique(p.name for p in ps)
        @test all(p.options.transformer_nameplate==:bmopftools for p in ps)
        empty!(ps[1].options.power_terms)
        @test !isempty(ps[2].options.power_terms)
    end
end

@testset "Inherited current caps under opposite reactive requests" begin
    for n in (2,3),direction in (-1,1),policy in ("none","gradient-based")
        original=L.P.ivr_compiler_case(conductors=n,segments=1,loading=0.)
        original["line"]["l1"]["length"]=.01
        net,m=L.scenario(original;line_id="l1",terminal_indices=1:n,q_capacity_VAR=1.2e6)
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
            @test maximum(abs.(r.current_candidate[(:line_from,"l1")]))≈200. atol=1e-5
            @test direction*sum(imag,r.powers[(:line_from,"l1")])>0
            obj=sum(t.quadratic*(sum(imag(r.powers[(f,id)][k]) for (f,id,k) in t.channels)-t.target)^2 for t in profile.options.power_terms)
            @test isapprox(obj,r.objective;atol=1e-6,rtol=1e-8)
            if anchor===nothing;anchor=point;objective=r.objective;end
            @test ivr_nlp_point_report(b,anchor).passed && isapprox(objective,r.objective;atol=1e-6,rtol=1e-8)
            tight=deepcopy(net);tight["line"]["l1"]["i_max"]=fill(199.,n)
            @test !physical_residuals(tight,r).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(profile.options)),point).passed
            for side in (:from,:to)
                @test all(abs.(point.currents[(Symbol("line_",side),"l1")]).<=200+1e-5)
            end
            d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
            @test isequal(read_result(io),d)
        end
    end
end
end
