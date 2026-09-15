using Test, FormulationLab, JuMP, Clarabel
include("lindist3flow_fixtures.jl")

@testset "L3F hard limits and fixed-dispatch overload reporting" begin
    @test L3FOptions().operating_mode == :opf
    @test L3FOptions(operating_mode=:power_flow).objective == :feasibility
    @test_throws ArgumentError L3FOptions(operating_mode=:unrated)
    for pu in (false,true)
        net=_l3f_case();net["linecode"]["lc"]["i_max"]=[20.0]
        snapshot=deepcopy(net)
        hard=solve_l3f_opf(net,Clarabel.Optimizer;options=L3FOptions(per_unit=pu),solver_options=("verbose"=>false,))
        @test hard.solve.termination_status == "INFEASIBLE"
        @test l3f_limit_report(hard)["status"] == "unavailable"
        @test isempty(l3f_limit_report(hard)["entries"])
        b=build_l3f_opf(net,Clarabel.Optimizer;options=L3FOptions(operating_mode=:power_flow,per_unit=pu))
        @test l3f_limit_report(b)["status"] == "unavailable"
        @test isempty(b.constraints[:line_current])
        set_silent(b.model);optimize!(b.model)
        @test termination_status(b.model)==MOI.OPTIMAL
        report=l3f_limit_report(b)
        @test report["status"]=="overloaded"
        @test report["overload_count"]==2
        # Independent lossless feeder equation and S/V ampacity estimate.
        v=sqrt(230.0^2-2*(.2*10_000+.1*2_000))
        row=only(filter(r->r["key"]==["line","to",1],report["entries"]))
        @test row["limit"]==20.0
        @test row["value"] ≈ hypot(10_000.,2_000.)/v rtol=1e-6
        @test row["loading_ratio"] ≈ row["value"]/20.0 rtol=1e-8
        @test net==snapshot
        @test_throws ArgumentError l3f_limit_report(b;rtol=-1)
    end
end

@testset "Power flow requires and preserves fixed P/Q" begin
    net=_l3f_case(generator=true)
    gen=net["generator"]["pv"]
    gen["p_min"]=[0.];gen["p_max"]=[15_000.]
    opts=L3FOptions(operating_mode=:power_flow)
    @test_throws ArgumentError build_l3f_opf(net,Clarabel.Optimizer;options=opts)
    @test_throws ArgumentError build_l3f_opf(net,Clarabel.Optimizer;options=opts,dispatch=Dict("unknown"=>Dict()))
    @test_throws ArgumentError build_l3f_opf(net,Clarabel.Optimizer;options=opts,dispatch=Dict("pv"=>Dict("pg"=>[NaN],"qg"=>[0.])))
    point=Dict("pv"=>Dict("pg"=>[3000.],"qg"=>[0.]))
    @test_throws ArgumentError build_l3f_opf(net,Clarabel.Optimizer;dispatch=point)
    for pu in (false,true)
        r=solve_l3f_opf(net,Clarabel.Optimizer;options=L3FOptions(operating_mode=:power_flow,per_unit=pu),dispatch=point,solver_options=("verbose"=>false,))
        @test r.generators["pv"]["pg"][1] ≈ 3000. atol=1e-3
        @test r.sources["source"]["pg"][1] ≈ 7000. atol=1e-3
        @test r.objective==0.0
        @test r.formulation["dispatch_policy"]=="fixed_pq"
        @test r.formulation["fixed_dispatch"]["pv"]["pg"]==[3000.]
        @test !r.formulation["branch_limits_enforced"]
    end
    outside=Dict("pv"=>Dict("pg"=>[20_000.],"qg"=>[0.]))
    bad=solve_l3f_opf(net,Clarabel.Optimizer;options=opts,dispatch=outside,solver_options=("verbose"=>false,))
    @test bad.solve.termination_status=="INFEASIBLE"
    @test l3f_limit_report(bad)["status"]=="unavailable"
    # Fixed capability bounds may supply the operating point without a map.
    fixed=_l3f_case(generator=true)
    r=solve_l3f_opf(fixed,Clarabel.Optimizer;options=opts,solver_options=("verbose"=>false,))
    @test r.generators["pv"]["pg"][1] ≈ 15_000. atol=1e-3
end

@testset "Center-tap nameplate monitoring and retained capability" begin
    for pu in (false,true)
        n=_l3f_case()
        empty!(n["line"])
        n["bus"]["load"]=Dict{String,Any}("terminal_names"=>["x1","x2"])
        n["load"]=Dict("a"=>Dict{String,Any}("bus"=>"load","terminal_map"=>["x1"],
            "configuration"=>"SINGLE_PHASE","model"=>"constant_power","p_nom"=>[6000.],"q_nom"=>[1000.]),
            "b"=>Dict{String,Any}("bus"=>"load","terminal_map"=>["x2"],
            "configuration"=>"SINGLE_PHASE","model"=>"constant_power","p_nom"=>[2000.],"q_nom"=>[250.]))
        n["transformer"]=Dict("center_tap"=>Dict("ct"=>Dict{String,Any}("bus_from"=>"source","bus_to"=>"load",
            "terminal_map_from"=>["a"],"terminal_map_to"=>["x1","x2"],"v_nom_from"=>230.,"v_nom_to"=>120.,"s_rating"=>5000.)))
        r=solve_l3f_opf(n,Clarabel.Optimizer;options=L3FOptions(operating_mode=:power_flow,per_unit=pu),solver_options=("verbose"=>false,))
        row=only(l3f_limit_report(r)["entries"])
        @test row["limit"] ≈ 5000.
        @test row["value"] ≈ hypot(8000.,1250.) rtol=1e-7
        @test row["overloaded"]
        @test n["transformer"]["center_tap"]["ct"]["s_rating"]==5000.
    end
    n=_l3f_case(generator=true);n["generator"]["pv"]["s_max"]=[10_000.]
    r=solve_l3f_opf(n,Clarabel.Optimizer;options=L3FOptions(operating_mode=:power_flow),solver_options=("verbose"=>false,))
    @test r.solve.termination_status=="INFEASIBLE" # 15 kW dispatch exceeds generator capability
    @test l3f_limit_report(r)["status"]=="unavailable"
end
