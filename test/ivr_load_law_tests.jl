using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
isdefined(@__MODULE__,:ivr_compiler_case) || include("../examples/ivr_compiler_cases.jl")

function _loadlaw_data!(d,law,n;nominal=230.)
    d["model"]=law;d["v_nom"]=fill(nominal,n)
    if lowercase(law)=="zip"
        for (prefix,vals) in (("alpha",(.2,.3,.5)),("beta",(.4,.5,.1))), (suffix,x) in zip(("z","i","p"),vals)
            d[prefix*"_"*suffix]=fill(x,n)
        end
    elseif lowercase(law)=="exponential"
        d["gamma_p"]=[(.4,3.2,-1.)[mod1(k,3)] for k in 1:n]
        d["gamma_q"]=[(-.5,0.,2.)[mod1(k,3)] for k in 1:n]
    end
    d
end
# Manufacture an SI state from prescribed coil voltages and the declared power
# functions; derive source phasors from the series drop. No formulation helpers.
function _loadlaw_witness(m,law;direction=1.)
    net=ivr_compiler_case(conductors=m,segments=1)
    tm=net["bus"]["b1"]["terminal_names"];n=m==2 ? 1 : 3
    pairs=m==3 ? [(1,2),(2,3),(3,1)] : [(k,m) for k in 1:n]
    D=[Float64(j==a)-Float64(j==b) for (a,b) in pairs,j in 1:m]
    v=m==2 ? ComplexF64[218cis(.23),0] : [218cis(.23),227cis(-2pi/3+.23),211cis(2pi/3+.23)]
    m==4 && push!(v,0im)
    u=D*v;vn=m==3 ? 230sqrt(3) : 230.
    d=_loadlaw_data!(net["load"]["d1"],law,n;nominal=vn)
    d["p_nom"]=direction.*[400.0+100k for k in 1:n];d["q_nom"]=direction.*[70.0-25k for k in 1:n]
    r=abs.(u)./vn
    fp=lowercase(law)=="constant_current" ? r : lowercase(law)=="zip" ? .2r.^2+.3r.+.5 : r.^d["gamma_p"]
    fq=lowercase(law)=="constant_current" ? r : lowercase(law)=="zip" ? .4r.^2+.5r.+.1 : r.^d["gamma_q"]
    power=complex.(d["p_nom"].*fp,d["q_nom"].*fq);j=conj.(power./u);it=transpose(D)*j
    Z=[a==b ? (.12+.03a)+(.03+.01a)*im : .015+.005im for a in 1:m,b in 1:m]
    if m!=3;v .-= (Z*it)[end];end # Fix source neutral to earth while retaining downstream displacement.
    vs=v+Z*it;m!=3 && (vs[end]=0im)
    code=net["linecode"]["wire"]
    for a in 1:m,b in a:m;code["R_series_$(a)_$(b)"]=real(Z[a,b]);code["X_series_$(a)_$(b)"]=imag(Z[a,b]);end
    src=net["voltage_source"]["source"];src["v_magnitude"]=abs.(vs);src["v_angle"]=angle.(vs)
    source=copy(it);m!=3 && (source[end]=0im)
    point=ACPoint(voltage=merge(Dict(("b0",t)=>x for (t,x) in zip(tm,vs)),Dict(("b1",t)=>x for (t,x) in zip(tm,v))),
        currents=Dict((:line_from,"l1")=>it,(:line_to,"l1")=>-it,(:load,"d1")=>j,(:voltage_source,"source")=>source))
    net,point
end
_loadlaw_solve(b)=solve_ivr_nlp_opf(b;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.,max_iter=600))

@testset "Exact voltage-dependent laws: independent states and full/reduced solves" begin
    for m in (2,3,4),law in ("CONSTANT_CURRENT","zip","exponential"),direction in (-1.,0.,1.)
        net,point=_loadlaw_witness(m,law;direction);original=deepcopy(net)
        for sb in (1e3,1e5),specialization in (:off,:conductor_difference)
            b=build_opf(net,IVRNLP(;s_base=sb,specialization);optimizer=Ipopt.Optimizer)
            @test ivr_nlp_point_report(b,point).passed
            @test physical_residuals(net,point;delta_dispatch=:coil).passed
            @test b.numerical_diagnostics[:specialization]==specialization
            @test !haskey(b.load_constraints,"d1")
            @test length(b.load_voltage_variables["d1"])==(m==2 ? 1 : 3)
            r=_loadlaw_solve(b);@test r.solve.optimal
            @test physical_residuals(net,r).passed
            rp=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(b,rp).passed
            for (key,v) in point.voltage;@test r.voltage_candidate[key] ≈ v atol=1e-5;end
            @test r.current_candidate[(:load,"d1")] ≈ point.currents[(:load,"d1")] atol=1e-5
            other=build_opf(net,IVRNLP(s_base=sb,specialization=specialization==:off ? :conductor_difference : :off))
            @test ivr_nlp_point_report(other,rp).passed
            for ref in b.load_voltage_variables["d1"]
                supplied=ivr_nlp_point_report(b,point).variable_values
                supplied[ref.variable]*=1.1
                @test !isempty(primal_feasibility_report(b.model,supplied;atol=1e-7))
            end
        end
        @test net==original
    end
