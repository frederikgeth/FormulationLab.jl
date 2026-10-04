# Pendant trees are certified from their leaves toward a retained boundary.
# No source, grounding or device assumption is imposed on that boundary bus.
function _ivrn_regions(net,e)
    buses=sort!(collect(keys(net["bus"])))
    barriers=Dict(b=>String[] for b in buses)
    block(b,reason)=push!(barriers[b],reason)
    for (b,d) in net["bus"]
        length(d["terminal_names"]) in (2,3,4) || block(b,"conductor_count")
        isempty(get(d,"perfectly_grounded_terminals",[])) || block(b,"ideal_ground")
    end
    for (id,d) in net["voltage_source"];block(d["bus"],"source/$id");end
    for (id,d) in get(net,"shunt",Dict())
        any(!iszero,_l3f_shunt_matrix(d,length(d["terminal_map"]))) && block(d["bus"],"shunt/$id")
    end
    for (kind,table) in get(net,"transformer",Dict()),(id,d) in table
        ports=kind=="n_winding" ? [w["bus"] for w in d["windings"]] : [d["bus_from"],d["bus_to"]]
        for b in ports;block(b,"transformer/$kind/$id");end
    end
    for (id,d) in get(net,"switch",Dict()),side in ("from","to")
        block(d["bus_$side"],"switch/$id")
    end
    for (family,id,_,currents,d) in e.devices
        family in (:load,:generator,:capacitor,:ibr) || continue
        cfg=family==:ibr ? Dict("FOUR_LEG"=>"WYE","THREE_LEG"=>"DELTA","SINGLE_PHASE"=>"SINGLE_PHASE")[d["topology"]] : uppercase(d["configuration"])
        D=_sdp_connection(net,d["bus"],d["terminal_map"],cfg,length(currents);
                          neutral=get(e.neutral_map,d["bus"],nothing))
        all(iszero,sum(D;dims=2)) || block(d["bus"],"earth_return/$family/$id")
    end
    lines=Dict(l.id=>l for l in e.lnc_lines)
    adjacency=Dict(b=>Tuple{String,String}[] for b in buses)
    eligible=Set{String}()
    for l in e.lnc_lines
        m=length(l.tmf)
        nf=get(e.neutral_map,l.from,nothing);nt=get(e.neutral_map,l.to,nothing)
        pf=findfirst(==(nf),l.tmf);pt=findfirst(==(nt),l.tmt)
        reason= m ∉ (2,3,4) ? "conductor_count" :
            any(!iszero,l.Yf) || any(!iszero,l.Yt) ? "line_shunt" :
            pf!=pt || m==4 && pf===nothing ? "conductor_roles" : nothing
        if reason!==nothing
            block(l.from,"$reason/$(l.id)");block(l.to,"$reason/$(l.id)")
            continue
        end
        # A branch may use a subset of the boundary conductors. Such a bus
        # stays physical; every peeled interior bus must carry the full set.
        for (b,tm) in ((l.from,l.tmf),(l.to,l.tmt))
            Set(tm)==Set(net["bus"][b]["terminal_names"]) || block(b,"partial_port/$(l.id)")
        end
        push!(eligible,l.id)
        push!(adjacency[l.from],(l.id,l.to));push!(adjacency[l.to],(l.id,l.from))
    end
    for entries in values(adjacency);sort!(entries;by=first);end
    degree=Dict(b=>length(adjacency[b]) for b in buses)
    queue=[b for b in buses if isempty(barriers[b]) && degree[b]==1]
    active=copy(eligible);parent=Dict{String,Tuple{String,String}}();cursor=1
    while cursor<=length(queue)
        b=queue[cursor];cursor+=1
        degree[b]==1 || continue
        edge,t=only([(id,t) for (id,t) in adjacency[b] if id in active])
        parent[b]=(t,edge);delete!(active,edge);degree[b]=0;degree[t]-=1
        isempty(barriers[t]) && degree[t]==1 && push!(queue,t)
    end
    children=Dict(b=>String[] for b in buses)
    for (b,(p,_)) in parent;push!(children[p],b);end
    for entries in values(children);sort!(entries);end
    regions=_IVRDifferencePlan[];descriptions=NamedTuple[]
    for root in buses
        haskey(parent,root) && continue
        for first_child in children[root]
            _,edge=parent[first_child];l=lines[edge]
            tm=sort!(copy(l.from==root ? l.tmf : l.tmt));m=length(tm)
            nt=get(e.neutral_map,root,nothing)
            nt in tm && (filter!(!=(nt),tm);push!(tm,nt))
            terminals=Dict(root=>tm);order=[first_child];ids=String[];index=1
            while index<=length(order)
                b=order[index];index+=1;p,id=parent[b];line=lines[id]
                from,to=line.from==p ? (line.tmf,line.tmt) : (line.tmt,line.tmf)
                terminals[b]=[to[findfirst(==(t),from)] for t in terminals[p]]
                push!(ids,id);append!(order,children[b])
            end
            sort!(ids);omitted=[(b,last(terminals[b])) for b in order]
            rule=m==2 ? :two_wire : m==3 ? :three_wire : :four_wire
            push!(regions,_IVRDifferencePlan(rule,root,terminals,omitted,ids))
            push!(descriptions,(;root,rule,components=ids,interior_buses=sort(order),
                boundary_terminals=copy(tm),omitted_kcl=omitted))
        end
    end
    ids=sort!([id for r in regions for id in r.line_ids])
    omitted=[key for r in regions for key in r.omitted_kcl]
    report=(;status=isempty(regions) ? :inapplicable : :applicable,
        code=isempty(regions) ? :no_certified_regions : :pendant_zero_sum,
        components=ids,regions=descriptions,
        retained_lines=sort!(collect(setdiff(Set(keys(lines)),Set(ids)))),
        retained_buses=[b for b in buses if !haskey(parent,b)],
        boundary_buses=sort!(unique([r.root for r in regions])),
        barriers=Dict(b=>sort!(unique(reasons)) for (b,reasons) in barriers if !isempty(reasons)),
        omitted_kcl=omitted,device_identity=:interior_zero_sum_connection,
        proof=:leaf_kcl,common_mode=:retained_reference_conductor)
    report,isempty(regions) ? nothing : (;regions,omitted_kcl=omitted)
end
