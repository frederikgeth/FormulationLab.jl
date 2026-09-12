@testset "SDP numerical profiles preserve physical objectives" begin
    @test SDPOptions().state_scaling==:voltage_region
    @test SDPOptions(profile=:reference).state_scaling==:global
    @test SOCOptions().electrical.state_scaling==:global
    @test IVRSOC().options.electrical.state_scaling==:global
    @test SDPOptions(clique_merge=:cost).clique_size==12
    @test SDPOptions(clique_merge=:cost).clique_overlap_weight==1.0
    net=_l3f_case()
    for objective in (:cost,:source_import), sb in (1e4,1e6)
        reference=_sdp_test_solve(net;options=SDPOptions(profile=:reference,s_base=sb,objective=objective),solver_options=(verbose=false,))
        improved=_sdp_test_solve(net;options=SDPOptions(s_base=sb,objective=objective),solver_options=(verbose=false,))
        @test reference.solve.optimal && improved.solve.optimal
        @test improved.objective ≈ reference.objective rtol=3e-6
        @test improved.voltage_candidate[("load","a")] ≈ reference.voltage_candidate[("load","a")] rtol=2e-5
        @test solve_diagnostics(improved).numerical[:voltage_rank_ratio] < 1e-6
    end
    for options in (SDPOptions(profile=:bad),SDPOptions(basis=:bad),SDPOptions(cone=:bad),SDPOptions(shunt_coordinates=:bad),SDPOptions(decomposition=:bad),SDPOptions(recovery=:bad),SDPOptions(clique_size=0),SDPOptions(clique_merge=:bad),SDPOptions(state_scaling=:bad),SDPOptions(clique_overlap_weight=-1.),SDPOptions(clique_overlap_weight=Inf))
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
    for consistency in (:local,:shared), scaling in (:global,:voltage_region)
        cost=_sdp_test_solve(net;options=SDPOptions(;s_base=1000.,objective=:source_import,
            decomposition=:chordal,clique_size=4,clique_merge=:cost,state_scaling=scaling,consistency),
            solver_options=(verbose=false,))
        @test cost.solve.optimal
        @test cost.objective ≈ dense.objective rtol=2e-6
        @test cost.voltage_candidate[("b8","a")] ≈ dense.voltage_candidate[("b8","a")] atol=2e-3
        @test solve_diagnostics(cost).numerical[:separator_real_dimension]>=0
    end
end

@testset "Voltage-region congruence preserves mixed-voltage transformer physics" begin
    net=_sdp_tx_case("single_phase")
    net["transformer"]["single_phase"]["tx"]["v_nom_from"]=23000.
    net["voltage_source"]["s"]["v_magnitude"][1]=23000.
    _sdp_zload!(net,"z",["p","n"],0.1-0.02im)
    original=deepcopy(net)
    for basis in (:sparse,:physical_sparse,:orthonormal), cone in (:real,:hermitian)
        r=_sdp_test_solve(net;options=SDPOptions(;state_scaling=:voltage_region,basis,cone,
            objective=:source_import),solver_options=(verbose=false,))
        @test r.solve.optimal
        @test r.voltage_candidate[("t","p")] ≈ 115. atol=1e-3
        @test r.objective ≈ 0.1*115^2 rtol=1e-6
        @test r.numerical_diagnostics[:state_scaling].minimum<0.01
        @test !r.numerical_diagnostics[:scaling_basis_fallback]
    end
    @test net==original
end

@testset "Region scaling leaves a uniform-voltage neutral network unchanged" begin
    net=_l3f_case(explicit_neutral=true)
    net["bus"]["load"]["perfectly_grounded_terminals"]=String[]
    a=build_sdp_opf(net,nothing;options=SDPOptions(state_scaling=:global))
    b=build_sdp_opf(net,nothing;options=SDPOptions(state_scaling=:voltage_region))
    @test b.numerical_diagnostics[:state_scaling].minimum==1.0
    @test b.numerical_diagnostics[:state_scaling].maximum==1.0
    @test a.nullspace==b.nullspace
    @test num_variables(a.model)==num_variables(b.model)
    # A changed numerical rank must not silently change the electrical space.
    A=ComplexF64[1 0 0;0 1e-18 0];diagnostics=Dict{Symbol,Any}()
    N=FormulationLab._sdp_scaled_basis(A,:orthonormal,[1.,1e18,1.];diagnostics)
    @test diagnostics[:scaling_basis_fallback]
    @test N==FormulationLab._sdp_basis(A,:orthonormal)
    # An open tie must not pool the voltage bases of separate source regions.
    regions=Dict("bus"=>Dict("hi"=>Dict(),"lo"=>Dict()),
        "voltage_source"=>Dict("a"=>Dict("bus"=>"hi","v_magnitude"=>[230.]),
            "b"=>Dict("bus"=>"lo","v_magnitude"=>[115.])),
        "switch"=>Dict("tie"=>Dict("bus_from"=>"hi","bus_to"=>"lo","open_switch"=>true)))
    scales,info=FormulationLab._sdp_state_scales(regions,Dict(("hi","a")=>1,("lo","a")=>2),[],[],2,230.,:voltage_region)
    @test scales==[1.,0.5]
    @test info.regions==2
end

@testset "Cost amalgamation preserves a running-intersection cover" begin
    bags=[[1,2,3],[2,3,4],[3,4,5],[4,5,6]];parents=[0,1,2,3]
    N=ComplexF64[1 0 0;0 1 0;0 0 1;1 1 0;0 1 1;1 0 1]
    for limit in (2,3,4), weight in (0.,8.,100.)
        merged,ps=FormulationLab._sdp_merge_cliques(bags,parents,limit;N,weight)
        @test all(any(issubset(b,c) for c in merged) for b in bags)
        for i in 2:length(merged)
            @test 1<=ps[i]<i
            @test issubset(intersect(merged[i],reduce(union,merged[1:i-1])),merged[ps[i]])
        end
    end
end
