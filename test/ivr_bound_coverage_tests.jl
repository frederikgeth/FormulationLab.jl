using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
isdefined(@__MODULE__, :ivr_compiler_case) || include("../examples/ivr_compiler_cases.jl")
isdefined(@__MODULE__, :_sdp_tx_case) || include("sdp_transformer_fixtures.jl")
isdefined(@__MODULE__, :_audit_transformer_state) || include("ac_validation_fixtures.jl")

# Hold a feasible physical state fixed. Change one array entry at a time and
# require both the actual NLP and the independent SI auditor to detect exactly
# that limit. This does not infer coverage from the number of constraints.
function _bound_probe(net, point, select, field, values, label;
                      specialization=:off, s_base=1e4, lower=endswith(field,"_min"))
    x=Float64.(values);margin=max.(.2abs.(x),.1)
    magnitude=!(field in ("p_min","p_max","q_min","q_max"))
    loose=lower ? x.-margin : x.+margin
    lower && startswith(field,"v") && (loose=max.(loose,0.))
    safe=deepcopy(net);select(safe)[field]=loose
    options=IVRNLP(;specialization,s_base,objective=:feasibility)
    @test ivr_nlp_point_report(build_opf(safe,options),point).passed
    @test physical_residuals(safe,point;delta_dispatch=:coil).passed
    for k in eachindex(x)
        # A nonnegative upper bound cannot exclude a zero magnitude.
        magnitude && !lower && x[k]<=1e-5 && continue
        bad=deepcopy(safe)
        select(bad)[field][k]=lower ? x[k]+margin[k] : magnitude ? max(0.,x[k]-margin[k]) : x[k]-margin[k]
        report=ivr_nlp_point_report(build_opf(bad,options),point)
        @test !report.passed
        @test report.max_binding_residual_pu < 1e-7
        @test report.max_reconstruction_residual_pu < 1e-7
        physical=physical_residuals(bad,point;delta_dispatch=:coil)
        @test !physical.passed
        @test isempty(physical.unassessed)
        violated=[r.label for r in physical.records if r.residual>getproperty(physical.tolerances,r.unit)]
        @test !isempty(violated) && all(==(label*"/"*field),violated)
    end
end

function _bound_case(m;shunts=false,direction=1)
    net=ivr_compiler_case(conductors=m,segments=2)
    # Unequal generation keeps all sequence and neutral channels observable.
    tm=m==2 ? ["a","n"] : m==3 ? ["a","b","c"] : ["a","b","c","n"]
    p=direction.*(m==2 ? [300.] : [300.,110.,50.]);q=.3p
    for load in values(net["load"])
        load["p_nom"] .*= direction;load["q_nom"] .*= direction
    end
    net["generator"]=Dict("g"=>Dict("bus"=>"b2","terminal_map"=>tm,
        "configuration"=>m==2 ? "SINGLE_PHASE" : m==3 ? "DELTA" : "WYE",
        "p_min"=>p,"p_max"=>p,"q_min"=>q,"q_max"=>q))
    if shunts
        code=net["linecode"]["wire"]
        for k in 1:m
            code["G_from_$(k)_$(k)"]=.001k
            code["B_to_$(k)_$(k)"]=.002k
        end
    end
    result=solve_opf(net,IVRNLP(objective=:feasibility);optimizer=Ipopt.Optimizer,
        solver_options=(print_level=0,tol=1e-11,constr_viol_tol=1e-11,bound_relax_factor=0.))
    @test result.solve.optimal
    point=ACPoint(voltage=result.voltage_candidate,currents=result.current_candidate)
    @test physical_residuals(net,point;delta_dispatch=:coil).passed
    # Strip existing operational limits, keeping the very same feasible state.
    for d in values(net["bus"]),key in collect(keys(d))
        (endswith(key,"_min") || endswith(key,"_max")) && delete!(d,key)
    end
    for key in ("p_min","p_max","q_min","q_max");delete!(net["generator"]["g"],key);end
    delete!(net["linecode"]["wire"],"i_max")
    net,point
end

