using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra, JSON3
isdefined(@__MODULE__,:_sdp_tx_case) || include("sdp_transformer_fixtures.jl")
isdefined(@__MODULE__,:_audit_transformer_state) || include("ac_validation_fixtures.jl")

# Deliberately independent of the compiler's winding plan and limit ledger.
function _nameplate_observation(net,p,kind)
    d=net["transformer"][kind]["tx"];side=kind=="delta_wye" ? "to" : "from"
    tm=d["terminal_map_$side"];v=[p.voltage[(d["bus_$side"],t)] for t in tm]
    if kind in ("delta_wye","wye_delta")
        ni=findfirst(==("n"),tm);ph=filter(!=(ni),collect(eachindex(tm)))
        u=v[ph].-(ni===nothing ? 0im : v[ni]);i=p.currents[(Symbol("transformer_",side),"$kind/tx")][ph]
        return u.*conj.(i),3,ph,side
    end
    u=kind=="open_delta_regulator" ? [v[1]-v[2],v[2]-v[3]] : [v[1]-v[2]]
    u.*conj.(p.currents[(:transformer_coil_from,"$kind/tx")]),1,collect(eachindex(u)),side
end

@testset "Explicit transformer nameplates reject original physical witnesses" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta","single_phase_autotransformer","open_delta_regulator"),
        reverse in (false,true),sb in (1e3,1e5),lifting in (:off,:powers,:bounded_observations)
        net,p=_audit_transformer_state(kind;reverse)
        kind in ("single_phase_autotransformer","open_delta_regulator") &&
            (p.currents[(:transformer_bond,"$kind/tx")]=ComplexF64[0])
        tx=net["transformer"][kind]["tx"]
        for side in ("from","to");tx["i_max_$side"]=max.(tx["i_max_$side"],1e-6);end
        s,divisor,channels,side=_nameplate_observation(net,p,kind)
        tx["s_rating"]=1.01divisor*maximum(abs,s)
        options=IVRNLPOptions(;s_base=sb,transformer_nameplate=:bmopftools,lifting,lifted_power_base=1e3,
            observation_sharing=:signed,specialization=:conductor_regions,linear_elimination=:passive_blocks,
            device_elimination=:transformer_currents,transformer_scaling=:nominal,row_scaling=:composed)
        b=build_opf(net,IVRNLP(options))
        @test ivr_nlp_point_report(b,p).passed
        @test physical_residuals(net,p;delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed
        record=only(b.numerical_diagnostics[:transformer_nameplate_report])
        @test record.limit_VA==tx["s_rating"]/divisor && record.channels==channels && string(record.side)==side
        tight=deepcopy(net);tight["transformer"][kind]["tx"]["s_rating"]=.9divisor*maximum(abs,s)
        @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(options)),p).passed
        audit=physical_residuals(tight,p;delta_dispatch=:coil,transformer_nameplate=:bmopftools)
        @test !audit.passed && any(x->endswith(x.label,"/s_rating") && x.residual>1.,audit.records)
        @test ivr_nlp_point_report(build_opf(tight,IVRNLP()),p).passed
        @test physical_residuals(tight,p;delta_dispatch=:coil).passed
    end
end

@testset "Nameplate active dispatch, lifting, recovery and SI exports" begin
    net=_sdp_tx_case("single_phase");tx=net["transformer"]["single_phase"]["tx"]
    tx["s_rating"]=100.
    net["load"]=Dict("d"=>Dict("bus"=>"t","terminal_map"=>["p","n"],"configuration"=>"SINGLE_PHASE","p_nom"=>[200.],"q_nom"=>[0.]))
    net["generator"]=Dict("g"=>Dict("bus"=>"t","terminal_map"=>["p","n"],"configuration"=>"SINGLE_PHASE",
        "p_min"=>[0.],"p_max"=>[300.],"q_min"=>[0.],"q_max"=>[0.],"s_max"=>[300.]))
    term=IVRPowerTerm(channels=[(:generator,"g",1)],linear=1.)
    for policy in (:ignore,:bmopftools),sb in (1e3,1e5),lifting in (:off,:powers,:bounded_observations),eliminate in (:off,:transformer_currents)
        b=build_opf(net,IVRNLP(;objective=:power,power_terms=[term],objective_scale=1.,s_base=sb,
            transformer_nameplate=policy,lifting,device_elimination=eliminate,transformer_scaling=:nominal,
            row_scaling=:composed,lifted_power_base=1e3);optimizer=Ipopt.Optimizer)
        r=solve_ivr_nlp_opf(b;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,bound_relax_factor=0.))
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test r.objective≈(policy==:bmopftools ? 100. : 0.) atol=1e-5
        d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
        @test isequal(read_result(io),d)
        @test d["_formulationlab"]["transformer_nameplate_policy"]==string(policy)
        rec=d["transformer"]["tx"]["fr"]["1"]
        if policy==:bmopftools
            @test rec["s"]≈100. atol=1e-5
            @test rec["s_max"]==100.
        else
            @test !haskey(rec,"s_max")
            @test !physical_residuals(net,r;transformer_nameplate=:bmopftools).passed
        end
    end
    for value in (0.,nothing)
        n=deepcopy(net)
        value===nothing ? delete!(n["transformer"]["single_phase"]["tx"],"s_rating") : (n["transformer"]["single_phase"]["tx"]["s_rating"]=value)
        if value===nothing
            @test isempty(build_opf(n,IVRNLP(transformer_nameplate=:bmopftools)).numerical_diagnostics[:transformer_nameplate_report])
        else
            @test_throws IVRNLPInapplicableError build_opf(n,IVRNLP(transformer_nameplate=:bmopftools))
            @test isempty(build_opf(n,IVRNLP()).numerical_diagnostics[:transformer_nameplate_report])
        end
    end
    @test_throws ArgumentError build_opf(net,IVRNLP(transformer_nameplate=:unknown))
    @test_throws ArgumentError physical_residuals(net,ACPoint(voltage=Dict{Tuple{String,String},ComplexF64}());transformer_nameplate=:unknown)
    nw,p=_audit_nwinding_state();nw["transformer"]["n_winding"]["tx"]["s_rating"]=1.
    @test ivr_nlp_point_report(build_opf(nw,IVRNLP(transformer_nameplate=:bmopftools)),p).passed
    @test physical_residuals(nw,p;delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed
end
