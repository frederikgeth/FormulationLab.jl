# Input normalization is performed on the private SI snapshot, before neutral
# reduction or lowering. Retained parser extras are not electrical defaults.
function _l3f_normalize_inputs!(findings, net, options)
    conventions=get(net,"terminal_conventions",Dict())
    phases=string.(get(conventions,"phase",String[]))
    neutrals=string.(get(conventions,"neutral",String[]))
    for (kind,table) in get(net,"transformer",Dict()), (id,d) in table
        if options.infer_terminal_maps && kind in ("delta_wye","wye_delta")
            for side in ("from","to")
                key="terminal_map_$side";haskey(d,key) && continue
                bus=get(get(net,"bus",Dict()),get(d,"bus_$side",""),Dict())
                terminals=string.(get(bus,"terminal_names",String[]))
                wye=(kind=="delta_wye")==(side=="to")
                ns=intersect(neutrals,terminals)
                # Require declared ordered phase identities, and at most one
                # neutral. Never choose three terminals by dictionary order.
                if length(phases)==3 && allunique(phases) &&
                   isempty(intersect(phases,neutrals)) && all(in(terminals),phases) &&
                   length(ns)<=1 && isempty(setdiff(terminals,[phases;ns]))
                    d[key]=wye ? [phases;ns] : copy(phases)
                    _l3f_info!(findings,"L.L3F.TERMINAL_MAP_INFERRED",:transformer,id,
                        "$key inferred from declared terminal conventions";
                        evidence=Dict("field"=>key,"value"=>copy(d[key])))
                else
                    _l3f_error!(findings,"E.L3F.TERMINAL_MAP_AMBIGUOUS",:transformer,id,
                        "cannot infer $key unambiguously; supply an explicit map")
                end
            end
        end
        aliases=filter(k->haskey(d,k),("r_series","x_series"))
        if !isempty(aliases)
            canonical=("r_series_from","x_series_from","r_series_to","x_series_to")
            if options.transformer_impedance==:unspecified
                _l3f_error!(findings,"E.L3F.IMPEDANCE_CONVENTION_REQUIRED",:transformer,id,
                    "r_series/x_series require transformer_impedance=:from_terminal or :from_coil";
                    evidence=Dict(k=>d[k] for k in aliases))
            elseif kind ∉ ("delta_wye","wye_delta","single_phase") || any(k->haskey(d,k),canonical)
                _l3f_error!(findings,"E.L3F.IMPEDANCE_ALIAS_CONFLICT",:transformer,id,
                    "impedance aliases require a supported bank and no side-specific impedance fields")
            elseif any(k->!(d[k] isa Real && !(d[k] isa Bool) && isfinite(d[k])),aliases)
                _l3f_error!(findings,"E.L3F.IMPEDANCE_ALIAS_INVALID",:transformer,id,
                    "impedance aliases must be finite numeric scalars")
            else
                original=Dict(k=>d[k] for k in aliases)
                # Existing Yd/Dy leakage lowering uses terminal-equivalent ohms:
                # Z_wye,eq = Z_from,eq / N² for Dy. A delta coil is 3 Z_terminal.
                factor=options.transformer_impedance==:from_coil && kind=="delta_wye" ? 1/3 : 1.0
                for k in aliases;d[k*"_from"]=factor*d[k];delete!(d,k);end
                _l3f_info!(findings,"L.L3F.IMPEDANCE_ALIAS_NORMALIZED",:transformer,id,
                    "total primary-referred leakage normalized to side-specific terminal-equivalent ohms";
                    evidence=Dict("original"=>original,"convention"=>String(options.transformer_impedance),"factor"=>factor))
            end
        end
        known=Set(("r_series","x_series","r_series_from","x_series_from","r_series_to","x_series_to",
            "r_neutral_from","x_neutral_from","r_neutral_to","x_neutral_to","g_no_load","b_no_load",
            "v_nom_from","v_nom_to","i_max_from","i_max_to","s_rating","tap","tap_min","tap_max",
            "tap_ratio","tap_ratio_min","tap_ratio_max","no_load_shunt"))
        for k in keys(d)
            key=String(k)
            if occursin(r"^([rxgbz]_|v_nom|i_max|s_rating|tap|impedance|no_load)"i,key) && key ∉ known
                _l3f_error!(findings,"E.L3F.UNCONSUMED_ELECTRICAL_FIELD",:transformer,id,
                    "unrecognized transformer electrical field '$key'";
                    evidence=Dict("field"=>key,"value"=>d[k]))
            end
        end
    end