@testset "IVR operational bound inventory: buses, sources, generators and lines" begin
    for m in (2,3,4)
        net,point=_bound_case(m)
        tm=net["bus"]["b2"]["terminal_names"];np=m==2 ? 1 : 3
        v=[point.voltage[("b2",t)] for t in tm];vn=m==3 ? 0im : v[end]
        vp=v[1:np];vpn=vp.-vn
        pp=np==1 ? ComplexF64[] : [vp[1]-vp[2],vp[2]-vp[3],vp[3]-vp[1]]
        a=cis(2pi/3)
        for specialization in (:off,:conductor_difference),s_base in (1e3,1e5)
            probe(select,field,x,label;kwargs...)=_bound_probe(net,point,select,field,x,label;specialization,s_base,kwargs...)
            bus=n->n["bus"]["b2"]
            for (prefix,x) in (("v",v),("v",vp),("vpn",vpn),("vpp",pp))
                isempty(x) && continue
                for suffix in ("min","max");probe(bus,prefix*"_"*suffix,abs.(x),"bus/b2");end
            end
            m==3 || probe(bus,"vn_max",[abs(vn)],"bus/b2")
            if np==3
                pos=abs((vpn[1]+a*vpn[2]+a^2*vpn[3])/3)
                neg=abs((vpn[1]+a^2*vpn[2]+a*vpn[3])/3);zero=abs(sum(vpn)/3)
                for (field,value) in (("vpos_min",pos),("vpos_max",pos),("vneg_max",neg),("vzero_max",zero))
                    probe(bus,field,[value],"bus/b2")
                end
            end
            source=n->n["voltage_source"]["source"]
            sv=[point.voltage[("b0",t)] for t in tm];si=point.currents[(:voltage_source,"source")];ss=sv.*conj.(si)
            gen=n->n["generator"]["g"]
            gi=point.currents[(:generator,"g")];gu=m==3 ? pp : vpn;gs=gu.*conj.(gi)
            for (select,s,label) in ((source,ss[1:np],"source/source"),(source,ss,"source/source"),(gen,gs,"generator/g"))
                for (field,x) in (("p_min",real.(s)),("p_max",real.(s)),("q_min",imag.(s)),("q_max",imag.(s)))
                    probe(select,field,x,label)
                end
            end
            probe(source,"s_max",abs.(ss[1:np]),"source/source")
            if m==3
                probe(source,"i_max",abs.(si),"source/source")
            else
                grounded=deepcopy(net);source(grounded)["i_max"]=fill(100.,m)
                @test_throws IVRNLPInapplicableError build_opf(grounded,IVRNLP(;specialization))
            end
            probe(gen,"s_max",abs.(gs),"generator/g")
            probe(gen,"i_max",abs.(gi),"generator/g")
            m==3 || probe(gen,"i_max",abs.([gi;-sum(gi)]),"generator/g")
            # With no shunts both current ends tie; the independent auditor
            # records both. Endpoint-isolating probes are tested below.
            for field in ("i_max","s_max")
                i=point.currents[(:line_from,"l1")]
                x=field=="i_max" ? abs.(i) : abs.([point.voltage[("b0",t)] for t in tm[1:np]].*conj.(i[1:np]))
                for select in (n->n["line"]["l1"],n->n["linecode"]["wire"])
                    safe=deepcopy(net);select(safe)[field]=x.+1.
                    @test ivr_nlp_point_report(build_opf(safe,IVRNLP(;specialization,s_base)),point).passed
                    select(safe)[field].=0.
                    @test !ivr_nlp_point_report(build_opf(safe,IVRNLP(;specialization,s_base)),point).passed
                    @test !physical_residuals(safe,point;delta_dispatch=:coil).passed
                end
            end
        end
    end
end

@testset "Line endpoint totals, linecode inheritance and overrides" begin
    net,point=_bound_case(4;shunts=true)
    d=net["line"]["l1"];tm=d["terminal_map_from"]
    for field in ("i_max","s_max")
        xf=abs.(point.currents[(:line_from,"l1")]);xt=abs.(point.currents[(:line_to,"l1")])
        if field=="s_max"
            xf=xf[1:3].*abs.([point.voltage[("b0",t)] for t in tm[1:3]])
            xt=xt[1:3].*abs.([point.voltage[("b1",t)] for t in tm[1:3]])
        end
        for k in eachindex(xf)
            abs(xf[k]-xt[k])>.01 || continue
            changed=deepcopy(net);limits=max.(xf,xt).+1.;limits[k]=(xf[k]+xt[k])/2
            changed["line"]["l1"][field]=limits
            @test !ivr_nlp_point_report(build_opf(changed,IVRNLP()),point).passed
            report=physical_residuals(changed,point;delta_dispatch=:coil)
            violated=[r.label for r in report.records if r.residual>getproperty(report.tolerances,r.unit)]
            @test violated==["line/l1/$(xf[k]>xt[k] ? "from" : "to")/$field"]
        end
        for (code_limit,line_limit,passed) in ((0.,1e6,true),(1e6,0.,false))
            changed=deepcopy(net);changed["linecode"]["wire"][field]=fill(code_limit,length(xf))
            for line in values(changed["line"]);line[field]=fill(line_limit,length(xf));end
            @test ivr_nlp_point_report(build_opf(changed,IVRNLP()),point).passed==passed
            @test physical_residuals(changed,point;delta_dispatch=:coil).passed==passed
        end
    end
end

