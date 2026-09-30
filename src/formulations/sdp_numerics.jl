# Numerical voltage regions are connected by lines and switches, not by
# transformers. Hints choose coordinates only: they NEVER create a bound or
# replace a declared voltage, tap, winding map, or finite grounding impedance.
function _sdp_state_scales(net,voltage,devices,limits,n,vb,mode)
    d=ones(n)
    mode==:global && return d,(mode=:global,minimum=1.0,maximum=1.0,regions=0,fallback_regions=0)
    buses=sort!(collect(keys(net["bus"])));parent=Dict(b=>b for b in buses)
    function root(b)
        while parent[b]!=b
            parent[b]=parent[parent[b]];b=parent[b]
        end
        b
    end
    for family in ("line","switch"), e in values(get(net,family,Dict()))
        family=="switch" && e["open_switch"] && continue
        a=root(e["bus_from"]);b=root(e["bus_to"]);parent[b]=a
    end
    hints=Dict{String,Vector{Tuple{Int,Float64}}}()
    function hint(bus,raw,priority)
        xs=raw isa Number ? (raw,) : raw
        positive=[Float64(x) for x in xs if isfinite(x) && x>0]
        isempty(positive) || push!(get!(hints,root(bus),Tuple{Int,Float64}[]),(priority,maximum(positive)))
    end
    for s in values(net["voltage_source"]);hint(s["bus"],s["v_magnitude"],3);end
    for (kind,table) in get(net,"transformer",Dict()), t in values(table)
        if kind=="n_winding"
            for w in t["windings"];hint(w["bus"],w["v_nom"],2);end
        else
            for side in ("from","to")
                haskey(t,"v_nom_"*side) && hint(t["bus_"*side],t["v_nom_"*side],2)
            end
        end
    end
    for (b,bus) in net["bus"], key in ("v_max","vpn_max","v_min","vpn_min")
        haskey(bus,key) && hint(b,bus[key],1)
    end
    for l in values(get(net,"load",Dict()))
        haskey(l,"v_nom") && hint(l["bus"],l["v_nom"],1)
    end
    # Powers of two avoid introducing another source of coefficient rounding.
    bounded_scale(x)=exp2(clamp(round(log2(x)),-40,40))
    region=Dict{String,Float64}();fallback=0
    for b in buses
        r=root(b);haskey(region,r) && continue
        hs=get(hints,r,Tuple{Int,Float64}[])
        if isempty(hs)
            region[r]=1.0;fallback+=1
        else
            priority=maximum(first,hs)
            logs=sort!([log2(x/vb) for (p,x) in hs if p==priority])
            region[r]=exp2(clamp(round(sum(logs)/length(logs)),-40,40))
        end
    end
    voltage_set=Set(filter(!iszero,collect(values(voltage))))
    for ((bus,_),i) in voltage;i==0 || (d[i]=region[root(bus)]);end
    channels=vcat([(v,i) for (_,_,v,i,_) in devices],[(v,i) for (v,i,_) in limits])
    # Internal voltage coordinates (e.g. inverter filter EMFs) must not be
    # mistaken for currents merely because an admittance map contains them.
    for (vs,_) in channels, v in vs;union!(voltage_set,keys(v));end
    current_hints=Dict{Int,Tuple{Int,Float64}}()
    for (vs,is) in channels, (v,i) in zip(vs,is)
        # Use the voltage REGION, not the norm of a delta/neutral incidence row.
        # On a uniform-voltage feeder this leaves all state scales equal to one.
        vscale=maximum((d[k] for k in keys(v));init=0.0)
        vscale>0 || continue
        direct=length(i)==1 && abs(only(values(i)))==1
        for (k,c) in i
            k in voltage_set && continue
            iszero(c) && continue
            hint=(direct ? 1 : 0,bounded_scale(inv(vscale)))
            current_hints[k]=max(get(current_hints,k,(-1,0.0)),hint)
        end
    end
    for (k,(_,s)) in current_hints;d[k]=s;end
    d,(mode=mode,minimum=minimum(d;init=1.0),maximum=maximum(d;init=1.0),
        regions=length(region),fallback_regions=fallback)
end

# z=D*x, (A*D)*x=0, then z=(D*Nx)*y. All downstream expressions,
# containment audits, and recovery continue to use the original state units.
function _sdp_scaled_basis(A,kind,scales;diagnostics=nothing)
    all(==(1.0),scales) && return _sdp_basis(A,kind;diagnostics)
    reference=_sdp_basis(A,kind)
    B=A*Diagonal(scales)
    for r in axes(B,1)
        s=norm(B[r,:]);iszero(s) || (B[r,:]./=s)
    end
    N=Diagonal(scales)*_sdp_basis(B,kind;diagnostics)
    residual=norm(A*N,Inf)/max(1.0,norm(A,Inf)*norm(N,Inf))
    fallback=size(N,2)!=size(reference,2) || !isfinite(residual) || residual>1e-10
    if diagnostics!==nothing
        diagnostics[:scaling_basis_fallback]=fallback
        diagnostics[:scaling_basis_residual]=residual
    end
    fallback ? reference : N
end

# Magnitude bounds are indexed by physical voltage maps, including their scale.
# No nominal phase angles or sampled power-flow voltages enter these bounds.
function _sdp_map_key(row)
    isempty(row) && return (),0.0
    entries=sort!(collect(row);by=first)
    c=last(first(entries))
    Tuple((i,a/c) for (i,a) in entries),abs(c)
end

