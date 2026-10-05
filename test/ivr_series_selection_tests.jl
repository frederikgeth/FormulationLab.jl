using Test, FormulationLab, JuMP, Ipopt
isdefined(@__MODULE__,:_elim_series_case) || include("ivr_elimination_tests.jl")

function _selection_unbound!(net,b)
    for key in collect(keys(net["bus"][b]))
        key=="terminal_names" || delete!(net["bus"][b],key)
    end
    net
end

@testset "Series selection retains expanding bounds and accepts sparse sections" begin
    for m in (2,3,4),specialization in (:off,:conductor_difference,:conductor_regions),reverse in (false,true)
        net=_elim_series_case(m;reverse,permuted=true)
        a=build_opf(net,IVRNLP(;specialization);optimizer=Ipopt.Optimizer)
        r=_elim_solve(a);@test r.solve.optimal
        p=_elim_point(r)
        b=build_opf(net,IVRNLP(;specialization,linear_elimination=:passive,series_selection=:bound_support))
        report=b.numerical_diagnostics[:linear_elimination_report]
        @test isempty(report.series_buses)
        @test all(==("operating_bound_support_expansion"),values(report.retained_series_buses))
        @test all(x.after>x.before for rows in values(report.bound_support_rejections) for x in rows)
        @test num_variables(a.model)==num_variables(b.model)
        @test ivr_nlp_point_report(b,p).passed
        @test b.coordinates.projection==a.coordinates.projection
        @test b.coordinates.reconstruction==a.coordinates.reconstruction
        for bus in ("b1","b2");_selection_unbound!(net,bus);end
        sparse=build_opf(net,IVRNLP(;specialization,linear_elimination=:passive,series_selection=:bound_support);optimizer=Ipopt.Optimizer)
        sr=sparse.numerical_diagnostics[:linear_elimination_report]
        @test sr.series_buses==["b1"]
        @test isempty(sr.bound_support_rejections)
        @test sr.retained_series_buses["b2"]=="adjacent_elimination"
        @test num_variables(sparse.model)<num_variables(a.model)
        @test ivr_nlp_point_report(sparse,p).passed
        rs=_elim_solve(sparse);@test rs.solve.optimal
        @test physical_residuals(net,rs).passed
        full=build_opf(net,IVRNLP())
        @test ivr_nlp_point_report(full,_elim_point(rs)).passed
        bad=copy(p.voltage);bad[("b1","a")]+=1
        @test !ivr_nlp_point_report(sparse,ACPoint(voltage=bad,currents=p.currents)).passed
    end
end

@testset "Series selection sees voltage and apparent-power bound rows" begin
    for field in ("v_min","v_max","vpn_min","vpn_max","vpp_min","vpp_max","vn_max","vpos_min","vpos_max","vneg_max","vzero_max")
        net=_elim_series_case(4)
        for bus in ("b1","b2");_selection_unbound!(net,bus);end
        n=field in ("vn_max","vpos_min","vpos_max","vneg_max","vzero_max") ? 1 : 3
        net["bus"]["b1"][field]=fill(endswith(field,"min") ? 1. : 1000.,n)
        b=build_opf(net,IVRNLP(linear_elimination=:passive,series_selection=:bound_support))
        report=b.numerical_diagnostics[:linear_elimination_report]
        @test report.retained_series_buses["b1"]=="operating_bound_support_expansion"
        @test any(x->x.label=="bus/b1/$field",report.bound_support_rejections["b1"])
        @test "b2" in report.series_buses # A rejected bus does not protect its neighbours.
    end
    for specialization in (:off,:conductor_regions),endpoint in (:from,:to)
        net=_elim_series_case(4;reverse=endpoint==:from)
        for bus in ("b1","b2");_selection_unbound!(net,bus);end
        net["line"]["l1"]["s_max"]=fill(1e6,3)
        b=build_opf(net,IVRNLP(;specialization,linear_elimination=:passive,series_selection=:bound_support))
        report=b.numerical_diagnostics[:linear_elimination_report]
        @test report.retained_series_buses["b1"]=="operating_bound_support_expansion"
        @test any(x->occursin("/s_max/",x.label),report.bound_support_rejections["b1"])
    end
    net=_elim_series_case(4)
    for bus in ("b1","b2");_selection_unbound!(net,bus);end
    net["bus"]["b1"]["vpn_min"]=zeros(3) # No lower constraint is emitted.
    b=build_opf(net,IVRNLP(linear_elimination=:passive,series_selection=:bound_support))
    @test b.numerical_diagnostics[:linear_elimination_report].series_buses==["b1"]
end

@testset "Series selection preserves impedance substitution and updates" begin
    net=_elim_series_case(4)
    _elim_impedance!(net["load"]["d3"],"constant_impedance",230.)
    net["load"]["cp"]=deepcopy(ivr_compiler_case(conductors=4,segments=3)["load"]["d3"])
    net["bus"]["b0"]["perfectly_grounded_terminals"]=String[]
    source=net["voltage_source"]["source"]
    for key in ("terminal_map","v_magnitude","v_angle");pop!(source[key]);end
    net["shunt"]=Dict("ground"=>Dict("bus"=>"b0","terminal_map"=>["n"],"B_1_1"=>-1e10))
    net["generator"]=Dict("g"=>Dict("bus"=>"b3","terminal_map"=>["a","b","c","n"],"configuration"=>"WYE",
        "p_min"=>zeros(3),"p_max"=>zeros(3),"q_min"=>zeros(3),"q_max"=>zeros(3),"cost"=>ones(3)))
    b=build_opf(net,IVRNLP(linear_elimination=:passive,series_selection=:bound_support,ground_scaling=:voltage,specialization=:conductor_regions);optimizer=Ipopt.Optimizer)
    report=b.numerical_diagnostics[:linear_elimination_report]
    @test report.impedance_loads==["d3"]
    @test isempty(report.series_buses)
    @test length(b.numerical_diagnostics[:ground_scaling_report].scaled_terminals)==1
    vars=all_variables(b.model)
    update_ivr_loads!(b,Dict("cp"=>(p=[100.,200.,300.],q=[20.,30.,40.])))
    update_ivr_generators!(b,Dict("g"=>(p_min=[20.,30.,40.],p_max=[20.,30.,40.],cost=[.2,.3,.4])))
    r=_elim_solve(b);@test r.solve.optimal
    @test physical_residuals(b.network,r).passed
    @test all_variables(b.model)==vars
    @test ivr_nlp_point_report(build_opf(b.network,IVRNLP()),_elim_point(r)).passed
    for mode in (:off,:impedance_loads)
        a=build_opf(net,IVRNLP(linear_elimination=mode))
        c=build_opf(net,IVRNLP(linear_elimination=mode,series_selection=:bound_support))
        @test a.coordinates.projection==c.coordinates.projection
        @test a.coordinates.reconstruction==c.coordinates.reconstruction
    end
    @test_throws ArgumentError build_opf(net,IVRNLP(series_selection=:unknown))
end
