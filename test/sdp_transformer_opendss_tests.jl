# Independent OpenDSS circuits, fixed taps and controls disabled. Source phasors
# are read after solving to account for OpenDSS's finite source impedance.
using OpenDSSDirect
@testset "SDP winding leakage matches OpenDSS fixed-tap circuits" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta"),tap in (1.0,1.04)
        net=_sdp_tx_case(kind;tap)
        tx=net["transformer"][kind]["tx"]
        # Three-phase delta bus gauge is free in the SDP; compare line-to-line
        # voltages, never a pseudoinverse-selected common mode.
        kind=="wye_delta" && empty!(net["bus"]["t"]["perfectly_grounded_terminals"])
        nphase=kind in ("single_phase","center_tap") ? 1 : 3
        vh=tx["v_nom_from"];vl=tx["v_nom_to"];rating=10_000.0
        zbh=vh^2/(rating/nphase);zbl=vl^2/(rating/nphase)
        merge!(tx,Dict("r_series_from"=>0.005zbh,"x_series_from"=>0.01zbh,
                      "r_series_to"=>0.005zbl,"x_series_to"=>0.01zbl))
        dss(cmd)=OpenDSSDirect.dss(cmd)
        dss("clear")
        kvh=vh/1000*(nphase==3 ? sqrt(3) : 1)
        kvl=vl/1000*(nphase==3 ? sqrt(3) : 1)
        dss("new circuit.sdp_tx phases=$nphase bus1=f basekv=$kvh pu=1 angle=0")
        if kind=="center_tap"
            dss("new transformer.tx phases=1 windings=3 xhl=2 xht=2 xlt=2")
            dss("~ wdg=1 bus=f.1.0 conn=wye kv=$kvh kva=10 %r=0.5 tap=$tap")
            dss("~ wdg=2 bus=t.1.0 conn=wye kv=$kvl kva=10 %r=0.5")
            dss("~ wdg=3 bus=t.0.2 conn=wye kv=$kvl kva=10 %r=0.5")
            specs=[("l1",["x1","n"],"t.1.0",0.9,0.2),("l2",["x2","n"],"t.2.0",0.3,0.05)]
        elseif nphase==1
            dss("new transformer.tx phases=1 windings=2 xhl=2")
            dss("~ wdg=1 bus=f.1.0 conn=wye kv=$kvh kva=10 %r=0.5 tap=$tap")
            dss("~ wdg=2 bus=t.1.0 conn=wye kv=$kvl kva=10 %r=0.5")
            specs=[("l",["p","n"],"t.1.0",1.0,0.2)]
        else
            cf=kind=="delta_wye" ? "delta" : "wye";ct=kind=="delta_wye" ? "wye" : "delta"
            dss("new transformer.tx phases=3 windings=2 xhl=2 leadlag=lag")
            dss("~ wdg=1 bus=f.1.2.3.0 conn=$cf kv=$kvh kva=10 %r=0.5 tap=$tap")
            dss("~ wdg=2 bus=t.1.2.3.0 conn=$ct kv=$kvl kva=10 %r=0.5")
            phase=["a","b","c"]
            specs=[("l$k",kind=="delta_wye" ? [phase[k],"n"] : [phase[k],phase[mod1(k+1,3)]],
                "t.$k.$(kind=="delta_wye" ? 0 : mod1(k+1,3))",0.2k,0.05k) for k in 1:3]
        end
        for (id,tm,bus,p,q) in specs
            voltage=kind=="wye_delta" ? vl*sqrt(3) : vl
            _sdp_zload!(net,id,tm,conj(complex(p,q))*1000/voltage^2)
            dss("new load.$id phases=1 bus1=$bus conn=wye kv=$(voltage/1000) kw=$p kvar=$q model=2")
        end
        dss("set maxiterations=100 tolerance=1e-11 controlmode=off")
        dss("solve")
        @test OpenDSSDirect.Solution.Converged()
        dv=Dict(lowercase(n)=>v for (n,v) in zip(OpenDSSDirect.Circuit.AllNodeNames(),OpenDSSDirect.Circuit.AllBusVolts()))
        src=net["voltage_source"]["s"]
        for k in 1:nphase
            src["v_magnitude"][k]=abs(dv["f.$k"]);src["v_angle"][k]=angle(dv["f.$k"])
        end
        r=_tx_solve(net)
        @test r.solve.optimal
        terminalmap=kind=="center_tap" ? Dict("x1"=>1,"x2"=>2,"n"=>0) :
            nphase==1 ? Dict("p"=>1,"n"=>0) : Dict("a"=>1,"b"=>2,"c"=>3,"n"=>0)
        for (_,tm,_,_,_) in specs
            actual=r.voltage_candidate[("t",tm[1])]-r.voltage_candidate[("t",tm[2])]
            expected=get(dv,"t.$(terminalmap[tm[1]])",0im)-get(dv,"t.$(terminalmap[tm[2]])",0im)
            @test actual ≈ expected rtol=2e-4 atol=0.005
        end
        # Compare source complex power, including winding losses.
        OpenDSSDirect.Circuit.SetActiveElement("transformer.tx")
        powers=OpenDSSDirect.CktElement.Powers()
        expected=sum(powers[1:OpenDSSDirect.CktElement.NumConductors()])*1000
        @test sum(r.relaxed_powers[(:transformer_from,"$kind/tx")]) ≈ expected rtol=2e-4 atol=0.02
    end
end
