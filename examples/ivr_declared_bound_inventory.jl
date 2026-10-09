"""Reconcile normalized input operating-bound channels with recorded provenance."""
module IVRDeclaredBoundInventory
using FormulationLab, JuMP
include("ivr_constraint_inventory.jl")
const I=IVRConstraintInventory
const BUS_FIELDS=("v_min","v_max","vpn_min","vpn_max","vpp_min","vpp_max",
                  "vn_max","vpos_min","vpos_max","vneg_max","vzero_max")
const BOX_FIELDS=("p_min","p_max","q_min","q_max")

_neutral(net,b)=FormulationLab._vcheck_neutral(net,b)
_phases(net,b,tm)=findall(!=(_neutral(net,b)),tm)
function _coils(net,d)
    tm=d["terminal_map"];cfg=uppercase(d["configuration"])
    cfg=="SINGLE_PHASE" ? 1 : cfg=="DELTA" ? (length(tm)==2 ? 1 : 3) :
        cfg=="WYE" ? length(_phases(net,d["bus"],tm)) :
        throw(ArgumentError("unsupported connection in bound inventory"))
end
_relation(field)=endswith(field,"min") ? :lower : :upper
function _values(raw,n)
    xs=raw isa Real ? fill(raw,n) : collect(raw)
    length(xs)==n && all(x->x isa Real && isfinite(x),xs) ||
        throw(ArgumentError("bound declaration requires $n finite real values"))
    xs
end
_identity(q)=(q.category,q.source_path,q.source_channel,q.family,q.id,q.side,q.winding,q.channel)

