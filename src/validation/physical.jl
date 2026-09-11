# Independent SI evaluation. This file deliberately never calls the formulation's
# _sdp_* stamping, connection, bound-propagation or matrix-decoding helpers.
_vcheck_array(d,k,n,default=0.0)=haskey(d,k) ? (d[k] isa Number ? fill(Float64(d[k]),n) : Float64.(d[k])) : fill(default,n)
function _vcheck_matrix(d,prefix,n;symmetric=false)
    M=zeros(n,n)
    for i in 1:n,j in 1:n
        key="$(prefix)_$(i)_$(j)"
        M[i,j]=get(d,key,symmetric ? get(d,"$(prefix)_$(j)_$(i)",0.0) : 0.0)
    end
    M
end
function _vcheck_neutral(net,bus)
    d=net["bus"][bus];roles=get(net,"terminal_conventions",nothing)
    names=roles===nothing ? [get(d,"neutral_terminal","n"),"N"] : get(roles,"neutral",String[])
    indices=findall(in(names),d["terminal_names"])
    isempty(indices) ? nothing : d["terminal_names"][only(indices)]
end
function _vcheck_pairs(net,bus,tm,cfg,n)
    neutral=_vcheck_neutral(net,bus)
    if cfg=="SINGLE_PHASE"
        return [(1,length(tm)==1 ? 0 : 2)]
    elseif cfg=="DELTA"
        return length(tm)==2 ? [(1,2)] : [(1,2),(2,3),(3,1)]
    end
    ni=findfirst(==(neutral),tm)
    [(i,something(ni,0)) for i in eachindex(tm) if i!=ni]
end
_vcheck_incidence(pairs,n)=[Float64(k==i)-Float64(k==j) for (i,j) in pairs,k in 1:n]

