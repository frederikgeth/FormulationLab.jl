# Fixed winding networks. All currents point into the transformer. Electrical
# connections are kept before lifting; delta coil currents are never replaced
# with delta terminal currents. See docs/src/sdp_transformers.md.
const _SDP_TRANSFORMERS = ("single_phase", "center_tap", "wye_delta", "delta_wye",
                           "single_phase_autotransformer", "open_delta_regulator")

function _sdp_fixed_tap(d, regulator, n, label)
    key = regulator ? "tap_ratio" : "tap"
    vector(x) = x isa Real ? fill(Float64(x), n) : Float64.(x)
    readvalue(k) = try
        v = vector(d[k])
        length(v) == n && all(x -> isfinite(x) && x > 0, v) ||
            _sdp_refuse("$label $k needs $n positive finite values")
        v
    catch e
        e isa SDPInapplicableError && rethrow()
        _sdp_refuse("$label invalid $k")
    end
    lo, hi = key*"_min", key*"_max"
    haskey(d,lo) == haskey(d,hi) || _sdp_refuse("$label needs both tap bounds")
    bounds = haskey(d,lo) ? (readvalue(lo),readvalue(hi)) : nothing
    bounds !== nothing && any(bounds[1] .> bounds[2]) && _sdp_refuse("$label reversed tap bounds")
    if haskey(d,key)
        tap = readvalue(key)
        bounds !== nothing && !all(bounds[1] .<= tap .<= bounds[2]) &&
            _sdp_refuse("$label fixed tap outside declared bounds")
        return tap
    end
    bounds === nothing && return ones(n)
    bounds[1] == bounds[2] || _sdp_refuse("$label adjustable taps need an explicit fixed setting")
    bounds[1]
end