# This enumeration starts from input records, never from emitted constraint counts
# or assembly limit lists. A shared source field can serve several consumers.
function _expected(build)
    net=build.network;rows=Any[];inactive=Any[];fixed=Any[];visited=Set{Tuple}()
    function add(path,raw,channels,category,family,id;side=nothing,winding=nothing,
                 divisor=1,relation=_relation(string(last(path))))
        path=Tuple(path);push!(visited,path)
        vals=_values(raw,length(channels))
        for (k,channel) in enumerate(channels)
            push!(rows,(;category,source_path=path,source_channel=raw isa Real ? nothing : k,
                family,id,side,winding,channel,declared_value=vals[k],divisor,
                limit_SI=vals[k]/divisor,relation))
        end
    end
    function skip(path,raw,status;consumer=nothing)
        path=Tuple(path);push!(visited,path)
        push!(inactive,(;source_path=path,declared=deepcopy(raw),status,consumer))
    end
    function taps(d,path,key,n)
        lo=key*"_min";hi=key*"_max"
        any(haskey(d,k) for k in (lo,hi)) || return
        all(haskey(d,k) for k in (lo,hi)) || throw(ArgumentError("incomplete fixed tap bounds"))
        lower=_values(d[lo],n);upper=_values(d[hi],n)
        values=haskey(d,key) ? _values(d[key],n) : lower==upper ? lower :
            throw(ArgumentError("movable taps are outside the declared-bound inventory"))
        all(>(0),[lower;upper;values]) || throw(ArgumentError("nonpositive tap declaration"))
        for (field,limits,relation) in ((lo,lower,:lower),(hi,upper,:upper))
            p=(path...,field);push!(visited,p)
            for k in 1:n
                push!(fixed,(;source_path=p,source_channel=d[field] isa Real ? nothing : k,
                    channel=k,limit=limits[k],setting=values[k],relation,
                    satisfied=relation==:lower ? limits[k]<=values[k] : values[k]<=limits[k]))
            end
        end
    end
    for (id,d) in net["bus"]
        tm=d["terminal_names"];np=length(_phases(net,id,tm))
        for field in BUS_FIELDS
            haskey(d,field) || continue
            raw=d[field]
            n=field in ("v_min","v_max") ? (raw isa Real ? 1 : length(raw)) :
                startswith(field,"vpn") ? np : startswith(field,"vpp") ? np*(np-1)÷2 : 1
            add(("bus",id,field),raw,1:n,:bus_limit,:bus,id)
        end
    end
    for (id,d) in get(net,"line",Dict())
        tm=d["terminal_map_from"];ph=_phases(net,d["bus_from"],tm)
        code=haskey(d,"linecode") ? net["linecode"][d["linecode"]] : Dict()
        for field in ("i_max","s_max")
            haskey(d,field) || haskey(code,field) || continue
            path=haskey(d,field) ? ("line",id,field) : ("linecode",d["linecode"],field)
            raw=haskey(d,field) ? d[field] : code[field]
            for side in (:from,:to)
                add(path,raw,field=="i_max" ? eachindex(tm) : ph,:equipment_limit,:line,id;side)
            end
        end
    end
    for (id,d) in get(net,"linecode",Dict()),field in ("i_max","s_max")
        haskey(d,field) || continue
        consumers=[(lid,l) for (lid,l) in get(net,"line",Dict()) if get(l,"linecode",nothing)==id]
        isempty(consumers) && skip(("linecode",id,field),d[field],:unused_linecode)
        for (lid,l) in consumers
            haskey(l,field) && skip(("linecode",id,field),d[field],:overridden;consumer=("line",lid,field))
        end
    end
    for (id,d) in get(net,"switch",Dict()),field in ("i_max","s_max")
        haskey(d,field) || continue
        for side in (:from,:to)
            add(("switch",id,field),d[field],eachindex(d["terminal_map_from"]),:equipment_limit,:switch,id;side)
        end
    end
    for family in ("generator","voltage_source","ibr"),(id,d) in get(net,family,Dict())
        tm=d["terminal_map"];source=family=="voltage_source";ibr=family=="ibr"
        ph=_phases(net,d["bus"],tm)
        n=source ? length(tm) : ibr ? length(d["s_max"]) : _coils(net,d)
        for field in BOX_FIELDS
            haskey(d,field) || continue
            raw=d[field];size=raw isa Real ? 1 : length(raw)
            channels=source && size!=n ? ph : (1:n)
            add((family,id,field),raw,channels,:dispatch,Symbol(family),id)
        end
        for field in ("i_max","s_max")
            haskey(d,field) || continue
            raw=d[field]
            channels=source ? (field=="s_max" ? ph : eachindex(tm)) :
                field=="i_max" && !(raw isa Real) && length(raw)==length(tm) ? eachindex(tm) : (1:n)
            add((family,id,field),raw,channels,:equipment_limit,Symbol(family),id)
        end
        if ibr
            for field in ("p_avail","p_dc_min","p_dc_max","v_ref_internal")
                haskey(d,field) || continue
                field in ("p_dc_min","p_dc_max") && !get(d,"dc_link_coupled",false) &&
                    throw(ArgumentError("DC bound without coupled-link contract"))
                field=="v_ref_internal" && !get(d,"grid_forming",false) &&
                    throw(ArgumentError("internal voltage without grid-forming contract"))
                add((family,id,field),d[field],field=="v_ref_internal" ? (1:n) : (nothing,),
                    :ibr_limit,:ibr,id;relation=field=="v_ref_internal" ? :equality : _relation(field))
            end
        end
    end
    for (kind,table) in get(net,"transformer",Dict()),(id,d) in table
        path=("transformer",kind,id);key="$kind/$id"
        if kind=="n_winding"
            haskey(d,"s_rating") && skip((path...,"s_rating"),d["s_rating"],:base_metadata)
            for (k,w) in enumerate(d["windings"])
                wp=(path...,"windings",k);n=_coils(net,w)
                haskey(w,"s_rating") && skip((wp...,"s_rating"),w["s_rating"],:base_metadata)
                for field in ("i_max","s_max")
                    haskey(w,field) || continue
                    divisor=field=="s_max" && w[field] isa Real && build.options.transformer_nameplate==:bmopftools ? n : 1
                    add((wp...,field),w[field],1:n,:equipment_limit,:transformer,key;winding=k,divisor)
                end
                taps(w,wp,"tap_ratio",1)
            end
        else
            kind in ("single_phase","center_tap","delta_wye","wye_delta","single_phase_autotransformer","open_delta_regulator") ||
                throw(ArgumentError("unclassified transformer kind"))
            for side in (:from,:to)
                field="i_max_$side";haskey(d,field) || continue
                delta=kind=="delta_wye" && side==:from || kind=="wye_delta" && side==:to
                n=delta ? 3 : length(d["terminal_map_$side"])
                add((path...,field),d[field],1:n,:equipment_limit,:transformer,key;side)
            end
            if haskey(d,"s_rating")
                if build.options.transformer_nameplate==:ignore
                    skip((path...,"s_rating"),d["s_rating"],:ignored_nameplate)
                else
                    side=kind=="delta_wye" ? :to : :from
                    three=kind in ("delta_wye","wye_delta")
                    channels=three ? _phases(net,d["bus_$side"],d["terminal_map_$side"]) :
                        (1:(kind=="open_delta_regulator" ? 2 : 1))
                    add((path...,"s_rating"),d["s_rating"],channels,:equipment_limit,:transformer,key;
                        side,divisor=three ? 3 : 1)
                end
            end
            regulator=kind in ("single_phase_autotransformer","open_delta_regulator")
            taps(d,path,regulator ? "tap_ratio" : "tap",kind=="open_delta_regulator" ? 2 : 1)
            if !regulator
                # Normalization copies 0.2 aliases to the internal 0.1 keys,
                # retaining both spellings. Account for each retained interval.
                for suffix in ("","_min","_max")
                    canonical="tap_ratio"*suffix;legacy="tap"*suffix
                    haskey(d,canonical) || continue
                    haskey(d,legacy) && d[canonical]==d[legacy] ||
                        throw(ArgumentError("inconsistent normalized tap aliases at $path"))
                end
                taps(d,path,"tap_ratio",1)
            end
        end
    end
    # Fail closed for bound-shaped fields outside the explicit classification.
    # Descriptive extensions and geometry are outside this inventory's scope.
    function scan(x,path=())
        if x isa AbstractDict
            for (key,v) in x
                key in ("meta","extras","_meta","wire_data","line_geometry") && continue
                p=(path...,key)
                if endswith(key,"_min") || endswith(key,"_max") || key in ("s_rating","p_avail","v_ref_internal")
                    p in visited || throw(ArgumentError("unclassified bound declaration: $p"))
                end
                scan(v,p)
            end
        elseif x isa AbstractVector
            for (k,v) in enumerate(x);scan(v,(path...,k));end
        end
    end
    scan(net)
    sort!(rows;by=q->repr(_identity(q)))
    sort!(inactive;by=q->repr((q.source_path,q.status,q.consumer)))
    sort!(fixed;by=q->repr((q.source_path,q.source_channel,q.channel)))
    (;rows,inactive,fixed)
