using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
isdefined(@__MODULE__,:ivr_compiler_case) || include("../examples/ivr_compiler_cases.jl")

# Independent constant-current witness: line current is load minus delivered
# converter terminal current. Filter currents/voltages are computed in SI.
function _ibr_state(m;reverse=false)
    net=ivr_compiler_case(conductors=m,segments=1)
    tm=net["bus"]["b1"]["terminal_names"];n=m==2 ? 1 : 3
    D=m==2 ? [1. -1.] : m==3 ? [1. -1. 0.;0. 1. -1.;-1. 0. 1.] : [Matrix{Float64}(I,3,3) -ones(3)]
    jl=ComplexF64[(4+.7k)*cis(-.3-2pi*(k-1)/3) for k in 1:n]
    ci=(reverse ? -1 : 1).*ComplexF64[(1+.3k)*cis(.2-2pi*(k-1)/3) for k in 1:n]
    it=transpose(D)*ci;il=transpose(D)*jl-it
    Z=[complex(a==b ? .08+.01a : .01+.001(a+b),a==b ? .04+.002a : .008+.0001(a+b)) for a in 1:m,b in 1:m]
    vs=m==2 ? ComplexF64[230,0] : [230cis.([0.,-2pi/3,2pi/3]);m==4 ? [0im] : ComplexF64[]]
    v=vs-Z*il;u=D*v;jf=ci+.001im.*u;e=u+(.2+.08im).*jf
    sload=u.*conj.(jl);sp=(m==3 ? v.*conj.(it) : u.*conj.(ci));si=e.*conj.(jf)
    net["load"]["d1"]["p_nom"]=real.(sload);net["load"]["d1"]["q_nom"]=imag.(sload)
    net["ibr"]=Dict("g"=>Dict{String,Any}("bus"=>"b1","terminal_map"=>copy(tm),
        "topology"=>m==2 ? "SINGLE_PHASE" : m==3 ? "THREE_LEG" : "FOUR_LEG","prime_mover"=>"BATTERY",
        "s_max"=>fill(1e4,n),"i_max"=>fill(100.,m),"p_min"=>real.(sp),"p_max"=>real.(sp),
        "q_min"=>imag.(sp),"q_max"=>imag.(sp),"r_filter"=>fill(.2,n),"x_filter"=>fill(.08,n),
        "b_filter_shunt"=>.001,"dc_link_coupled"=>true,"p_dc_min"=>-1e5,"p_dc_max"=>1e5,"p_avail"=>1e5,"cost"=>fill(.2,n)))
    volts=Dict(("b0",t)=>z for (t,z) in zip(tm,vs));merge!(volts,Dict(("b1",t)=>z for (t,z) in zip(tm,v)))
    source=copy(il);m==3 || (source[end]=0im)
    currents=Dict((:voltage_source,"source")=>source,(:line_from,"l1")=>il,(:line_to,"l1")=>-il,
        (:load,"d1")=>jl,(:ibr,"g")=>m==3 ? it : ci,(:ibr_internal,"g")=>jf)
    net,ACPoint(voltage=volts,currents=currents),sp,si
end
_ibr_audit(net,p)=physical_residuals(net,p;delta_dispatch=:coil,ibr_delta_dispatch=:conductor)
isdefined(@__MODULE__,:strict_solve) || include("strict_solve.jl")
# tol=1e-11 sat at the limit of double precision for these cases: one solve ended
# at ALMOST_LOCALLY_SOLVED on x86-64 Linux while passing on macOS.
_ibr_solve(b)=strict_solve(b,(print_level=0,tol=1e-10,constr_viol_tol=1e-10,bound_relax_factor=0.))

@testset "Power objectives retain IBR internal and PCC conventions" begin
    for m in (2,3,4),sb in (1e3,1e5),lifting in (:off,:powers)
        net,point,sp,si=_ibr_state(m)
        terms=[IVRPowerTerm(channels=[(family,"g",k)];quantity,
            target=quantity==:p ? real(s[k]) : imag(s[k]),quadratic=1e-6)
            for (family,s) in ((:ibr,sp),(:ibr_internal,si)) for k in eachindex(s) for quantity in (:p,:q)]
        b=build_opf(net,IVRNLP(;objective=:power,power_terms=terms,objective_scale=1.,s_base=sb,
            specialization=:conductor_difference,linear_elimination=:passive_blocks,lifting);optimizer=Ipopt.Optimizer)
        encoded=ivr_nlp_point_report(b,point)
        @test encoded.passed && abs(encoded.objective)<1e-9
        for (v,x) in encoded.variable_values;set_start_value(v,x);end
        r=_ibr_solve(b)
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test abs(r.objective)<1e-8
        @test r.powers[(:ibr,"g")]≈sp atol=1e-3
        @test r.powers[(:ibr_internal,"g")]≈si atol=1e-3
    end
