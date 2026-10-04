using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
if !isdefined(@__MODULE__,:ivr_compiler_case)
    include("../examples/ivr_compiler_cases.jl")
end
_compiler_build(net;specialization=:conductor_difference)=build_opf(net,IVRNLP(;specialization,objective=:source_import);optimizer=Ipopt.Optimizer)
_compiler_solve(b)=solve_ivr_nlp_opf(b;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10))
_compiler_point(r)=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
_compiler_code(net)=_compiler_build(net).numerical_diagnostics[:specialization_report].code

# Manufacture branch/device states by KCL then KVL, derive load setpoints from
# those states. This uses no assembler, coordinate elimination or optimizer.
function _compiler_manufactured(m)
    net=ivr_compiler_case(conductors=m,segments=3,shape=:tree)
    tm=net["bus"]["b0"]["terminal_names"]
    D=m==2 ? [1. -1.] : m==3 ? [1. -1. 0.;0. 1. -1.;-1. 0. 1.] :
        [1. 0. 0. -1.;0. 1. 0. -1.;0. 0. 1. -1.]
    Z=ComplexF64[(a==b ? .08+.01a : .01+.001(a+b))+
        im*(a==b ? .04+.002a : .008+.0001(a+b)) for a in 1:m,b in 1:m]
    load_i=Dict("d$k"=>ComplexF64[(1+.2k)*cis(-.4-2pi*(j-1)/3) for j in axes(D,1)] for k in 1:3)
    branch=Dict("l$k"=>transpose(D)*load_i["d$k"] for k in 1:3)
    branch["l1"]+=branch["l3"]
    source=net["voltage_source"]["source"]
    v=Dict("b0"=>source["v_magnitude"].*cis.(source["v_angle"]))
    for (k,parent) in ((1,0),(2,0),(3,1))
        v["b$k"]=v["b$parent"]-Z*branch["l$k"]
        s=(D*v["b$k"]).*conj.(load_i["d$k"])
        net["load"]["d$k"]["p_nom"]=real.(s);net["load"]["d$k"]["q_nom"]=imag.(s)
    end
    volts=Dict((b,t)=>x[j] for (b,x) in v for (j,t) in enumerate(tm))
    currents=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    for k in 1:3
        currents[(:load,"d$k")]=load_i["d$k"]
        currents[(:line_from,"l$k")]=branch["l$k"]
        currents[(:line_to,"l$k")]=-branch["l$k"]
    end
    source_i=branch["l1"]+branch["l2"]
    m==3 || (source_i[end]=0) # Declared unobserved source/earth allocation.
    currents[(:voltage_source,"source")]=source_i
    net,ACPoint(voltage=volts,currents=currents)
end

@testset "Certified conductor sections and supplied-point equivalence" begin
    for m in (2,3,4)
        net,point=_compiler_manufactured(m)
        full=_compiler_build(net;specialization=:off);reduced=_compiler_build(net)
        @test reduced.numerical_diagnostics[:specialization]==:conductor_difference
        @test reduced.numerical_diagnostics[:specialization_report].code==:radial_zero_sum
        @test num_variables(full.model)-num_variables(reduced.model)==2length(net["line"])
        @test reduced.numerical_diagnostics[:discharged_complex_kcl]==length(net["bus"])-1
        @test physical_residuals(net,point;delta_dispatch=:coil).passed
        f=ivr_nlp_point_report(full,point);r=ivr_nlp_point_report(reduced,point)
        @test f.passed && r.passed
        @test r.objective ≈ f.objective atol=1e-9
        @test ivr_nlp_point_report(full,r.reconstructed_point).passed
        @test ivr_nlp_point_report(reduced,f.reconstructed_point).passed
        @test physical_residuals(net,r.reconstructed_point;delta_dispatch=:coil).passed
        for key in keys(point.voltage)
            @test r.reconstructed_point.voltage[key] ≈ point.voltage[key] atol=1e-11
        end
        for key in keys(point.currents)
            @test r.reconstructed_point.currents[key] ≈ point.currents[key] atol=1e-11
        end
        # Projection must not silently repair a nonzero conductor-current sum.
        bad=deepcopy(point);bad.currents[(:line_from,"l1")][end]+=.1
        rejected=ivr_nlp_point_report(reduced,bad)
        @test !rejected.passed
        @test rejected.max_reconstruction_residual_pu>1e-5
        absent=deepcopy(point);delete!(absent.currents,(:line_to,"l1"))
        @test !ivr_nlp_point_report(reduced,absent).passed
        @test "current/line_to/l1" in ivr_nlp_point_report(reduced,absent).missing_channels
        # Full-space and reduced-space solutions map in both directions.
        fr=_compiler_solve(full);rr=_compiler_solve(reduced)
        @test fr.solve.optimal && rr.solve.optimal
        @test fr.objective ≈ rr.objective atol=1e-5
        @test ivr_nlp_point_report(full,_compiler_point(rr)).passed
        @test ivr_nlp_point_report(reduced,_compiler_point(fr)).passed
    end