"""Independently evaluate an AC point in SI units. Reports equation residuals,
limit violations and explicit unassessed items. No optimization and no compiled
formulation expressions are used. A partial assessment never reports `passed`.
Currently covers buses, sources, lines, loads, generators, fixed switches,
shunts/capacitors fixed transformer winding networks and static IBR filters/capabilities. `atol` is a named tuple of V, A and VA tolerances.
"""
function physical_residuals(input,point::ACPoint;atol=(voltage=1e-5,current=1e-6,power=1e-3))
    net=input isa BMOPFInput ? _l3f_input(input) : input
    records=NamedTuple[];unassessed=String[]
    V(b,tm)=[get(point.voltage,(b,t),ComplexF64(NaN)) for t in tm]
    kcl=Dict(k=>0.0im for k in keys(point.voltage))
    function check(label,value,unit)
        magnitude=maximum(abs,value isa Number ? [value] : value;init=0.0)
        push!(records,(label=label,residual=isfinite(magnitude) ? magnitude : Inf,unit=unit))
    end
    function current(f,id,n)
        key=(f,id)
        if !haskey(point.currents,key)
            push!(unassessed,"missing current $key");return fill(ComplexF64(NaN),n)
        end
        x=point.currents[key];length(x)==n || throw(ArgumentError("current arity for $key"));x
    end
    function inject(b,tm,i,sign=1)
        for (t,a) in zip(tm,i);kcl[(b,t)]=get(kcl,(b,t),0im)+sign*a;end
    end
    function bounds(d,x,lo,hi,label,unit)
        for (field,lower) in ((lo,true),(hi,false))
            haskey(d,field) || continue
            limits=_vcheck_array(d,field,length(x))
            length(limits)==length(x) || (push!(unassessed,"$label/$field arity");continue)
            check("$label/$field",max.(0.,lower ? limits.-x : x.-limits),unit)
        end
    end
    function rates(d,v,i,label)
        bounds(d,abs.(i),"__none","i_max",label,:current)
        bounds(d,abs.(v.*conj.(i)),"__none","s_max",label,:power)
    end
    for (b,d) in net["bus"]
        tm=d["terminal_names"];v=V(b,tm);nt=_vcheck_neutral(net,b);ni=findfirst(==(nt),tm)
        check("bus/$b/finite_voltage",all(isfinite,v) ? 0.0 : Inf,:voltage)
        ph=findall(!=(nt),tm);vp=v[ph];vn=ni===nothing ? 0im : v[ni];vpn=vp.-vn
        for t in get(d,"perfectly_grounded_terminals",String[]);check("bus/$b/ground/$t",V(b,[t]),:voltage);end
        for field in ("v_min","v_max")
            haskey(d,field) || continue
            n=length(d[field]);x=n==length(tm) ? v : vp
            bounds(Dict(field=>d[field]),abs.(x),"v_min","v_max","bus/$b",:voltage)
        end
        bounds(d,abs.(vpn),"vpn_min","vpn_max","bus/$b",:voltage)
        pairs=length(vp)==3 ? [(1,2),(2,3),(3,1)] : [(i,j) for i in eachindex(vp) for j in i+1:length(vp)]
        bounds(d,[abs(vp[i]-vp[j]) for (i,j) in pairs],"vpp_min","vpp_max","bus/$b",:voltage)
        bounds(d,[abs(vn)],"__none","vn_max","bus/$b",:voltage)
        if any(haskey(d,k) for k in ("vpos_min","vpos_max","vneg_max","vzero_max"))
            if length(vpn)!=3
                push!(unassessed,"bus/$b sequence limits without three phases")
            else
                order=get(get(net,"terminal_conventions",Dict()),"phase",["a","b","c"])
                all(t->t in tm[ph],order) && length(order)==3 || (order=tm[ph])
                vals=[v[findfirst(==(t),tm)]-vn for t in order];a=cis(2pi/3)
                bounds(d,[abs((vals[1]+a*vals[2]+a^2*vals[3])/3)],"vpos_min","vpos_max","bus/$b",:voltage)
                bounds(d,[abs((vals[1]+a^2*vals[2]+a*vals[3])/3)],"__none","vneg_max","bus/$b",:voltage)
                bounds(d,[abs(sum(vals)/3)],"__none","vzero_max","bus/$b",:voltage)
            end
        end
    end
    for (id,d) in get(net,"voltage_source",Dict())
        tm=d["terminal_map"];v=V(d["bus"],tm);i=current(:voltage_source,id,length(tm))
        check("source/$id/phasor",v-d["v_magnitude"].*cis.(d["v_angle"]),:voltage)
        inject(d["bus"],tm,i,-1)
        ph=findall(!=(_vcheck_neutral(net,d["bus"])),tm);s=v.*conj.(i)
        for (lo,hi,part) in (("p_min","p_max",real),("q_min","q_max",imag))
            for field in (lo,hi)
                haskey(d,field) || continue
                x=length(d[field])==length(tm) ? s : s[ph]
                bounds(Dict(field=>d[field]),part.(x),lo,hi,"source/$id",:power)
            end
        end
        bounds(d,abs.(i),"__none","i_max","source/$id",:current)
    end
    for (id,d) in get(net,"line",Dict())
        f,t=d["bus_from"],d["bus_to"];mf,mt=d["terminal_map_from"],d["terminal_map_to"];n=length(mf)
        code=haskey(d,"linecode") ? net["linecode"][d["linecode"]] : d;len=haskey(d,"linecode") ? get(d,"length",1.0) : 1.0
        matrix(r,x)=complex.(_vcheck_matrix(code,r,n;symmetric=true),_vcheck_matrix(code,x,n;symmetric=true))*len
        Z=matrix("R_series","X_series");Yf=matrix("G_from","B_from");Yt=matrix("G_to","B_to")
        vf,vt=V(f,mf),V(t,mt);cf,ct=current(:line_from,id,n),current(:line_to,id,n)
        jf,jt=cf-Yf*vf,ct-Yt*vt
        check("line/$id/voltage_drop",vf-vt-Z*jf,:voltage);check("line/$id/series_current",jf+jt,:current)
        inject(f,mf,cf);inject(t,mt,ct)
        limits=merge(code,d)
        for (side,b,tm,v,i) in (("from",f,mf,vf,cf),("to",t,mt,vt,ct))
            bounds(limits,abs.(i),"__none","i_max","line/$id/$side",:current)
            ph=findall(!=(_vcheck_neutral(net,b)),tm)
            bounds(limits,abs.(v[ph].*conj.(i[ph])),"__none","s_max","line/$id/$side",:power)
        end
    end
    for family in ("load","generator","capacitor"),(id,d) in get(net,family,Dict())
        tm=d["terminal_map"];cfg=uppercase(d["configuration"]);n=cfg=="SINGLE_PHASE" || length(tm)==2 && cfg=="DELTA" ? 1 : cfg=="DELTA" ? 3 : count(!=(_vcheck_neutral(net,d["bus"])),tm)
        D=_vcheck_incidence(_vcheck_pairs(net,d["bus"],tm,cfg,n),length(tm));v=V(d["bus"],tm);u=D*v
        if family=="generator" && cfg=="DELTA" && length(tm)==3
            i=current(:generator,id,3);s=v.*conj.(i);inject(d["bus"],tm,i,-1)
            check("generator/$id/three_wire",sum(i),:current)
        elseif family=="capacitor"
            vn=_vcheck_array(d,"v_nom",n);i=im.*d["q_rated"]./vn.^2 .*u;s=u.*conj.(i);inject(d["bus"],tm,transpose(D)*i)
            haskey(point.currents,(:capacitor,id)) && check("capacitor/$id/current",point.currents[(:capacitor,id)]-i,:current)
        else
            i=current(Symbol(family),id,n);s=u.*conj.(i);inject(d["bus"],tm,transpose(D)*i,family=="load" ? 1 : -1)
        end
        if family=="load"
            law=lowercase(get(d,"model","constant_power"));vnom=_vcheck_array(d,"v_nom",n,1.0);ratio=abs.(u)./vnom
            function factor(prefix,gamma)
                law=="constant_power" && return ones(n)
                law=="constant_impedance" && return ratio.^2
                law=="constant_current" && return ratio
                law=="exponential" && return ratio.^d[gamma]
                law=="zip" && return d[prefix*"_z"].*ratio.^2+d[prefix*"_i"].*ratio+d[prefix*"_p"]
                push!(unassessed,"load/$id law $law");fill(NaN,n)
            end
            expected=complex.(d["p_nom"].*factor("alpha","gamma_p"),d["q_nom"].*factor("beta","gamma_q"))
            check("load/$id/power",s-expected,:power)
        elseif family=="generator"
            bounds(d,real.(s),"p_min","p_max","generator/$id",:power);bounds(d,imag.(s),"q_min","q_max","generator/$id",:power)
            bounds(d,abs.(s),"__none","s_max","generator/$id",:power)
            terminal_i=cfg=="DELTA" && length(tm)==3 ? i : transpose(D)*i
            rated=haskey(d,"i_max") && length(d["i_max"])==length(terminal_i) ? terminal_i : i
            bounds(d,abs.(rated),"__none","i_max","generator/$id",:current)
        end
    end
    for (id,d) in get(net,"shunt",Dict())
        tm=d["terminal_map"];n=length(tm);v=V(d["bus"],tm)
        Y=complex.(_vcheck_matrix(d,"G",n;symmetric=true),_vcheck_matrix(d,"B",n;symmetric=true))
        inject(d["bus"],tm,Y*v)
    end
    for (id,d) in get(net,"switch",Dict())
        tm=d["terminal_map_from"];mt=d["terminal_map_to"];v=V(d["bus_from"],tm);w=V(d["bus_to"],mt)
        i=current(:switch_from,id,length(tm));j=current(:switch_to,id,length(mt))
        check("switch/$id/current",i+j,:current)
        d["open_switch"] ? check("switch/$id/open",[i;j],:current) : check("switch/$id/closed",v-w,:voltage)
        inject(d["bus_from"],tm,i);inject(d["bus_to"],mt,j);rates(d,v,i,"switch/$id")
    end
    _physical_transformers!(net,point,V,current,check,bounds,inject,unassessed)
    for (id,d) in get(net,"ibr",Dict())
        tm=d["terminal_map"];top=d["topology"];n=length(d["s_max"])
        cfg=top=="FOUR_LEG" ? "WYE" : top=="THREE_LEG" ? "DELTA" : "SINGLE_PHASE"
        D=_vcheck_incidence(_vcheck_pairs(net,d["bus"],tm,cfg,n),length(tm));v=V(d["bus"],tm);u=D*v
        i=current(:ibr,id,n);jf=current(:ibr_internal,id,n)
        coil=jf-im*get(d,"b_filter_shunt",0.).*u
        terminal_i=top=="THREE_LEG" ? i : transpose(D)*i
        check("ibr/$id/filter_current",transpose(D)*coil-terminal_i,:current)
        e=u+complex.(_vcheck_array(d,"r_filter",n),_vcheck_array(d,"x_filter",n)).*jf
        s=(top=="THREE_LEG" ? v : u).*conj.(i);internal=e.*conj.(jf)
        inject(d["bus"],tm,terminal_i,-1)
        bounds(d,real.(s),"p_min","p_max","ibr/$id",:power);bounds(d,imag.(s),"q_min","q_max","ibr/$id",:power)
        bounds(d,abs.(s),"__none","s_max","ibr/$id",:power)
        rated=haskey(d,"i_max") && length(d["i_max"])==length(terminal_i) ? terminal_i : i
        bounds(d,abs.(rated),"__none","i_max","ibr/$id",:current)
        bounds(d,[sum(real,s)],"__none","p_avail","ibr/$id",:power)
        if get(d,"dc_link_coupled",false)
            bounds(d,[sum(real,internal)],"p_dc_min","p_dc_max","ibr/$id",:power)
        end
        get(d,"grid_forming",false) && check("ibr/$id/internal_voltage",abs.(e).-d["v_ref_internal"],:voltage)
    end
    for (key,value) in kcl
        key[2] in get(net["bus"][key[1]],"perfectly_grounded_terminals",String[]) && continue
        check("kcl/$(key[1])/$(key[2])",value,:current)
    end
    known=Set(["bus","line","linecode","voltage_source","load","generator","ibr","switch","shunt","capacitor","transformer",
        "name","meta","_meta","extras","terminal_conventions","wire_data","line_geometry","control_profile"])
    for family in keys(net)
        family in known || push!(unassessed,"unsupported root field $family")
    end
    maxima=Dict(u=>maximum((r.residual for r in records if r.unit==u);init=0.) for u in (:voltage,:current,:power))
    passed=isempty(unassessed) && all(maxima[u]<=getproperty(atol,u) for u in keys(maxima))
    (;passed,maxima,records,unassessed=unique(unassessed),tolerances=atol,nodal_balance=kcl)