end

@testset "Exact IBR ports, filters and reduced current structure" begin
    for m in (2,3,4),reverse in (false,true)
        net,point,sp,si=_ibr_state(m;reverse);original=deepcopy(net)
        for specialization in (:off,:conductor_difference),s_base in (1e3,1e5)
            build=build_opf(net,IVRNLP(;specialization,s_base);optimizer=Ipopt.Optimizer)
            @test build.numerical_diagnostics[:ibr_delta_dispatch]==:conductor
            @test build.numerical_diagnostics[:specialization]==specialization
            @test ivr_nlp_point_report(build,point).passed
            @test _ibr_audit(net,point).passed
            r=_ibr_solve(build);@test r.solve.optimal
            @test physical_residuals(net,r).passed
            @test r.powers[(:ibr,"g")] ≈ sp atol=1e-5
            # A delta coil circulation is electrically unobserved at PCC;
            # fixed PCC dispatch does not fix its internal filter losses.
            if m!=3;@test r.powers[(:ibr_internal,"g")] ≈ si atol=1e-5;end
            for (key,v) in point.voltage;@test r.voltage_candidate[key] ≈ v atol=2e-5;end
            p=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(build,p).passed
            for family in (:ibr,:ibr_internal)
                bad=deepcopy(point.currents);bad[(family,"g")][1]+=.1
                @test !ivr_nlp_point_report(build,ACPoint(voltage=point.voltage,currents=bad)).passed
                @test !_ibr_audit(net,ACPoint(voltage=point.voltage,currents=bad)).passed
            end
        end
        @test net==original
    end
end

@testset "Every supported IBR operating bound rejects a fixed witness" begin
    for m in (2,3,4),reverse in (false,true)
        net,point,sp,si=_ibr_state(m;reverse)
        for key in ("p_min","p_max","q_min","q_max","i_max","p_avail","p_dc_min","p_dc_max");delete!(net["ibr"]["g"],key);end
        # Keep s_max required but loose; other bounds enter individually.
        tm=net["ibr"]["g"]["terminal_map"];ci=point.currents[(:ibr,"g")]
        terminal=m==3 ? ci : [ci;-sum(ci)]
        fields=[("p_min",real.(sp)),("p_max",real.(sp)),("q_min",imag.(sp)),("q_max",imag.(sp)),
            ("s_max",abs.(sp)),("i_max",abs.(terminal)),("p_dc_min",sum(real,si)),("p_dc_max",sum(real,si))]
        reverse || push!(fields,("p_avail",sum(real,sp)))
        m==3 || push!(fields,("i_max",abs.(ci)))
        for specialization in (:off,:conductor_difference),(field,values) in fields
            lower=endswith(field,"min");mag=field in ("s_max","i_max","p_avail")
            x=values isa Number ? [values] : values;delta=max.(.2abs.(x),.1)
            loose=lower ? x.-delta : x.+delta
            safe=deepcopy(net);safe["ibr"]["g"][field]=values isa Number ? only(loose) : loose
            @test ivr_nlp_point_report(build_opf(safe,IVRNLP(;specialization)),point).passed
            @test _ibr_audit(safe,point).passed
            for k in eachindex(x)
                bad=deepcopy(safe);tight=copy(loose);tight[k]=lower ? x[k]+delta[k] : mag ? max(0.,x[k]-delta[k]) : x[k]-delta[k]
                bad["ibr"]["g"][field]=values isa Number ? only(tight) : tight
                b=build_opf(bad,IVRNLP(;specialization));report=ivr_nlp_point_report(b,point)
                @test !report.passed
                @test report.max_binding_residual_pu<1e-7 && report.max_reconstruction_residual_pu<1e-7
                audit=_ibr_audit(bad,point);@test !audit.passed
                @test [r.label for r in audit.records if r.residual>getproperty(audit.tolerances,r.unit)]==["ibr/g/$field"]
            end
        end
    end
