using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
isdefined(@__MODULE__,:_sdp_tx_case) || include("sdp_transformer_fixtures.jl")

# SI witness derived from EMF/current conservation; no formulation stamping.
function _ivr_regulator_state(kind; connection="ABBC",rt="B",four=false,reverse=false,excitation=0,rotation=.23)
    net=_sdp_tx_case(kind;tap=1.04);d=net["transformer"][kind]["tx"]
    open=kind=="open_delta_regulator"
    if open && four
        for b in ("f","t");net["bus"][b]["terminal_names"]=["a","b","c","n"];end
        d["terminal_map_from"]=["a","b","c","n"];d["terminal_map_to"]=["a","b","c","n"]
        s=net["voltage_source"]["s"];s["terminal_map"]=["a","b","c","n"]
        push!(s["v_magnitude"],0.);push!(s["v_angle"],0.)
    end
    mf=d["terminal_map_from"];mt=d["terminal_map_to"];n=length(mf)
    net["bus"]["f"]["perfectly_grounded_terminals"]=filter(==("n"),mf)
    net["bus"]["t"]["perfectly_grounded_terminals"]=String[]
    pairs=open ? Dict("ABBC"=>[(1,2),(2,3)],"BCAC"=>[(2,3),(1,3)],"CABA"=>[(3,1),(2,1)])[connection] : [(1,2)]
    bonds=open ? [only(intersect(collect(pairs[1]),collect(pairs[2])));four ? [4] : Int[]] : [2]
    D=[Float64(k==a)-Float64(k==b) for (a,b) in pairs,k in 1:n]
    taps=open ? [1.04,.97] : [1.04];gain=uppercase(rt)=="A" ? inv.(taps) : taps
    d["regulator_type"]=rt;d["tap_ratio"]=open ? taps : only(taps)
    open && (d["connection"]=connection)
    zf=.12+.05im;zt=.03+.015im
    merge!(d,Dict("r_series_from"=>real(zf),"x_series_from"=>imag(zf),"r_series_to"=>real(zt),"x_series_to"=>imag(zt)))
    yf=excitation==1 ? .001-.0003im : 0im;yt=excitation==2 ? .001-.0003im : 0im
    excitation>0 && (d["no_load_shunt"]=Dict("winding"=>excitation,"g"=>.001,"b"=>-.0003))
    s=net["voltage_source"]["s"];s["v_angle"] .+= rotation
    vf=s["v_magnitude"].*cis.(s["v_angle"]);uf=D*vf
    jt=(reverse ? 1 : -1).*(1-.2im).*uf./abs.(uf).*[1+.2k for k in eachindex(uf)]
    jf=-gain.*jt;ut=gain.*(uf-zf*jf)+zt*jt
    M=vcat(D,[Float64(k==b) for b in bonds,k in 1:n]);vt=M\[ut;vf[bonds]]
    jb=open ? [(.35+.15im)*cis(rotation);four ? [-(.35+.15im)*cis(rotation)] : ComplexF64[]] : [0im]
    cf=transpose(D)*(jf+yf*uf);ct=transpose(D)*(jt+yt*ut)
    for (a,k) in enumerate(bonds);cf[k]+=jb[a];ct[k]-=jb[a];end
    voltage=Dict(("f",t)=>v for (t,v) in zip(mf,vf));merge!(voltage,Dict(("t",t)=>v for (t,v) in zip(mt,vt)))
    source=copy(cf);"n" in mf && (source[findfirst(==("n"),mf)]=0)
    key="$kind/tx"
    currents=Dict((:voltage_source,"s")=>source,(:transformer_from,key)=>cf,(:transformer_to,key)=>ct,
        (:transformer_coil_from,key)=>jf,(:transformer_coil_to,key)=>jt,(:transformer_bond,key)=>jb)
    net["load"]=Dict{String,Any}();neutral=findfirst(==("n"),mt)
    for k in 1:(neutral===nothing ? n : n-1)
        id="l$k";tm=neutral===nothing ? [mt[k]] : [mt[k],mt[neutral]]
        u=vt[k]-(neutral===nothing ? 0im : vt[neutral]);load=-ct[k];power=u*conj(load)
        net["load"][id]=Dict("bus"=>"t","terminal_map"=>tm,"configuration"=>"SINGLE_PHASE",
            "model"=>"constant_power","p_nom"=>[real(power)],"q_nom"=>[imag(power)])
        currents[(:load,id)]=[load]
    end
    for (side,c) in (("from",cf),("to",ct));d["i_max_$side"]=max.(abs.(c)*1.1,.01);end
    net,ACPoint(;voltage,currents)
end

_regulator_solve(b)=solve_ivr_nlp_opf(b;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,max_iter=600))

