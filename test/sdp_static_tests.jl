function _static_source_case(;voltage=230.0)
    Dict{String,Any}("bus"=>Dict("b"=>Dict{String,Any}("terminal_names"=>["p","n"],"perfectly_grounded_terminals"=>["n"])),
        "voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>["p","n"],"v_magnitude"=>[voltage,0.0],"v_angle"=>[0.0,0.0])))
end
@testset "SDP fixed switches and connection-aware capacitors" begin
    net=_l3f_case();old=deepcopy(net["line"]["line"])
    net["switch"]=Dict("sw"=>Dict(k=>old[k] for k in ("bus_from","bus_to","terminal_map_from","terminal_map_to")))
    sw=net["switch"]["sw"];sw["open_switch"]=false;delete!(net,"line")
    r=_tx_solve(net)
    @test r.solve.optimal
    @test r.objective ≈ 10000 atol=0.01
    sw["i_max"]=[1.0];@test !_tx_solve(net).solve.optimal
    delete!(sw,"i_max");sw["open_switch"]=true;@test !_tx_solve(net).solve.optimal
    sw["open_switch"]=false
    net["capacitor"]=Dict("c"=>Dict("bus"=>"load","terminal_map"=>["a"],"configuration"=>"SINGLE_PHASE","q_rated"=>[2000.0],"v_nom"=>230.0))
    r=_tx_solve(net)
    @test r.solve.optimal
    @test only(r.relaxed_powers[(:capacitor,"c")]) ≈ -2000im atol=0.01
    @test imag(sum(r.relaxed_powers[(:voltage_source,"source")])) ≈ 0 atol=0.01
end

@testset "SDP internal winding grounding and explicit excitation" begin
    for rground in (0.0,2.0)
        net=_sdp_tx_case("single_phase");tx=net["transformer"]["single_phase"]["tx"]
        empty!(net["bus"]["t"]["perfectly_grounded_terminals"])
        tx["r_neutral_to"]=rground
        # A phase-to-earth load drives an observable neutral ground current.
        _sdp_zload!(net,"l",["p"],0.1)
        r=_tx_solve(net);vp=115/(1+0.1rground);vn=vp-115
        @test r.solve.optimal
        @test r.voltage_candidate[("t","p")] ≈ vp rtol=3e-5
        @test r.voltage_candidate[("t","n")] ≈ vn atol=0.002
        @test r.objective ≈ 115*0.1vp rtol=3e-5
    end
    net=_sdp_tx_case("center_tap");tx=net["transformer"]["center_tap"]["tx"]
    tx["no_load_shunt"]=Dict("winding"=>3,"g"=>0.01,"b"=>-0.02)
    r=_tx_solve(net)
    @test r.solve.optimal
    @test r.objective ≈ 144 atol=0.005
    @test sum(r.relaxed_powers[(:transformer_to,"center_tap/tx")]) ≈ 0 atol=0.005
    tx["g_no_load"]=0.0
    @test_throws SDPInapplicableError build_sdp_opf(net,nothing)
end

function _nw_case(;tap=1.0)
    net=_static_source_case();ws=Dict{String,Any}[]
    for (k,voltage) in enumerate((230.0,115.0,57.5))
        bus=k==1 ? "b" : "b$k"
        net["bus"][bus]=Dict{String,Any}("terminal_names"=>["p","n"],"perfectly_grounded_terminals"=>["n"])
        push!(ws,Dict("bus"=>bus,"terminal_map"=>["p","n"],"configuration"=>"WYE","v_nom"=>voltage,"r_winding"=>0.01*(voltage/230)^2,"tap_ratio"=>k==1 ? tap : 1.0))
    end
    net["transformer"]=Dict("n_winding"=>Dict("t"=>Dict("windings"=>ws,"x_sc"=>Dict("1_2"=>0.04,"1_3"=>0.04,"2_3"=>0.04),"s_rating"=>10000.0)))
    net["load"]=Dict("l2"=>Dict("bus"=>"b2","terminal_map"=>["p","n"],"configuration"=>"WYE","model"=>"constant_impedance","v_nom"=>[115.0],"p_nom"=>[1000.0],"q_nom"=>[200.0]),
                     "l3"=>Dict("bus"=>"b3","terminal_map"=>["p","n"],"configuration"=>"WYE","model"=>"constant_impedance","v_nom"=>[57.5],"p_nom"=>[300.0],"q_nom"=>[50.0]))
    net
end
@testset "SDP multiwinding coupled leakage and fixed taps" begin
    for tap in (0.97,1.0,1.04)
        net=_nw_case(;tap)
        # Independent star equivalent: common referred R+jX=0.01+j0.02.
        z=0.01+0.02im;ratio=[1.0,0.5,0.25]
        y=[conj(1000+200im)/115^2,conj(300+50im)/57.5^2]
        adm=[ratio[k+1]^2*y[k]/(1+z*ratio[k+1]^2*y[k]) for k in 1:2]
        e=(230/tap)/(1+z*sum(adm));expected=[ratio[k+1]*e/(1+z*ratio[k+1]^2*y[k]) for k in 1:2]
        r=_tx_solve(net)
        @test r.solve.optimal
        for k in 1:2;@test r.voltage_candidate[("b$(k+1)","p")] ≈ expected[k] rtol=3e-5;end
        @test r.objective ≈ real((230/tap)*conj(e*sum(adm))) rtol=3e-5
    end
    net=_nw_case();d=net["transformer"]["n_winding"]["t"]
    delete!(d["x_sc"],"1_3");@test_throws SDPInapplicableError build_sdp_opf(net,nothing)
    d["x_sc"]["1_3"]=0.000001;d["x_sc"]["2_3"]=100
    @test_throws SDPInapplicableError build_sdp_opf(net,nothing)
end

@testset "SDP full bus voltage bounds and multiple fixed sources" begin
    net=_sdp_tx_case("delta_wye");b=net["bus"]["t"]
    # Dy is at nominal 115 V phase-neutral with a -30 degree shift.
    merge!(b,Dict("v_min"=>fill(114.0,3),"v_max"=>fill(116.0,3),"vpn_min"=>fill(114.0,3),"vpn_max"=>fill(116.0,3),
        "vpp_min"=>fill(195.0,3),"vpp_max"=>fill(205.0,3),"vn_max"=>0.0,"vpos_min"=>114.0,"vpos_max"=>116.0,"vneg_max"=>0.01,"vzero_max"=>0.01))
    @test _tx_solve(net).solve.optimal
    b["vpos_max"]=100.0;@test !_tx_solve(net).solve.optimal
    net=_static_source_case();net["bus"]["b2"]=deepcopy(net["bus"]["b"])
    net["voltage_source"]["s2"]=Dict("bus"=>"b2","terminal_map"=>["p","n"],"v_magnitude"=>[115.0,0.0],"v_angle"=>[0.4,0.0])
    r=_tx_solve(net)
    @test r.solve.optimal
    @test r.voltage_candidate[("b2","p")] ≈ 115cis(0.4) rtol=3e-5
end

@testset "SDP static inverters: capability, filter, shared link, controls excluded" begin
    net=_static_source_case()
    d=Dict{String,Any}("bus"=>"b","terminal_map"=>["p","n"],"topology"=>"SINGLE_PHASE","prime_mover"=>"PV","s_max"=>[1000.0],
        "p_min"=>[0.0],"p_max"=>[1000.0],"q_min"=>[0.0],"q_max"=>[0.0],"p_avail"=>500.0,"i_max"=>[10.0,10.0],"control_profile"=>"not-run")
    net["ibr"]=Dict("pv"=>d);net["control_profile"]=Dict("not-run"=>Dict("volt_var"=>"deliberately not evaluated"))
    r=_tx_solve(net)
    @test r.solve.optimal
    @test real(only(r.relaxed_powers[(:ibr,"pv")])) ≈ 500 atol=0.02
    @test build_sdp_opf(net,nothing).omitted_controls == ["ibr/pv/not-run"]
    d["i_max"]=[10.0,1.0];r=_tx_solve(net)
    @test real(only(r.relaxed_powers[(:ibr,"pv")])) ≈ 230 atol=0.02
    d["i_max"]=[10.0,10.0];d["r_filter"]=[1.0];d["dc_link_coupled"]=true;d["p_dc_max"]=300.0
    r=_tx_solve(net)
    @test r.solve.optimal
    @test real(only(r.relaxed_powers[(:ibr_internal,"pv")])) ≈ 300 atol=0.03
    @test real(only(r.relaxed_powers[(:ibr,"pv")])) < 300
end

@testset "SDP voltage-dependent load envelopes contain fixed-voltage laws" begin
    for (law,gp,gq) in (("constant_current",1.0,1.0),("zip",0.0,0.0),("exponential",3.0,-1.0),("exponential",0.4,2.0))
        net=_static_source_case(;voltage=220.0)
        net["bus"]["b"]["vpn_min"]=[220.0];net["bus"]["b"]["vpn_max"]=[220.0]
        d=Dict{String,Any}("bus"=>"b","terminal_map"=>["p","n"],"configuration"=>"WYE","model"=>law,"v_nom"=>[230.0],"p_nom"=>[1000.0],"q_nom"=>[200.0])
        if law=="zip"
            for prefix in ("alpha","beta"),suffix in ("z","i","p");d[prefix*"_"*suffix]=[1/3];end
        elseif law=="exponential"
            d["gamma_p"]=[gp];d["gamma_q"]=[gq]
        end
        net["load"]=Dict("l"=>d)
        r=_tx_solve(net);x=220/230
        @test r.solve.optimal
        expected=law=="zip" ? (1000+200im)*(x^2+x+1)/3 : 1000x^gp+200im*x^gq
        @test only(r.relaxed_powers[(:load,"l")]) ≈ expected rtol=2e-5
    end
end

@testset "SDP canonical combined leakage and from-side legacy excitation" begin
    for kind in ("wye_delta","delta_wye")
        net=_sdp_tx_case(kind);d=net["transformer"][kind]["tx"]
        d["r_series"]=0.01;d["x_series"]=0.02;d["g_no_load"]=0.003
        r=_tx_solve(net)
        @test r.solve.optimal
        winding_voltage=kind=="wye_delta" ? 230.0 : sqrt(3)*230.0
        @test r.objective ≈ 0.003winding_voltage^2 atol=0.03
        d["r_series_from"]=0.1
        @test_throws SDPInapplicableError build_sdp_opf(net,nothing)
    end
    net=_sdp_tx_case("single_phase");d=net["transformer"]["single_phase"]["tx"];d["g_no_load"]=0.003
    @test _tx_solve(net).objective ≈ 0.003*230^2 atol=0.01
end

@testset "SDP four-winding model retains non-star leakage couplings" begin
    net=_nw_case();tx=net["transformer"]["n_winding"]["t"]
    w4=deepcopy(tx["windings"][3]);w4["bus"]="b4";push!(tx["windings"],w4)
    net["bus"]["b4"]=deepcopy(net["bus"]["b3"])
    # This full leakage matrix cannot be reproduced by independent star arms.
    X=[0.06 0.015 0.01;0.015 0.08 0.025;0.01 0.025 0.09]
    tx["x_sc"]=Dict("1_2"=>X[1,1],"1_3"=>X[2,2],"1_4"=>X[3,3],
        "2_3"=>X[1,1]+X[2,2]-2X[1,2],"2_4"=>X[1,1]+X[3,3]-2X[1,3],"3_4"=>X[2,2]+X[3,3]-2X[2,3])
    l4=deepcopy(net["load"]["l3"]);l4["bus"]="b4";l4["p_nom"]=[600.0];net["load"]["l4"]=l4
    ratios=[0.5,0.25,0.25];ys=[conj(1000+200im)/115^2,conj(300+50im)/57.5^2,conj(600+50im)/57.5^2]
    Z=0.01*(ones(3,3)+I)+im*X
    ur=(I+Z*Diagonal(ratios.^2 .*ys))\fill(230.0,3)
    r=_tx_solve(net)
    @test r.solve.optimal
    @test [r.voltage_candidate[("b$k","p")] for k in 2:4] ≈ ratios.*ur rtol=3e-5
end

@testset "SDP generator bounds optional and ignored controls reported" begin
    net=_static_source_case()
    net["generator"]=Dict("g"=>Dict("bus"=>"b","terminal_map"=>["p","n"],"configuration"=>"WYE","s_max"=>[100.0]))
    r=_tx_solve(net)
    @test r.solve.optimal
    @test real(only(r.relaxed_powers[(:generator,"g")])) ≈ 100 atol=0.01
    @test isempty(solve_diagnostics(r).omitted_controls)
    @test isempty(solve_diagnostics(r).load_envelopes)
end

@testset "SDP three-phase inverter connections and delta capacitance" begin
    for topology in ("FOUR_LEG","THREE_LEG")
        net=_static_source_case()
        tm=topology=="FOUR_LEG" ? ["a","b","c","n"] : ["a","b","c"]
        net["bus"]["b"]=Dict{String,Any}("terminal_names"=>tm,"perfectly_grounded_terminals"=>topology=="FOUR_LEG" ? ["n"] : String[])
        volts=230cis.([0.0,-2pi/3,2pi/3]);topology=="FOUR_LEG" && push!(volts,0)
        net["voltage_source"]["s"]=Dict("bus"=>"b","terminal_map"=>tm,"v_magnitude"=>abs.(volts),"v_angle"=>angle.(volts))
        ps=topology=="FOUR_LEG" ? [100.0,200.0,300.0] : fill(200.0,3)
        d=Dict{String,Any}("bus"=>"b","terminal_map"=>tm,"topology"=>topology,"s_max"=>fill(1000.0,3),"p_min"=>ps,"p_max"=>ps,"q_min"=>zeros(3),"q_max"=>zeros(3))
        net["ibr"]=Dict("g"=>d)
        r=_tx_solve(net)
        @test r.solve.optimal
        @test r.objective ≈ -600 atol=0.02
        @test r.relaxed_powers[(:ibr,"g")] ≈ complex.(ps) atol=0.01
        # Fixed internal magnitude is compatible with a filter-free inverter.
        d["grid_forming"]=true;d["v_ref_internal"]=topology=="FOUR_LEG" ? 230.0 : sqrt(3)*230
        @test _tx_solve(net).solve.optimal
        if topology=="FOUR_LEG"
            # Unequal phase powers require a neutral return current.
            d["i_max"]=[10.0,10.0,10.0,0.0]
            @test !_tx_solve(net).solve.optimal
        else
            delete!(net,"ibr") # Test the passive delta admittance independently.
            net["capacitor"]=Dict("c"=>Dict("bus"=>"b","terminal_map"=>tm,"configuration"=>"DELTA","v_nom"=>sqrt(3)*230,"q_rated"=>[100.0,200.0,300.0]))
            r=_tx_solve(net)
            @test r.solve.optimal
            @test r.relaxed_powers[(:capacitor,"c")] ≈ -im.*[100.0,200.0,300.0] atol=0.01
            net["ibr"]=Dict("g"=>d)
            # Equal P/Q bounds must compile as equalities, not opposing cones.
            r=_tx_solve(net)
            @test r.solve.optimal
            @test r.objective ≈ -600 atol=0.02
        end
    end
end
