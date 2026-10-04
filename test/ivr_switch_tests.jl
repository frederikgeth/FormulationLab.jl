using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
isdefined(@__MODULE__,:ivr_compiler_case) || include("../examples/ivr_compiler_cases.jl")
isdefined(@__MODULE__,:_sdp_tx_case) || include("sdp_transformer_fixtures.jl")
isdefined(@__MODULE__,:_audit_transformer_state) || include("ac_validation_fixtures.jl")

# Independent circuit witness: choose load coil currents, propagate line KVL,
# then insert an ideal switch with permuted receiving terminal names.
function _switch_state(m;reverse=false,exporting=false)
    net=ivr_compiler_case(conductors=m,segments=1)
    tm=copy(net["bus"]["b0"]["terminal_names"])
    mt=m==2 ? copy(tm) : [reverse!(copy(tm[1:3]));m==4 ? ["n"] : String[]]
    D=m==2 ? [1. -1.] : m==3 ? [1. -1. 0.;0. 1. -1.;-1. 0. 1.] : [Matrix{Float64}(I,3,3) -ones(3)]
    j=ComplexF64[(exporting ? -1 : 1)*(2+.7k)*cis(-.3-2pi*(k-1)/3) for k in axes(D,1)]
    i=transpose(D)*j
    Z=[complex(a==b ? .08+.01a : .01+.001(a+b),a==b ? .04+.002a : .008+.0001(a+b)) for a in 1:m,b in 1:m]
    vf=m==2 ? ComplexF64[230,0] : [230cis.([0.,-2pi/3,2pi/3]);m==4 ? [0im] : ComplexF64[]]
    vt=vf-Z*i
    net["bus"]["mid"]=Dict("terminal_names"=>tm)
    net["line"]["l1"]["bus_to"]="mid"
    net["load"]["d1"]["terminal_map"]=mt
    s=(D*vt).*conj.(j)
    net["load"]["d1"]["p_nom"]=real.(s);net["load"]["d1"]["q_nom"]=imag.(s)
    sw=Dict{String,Any}("bus_from"=>reverse ? "b1" : "mid","bus_to"=>reverse ? "mid" : "b1",
        "terminal_map_from"=>reverse ? mt : tm,"terminal_map_to"=>reverse ? tm : mt,
        "open_switch"=>false,"i_max"=>abs.(i).+1.,"s_max"=>abs.(vt.*conj.(i)).+10.)
    net["switch"]=Dict("s"=>sw)
    voltage=Dict(("b0",t)=>v for (t,v) in zip(tm,vf))
    merge!(voltage,Dict(("mid",t)=>v for (t,v) in zip(tm,vt)),Dict(("b1",t)=>v for (t,v) in zip(mt,vt)))
    source=copy(i);m==3 || (source[end]=0im)
    si=reverse ? -i : i
    currents=Dict((:voltage_source,"source")=>source,(:line_from,"l1")=>i,(:line_to,"l1")=>-i,
        (:load,"d1")=>j,(:switch_from,"s")=>si,(:switch_to,"s")=>-si)
    net,ACPoint(;voltage,currents)
end

_switch_solve(build)=solve_ivr_nlp_opf(build;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,bound_relax_factor=0.))
_switch_point(r)=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)

