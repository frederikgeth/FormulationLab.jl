# A deliberately narrow certificate for one complete, source-rooted section.
# This uses declared connections, never today's injection or solved currents.
struct _IVRDifferencePlan
    rule::Symbol
    root::String
    terminals::Dict{String,Vector{String}}
    omitted_kcl::Vector{Tuple{String,String}}
    line_ids::Vector{String}
end

function _ivrn_structure(net,e)
    decline(code,ids=String[])=((;status=:inapplicable,code,components=ids),nothing)
    transformers=sort!(["$kind/$id" for (kind,table) in get(net,"transformer",Dict()) for id in keys(table)])
    isempty(transformers) || return decline(:transformer_boundary,transformers)
    switches=sort!(collect(keys(get(net,"switch",Dict()))))
    isempty(switches) || return decline(:switch_boundary,switches)
    sources=net["voltage_source"]
    length(sources)==1 || return decline(:multiple_sources,sort!(collect(keys(sources))))
    source_id=only(keys(sources));source=sources[source_id];root=source["bus"]
    tm=String.(net["bus"][root]["terminal_names"]);m=length(tm)
    m in (2,3,4) || return decline(:conductor_count,[root])
    fixed=union(Set(source["terminal_map"]),Set(get(net["bus"][root],"perfectly_grounded_terminals",String[])))
    for s in values(get(net,"shunt",Dict()))
        s["bus"]==root && length(s["terminal_map"])==1 || continue
        y=only(_l3f_shunt_matrix(s,1))
        isfinite(y) && !iszero(y) && push!(fixed,only(s["terminal_map"]))
    end
    fixed==Set(tm) || return decline(:source_boundary,[source_id])
    neutral=e.neutral_map;rn=get(neutral,root,nothing)
    m==4 && rn===nothing && return decline(:neutral_role,[root])
    # Choose a physical reference conductor last; conductor order at every
    # other bus is propagated through the actual terminal maps of tree edges.
    sort!(tm)
    rn===nothing || (filter!(!=(rn),tm);push!(tm,rn))
    for (id,b) in sort!(collect(net["bus"]);by=first)
        length(b["terminal_names"])==m || return decline(:conductor_count,[id])
        id!=root && !isempty(get(b,"perfectly_grounded_terminals",[])) &&
            return decline(:downstream_ground,[id])
    end
    for (id,s) in sort!(collect(get(net,"shunt",Dict()));by=first)
        s["bus"]==root && continue # Root KCL and shunt laws remain in full.
        any(!iszero,_l3f_shunt_matrix(s,length(s["terminal_map"]))) &&
            return decline(:bus_shunt,[id])
    end
    adjacency=Dict(b=>Tuple{String,String,Vector{String},Vector{String}}[] for b in keys(net["bus"]))
    for l in e.lnc_lines
        (any(!iszero,l.Yf) || any(!iszero,l.Yt)) && return decline(:line_shunt,[l.id])
        length(l.tmf)==m && Set(l.tmf)==Set(net["bus"][l.from]["terminal_names"]) &&
            Set(l.tmt)==Set(net["bus"][l.to]["terminal_names"]) ||
            return decline(:conductor_continuity,[l.id])
        push!(adjacency[l.from],(l.id,l.to,l.tmf,l.tmt))
        push!(adjacency[l.to],(l.id,l.from,l.tmt,l.tmf))
    end
    terminals=Dict(root=>tm);queue=[root];cursor=1;visited_edges=Set{String}()
    while cursor<=length(queue)
        b=queue[cursor];cursor+=1
        for (id,t,from,to) in sort!(adjacency[b];by=first)
            id in visited_edges && continue
            push!(visited_edges,id)
            haskey(terminals,t) && return decline(:cycle,[id])
            terminals[t]=[to[findfirst(==(terminal),from)] for terminal in terminals[b]]
            tn=get(neutral,t,nothing)
            (rn===nothing ? tn===nothing : tn==last(terminals[t])) ||
                return decline(:conductor_roles,[id,t])
            push!(queue,t)
        end
    end
    length(queue)==length(net["bus"]) || return decline(:disconnected,
        sort!(collect(setdiff(Set(keys(net["bus"])),Set(queue)))))
    isempty(visited_edges) && return decline(:no_lines,[root])
    for (family,id,_,currents,d) in e.devices
        family in (:load,:generator,:capacitor,:ibr) || continue
        # Root KCL is retained in full. Only downstream device identities are
        # needed for the subtree proof; root devices may exchange with earth.
        d["bus"]==root && continue
        cfg=family==:ibr ? Dict("FOUR_LEG"=>"WYE","THREE_LEG"=>"DELTA","SINGLE_PHASE"=>"SINGLE_PHASE")[d["topology"]] : uppercase(d["configuration"])
        D=_sdp_connection(net,d["bus"],d["terminal_map"],cfg,length(currents);
                          neutral=get(neutral,d["bus"],nothing))
        all(iszero,sum(D;dims=2)) || return decline(:earth_return_device,["$family/$id"])
    end
    rule=m==2 ? :two_wire : m==3 ? :three_wire : :four_wire
    omitted=[(b,last(terminals[b])) for b in queue if b!=root]
    ids=sort!(collect(visited_edges))
    plan=_IVRDifferencePlan(rule,root,terminals,omitted,ids)
    report=(;status=:applicable,code=:radial_zero_sum,components=ids,rule,root,
        omitted_kcl=omitted,device_identity=:downstream_zero_sum_connection,
        proof=:subtree_kcl,common_mode=:retained_reference_conductor)
    report,plan