function _sdp_transformer_plan(subtype, d, label)
    subtype in _SDP_TRANSFORMERS || _sdp_refuse("$label subtype is not implemented")
    regulator = subtype in ("single_phase_autotransformer", "open_delta_regulator")
    allowed = ("bus_from","bus_to","terminal_map_from","terminal_map_to",
        "r_series_from","x_series_from","r_series_to","x_series_to",
        "g_no_load","b_no_load","s_rating","i_max_from","i_max_to","no_load_shunt",
        "r_neutral_from","x_neutral_from","r_neutral_to","x_neutral_to")
    extra = regulator ? ("tap_ratio","tap_ratio_min","tap_ratio_max","regulator_type") :
        ("v_nom_from","v_nom_to","tap","tap_min","tap_max","tap_ratio","tap_ratio_min","tap_ratio_max")
    _sdp_fields(d,(allowed...,extra...,(subtype=="open_delta_regulator" ? ("connection",) : ())...,
        (subtype in ("wye_delta","delta_wye") ? ("r_series","x_series") : ())...),label)
    required = ("bus_from","bus_to","terminal_map_from","terminal_map_to",
                (regulator ? () : ("v_nom_from","v_nom_to"))...)
    all(haskey(d,k) for k in required) || _sdp_refuse("$label missing required winding fields")
    nf,nt = length(d["terminal_map_from"]),length(d["terminal_map_to"])
    scalar(k, default=0.0) = begin
        x=get(d,k,default)
        x isa Real && isfinite(x) || _sdp_refuse("$label $k must be finite scalar")
        Float64(x)
    end
    zf=complex(scalar("r_series_from"),scalar("x_series_from"))
    zt=complex(scalar("r_series_to"),scalar("x_series_to"))
    if haskey(d,"r_series") || haskey(d,"x_series")
        any(haskey(d,k) for k in ("r_series_from","x_series_from","r_series_to","x_series_to")) &&
            _sdp_refuse("$label conflicting combined and split leakage")
        z=complex(scalar("r_series"),scalar("x_series"))
        subtype=="wye_delta" ? (zf=z) : (zt=z)
    end
    real(zf)>=0 && real(zt)>=0 || _sdp_refuse("$label negative winding resistance")
    y=complex(scalar("g_no_load"),scalar("b_no_load"))
    real(y)>=0 || _sdp_refuse("$label negative core conductance")
    rating=haskey(d,"s_rating") ? scalar("s_rating") : nothing
    rating === nothing || rating>=0 || _sdp_refuse("$label s_rating must be nonnegative")
    incidence(n,pairs) = [Float64(j==p)-Float64(j==q) for (p,q) in pairs, j in 1:n]
    pair(n) = n in (1,2) ? [(1,n==2 ? 2 : 0)] : _sdp_refuse("$label expects one coil on this side")
    wye(n) = n in (3,4) ? [(k,n==4 ? 4 : 0) for k in 1:3] : _sdp_refuse("$label wye map needs 3 phases and optional trailing neutral")
    bonds=Tuple{Int,Int}[]
    tap=_sdp_fixed_tap(d,regulator,subtype=="open_delta_regulator" ? 2 : 1,label)
    if regulator
        rt=uppercase(String(get(d,"regulator_type","B")))
        rt in ("A","B") || _sdp_refuse("$label regulator_type must be A or B")
        ratios=rt=="A" ? tap : inv.(tap)
        if subtype=="open_delta_regulator"
            nf==nt && nf in (3,4) || _sdp_refuse("$label open delta requires three phases and optional trailing neutral")
            pairs=get(Dict("ABBC"=>[(1,2),(2,3)],"BCAC"=>[(2,3),(1,3)],
                "CABA"=>[(3,1),(2,1)]),get(d,"connection",""),nothing)
            pairs===nothing && _sdp_refuse("$label unknown open-delta connection")
            pf=pt=pairs
            shared=only(intersect(collect(pairs[1]),collect(pairs[2])))
            push!(bonds,(shared,shared))
            nf==4 && push!(bonds,(4,4))
        else
            pf=pair(nf);pt=pair(nt)
            nf==nt || _sdp_refuse("$label regulator reference terminals must match")
            nf==2 && push!(bonds,(2,2))
        end
        R=Matrix(Diagonal(inv.(ratios)))
        # Regulator leakage uses the declared through-winding ohms; tap changes
        # its referral via the coupling, not the input impedance coefficient.
        Zf=fill(zf,length(pf));Zt=fill(zt,length(pt))
        Yf=fill(y,length(pf));Yt=zeros(ComplexF64,length(pt))
        rated_side=:from; rating_count=1 # each open-delta unit has this rating
    else
        vf=scalar("v_nom_from");vt=scalar("v_nom_to")
        vf>0 && vt>0 || _sdp_refuse("$label nominal voltages must be positive")
        a=vf/vt*only(tap)
        if subtype=="single_phase"
            pf=pair(nf);pt=pair(nt);R=fill(inv(a),1,1)
        elseif subtype=="center_tap"
            pf=pair(nf)
            pt=nt==3 ? [(1,2),(2,3)] : nt==2 ? [(1,0),(0,2)] :
                _sdp_refuse("$label center tap needs [leg1,neutral,leg2] or two ground-referenced legs")
            R=fill(inv(a),2,1)
        elseif subtype=="wye_delta"
            nt==3 || _sdp_refuse("$label delta map needs three terminals")
            pf=wye(nf);pt=[(k,mod1(k+1,3)) for k in 1:3]
            R=Matrix{Float64}(I,3,3)*(sqrt(3)/a);zt*=3
        else
            nf==3 || _sdp_refuse("$label delta map needs three terminals")
            pf=[(k,mod1(k-1,3)) for k in 1:3];pt=wye(nt)
            R=Matrix{Float64}(I,3,3)/(sqrt(3)*a);zf*=3
        end
        Zf=fill(zf*only(tap)^2,length(pf));Zt=fill(zt,length(pt))
        # Canonical BMOPF legacy excitation is on the from winding. Use the
        # explicit no_load_shunt for other physical locations (e.g. OpenDSS wdg 2).
        Yf=fill(y/length(pf),length(pf));Yt=zeros(ComplexF64,length(pt))
        rated_side=subtype=="delta_wye" ? :to : :from
        rating_count=subtype in ("wye_delta","delta_wye") ? 3 : 1
    end
    if haskey(d,"no_load_shunt")
        any(haskey(d,k) for k in ("g_no_load","b_no_load")) && _sdp_refuse("$label conflicting excitation representations")
        sh=d["no_load_shunt"];_sdp_fields(sh,("winding","g","b"),label)
        k=get(sh,"winding",0);k isa Integer && 1<=k<=(subtype=="center_tap" ? 3 : 2) || _sdp_refuse("$label invalid exciting winding")
        y=complex(_sdp_scalar(sh,"g"),_sdp_scalar(sh,"b"));real(y)>=0 || _sdp_refuse("$label negative core conductance")
        fill!(Yf,0);fill!(Yt,0)
        if k==1;Yf .= y
        elseif subtype=="center_tap";Yt[k-1]=y
        else;Yt .= y;end
    end
    all(isfinite,R) && all(isfinite,Zf) && all(isfinite,Zt) ||
        _sdp_refuse("$label nonfinite effective winding coefficients")
    (;Df=incidence(nf,pf),Dt=incidence(nt,pt),R,Zf,Zt,Yf,Yt,bonds,rating,rated_side,rating_count)
