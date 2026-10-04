# Independent equivalent circuits: fixed two-winding units with a shared physical
# conductor. No regulator controllers are run, and no tap is optimized.
using Test, FormulationLab, Ipopt, OpenDSSDirect
isdefined(@__MODULE__,:_sdp_tx_case) || include("sdp_transformer_fixtures.jl")
@testset "Exact fixed regulators match OpenDSS bonded winding circuits" begin
    for connection in ("single","ABBC","BCAC","CABA"),rt in ("A","B")
        single=connection=="single";kind=single ? "single_phase_autotransformer" : "open_delta_regulator"
        net=_sdp_tx_case(kind;tap=1.04);d=net["transformer"][kind]["tx"]
        d["regulator_type"]=rt
        pairs=single ? [(1,0)] : Dict("ABBC"=>[(1,2),(2,3)],"BCAC"=>[(2,3),(1,3)],"CABA"=>[(3,1),(2,1)])[connection]
        single || (d["connection"]=connection)
        taps=single ? [1.04] : [1.04,1/1.04];gains=rt=="A" ? inv.(taps) : taps
        d["x_series_from"]=.1
        shared=single ? 0 : only(intersect(collect(pairs[1]),collect(pairs[2])))
        # Use distinct physical node numbers in one DSS bus; the common node
        # is literally shared, so no small-impedance proxy for an ideal bond.
        out(k)=k==shared ? k : k+3
        phases=single ? 1 : 3;kv=single ? .23 : .23sqrt(3)
        OpenDSSDirect.dss("clear")
        OpenDSSDirect.dss("new circuit.reg phases=$phases bus1=n basekv=$kv pu=1 angle=0")
        for (k,(a,b)) in enumerate(pairs)
            tap_from=1/gains[k];zb=(1000kv)^2/10000
            xhl=100*.1/(zb*tap_from^2)
            OpenDSSDirect.dss("new transformer.r$k phases=1 windings=2 xhl=$xhl %noloadloss=0 ppm_antifloat=0")
            OpenDSSDirect.dss("~ wdg=1 bus=n.$a.$b conn=wye kv=$kv kva=10 %r=0 tap=$tap_from")
            OpenDSSDirect.dss("~ wdg=2 bus=n.$(out(a)).$(out(b)) conn=wye kv=$kv kva=10 %r=0 tap=1")
        end
        names=single ? ["p"] : ["a","b","c"]
        for (k,t) in enumerate(names)
            y=.01k-.002im;p=230^2*real(y)/1000;q=-230^2*imag(y)/1000
            _sdp_zload!(net,"l$k",single ? [t,"n"] : [t],y)
            OpenDSSDirect.dss("new load.l$k phases=1 bus1=n.$(out(k)).0 conn=wye kv=.23 kw=$p kvar=$q model=2")
        end
        OpenDSSDirect.dss("set maxiterations=100 tolerance=1e-11 controlmode=off")
        OpenDSSDirect.dss("solve")
        @test OpenDSSDirect.Solution.Converged()
        v=Dict(lowercase(k)=>u for (k,u) in zip(OpenDSSDirect.Circuit.AllNodeNames(),OpenDSSDirect.Circuit.AllBusVolts()))
        s=net["voltage_source"]["s"]
        for k in 1:phases;s["v_magnitude"][k]=abs(v["n.$k"]);s["v_angle"][k]=angle(v["n.$k"]);end
        b=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
        r=solve_ivr_nlp_opf(b;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0))
        @test r.solve.optimal
        @test physical_residuals(net,r).passed
        @test ivr_nlp_point_report(b,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
        for (k,t) in enumerate(names)
            @test r.voltage_candidate[("t",t)] ≈ v["n.$(out(k))"] atol=1e-4 rtol=1e-6
        end
        OpenDSSDirect.Circuit.SetActiveElement("vsource.source")
        power=-sum(OpenDSSDirect.CktElement.Powers())*1000
        @test sum(r.powers[(:voltage_source,"s")]) ≈ power atol=1e-3 rtol=1e-6
    end
end