function _sdp_voltage_ranges(net,terminal_rows,fixed)
    ranges=Dict{Tuple,Tuple{Float64,Float64}}()
    for (bus,d) in net["bus"]
        for (prefix,rows) in _sdp_voltage_maps(net,bus,terminal_rows)
            fields=startswith(prefix,"v_") ? (prefix,) : (prefix*"_min",prefix*"_max")
            for field in fields
                haskey(d,field) || continue
                bounds=_sdp_vector(d,field,length(rows))
                for (row,bound) in zip(rows,bounds)
                    bound>=0 || _sdp_refuse("bus/$bus negative voltage bound")
                    key,scale=_sdp_map_key(row)
                    iszero(scale) && continue
                    lo,hi=get(ranges,key,(0.0,Inf))
                    ranges[key]=endswith(field,"min") ? (max(lo,bound/scale),hi) : (lo,min(hi,bound/scale))
                end
            end
        end
    end
    function range(row)
        if all(haskey(fixed,k) for k in keys(row))
            v=abs(sum((a*fixed[k] for (k,a) in row);init=0im))
            return v,v
        end
        key,scale=_sdp_map_key(row)
        lo,hi=get(ranges,key,(0.0,Inf))
        lo*scale,hi*scale
    end
    range
end

# A physical power bound and a positive bound on the SAME coil voltage imply
# an upper current bound. This strengthens, rather than merely rewrites, SDP.
function _sdp_current_bounds(devices,limits,voltage_range)
    bounds=[]
    function add(v,i,smax,label)
        lo,_=voltage_range(v)
        isfinite(smax) && smax>=0 && lo>0 || return
        imax=smax/lo*(1+1e-12) # outward padding, not an interval certificate
        isfinite(imax) && push!(bounds,(i,imax,label))
    end
    for (family,id,v,i,d) in devices
        n=length(v)
        if family==:load && lowercase(get(d,"model","constant_power"))=="constant_power"
            for k in 1:n
                add(v[k],i[k],hypot(d["p_nom"][k],d["q_nom"][k]),"load/$id/$k")
            end
        elseif family in (:generator,:voltage_source,:ibr)
            names=("p_min","p_max","q_min","q_max")
            if all(haskey(d,key) for key in names)
                values=[family==:voltage_source ? d[key] : _sdp_vector(d,key,n) for key in names]
                for k in 1:n
                    p=max(abs(values[1][k]),abs(values[2][k]))
                    q=max(abs(values[3][k]),abs(values[4][k]))
                    add(v[k],i[k],hypot(p,q),"$family/$id/$k")
                end
            end
        end
    end
    for (index,(v,i,d)) in enumerate(limits)
        haskey(d,"s_max") || continue
        smax=_sdp_vector(d,"s_max",length(v))
        existing=_sdp_vector(d,"i_max",length(v);default=fill(Inf,length(v)))
        for k in eachindex(v)
            lo,_=voltage_range(v[k])
            lo>0 && smax[k]/lo<existing[k] && add(v[k],i[k],smax[k],"rating/$index/$k")
        end
    end
    bounds
end

# Power-of-two row scaling is exact in ordinary binary floating-point range.
# Small rows are never amplified: nullspace roundoff in an implied equality
# must not become a unit-sized artificial restriction.
# Merge only identical scaled coefficient vectors, never approximately parallel
# rows. Opposing equal bounds become one equality; conflicting bounds survive.
function _sdp_split_complex_equalities!(model)
    F = JuMP.GenericAffExpr{ComplexF64,JuMP.VariableRef}
    S = JuMP.MOI.EqualTo{ComplexF64}
    refs = JuMP.all_constraints(model, F, S)
    for ref in refs
        object = JuMP.constraint_object(ref)
        residual = object.func - object.set.value
        JuMP.delete(model, ref)
        @constraint(model, real(residual) == 0)
        @constraint(model, imag(residual) == 0)
    end
    length(refs)
end

function _sdp_preprocess_affine!(model; split_complex=false)
    split = split_complex ? _sdp_split_complex_equalities!(model) : 0
    model.ext[:split_complex_equalities] = split
    groups=Dict{Any,Any}()
    count_before=0
    for (F,S) in JuMP.list_of_constraint_types(model)
        F==JuMP.AffExpr || continue
        S in (JuMP.MOI.EqualTo{Float64},JuMP.MOI.LessThan{Float64},JuMP.MOI.GreaterThan{Float64}) || continue
        for ref in JuMP.all_constraints(model,F,S)
            object=JuMP.constraint_object(ref);f=object.func;s=object.set
            terms=sort!([(JuMP.index(v).value,c) for (v,c) in f.terms if !iszero(c)];by=first)
            isempty(terms) && continue
            magnitude=maximum(abs(last(t)) for t in terms)
            scale=copysign(exp2(clamp(floor(log2(magnitude)),0,500)),last(first(terms)))
            key=[(v,c/scale) for (v,c) in terms]
            low=s isa JuMP.MOI.LessThan ? -Inf : (s isa JuMP.MOI.EqualTo ? s.value : s.lower)-f.constant
            high=s isa JuMP.MOI.GreaterThan ? Inf : (s isa JuMP.MOI.EqualTo ? s.value : s.upper)-f.constant
            low,high=scale>0 ? (low/scale,high/scale) : (high/scale,low/scale)
            if haskey(groups,key)
                g=groups[key];g[2]=max(g[2],low);g[3]=min(g[3],high);push!(g[4],ref)
            else
                g=Any[(f-f.constant)/scale,low,high,Any[ref]];groups[key]=g
            end
            count_before+=1
        end
    end
    count_after=0
    for (f,low,high,refs) in values(groups)
        for ref in refs;JuMP.delete(model,ref);end
        if low==high
            @constraint(model,f==low);count_after+=1
        else
            if isfinite(low);@constraint(model,f>=low);count_after+=1;end
            if isfinite(high);@constraint(model,f<=high);count_after+=1;end
        end
    end
    count_before-count_after
end
