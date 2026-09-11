using Test, FormulationLab, Clarabel, JuMP, LinearAlgebra

function no_psd(model)
    all(!occursin("PositiveSemidefinite",string(S)) && !occursin("HermitianPositive",string(S)) for (_,S) in JuMP.list_of_constraint_types(model))
end

@testset "Complex SOC minors and fixed Kim constraints" begin
    model=Model(Clarabel.Optimizer);set_silent(model)
    model.ext[:soc_policy]=(blocks=Any[],)
    H=FormulationLab._sdp_psd(model,3,:real)
    # Pairwise minors cannot detect this negative eigenvalue.
    target=ComplexF64[1 -.75 -.75;-.75 1 -.75;-.75 -.75 1]
    phases=Diagonal(ones(3));target=phases*target*phases'
    for i in 1:3,j in 1:i
        @constraint(model,real(H[i,j])==real(target[i,j]))
        i==j || @constraint(model,imag(H[i,j])==imag(target[i,j]))
    end
    optimize!(model)
    @test termination_status(model)==MOI.OPTIMAL
    @test no_psd(model)
    e=eigen(Hermitian(target));u=e.vectors[:,1]
    FormulationLab._soc_kim!(model,H,1+0im)
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
        r=solve_soc_opf(b;solver_options=(verbose=false,))
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
    @test_throws ArgumentError build_opf(net,IVRSOC(max_triplets=-1))
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

@testset "Fixed profiles and budgets" begin
    for profile in (:none,:linear,:kim)
        b=build_opf(_l3f_case(),IVRSOC(strengthening=profile,max_triplets=0))
        before=JuMP.num_constraints(b.model;count_variable_in_set_constraints=true)
        r=solve_soc_opf(b;solver_options=(verbose=false,))
        @test r.solve.optimal
        @test r.stop_reason==:one_shot
        @test length(r.history)==1 && r.cuts==0
        @test JuMP.num_constraints(b.model;count_variable_in_set_constraints=true)==before
        @test isempty(b.electrical.numerical_diagnostics[:fixed_strengthening].triplets)
        @test !isempty(bound_report(b).entries)
        @test no_psd(b.model)
    end
    @test_throws ArgumentError build_opf(_l3f_case(),IVRSOC(strengthening=:iterative))
    # The chord bounds every rank-one constant-power state on its voltage domain.
    a,b,c=0.81,1.21,0.37
    for w in range(a,b;length=101)
        @test c/w <= c*(a+b-w)/(a*b)+1e-12
    end
    # Complex expansion of the projected Schur inequality, including i direction.
    z=ComplexF64[1+im,2-im,3+2im];G=z*z'
    for eta in (1+0im,1im,-1im),p in 1:3
        j,k=filter(!=(p),1:3)
        t=real(G[j,j]+abs2(eta)*G[k,k]+eta*G[j,k]+conj(eta)*G[k,j])
        @test abs2(G[p,j]+eta*G[p,k]) ≈ real(G[p,p])*t
    end
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

@testset "BMOPF bounds and physical propagation" begin
    # Three-phase line-line bounds follow AB, BC, CA, even when asymmetric.
    net=Dict("bus"=>Dict("b"=>Dict("terminal_names"=>["a","b","c"])))
    rows=(b,tm)->[Dict(findfirst(==(t),["a","b","c"])=>1.0+0im) for t in tm]
    maps=FormulationLab._sdp_voltage_maps(net,"b",rows)
    @test maps["vpp"]==[Dict(1=>1+0im,2=>-1+0im),Dict(2=>1+0im,3=>-1+0im),Dict(3=>1+0im,1=>-1+0im)]
    # Phase-only source P/Q arrays and line apparent ratings with explicit neutral.
    net=_l3f_case(;explicit_neutral=true)
    merge!(net["voltage_source"]["source"],Dict("p_min"=>[0.],"p_max"=>[20000.],"q_min"=>[-10000.],"q_max"=>[10000.]))
    net["linecode"]["lc"]["s_max"]=[20000.]
    b=build_opf(net,IVRSOC())
    @test solve_soc_opf(b;solver_options=(verbose=false,)).solve.optimal
    net["line"]["line"]["s_max"]=[1.]
    @test !solve_opf(net,IVRSOC();solver_options=(verbose=false,)).solve.optimal
    net=_l3f_case(;generator=true)
    for key in ("q_min","q_max");delete!(net["generator"]["pv"],key);end
    report=bound_report(build_opf(net,IVRSOC()))
    @test only(report.missing_capabilities).fields==["q_min","q_max","s_max","i_max"]
    @test any(e->isfinite(e.upper_pu) && occursin("derived",e.provenance),report.entries)
end

@testset "Three-wire dispatch rates conductor powers" begin
    v=230cis.([0.,-2pi/3,2pi/3]);i=ComplexF64[1+.2im,-.3+.1im,-.7-.3im];s=v.*conj.(i)
    for family in ("generator","ibr")
        d=Dict{String,Any}("bus"=>"b","terminal_map"=>["a","b","c"],"s_max"=>fill(1000.,3),
            "p_min"=>real.(s),"p_max"=>real.(s),"q_min"=>imag.(s),"q_max"=>imag.(s),"i_max"=>abs.(i).*(1+1e-6))
        family=="generator" ? (d["configuration"]="DELTA") : (d["topology"]="THREE_LEG")
        net=Dict{String,Any}("bus"=>Dict("b"=>Dict("terminal_names"=>["a","b","c"])),
            "voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>["a","b","c"],"v_magnitude"=>abs.(v),"v_angle"=>angle.(v))),family=>Dict("g"=>d))
        r=solve_opf(net,IVRSOC(objective=:source_import);solver_options=(verbose=false,))
        @test r.solve.optimal
        @test r.relaxed_powers[(Symbol(family),"g")] ≈ s atol=1e-3
        @test r.relaxed_powers[(:voltage_source,"s")] ≈ -s atol=1e-3
    end
end

@testset "Static Kim selection is budgeted and reproducible" begin
    net=_l3f_dy_case("delta_wye";line=true)
    a=build_opf(net,IVRSOC(strengthening=:kim,max_triplets=1))
    b=build_opf(deepcopy(net),IVRSOC(strengthening=:kim,max_triplets=1))
    da=a.electrical.numerical_diagnostics[:fixed_strengthening]
    db=b.electrical.numerical_diagnostics[:fixed_strengthening]
    @test length(da.triplets)==1
    @test da.triplets==db.triplets
    @test da.cones==9
    @test no_psd(a.model)
    @test !has_values(a.model)
end
