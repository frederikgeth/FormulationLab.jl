using Test, FormulationLab, Ipopt, OpenDSSDirect

@testset "Exact IVR capacitor bank ratings match OpenDSS" begin
    for cfg in ("SINGLE_PHASE","WYE","DELTA"),pu in (.9,1.1)
        n=cfg=="SINGLE_PHASE" ? 1 : 3;tm=n==1 ? ["a"] : ["a","b","c"]
        vn=n==1 ? 230. : sqrt(3)*230
        dss(cmd)=OpenDSSDirect.dss(cmd)
        dss("clear")
        dss("new circuit.cap_test phases=$n bus1=b basekv=$(vn/1000) pu=$pu angle=0")
        conn=cfg=="DELTA" ? "delta" : "wye"
        bus=n==1 ? "b.1.0" : "b.1.2.3"
        dss("new capacitor.c phases=$n bus1=$bus conn=$conn kv=$(vn/1000) kvar=1.5")
        dss("set controlmode=off tolerance=1e-12 maxiterations=100")
        dss("solve")
        @test OpenDSSDirect.Solution.Converged()
        v=Dict(lowercase(k)=>z for (k,z) in zip(OpenDSSDirect.Circuit.AllNodeNames(),OpenDSSDirect.Circuit.AllBusVolts()))
        volts=[v["b.$k"] for k in 1:n]
        net=Dict{String,Any}("bus"=>Dict("b"=>Dict("terminal_names"=>tm)),
            "voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>tm,"v_magnitude"=>abs.(volts),"v_angle"=>angle.(volts))),
            "capacitor"=>Dict("c"=>Dict("bus"=>"b","terminal_map"=>tm,"configuration"=>cfg,"q_rated"=>1500.,"v_nom"=>vn)))
        build=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer)
        r=solve_ivr_nlp_opf(build;solver_options=(print_level=0,tol=1e-11))
        @test r.solve.optimal
        point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        @test physical_residuals(net,point;delta_dispatch=:coil).passed
        @test ivr_nlp_point_report(build,point).passed
        OpenDSSDirect.Circuit.SetActiveElement("capacitor.c")
        nc=OpenDSSDirect.CktElement.NumConductors()
        expected=sum(OpenDSSDirect.CktElement.Powers()[1:nc])*1000
        @test sum(r.powers[(:capacitor,"c")]) ≈ expected atol=1e-3 rtol=1e-6
        @test r.current_candidate[(:voltage_source,"s")][1:n] ≈ OpenDSSDirect.CktElement.Currents()[1:n] atol=1e-5 rtol=1e-6
    end
end
