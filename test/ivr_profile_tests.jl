using Test, FormulationLab, JuMP, Ipopt
isdefined(@__MODULE__,:_sdp_tx_case) || include("sdp_transformer_fixtures.jl")

# A single-phase 11 kV/230 V transformer case: the global per-unit base leaves
# LV quantities far from unity, which is what the per-zone coordinates fix.
function _profile_case(ratio=11000/415)
    net=_sdp_tx_case("single_phase");tx=net["transformer"]["single_phase"]["tx"]
    net["voltage_source"]["s"]["v_magnitude"]=[230ratio,0.]
    tx["v_nom_from"]=230ratio;tx["v_nom_to"]=230.
    tx["r_series_from"]=.01ratio^2;tx["x_series_from"]=.005ratio^2
    tx["r_series_to"]=.01;tx["x_series_to"]=.005
    net["load"]=Dict("d"=>Dict("bus"=>"t","terminal_map"=>["p","n"],"configuration"=>"SINGLE_PHASE",
        "model"=>"constant_power","p_nom"=>[1000.],"q_nom"=>[200.]),
        "z"=>Dict("bus"=>"t","terminal_map"=>["p","n"],"configuration"=>"SINGLE_PHASE",
        "model"=>"constant_power","p_nom"=>[0.],"q_nom"=>[0.]))
    net["generator"]=Dict("g"=>Dict("bus"=>"t","terminal_map"=>["p","n"],"configuration"=>"SINGLE_PHASE",
        "p_min"=>[0.],"p_max"=>[300.],"q_min"=>[0.],"q_max"=>[0.],"s_max"=>[250.],"cost"=>[0.]))
    net
end

@testset "Named exact-IVR profiles" begin
    same(a,b)=all(isequal(getfield(a,k),getfield(b,k)) for k in fieldnames(IVRNLPOptions))
    @test same(IVRNLP().options,IVRNLPOptions())
    @test same(IVRNLP(profile=:reference).options,IVRNLPOptions())
    fast=IVRNLP(profile=:fast).options
    for (k,v) in pairs(IVR_PROFILES[:fast]);@test getfield(fast,k)==v;end
    # Explicit keywords override the profile; unrelated defaults are kept.
    o=IVRNLP(profile=:fast,lifting=:off,objective=:source_import).options
    @test o.lifting==:off && o.objective==:source_import && o.transformer_scaling==:nominal
    @test_throws ArgumentError IVRNLP(profile=:fastest)
    s=ivr_ipopt_options(max_iter=50)
    @test s.mumps_pivtol==1e-3 && s.max_iter==50

    net=_profile_case()
    results=Dict{Symbol,Any}()
    for profile in (:reference,:scaled,:fast)
        b=build_opf(net,IVRNLP(;profile,objective=:source_import);optimizer=Ipopt.Optimizer)
        profile==:reference || @test b.numerical_diagnostics[:transformer_scaling_report].status==:applied
        r=solve_ivr_nlp_opf(b;solver_options=ivr_ipopt_options(tol=1e-10))
        @test r.solve.optimal
        @test physical_residuals(net,r).passed
        results[profile]=r
    end
    for profile in (:scaled,:fast)
        @test results[profile].objective≈results[:reference].objective rtol=1e-6
        p=ACPoint(voltage=results[profile].voltage_candidate,currents=results[profile].current_candidate)
        @test ivr_nlp_point_report(build_opf(net,IVRNLP(objective=:source_import)),p).passed
    end
end
