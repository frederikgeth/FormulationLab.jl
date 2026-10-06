module IVRNWindingLimitTests
using Test,FormulationLab,JuMP,Ipopt,LinearAlgebra,JSON3
include("ivr_nwinding_limit_fixtures.jl")
include("ac_validation_fixtures.jl")
const SETTINGS=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.)
@testset "Scalar multiwinding ratings: exact dispatch, recovery and exports" begin
    for phases in (1,3),reverse in (false,true),policy in (:ignore,:bmopftools),
        sb in (1e3,1e5),lifting in (:off,:powers,:bounded_observations)
        net,demand=_nwinding_limit_case(;phases,reverse,rating=100phases)
        original=deepcopy(net);cap=policy==:bmopftools ? 100. : 100phases
        expected=max.(0.,demand.-cap);sign=reverse ? -1. : 1.
        options=IVRNLPOptions(;s_base=sb,objective=:power,objective_scale=1.,
            power_terms=[IVRPowerTerm(channels=[(:generator,"g",k)],linear=sign) for k in 1:phases],
            transformer_nameplate=policy,lifting,lifted_power_base=500.,observation_sharing=:signed,
            specialization=:conductor_regions,linear_elimination=:passive_blocks,
            device_elimination=:transformer_currents,transformer_scaling=:nominal,row_scaling=:composed)
        b=build_opf(net,IVRNLP(options);optimizer=Ipopt.Optimizer)
        r=solve_ivr_nlp_opf(b;solver_options=SETTINGS)
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test r.objective≈sum(expected) atol=1e-5
        @test real.(r.powers[(:generator,"g")])≈sign*expected atol=1e-5
        point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        @test ivr_nlp_point_report(b,point).passed
        record=only(b.numerical_diagnostics[:nwinding_power_limit_report])
        @test record.coil_count==phases && record.limits_VA==fill(cap,phases)
        @test record.interpretation==(policy==:bmopftools ? :winding_total_equal_shares : :per_coil)
        equivalent=deepcopy(net);equivalent["transformer"]["n_winding"]["tx"]["windings"][2]["s_max"]=fill(cap,phases)
        @test ivr_nlp_point_report(build_opf(equivalent,IVRNLP(;transformer_nameplate=policy)),point).passed
        @test physical_residuals(equivalent,point;delta_dispatch=:coil,transformer_nameplate=policy).passed
        d=result_dict(b,r)
        for k in 1:phases
            rec=d["transformer"]["tx"]["w2"][string(k)]
            @test rec["s_max"]==cap
            @test rec["s"]≈min(demand[k],cap) atol=1e-5
        end
        @test d["_formulationlab"]["nwinding_power_limit_report"][1]["limits_VA"]==fill(cap,phases)
        io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
        tight=deepcopy(net);tight["transformer"]["n_winding"]["tx"]["windings"][2]["s_max"]=50.
        @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(;transformer_nameplate=policy)),point).passed
        @test !physical_residuals(tight,r).passed
        @test net==original
    end
end
@testset "Non-star mixed-winding point independently rejects per-coil excess" begin
    for policy in (:ignore,:bmopftools),sb in (1e3,1e5),lifting in (:off,:powers,:bounded_observations)
        net,p=_audit_nwinding_state()
        ws=net["transformer"]["n_winding"]["tx"]["windings"]
        # Independent SI coil powers from the manufactured point, including delta.
        for (k,w) in enumerate(ws)
            v=[p.voltage[(w["bus"],t)] for t in w["terminal_map"]]
            u=k==3 ? v.-v[[2,3,1]] : v[1:3].-v[4]
            power=abs.(u.*conj.(p.currents[(:transformer_coil,"n_winding/tx/$k")]))
            w["s_max"]=(policy==:bmopftools ? 3 : 1)*1.01maximum(power)
        end
        opts=IVRNLPOptions(;s_base=sb,transformer_nameplate=policy,lifting,transformer_scaling=:nominal,row_scaling=:composed)
        @test ivr_nlp_point_report(build_opf(net,IVRNLP(opts)),p).passed
        @test physical_residuals(net,p;delta_dispatch=:coil,transformer_nameplate=policy).passed
        for k in 1:4
            tight=deepcopy(net);tight["transformer"]["n_winding"]["tx"]["windings"][k]["s_max"]*=.9
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(opts)),p).passed
            @test !physical_residuals(tight,p;delta_dispatch=:coil,transformer_nameplate=policy).passed
        end
    end
end
@testset "Explicit vectors, zero and absent winding ratings" begin
    for policy in (:ignore,:bmopftools)
        net,p=_audit_nwinding_state();w=net["transformer"]["n_winding"]["tx"]["windings"][3]
        v=[p.voltage[(w["bus"],t)] for t in w["terminal_map"]]
        power=abs.((v.-v[[2,3,1]]).*conj.(p.currents[(:transformer_coil,"n_winding/tx/3")]))
        w["s_max"]=1.01power
        b=build_opf(net,IVRNLP(;transformer_nameplate=policy))
        @test ivr_nlp_point_report(b,p).passed
        @test only(b.numerical_diagnostics[:nwinding_power_limit_report]).limits_VA==1.01power
        @test only(b.numerical_diagnostics[:nwinding_power_limit_report]).interpretation==:per_coil
        for k in 1:3
            tight=deepcopy(net);tight["transformer"]["n_winding"]["tx"]["windings"][3]["s_max"][k]=.9power[k]
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(;transformer_nameplate=policy)),p).passed
            @test !physical_residuals(tight,p;delta_dispatch=:coil,transformer_nameplate=policy).passed
        end
        for rating in (0.,nothing)
            empty_net,_=_nwinding_limit_case(;rating)
            empty!(empty_net["load"]);empty!(empty_net["generator"])
            voltage=Dict(("b$k",t)=>(t=="n" ? 0im : 230.0/2.0^(k-1)*cis([0.,-2pi/3,2pi/3][i]))
                for k in 1:3 for (i,t) in enumerate(["a","b","c","n"]))
            currents=Dict{Tuple{Symbol,String},Vector{ComplexF64}}((:voltage_source,"source")=>zeros(ComplexF64,4))
            for k in 1:3
                currents[(:transformer_coil,"n_winding/tx/$k")]=zeros(ComplexF64,3)
                currents[(:transformer_winding,"n_winding/tx/$k")]=zeros(ComplexF64,4)
            end
            zero_point=ACPoint(;voltage,currents)
            b=build_opf(empty_net,IVRNLP(;transformer_nameplate=policy))
            @test ivr_nlp_point_report(b,zero_point).passed
            @test physical_residuals(empty_net,zero_point;transformer_nameplate=policy).passed
            report=b.numerical_diagnostics[:nwinding_power_limit_report]
            @test rating===nothing ? isempty(report) : only(report).limits_VA==zeros(3)
        end
        for invalid in (-1.,Inf,NaN,[1.,2.])
            bad,_=_nwinding_limit_case(;rating=invalid)
            @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP(;transformer_nameplate=policy))
        end
    end
end
end