end

function _observed(inventory,net)
    rows=Dict{Any,Any}()
    for declaration in inventory.declarations
        category=declaration.category
        category in (:bus_limit,:equipment_limit,:dispatch,:ibr_limit) || continue
        q=declaration.metadata
        path=category==:bus_limit ? ("bus",q.b,q.key) : q.source_path
        source_channel=category==:bus_limit ? (get(net["bus"][q.b],q.key,nothing) isa Real ? nothing : q.channel) : q.source_channel
        family=category==:bus_limit ? :bus : category==:ibr_limit ? :ibr : q.family
        id=category==:bus_limit ? q.b : q.id
        side=category==:equipment_limit ? q.side : nothing
        winding=category==:equipment_limit ? q.winding : nothing
        limit=category==:bus_limit ? q.bound : q.limit_SI
        relation=category==:equipment_limit ? :upper : q.relation
        divisor=category==:equipment_limit ? q.divisor : 1
        declared_value=category==:equipment_limit ? q.declared_value : limit
        row=(;category,source_path=Tuple(path),source_channel,family,id,side,winding,q.channel,
            limit_SI=limit,declared_value,divisor,relation,q.form,constraints=declaration.constraints)
        identity=_identity(row)
        haskey(rows,identity) && throw(ArgumentError("duplicate bound provenance: $identity"))
        rows[identity]=row
    end
    rows
end

"""Check supplied bound channels, independently of emitted-row completeness.

This reconciles the normalized build.network and live recorded provenance. It
does not establish input-schema coverage, feasibility, correct algebra after
arbitrary JuMP edits, or validity of unsupported direct network mutations.
"""
function catalog(build::FormulationLab.IVRNLPBuild)
    expected=_expected(build);inventory=I.catalog(build);observed=_observed(inventory,build.network)
    identities=[_identity(q) for q in expected.rows]
    allunique(identities) || throw(ArgumentError("duplicate expected bound consumer"))
    matched=Any[];missing=Any[];mismatched=Any[]
    for q in expected.rows
        identity=_identity(q)
        if !haskey(observed,identity);push!(missing,q);continue;end
        actual=observed[identity]
        if any(getproperty(q,k)!=getproperty(actual,k) for k in (:limit_SI,:declared_value,:divisor,:relation))
            push!(mismatched,(;expected=q,observed=actual));continue
        end
        push!(matched,(;q...,actual.form,constraints=actual.constraints))
    end
    wanted=Set(identities)
    unexpected=[q for (key,q) in observed if key ∉ wanted]
    sort!(unexpected;by=q->repr(_identity(q)))
    complete=isempty(missing) && isempty(mismatched) && isempty(unexpected) && all(q->q.satisfied,expected.fixed)
    (;complete_declared_bound_coverage=complete,complete_input_coverage=false,
        complete_emitted_coverage=inventory.complete_emitted_coverage,
        expected_channel_count=length(expected.rows),matched,missing,mismatched,unexpected,
        inactive=expected.inactive,fixed_setting_checks=expected.fixed)
end

_portable(q)=NamedTuple{Tuple(k for k in keys(q) if k!=:constraints)}(
    Tuple(v for (k,v) in pairs(q) if k!=:constraints))
"""Serializable diagnostic report; no physical-result schema or solver mutation."""
function report(build)
    c=catalog(build)
    (;schema="FormulationLab.declared_bound_inventory.v1",c.complete_declared_bound_coverage,
        c.complete_emitted_coverage,c.complete_input_coverage,c.expected_channel_count,
        matched=[(;_portable(q)...,emitted_constraint_count=length(q.constraints)) for q in c.matched],
        c.missing,mismatched=[(;q.expected,observed=_portable(q.observed)) for q in c.mismatched],
        unexpected=_portable.(c.unexpected),c.inactive,c.fixed_setting_checks)
end
end