end

function _sdp_stamp_transformers!(net, newvar, terminal_rows, matrows, inject,
                                 equations, devices, limits, zb)
    for (subtype,table) in sort!(collect(get(net,"transformer",Dict()));by=first),
        (id,d) in sort!(collect(table);by=first)
        subtype=="n_winding" && continue
        label="transformer/$subtype/$id"
        p=_sdp_transformer_plan(subtype,d,label)
        vf=terminal_rows(d["bus_from"],d["terminal_map_from"])
        vt=terminal_rows(d["bus_to"],d["terminal_map_to"])
        uf=matrows(p.Df,vf);ut=matrows(p.Dt,vt)
        jf=[_sdp_e(newvar()) for _ in uf];jt=[_sdp_e(newvar()) for _ in ut]
        ef=[_sdp_add!(copy(uf[k]),jf[k],-p.Zf[k]/zb) for k in eachindex(uf)]
        et=[_sdp_add!(copy(ut[k]),jt[k],-p.Zt[k]/zb) for k in eachindex(ut)]
        coupled=matrows(p.R,ef)
        for k in eachindex(et);push!(equations,_sdp_add!(et[k],coupled[k],-1));end
        current=matrows(adjoint(p.R),jt)
        for k in eachindex(jf);push!(equations,_sdp_add!(copy(jf[k]),current[k]));end
        cf=[_sdp_add!(copy(jf[k]),uf[k],p.Yf[k]*zb) for k in eachindex(jf)]
        ct=[_sdp_add!(copy(jt[k]),ut[k],p.Yt[k]*zb) for k in eachindex(jt)]
        tf=matrows(transpose(p.Df),cf);tt=matrows(transpose(p.Dt),ct)
        for (f,t) in p.bonds
            push!(equations,_sdp_add!(copy(vf[f]),vt[t],-1))
            bond=_sdp_e(newvar());_sdp_add!(tf[f],bond);_sdp_add!(tt[t],bond,-1)
        end
        for (side,v,terminals) in ((:from,vf,tf),(:to,vt,tt))
            neutral=get(_kr_neutral_map(net),d["bus_$side"],nothing)
            ni=findfirst(==(neutral),d["terminal_map_$side"])
            ground=_sdp_ground!(d,"r_neutral_$side","x_neutral_$side",ni,v,newvar,equations,zb)
            for k in eachindex(terminals);_sdp_add!(terminals[k],ground[k]);end
        end
        inject(d["bus_from"],d["terminal_map_from"],tf)
        inject(d["bus_to"],d["terminal_map_to"],tt)
        # Include subtype in IDs: BMOPF IDs need not be globally unique.
        key="$subtype/$id"
        for (side,v,i,u,j) in ((:from,vf,tf,uf,jf),(:to,vt,tt,ut,jt))
            push!(devices,(Symbol("transformer_",side),key,v,i,Dict()))
            push!(devices,(Symbol("transformer_coil_",side),key,u,j,Dict()))
            ratingkey="i_max_$side"
            if haskey(d,ratingkey)
                # Delta limits are on winding coils, not their differences at bus terminals.
                delta=(subtype=="delta_wye" && side==:from)||(subtype=="wye_delta" && side==:to)
                push!(limits,(delta ? u : v,delta ? j : i,Dict("i_max"=>d[ratingkey])))
            end
            # s_rating is a schema power base, not an operating limit.
        end
    end
end