end

# Sparse local operations only. projection maps full physical coordinates to
# solver coordinates; reconstruction maps solver coordinates back. No dense
# network-wide nullspace or least-squares projection is constructed.
function _ivrn_coordinates(e,plan)
    n=e.coordinate_count[]
    reconstruction=[_SDPRow() for _ in 1:n];projection=_SDPRow[];used=BitSet()
    add_coordinate(row)=(push!(projection,row);length(projection))
    plans=plan===nothing ? _IVRDifferencePlan[] : plan isa _IVRDifferencePlan ? [plan] : plan.regions
    lines=isempty(plans) ? nothing : Dict(l.id=>l for l in e.lnc_lines)
    for plan in plans
        map=_conductor_difference(plan.rule);P=map.voltage;m=size(P,2)
        # The last conductor voltage remains explicit, preserving local
        # neutral/phase-ground limits and avoiding long path substitutions.
        V=vcat(P,reshape([zeros(m-1);1.],1,m));B=inv(V)
        for b in sort!(collect(keys(plan.terminals)))
            b==plan.root && continue
            cols=[e.voltage[(b,t)] for t in plan.terminals[b]]
            new=[add_coordinate(_SDPRow(cols[j]=>ComplexF64(V[k,j]) for j in 1:m if !iszero(V[k,j]))) for k in 1:m]
            for j in 1:m
                reconstruction[cols[j]]=_SDPRow(new[k]=>ComplexF64(B[j,k]) for k in 1:m if !iszero(B[j,k]))
            end
            union!(used,cols)
        end
        for id in plan.line_ids
            l=lines[id]
            cols=[only(keys(l.current[findfirst(==(t),l.tmf)])) for t in plan.terminals[l.from]]
            new=[add_coordinate(_SDPRow(cols[j]=>ComplexF64(map.current_projection[k,j]) for j in 1:m
                                        if !iszero(map.current_projection[k,j]))) for k in 1:m-1]
            for j in 1:m
                reconstruction[cols[j]]=_SDPRow(new[k]=>ComplexF64(P[k,j]) for k in 1:m-1 if !iszero(P[k,j]))
            end
            union!(used,cols)
        end
    end
    for k in 1:n
        k in used && continue
        reconstruction[k]=_sdp_e(add_coordinate(_sdp_e(k)))
    end
    (;projection,reconstruction)
end
