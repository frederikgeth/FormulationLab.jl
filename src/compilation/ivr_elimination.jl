# Local linear substitutions in solver coordinates. The physical circuit and
# every observation row stay intact for reconstruction and independent audits.
function _ivrn_compose_row(row,maps)
    out=_SDPRow()
    for (k,a) in row;_sdp_add!(out,maps[k],a);end
    out
end

# Independent of line elimination: remove only recorded from-side coil-current
# coordinates through surviving unit pivots. No inverse of leakage, incidence,
# or the possibly rectangular winding ratio is required. Each device is atomic.
function _ivrn_device_coordinates(net,e,maps,omitted_equations,mode)
    selected=String[];retained=Dict{String,String}();consumed=Int[]
    substitutions=Dict{Int,_SDPRow}()
    report()=(;transformers=selected,retained_transformers=retained,
        equation_indices=consumed,eliminated_complex_coordinates=length(substitutions))
    mode==:off && return maps,omitted_equations,report()
    for id in keys(get(get(net,"transformer",Dict()),"n_winding",Dict()))
        retained["n_winding/$id"]="separate_certificate_required"
    end
    active(row)=_ivrn_resolve_row(_ivrn_compose_row(row,maps.reconstruction),substitutions)
    for device in e.transformer_current_balances
        if isempty(device.current) || length(device.current)!=length(device.equation_indices) || !allunique(device.equation_indices)
            retained[device.id]="incomplete_balance_record";continue
        end
        added=Int[];reason=nothing
        for (current,index) in zip(device.current,device.equation_indices)
            if index in omitted_equations
                reason="balance_equation_already_consumed";break
            end
            target=active(current)
            if length(target)!=1 || only(values(target)) ∉ (-1,1)
                reason="from_current_not_a_retained_coordinate";break
            end
            k=only(keys(target));row=active(e.equations[index]);a=get(row,k,0)
            if a ∉ (-1,1)
                reason="no_surviving_unit_pivot";break
            end
            replacement=_SDPRow(j=>-v/a for (j,v) in row if j!=k)
            if !all(isfinite,values(replacement))
                reason="nonfinite_substitution";break
            end
            substitutions[k]=replacement;push!(added,k)
        end
        if reason!==nothing
            for k in added;delete!(substitutions,k);end
            retained[device.id]=reason;continue
        end
        push!(selected,device.id);append!(consumed,device.equation_indices)
        union!(omitted_equations,device.equation_indices)
    end
    isempty(substitutions) && return maps,omitted_equations,report()
    kept=[k for k in eachindex(maps.projection) if !haskey(substitutions,k)]
    numbering=Dict(k=>j for (j,k) in enumerate(kept));cache=Dict{Int,_SDPRow}()
    reconstruction=[_SDPRow(numbering[k]=>a for (k,a) in _ivrn_resolve_row(row,substitutions,cache))
                    for row in maps.reconstruction]
    ((;projection=maps.projection[kept],reconstruction),omitted_equations,report())
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

# A series candidate touches only its bus voltages and one line's currents.
# Device boundaries are excluded, so other device equations/objectives are
# unchanged. Index the same bus-bound rows and physical limit records used by
# the compiler; output-only power observations are deliberately not a score.
function _ivrn_series_bound_index(net,e,maps,adjacency,blocked;all_bounds=false)
    # A superset of possible targets: ignoring shunts/terminal mismatches and
    # future neighbour protection here can only retain extra index records.
    buses=Set{String}();coordinates=Set{Int}()
    for (b,lines) in adjacency
        length(lines)==2 && b ∉ blocked || continue
        push!(buses,b)
        for t in net["bus"][b]["terminal_names"];push!(coordinates,e.voltage[(b,t)]);end
        line=first(sort!(lines;by=l->l.id))
        for row in line.current;union!(coordinates,keys(row));end
    end
    all_bounds && union!(buses,keys(net["bus"]))
    bounds=NamedTuple[];index=Dict{Int,Vector{Int}}()
    function add!(label,rows)
        all_bounds || any(row->any(in(coordinates),keys(row)),rows) || return
        touched=Set(k for row in rows for k in keys(row) if k in coordinates)
        transformed=map(row->_ivrn_compose_row(row,maps.reconstruction),rows)
        push!(bounds,(;label,rows=transformed));id=length(bounds)
        for k in touched
            push!(get!(Vector{Int},index,k),id)
        end
    end
    _ivrn_each_bus_limit(net,e;buses) do b,key,row,bound
        endswith(key,"max") || bound>0 || return
        add!("bus/$b/$key",(row,))
    end
    for (id,(v,i,d)) in enumerate(e.limits)
        imax=e.values_for(d,"i_max",length(i));smax=e.values_for(d,"s_max",length(v))
        for k in eachindex(v)
            imax===nothing || add!("limit/$id/i_max/$k",(i[k],))
            smax===nothing || add!("limit/$id/s_max/$k",(v[k],i[k]))
        end
    end
    (;bounds,index)
