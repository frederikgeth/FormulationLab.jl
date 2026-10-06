module IVRUrbanFinalistTests
using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/benchmark_ivr_urban_finalists.jl")
const U=IVRUrbanFinalistStudy
shape(x::AbstractDict)=Dict(k=>shape(v) for (k,v) in x)
shape(x::AbstractVector)=shape.(x)
shape(x)=nothing
changed(a,b)=Set(k for k in fieldnames(IVRNLPOptions) if JSON3.write(getfield(a,k))!=JSON3.write(getfield(b,k)))
@testset "Urban shortlist provenance, isolated contrasts and ownership" begin
    net=U.S.A.H.case(conductors=3,segments=6);before=deepcopy(net)
    ps=U.profiles(net,:quadratic_cost);by=Dict(p.name=>p for p in ps)
    @test length(ps)==16 && allunique(p.name for p in ps)
    old=U.F.profiles(net,:quadratic_cost);structural=U.S.profiles(net,:quadratic_cost)
    for (name,source,parent) in (("full_10k",old,"full_10k"),("full_1k",old,"full_1k"),
        ("full_powers",structural,"full_powers"),("reduced_1k",old,"reduced_1k"),
        ("dispatch100_unlifted",old,"reduced_dispatch_100k"),("powers",structural,"reduced_powers"),
        ("lifts10_reuse",old,"reduced_reuse"),("blocks_signed",structural,"blocks_signed_off"),
        ("blocks_signed_reuse",structural,"blocks_signed_generators"),("cap4_signed",structural,"cap4_signed_off"),
        ("cap4_signed_reuse",structural,"cap4_signed_generators"))
        @test isempty(changed(by[name].options,only(p for p in source if p.name==parent).options))
    end
    for (a,b,expected) in (("powers","powers_reuse",(:power_sharing,)),
        ("powers_reuse","lifts10_reuse",(:lifted_power_base,)),
        ("powers","dispatch100_lifts1",(:generator_power_bases,)),
        ("dispatch100_lifts1","dispatch100_lifts10",(:lifted_power_base,)),
        ("powers","cap4_powers",(:linear_elimination,)),
        ("powers_reuse","cap4_powers_reuse",(:linear_elimination,)),
        ("blocks_signed","blocks_signed_reuse",(:power_sharing,)),
        ("cap4_signed","cap4_signed_reuse",(:power_sharing,)),
        ("blocks_signed_reuse","cap4_signed_reuse",(:linear_elimination,)))
        @test changed(by[a].options,by[b].options)==Set(expected)
    end
    @test all(p->p.options.objective_scale==1. && p.options.passive_component_limit==4,ps)
    empty!(ps[1].options.power_terms);empty!(ps[1].options.generator_power_bases)
    @test all(!isempty(p.options.power_terms) && !isempty(p.options.generator_power_bases) for p in ps[2:end])
    @test net==before
    @test_throws ArgumentError U.profiles(net,:exchange_tracking)
    @test_throws ArgumentError U.profiles(net,:quadratic_cost;nlp_scaling_method="bad")
end
@testset "Urban finalists retain physical objectives, bounds and exports" begin
    for m in (2,3),workload in (:quadratic_cost,:exchange_tracking),policy in ("none","gradient-based")
        net=U.S.A.H.case(conductors=m,segments=6,charged=true)
        ps=U.profiles(net,workload;exchange_target_W=500.,nlp_scaling_method=policy)
        start=U.E.S.U.G.H.S.L.start_point(net);ref=nothing;anchor=nothing;objective=nothing;export_ref=nothing
        for profile in ps
            b=build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer);enc=ivr_nlp_point_report(b,start)
            @test length(enc.variable_values)==num_variables(b.model)
            @test max(enc.max_binding_residual_pu,enc.max_reconstruction_residual_pu)<1e-10
            for (v,x) in enc.variable_values;set_start_value(v,x);end
            r=solve_ivr_nlp_opf(b;solver_options=merge(U.P.STRICT,profile.solver_options))
            @test r.solve.optimal && physical_residuals(net,r).passed
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            ref===nothing && (ref=b;anchor=point;objective=r.objective;export_ref=result_dict(b,r))
            @test ivr_nlp_point_report(ref,point).passed && ivr_nlp_point_report(b,anchor).passed
            @test r.objective≈objective atol=1e-7 rtol=1e-7
            expected=sum(profile.options.power_terms) do t
                x=sum(w*(t.quantity==:p ? real(r.powers[(f,id)][k]) : imag(r.powers[(f,id)][k]))
                    for ((f,id,k),w) in zip(t.channels,t.weights))-t.target
                t.linear*x+t.quadratic*x^2
            end
            @test r.objective≈expected atol=1e-8
            d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
            @test isequal(read_result(io),d)
            for family in ("bus","line","load","generator","voltage_source","ground")
                @test shape(d[family])==shape(export_ref[family])
            end
            tight=deepcopy(net);tight["generator"]["der"]["s_max"]=.9abs.(r.powers[(:generator,"der")])
            @test !physical_residuals(tight,r).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(profile.options)),point).passed
            tight=deepcopy(net);field=m==3 ? "vpp_min" : "vpn_min";other=m==3 ? "b" : "n"
            tight["bus"]["b6"][field][1]=1.01abs(point.voltage[("b6","a")]-point.voltage[("b6",other)])
            @test !physical_residuals(tight,r).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(profile.options)),point).passed
        end
    end
end
@testset "Sweep checkpoints preserve complete trial and error reports" begin
    net=U.S.A.H.case(conductors=2,segments=2)
    ps=U.profiles(net,:quadratic_cost)[1:2]
    orders=[[1,2],[2,1]]
    mktempdir() do dir
        for checkpoint in (:trial,:sweep)
            path=joinpath(dir,string(checkpoint)*".json")
            r=U.P.benchmark(net,path;repetitions=2,candidates=ps,trial_orders=orders,checkpoint)
            saved=JSON3.read(read(path,String),Dict{String,Any})
            @test saved["checkpoint"]==string(checkpoint)
            @test saved["orders"]==r["orders"]==[["full_10k","full_1k"],["full_1k","full_10k"]]
            @test all(p->p["warmup"]["accepted"] && length(p["trials"])==2 && all(t->t["accepted"],p["trials"]),saved["profiles"])
            @test saved["ranking"]["objective_comparable"]
        end
        @test_throws ArgumentError U.P.benchmark(net,joinpath(dir,"bad");checkpoint=:bad)
        # Fail a candidate deliberately, retaining every failed row and denying ranking.
        bad=merge(ps[2],(;options=IVRNLPOptions(;(k=>(k==:s_base ? -1. : deepcopy(getfield(ps[2].options,k))) for k in fieldnames(IVRNLPOptions))...)))
        r=U.P.benchmark(net,joinpath(dir,"errors.json");repetitions=2,candidates=[ps[1],bad],trial_orders=orders,checkpoint=:sweep)
        saved=JSON3.read(read(joinpath(dir,"errors.json"),String),Dict{String,Any})
        @test !saved["profiles"][2]["warmup"]["accepted"]
        @test length(saved["profiles"][2]["trials"])==2 && all(t->!t["accepted"] && haskey(t,"error"),saved["profiles"][2]["trials"])
        @test length(saved["ranking"]["eligible"])==1
    end
end

end
