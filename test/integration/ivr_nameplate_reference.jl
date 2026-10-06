# Optional live reference; BMOPFTools is not a runtime dependency.
using Test, FormulationLab, JuMP, Ipopt, JSON3, SHA
import BMOPFTools
include("../sdp_transformer_fixtures.jl")

rows=Any[]
@testset "BMOPFTools nameplate changes dispatch and exports the same cap" begin
    for rating in (100.,nothing),sb in (1e3,1e5)
        net=_sdp_tx_case("single_phase")
        tx=net["transformer"]["single_phase"]["tx"]
        rating===nothing || (tx["s_rating"]=rating)
        tx["tap_ratio"]=pop!(tx,"tap")
        net["load"]=Dict("d"=>Dict("bus"=>"t","terminal_map"=>["p","n"],"configuration"=>"SINGLE_PHASE","p_nom"=>[200.],"q_nom"=>[0.]))
        net["generator"]=Dict("g"=>Dict("bus"=>"t","terminal_map"=>["p","n"],"configuration"=>"SINGLE_PHASE",
            "p_min"=>[0.],"p_max"=>[300.],"q_min"=>[0.],"q_max"=>[0.],"s_max"=>[300.],"cost"=>[1.]))
        ref=BMOPFTools.solve_opf(net;optimizer=Ipopt.Optimizer,per_unit=true,s_base=sb,
            solver_options=("print_level"=>0,"tol"=>1e-10,"constr_viol_tol"=>1e-10,"bound_relax_factor"=>0.))
        @test ref["feasible"]
        for lifting in (:off,:powers,:bounded_observations)
            b=build_opf(net,IVRNLP(;s_base=sb,objective_scale=1.,transformer_nameplate=:bmopftools,
                lifting,device_elimination=:transformer_currents,transformer_scaling=:nominal);optimizer=Ipopt.Optimizer)
            r=solve_ivr_nlp_opf(b;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,bound_relax_factor=0.))
            @test r.solve.optimal && physical_residuals(net,r).passed
            d=result_dict(b,r)
            @test d["objective"]≈ref["objective"] atol=1e-7
            @test real(only(r.powers[(:generator,"g")]))≈(rating===nothing ? 0. : 100.) atol=1e-4
            for side in ("fr","to"),channel in keys(d["transformer"]["tx"][side])
                ours=d["transformer"]["tx"][side][channel];theirs=ref["transformer"]["tx"][side][channel]
                @test Set(keys(ours))==Set(keys(theirs))
                @test all(isapprox(ours[k],theirs[k];atol=2e-5,rtol=1e-6) for k in keys(ours))
            end
            io=IOBuffer();FormulationLab.write_result(d,io);seekstart(io)
            @test isequal(BMOPFTools.read_result(io),d)
            push!(rows,(;rating,s_base=sb,lifting,objective=r.objective,reference_objective=ref["objective"],passed=true))
        end
        tx["s_rating"]=0.
        @test_throws ArgumentError BMOPFTools.solve_opf(net;optimizer=Ipopt.Optimizer,per_unit=true,s_base=sb)
        @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP(transformer_nameplate=:bmopftools))
    end
end
if !isempty(ARGS)
    report=(;reference_revision=readchomp(`git -C $(dirname(dirname(pathof(BMOPFTools)))) rev-parse HEAD`),
        reference_source_sha256=bytes2hex(sha256(read(joinpath(dirname(dirname(pathof(BMOPFTools))),"ext/BMOPFOpfExt/transformer.jl")))),
        cases=rows,note="Per-unit live single-phase active-cap/absent-cap controls; supplied zero rejected by both. No whole-transformer-family parity claim.")
    open(io->JSON3.write(io,report),ARGS[1],"w")
end
