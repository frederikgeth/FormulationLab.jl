using Test, FormulationLab, Ipopt, OpenDSSDirect
# Matched operating domain: DSS's low/high-voltage substitutions and ZIP cutoff
# are disabled within the tested range. Native nominal voltages are coil volts.
# Reference: https://dss-extensions.org/dss-format/Load.html
@testset "Exact voltage-dependent loads match OpenDSS within their common domain" begin
    for cfg in ("SINGLE_PHASE","WYE","DELTA"),law in ("constant_current","zip","exponential"),pu in (.85,1.08)
        n=cfg=="SINGLE_PHASE" ? 1 : 3;tm=n==1 ? ["a"] : ["a","b","c"]
        vn=cfg=="DELTA" ? 230sqrt(3) : 230.;kv=n==1 ? .23 : .23sqrt(3)
        model=law=="constant_current" ? 5 : law=="zip" ? 8 : 4
        extras=law=="zip" ? "ZIPV=[.2 .3 .5 .4 .5 .1 0]" : law=="exponential" ? "CVRwatts=.4 CVRvars=-.5" : ""
        dss(cmd)=OpenDSSDirect.dss(cmd)
        dss("clear");dss("new circuit.loadlaw phases=$n bus1=b0 basekv=$kv pu=$pu angle=13")
        mat(x)=join([join([j==k ? string(x) : "0" for j in 1:k]," ") for k in 1:n]," | ")
        dss("new line.l phases=$n bus1=b0 bus2=b1 length=1 units=none rmatrix=[$(mat(.2))] xmatrix=[$(mat(.05))] cmatrix=[$(mat(0.))]")
        conn=cfg=="DELTA" ? "delta" : "wye"
        bus=n==1 ? "b1.1.0" : "b1.1.2.3.0"
        dss("new load.d phases=$n bus1=$bus conn=$conn kv=$kv kw=1 kvar=.3 model=$model vminpu=.7 vmaxpu=1.2 vlowpu=.5 $extras")
        dss("set controlmode=off tolerance=1e-12 maxiterations=100");dss("solve")
        @test OpenDSSDirect.Solution.Converged()
        volt=Dict(lowercase(k)=>v for (k,v) in zip(OpenDSSDirect.Circuit.AllNodeNames(),OpenDSSDirect.Circuit.AllBusVolts()))
        vs=[volt["b0.$k"] for k in 1:n]
        load=Dict{String,Any}("bus"=>"b1","terminal_map"=>tm,"configuration"=>cfg,"model"=>law,
            "p_nom"=>fill(1000/n,n),"q_nom"=>fill(300/n,n),"v_nom"=>fill(vn,n))
        if law=="zip"
            for (prefix,vals) in (("alpha",(.2,.3,.5)),("beta",(.4,.5,.1))),(suffix,x) in zip(("z","i","p"),vals)
                load[prefix*"_"*suffix]=fill(x,n)
            end
        elseif law=="exponential"
            load["gamma_p"]=fill(.4,n);load["gamma_q"]=fill(-.5,n)
        end
        busdata=Dict("terminal_names"=>tm,(cfg=="DELTA" ? "vpp_min" : "v_min")=>fill(.7vn,n))
        line=Dict{String,Any}("bus_from"=>"b0","bus_to"=>"b1","terminal_map_from"=>tm,"terminal_map_to"=>tm)
        for k in 1:n;line["R_series_$(k)_$(k)"]=.2;line["X_series_$(k)_$(k)"]=.05;end
        net=Dict{String,Any}("bus"=>Dict("b0"=>Dict("terminal_names"=>tm),"b1"=>busdata),"line"=>Dict("l"=>line),"load"=>Dict("d"=>load),
            "voltage_source"=>Dict("s"=>Dict("bus"=>"b0","terminal_map"=>tm,"v_magnitude"=>abs.(vs),"v_angle"=>angle.(vs))))
        b=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
        r=solve_ivr_nlp_opf(b;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.))
        @test r.solve.optimal
        @test physical_residuals(net,r).passed
        @test ivr_nlp_point_report(b,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
        @test [r.voltage_candidate[("b1",t)] for t in tm] ≈ [volt["b1.$k"] for k in 1:n] atol=1e-5 rtol=1e-7
        OpenDSSDirect.Circuit.SetActiveElement("load.d")
        @test sum(r.powers[(:load,"d")]) ≈ 1000sum(OpenDSSDirect.CktElement.Powers()) atol=1e-4 rtol=1e-7
        OpenDSSDirect.Circuit.SetActiveElement("line.l")
        @test r.current_candidate[(:line_from,"l")] ≈ OpenDSSDirect.CktElement.Currents()[1:n] atol=1e-5 rtol=1e-7
    end
end
