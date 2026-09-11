using Test, FormulationLab, Clarabel, LinearAlgebra, JuMP
include("lindist3flow_fixtures.jl")

function _sdp_test_solve(input; solver_options=(), kwargs...)
    if isdefined(@__MODULE__, :SDP_TEST_OPTIMIZER)
        solve_sdp_opf(input, SDP_TEST_OPTIMIZER; solver_options=SDP_TEST_SOLVER_OPTIONS, kwargs...)
    else
        solve_sdp_opf(input; solver_options, kwargs...)
    end
end


@testset "Dense IVR SDP: analytical two-bus AC optimum" begin
    net=_l3f_case(); original=deepcopy(net)
    s=10_000+2_000im;z=0.2+0.1im;vs=230.0
    a=2real(z*conj(s))-vs^2
    w=(-a+sqrt(a^2-4abs2(z*s)))/2
    exact_v=conj((w+z*conj(s))/vs)
    exact_p=real(s)+real(z)*abs2(s)/w
    for sb in (1e4,1e6)
        result=_sdp_test_solve(net;options=SDPOptions(s_base=sb,objective=:source_import),
            solver_options=(verbose=false,tol_gap_abs=1e-8,tol_feas=1e-9))
        @test result.solve.optimal
        @test result.objective ≈ exact_p rtol=2e-6
        @test result.voltage_candidate[("load","a")] ≈ exact_v rtol=2e-5
        @test result.rank_ratio < 1e-6
        @test !solve_diagnostics(result).physical_feasibility_certified
        @test !solve_diagnostics(result).bound_certified
    end
    @test net==original
end

@testset "SDP retains explicit neutral current and voltage" begin
    net=_l3f_case(explicit_neutral=true)
    # The load neutral floats and carries the return current. Eliminating it
    # as an ideal ground would underestimate loop impedance and losses.
    net["bus"]["load"]["perfectly_grounded_terminals"]=String[]
    delete!(net["bus"]["load"],"v_min");delete!(net["bus"]["load"],"v_max")
    zloop=(0.2+0.1im)+(0.1+0.05im)-2(0.02+0.01im)
    s=10_000+2_000im;a=2real(zloop*conj(s))-230^2
    w=(-a+sqrt(a^2-4abs2(zloop*s)))/2
    expected=conj((w+zloop*conj(s))/230)
    r=_sdp_test_solve(net;options=SDPOptions(objective=:source_import),solver_options=(verbose=false,))
    @test r.solve.optimal
    @test r.voltage_candidate[("source","n")] == 0
    vl=r.voltage_candidate[("load","a")]-r.voltage_candidate[("load","n")]
    @test vl ≈ expected rtol=2e-5
    @test abs(r.voltage_candidate[("load","n")]) > 1.0
    @test r.objective ≈ real(s)+real(zloop)*abs2(s)/w rtol=2e-6
end

@testset "SDP rejects unsupported physics and enforces infeasibility" begin
    for (key,value) in ("transformer"=>Dict("single_phase"=>Dict("t"=>Dict())),
                        "dc_branch"=>Dict("b"=>Dict()),"time_series"=>Dict("t"=>Dict()))
        net=_l3f_case();net[key]=value
        @test_throws SDPInapplicableError build_sdp_opf(net)
    end
    net=_l3f_case();net["load"]["load"]["model"]="constant_current"
    @test_throws SDPInapplicableError build_sdp_opf(net)
    net=_l3f_case();net["bus"]["load"]["vpn_max"]=[240.0]
    @test build_sdp_opf(net) isa SDPBuild
    net=_l3f_case();net["line"]["line"]["i_max"]=[1.0]
    r=_sdp_test_solve(net;solver_options=(verbose=false,))
    @test !r.solve.optimal
    @test isnan(r.objective)
    @test_throws ArgumentError build_sdp_opf(_l3f_case();options=SDPOptions(s_base=0.0))
end

@testset "SDP constant impedance is a current law" begin
    net=_l3f_case();l=net["load"]["load"];l["model"]="constant_impedance";l["v_nom"]=[230.0]
    exact=230/(1+(0.2+0.1im)*conj(10_000+2_000im)/230^2)
    r=_sdp_test_solve(net;solver_options=(verbose=false,))
    @test r.solve.optimal
    @test r.voltage_candidate[("load","a")] ≈ exact rtol=2e-6
    @test r.rank_ratio < 1e-6
end

