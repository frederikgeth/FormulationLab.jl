# General fixed-tap coupled-coil leakage model. No star fit and no inverse ZB.
function _sdp_nwinding_plan(net,id,d)
    label="transformer/n_winding/$id"
    _sdp_fields(d,("windings","x_sc","s_rating","g_no_load","b_no_load","no_load_shunt"),label)
    ws=get(d,"windings",nothing)
    ws isa AbstractVector && length(ws)>=2 || _sdp_refuse("$label requires at least two windings")
    n=length(ws);Ds=Matrix{Float64}[];volts=Float64[];taps=Float64[];rs=Float64[]
    for (k,w) in enumerate(ws)
        _sdp_fields(w,("bus","terminal_map","v_nom","configuration","r_winding","delta_roll","i_max","s_max","s_rating",
            "tap_ratio","tap_ratio_min","tap_ratio_max","r_neutral","x_neutral"),"$label winding $k")
        v=_sdp_scalar(w,"v_nom");v>0 || _sdp_refuse("$label nonpositive v_nom")
        r=_sdp_scalar(w,"r_winding");r>=0 || _sdp_refuse("$label negative resistance")
        tm=w["terminal_map"];cfg=uppercase(get(w,"configuration","WYE"))
        nt=get(_kr_neutral_map(net),w["bus"],nothing)
        nc=cfg=="SINGLE_PHASE" ? 1 : cfg=="DELTA" ? 3 : count(!=(nt),tm)
        D=_sdp_connection(net,w["bus"],tm,cfg,nc;roll=get(w,"delta_roll",1))
        push!(Ds,D);push!(volts,v);push!(rs,r);push!(taps,only(_sdp_fixed_tap(w,true,1,label)))
    end
    all(D->size(D,1)==size(first(Ds),1),Ds) || _sdp_refuse("$label unequal coil counts")
    nominal=volts/first(volts);turns=volts.*taps/first(volts)
    xsc=get(d,"x_sc",Dict());expected=Set("$(i)_$(j)" for i in 1:n for j in i+1:n)
    Set(keys(xsc))==expected || _sdp_refuse("$label requires every i_j short-circuit pair exactly once")
    pair(i,j)=complex(rs[i]/nominal[i]^2+rs[j]/nominal[j]^2,_sdp_scalar(xsc,"$(min(i,j))_$(max(i,j))"))
    all(x->x isa Real && isfinite(x) && x>=0,values(xsc)) || _sdp_refuse("$label invalid x_sc")
    Z=[i==j ? pair(1,i+1) : (pair(1,i+1)+pair(1,j+1)-pair(i+1,j+1))/2 for i in 1:n-1,j in 1:n-1]
    minimum(eigvals(Symmetric(imag(Z))))>=-1e-10*max(1,norm(Z)) || _sdp_refuse("$label inconsistent short-circuit reactances")
    # Legacy fields in the 0.2 schema are referred to winding 1. Explicit
    # no_load_shunt removes ambiguity about the physical location and coil base.
    shunt=1;y=complex(_sdp_scalar(d,"g_no_load"),_sdp_scalar(d,"b_no_load"))/size(Ds[1],1)
    if haskey(d,"no_load_shunt")
        any(haskey(d,k) for k in ("g_no_load","b_no_load")) && _sdp_refuse("$label conflicting excitation representations")
        s=d["no_load_shunt"];_sdp_fields(s,("winding","g","b"),label)
        shunt=get(s,"winding",0);shunt isa Integer && 1<=shunt<=n || _sdp_refuse("$label invalid exciting winding")
        y=complex(_sdp_scalar(s,"g"),_sdp_scalar(s,"b"))
    end
    real(y)>=0 || _sdp_refuse("$label negative core conductance")
    (;ws,Ds,turns,Z,shunt,y)
end
function _sdp_stamp_nwinding!(net,newvar,terminal_rows,matrows,inject,equations,devices,limits,zb)
    for (id,d) in get(get(net,"transformer",Dict()),"n_winding",Dict())
        p=_sdp_nwinding_plan(net,id,d);n=length(p.ws)
        v=[terminal_rows(w["bus"],w["terminal_map"]) for w in p.ws]
        u=[matrows(p.Ds[k],v[k]) for k in 1:n]
        j=[[_sdp_e(newvar()) for _ in u[k]] for k in 1:n]
        for c in eachindex(u[1])
            amp=_SDPRow();for k in 1:n;_sdp_add!(amp,j[k][c],p.turns[k]);end;push!(equations,amp)
            for i in 2:n
                row=_sdp_add!(_SDPRow(),u[1][c],1/p.turns[1]);_sdp_add!(row,u[i][c],-1/p.turns[i])
                for k in 2:n;_sdp_add!(row,j[k][c],p.Z[i-1,k-1]*p.turns[k]/zb);end
                push!(equations,row)
            end
        end
        for k in 1:n
            w=p.ws[k];cf=deepcopy(j[k])
            if k==p.shunt
                for c in eachindex(cf);_sdp_add!(cf[c],u[k][c],p.y*zb);end
            end
            currents=matrows(transpose(p.Ds[k]),cf)
            neutral=get(_kr_neutral_map(net),w["bus"],nothing)
            ground=_sdp_ground!(w,"r_neutral","x_neutral",findfirst(==(neutral),w["terminal_map"]),v[k],newvar,equations,zb)
            for t in eachindex(currents);_sdp_add!(currents[t],ground[t]);end
            inject(w["bus"],w["terminal_map"],currents)
            key="n_winding/$id/$k"
            push!(devices,(:transformer_winding,key,v[k],currents,Dict()))
            push!(devices,(:transformer_coil,key,u[k],j[k],Dict()))
            bounds=Dict{String,Any}()
            for field in ("i_max","s_max")
                haskey(w,field) && (bounds[field]=_sdp_vector(w,field,length(j[k])))
            end
            # Schema s_rating is a power base, not an implicit operating cap.
            push!(limits,(u[k],j[k],bounds))
        end
    end
end
