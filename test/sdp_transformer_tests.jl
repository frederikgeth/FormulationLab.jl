include("sdp_transformer_fixtures.jl")
_tx_solve(net;sb=1e4)=_sdp_test_solve(net;options=SDPOptions(s_base=sb,objective=:source_import),solver_options=(verbose=false,))

@testset "SDP fixed transformer leakage, shunts, taps and terminal limits" begin
    for tap in (0.95,1.0,1.05), sb in (1e4,1e5)
        net=_sdp_tx_case("single_phase";tap)
        tx=net["transformer"]["single_phase"]["tx"]
        zf=0.4+0.3im;zt=0.1+0.2im;y0=0.002-0.001im;yl=0.1-0.03im
        merge!(tx,Dict("r_series_from"=>real(zf),"x_series_from"=>imag(zf),
            "r_series_to"=>real(zt),"x_series_to"=>imag(zt),"no_load_shunt"=>Dict("winding"=>2,"g"=>real(y0),"b"=>imag(y0)),
            "s_rating"=>5000.0,"i_max_from"=>[100.0,100.0],"i_max_to"=>[100.0,100.0]))
        _sdp_zload!(net,"l",["p","n"],yl)
        original=deepcopy(net);n=2tap;z=zf*tap^2/n^2+zt
        v=230/n/(1+z*(yl+y0));i=(yl+y0)*v/n
        r=_tx_solve(net;sb)
        @test r.solve.optimal
        @test r.voltage_candidate[("t","p")] ≈ v rtol=3e-5
        @test r.objective ≈ real(230conj(i)) rtol=3e-6
        @test sum(r.relaxed_powers[(:transformer_from,"single_phase/tx")]) ≈ 230conj(i) rtol=3e-5
        @test net==original
    end
    net=_sdp_tx_case("single_phase");_sdp_zload!(net,"l",["p","n"],0.1)
    tx=net["transformer"]["single_phase"]["tx"]
    tx["i_max_to"]=[100.0,1.0] # the return terminal must also be rated
    @test !_tx_solve(net).solve.optimal
    delete!(tx,"i_max_to");tx["s_rating"]=100.0
    @test _tx_solve(net).solve.optimal # power base does not impose a thermal cap
end

@testset "SDP center tap retains shared primary and reversed secondary" begin
    for zf in (0im,0.3+0.2im),zt in (0im,0.1+0.05im)
        net=_sdp_tx_case("center_tap");tx=net["transformer"]["center_tap"]["tx"]
        merge!(tx,Dict("r_series_from"=>real(zf),"x_series_from"=>imag(zf),"r_series_to"=>real(zt),"x_series_to"=>imag(zt)))
        y1=0.2-0.06im;y2=0.05-0.01im
        _sdp_zload!(net,"l1",["x1","n"],y1);_sdp_zload!(net,"l2",["x2","n"],y2)
        q1=y1/(1+zt*y1);q2=y2/(1+zt*y2)
        e=240/(1+zf*(q1+q2)/4)
        v1=e/2/(1+zt*y1);v2=-e/2/(1+zt*y2)
        r=_tx_solve(net)
        @test r.solve.optimal
        @test r.voltage_candidate[("t","x1")] ≈ v1 rtol=3e-5
        @test r.voltage_candidate[("t","x2")] ≈ v2 rtol=3e-5
        @test r.objective ≈ real(240conj((y1*v1-y2*v2)/2)) rtol=3e-6
    end
end

@testset "SDP delta winding phase shifts and unbalanced leg powers" begin
    for kind in ("delta_wye","wye_delta"),tap in (0.97,1.03)
        net=_sdp_tx_case(kind;tap)
        vs=230cis.([0.0,-2pi/3,2pi/3]);a=2tap
        if kind=="delta_wye"
            expected=[vs[k]-vs[mod1(k-1,3)] for k in 1:3]/(sqrt(3)*a)
            for (k,t) in enumerate(["a","b","c"]);_sdp_zload!(net,t,[t,"n"],0.02k-0.005im);end
        else
            u=sqrt(3)/a*vs
            expected=ComplexF64[-u[3],u[2],0]
            for (k,(p,q)) in enumerate([("a","b"),("b","c"),("c","a")]);_sdp_zload!(net,p,[p,q],0.02k-0.005im);end
        end
        r=_tx_solve(net)
        @test r.solve.optimal
        @test [r.voltage_candidate[("t",t)] for t in ["a","b","c"]] ≈ expected rtol=5e-5
        @test sum(r.relaxed_powers[(:transformer_from,"$kind/tx")])+sum(r.relaxed_powers[(:transformer_to,"$kind/tx")]) ≈ 0 atol=1e-3
    end
end