@testset "Autotransformer implicit earth and nonneutral common conductor" begin
    for earth in (true,false),rt in ("A","B")
        net=_sdp_tx_case("single_phase_autotransformer";tap=1.04)
        tm=earth ? ["p"] : ["p","q"]
        for bus in values(net["bus"])
            bus["terminal_names"]=copy(tm);empty!(bus["perfectly_grounded_terminals"])
        end
        d=net["transformer"]["single_phase_autotransformer"]["tx"]
        d["terminal_map_from"]=copy(tm);d["terminal_map_to"]=copy(tm);d["regulator_type"]=rt
        s=net["voltage_source"]["s"];s["terminal_map"]=copy(tm)
        s["v_magnitude"]=earth ? [230.] : [230.,90.]
        s["v_angle"]=earth ? [.2] : [.2,-.4]
        _sdp_zload!(net,"l",tm,.02-.003im)
        b=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);r=_regulator_solve(b)
        @test r.solve.optimal
        vf=230cis(.2);common=earth ? 0im : 90cis(-.4);g=rt=="A" ? 1/1.04 : 1.04
        @test r.voltage_candidate[("t","p")] ≈ common+g*(vf-common) atol=1e-6
        @test physical_residuals(net,r).passed
        @test ivr_nlp_point_report(b,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
        @test haskey(r.current_candidate,(:transformer_bond,"single_phase_autotransformer/tx"))==!earth
        if !earth
            @test r.voltage_candidate[("t","q")] ≈ common atol=1e-6
        end
    end
end

@testset "Exact fixed regulator connections, bonds, excitation and reverse flow" begin
    specs=[("single_phase_autotransformer","ABBC",false);[("open_delta_regulator",c,f) for c in ("ABBC","BCAC","CABA") for f in (false,true)]]
    for (kind,connection,four) in specs,rt in ("A","B"),reverse in (false,true),excitation in (0,1,2)
        net,p=_ivr_regulator_state(kind;connection,four,rt,reverse,excitation);original=deepcopy(net)
        for sb in (1e3,1e5)
            b=build_opf(net,IVRNLP(s_base=sb,specialization=:conductor_difference);optimizer=Ipopt.Optimizer)
            @test b.numerical_diagnostics[:specialization_report].code==:transformer_boundary
            @test ivr_nlp_point_report(b,p).passed
            @test physical_residuals(net,p;delta_dispatch=:coil).passed
            r=_regulator_solve(b);@test r.solve.optimal
            r.solve.optimal || continue
            actual=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test physical_residuals(net,r).passed
            @test ivr_nlp_point_report(b,actual).passed
            for (k,v) in p.voltage;@test r.voltage_candidate[k] ≈ v atol=2e-5;end
            key="$kind/tx"
            for family in (:transformer_from,:transformer_to,:transformer_coil_from,:transformer_coil_to,:transformer_bond)
                # The source neutral is grounded; the downstream neutral is
                # fixed only by the bond, so all regulator currents are determined.
                @test r.current_candidate[(family,key)] ≈ p.currents[(family,key)] atol=2e-5
            end
        end
        @test net==original
    end
end

@testset "Regulator side bounds and observed-bond perturbations" begin
    for (kind,four) in (("single_phase_autotransformer",false),("open_delta_regulator",false),("open_delta_regulator",true)),reverse in (false,true)
        net,p=_ivr_regulator_state(kind;four,reverse,excitation=2);key="$kind/tx"
        b=build_opf(net,IVRNLP())
        for family in (:transformer_from,:transformer_to,:transformer_coil_from,:transformer_coil_to,:transformer_bond)
            for k in eachindex(p.currents[(family,key)])
                cs=deepcopy(p.currents);cs[(family,key)][k]+=.1
                bad=ACPoint(voltage=p.voltage,currents=cs)
                @test !ivr_nlp_point_report(b,bad).passed
                @test !physical_residuals(net,bad;delta_dispatch=:coil).passed
            end
        end
        cs=deepcopy(p.currents);delete!(cs,(:transformer_bond,key))
        @test !ivr_nlp_point_report(b,ACPoint(voltage=p.voltage,currents=cs)).passed
        for side in ("from","to"),k in eachindex(p.currents[(Symbol("transformer_",side),key)])
            actual=abs(p.currents[(Symbol("transformer_",side),key)][k]);actual>.01 || continue
            tight=deepcopy(net);tight["transformer"][kind]["tx"]["i_max_$side"][k]=.5actual
            @test !ivr_nlp_point_report(build_opf(tight,IVRNLP()),p).passed
            a=physical_residuals(tight,p;delta_dispatch=:coil);@test !a.passed
            @test [r.label for r in a.records if r.residual>getproperty(a.tolerances,r.unit)]==["transformer/$key/i_max_$side"]
        end
    end
end

@testset "Regulator ideal and finite earth paths preserve observed bond allocation" begin
    for gf in (nothing,0.,2.5),gt in (nothing,0.,3.),sb in (1e3,1e5)
        net=_sdp_tx_case("single_phase_autotransformer";tap=1.04)
        empty!(net["bus"]["t"]["perfectly_grounded_terminals"])
        d=net["transformer"]["single_phase_autotransformer"]["tx"]
        gf===nothing || (d["r_neutral_from"]=gf)
        gt===nothing || (d["r_neutral_to"]=gt)
        merge!(d,Dict("r_series_from"=>.12,"x_series_from"=>.05,"r_series_to"=>.03,"x_series_to"=>.015,
                     "i_max_from"=>[100.,100.],"i_max_to"=>[100.,100.]))
        y=.02-.005im;g=1.04;vp=230g/(1+y*(g^2*(.12+.05im)+(.03+.015im)))
        jt=-y*vp;jf=-g*jt
        earthf=gf==0. ? .3-.1im : 0im;eartht=gt==0. ? .4+.2im : 0im
        bond=-jt+eartht;cf=ComplexF64[jf,-jf+bond+earthf];ct=ComplexF64[jt,0]
        _sdp_zload!(net,"earthload",["p"],y)
        key="single_phase_autotransformer/tx"
        point=ACPoint(voltage=Dict(("f","p")=>230+0im,("f","n")=>0im,("t","p")=>vp,("t","n")=>0im),
            currents=Dict((:voltage_source,"s")=>[jf,0im],(:load,"earthload")=>[-jt],
                (:transformer_from,key)=>cf,(:transformer_to,key)=>ct,
                (:transformer_coil_from,key)=>[jf],(:transformer_coil_to,key)=>[jt],(:transformer_bond,key)=>[bond]))
        b=build_opf(net,IVRNLP(s_base=sb);optimizer=Ipopt.Optimizer)
        @test ivr_nlp_point_report(b,point).passed
        @test physical_residuals(net,point;delta_dispatch=:coil).passed
        # Legacy points expose only terminal/coil channels. With an ideal earth
        # path the allocation is not unique; observable relations remain valid.
        old=deepcopy(point.currents);delete!(old,(:transformer_bond,key))
        @test physical_residuals(net,ACPoint(voltage=point.voltage,currents=old);delta_dispatch=:coil).passed
        r=_regulator_solve(b);@test r.solve.optimal
        @test r.voltage_candidate[("t","p")] ≈ vp atol=1e-6
        @test physical_residuals(net,r).passed
        @test ivr_nlp_point_report(b,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
        # The generated point deliberately selects nonzero ideal-ground flows.
        # Do not assert that the solver selects the same unobservable allocation.
    end
end

@testset "Regulator taps, scope, relabeling, reverse supply and reuse" begin
    for kind in ("single_phase_autotransformer","open_delta_regulator")
        net,p=_ivr_regulator_state(kind;rt="a");d=net["transformer"][kind]["tx"]
        @test physical_residuals(net,p;delta_dispatch=:coil).passed
        @test ivr_nlp_point_report(build_opf(net,IVRNLP()),p).passed
        for (field,value) in (("tap_ratio",0.),("tap_ratio",Inf),("tap_ratio_min",.9),
            ("regulator_type","C"),("r_series_from",-1.),("control_profile","ctrl"),
            ("time_series","schedule"),("s_max",[1000.]),("i_max_to",[-1.]))
            bad=deepcopy(net);bad["transformer"][kind]["tx"][field]=value
            @test_throws IVRNLPInapplicableError build_opf(bad,IVRNLP())
        end
        tap=pop!(d,"tap_ratio");d["tap_ratio_min"]=tap;d["tap_ratio_max"]=tap
        @test ivr_nlp_point_report(build_opf(net,IVRNLP()),p).passed
        d["tap_ratio_max"]=tap.*1.01
        @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
        d["tap_ratio"]=tap
        @test ivr_nlp_point_report(build_opf(net,IVRNLP()),p).passed
        d["tap_ratio"]=tap.*1.02
        @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
    end
    # Terminal maps carry polarity; changing bus storage order does not change it.
    net,p=_ivr_regulator_state("open_delta_regulator";connection="CABA",four=true)
    for bus in values(net["bus"]);reverse!(bus["terminal_names"]);end
    @test ivr_nlp_point_report(build_opf(net,IVRNLP()),p).passed
    @test physical_residuals(net,p;delta_dispatch=:coil).passed
    # Reserve rating headroom for the 1.1 demand scenario; constant-power
    # currents grow slightly faster than demand when voltage drops increase.
    for side in ("from","to");net["transformer"]["open_delta_regulator"]["tx"]["i_max_$side"] .*= 2;end
    b=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer)
    original=deepcopy(net["load"])
    for scale in (0.,.7,1.1)
        update_ivr_loads!(b,Dict(id=>(p=scale*d["p_nom"],q=scale*d["q_nom"]) for (id,d) in original))
        r=_regulator_solve(b);@test r.solve.optimal
        @test physical_residuals(b.network,r).passed
        @test ivr_nlp_point_report(b,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
    end
    # Reverse the supply boundary, leaving the fixed physical orientation intact.
    net=_sdp_tx_case("single_phase_autotransformer";tap=1.04)
    s=net["voltage_source"]["s"];s["bus"]="t";s["v_magnitude"]=[230.,0.]
    _sdp_zload!(net,"l",["p","n"],.01-.002im);net["load"]["l"]["bus"]="f"
    b=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer);r=_regulator_solve(b)
    @test r.solve.optimal
    @test r.voltage_candidate[("f","p")] ≈ 230/1.04 atol=1e-6
    @test physical_residuals(net,r).passed
    @test ivr_nlp_point_report(b,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
end