end

@testset "IBR dispatch costs, availability and internal loss budget" begin
    net,_,_,_=_ibr_state(2)
    d=net["ibr"]["g"];d["p_min"]=[0.];d["p_max"]=[1000.];d["q_min"]=[0.];d["q_max"]=[0.];d["p_avail"]=500.;d["cost"]=[-1.]
    net["voltage_source"]["source"]["cost"]=[0.]
    b=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);r=_ibr_solve(b)
    @test r.solve.optimal && physical_residuals(net,r).passed
    @test real(only(r.powers[(:ibr,"g")])) ≈ 500 atol=1e-4
    @test r.objective ≈ -.5 atol=1e-6
    d["cost"]=[1.];r=_ibr_solve(build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer))
    @test r.solve.optimal
    @test abs(real(only(r.powers[(:ibr,"g")])))<1e-4
    d["cost"]=[-1.];d["p_dc_max"]=300.
    r=_ibr_solve(build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer))
    @test r.solve.optimal && physical_residuals(net,r).passed
    @test real(only(r.powers[(:ibr_internal,"g")])) ≈ 300 atol=1e-4
    @test real(only(r.powers[(:ibr,"g")]))<300
end

@testset "IBR internal-voltage setpoints and zero budgets" begin
    net,_,_,_=_ibr_state(2)
    delete!(net,"line");delete!(net,"load");delete!(net["bus"],"b1")
    d=net["ibr"]["g"];d["bus"]="b0";d["p_min"]=[230.];d["p_max"]=[230.]
    d["q_min"]=[-500.];d["q_max"]=[500.];d["s_max"]=[2000.]
    d["grid_forming"]=true
    expected_i=1-.2im;expected_j=expected_i+.001im*230
    d["v_ref_internal"]=abs(230+(.2+.08im)*expected_j)
    build=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);r=_ibr_solve(build)
    @test r.solve.optimal && physical_residuals(net,r).passed
    @test only(r.current_candidate[(:ibr,"g")]) ≈ expected_i atol=1e-5
    point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
    for factor in (.9,1.1)
        bad=deepcopy(net);bad["ibr"]["g"]["v_ref_internal"]*=factor
        @test !ivr_nlp_point_report(build_opf(bad,IVRNLP()),point).passed
        @test !_ibr_audit(bad,point).passed
    end
    # A filter-free fixed source already supplies this voltage equality.
    d["r_filter"]=[0.];d["x_filter"]=[0.];d["b_filter_shunt"]=0.;d["v_ref_internal"]=230.
    d["q_min"]=[0.];d["q_max"]=[0.]
    @test _ibr_solve(build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer)).solve.optimal
    d["v_ref_internal"]=231.
    @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
    # Shared-link zero active budget counts internal filter loss. With fixed
    # reactive injection it requires active absorption at PCC.
    delete!(d,"grid_forming");delete!(d,"v_ref_internal")
    d["r_filter"]=[1.];d["p_min"]=[-100.];d["p_max"]=[100.];d["q_min"]=[200.];d["q_max"]=[200.]
    d["p_dc_min"]=0.;d["p_dc_max"]=0.;d["p_avail"]=0.
    r=_ibr_solve(build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer))
    @test r.solve.optimal && physical_residuals(net,r).passed
    @test abs(real(only(r.powers[(:ibr_internal,"g")])))<1e-6
    @test real(only(r.powers[(:ibr,"g")])) < -.1
    for m in (2,3,4),field in ("s_max","i_max","p_avail")
        n,p,_,_=_ibr_state(m);value=n["ibr"]["g"][field]
        n["ibr"]["g"][field]=value isa Number ? 0. : zero.(value)
        @test !ivr_nlp_point_report(build_opf(n,IVRNLP()),p).passed
        @test !_ibr_audit(n,p).passed
    end
end

