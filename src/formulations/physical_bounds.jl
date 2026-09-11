# Magnitude interval propagation for homogeneous complex electrical equations.
# Internal quantities are per unit. Nominal values never become operating bounds.
"""Physical magnitude intervals in per unit, last-tightening provenance and absent DER capability fields."""
struct PhysicalBoundReport
    entries::Vector{NamedTuple}
    missing_capabilities::Vector{NamedTuple}
    sweeps::Int
end

function _sdp_bound_profile(net,terminal_rows,fixed,equations,devices,limits,n,vb,ib;sweeps=8)
    lower=zeros(n);upper=fill(Inf,n);origin=fill("unbounded",n)
    relations=Vector{Tuple{Int,ComplexF64}}[[(i,c) for (i,c) in row] for row in equations]
    indices=Dict{Any,Int}();labels=Dict{Int,String}()
    function register(row,label="electrical map")
        isempty(row) && return 0,1.0
        key,scale=_sdp_map_key(row)
        idx=get!(indices,key) do
            if length(key)==1
                first(first(key))
            else
                push!(lower,0.0);push!(upper,Inf);push!(origin,"unbounded")
                j=length(lower)
                push!(relations,[(i,ComplexF64(c)) for (i,c) in key])
                push!(relations[end],(j,-1.0+0im));j
            end
        end
        get!(labels,idx,label)
        idx,scale
    end
    function seed(row,lo,hi,label)
        idx,scale=register(row,label);idx==0 && return
        if lo/scale>lower[idx] || hi/scale<upper[idx]
            lower[idx]=max(lower[idx],lo/scale);upper[idx]=min(upper[idx],hi/scale)
            origin[idx]=label
        end
    end
    for (i,value) in fixed;seed(_sdp_e(i),abs(value),abs(value),"fixed source");end
    for (bus,_) in sort!(collect(net["bus"]);by=first)
        d=net["bus"][bus]
        for (prefix,rows) in sort!(collect(_sdp_voltage_maps(net,bus,terminal_rows));by=first)
            for row in rows;register(row,"bus/$bus/$prefix");end
            fields=startswith(prefix,"v_") ? (prefix,) : (prefix*"_min",prefix*"_max")
            for field in fields
                haskey(d,field) || continue
                for (r,bound) in zip(rows,_sdp_vector(d,field,length(rows)))
                    seed(r,endswith(field,"min") ? bound/vb : 0.0,endswith(field,"max") ? bound/vb : Inf,"declared bus/$bus/$field")
                end
            end
        end
    end
    for (family,id,v,i,_) in devices,k in eachindex(v)
        register(v[k],"$family/$id/voltage/$k");register(i[k],"$family/$id/current/$k")
    end
    for (v,i,d) in limits
        for row in v;register(row);end
        for row in i;register(row);end
        haskey(d,"i_max") || continue
        for (r,bound) in zip(i,_sdp_vector(d,"i_max",length(i)));seed(r,0.,bound/ib,"declared current limit");end
    end
    function range(row)
        isempty(row) && return (0.0,0.0)
        if all(haskey(fixed,k) for k in keys(row))
            a=abs(sum(c*fixed[k] for (k,c) in row));return a,a
        end
        key,scale=_sdp_map_key(row);idx=get(indices,key,0)
        idx==0 ? (0.0,Inf) : (lower[idx]*scale,upper[idx]*scale)
    end
    # Power boxes and nameplates bound current on the same physical coil.
    function power_bounds!()
        for (row,imax,label) in _sdp_current_bounds(devices,limits,r->vb.*range(r))
            seed(row,0.,imax/ib,"derived $label from power and voltage")
        end
    end
    # Cancellation in a sum of known source phasors is evaluated exactly above.
    # Propagation uses triangle inequalities only; no operating angles are guessed.
    for pass in 1:sweeps
        power_bounds!()
        for terms in relations
            for (idx,c) in terms
                iszero(c) && continue
                rest=0.0
                for (j,a) in terms;j==idx || (rest+=abs(a)*upper[j]);end
                for (j,a) in terms
                    j==idx && continue
                    other=sum((abs(b)*upper[k] for (k,b) in terms if k!=idx && k!=j);init=0.0)
                    candidate=max(0.0,(abs(a)*lower[j]-other)/abs(c))
                    candidate=isfinite(candidate) ? max(0.0,prevfloat(candidate*(1-1e-10))) : 0.0
                    if lower[idx]<candidate<=upper[idx]
                        lower[idx]=candidate;origin[idx]="derived reverse triangle inequality (electrical equations)"
                    end
                end
                if isfinite(rest)
                    candidate=rest/abs(c)
                    # Outward padding; do not create a numerical zero face.
                    candidate=candidate==0 ? 0.0 : nextfloat(candidate*(1+1e-10))
                    if candidate<upper[idx] && candidate>=lower[idx]
                        upper[idx]=candidate;origin[idx]="derived triangle inequality (electrical equations)"
                    end
                end
            end
        end
    end
    power_bounds!()
    entries=[(map=collect(key),lower_pu=lower[idx],upper_pu=upper[idx],provenance=origin[idx],label=get(labels,idx,"state/$idx")) for (key,idx) in sort!(collect(indices);by=x->string(first(x)))]
    missing=NamedTuple[]
    for family in ("generator","ibr"),(id,d) in sort!(collect(get(net,family,Dict()));by=first)
        fields=[k for k in ("q_min","q_max","s_max","i_max") if !haskey(d,k)]
        isempty(fields) || push!(missing,(component="$family/$id",fields=fields))
    end
    range,PhysicalBoundReport(entries,missing,sweeps)
end
