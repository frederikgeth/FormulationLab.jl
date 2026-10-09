module IVRExpressionSelectionTests
using Test,FormulationLab,JuMP,Ipopt
include("../examples/ivr_compiler_cases.jl")
include("../examples/ivr_declared_bound_inventory.jl")
const F=FormulationLab
const STRICT=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.)
function fixture(m)
    net=ivr_compiler_case(conductors=m,segments=3)
    for field in ("p_nom","q_nom");net["load"]["d3"][field] .*=3;end
    for b in ("b1","b2")
        delete!(net["load"],replace(b,"b"=>"d"))
        for k in collect(keys(net["bus"][b]));k=="terminal_names" || delete!(net["bus"][b],k);end
    end
    net
end
@testset "Line objectives participate in local expression selection" begin
    for m in (2,3,4),lifting in (:off,:powers,:bounded_observations)
        net=fixture(m)
        term=IVRPowerTerm(channels=[(:line_to,"l1",1)],target=-1000.,quadratic=1e-6)
        common=(;objective=:power,power_terms=[term],lifting,linear_elimination=:passive)
        full=build_opf(net,IVRNLP(;objective=:power,power_terms=[term],lifting))
        bound=build_opf(net,IVRNLP(;common...,series_selection=:bound_support))
        aware=build_opf(net,IVRNLP(;common...,series_selection=:expression_support))
        @test bound.numerical_diagnostics[:linear_elimination_report].series_buses==["b1"]
        r=aware.numerical_diagnostics[:linear_elimination_report]
        @test "b1" ∉ r.series_buses
        @test r.retained_series_buses["b1"]=="expression_support_expansion"
        @test any(x->startswith(x.label,"objective/"),r.bound_support_rejections["b1"])
        @test r.final_expression_support.checked && !r.final_expression_support.fallback
        @test isempty(F._ivrn_final_expression_expansions(net,aware.electrical,full.coordinates,aware.coordinates,[term]))
        @test !isempty(F._ivrn_final_expression_expansions(net,bound.electrical,full.coordinates,bound.coordinates,[term]))
        @test IVRDeclaredBoundInventory.catalog(aware).complete_declared_bound_coverage
    end
end
@testset "Expression selection: power objectives, reductions and physical recovery" begin
    for m in (2,3,4),kind in (:cost,:tracking),mode in (:passive,:passive_chains,:passive_blocks,:passive_hybrid)
        net=fixture(m)
        term=IVRPowerTerm(channels=[(:line_to,"l1",1),(:line_to,"l2",1)],weights=[1.,-.25],
            target=kind==:tracking ? -1000. : 0.,linear=kind==:cost ? .001 : 0.,
            quadratic=kind==:cost ? 2e-8 : 1e-6)
        common=(;objective=:power,power_terms=[term],lifting=:powers,specialization=:conductor_regions,
            row_scaling=:composed,device_elimination=:transformer_currents,zero_load_elimination=true)
        a=build_opf(net,IVRNLP(;common...);optimizer=Ipopt.Optimizer)
        b=build_opf(net,IVRNLP(;common...,linear_elimination=mode,series_selection=:expression_support);optimizer=Ipopt.Optimizer)
        @test isempty(F._ivrn_final_expression_expansions(net,b.electrical,a.coordinates,b.coordinates,[term]))
        @test IVRDeclaredBoundInventory.catalog(b).complete_declared_bound_coverage
        ra=solve_ivr_nlp_opf(a;solver_options=STRICT);rb=solve_ivr_nlp_opf(b;solver_options=STRICT)
        @test ra.solve.optimal && rb.solve.optimal
        @test ra.objective≈rb.objective atol=1e-5 rtol=1e-7
        @test physical_residuals(net,rb).passed
        for (build,result) in ((a,rb),(b,ra))
            @test ivr_nlp_point_report(build,ACPoint(voltage=result.voltage_candidate,currents=result.current_candidate)).passed
        end
        d=result_dict(b,rb);io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
    end
end
@testset "Boundary objective accepts sparse passive reductions" begin
    for m in (2,3,4)
        net=fixture(m);term=IVRPowerTerm(channels=[(:voltage_source,"source",1)],quadratic=1e-6)
        b=build_opf(net,IVRNLP(objective=:power,power_terms=[term],linear_elimination=:passive_chains,series_selection=:expression_support))
        r=b.numerical_diagnostics[:linear_elimination_report]
        @test r.series_buses==["b1","b2"]
        @test !r.final_expression_support.fallback
    end