@testset "Exact fixed switches: independent states, solves and rated channels" begin
    for m in (2,3,4),reverse in (false,true),exporting in (false,true)
        net,point=_switch_state(m;reverse,exporting);original=deepcopy(net)
        for specialization in (:off,:conductor_difference),s_base in (1e3,1e5)
            build=build_opf(net,IVRNLP(;specialization,s_base);optimizer=Ipopt.Optimizer)
            @test build.numerical_diagnostics[:initialization]==:linear_circuit
            @test build.numerical_diagnostics[:specialization]==:off
            specialization==:off || @test build.numerical_diagnostics[:specialization_report].code==:switch_boundary
            @test ivr_nlp_point_report(build,point).passed
            @test physical_residuals(net,point;delta_dispatch=:coil).passed
            r=_switch_solve(build);@test r.solve.optimal
            @test ivr_nlp_point_report(build,_switch_point(r)).passed
            @test physical_residuals(net,_switch_point(r);delta_dispatch=:coil).passed
            for (key,v) in point.voltage;@test r.voltage_candidate[key] ≈ v atol=2e-5;end
            @test r.current_candidate[(:switch_from,"s")] ≈ point.currents[(:switch_from,"s")] atol=2e-5
            @test r.current_candidate[(:switch_to,"s")] ≈ -r.current_candidate[(:switch_from,"s")] atol=1e-9
            for side in (:switch_from,:switch_to)
                changed=deepcopy(point.currents);changed[(side,"s")][1]+=.1
                @test !ivr_nlp_point_report(build,ACPoint(voltage=point.voltage,currents=changed)).passed
                @test !physical_residuals(net,ACPoint(voltage=point.voltage,currents=changed);delta_dispatch=:coil).passed
            end
            missing=deepcopy(point.currents);delete!(missing,(:switch_from,"s"))
            @test !ivr_nlp_point_report(build,ACPoint(voltage=point.voltage,currents=missing)).passed
        end
        sw=net["switch"]["s"];v=[point.voltage[(sw["bus_from"],t)] for t in sw["terminal_map_from"]]
        i=point.currents[(:switch_from,"s")]
        for (field,x) in (("i_max",abs.(i)),("s_max",abs.(v.*conj.(i)))),k in eachindex(i)
            @test x[k]>1e-5 # Includes observable four-wire neutral and its VA.
            bad=deepcopy(net);bad["switch"]["s"][field][k]=.5x[k]
            @test !ivr_nlp_point_report(build_opf(bad,IVRNLP()),point).passed
            report=physical_residuals(bad,point;delta_dispatch=:coil)
            @test !report.passed
            violated=Set(r.label for r in report.records if r.residual>getproperty(report.tolerances,r.unit))
            @test violated==Set(["switch/s/$field","switch/s/to/$field"])
            bad["switch"]["s"][field][k]=0.
            @test !ivr_nlp_point_report(build_opf(bad,IVRNLP()),point).passed
        end
        @test net==original
    end
end

@testset "Open switches isolate independently supplied sections" begin
    net=Dict{String,Any}("bus"=>Dict(b=>Dict("terminal_names"=>["a"]) for b in ("f","t")),
        "voltage_source"=>Dict(b=>Dict("bus"=>b,"terminal_map"=>["a"],"v_magnitude"=>[v],"v_angle"=>[0.]) for (b,v) in (("f",230.),("t",240.))),
        "load"=>Dict(b=>Dict("bus"=>b,"terminal_map"=>["a"],"configuration"=>"SINGLE_PHASE","p_nom"=>[1000.],"q_nom"=>[200.]) for b in ("f","t")),
        "switch"=>Dict("s"=>Dict("bus_from"=>"f","bus_to"=>"t","terminal_map_from"=>["a"],"terminal_map_to"=>["a"],"open_switch"=>true,"i_max"=>[0.],"s_max"=>[0.])))
    build=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);r=_switch_solve(build)
    @test r.solve.optimal
    point=_switch_point(r)
    @test physical_residuals(net,point;delta_dispatch=:coil).passed
    @test ivr_nlp_point_report(build,point).passed
    @test r.voltage_candidate[("f","a")] ≈ 230
    @test r.voltage_candidate[("t","a")] ≈ 240
    @test all(iszero,r.current_candidate[(:switch_from,"s")])
    @test all(iszero,r.current_candidate[(:switch_to,"s")])
    for side in (:switch_from,:switch_to)
        changed=deepcopy(point.currents);changed[(side,"s")][1]=.1
        @test !ivr_nlp_point_report(build,ACPoint(voltage=point.voltage,currents=changed)).passed
    end
    # A closed tie cannot reconcile conflicting ideal source phasors.
    bad=deepcopy(net);bad["switch"]["s"]["open_switch"]=false
    @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    # An open tie supplies neither the disconnected load nor its voltage gauge.
    bad=deepcopy(net);delete!(bad["voltage_source"],"t")
    @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    delete!(bad["load"],"t")
    @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    # Finite earth grounding makes an unloaded disconnected terminal observable.
    bad["shunt"]=Dict("ground"=>Dict("bus"=>"t","terminal_map"=>["a"],"G_1_1"=>.01))
    b=build_opf(bad,IVRNLP();optimizer=Ipopt.Optimizer);a=_switch_solve(b)
    @test a.solve.optimal
    @test abs(a.voltage_candidate[("t","a")])<1e-6
    @test physical_residuals(bad,_switch_point(a);delta_dispatch=:coil).passed