end

# First meshed version supports line cycles only. A transformer must be a bridge
# of the bus multigraph; removing it must disconnect its endpoints.
function _l3f_mesh_contract!(findings,net,topology)
    adjacency=Dict{String,Vector{Tuple{String,Int}}}()
    for (i,e) in enumerate(topology)
        push!(get!(adjacency,e.parent,Tuple{String,Int}[]),(e.child,i))
        push!(get!(adjacency,e.child,Tuple{String,Int}[]),(e.parent,i))
    end
    for (i,e) in enumerate(topology)
        e.family==:transformer || continue
        seen=Set([e.parent]);queue=[e.parent]
        for u in queue, (v,j) in get(adjacency,u,Tuple{String,Int}[])
            j==i && continue
            v in seen && continue
            push!(seen,v);push!(queue,v)
        end
        e.child in seen && _l3f_error!(findings,"E.L3F.MESH_TRANSFORMER_CYCLE",:transformer,e.id,
            "meshed_linear currently requires transformers to be bus-graph bridges")
    end
    _l3f_warning!(findings,"A.L3F.MESH_LINEARIZED",:network,nothing,
        "all lines retained with nodal power balance and fixed-reference magnitude/angle drops; no AC feasibility guarantee")
end

# Angle deviations are local to each line-connected terminal region. Transformer
# bridges need no cycle equation between regions. One gauge per region is fixed.
function _l3f_mesh_angles!(model,variables,constraints,net,topology,reference,p,q)
    theta=Dict{Tuple{String,String},JuMP.VariableRef}()
    adjacency=Dict{Tuple{String,String},Vector{Tuple{String,String}}}()
    for e in topology
        e.family==:line || continue
        Z=_l3f_series_matrix(net,net["line"][e.id],length(e.parent_map),e.id)
        vf=[reference.voltage[(e.parent,t)] for t in e.parent_map]
        for k in eachindex(e.parent_map)
            a=(e.parent,e.parent_map[k]);b=(e.child,e.child_map[k])
            isapprox(reference.voltage[b],vf[k];rtol=1e-9,atol=1e-9) ||
                throw(ArgumentError("meshed_linear requires equal endpoint reference phasors on line $(e.id)"))
            for key in (a,b)
                get!(theta,key) do;@variable(model,base_name=_l3f_name("l3f_angle_deviation",key...));end
            end
            push!(get!(adjacency,a,Tuple{String,String}[]),b)
            push!(get!(adjacency,b,Tuple{String,String}[]),a)
            rhs=JuMP.AffExpr(0.0)
            for j in eachindex(vf)
                c=Z[k,j]/(vf[k]*conj(vf[j]))
                JuMP.add_to_expression!(rhs,-imag(c),p[(e.family,e.id,j)])
                JuMP.add_to_expression!(rhs,real(c),q[(e.family,e.id,j)])
            end
            _l3f_register_constraint!(constraints,:line_angle_drop,(e.id,k),
                @constraint(model,theta[b]-theta[a]==rhs))
        end
    end
    seen=Set{Tuple{String,String}}()
    for root in sort!(collect(keys(theta)))
        root in seen && continue
        JuMP.fix(theta[root],0.0);push!(seen,root);queue=[root]
        for u in queue,v in adjacency[u]
            v in seen && continue
            push!(seen,v);push!(queue,v)
        end
    end
    variables[:angle_deviation]=theta
end
