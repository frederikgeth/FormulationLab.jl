module IVRNWindingNonstarTests
using Test,FormulationLab,JuMP,Ipopt,LinearAlgebra
include("ivr_nwinding_limit_fixtures.jl")
const SETTINGS=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,
    bound_relax_factor=0.,max_iter=500,nlp_scaling_method="gradient-based")
@testset "Four-winding non-star pair certificate" begin
    net=_nwinding_nonstar_case();tx=net["transformer"]["n_winding"]["tx"]
    x=tx["x_sc"];X=[.04 .02 .015;.02 .07 .025;.015 .025 .10]
    @test isposdef(Symmetric(X))
    @test all(X[i,i]>sum(abs(X[i,j]) for j in 1:3 if j!=i) for i in 1:3)
    @test [x["1_2"]+x["3_4"],x["1_3"]+x["2_4"],x["1_4"]+x["2_3"]]≈[.16,.18,.17]
    @test length(unique([x["1_2"]+x["3_4"],x["1_3"]+x["2_4"],x["1_4"]+x["2_3"]]))==3
    @test all(isapprox(X[i,j],i==j ? x["1_$(i+1)"] :
        (x["1_$(i+1)"]+x["1_$(j+1)"]-x["$(min(i,j)+1)_$(max(i,j)+1)"])/2) for i in 1:3,j in 1:3)
end
@testset "Four-winding power cost, limits, excitation and SI recovery" begin
    for (connection,roll) in ((:YYYY,1),(:YDYY,1),(:YDYY,-1),(:YYYD,1),(:YYYD,-1),(:DYYY,1),(:DYYY,-1)),
        reverse in (false,true),bounded in (false,true),excitation in (false,true),sb in (1e3,1e5)
        net=_nwinding_nonstar_case(;connection,roll,reverse,bounded,excitation);original=deepcopy(net)
        full=build_opf(net,IVRNLP(;s_base=sb,objective_scale=1.,transformer_nameplate=:bmopftools))
        anchor=nothing;objective=nothing
        for lifting in (:off,:powers,:bounded_observations)
            opts=_nwinding_nonstar_options(sb,lifting)
            b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
            r=solve_ivr_nlp_opf(b;solver_options=SETTINGS)
            @test r.solve.optimal && physical_residuals(net,r).passed
            d=result_dict(b,r);point=_nwinding_connection_point(net,d)
            @test physical_residuals(net,point;delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed
            @test ivr_nlp_point_report(b,point).passed && ivr_nlp_point_report(full,point).passed
            if anchor===nothing;anchor=point;objective=r.objective;end
            @test ivr_nlp_point_report(b,anchor).passed
            @test isapprox(objective,r.objective;atol=1e-8,rtol=1e-7)
            eq=_nwinding_nonstar_equations(net,point)
            @test eq.ampere_turn_A<1e-7 && eq.leakage_V<1e-7 && eq.loss_identity_VA<1e-5
            for k in 1:4
                @test eq.coil_power[k]≈r.powers[(:transformer_coil,"n_winding/tx/$k")] atol=1e-7
                @test minimum(abs.(eq.coil_power[k]))>1. # all winding channels exercised
            end
            cost=sum((reverse ? -1 : 1)*real(only(r.powers[(:generator,id)]))/1000 for id in keys(net["generator"]))
            @test cost≈r.objective atol=1e-10
            @test bounded ? r.objective>.23 : abs(r.objective)<1e-7
            if bounded
                for (k,cap) in ((2,100.),(4,60.))
                    @test maximum(abs.(eq.coil_power[k]))≈cap atol=1e-5
                    tight=deepcopy(net);tight["transformer"]["n_winding"]["tx"]["windings"][k]["s_max"]*=.9
                    @test !physical_residuals(tight,r).passed
                    @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(opts)),point).passed
                end
            end
            changed=deepcopy(net);changed["transformer"]["n_winding"]["tx"]["x_sc"]["3_4"]-=.02
            @test !physical_residuals(changed,r).passed
            @test !ivr_nlp_point_report(build_opf(changed,IVRNLP(opts)),point).passed
            for (key,current) in r.current_candidate
                key[1]==:voltage_source && continue
                @test point.currents[key]≈current atol=1e-8
            end
            io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
            @test net==original
        end
    end
end
end
