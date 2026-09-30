using Test, FormulationLab, Clarabel, LinearAlgebra, JuMP
include("lindist3flow_fixtures.jl")
include("../examples/linivr_cases.jl")

function _linivr_two_wire(;ground=nothing,generator=false)
    net=_l3f_case(;explicit_neutral=true,generator)
    bus=net["bus"]["load"]
    bus["perfectly_grounded_terminals"]=String[]
    delete!(bus,"v_min");delete!(bus,"v_max")
    bus["vpn_min"]=[180.0];bus["vpn_max"]=[250.0]
    if ground!==nothing
        net["shunt"]=Dict("earth"=>Dict("bus"=>"load","terminal_map"=>["n"],"G_1_1"=>1/ground))
    end
    if generator
        g=net["generator"]["pv"];g["terminal_map"]=["a","n"]
        g["p_min"]=[0.];g["p_max"]=[15_000.]
        g["q_min"]=[-5_000.];g["q_max"]=[5_000.]
    end
    net
end

_linivr_solve(net;kwargs...)=solve_opf(net,LinIVR(;kwargs...);
    solver_options=(verbose=false,tol_gap_abs=1e-10,tol_gap_rel=1e-9,tol_feas=1e-9))

@testset "LinIVR coupled four-wire, delta, shunts and mesh" begin
    for delta in (false,true),ground in (Inf,.2)
        net=linivr_case(segments=2,loading=.5;delta,ground)
        # Nonzero line charging makes passive reference currents nonzero.
        net["linecode"]["wire"]["B_from_1_1"]=1e-5
        net["linecode"]["wire"]["B_to_2_2"]=2e-5
        net["line"]["parallel"]=deepcopy(net["line"]["l1"])
        r=_linivr_solve(net)
        @test r.solve.optimal
        audit=physical_residuals(net,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate))
        @test isempty(audit.unassessed)
        @test audit.maxima[:current]<1e-6
        @test audit.maxima[:voltage]<1e-6
        @test maximum(abs, r.powers[(:load,"d2")]-complex.([2000.,750.,250.],[500.,187.5,62.5]))<1e-5
    end
    # Ideal two-winding transformation with non-unity tap, plus a passive load.
    net=Dict{String,Any}("bus"=>Dict("s"=>Dict("terminal_names"=>["a","n"],"perfectly_grounded_terminals"=>["n"]),
        "t"=>Dict("terminal_names"=>["a","n"],"perfectly_grounded_terminals"=>["n"])),
        "voltage_source"=>Dict("s"=>Dict("bus"=>"s","terminal_map"=>["a","n"],"v_magnitude"=>[230.,0.],"v_angle"=>[0.,0.])),
        "transformer"=>Dict("single_phase"=>Dict("tx"=>Dict("bus_from"=>"s","bus_to"=>"t",
            "terminal_map_from"=>["a","n"],"terminal_map_to"=>["a","n"],"v_nom_from"=>230.,"v_nom_to"=>115.,"tap"=>1.05))),
        "load"=>Dict("d"=>Dict("bus"=>"t","terminal_map"=>["a","n"],"configuration"=>"SINGLE_PHASE",
            "model"=>"constant_impedance","v_nom"=>[115.],"p_nom"=>[1000.],"q_nom"=>[200.])))
    r=_linivr_solve(net)
    @test r.solve.optimal
    @test r.voltage_candidate[("t","a")] ≈ 115/1.05 atol=1e-6
    @test physical_residuals(net,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
    @test _linivr_solve(net;objective=:losses).objective ≈ 0 atol=1e-7
end

@testset "LinIVR explicit-neutral analytical circuit" begin
    s=10_000+2_000im;i=conj(s)/230
    Z=[.2+.1im .02+.01im;.02+.01im .1+.05im]
    for ground in (nothing,0.2,5.0),sb in (1e3,1e5)
        net=_linivr_two_wire(;ground);original=deepcopy(net)
        # Independent two-conductor KVL/KCL solution. Neutral grounding splits
        # the return current; no Schur complement or formulation helper used.
        vn=ground===nothing ? (Z[2,2]-Z[2,1])*i : (Z[2,2]-Z[2,1])*i/(1+Z[2,2]/ground)
        jn=-i+(ground===nothing ? 0im : vn/ground)
        vp=230-Z[1,1]*i-Z[1,2]*jn
        r=_linivr_solve(net;s_base=sb,objective=:source_import)
        @test r.solve.optimal
        @test r.voltage_candidate[("load","n")] ≈ vn atol=1e-6
        @test r.voltage_candidate[("load","a")] ≈ vp atol=1e-6
        @test r.current_candidate[(:line_from,"line")] ≈ [i,jn] atol=1e-6
        @test r.powers[(:load,"load")] ≈ [s] atol=1e-5
        @test r.physical_powers[(:load,"load")] ≈ [(vp-vn)*conj(i)] atol=1e-5
        @test r.objective ≈ real(s) atol=1e-4
        @test r.numerical_diagnostics[:max_relative_device_power_mismatch] ≈ abs(vp-vn-230)/230 atol=1e-8
        @test net==original
        @test !solve_diagnostics(r).bound_certified
        # Exact network laws, but deliberately nonzero constant-power mismatch.
        audit=physical_residuals(net,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate))
        @test !audit.passed
        build=build_opf(net,LinIVR();optimizer=nothing)
        @test build.reference[build.electrical.voltage[("load","n")]] ≈ 0 atol=1e-12
        @test formulation_kind(LinIVR())==:approximation
    end