end
@testset "Final-map guard falls back on an actual expanding candidate" begin
    net=fixture(4);term=IVRPowerTerm(channels=[(:line_to,"l1",1)],quadratic=1e-6)
    b=build_opf(net,IVRNLP(objective=:power,power_terms=[term],linear_elimination=:passive))
    e=b.electrical;initial=F._ivrn_coordinates(e,nothing)
    options=IVRNLPOptions(objective=:power,power_terms=[term],linear_elimination=:passive,series_selection=:expression_support)
    # Feed the guard a genuine exact but support-expanding Schur candidate.
    # This directly exercises its fallback independently of the local filter.
    finish(maps,equations)=(;maps,equations)
    result=F._ivrn_expression_selection_guard(net,e,initial,Set{Tuple{String,String}}(),
        (;maps=b.coordinates),Set{Tuple{String,String}}(),
        b.numerical_diagnostics[:linear_elimination_report],options,finish)
    @test result.elimination.final_expression_support.fallback
    @test !isempty(result.elimination.final_expression_support.expansions)
    @test isempty(result.elimination.series_buses) && isempty(result.omitted)
    @test result.final.maps.projection==initial.projection
    @test result.final.maps.reconstruction==initial.reconstruction
    @test result.elimination.retained_series_buses["b1"]=="final_expression_support_expansion"
end

include("sdp_transformer_fixtures.jl")
@testset "Final support after transformer units and zero-load substitution" begin
    net=_sdp_tx_case("single_phase")
    for bus in ("m","d");net["bus"][bus]=Dict{String,Any}("terminal_names"=>["p","n"]);end
    net["bus"]["d"]["vpn_min"]=[50.];net["bus"]["d"]["vpn_max"]=[130.]
    net["linecode"]=Dict("wire"=>Dict("R_series_1_1"=>.02,"R_series_2_2"=>.02,
        "X_series_1_1"=>.01,"X_series_2_2"=>.01,"i_max"=>[100.,100.]))
    net["line"]=Dict(id=>Dict("bus_from"=>a,"bus_to"=>b,
        "terminal_map_from"=>["p","n"],"terminal_map_to"=>["p","n"],"linecode"=>"wire")
        for (id,a,b) in (("l1","t","m"),("l2","m","d")))
    net["load"]=Dict(id=>Dict("bus"=>"d","terminal_map"=>["p","n"],"configuration"=>"SINGLE_PHASE",
        "p_nom"=>[p],"q_nom"=>[q]) for (id,p,q) in (("demand",200.,50.),("zero",0.,0.)))
    term=IVRPowerTerm(channels=[(:voltage_source,"s",1)],linear=.001,quadratic=1e-6)
    common=(;objective=:power,power_terms=[term],lifting=:powers,
        device_elimination=:transformer_currents,zero_load_elimination=true,
        transformer_scaling=:nominal,current_power_bases=Dict("f"=>1e5,"t"=>1e3),row_scaling=:composed)
    a=build_opf(net,IVRNLP(;common...);optimizer=Ipopt.Optimizer)
    b=build_opf(net,IVRNLP(;common...,linear_elimination=:passive_chains,series_selection=:expression_support);optimizer=Ipopt.Optimizer)
    @test b.numerical_diagnostics[:linear_elimination_report].series_buses==["m"]
    @test b.numerical_diagnostics[:device_elimination_report].transformers==["single_phase/tx"]
    @test b.numerical_diagnostics[:zero_load_elimination_report].eliminated_complex_coordinates>0
    @test isempty(F._ivrn_final_expression_expansions(net,b.electrical,a.coordinates,b.coordinates,[term]))
    @test IVRDeclaredBoundInventory.catalog(b).complete_declared_bound_coverage
    ra=solve_ivr_nlp_opf(a;solver_options=STRICT);rb=solve_ivr_nlp_opf(b;solver_options=STRICT)
    @test ra.solve.optimal && rb.solve.optimal
    @test ra.objective≈rb.objective atol=1e-6 rtol=1e-7
    @test physical_residuals(net,rb).passed
    for (build,result) in ((a,rb),(b,ra))
        @test ivr_nlp_point_report(build,ACPoint(voltage=result.voltage_candidate,currents=result.current_candidate)).passed
    end
    d=result_dict(b,rb);io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
end

end
