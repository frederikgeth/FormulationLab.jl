# Local linear substitutions in solver coordinates. The physical circuit and
# every observation row stay intact for reconstruction and independent audits.
function _ivrn_compose_row(row,maps)
    out=_SDPRow()
    for (k,a) in row;_sdp_add!(out,maps[k],a);end
    out
end

function _ivrn_resolve_row(row,substitutions,cache=Dict{Int,_SDPRow}())
    out=_SDPRow()
    for (k,a) in row
        resolved=get!(cache,k) do
            haskey(substitutions,k) ? _ivrn_resolve_row(substitutions[k],substitutions,cache) : _sdp_e(k)
        end
        _sdp_add!(out,resolved,a)
    end
    out
end

function _ivrn_linear_coordinates(net,e,maps,omitted_kcl,mode)
    substitutions=Dict{Int,_SDPRow}();omitted_equations=Set{Int}()
    loads=String[];buses=String[];retained=Dict{String,String}()
    report()=(;impedance_loads=loads,series_buses=buses,retained_series_buses=retained,
               eliminated_complex_coordinates=length(substitutions))
    mode==:off && return maps,omitted_equations,omitted_kcl,report()
    compose(row)=_ivrn_compose_row(row,maps.reconstruction)
    active(row)=_ivrn_resolve_row(compose(row),substitutions)
    function eliminate!(equation,candidates,added)
        row=active(equation)
        # These local laws admit unit pivots; do not introduce a numerical
        # rank threshold or divide by a small impedance/admittance.
        pivots=sort!([k for k in keys(row) if k in candidates && row[k] in (-1,1)])
        isempty(pivots) && return false
        k=first(pivots);a=row[k]
        replacement=_SDPRow(j=>-v/a for (j,v) in row if j!=k)
        all(isfinite,values(replacement)) || return false
        substitutions[k]=replacement;push!(added,k)
        true
    end
    for load in e.impedance_loads
        added=Int[]
        for (current,index) in zip(load.current,load.equation_indices)
            candidates=Set(keys(active(current)))
            eliminate!(e.equations[index],candidates,added) ||
                error("impedance-current substitution has no unit pivot")
            push!(omitted_equations,index)
        end
        push!(loads,load.id)
    end
    if mode==:passive
        blocked=Set{String}()
        for (b,d) in net["bus"]
            isempty(get(d,"perfectly_grounded_terminals",[])) || push!(blocked,b)
        end
        for family in ("voltage_source","load","generator","ibr","capacitor","shunt","switch"),d in values(get(net,family,Dict()))
            for key in ("bus","bus_from","bus_to");haskey(d,key) && push!(blocked,d[key]);end
        end
        for table in values(get(net,"transformer",Dict())),d in values(table)
            for key in ("bus_from","bus_to");haskey(d,key) && push!(blocked,d[key]);end
            for w in get(d,"windings",[]);push!(blocked,w["bus"]);end
        end
        adjacency=Dict(b=>Any[] for b in keys(net["bus"]))
        for line in e.lnc_lines
            push!(adjacency[line.from],line);push!(adjacency[line.to],line)
        end
        # Nonadjacent eliminations keep each substituted voltage local to a
        # retained neighbour. Longer chains can be considered in a later pass.
        protected=Set{String}()
        for b in sort!(collect(keys(adjacency)))
            lines=sort!(adjacency[b];by=l->l.id)
            length(lines)==2 || continue
            if b in blocked;retained[b]="device_or_ground_boundary";continue;end
            if b in protected;retained[b]="adjacent_elimination";continue;end
            neighbours=[l.from==b ? l.to : l.from for l in lines]
            if b in neighbours || !allunique(neighbours)
                retained[b]="self_loop_or_parallel_pair";continue
            end
            if any(l->!iszero(l.Yf)||!iszero(l.Yt),lines)
                retained[b]="line_shunt";continue
            end
            terminals=net["bus"][b]["terminal_names"]
            if !all(l->Set(l.from==b ? l.tmf : l.tmt)==Set(terminals),lines)
                retained[b]="partial_terminal_map";continue
            end
            line=first(lines)
            current_candidates=Set(k for row in line.current for k in keys(active(row)))
            voltage_candidates=Set(k for t in terminals for k in keys(active(_sdp_e(e.voltage[(b,t)]))))
            added=Int[];kcl_keys=sort!([(b,t) for t in terminals if (b,t) ∉ omitted_kcl])
            ok=all(key->eliminate!(e.kcl[key],current_candidates,added),kcl_keys)
            ok &= all(k->haskey(substitutions,k),current_candidates)
            if ok
                ok=all(index->eliminate!(e.equations[index],voltage_candidates,added),line.equation_indices)
                ok &= all(k->haskey(substitutions,k),voltage_candidates)
            end
            if !ok
                for k in added;delete!(substitutions,k);end
                retained[b]="no_local_unit_pivot";continue
            end
            union!(omitted_kcl,kcl_keys);union!(omitted_equations,line.equation_indices)
            union!(protected,neighbours);push!(buses,b)
        end
    end
    kept=[k for k in eachindex(maps.projection) if !haskey(substitutions,k)]
    numbering=Dict(k=>j for (j,k) in enumerate(kept));cache=Dict{Int,_SDPRow}()
    reconstruction=[_SDPRow(numbering[k]=>a for (k,a) in _ivrn_resolve_row(row,substitutions,cache))
                    for row in maps.reconstruction]
    ((;projection=maps.projection[kept],reconstruction),omitted_equations,omitted_kcl,report())
end