@testset "Fixed transformer side and multiwinding coil bounds" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta"),reverse in (false,true)
        net,point=_audit_transformer_state(kind;reverse)
        tx=net["transformer"][kind]["tx"]
        for side in ("from","to");delete!(tx,"i_max_$side");end
        for side in ("from","to")
            delta=kind=="delta_wye" && side=="from" || kind=="wye_delta" && side=="to"
            i=point.currents[(Symbol(delta ? "transformer_coil_$side" : "transformer_$side"),"$kind/tx")]
            _bound_probe(net,point,n->n["transformer"][kind]["tx"],"i_max_$side",abs.(i),"transformer/$kind/tx")
        end
    end
    net,point=_audit_nwinding_state()
    for w in net["transformer"]["n_winding"]["tx"]["windings"];delete!(w,"i_max");end
    for k in 1:4
        select=n->n["transformer"]["n_winding"]["tx"]["windings"][k];w=select(net)
        v=[point.voltage[(w["bus"],t)] for t in w["terminal_map"]]
        u=w["configuration"]=="DELTA" ? [v[1]-v[2],v[2]-v[3],v[3]-v[1]] : v[1:3].-v[4]
        i=point.currents[(:transformer_coil,"n_winding/tx/$k")]
        for (field,x) in (("i_max",abs.(i)),("s_max",abs.(u.*conj.(i))))
            _bound_probe(net,point,select,field,x,"transformer/n_winding/tx/$k")
            # Multiwinding scalar bounds broadcast to every coil.
            changed=deepcopy(net);select(changed)[field]=maximum(x)+1
            @test ivr_nlp_point_report(build_opf(changed,IVRNLP()),point).passed
            @test physical_residuals(changed,point;delta_dispatch=:coil).passed
            select(changed)[field]=0.
            @test !ivr_nlp_point_report(build_opf(changed,IVRNLP()),point).passed
            @test !physical_residuals(changed,point;delta_dispatch=:coil).passed
        end
    end
end

@testset "Sequence limits use phase names before bus storage order" begin
    net,point=_bound_case(4)
    # A network-wide phase vocabulary can include names absent at this bus.
    # Conventional a,b,c ordering still precedes local terminal storage order.
    net["terminal_conventions"]["phase"]=["a","b","c","other"]
    net["bus"]["b2"]["terminal_names"]=["c","b","a","n"]
    v=[point.voltage[("b2",t)]-point.voltage[("b2","n")] for t in ("a","b","c")];a=cis(2pi/3)
    _bound_probe(net,point,n->n["bus"]["b2"],"vpos_min",[abs((v[1]+a*v[2]+a^2*v[3])/3)],"bus/b2")
end

@testset "Signed source and generator boxes in reverse flow" begin
    for m in (2,3,4)
        net,point=_bound_case(m;direction=-1)
        tm=net["bus"]["b2"]["terminal_names"];np=m==2 ? 1 : 3
        v=[point.voltage[("b2",t)] for t in tm]
        u=m==3 ? [v[1]-v[2],v[2]-v[3],v[3]-v[1]] : v[1:np].-v[end]
        gs=u.*conj.(point.currents[(:generator,"g")])
        ss=[point.voltage[("b0",t)] for t in tm[1:np]].*conj.(point.currents[(:voltage_source,"source")][1:np])
        @test all(<(0),real.(gs)) && all(<(0),real.(ss))
        for (family,id,s) in (("generator","g",gs),("voltage_source","source",ss)),specialization in (:off,:conductor_difference)
            label=family=="generator" ? "generator/g" : "source/source"
            for (field,x) in (("p_min",real.(s)),("p_max",real.(s)),("q_min",imag.(s)),("q_max",imag.(s)))
                _bound_probe(net,point,n->n[family][id],field,x,label;specialization)
            end
        end
    end
end

@testset "Line apparent limits retain from-side positions at the receiving end" begin
    # Independently manufacture export through a two-wire line. Renaming the
    # receiving terminals exchanges local phase/neutral labels, not conductor
    # positions. The receiving end alone exceeds the midpoint VA rating.
    net=ivr_compiler_case(conductors=2,segments=1)
    net["line"]["l1"]["terminal_map_to"]=["n","a"]
    net["load"]["d1"]["terminal_map"]=["n","a"]
    for key in ("vpn_min","vpn_max","vn_max");delete!(net["bus"]["b1"],key);end
    Z=[.09+.042im .013+.0083im;.013+.0083im .10+.044im]
    i=ComplexF64[-10+2im,10-2im];vf=ComplexF64[230,0];vt=vf-Z*i
    s=(vt[1]-vt[2])*conj(i[1]);net["load"]["d1"]["p_nom"]=[real(s)];net["load"]["d1"]["q_nom"]=[imag(s)]
    voltage=Dict(("b0","a")=>vf[1],("b0","n")=>vf[2],("b1","n")=>vt[1],("b1","a")=>vt[2])
    currents=Dict((:voltage_source,"source")=>[i[1],0im],(:line_from,"l1")=>i,(:line_to,"l1")=>-i,(:load,"d1")=>[i[1]])
    point=ACPoint(;voltage,currents)
    @test physical_residuals(net,point;delta_dispatch=:coil).passed
    @test ivr_nlp_point_report(build_opf(net,IVRNLP()),point).passed
    sf=abs(vf[1]*conj(i[1]));st=abs(vt[1]*conj(i[1]));@test st>sf+1
    net["line"]["l1"]["s_max"]=[(sf+st)/2]
    @test !ivr_nlp_point_report(build_opf(net,IVRNLP()),point).passed
    report=physical_residuals(net,point;delta_dispatch=:coil)
    @test !report.passed
    @test [r.label for r in report.records if r.residual>getproperty(report.tolerances,r.unit)]==["line/l1/to/s_max"]
end