end

@testset "Conductor certificate blockers preserve full IVR" begin
    for (change,code) in (
        (net->(net["bus"]["b1"]["perfectly_grounded_terminals"]=["n"]),:downstream_ground),
        (net->(net["shunt"]=Dict("earth"=>Dict("bus"=>"b1","terminal_map"=>["n"],"G_1_1"=>1e-15))),:bus_shunt),
        (net->(net["linecode"]["wire"]["B_from_1_1"]=1e-15),:line_shunt),
        (net->(net["line"]["parallel"]=deepcopy(net["line"]["l1"])),:cycle),
        (net->(net["load"]["d1"]["terminal_map"]=["a"]),:earth_return_device))
        net=ivr_compiler_case(conductors=2,segments=2);change(net)
        @test _compiler_code(net)==code
        reduced=_compiler_build(net);full=_compiler_build(net;specialization=:off)
        @test reduced.numerical_diagnostics[:specialization]==:off
        @test num_variables(reduced.model)==num_variables(full.model)
        @test length(reduced.coordinates.projection)==length(full.coordinates.projection)
    end
    # An explicitly zero shunt does not create an earth path.
    net=ivr_compiler_case(conductors=2)
    net["shunt"]=Dict("zero"=>Dict("bus"=>"b1","terminal_map"=>["n"],"G_1_1"=>0.))
    @test _compiler_code(net)==:radial_zero_sum
    # The root neutral can be fixed by grounding rather than a source terminal.
    net=ivr_compiler_case(conductors=4)
    for key in ("terminal_map","v_magnitude","v_angle")
        net["voltage_source"]["source"][key]=net["voltage_source"]["source"][key][1:3]
    end
    net["load"]["root"]=Dict("bus"=>"b0","terminal_map"=>["a"],
        "configuration"=>"SINGLE_PHASE","p_nom"=>[20.],"q_nom"=>[1.])
    @test _compiler_code(net)==:radial_zero_sum
    b=_compiler_build(net);r=_compiler_solve(b)
    @test r.solve.optimal && physical_residuals(net,_compiler_point(r);delta_dispatch=:coil).passed
    # A finite root ground must remain finite; neither model fixes its voltage.
    net["bus"]["b0"]["perfectly_grounded_terminals"]=String[]
    net["shunt"]=Dict("root_ground"=>Dict("bus"=>"b0","terminal_map"=>["n"],"G_1_1"=>5.))
    b=_compiler_build(net);f=_compiler_build(net;specialization=:off)
    r=_compiler_solve(b);fr=_compiler_solve(f)
    @test b.numerical_diagnostics[:specialization]==:conductor_difference
    @test r.solve.optimal && fr.solve.optimal
    @test abs(r.voltage_candidate[("b0","n")])>1e-3
    @test r.objective ≈ fr.objective atol=1e-5
    @test physical_residuals(net,_compiler_point(r);delta_dispatch=:coil).passed
    @test ivr_nlp_point_report(f,_compiler_point(r)).passed
    @test ivr_nlp_point_report(b,_compiler_point(fr)).passed
    # An additional fixed source changes the boundary even at today's no-load voltage.
    net=ivr_compiler_case(conductors=4)
    net["voltage_source"]["other"]=deepcopy(net["voltage_source"]["source"])
    net["voltage_source"]["other"]["bus"]="b1"
    @test _compiler_code(net)==:multiple_sources
    @test_throws ArgumentError build_opf(net,IVRNLP(specialization=:unknown))
end

