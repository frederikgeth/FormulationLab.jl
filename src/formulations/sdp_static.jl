function _sdp_is_impedance_load(d)
    law=lowercase(get(d,"model","constant_power"))
    law=="constant_impedance" && return true
    if law=="exponential"
        return all(k->haskey(d,k) && all(==(2),d[k]),("gamma_p","gamma_q"))
    elseif law=="zip"
        return all(k->haskey(d,k)&&all(==(1),d[k]),("alpha_z","beta_z")) &&
            all(k->haskey(d,k)&&all(iszero,d[k]),("alpha_i","alpha_p","beta_i","beta_p"))
    end
    false
end
function _sdp_has_load_envelope(d)
    law=lowercase(get(d,"model","constant_power"))
    law=="constant_current" && return true
    law=="zip" && return any(k->any(!iszero,get(d,k,[])),("alpha_i","beta_i"))
    law=="exponential" && return any(k->any(x->x ∉ (0,2),get(d,k,[])),("gamma_p","gamma_q"))
    false
end

# Static AC components and physical voltage maps. No controls are evaluated.
function _sdp_scalar(d,k,default=0.0)
    x=get(d,k,default)
    x isa Real && isfinite(x) || _sdp_refuse("$k must be a finite scalar")
    Float64(x)
end
function _sdp_vector(d,k,n;default=nothing)
    haskey(d,k) || return default
    raw=d[k];v=raw isa Real ? fill(Float64(raw),n) : Float64.(raw)
    length(v)==n && all(isfinite,v) || _sdp_refuse("$k requires $n finite values")
    v
end

function _sdp_connection(net,bus,tm,cfg,n;roll=1)
    neutral=get(_kr_neutral_map(net),bus,nothing)
    if cfg=="WYE"
        phases=findall(t->t!=neutral,tm)
        length(phases)==n || _sdp_refuse("$bus wye phase/neutral map mismatch")
        q=findfirst(==(neutral),tm)
        return [Float64(j==phases[k])-Float64(q!==nothing && j==q) for k in 1:n,j in eachindex(tm)]
    elseif cfg=="DELTA" && length(tm)==3 && n==3
        roll in (-1,1) || _sdp_refuse("delta_roll must be -1 or 1")
        return [Float64(j==k)-Float64(j==mod1(k+roll,3)) for k in 1:3,j in 1:3]
    end
    _l3f_connection_incidence(cfg,length(tm),n)
end

# Stamps an internal neutral-earth branch, including an exact ideal ground.
# Return its current separately so winding and terminal ratings are distinguishable.
function _sdp_ground!(d,rkey,xkey,neutral_index,v,newvar,equations,zb)
    result=[_SDPRow() for _ in v]
    haskey(d,rkey) || haskey(d,xkey) || return result
    neutral_index===nothing && _sdp_refuse("$rkey/$xkey require an explicit winding neutral")
    z=complex(_sdp_scalar(d,rkey),_sdp_scalar(d,xkey))
    real(z)>=0 && imag(z)>=0 || _sdp_refuse("negative grounding impedance")
    if iszero(z)
        push!(equations,copy(v[neutral_index]))
        result[neutral_index]=_sdp_e(newvar())
    else
        _sdp_add!(result[neutral_index],v[neutral_index],zb/z)
    end
    result
end

