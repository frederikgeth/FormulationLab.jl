using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra, Clarabel, JSON3
isdefined(@__MODULE__,:ivr_compiler_case) || include("../examples/ivr_compiler_cases.jl")

# Construct a loaded capacitor feeder independently by solving its linear
# voltage equation for chosen CP-load currents. No formulation stamp is used.
function _capacitor_state(m;bank=true,loading=1.)
    net=ivr_compiler_case(conductors=m,segments=1)
    tm=net["bus"]["b1"]["terminal_names"]
    D=m==2 ? [1. -1.] : m==3 ? [1. -1. 0.;0. 1. -1.;-1. 0. 1.] : [Matrix{Float64}(I,3,3) -ones(3)]
    nc=size(D,1);cfg=m==2 ? "SINGLE_PHASE" : m==3 ? "DELTA" : "WYE"
    vcoil=m==3 ? sqrt(3)*230 : 230.
    q=bank ? fill(1200/nc,nc) : 100 .* collect(1.:nc)
    b=q./vcoil^2
    cap=Dict("bus"=>"b1","terminal_map"=>copy(tm),"configuration"=>cfg,
        "q_rated"=>bank ? 1200. : q,"v_nom"=>bank && m==4 ? sqrt(3)*230 : vcoil)
    net["capacitor"]=Dict("c"=>cap)
    jl=ComplexF64[loading*(3+.7k)*cis(-.4-2pi*(k-1)/3) for k in 1:nc]
    Z=[complex(a==b ? .08+.01a : .01+.001(a+b),a==b ? .04+.002a : .008+.0001(a+b)) for a in 1:m,b in 1:m]
    vf=m==2 ? ComplexF64[230,0] : [230cis.([0.,-2pi/3,2pi/3]);m==4 ? [0im] : ComplexF64[]]
    Y=im*transpose(D)*Diagonal(b)*D
    vt=(I+Z*Y)\(vf-Z*transpose(D)*jl)
    jc=im.*b.*(D*vt);i=transpose(D)*jl+Y*vt
    s=(D*vt).*conj.(jl)
    net["load"]["d1"]["p_nom"]=real.(s);net["load"]["d1"]["q_nom"]=imag.(s)
    voltage=Dict(("b0",t)=>v for (t,v) in zip(tm,vf));merge!(voltage,Dict(("b1",t)=>v for (t,v) in zip(tm,vt)))
    source=copy(i);m==3 || (source[end]=0im)
    currents=Dict((:voltage_source,"source")=>source,(:line_from,"l1")=>i,(:line_to,"l1")=>-i,(:load,"d1")=>jl,(:capacitor,"c")=>jc)
    net,ACPoint(;voltage,currents),D,b
end

_cap_solve(b)=solve_ivr_nlp_opf(b;solver_options=(print_level=0,tol=1e-11,constr_viol_tol=1e-11))
_cap_point(r)=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)

@testset "Exact capacitors: bank and coil ratings on full/reduced feeders" begin
    for m in (2,3,4),bank in (false,true),loading in (1.,-.5)
        net,point,D,b=_capacitor_state(m;bank,loading);original=deepcopy(net)
        for specialization in (:off,:conductor_difference),s_base in (1e3,1e5)
            build=build_opf(net,IVRNLP(;specialization,s_base);optimizer=Ipopt.Optimizer)
            @test build.numerical_diagnostics[:initialization]==:linear_circuit
            @test build.numerical_diagnostics[:specialization]==specialization
            @test physical_residuals(net,point;delta_dispatch=:coil).passed
            @test ivr_nlp_point_report(build,point).passed
            result=_cap_solve(build);@test result.solve.optimal
            @test physical_residuals(net,_cap_point(result);delta_dispatch=:coil).passed
            @test ivr_nlp_point_report(build,_cap_point(result)).passed
            for (key,v) in point.voltage;@test result.voltage_candidate[key] ≈ v atol=2e-5;end
            @test result.current_candidate[(:capacitor,"c")] ≈ point.currents[(:capacitor,"c")] atol=2e-6
            bad=deepcopy(point.currents);bad[(:capacitor,"c")][1]+=.1
            @test !ivr_nlp_point_report(build,ACPoint(voltage=point.voltage,currents=bad)).passed
            @test !physical_residuals(net,ACPoint(voltage=point.voltage,currents=bad);delta_dispatch=:coil).passed
            # Every retained line-current entry still bounds total current,
            # which includes the capacitor contribution and neutral return.
            for k in 1:m
                abs(point.currents[(:line_from,"l1")][k])>1e-5 || continue
                tight=deepcopy(net);tight["line"]["l1"]["i_max"]=fill(1e4,m)
                tight["line"]["l1"]["i_max"][k]=.5abs(point.currents[(:line_from,"l1")][k])
                @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(;specialization,s_base)),point).passed
                @test !physical_residuals(tight,point;delta_dispatch=:coil).passed
            end
        end
        @test net==original
    end