end

function _ivrn_bound_support_width(rows,active)
    a=active(first(rows))
    length(rows)==1 && return length(a)
    isempty(a) && return 0
    b=active(last(rows));isempty(b) && return 0
    # Bounds contain one magnitude row or two power-factor rows. Avoid set
    # materialization for their union; no coefficient/rank threshold is used.
    length(a)+count(k->!haskey(a,k),keys(b))
end

# Conditional exact Schur substitution, in the existing current-voltage rows.
# Row equilibration and a conservative condition gate protect floating-point
# reconstruction. No pseudoinverse, regularization or coefficient truncation.
function _ivrn_block_substitution(rows,targets)
    columns=sort!(collect(targets));n=length(columns)
    n>0 && length(rows)==n || return nothing,"incomplete_local_block"
    external=sort!(collect(setdiff(Set(k for row in rows for k in keys(row)),targets)))
    A=ComplexF64[get(row,k,0im) for row in rows,k in columns]
    B=ComplexF64[get(row,k,0im) for row in rows,k in external]
    scales=maximum(abs,A;dims=2)
    all(x->isfinite(x)&&x>0,scales) || return nothing,"singular_local_block"
    A ./= scales;B ./= scales
    all(isfinite,B) || return nothing,"nonfinite_local_block"
    condition=cond(A)
    isfinite(condition) && condition<=1e8 || return nothing,"ill_conditioned_local_block"
    X=-(lu(A)\B)
    all(isfinite,X) || return nothing,"nonfinite_local_block"
    residual=norm(A*X+B,Inf)/max(1.,norm(A,Inf)*norm(X,Inf),norm(B,Inf))
    residual<=1e-12 || return nothing,"inaccurate_local_block"
    substitutions=Dict(columns[j]=>_SDPRow(k=>X[j,h] for (h,k) in enumerate(external) if !iszero(X[j,h])) for j in 1:n)
    (;substitutions,condition,relative_residual=residual,dimension=n),"accepted"
end