end

@testset "Voltage-law operating bounds, current perturbations and domain" begin
    for m in (2,3,4),law in ("constant_current","zip","exponential")
        net,p=_loadlaw_witness(m,law);tm=net["bus"]["b1"]["terminal_names"]
        for specialization in (:off,:conductor_difference)
            b=build_opf(net,IVRNLP(;specialization))
            cs=deepcopy(p.currents);cs[(:load,"d1")][1]+=.1
            bad=ACPoint(voltage=p.voltage,currents=cs)
            @test !ivr_nlp_point_report(b,bad).passed
            @test !physical_residuals(net,bad;delta_dispatch=:coil).passed
            # Tighten the actual load-coil lower bound, retaining the original state.
            tight=deepcopy(net);u=m==3 ? p.voltage[("b1","a")]-p.voltage[("b1","b")] : p.voltage[("b1","a")]-p.voltage[("b1","n")]
            field=m==3 ? "vpp_min" : "vpn_min";tight["bus"]["b1"][field][1]=1.01abs(u)
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(;specialization)),p).passed
            a=physical_residuals(tight,p;delta_dispatch=:coil)
            @test [r.label for r in a.records if r.residual>getproperty(a.tolerances,r.unit)]==["bus/b1/$field"]
            tight=deepcopy(net);tight["linecode"]["wire"]["i_max"][end]=.5abs(p.currents[(:line_from,"l1")][end])
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(;specialization)),p).passed
            a=physical_residuals(tight,p;delta_dispatch=:coil)
            @test Set(r.label for r in a.records if r.residual>getproperty(a.tolerances,r.unit))==Set(["line/l1/from/i_max","line/l1/to/i_max"])
            # Zero voltage must reject without evaluating a singular fractional power.
            volts=deepcopy(p.voltage);for t in tm;volts[("b1",t)]=0im;end
            @test !ivr_nlp_point_report(b,ACPoint(voltage=volts,currents=p.currents)).passed
        end
        field=m==3 ? "vpp_min" : "vpn_min";delete!(net["bus"]["b1"],field)
        @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
        # Individual conductor lower bounds do not bound a difference voltage.
        net["bus"]["b1"]["v_min"]=fill(1.,m)
        @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
    end
end