@testset "SDP delta connection, dispatch, and branch orientation" begin
    net=_l3f_case()
    for b in values(net["bus"])
        b["terminal_names"]=["a","b"]
        for f in ("v_min","v_max");haskey(b,f) && (b[f]=fill(only(b[f]),2));end
    end
    src=net["voltage_source"]["source"]
    src["terminal_map"]=["a","b"];src["v_magnitude"]=[230.0,230.0]
    src["v_angle"]=[0.0,pi];src["cost"]=[1.0,1.0]
    line=net["line"]["line"];line["terminal_map_from"]=["a","b"];line["terminal_map_to"]=["a","b"]
    merge!(net["linecode"]["lc"],Dict("R_series_2_2"=>0.2,"X_series_2_2"=>0.1))
    load=net["load"]["load"];load["terminal_map"]=["a","b"];load["configuration"]="DELTA"
    s=10_000+2_000im;z=0.4+0.2im;a=2real(z*conj(s))-460^2
    w=(-a+sqrt(a^2-4abs2(z*s)))/2
    r=_sdp_test_solve(net;options=SDPOptions(objective=:source_import),solver_options=(verbose=false,))
    @test r.solve.optimal
    @test r.objective ≈ real(s)+real(z)*abs2(s)/w rtol=2e-6
    @test r.relaxed_powers[(:load,"load")] ≈ [s] rtol=1e-7
    # Reversing the input orientation does not change the electrical problem.
    line["bus_from"],line["bus_to"]=line["bus_to"],line["bus_from"]
    reversed=_sdp_test_solve(net;options=SDPOptions(objective=:source_import),solver_options=(verbose=false,))
    @test reversed.objective ≈ r.objective rtol=2e-6
    @test reversed.relaxed_powers[(:line_to,"line")] ≈ r.relaxed_powers[(:line_from,"line")] rtol=2e-5

    gen=Dict{String,Any}("bus"=>"load","terminal_map"=>["a","b"],"configuration"=>"DELTA",
        "p_min"=>[0.0],"p_max"=>[5000.0],"q_min"=>[0.0],"q_max"=>[0.0],"s_max"=>[3000.0],"cost"=>[0.0])
    net["generator"]=Dict("pv"=>gen)
    generated=_sdp_test_solve(net;solver_options=(verbose=false,))
    @test generated.solve.optimal
    @test real(only(generated.relaxed_powers[(:generator,"pv")])) ≈ 3000.0 atol=0.02
end

@testset "SDP pi shunts and endpoint ratings retain physical locations" begin
    net=_l3f_case()
    load=net["load"]["load"];load["model"]="constant_impedance";load["v_nom"]=[230.0]
    yf=0.002+0.003im;yt=0.004-0.002im;yb=0.001+0.002im
    code=net["linecode"]["lc"]
    merge!(code,Dict("G_from_1_1"=>real(yf),"B_from_1_1"=>imag(yf),
                    "G_to_1_1"=>real(yt),"B_to_1_1"=>imag(yt),"i_max"=>[1.0]))
    net["line"]["line"]["i_max"]=[200.0] # explicit line override
    net["shunt"]=Dict("sh"=>Dict("bus"=>"load","terminal_map"=>["a"],"G_1_1"=>real(yb),"B_1_1"=>imag(yb)))
    z=0.2+0.1im;yl=conj(10_000+2_000im)/230^2
    vl=230/(1+z*(yl+yt+yb));iseries=(230-vl)/z
    r=_sdp_test_solve(net;solver_options=(verbose=false,))
    @test r.solve.optimal
    @test r.voltage_candidate[("load","a")] ≈ vl rtol=2e-6
    @test only(r.relaxed_powers[(:line_from,"line")]) ≈ 230conj(iseries+yf*230) rtol=2e-6
    @test only(r.relaxed_powers[(:line_to,"line")]) ≈ vl*conj(-iseries+yt*vl) rtol=2e-6
    delete!(net["line"]["line"],"i_max")
    @test !_sdp_test_solve(net;solver_options=(verbose=false,)).solve.optimal
    net["shunt"]["sh"]["G_bad_1_1"]=1.0
    @test_throws SDPInapplicableError build_sdp_opf(net)
end

@testset "SDP refuses unresolved impedance data" begin
    net=_l3f_case();delete!(net["line"]["line"],"linecode")
    @test_throws SDPInapplicableError build_sdp_opf(net)
    net["line"]["line"]["linecode"]="missing"
    @test_throws SDPInapplicableError build_sdp_opf(net)
end

include("sdp_transformer_tests.jl")

include("sdp_static_tests.jl")