function _ivrn_linear_coordinates(net,e,maps,omitted_kcl,mode;series_selection=:all,component_limit=4)
    substitutions=Dict{Int,_SDPRow}();omitted_equations=Set{Int}()
    loads=String[];buses=String[];retained=Dict{String,String}()
    selected_lines=Dict{String,String}()
    block_diagnostics=Dict{String,Any}()
    support_rejections=Dict{String,Vector{NamedTuple}}()
    hybrid=mode==:passive_hybrid
    # Every accepted member points to its sorted component. Update only after
    # the entire local substitution and optional support check have committed.
    components=Dict{String,Vector{String}}()
    component_rejections=Dict{String,Int}()
    component_groups()=[components[b] for b in sort!(collect(keys(components))) if first(components[b])==b]
    report()=(;impedance_loads=loads,series_buses=buses,retained_series_buses=retained,
               series_selection,selected_series_lines=selected_lines,bound_support_rejections=support_rejections,
               block_diagnostics,eliminated_complex_coordinates=length(substitutions),
               component_limit=hybrid ? component_limit : nothing,
               eliminated_components=component_groups(),
               max_component_buses=maximum(length,values(components);init=0),
               component_limit_rejections=component_rejections)
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
    if mode in (:passive,:passive_chains,:passive_blocks,:passive_hybrid)
        chains=mode in (:passive_chains,:passive_blocks,:passive_hybrid);blocks=mode in (:passive_blocks,:passive_hybrid)
        bound_index=nothing # Build only when a structurally eligible bus exists.
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
        # The original passive policy retains neighbours. The chain policy
        # instead consumes each defining equation at most once.
        protected=Set{String}()
        for b in sort!(collect(keys(adjacency)))
            lines=sort!(adjacency[b];by=l->l.id)
            length(lines)==2 || continue
            if b in blocked;retained[b]="device_or_ground_boundary";continue;end
            if !chains && b in protected;retained[b]="adjacent_elimination";continue;end
            neighbours=[l.from==b ? l.to : l.from for l in lines]
            if b in neighbours || !allunique(neighbours)
                retained[b]="self_loop_or_parallel_pair";continue
            end
            if !blocks && any(l->!iszero(l.Yf)||!iszero(l.Yt),lines)
                retained[b]="line_shunt";continue
            end
            terminals=net["bus"][b]["terminal_names"]
            if !all(l->Set(l.from==b ? l.tmf : l.tmt)==Set(terminals),lines)
                retained[b]="partial_terminal_map";continue
            end
            merged=String[]
            if hybrid
                members=Set([b])
                for neighbour in neighbours;union!(members,get(components,neighbour,String[]));end
                if length(members)>component_limit
                    retained[b]="eliminated_component_limit"
                    component_rejections[b]=length(members)
                    continue
                end
                merged=sort!(collect(members))
            end
            candidates=chains ? filter(l->all(i->i ∉ omitted_equations,l.equation_indices),lines) : lines[1:1]
            isempty(candidates) && (retained[b]="no_surviving_line_equations")
            for line in candidates
                # In chain mode a previous bus's observations can depend on a
                # coordinate eliminated here. Check every original bound after
                # composition; the local physical-coordinate index is insufficient.
                affected=Int[];before=Int[]
                if series_selection==:bound_support
                    bound_index===nothing && (bound_index=_ivrn_series_bound_index(net,e,maps,adjacency,blocked;all_bounds=chains))
                    physical=union(Set(e.voltage[(b,t)] for t in terminals),
                                   (Set(keys(row)) for row in line.current)...)
                    affected=chains ? collect(eachindex(bound_index.bounds)) :
                        sort!(unique!([id for k in physical for id in get(bound_index.index,k,Int[])]))
                    cache=Dict{Int,_SDPRow}()
                    resolve(row)=_ivrn_resolve_row(row,substitutions,cache)
                    before=[_ivrn_bound_support_width(bound_index.bounds[id].rows,resolve) for id in affected]
                end
                current_candidates=Set(k for row in line.current for k in keys(active(row)))
                voltage_candidates=Set(k for t in terminals for k in keys(active(_sdp_e(e.voltage[(b,t)]))))
                added=Int[];kcl_keys=sort!([(b,t) for t in terminals if (b,t) ∉ omitted_kcl])
                if blocks
                    rows=[active(e.kcl[key]) for key in kcl_keys]
                    append!(rows,[active(e.equations[index]) for index in line.equation_indices])
                    block,reason=_ivrn_block_substitution(rows,union(current_candidates,voltage_candidates))
                    ok=block!==nothing
                    if ok
                        merge!(substitutions,block.substitutions);append!(added,keys(block.substitutions))
                    else
                        retained[b]=reason;continue
                    end
                else
                    ok=all(key->eliminate!(e.kcl[key],current_candidates,added),kcl_keys)
                    ok &= all(k->haskey(substitutions,k),current_candidates)
                    if ok
                        ok=all(index->eliminate!(e.equations[index],voltage_candidates,added),line.equation_indices)
                        ok &= all(k->haskey(substitutions,k),voltage_candidates)
                    end
                end
                if !ok
                    for k in added;delete!(substitutions,k);end
                    retained[b]="no_local_unit_pivot";continue
                end
                if bound_index!==nothing
                    expansions=NamedTuple[]
                    cache=Dict{Int,_SDPRow}() # Never reuse a pre-substitution cache.
                    resolve_after(row)=_ivrn_resolve_row(row,substitutions,cache)
                    for (id,width) in zip(affected,before)
                        bound=bound_index.bounds[id];after=_ivrn_bound_support_width(bound.rows,resolve_after)
                        after>width && push!(expansions,(;label=bound.label,before=width,after))
                    end
                    if !isempty(expansions)
                        for k in added;delete!(substitutions,k);end
                        retained[b]="operating_bound_support_expansion";support_rejections[b]=expansions
                        continue
                    end
                end
                union!(omitted_kcl,kcl_keys);union!(omitted_equations,line.equation_indices)
                chains || union!(protected,neighbours)
                push!(buses,b);selected_lines[b]=line.id
                if hybrid
                    for member in merged;components[member]=merged;end
                end
                blocks && (block_diagnostics[b]=(;condition=block.condition,relative_residual=block.relative_residual,dimension=block.dimension))
                delete!(retained,b);delete!(support_rejections,b)
                break
            end
        end
    end
    isempty(substitutions) && return maps,omitted_equations,omitted_kcl,report()
    kept=[k for k in eachindex(maps.projection) if !haskey(substitutions,k)]
    numbering=Dict(k=>j for (j,k) in enumerate(kept));cache=Dict{Int,_SDPRow}()
    reconstruction=[_SDPRow(numbering[k]=>a for (k,a) in _ivrn_resolve_row(row,substitutions,cache))
                    for row in maps.reconstruction]
    ((;projection=maps.projection[kept],reconstruction),omitted_equations,omitted_kcl,report())
end