@testset "Terminal order, branch reversal and reduced family reuse" begin
    for m in (2,3,4)
        net=ivr_compiler_case(conductors=m,segments=3)
        # Reverse branch orientation; the impedance matrix is reciprocal.
        l=net["line"]["l2"];l["bus_from"],l["bus_to"]=l["bus_to"],l["bus_from"]
        # Rename terminals at a bus and permute its declaration, keeping each
        # physical connection. Coordinate detection cannot rely on bus sorting.
        old=copy(net["bus"]["b2"]["terminal_names"])
        rename=Dict(t=>(t=="n" ? "n" : "phase_$(j)") for (j,t) in enumerate(old))
        net["bus"]["b2"]["terminal_names"]=reverse([rename[t] for t in old])
        for l in values(net["line"]),side in ("from","to")
            l["bus_$side"]=="b2" && (l["terminal_map_$side"]=[rename[t] for t in l["terminal_map_$side"]])
        end
        net["load"]["d2"]["terminal_map"]=[rename[t] for t in net["load"]["d2"]["terminal_map"]]
        build=_compiler_build(net);vars=all_variables(build.model)
        @test build.numerical_diagnostics[:specialization]==:conductor_difference
        for factor in (1.,0.,-.5)
            update_ivr_loads!(build,Dict(id=>(p=factor*d["p_nom"],q=factor*d["q_nom"]) for (id,d) in net["load"]))
            r=_compiler_solve(build)
            full=_compiler_build(build.network;specialization=:off);f=_compiler_solve(full)
            @test r.solve.optimal && f.solve.optimal
            @test r.objective ≈ f.objective atol=1e-5
            @test ivr_nlp_point_report(full,_compiler_point(r)).passed
            @test physical_residuals(build.network,_compiler_point(r);delta_dispatch=:coil).passed
            @test all_variables(build.model)==vars
            @test build.numerical_diagnostics[:assembly_count]==1
            @test build.numerical_diagnostics[:structure_analysis_count]==1
        end
    end
end

@testset "Reduced IVR preserves binding neutral and phase-ground limits" begin
    for limit in (:current,:neutral,:phase_ground,:line_apparent)
        net=ivr_compiler_case(conductors=2,segments=1)
        d=net["load"]["d1"]
        net["voltage_source"]["source"]["cost"]=[0.]
        net["generator"]=Dict("g"=>Dict("bus"=>"b1","terminal_map"=>["a","n"],
            "configuration"=>"SINGLE_PHASE","p_min"=>[0.],"p_max"=>[20_000.],
            "q_min"=>d["q_nom"],"q_max"=>d["q_nom"],"cost"=>[-1.],"s_max"=>[25_000.],"i_max"=>[150.]))
        limit==:current && (net["line"]["l1"]["i_max"]=[200.,1.])
        limit==:neutral && (net["bus"]["b1"]["vn_max"]=[.1])
        limit==:phase_ground && (net["bus"]["b1"]["v_max"]=[230.1,30.])
        limit==:line_apparent && (net["line"]["l1"]["s_max"]=[250.])
        full=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer)
        reduced=build_opf(net,IVRNLP(specialization=:conductor_difference);optimizer=Ipopt.Optimizer)
        f=_compiler_solve(full);r=_compiler_solve(reduced)
        @test f.solve.optimal && r.solve.optimal
        @test r.objective ≈ f.objective atol=1e-5
        @test physical_residuals(net,_compiler_point(r);delta_dispatch=:coil).passed
        @test ivr_nlp_point_report(full,_compiler_point(r)).passed
        @test ivr_nlp_point_report(reduced,_compiler_point(f)).passed
        limit==:current && @test abs(r.current_candidate[(:line_from,"l1")][2]) ≈ 1. atol=1e-5
        limit==:neutral && @test abs(r.voltage_candidate[("b1","n")]) ≈ .1 atol=1e-6
        limit==:phase_ground && @test abs(r.voltage_candidate[("b1","a")]) ≈ 230.1 atol=1e-6
        limit==:line_apparent && @test maximum(abs(r.powers[(side,"l1")][1]) for side in (:line_from,:line_to)) ≈ 250. atol=1e-4
    end
end

@testset "Reduced IVR preserves binding delta-leg limits" begin
    for m in (3,4)
        net=ivr_compiler_case(conductors=m,segments=1)
        net["voltage_source"]["source"]["cost"]=zeros(3)
        net["generator"]=Dict("delta"=>Dict("bus"=>"b1","terminal_map"=>["a","b","c"],
            "configuration"=>"DELTA","p_min"=>zeros(3),"p_max"=>[20_000.,0.,0.],
            "q_min"=>zeros(3),"q_max"=>zeros(3),"cost"=>[-1.,0.,0.],"i_max"=>[1.,150.,150.]))
        full=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer)
        reduced=build_opf(net,IVRNLP(specialization=:conductor_difference);optimizer=Ipopt.Optimizer)
        f=_compiler_solve(full);r=_compiler_solve(reduced)
        @test reduced.numerical_diagnostics[:specialization]==:conductor_difference
        @test f.solve.optimal && r.solve.optimal
        @test r.objective ≈ f.objective atol=1e-5
        @test physical_residuals(net,_compiler_point(r);delta_dispatch=:coil).passed
        @test ivr_nlp_point_report(full,_compiler_point(r)).passed
        @test ivr_nlp_point_report(reduced,_compiler_point(f)).passed
        @test abs(r.current_candidate[(:generator,"delta")][1]) ≈ 1. atol=1e-6
    end
end