end

function _physical_transformers!(net,point,V,current,check,bounds,inject,unassessed)
    for (kind,table) in get(net,"transformer",Dict()),(id,d) in table
        key="$kind/$id"
        if !(kind in (_SDP_TRANSFORMERS...,"n_winding"));push!(unassessed,"transformer/$key");continue;end
        kind=="n_winding" && (_physical_nwinding!(net,d,key,V,current,check,bounds,inject,unassessed);continue)
        mf,mt=d["terminal_map_from"],d["terminal_map_to"];nf,nt=length(mf),length(mt)
        vf,vt=V(d["bus_from"],mf),V(d["bus_to"],mt)
        pair(n)=[(1,n==1 ? 0 : 2)]
        wye(n)=[(k,n==4 ? 4 : 0) for k in 1:3]
        regulator=kind in ("single_phase_autotransformer","open_delta_regulator")
        tap=get(d,"tap",get(d,"tap_ratio",get(d,"tap_min",get(d,"tap_ratio_min",1.0))))
        tap=tap isa Number ? [tap] : tap
        bonds=Int[]
        if kind=="open_delta_regulator"
            pf=pt=Dict("ABBC"=>[(1,2),(2,3)],"BCAC"=>[(2,3),(1,3)],"CABA"=>[(3,1),(2,1)])[d["connection"]]
            length(tap)==1 && (tap=fill(only(tap),2))
            gain=get(d,"regulator_type","B")=="A" ? inv.(tap) : tap
            R=Matrix(Diagonal(gain));push!(bonds,only(intersect(collect(pf[1]),collect(pf[2]))))
            nf==4 && push!(bonds,4)
        elseif kind=="single_phase_autotransformer"
            pf,pt=pair(nf),pair(nt);R=fill(get(d,"regulator_type","B")=="A" ? inv(only(tap)) : only(tap),1,1)
            nf==2 && push!(bonds,2)
        else
            ratio=d["v_nom_to"]/d["v_nom_from"]/only(tap)
            if kind=="single_phase";pf,pt=pair(nf),pair(nt);R=fill(ratio,1,1)
            elseif kind=="center_tap";pf=pair(nf);pt=nt==3 ? [(1,2),(2,3)] : [(1,0),(0,2)];R=fill(ratio,2,1)
            elseif kind=="wye_delta";pf,pt=wye(nf),[(1,2),(2,3),(3,1)];R=Matrix{Float64}(I,3,3)*(sqrt(3)*ratio)
            elseif kind=="delta_wye";pf,pt=[(1,3),(2,1),(3,2)],wye(nt);R=Matrix{Float64}(I,3,3)*(ratio/sqrt(3))
            else;push!(unassessed,"transformer/$key");continue
            end
        end
        Df,Dt=_vcheck_incidence(pf,nf),_vcheck_incidence(pt,nt);uf,ut=Df*vf,Dt*vt
        jf=current(:transformer_coil_from,key,length(pf));jt=current(:transformer_coil_to,key,length(pt))
        cf=current(:transformer_from,key,nf);ct=current(:transformer_to,key,nt)
        zf=complex(get(d,"r_series_from",0.),get(d,"x_series_from",0.));zt=complex(get(d,"r_series_to",0.),get(d,"x_series_to",0.))
        if haskey(d,"r_series") || haskey(d,"x_series")
            z=complex(get(d,"r_series",0.),get(d,"x_series",0.));kind=="wye_delta" ? (zf=z) : (zt=z)
        end
        kind=="wye_delta" && (zt*=3);kind=="delta_wye" && (zf*=3)
        regulator || (zf*=only(tap)^2)
        check("transformer/$key/emf",ut-zt*jt-R*(uf-zf*jf),:voltage)
        check("transformer/$key/ampere_turns",jf+transpose(R)*jt,:current)
        y=complex(get(d,"g_no_load",0.),get(d,"b_no_load",0.))
        yf=fill(y/(regulator ? 1 : length(pf)),length(pf));yt=zeros(ComplexF64,length(pt))
        if haskey(d,"no_load_shunt")
            sh=d["no_load_shunt"];y=complex(get(sh,"g",0.),get(sh,"b",0.));fill!(yf,0);fill!(yt,0)
            sh["winding"]==1 ? (yf.=y) : kind=="center_tap" ? (yt[sh["winding"]-1]=y) : (yt.=y)
        end
        expectedf=transpose(Df)*(jf+yf.*uf);expectedt=transpose(Dt)*(jt+yt.*ut)
        for (side,tm,v,expected,bus) in (("from",mf,vf,expectedf,d["bus_from"]),("to",mt,vt,expectedt,d["bus_to"]))
            _physical_neutral!(net,d,"r_neutral_$side","x_neutral_$side",bus,tm,v,expected,check,unassessed,"transformer/$key/$side",side=="from" ? cf : ct)
        end
        for k in bonds
            check("transformer/$key/bond_voltage/$k",vf[k]-vt[k],:voltage)
            check("transformer/$key/bond_current/$k",cf[k]-expectedf[k]+ct[k]-expectedt[k],:current)
        end
        for (side,c,e,v,u,j,tm,bus) in (("from",cf,expectedf,vf,uf,jf,mf,d["bus_from"]),("to",ct,expectedt,vt,ut,jt,mt,d["bus_to"]))
            for k in eachindex(c);k in bonds || check("transformer/$key/terminal_$side/$k",c[k]-e[k],:current);end
            delta=kind=="wye_delta" && side=="to" || kind=="delta_wye" && side=="from"
            bounds(d,abs.(delta ? j : c),"__none","i_max_$side","transformer/$key",:current)
            inject(bus,tm,c)
        end
    end