end

@testset "LinIVR dispatch, loss objective and neutral limits" begin
    net=_linivr_two_wire(generator=true)
    r=_linivr_solve(net;objective=:losses)
    @test r.solve.optimal
    @test r.powers[(:generator,"pv")] ≈ [10_000+2_000im] atol=0.02
    @test abs(r.voltage_candidate[("load","n")])<1e-4
    @test abs(r.objective)<1e-5
    @test r.numerical_diagnostics[:line_shunt_losses_W] ≈ r.objective atol=1e-8
    # A zero no-load neutral must still have a working norm limit.
    net=_linivr_two_wire();net["bus"]["load"]["vn_max"]=[0.5]
    @test !_linivr_solve(net).solve.optimal
    net=_linivr_two_wire();net["line"]["line"]["i_max"]=[100.,1.]
    @test !_linivr_solve(net).solve.optimal
    net=_linivr_two_wire()
    @test !_linivr_solve(net;voltage_radius=.001).solve.optimal
    @test _linivr_solve(net;voltage_radius=.1).solve.optimal
    # Dispatch cost acts on power variables, with the established cost units.
    net=_linivr_two_wire(generator=true);net["generator"]["pv"]["cost"]=[2.0]
    r=_linivr_solve(net;objective=:cost)
    @test r.solve.optimal
    @test real(only(r.powers[(:generator,"pv")])) ≈ 0 atol=.01
    @test r.objective ≈ 10 atol=1e-4
end

@testset "LinIVR passive reference and refusal boundaries" begin
    net=_linivr_two_wire()
    load=net["load"]["load"];load["model"]="constant_impedance";load["v_nom"]=[230.]
    zloop=.26+.13im;y=conj(10_000+2_000im)/230^2
    r=_linivr_solve(net)
    @test r.solve.optimal
    @test r.voltage_candidate[("load","a")]-r.voltage_candidate[("load","n")] ≈ 230/(1+zloop*y) atol=1e-6
    @test r.physical_powers[(:load,"load")] ≈ r.powers[(:load,"load")] atol=1e-5
    for model in ("constant_current","zip","exponential")
        net=_linivr_two_wire();net["load"]["load"]["model"]=model
        @test_throws LinIVRInapplicableError build_opf(net,LinIVR();optimizer=nothing)
    end
    net=_linivr_two_wire();net["bus"]["island"]=Dict("terminal_names"=>["a"])
    @test_throws LinIVRInapplicableError build_opf(net,LinIVR();optimizer=nothing)
    net=_linivr_two_wire();net["load"]["load"]["terminal_map"]=["n"]
    @test_throws LinIVRInapplicableError build_opf(net,LinIVR();optimizer=nothing)
    @test_throws ArgumentError build_opf(_linivr_two_wire(),LinIVR(s_base=0);optimizer=nothing)
end

@testset "LinIVR orientation and global angle invariance" begin
    net=_linivr_two_wire(ground=2.);r=_linivr_solve(net)
    line=net["line"]["line"];line["bus_from"],line["bus_to"]=line["bus_to"],line["bus_from"]
    rev=_linivr_solve(net)
    @test rev.voltage_candidate[("load","n")] ≈ r.voltage_candidate[("load","n")] atol=1e-6
    net["voltage_source"]["source"]["v_angle"] .+= .71
    rot=_linivr_solve(net)
    @test rot.voltage_candidate[("load","n")] ≈ cis(.71)*r.voltage_candidate[("load","n")] atol=1e-6
    @test rot.physical_powers[(:load,"load")] ≈ r.physical_powers[(:load,"load")] atol=1e-5
end
