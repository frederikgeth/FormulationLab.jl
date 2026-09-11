@testset "SDP numerical profiles preserve physical objectives" begin
    net=_l3f_case()
    for objective in (:cost,:source_import), sb in (1e4,1e6)
        reference=_sdp_test_solve(net;options=SDPOptions(profile=:reference,s_base=sb,objective=objective),solver_options=(verbose=false,))
        improved=_sdp_test_solve(net;options=SDPOptions(s_base=sb,objective=objective),solver_options=(verbose=false,))
        @test reference.solve.optimal && improved.solve.optimal
        @test improved.objective ≈ reference.objective rtol=3e-6
        @test improved.voltage_candidate[("load","a")] ≈ reference.voltage_candidate[("load","a")] rtol=2e-5
        @test solve_diagnostics(improved).numerical[:voltage_rank_ratio] < 1e-6
    end
    for options in (SDPOptions(profile=:bad),SDPOptions(basis=:bad),SDPOptions(cone=:bad),SDPOptions(shunt_coordinates=:bad),SDPOptions(decomposition=:bad),SDPOptions(recovery=:bad),SDPOptions(clique_size=0))
        @test_throws ArgumentError build_sdp_opf(net;options)
    end
end

@testset "SDP finite shunt current coordinates retain admittance physics" begin
    net=_l3f_case();net["load"]["load"]["model"]="constant_impedance";net["load"]["load"]["v_nom"]=[230.0]
    net["shunt"]=Dict("sh"=>Dict("bus"=>"load","terminal_map"=>["a"],"G_1_1"=>0.002,"B_1_1"=>0.003))
    a=_sdp_test_solve(net;options=SDPOptions(shunt_coordinates=:admittance),solver_options=(verbose=false,))
    b=_sdp_test_solve(net;options=SDPOptions(shunt_coordinates=:current),solver_options=(verbose=false,))
    @test a.solve.optimal && b.solve.optimal
    @test a.objective ≈ b.objective rtol=1e-6
    @test a.voltage_candidate[("load","a")] ≈ b.voltage_candidate[("load","a")] rtol=1e-6
end

@testset "SDP current cuts use coil voltage domains" begin
    row=FormulationLab._SDPRow(1=>1,2=>-1);current=FormulationLab._SDPRow(3=>1)
    device=(:load,"delta",[row],[current],Dict("model"=>"constant_power","p_nom"=>[3000.0],"q_nom"=>[4000.0]))
    bounds=FormulationLab._sdp_current_bounds([device],[],r->(200.0,250.0))
    @test length(bounds)==1
    @test bounds[1][2] ≈ 25.0
    @test isempty(FormulationLab._sdp_current_bounds([device],[],r->(0.0,250.0)))
    # Exact feasible states throughout the declared magnitude range survive.
    for voltage in (200.0,220.0,250.0), angle in (-2.0,0.0,1.0)
        v=voltage*cis(angle);i=conj((3000+4000im)/v)
        @test abs(i)<=bounds[1][2]
    end
    @test FormulationLab._sdp_map_key(row)[1]==FormulationLab._sdp_map_key(FormulationLab._SDPRow(k=>-v for (k,v) in row))[1]
end

@testset "SDP affine preprocessing preserves contradictions and equalities" begin
    m=Model();@variable(m,x);@variable(m,y)
    @constraint(m,2x+4y<=6);@constraint(m,-x-2y>=-3)
    @constraint(m,x+2y>=3)
    removed=FormulationLab._sdp_preprocess_affine!(m)
    @test removed==2
    @test num_constraints(m,AffExpr,MOI.EqualTo{Float64})==1
    m=Model(FormulationLab.default_optimizer());set_silent(m);@variable(m,x)
    @constraint(m,x<=1);@constraint(m,2x>=4)
    FormulationLab._sdp_preprocess_affine!(m);optimize!(m)
    @test termination_status(m)==MOI.INFEASIBLE
    net=_l3f_case();net["bus"]["source"]["v_max"]=[100.0]
    @test !_sdp_test_solve(net;solver_options=(verbose=false,)).solve.optimal
end

@testset "Chordal completion agrees with the dense network relaxation" begin
    net=_l3f_case();bus=deepcopy(net["bus"]["load"])
    load=deepcopy(net["load"]["load"]);line=deepcopy(net["line"]["line"])
    net["bus"]=Dict("source"=>net["bus"]["source"]);net["load"]=Dict();net["line"]=Dict()
    for k in 1:8
        id="b$k";net["bus"][id]=deepcopy(bus)
        l=deepcopy(load);l["bus"]=id;l["p_nom"]=[100.];l["q_nom"]=[20.];net["load"][id]=l
        e=deepcopy(line);e["bus_from"]=k==1 ? "source" : "b$(k-1)";e["bus_to"]=id;net["line"][id]=e
    end
    original=deepcopy(net)
    dense=_sdp_test_solve(net;options=SDPOptions(s_base=1000.,objective=:source_import,decomposition=:dense),solver_options=(verbose=false,))
    sparse=_sdp_test_solve(net;options=SDPOptions(s_base=1000.,objective=:source_import,decomposition=:chordal,clique_size=8),solver_options=(verbose=false,))
    @test dense.solve.optimal && sparse.solve.optimal
    @test sparse.objective ≈ dense.objective rtol=1e-6
    @test sparse.voltage_candidate[("source","a")] ≈ 230.0 atol=1e-5
    @test sparse.voltage_candidate[("b8","a")] ≈ dense.voltage_candidate[("b8","a")] atol=1e-3
    @test solve_diagnostics(sparse).numerical[:decomposition]==:chordal
    @test maximum(solve_diagnostics(sparse).numerical[:clique_orders])<9
    @test net==original
end
