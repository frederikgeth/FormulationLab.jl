module IVRNWindingExcitationTests
using Test,FormulationLab,JuMP,Ipopt,JSON3
include("ivr_nwinding_limit_fixtures.jl")
const SETTINGS=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.,max_iter=500)
@testset "Explicit multiwinding excitation and identifiable SI recovery" begin
    for (connection,roll) in ((:YYY,1),(:YDY,1),(:YDY,-1),(:DYY,1),(:DYY,-1)),
        reverse in (false,true),sb in (1e3,1e5),winding in 1:3
        net=_nwinding_excitation_case(;connection,roll,reverse,winding);original=deepcopy(net)
        full=build_opf(net,IVRNLP(;s_base=sb,objective_scale=1.,transformer_nameplate=:bmopftools))
        anchor=nothing;objective=nothing
        for lifting in (:off,:powers,:bounded_observations)
            opts=IVRNLPOptions(;s_base=sb,objective_scale=1.,transformer_nameplate=:bmopftools,
                lifting,lifted_power_base=500.,observation_sharing=:signed,
                specialization=:conductor_regions,linear_elimination=:passive_blocks,
                device_elimination=:transformer_currents,transformer_scaling=:nominal,row_scaling=:composed)
            b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
            r=solve_ivr_nlp_opf(b;solver_options=SETTINGS)
            @test r.solve.optimal && physical_residuals(net,r).passed
            d=result_dict(b,r);point=_nwinding_connection_point(net,d)
            @test physical_residuals(net,point;delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed
            @test ivr_nlp_point_report(full,point).passed && ivr_nlp_point_report(b,point).passed
            if anchor===nothing;anchor=point;objective=r.objective;end
            @test ivr_nlp_point_report(b,anchor).passed
            @test isapprox(objective,r.objective;atol=1e-8,rtol=1e-7)
            @test maximum(x["s"] for x in values(d["transformer"]["tx"]["w2"]))≈100. atol=1e-5
            # Omitting the physical branch must fail, even though bare winding
            # currents and the coil power limits still look plausible.
            omitted=deepcopy(net);delete!(omitted["transformer"]["n_winding"]["tx"],"no_load_shunt")
            bare=_nwinding_connection_point(omitted,d)
            @test !physical_residuals(net,bare;delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed
            @test !ivr_nlp_point_report(full,bare).passed
            tight=deepcopy(net);tight["transformer"]["n_winding"]["tx"]["windings"][2]["s_max"]=270.
            @test !physical_residuals(tight,r).passed
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(opts)),point).passed
            for (key,v) in r.current_candidate
                key[1]==:voltage_source && continue
                @test point.currents[key]≈v atol=1e-8
            end
            io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
            @test net==original
        end
    end
end
end