@testset "SDP fixed regulators preserve galvanic return" begin
    for kind in ("single_phase_autotransformer","open_delta_regulator"),rt in ("A","B")
        net=_sdp_tx_case(kind;tap=1.04);tx=net["transformer"][kind]["tx"];tx["regulator_type"]=rt
        if kind=="single_phase_autotransformer"
            _sdp_zload!(net,"l",["p","n"],0.03-0.01im)
            ratio=rt=="A" ? 1.04 : 1/1.04
            expected=Dict("p"=>230/ratio,"n"=>0im)
        else
            vs=230cis.([0.0,-2pi/3,2pi/3]);ratios=rt=="A" ? [1.04,1/1.04] : [1/1.04,1.04]
            expected=Dict("a"=>vs[2]+(vs[1]-vs[2])/ratios[1],"b"=>vs[2],"c"=>vs[2]-(vs[2]-vs[3])/ratios[2])
            for (k,t) in enumerate(["a","b","c"]);_sdp_zload!(net,t,[t],0.01k);end
        end
        r=_tx_solve(net)
        @test r.solve.optimal
        for (t,v) in expected;@test r.voltage_candidate[("t",t)] ≈ v atol=0.002;end
        @test sum(r.relaxed_powers[(:transformer_from,"$kind/tx")])+sum(r.relaxed_powers[(:transformer_to,"$kind/tx")]) ≈ 0 atol=0.002
    end
end

@testset "SDP transformer refusal and fixed-setting contracts" begin
    for patch in (Dict("tap_min"=>0.9,"tap_max"=>1.1),Dict("tap"=>0.0),
        Dict("tap"=>1.2,"tap_min"=>0.9,"tap_max"=>1.1),Dict("tap_min"=>1.0),
        Dict("r_neutral_to"=>-1.0),Dict("v_nom_to"=>0.0),Dict("r_series_from"=>-1.0))
        net=_sdp_tx_case("single_phase");tx=net["transformer"]["single_phase"]["tx"]
        delete!(tx,"tap");merge!(tx,patch)
        @test_throws SDPInapplicableError build_sdp_opf(net,nothing)
    end
    net=_sdp_tx_case("single_phase");tx=net["transformer"]["single_phase"]["tx"]
    delete!(tx,"tap");tx["tap_min"]=tx["tap_max"]=1.02
    @test build_sdp_opf(net,nothing) isa SDPBuild
    tx["tap_ratio"]=1.02
    @test build_sdp_opf(net,nothing) isa SDPBuild
end

@testset "SDP source phase does not create a spurious nullspace row" begin
    net=_sdp_tx_case("single_phase")
    _sdp_zload!(net,"l",["p","n"],0.03-0.01im)
    net["voltage_source"]["s"]["v_angle"][1]=0.173
    r=_tx_solve(net)
    @test r.solve.optimal
    @test r.voltage_candidate[("t","p")] ≈ 115cis(0.173) rtol=3e-5
end

@testset "SDP open-delta connection choices, loss and excitation" begin
    for (conn,pairs,shared) in (("ABBC",[(1,2),(2,3)],2),("BCAC",[(2,3),(1,3)],3),("CABA",[(3,1),(2,1)],1))
        net=_sdp_tx_case("open_delta_regulator";tap=1.03)
        tx=net["transformer"]["open_delta_regulator"]["tx"];tx["connection"]=conn
        vs=230cis.([0.0,-2pi/3,2pi/3]);n=[1/1.03,1.03]
        expected=zeros(ComplexF64,3);expected[shared]=vs[shared]
        for (k,(p,q)) in enumerate(pairs)
            if q==shared;expected[p]=expected[q]+(vs[p]-vs[q])/n[k]
            else;expected[q]=expected[p]-(vs[p]-vs[q])/n[k];end
        end
        for (k,t) in enumerate(["a","b","c"]);_sdp_zload!(net,t,[t],0.01k);end
        r=_tx_solve(net)
        @test r.solve.optimal
        @test [r.voltage_candidate[("t",t)] for t in ["a","b","c"]] ≈ expected rtol=3e-5
    end
    # Single regulator: analytic through-circuit including source-side exciting shunt.
    net=_sdp_tx_case("single_phase_autotransformer";tap=1.03)
    tx=net["transformer"]["single_phase_autotransformer"]["tx"]
    merge!(tx,Dict("r_series_from"=>0.1,"x_series_to"=>0.2,"g_no_load"=>0.002))
    y=0.03-0.01im;_sdp_zload!(net,"l",["p","n"],y)
    n=1/1.03;v=230/n/(1+(0.1/n^2+0.2im)*y)
    r=_tx_solve(net)
    @test r.solve.optimal
    @test r.voltage_candidate[("t","p")] ≈ v rtol=3e-5
    @test r.objective ≈ real(230conj(y*v/n+0.002*230)) rtol=3e-6
end