function _sdp_stamp_static!(net,newvar,terminal_rows,matrows,inject,equations,devices,limits,zb)
    for (id,d) in get(net,"switch",Dict())
        _sdp_fields(d,("bus_from","bus_to","terminal_map_from","terminal_map_to","open_switch","i_max","s_max"),"switch/$id")
        get(d,"open_switch",nothing) isa Bool || _sdp_refuse("switch/$id needs a fixed Boolean open_switch")
        vf=terminal_rows(d["bus_from"],d["terminal_map_from"]);vt=terminal_rows(d["bus_to"],d["terminal_map_to"])
        length(vf)==length(vt) || _sdp_refuse("switch/$id map arity mismatch")
        cf=d["open_switch"] ? [_SDPRow() for _ in vf] : [_sdp_e(newvar()) for _ in vf]
        if !d["open_switch"]
            for k in eachindex(vf);push!(equations,_sdp_add!(copy(vf[k]),vt[k],-1));end
        end
        ct=[_sdp_add!(_SDPRow(),i,-1) for i in cf]
        inject(d["bus_from"],d["terminal_map_from"],cf);inject(d["bus_to"],d["terminal_map_to"],ct)
        for (side,v,i) in ((:from,vf,cf),(:to,vt,ct))
            push!(devices,(Symbol("switch_",side),id,v,i,Dict()));push!(limits,(v,i,d))
        end
    end
    for (id,d) in get(net,"capacitor",Dict())
        _sdp_fields(d,("bus","terminal_map","configuration","q_rated","v_nom"),"capacitor/$id")
        q=Float64.(d["q_rated"]);n=length(q)
        all(x->isfinite(x)&&x>=0,q) || _sdp_refuse("capacitor/$id invalid rating")
        vn=_sdp_vector(d,"v_nom",n);vn!==nothing && all(>(0),vn) || _sdp_refuse("capacitor/$id requires positive v_nom")
        tm=d["terminal_map"];v=terminal_rows(d["bus"],tm)
        D=_sdp_connection(net,d["bus"],tm,uppercase(d["configuration"]),n)
        u=matrows(D,v);i=[_sdp_add!(_SDPRow(),u[k],im*q[k]/vn[k]^2*zb) for k in 1:n]
        inject(d["bus"],tm,matrows(transpose(D),i))
        push!(devices,(:capacitor,id,u,i,Dict()))
    end
end

# All magnitude constraints are affine in the same global moment matrix.
function _sdp_voltage_maps(net,b,terminal_rows)
    d=net["bus"][b];tm=d["terminal_names"];v=terminal_rows(b,tm)
    nt=get(_kr_neutral_map(net),b,nothing);ni=findfirst(==(nt),tm)
    ph=findall(t->t!=nt,tm);vp=v[ph]
    pn=[ni===nothing ? copy(r) : _sdp_add!(copy(r),v[ni],-1) for r in vp]
    pp=[_sdp_add!(copy(vp[i]),vp[j],-1) for i in eachindex(vp) for j in i+1:length(vp)]
    maps=Dict("vpn"=>pn,"vpp"=>pp)
    if ni!==nothing;maps["vn"]=[v[ni]];end
    if length(ph)==3
        a=cis(2pi/3)
        declared=get(get(net,"terminal_conventions",Dict()),"phase",["a","b","c"])
        if !(length(declared)==3 && all(t->t in tm[ph],declared));declared=["a","b","c"];end
        seq=length(declared)==3 && all(t->t in tm[ph],declared) ? [findfirst(==(t),tm[ph]) for t in declared] : collect(1:3)
        for (name,coef) in (("vpos",[1,a,a^2]),("vneg",[1,a^2,a]),("vzero",[1,1,1]))
            r=_SDPRow();for k in 1:3;_sdp_add!(r,pn[seq[k]],coef[k]/3);end
            maps[name]=[r]
        end
    end
    # Legacy full-terminal arrays and schema per-phase arrays are both explicit.
    for key in ("v_min","v_max")
        if haskey(d,key)
            n=d[key] isa Real ? 1 : length(d[key])
            maps[key]=n==length(tm) ? v : n==length(ph) ? vp :
                _sdp_refuse("bus/$b $key must match phases or all terminals")
        end
    end
    maps
end
function _sdp_bus_limits!(model,net,terminal_rows,lift,vb;fixed=Dict())
    for (b,d) in net["bus"]
        maps=_sdp_voltage_maps(net,b,terminal_rows)
        for key in ("v_min","v_max","vpn_min","vpn_max","vpp_min","vpp_max","vn_max","vpos_min","vpos_max","vneg_max","vzero_max")
            haskey(d,key) || continue
            prefix=startswith(key,"v_") ? key : first(split(key,"_"))
            haskey(maps,prefix) || _sdp_refuse("bus/$b $key requires the corresponding terminals")
            rows=maps[prefix];bound=_sdp_vector(d,key,length(rows))
            for (r,value) in zip(rows,bound)
                value>=0 || _sdp_refuse("bus/$b negative voltage bound")
                # Source maps are known before the floating-point nullspace.
                # Remove only satisfied fixed bounds; retain contradictions as
                # explicit constant constraints, so infeasibility is preserved.
                if all(haskey(fixed,k) for k in keys(r))
                    known=abs(sum((c*fixed[k] for (k,c) in r);init=0im))
                    satisfied=endswith(key,"min") ? known>=value : known<=value
                    satisfied && continue
                    w=JuMP.AffExpr((known/vb)^2)
                else
                    endswith(key,"min") && iszero(value) && continue
                    # Zero upper voltage maps have been eliminated before lifting.
                    endswith(key,"max") && iszero(value) && continue
                    w=real(lift(r,r))
                end
                lim=(value/vb)^2
                endswith(key,"min") ? @constraint(model,w>=lim) : @constraint(model,w<=lim)
            end
        end
    end
