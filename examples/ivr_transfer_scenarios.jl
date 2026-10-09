"""Bounded, input-only supplemental dispatch scenarios for transfer validation.

These are explicitly different physical problems with recorded parentage, not
repairs or hidden augmentation of original-case trials. No build or solve occurs.
"""
module IVRTransferScenarios
using SHA
finite_real(x)=x isa Real && !(x isa Bool) && isfinite(x)

"""Four sites: first two positive three-coil WYE and DELTA demands in SHA(id) order.

This finite mechanism scenario requires both configurations; missing sites are
inapplicability, not permission to switch to a different parent. The first site
of each configuration receives a generator; the second receives an IBR.
"""
function select_sites(net)
    loads=get(net,"load",Dict())
    loads isa AbstractDict || throw(ArgumentError("load table required"))
    sites=NamedTuple[]
    for cfg in ("WYE","DELTA")
        ids=String[]
        for (id,d) in loads
            d isa AbstractDict || throw(ArgumentError("load record required"))
            get(d,"configuration",nothing)==cfg || continue
            tm=get(d,"terminal_map",nothing);p=get(d,"p_nom",nothing);q=get(d,"q_nom",nothing)
            tm isa AbstractVector && length(tm)==(cfg=="WYE" ? 4 : 3) && allunique(tm) &&
                all(x->x isa String,tm) && p isa AbstractVector && q isa AbstractVector &&
                length(p)==length(q)==3 && all(x->finite_real(x) && x>=0,p) && all(finite_real,q) ||
                throw(ArgumentError("invalid three-phase demand at $id"))
            sum(p)>0 && push!(ids,id)
        end
        sort!(ids;by=id->bytes2hex(sha256(id)))
        length(ids)>=2 || throw(ArgumentError("two positive $cfg demand sites required"))
        for (id,family) in zip(ids[1:2],("generator","ibr"))
            push!(sites,(;load=id,family,configuration=cfg))
        end
    end
    sites
end

"""Append four declared DERs using an explicit three-coil voltage scale per site.

Each coil P box is [0, 2 mean(parent P)], Q box is +/-half that cap, and apparent
power cap equals the P cap. IBR filter R/X are 0.005/0.002 Vscale²/Pcap, with
shunt susceptance 0.002/mean(Vscale²/Pcap); DC limits are [0,0.6 total Pcap] and
availability is 0.8 total Pcap. These are fixed study choices, not fitted ratings.
Voltage scales set only newly declared filter parameters, not original voltage
bounds or compiler per-unit bases. Every added record is included in the manifest.
"""
function scenario(original;coil_voltage_V)
    sites=select_sites(original)
    Set(keys(coil_voltage_V))==Set(s.load for s in sites) ||
        throw(ArgumentError("exactly one voltage-scale vector per selected site required"))
    net=Dict{String,Any}(k=>deepcopy(v) for (k,v) in original)
    changes=NamedTuple[];details=NamedTuple[]
    for family in ("generator","ibr")
        rows=get(original,family,Dict())
        rows isa AbstractDict && all(id isa String for id in keys(rows)) ||
            throw(ArgumentError("named $family table required"))
        net[family]=Dict{String,Any}(id=>deepcopy(d) for (id,d) in rows)
    end
    for s in sites
        d=original["load"][s.load];vn=coil_voltage_V[s.load]
        vn isa AbstractVector && length(vn)==3 && all(x->finite_real(x) && x>0,vn) ||
            throw(ArgumentError("three finite positive coil voltage scales required at $(s.load)"))
        cap=2*(sum(d["p_nom"])/3)
        isfinite(cap) && cap>0 || throw(ArgumentError("invalid supplemental dispatch cap"))
        id="transfer_"*s.load
        table=get!(net,s.family,Dict{String,Any}())
        table isa AbstractDict && !haskey(table,id) || throw(ArgumentError("scenario ID collision at $(s.family)/$id"))
        device=Dict{String,Any}("bus"=>d["bus"],"terminal_map"=>copy(d["terminal_map"]),
            "p_min"=>zeros(3),"p_max"=>fill(cap,3),"q_min"=>fill(-cap/2,3),
            "q_max"=>fill(cap/2,3),"s_max"=>fill(cap,3))
        if s.family=="generator"
            device["configuration"]=s.configuration
        else
            zbase=Float64.(vn).^2 ./ cap
            all(x->isfinite(x) && x>0,zbase) && isfinite(sum(zbase)) ||
                throw(ArgumentError("invalid supplemental filter scale"))
            merge!(device,Dict("topology"=>s.configuration=="WYE" ? "FOUR_LEG" : "THREE_LEG",
                "prime_mover"=>"BATTERY","r_filter"=>.005zbase,"x_filter"=>.002zbase,
                "b_filter_shunt"=>.002/(sum(zbase)/3),"dc_link_coupled"=>true,
                "p_dc_min"=>0.,"p_dc_max"=>.6*3cap,"p_avail"=>.8*3cap))
            all(x->finite_real(x) && x>0,[device["r_filter"];device["x_filter"];
                device["b_filter_shunt"];device["p_dc_max"];device["p_avail"]]) ||
                throw(ArgumentError("nonrepresentable supplemental filter or DC limit"))
        end
        table[id]=device
        push!(changes,(;family=s.family,id,before=nothing,after=deepcopy(device)))
        push!(details,(;s...,id,coil_voltage_V=Float64.(vn),p_max_per_coil_W=cap))
    end
    # Preserve missing versus explicitly empty tables as well as every record.
    added_tables=[f for f in ("generator","ibr") if !haskey(original,f)]
    for (key,value) in original
        if key in ("generator","ibr")
            all(isequal(record,net[key][id]) for (id,record) in value) || error("original device changed")
        else
            isequal(value,net[key]) || error("original field changed: $key")
        end
    end
    net,(;schema="FormulationLab.transfer_dispatch_scenario.v1",sites=details,changes,added_tables,
        original_fields_preserved=true,original_bounds_preserved=true,
        active_limits_guaranteed=false,compiler_invoked=false,optimizer_invoked=false,
        interpretation="Supplemental physical problem; not an unchanged input or independent parent.")
end
end