@testset "IBR scope, validation and load reuse" begin
    net,_,_,_=_ibr_state(4)
    for (field,value) in (("control_profile","unexecuted"),("voltage_aggregation","AVERAGE"),("dc_bus","dc"),
        ("dc_control","V"),("grid_forming",1),("dc_link_coupled","true"),("p_avail",-1.),("p_avail",true),
        ("s_max",1000.),("s_max",[1.,2.]),("i_max",[-1.,1.,1.,1.]),("p_min",[Inf,0.,0.]),
        ("p_min",[1.,2.]),("r_filter",[-1.,0.,0.]),("x_filter",[NaN,0.,0.]),("b_filter_shunt",false),
        ("p_dc_min",1e6),("p_dc_min","zero"),("v_ref_internal",230.),("grid_forming",true),
        ("topology","UNKNOWN"),("terminal_map",["a","b","c"]))
        bad=deepcopy(net);bad["ibr"]["g"][field]=value
        @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    end
    bad=deepcopy(net);bad["ibr"]["g"]["dc_link_coupled"]=false
    @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    bad=deepcopy(net);bad["ibr"]["g"]["energy_cost_rate"]=[1.,1.,1.]
    @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    for key in ("bus","terminal_map","topology","s_max")
        bad=deepcopy(net);delete!(bad["ibr"]["g"],key)
        @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    end
    d=net["ibr"]["g"];d["energy_cost_rate"]=pop!(d,"cost")
    b=build_opf(net,IVRNLP(specialization=:conductor_difference);optimizer=Ipopt.Optimizer)
    variables=all_variables(b.model);load=net["load"]["d1"]
    for factor in (1.,.8,1.1)
        update_ivr_loads!(b,Dict("d1"=>(p=factor*load["p_nom"],q=factor*load["q_nom"])))
        r=_ibr_solve(b);@test r.solve.optimal
        @test physical_residuals(b.network,r).passed
        @test all_variables(b.model)==variables
        @test ivr_nlp_point_report(build_opf(b.network,IVRNLP()),ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
    end
    @test_throws ArgumentError update_ivr_generators!(b,Dict("g"=>(p_max=[1.,1.,1.],)))
    # Implicit earth-return single-phase converter cannot be reduced away.
    earth=deepcopy(net);d=earth["ibr"]["g"]
    d["topology"]="SINGLE_PHASE";d["terminal_map"]=["a"]
    for key in ("s_max","i_max","p_min","p_max","q_min","q_max","r_filter","x_filter","energy_cost_rate");d[key]=[first(d[key])];end
    b=build_opf(earth,IVRNLP(specialization=:conductor_difference))
    @test b.numerical_diagnostics[:specialization_report].code==:earth_return_device
end

@testset "Three-phase IBR internal voltage uses winding-filter coordinates" begin
    for m in (3,4)
        net,_,_,_=_ibr_state(m);delete!(net,"line");delete!(net,"load");delete!(net["bus"],"b1")
        d=net["ibr"]["g"];d["bus"]="b0"
        tm=d["terminal_map"];v=[230cis.([0.,-2pi/3,2pi/3]);m==4 ? [0im] : ComplexF64[]]
        D=m==3 ? [1. -1. 0.;0. 1. -1.;-1. 0. 1.] : [Matrix{Float64}(I,3,3) -ones(3)]
        u=D*v;ci=.01u;it=transpose(D)*ci;jf=ci+.001im.*u;e=u+(.2+.08im).*jf
        port=m==3 ? it : ci;s=(m==3 ? v : u).*conj.(port)
        d["p_min"]=real.(s);d["p_max"]=real.(s);d["q_min"]=fill(-5000.,3);d["q_max"]=fill(5000.,3)
        d["grid_forming"]=true;d["v_ref_internal"]=abs(e[1]);d["cost"]=zeros(3)
        source=-it;m==4 && (source[4]=0im)
        point=ACPoint(voltage=Dict(("b0",t)=>z for (t,z) in zip(tm,v)),
            currents=Dict((:voltage_source,"source")=>source,(:ibr,"g")=>port,(:ibr_internal,"g")=>jf))
        b=build_opf(net,IVRNLP(objective=:feasibility);optimizer=Ipopt.Optimizer)
        @test ivr_nlp_point_report(b,point).passed
        @test _ibr_audit(net,point).passed
        r=_ibr_solve(b);@test r.solve.optimal
        @test physical_residuals(net,r).passed
        for scale in (.9,1.1)
            bad=deepcopy(net);bad["ibr"]["g"]["v_ref_internal"]*=scale
            @test !ivr_nlp_point_report(build_opf(bad,IVRNLP()),point).passed
            @test !_ibr_audit(bad,point).passed
        end
    end
end
