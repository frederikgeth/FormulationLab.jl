using Test, FormulationLab, Clarabel, JuMP, LinearAlgebra

function no_psd(model)
    all(!occursin("PositiveSemidefinite",string(S)) && !occursin("HermitianPositive",string(S)) for (_,S) in JuMP.list_of_constraint_types(model))
end

@testset "Complex SOC minors and separating cuts" begin
    model=Model(Clarabel.Optimizer);set_silent(model)
    model.ext[:soc_policy]=(blocks=Any[],)
    H=FormulationLab._sdp_psd(model,3,:real)
    # Pairwise minors cannot detect this negative eigenvalue.
    target=ComplexF64[1 -.75 -.75;-.75 1 -.75;-.75 -.75 1]
    phases=Diagonal(cis.([0.2,1.1,-0.7]));target=phases*target*phases'
    for i in 1:3,j in 1:i
        @constraint(model,real(H[i,j])==real(target[i,j]))
        i==j || @constraint(model,imag(H[i,j])==imag(target[i,j]))
    end
    optimize!(model)
    @test termination_status(model)==MOI.OPTIMAL
    @test no_psd(model)
    e=eigen(Hermitian(target));u=e.vectors[:,1]
    FormulationLab._soc_eigencut!(model,H,u)
    optimize!(model)
    @test termination_status(model)==MOI.INFEASIBLE
    @test no_psd(model)
    for z in ([1+im,2-im,3+2im],[0im,1im,1+0im])
        @test real(u'*(z*z')*u)>=-1e-12
    end
end

@testset "SOC shared component builder and result semantics" begin
    net=_l3f_case()
    for physical in (false,true)
        b=build_opf(net,IVRSOC(objective=:source_import,physical_projections=physical))
        @test no_psd(b.model)
        @test_throws ArgumentError solve_sdp_opf(b.electrical)
        r=solve_soc_opf(b;separation=PSDSeparationOptions(max_rounds=5),solver_options=(verbose=false,))
        @test r.solve.optimal
        s=solve_sdp_opf(net;options=SDPOptions(objective=:source_import),solver_options=(verbose=false,))
        @test r.objective<=s.objective+0.01
        @test r.objective ≈ s.objective atol=0.02
        @test !solve_diagnostics(r).physical_feasibility_certified
        @test no_psd(b.model)
        @test all(diff([h.objective for h in r.history]).>=-1e-3)
    end
    b=build_opf(net,IVRSOC())
    u=VoltagePhasor("source","a");v=VoltagePhasor("load","a")
    spec=VoltageLNC("soc-domain",u,v,LNCBounds((230.,230.),(200.,250.),(-0.2,0.2));provenance="test operating domain")
    add_voltage_lnc!(b,spec)
    @test length(b.electrical.lnc_diagnostics)==1
    @test phasor_products(b,u,v).wu isa JuMP.AffExpr
    @test_throws ArgumentError solve_soc_opf(build_opf(net,IVRSOC());separation=PSDSeparationOptions(max_rounds=-1))
    bad=deepcopy(net);bad["bus"]["source"]["v_min"]=[1000.0]
    r=solve_opf(bad,IVRSOC();solver_options=(verbose=false,))
    @test !r.solve.publishable
    @test isnan(r.objective)
end

@testset "SOC covers every clique and retains exotic cones" begin
    for consistency in (:local,:shared)
        model=Model(Clarabel.Optimizer);set_silent(model)
        policy=(blocks=Any[],physical=true);model.ext[:soc_policy]=policy
        options=SDPOptions(decomposition=:chordal,consistency=consistency,clique_size=3)
        H,N=FormulationLab._sdp_sparse_moment(model,zeros(ComplexF64,0,6),[[1,2,3],[3,4,5],[5,6]],options,Dict{Symbol,Any}())
        @test length(policy.blocks)==3
        @test sort(size.(policy.blocks,1))==[2,3,3]
        @test no_psd(model)
        x=@variable(model,lower_bound=0.5,upper_bound=1.5)
        FormulationLab._sdp_power_envelope!(model,x,0.3,0.5,1.5)
        @test any(S<:MOI.PowerCone for (_,S) in list_of_constraint_types(model))
        optimize!(model)
        @test termination_status(model)==MOI.OPTIMAL
        @test no_psd(model)
    end
end

@testset "SOC delta load inherited equations" begin
    net=_l3f_case()
    for b in values(net["bus"])
        b["terminal_names"]=["a","b"]
        for f in ("v_min","v_max");haskey(b,f) && (b[f]=fill(only(b[f]),2));end
    end
    src=net["voltage_source"]["source"]
    src["terminal_map"]=["a","b"];src["v_magnitude"]=[230.,230.]
    src["v_angle"]=[0.,pi];src["cost"]=[1.,1.]
    line=net["line"]["line"];line["terminal_map_from"]=["a","b"];line["terminal_map_to"]=["a","b"]
    merge!(net["linecode"]["lc"],Dict("R_series_2_2"=>0.2,"X_series_2_2"=>0.1))
    load=net["load"]["load"];load["terminal_map"]=["a","b"];load["configuration"]="DELTA"
    r=solve_opf(net,IVRSOC(objective=:source_import);solver_options=(verbose=false,))
    @test r.solve.optimal
    @test r.relaxed_powers[(:load,"load")] ≈ [10_000+2_000im] rtol=1e-7
end

@testset "OA iterations and budgets" begin
    function toy()
        b=build_opf(_l3f_case(),IVRSOC())
        H=FormulationLab._sdp_psd(b.model,3,:real)
        for i in 1:3;@constraint(b.model,real(H[i,i])==1);end
        @objective(b.model,Min,real(H[1,2]+H[1,3]+H[2,3]))
        b
    end
    b=toy();r=solve_soc_opf(b;separation=PSDSeparationOptions(max_cuts=0),solver_options=(verbose=false,))
    @test r.stop_reason==:cut_limit
    @test r.cuts==0
    @test r.objective/b.electrical.objective_scale ≈ -3 atol=1e-5
    b=toy();set_time_limit_sec(b.model,120.)
    r=solve_soc_opf(b;separation=PSDSeparationOptions(max_rounds=5),solver_options=(verbose=false,))
    @test r.stop_reason==:psd_tolerance
    @test time_limit_sec(b.model)==120.
    @test r.cuts>=1
    @test length(r.history)>=2
    @test r.objective/b.electrical.objective_scale ≈ -1.5 atol=1e-5
    @test no_psd(b.model)
end

@testset "SOC fixed transformer and regulator fixtures" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta","single_phase_autotransformer","open_delta_regulator")
        net=_sdp_tx_case(kind;tap=1.03)
        tm=net["bus"]["t"]["terminal_names"]
        _sdp_zload!(net,"l",tm[1:2],0.1-0.03im)
        b=build_opf(net,IVRSOC(objective=:source_import))
        r=solve_soc_opf(b;solver_options=(verbose=false,))
        s=solve_opf(net,IVRSDP(objective=:source_import);solver_options=(verbose=false,))
        @test no_psd(b.model)
        @test r.solve.optimal
        @test r.objective ≈ s.objective atol=1e-3
    end
end
