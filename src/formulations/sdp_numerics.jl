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
                values=[_sdp_vector(d,key,n) for key in names]
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
function _sdp_preprocess_affine!(model)
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