end
function _physical_neutral!(net,d,rfield,xfield,bus,tm,v,expected,check,unassessed,label,actual)
    haskey(d,rfield) || haskey(d,xfield) || return
    ni=findfirst(==(_vcheck_neutral(net,bus)),tm)
    ni===nothing && (push!(unassessed,"$label neutral impedance without neutral");return)
    z=complex(get(d,rfield,0.),get(d,xfield,0.))
    if iszero(z)
        check("$label/neutral_ground",v[ni],:voltage)
        # The earth current is free at an ideal ground. The observed total
        # terminal current still participates in KCL and terminal limits.
        expected[ni]=actual[ni]
    else
        expected[ni]+=v[ni]/z
    end
end
function _physical_nwinding!(net,d,key,V,current,check,bounds,inject,unassessed)
    ws=d["windings"];n=length(ws)
    volts=[w["v_nom"] for w in ws];nominal=volts/volts[1]
    tap=[get(w,"tap_ratio",get(w,"tap_ratio_min",1.)) for w in ws];turns=nominal.*tap
    u=Vector{ComplexF64}[];j=Vector{ComplexF64}[]
    for (k,w) in enumerate(ws)
        tm=w["terminal_map"];cfg=uppercase(get(w,"configuration","WYE"));v=V(w["bus"],tm)
        pairs=_vcheck_pairs(net,w["bus"],tm,cfg,3)
        cfg=="DELTA" && get(w,"delta_roll",1)==-1 && (pairs=[(1,3),(2,1),(3,2)])
        D=_vcheck_incidence(pairs,length(tm));uk=D*v;jk=current(:transformer_coil,"$key/$k",length(pairs))
        push!(u,uk);push!(j,jk)
        y=complex(get(d,"g_no_load",0.),get(d,"b_no_load",0.))/length(pairs);sh=1
        if haskey(d,"no_load_shunt");s=d["no_load_shunt"];sh=s["winding"];y=complex(get(s,"g",0.),get(s,"b",0.));end
        expected=transpose(D)*(jk+(k==sh ? y.*uk : zero(uk)))
        c=current(:transformer_winding,"$key/$k",length(tm))
        _physical_neutral!(net,w,"r_neutral","x_neutral",w["bus"],tm,v,expected,check,unassessed,"transformer/$key/$k",c)
        check("transformer/$key/$k/terminal",c-expected,:current);inject(w["bus"],tm,c)
        bounds(w,abs.(jk),"__none","i_max","transformer/$key/$k",:current)
        bounds(w,abs.(uk.*conj.(jk)),"__none","s_max","transformer/$key/$k",:power)
    end
    J=[turns[k].*j[k] for k in 1:n]
    check("transformer/$key/ampere_turns",sum(J),:current)
    r=[get(w,"r_winding",0.)/nominal[k]^2 for (k,w) in enumerate(ws)]
    pair(a,b)=complex(r[a]+r[b],d["x_sc"]["$(min(a,b))_$(max(a,b))"])
    for a in 2:n
        drop=zeros(ComplexF64,length(u[a]))
        for b in 2:n
            z=a==b ? pair(1,a) : (pair(1,a)+pair(1,b)-pair(a,b))/2
            drop .+= z.*J[b]
        end
        check("transformer/$key/$a/emf",u[1]/turns[1]-u[a]/turns[a]+drop,:voltage)
    end
end
