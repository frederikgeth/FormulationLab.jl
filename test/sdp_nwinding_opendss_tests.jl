using OpenDSSDirect
@testset "SDP general three-winding OpenDSS oracle" begin
    for tap in (1.0,1.04),delta in (false,true)
        net=_nw_case(;tap);tx=net["transformer"]["n_winding"]["t"]
        # Three physical phases, arbitrary output winding turns, optional delta.
        for (k,w) in enumerate(tx["windings"])
            w["terminal_map"]=["a","b","c","n"]
            net["bus"][w["bus"]]=Dict{String,Any}("terminal_names"=>copy(w["terminal_map"]),"perfectly_grounded_terminals"=>["n"])
            if delta && k==2
                w["terminal_map"]=["a","b","c"];w["configuration"]="DELTA";w["v_nom"]*=sqrt(3);w["r_winding"]*=3
                net["bus"][w["bus"]]=Dict{String,Any}("terminal_names"=>copy(w["terminal_map"]))
            end
        end
        src=net["voltage_source"]["s"];src["terminal_map"]=["a","b","c","n"]
        src["v_magnitude"]=[230.0,230.0,230.0,0.0];src["v_angle"]=[0.0,-2pi/3,2pi/3,0.0]
        net["load"]=Dict{String,Any}();specs=[]
        dss(cmd)=OpenDSSDirect.dss(cmd)
        dss("clear");dss("new circuit.nwind phases=3 bus1=b basekv=$(230sqrt(3)/1000) pu=1 angle=0")
        zb=3*230^2/10000;rpct=100*0.01/zb;xpct=100*0.04/zb
        dss("new transformer.t phases=3 windings=3 xhl=$xpct xht=$xpct xlt=$xpct leadlag=lag")
        for (k,w) in enumerate(tx["windings"])
            cfg=lowercase(w["configuration"]);vll=w["v_nom"]*(cfg=="wye" ? sqrt(3) : 1)
            bus=w["bus"];tk=k==1 ? tap : 1.0
            dss("edit transformer.t wdg=$k bus=$bus.1.2.3.0 conn=$cfg kv=$(vll/1000) kva=10 %r=$rpct tap=$tk")
            k==1 && continue
            for c in 1:3
                p=c;q=cfg=="delta" ? mod1(c+1,3) : 0
                tm=cfg=="delta" ? [w["terminal_map"][p],w["terminal_map"][q]] : [w["terminal_map"][p],"n"]
                id="l$(k)_$c";kw=0.2c/k;kvar=0.05c/k
                net["load"][id]=Dict("bus"=>bus,"terminal_map"=>tm,"configuration"=>"SINGLE_PHASE","model"=>"constant_impedance",
                    "v_nom"=>[w["v_nom"]],"p_nom"=>[kw*1000],"q_nom"=>[kvar*1000])
                dss("new load.$id phases=1 bus1=$bus.$p.$q conn=wye kv=$(w["v_nom"]/1000) kw=$kw kvar=$kvar model=2")
                push!(specs,(bus,tm,p,q))
            end
        end
        dss("set controlmode=off maxiterations=100 tolerance=1e-11");dss("solve")
        @test OpenDSSDirect.Solution.Converged()
        dv=Dict(lowercase(n)=>v for (n,v) in zip(OpenDSSDirect.Circuit.AllNodeNames(),OpenDSSDirect.Circuit.AllBusVolts()))
        for c in 1:3;src["v_magnitude"][c]=abs(dv["b.$c"]);src["v_angle"][c]=angle(dv["b.$c"]);end
        r=_tx_solve(net);@test r.solve.optimal
        for (bus,tm,p,q) in specs
            @test r.voltage_candidate[(bus,tm[1])]-r.voltage_candidate[(bus,tm[2])] ≈ dv["$bus.$p"]-get(dv,"$bus.$q",0im) rtol=3e-4 atol=0.01
        end
        OpenDSSDirect.Circuit.SetActiveElement("transformer.t")
        expected=sum(OpenDSSDirect.CktElement.Powers()[1:OpenDSSDirect.CktElement.NumConductors()])*1000
        @test sum(r.relaxed_powers[(:transformer_winding,"n_winding/t/1")]) ≈ expected rtol=3e-4 atol=0.03
    end
end