end

@testset "Nameplate Q is total at nominal voltage, with voltage-squared response" begin
    for cfg in ("SINGLE_PHASE","WYE","DELTA"),scale in (0.,.8,1.,1.1),bank in (false,true)
        tm=cfg=="SINGLE_PHASE" ? ["a","n"] : cfg=="WYE" ? ["a","b","c","n"] : ["a","b","c"]
        n=cfg=="SINGLE_PHASE" ? 1 : 3
        volts=n==1 ? ComplexF64[230scale,0] : [230scale*cis.([0.,-2pi/3,2pi/3]);cfg=="WYE" ? [0im] : ComplexF64[]]
        # A separate nonzero fixed bus keeps a valid voltage base when the
        # capacitor bus is exactly de-energized.
        capvn=cfg=="SINGLE_PHASE" ? 230. : sqrt(3)*230
        net=Dict{String,Any}("bus"=>Dict("b"=>Dict("terminal_names"=>tm,"perfectly_grounded_terminals"=>cfg=="DELTA" ? String[] : ["n"]),
            "ref"=>Dict("terminal_names"=>["a"])),
            "voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>tm,"v_magnitude"=>abs.(volts),"v_angle"=>angle.(volts)),
                "ref"=>Dict("bus"=>"ref","terminal_map"=>["a"],"v_magnitude"=>[230.],"v_angle"=>[0.])),
            "capacitor"=>Dict("c"=>Dict("bus"=>"b","terminal_map"=>tm,"configuration"=>cfg,
                "q_rated"=>bank ? 1500. : fill(1500/n,n),"v_nom"=>bank ? capvn : cfg=="WYE" ? 230. : capvn)))
        build=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);r=_cap_solve(build)
        @test r.solve.optimal
        @test sum(r.powers[(:capacitor,"c")]) ≈ -1500im*scale^2 atol=1e-6
        @test physical_residuals(net,_cap_point(r);delta_dispatch=:coil).passed
        @test ivr_nlp_point_report(build,_cap_point(r)).passed
        # Source-preserving JSON boundary must retain rating interpretation.
        @test ivr_nlp_point_report(build_opf(read_bmopf(JSON3.write(net)),IVRNLP()),_cap_point(r)).passed
    end
end