end

@testset "Fixed switch validation, load reuse and transformer composition" begin
    net,point=_switch_state(4)
    for state in (1,"closed",nothing)
        bad=deepcopy(net);bad["switch"]["s"]["open_switch"]=state
        @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    end
    for (field,value) in (("i_max",[-1.,1.,1.,1.]),("s_max",[Inf,1.,1.,1.]),("i_max",[1.]),("status",true),
                          ("terminal_map_to",["a","b","c"]),("terminal_map_to",["a","b","c","missing"]))
        bad=deepcopy(net);bad["switch"]["s"][field]=value
        @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
    end
    # Fixed switch channels survive repeated load RHS changes on one model.
    for field in ("i_max","s_max");net["switch"]["s"][field].*=3;end
    build=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);variables=all_variables(build.model)
    load=net["load"]["d1"]
    for factor in (1.,.7,-.5)
        update_ivr_loads!(build,Dict("d1"=>(p=factor*load["p_nom"],q=factor*load["q_nom"])))
        r=_switch_solve(build)
        @test r.solve.optimal
        @test all_variables(build.model)==variables
        @test physical_residuals(build.network,_switch_point(r);delta_dispatch=:coil).passed
        @test ivr_nlp_point_report(build_opf(build.network,IVRNLP()),_switch_point(r)).passed
    end
    net,point=_audit_transformer_state("single_phase")
    net["bus"]["end"]=Dict("terminal_names"=>["p","n"])
    net["switch"]=Dict("s"=>Dict("bus_from"=>"t","bus_to"=>"end","terminal_map_from"=>["p","n"],"terminal_map_to"=>["p","n"],"open_switch"=>false))
    for load in values(net["load"]);load["bus"]="end";end
    voltage=copy(point.voltage);merge!(voltage,Dict(("end",t)=>point.voltage[("t",t)] for t in ("p","n")))
    currents=deepcopy(point.currents);i=-currents[(:transformer_to,"single_phase/tx")]
    currents[(:switch_from,"s")]=i;currents[(:switch_to,"s")]=-i
    point=ACPoint(;voltage,currents)
    build=build_opf(net,IVRNLP(specialization=:conductor_difference);optimizer=Ipopt.Optimizer)
    @test ivr_nlp_point_report(build,point).passed
    @test physical_residuals(net,point;delta_dispatch=:coil).passed
    r=_switch_solve(build);@test r.solve.optimal
    @test physical_residuals(net,_switch_point(r);delta_dispatch=:coil).passed
end

@testset "Closed switch loops retain current circulation freedom" begin
    net,point=_switch_state(3)
    for field in ("i_max","s_max");delete!(net["switch"]["s"],field);end
    net["switch"]["parallel"]=deepcopy(net["switch"]["s"])
    build=build_opf(net,IVRNLP())
    # The no-load start may choose a minimum-norm current, but the operating
    # circuit must retain every KCL-compatible split, including circulation.
    for circulating in (0im,2-3im,-10+5im)
        currents=deepcopy(point.currents);total=point.currents[(:switch_from,"s")]
        currents[(:switch_from,"s")]=.3total.+circulating
        currents[(:switch_from,"parallel")]=.7total.-circulating
        currents[(:switch_to,"s")]=-currents[(:switch_from,"s")]
        currents[(:switch_to,"parallel")]=-currents[(:switch_from,"parallel")]
        supplied=ACPoint(voltage=point.voltage,currents=currents)
        @test ivr_nlp_point_report(build,supplied).passed
        @test physical_residuals(net,supplied;delta_dispatch=:coil).passed
    end
end