end

# Outer convex envelope of t=x^a. Chords are used only with finite engineering
# bounds; the global epigraph/hypograph remains valid without an upper bound.
function _sdp_power_envelope!(model,x,a,lo,hi)
    a==0 && return 1.0
    a==1 && return x
    t=@variable(model,lower_bound=0)
    if 0<a<1
        @constraint(model,[x,1.0,t] in JuMP.MOI.PowerCone(a))
    elseif a>1
        @constraint(model,[t,1.0,x] in JuMP.MOI.PowerCone(1/a))
    else
        @constraint(model,[t,x,1.0] in JuMP.MOI.PowerCone(1/(1-a)))
    end
    if isfinite(hi) && (a>=0 || lo>0)
        if lo==hi
            @constraint(model,t==lo^a)
        else
            chord=lo^a+(hi^a-lo^a)/(hi-lo)*(x-lo)
            0<a<1 ? @constraint(model,t>=chord) : @constraint(model,t<=chord)
        end
    end
    t
end
function _sdp_load_range(net,b,u,terminal_rows,vb)
    lo=0.0;hi=Inf
    d=net["bus"][b];maps=_sdp_voltage_maps(net,b,terminal_rows)
    for (prefix,rows) in maps
        keys=startswith(prefix,"v_") ? (prefix,) : (prefix*"_min",prefix*"_max")
        for key in keys
            haskey(d,key) || continue
            bounds=_sdp_vector(d,key,length(rows))
            for (r,value) in zip(rows,bounds)
                if r==u || r==_sdp_add!(_SDPRow(),u,-1)
                    endswith(key,"min") ? (lo=max(lo,(value/vb)^2)) : (hi=min(hi,(value/vb)^2))
                end
            end
        end
    end
    lo<=hi || _sdp_refuse("inconsistent load voltage bounds")
    lo,hi
end
function _sdp_load_law!(model,net,id,d,v,s,lift,terminal_rows,vb,sb)
    n=length(v);p=_sdp_vector(d,"p_nom",n);q=_sdp_vector(d,"q_nom",n)
    law=lowercase(get(d,"model","constant_power"))
    _sdp_is_impedance_load(d) && return # already enforced as a linear current law
    vn=law=="constant_power" ? ones(n) : _sdp_vector(d,"v_nom",n)
    vn!==nothing && all(>(0),vn) || _sdp_refuse("load/$id requires positive v_nom")
    if law=="zip"
        for names in (("alpha_z","alpha_i","alpha_p"),("beta_z","beta_i","beta_p"))
            vals=[_sdp_vector(d,k,n) for k in names]
            all(x->x!==nothing,vals) || _sdp_refuse("load/$id requires all ZIP fractions")
            all(x->all(>=(0),x),vals) && all(isapprox.(sum(vals),1;atol=1e-10)) || _sdp_refuse("load/$id invalid ZIP fractions")
        end
    end
    for k in 1:n
        x=real(lift(v[k],v[k]))*(vb/vn[k])^2
        low,high=_sdp_load_range(net,d["bus"],v[k],terminal_rows,vb)
        low*=(vb/vn[k])^2;high*=(vb/vn[k])^2
        cache=Dict{Float64,Any}()
        power(a)=get!(cache,Float64(a)) do;_sdp_power_envelope!(model,x,Float64(a),low,high);end
        rhs = if law=="constant_power"
            (1.0,1.0)
        elseif law=="constant_current"
            (power(0.5),power(0.5))
        elseif law=="zip"
            tuple((sum(_sdp_vector(d,prefix*suffix,n)[k]*power(a) for (suffix,a) in (("_z",1),("_i",0.5),("_p",0))) for prefix in ("alpha","beta"))...)
        elseif law=="exponential"
            gp=_sdp_vector(d,"gamma_p",n);gq=_sdp_vector(d,"gamma_q",n)
            gp!==nothing && gq!==nothing || _sdp_refuse("load/$id requires both exponents")
            (power(gp[k]/2),power(gq[k]/2))
        else
            _sdp_refuse("load/$id unknown voltage law")
        end
        @constraint(model,real(s[k])==p[k]/sb*rhs[1]);@constraint(model,imag(s[k])==q[k]/sb*rhs[2])
    end
end