@testset "Voltage-law fields and update boundaries" begin
    for law in ("constant_current","zip","exponential")
        net,p=_loadlaw_witness(2,law)
        for (key,value) in (("v_nom",[0.]),("v_nom",[-1.]),("v_nom",[NaN]),("v_nom",[true]),("v_nom",[230.,230.]),
                           ("p_nom",[Inf]),("q_nom",Float64[]),("control_profile","c"),("i_max",[10.]))
            bad=deepcopy(net);bad["load"]["d1"][key]=value
            @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
        end
        # A failed mixed update cannot mutate the valid CP entry first.
        cp=deepcopy(net["load"]["d1"])
        for key in collect(keys(cp));(startswith(key,"alpha") || startswith(key,"beta") || startswith(key,"gamma")) && delete!(cp,key);end
        cp["model"]="constant_power";cp["p_nom"]=[0.];cp["q_nom"]=[0.];net["load"]["cp"]=cp
        b=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);original=deepcopy(b.network)
        @test_throws ArgumentError update_ivr_loads!(b,Dict("cp"=>(p=[100.],q=[0.]),"d1"=>(p=[100.],q=[0.])))
        @test b.network==original
        update_ivr_loads!(b,Dict("cp"=>(p=[100.],q=[0.])))
        r=_loadlaw_solve(b);@test r.solve.optimal && physical_residuals(b.network,r).passed
        fresh=build_opf(b.network,IVRNLP();optimizer=Ipopt.Optimizer);rf=_loadlaw_solve(fresh)
        @test rf.solve.optimal
        @test r.objective ≈ rf.objective atol=1e-5
        @test ivr_nlp_point_report(fresh,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
        @test ivr_nlp_point_report(b,ACPoint(voltage=rf.voltage_candidate,currents=rf.current_candidate)).passed
    end
    for law in ("zip","exponential")
        net,p=_loadlaw_witness(2,law);key=law=="zip" ? "alpha_z" : "gamma_p"
        for value in ([NaN],[Inf],[true],[.1,.2])
            bad=deepcopy(net);bad["load"]["d1"][key]=value
            @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
        end
        bad=deepcopy(net);delete!(bad["load"]["d1"],key)
        @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
        bad=deepcopy(net);bad["load"]["d1"][law=="zip" ? "gamma_p" : "alpha_z"]=[1.]
        @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    end
    for x in (-.1,.5)
        net,p=_loadlaw_witness(2,"zip");net["load"]["d1"]["beta_p"]=[x]
        @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
    end
end

@testset "Fixed source domains, scalar coefficients and zero-voltage impedance" begin
    for law in ("constant_current","zip","exponential"),cfg in ("SINGLE_PHASE","WYE","DELTA")
        tm=cfg=="SINGLE_PHASE" ? ["a"] : ["a","b","c"];n=length(tm)
        v=n==1 ? [210cis(.3)] : 210cis.([.3,.3-2pi/3,.3+2pi/3]);vn=cfg=="DELTA" ? 230sqrt(3) : 230.
        d=Dict{String,Any}("bus"=>"b","terminal_map"=>tm,"configuration"=>cfg,"p_nom"=>fill(500.,n),"q_nom"=>fill(100.,n))
        _loadlaw_data!(d,law,n;nominal=vn)
        for key in ("v_nom","alpha_z","alpha_i","alpha_p","beta_z","beta_i","beta_p")
            haskey(d,key) && (d[key]=first(d[key]))
        end
        net=Dict{String,Any}("bus"=>Dict("b"=>Dict("terminal_names"=>tm)),"load"=>Dict("d"=>d),
            "voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>tm,"v_magnitude"=>abs.(v),"v_angle"=>angle.(v))))
        b=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);r=_loadlaw_solve(b)
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test isempty(b.load_voltage_variables["d"])
        @test ivr_nlp_point_report(b,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
    end
    for law in ("constant_impedance","zip","exponential")
        # Two distinct, equal nonzero conductor voltages give zero coil voltage.
        d=Dict{String,Any}("bus"=>"b","terminal_map"=>["a","b"],"configuration"=>"SINGLE_PHASE",
            "p_nom"=>[500.],"q_nom"=>[100.],"v_nom"=>[230.],"model"=>law)
        if law=="zip"
            for prefix in ("alpha","beta"),suffix in ("z","i","p");d[prefix*"_"*suffix]=[suffix=="z" ? 1. : 0.];end
        elseif law=="exponential"
            d["gamma_p"]=[2.];d["gamma_q"]=[2.]
        end
        net=Dict{String,Any}("bus"=>Dict("b"=>Dict("terminal_names"=>["a","b"])),"load"=>Dict("d"=>d),
            "voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>["a","b"],"v_magnitude"=>[230.,230.],"v_angle"=>[0.,0.])))
        b=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);r=_loadlaw_solve(b)
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test isempty(b.load_voltage_variables)
        @test r.current_candidate[(:load,"d")] ≈ [0im] atol=1e-8
        # Preserve KCL and power while violating only the zero-voltage current law.
        cs=deepcopy(r.current_candidate);cs[(:load,"d")]=[1im];cs[(:voltage_source,"s")]=[1im,-1im]
        p=ACPoint(voltage=r.voltage_candidate,currents=cs)
        @test !ivr_nlp_point_report(b,p).passed
        a=physical_residuals(net,p;delta_dispatch=:coil)
        @test [r.label for r in a.records if r.residual>getproperty(a.tolerances,r.unit)]==["load/d/impedance_current"]
        if law!="constant_impedance"
            d[law=="zip" ? "alpha_z" : "gamma_p"]=[.4]
            law=="zip" && (d["alpha_i"]=[.6])
            @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
        end
    end
    for law in ("constant_current","zip","exponential"),m in (3,4)
        net,p=_loadlaw_witness(m,law);d=net["load"]["d1"]
        for bus in values(net["bus"]);reverse!(bus["terminal_names"]);end
        cs=deepcopy(p.currents)
        if m==3
            d["terminal_map"]=["b","a","c"]
            for key in ("p_nom","q_nom","v_nom","alpha_z","alpha_i","alpha_p","beta_z","beta_i","beta_p","gamma_p","gamma_q")
                haskey(d,key) && (d[key]=d[key][[1,3,2]])
            end
            cs[(:load,"d1")]=-cs[(:load,"d1")][[1,3,2]]
        else
            d["terminal_map"]=["a","n","b","c"]
        end
        point=ACPoint(voltage=p.voltage,currents=cs)
        @test physical_residuals(net,point;delta_dispatch=:coil).passed
        for specialization in (:off,:conductor_difference)
            @test ivr_nlp_point_report(build_opf(net,IVRNLP(;specialization)),point).passed
        end
    end
end

@testset "Equal coil magnitude bounds do not overdetermine the load NLP" begin
    for law in ("constant_current","zip","exponential"),specialization in (:off,:conductor_difference),sb in (1e3,1e5)
        net,p=_loadlaw_witness(2,law)
        magnitude=abs(p.voltage[("b1","a")]-p.voltage[("b1","n")])
        bus=net["bus"]["b1"];bus["vpn_min"]=[magnitude];bus["vpn_max"]=[magnitude]
        b=build_opf(net,IVRNLP(;specialization,s_base=sb);optimizer=Ipopt.Optimizer)
        @test isempty(b.load_voltage_variables["d1"])
        @test ivr_nlp_point_report(b,p).passed
        r=_loadlaw_solve(b);@test r.solve.optimal
        @test physical_residuals(net,r).passed
        @test ivr_nlp_point_report(b,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
    end
end