@testset "Capacitor boundaries, earth paths and reusable loads" begin
    net,point,_,_=_capacitor_state(4)
    for (field,value) in (("q_rated",-1.),("q_rated",Inf),("q_rated",true),("q_rated",[1.,-2.,3.]),
                          ("q_rated",[1.]),("q_rated","1200"),("v_nom",0.),("v_nom",false),("v_nom",[230.,230.,230.]),
                          ("configuration","unknown"),("s_max",[100.,100.,100.]),("i_max",[1.,1.,1.]),("open_switch",true))
        bad=deepcopy(net);bad["capacitor"]["c"][field]=value
        @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    end
    for field in ("q_rated","v_nom","configuration")
        bad=deepcopy(net);delete!(bad["capacitor"]["c"],field)
        @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    end
    # Scalar three-phase bank data cannot silently describe a partial bank.
    bad=deepcopy(net);bad["capacitor"]["c"]["terminal_map"]=["a","n"]
    @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    # Explicit per-coil ratings can describe a partial wye bank.
    bad["capacitor"]["c"]["q_rated"]=[100.];bad["capacitor"]["c"]["v_nom"]=[230.]
    @test build_opf(bad,IVRNLP()) isa IVRNLPBuild
    # A phase-earth capacitor destroys downstream zero-sum current structure.
    earth=deepcopy(net);cap=earth["capacitor"]["c"]
    cap["configuration"]="SINGLE_PHASE";cap["terminal_map"]=["a"];cap["v_nom"]=230.
    build=build_opf(earth,IVRNLP(specialization=:conductor_difference);optimizer=Ipopt.Optimizer)
    @test build.numerical_diagnostics[:specialization]==:off
    @test build.numerical_diagnostics[:specialization_report].code==:earth_return_device
    r=_cap_solve(build);@test r.solve.optimal
    @test physical_residuals(earth,_cap_point(r);delta_dispatch=:coil).passed
    # A zero-rated earth bank still has a declared earth connection; no
    # operating-point-specific reduction rule is inferred from its zero Q.
    cap["q_rated"]=0.
    @test build_opf(earth,IVRNLP(specialization=:conductor_difference)).numerical_diagnostics[:specialization]==:off
    build=build_opf(net,IVRNLP(specialization=:conductor_difference);optimizer=Ipopt.Optimizer)
    variables=all_variables(build.model);d=net["load"]["d1"]
    for factor in (1.,0.,-.5)
        update_ivr_loads!(build,Dict("d1"=>(p=factor*d["p_nom"],q=factor*d["q_nom"])))
        r=_cap_solve(build);@test r.solve.optimal
        @test all_variables(build.model)==variables
        @test physical_residuals(build.network,_cap_point(r);delta_dispatch=:coil).passed
        @test ivr_nlp_point_report(build_opf(build.network,IVRNLP()),_cap_point(r)).passed
    end
    # Coil-voltage vectors and asymmetric ratings retain their former meaning.
    cap=net["capacitor"]["c"];cap["q_rated"]=[100.,200.,300.];cap["v_nom"]=[220.,230.,240.]
    build=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);r=_cap_solve(build)
    @test r.solve.optimal
    u=[r.voltage_candidate[("b1",t)]-r.voltage_candidate[("b1","n")] for t in ("a","b","c")]
    @test r.current_candidate[(:capacitor,"c")] ≈ im.*cap["q_rated"]./cap["v_nom"].^2 .*u atol=1e-6
end

@testset "Scalar bank ratings agree across shared formulation consumers" begin
    for cfg in ("SINGLE_PHASE","WYE","DELTA")
        n=cfg=="SINGLE_PHASE" ? 1 : 3;tm=n==1 ? ["a"] : ["a","b","c"]
        vnom=n==1 ? 230. : sqrt(3)*230
        net=Dict{String,Any}("bus"=>Dict("b"=>Dict("terminal_names"=>tm)),
            "voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>tm,"v_magnitude"=>fill(230.,n),"v_angle"=>n==1 ? [0.] : [0.,-2pi/3,2pi/3])),
            "capacitor"=>Dict("c"=>Dict("bus"=>"b","terminal_map"=>tm,"configuration"=>cfg,"q_rated"=>1500.,"v_nom"=>vnom)))
        for form in (IVRSDP(),IVRSOC(),BranchFlowSDP(),LinIVR())
            r=solve_opf(net,form;optimizer=Clarabel.Optimizer,solver_options=(verbose=false,tol_feas=1e-9,tol_gap_abs=1e-9,tol_gap_rel=1e-9))
            @test r.solve.optimal
            powers=hasproperty(r,:relaxed_powers) ? r.relaxed_powers : r.powers
            @test sum(powers[(:capacitor,"c")]) ≈ -1500im atol=1e-3
        end
        # L3F lowers into the same physical susceptance, while retaining its
        # distinct approximate network equations. Compare the lowered matrix.
        lowered=deepcopy(net);findings=FormulationLab.L3FFinding[]
        FormulationLab._l3f_lower_capacitors!(findings,lowered)
        @test !any(f->startswith(f.code,"E."),findings)
        sh=only(values(lowered["shunt"]))
        D=cfg=="DELTA" ? [1. -1. 0.;0. 1. -1.;-1. 0. 1.] : Matrix{Float64}(I,n,n)
        coilb=cfg=="DELTA" ? 1500/(3vnom^2) : cfg=="WYE" ? 1500/vnom^2 : 1500/230^2
        expected=coilb*transpose(D)*D
        for i in 1:n,j in i:n;@test get(sh,"B_$(i)_$(j)",0.) ≈ expected[i,j];end
    end
end
