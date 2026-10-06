"""Declared local reactive transfer across an unchanged, explicitly selected line."""
module IVRLineTransferStudy
using FormulationLab
include("benchmark_ivr_mixed_devices.jl")
const M=IVRMixedDeviceStudy
const P=M.P

function finite_value(x,name;positive=false)
    x isa Real && !(x isa Bool) && isfinite(x) || throw(ArgumentError("$name must be finite and real"))
    y=Float64(x)
    isfinite(y) && (!positive || y>0) || throw(ArgumentError("invalid Float64 $name"))
    y
end

"""Add two ideal reactive dispatch devices without changing original records.

`terminal_indices` selects corresponding conductors in the line's ordered maps.
Two conductors create SINGLE_PHASE devices; three create DELTA devices. The
total `q_capacity_VAR` is divided equally between native coils. Active power is
fixed at zero; reactive boxes and apparent-power caps are explicit. Devices
are research additions, not claims about installed equipment. No voltage,
line, transformer, load or source fields are changed.
"""
function scenario(original;line_id,terminal_indices,q_capacity_VAR)
    cap=finite_value(q_capacity_VAR,"q_capacity_VAR";positive=true)
    FormulationLab._ivrn_check(original)
    isempty(get(original,"generator",Dict())) && isempty(get(original,"ibr",Dict())) ||
        throw(ArgumentError("line-transfer scenario requires an input without DERs"))
    haskey(original["line"],line_id) || throw(ArgumentError("unknown line"))
    l=original["line"][line_id];ix=Any[terminal_indices...]
    length(ix) in (2,3) && allunique(ix) && all(i->i isa Integer && !(i isa Bool) &&
        1<=i<=length(l["terminal_map_from"]) && i<=length(l["terminal_map_to"]),ix) ||
        throw(ArgumentError("select two or three distinct corresponding line conductors"))
    ix=Int.(ix)
    m=length(ix)==2 ? 1 : 3
    cap/m>0 || throw(ArgumentError("per-coil capability underflows"))
    net=deepcopy(original);net["generator"]=Dict{String,Any}();devices=Any[];changes=Any[]
    for (side,sign) in (("from",1),("to",-1))
        id="line_transfer_"*side;tm=l["terminal_map_"*side][ix]
        d=Dict{String,Any}("bus"=>l["bus_"*side],"terminal_map"=>copy(tm),
            "configuration"=>m==1 ? "SINGLE_PHASE" : "DELTA",
            "p_min"=>zeros(m),"p_max"=>zeros(m),"q_min"=>fill(-cap/m,m),
            "q_max"=>fill(cap/m,m),"s_max"=>fill(cap/m,m))
        net["generator"][id]=d
        push!(devices,(;id,side,sign,channels=m))
        push!(changes,(;family="generator",id,before=nothing,after=deepcopy(d)))
    end
    net,(;line_id,terminal_indices=ix,q_capacity_VAR=cap,devices,changes,original_fields_preserved=true,
        note="Added ideal reactive devices; inherited ratings retained. Activity and feasibility must be measured.")
end

"""Opposite per-coil Q targets; positive target injects at the line's from end.

The sum of squared errors is divided by (1000 var)^2. `target_VAR` is total
per device, not per coil, and is a soft objective request. Reversing its sign
reverses the requested transfer. Original demand and electrical losses remain.
"""
function terms(manifest;target_VAR)
    target=finite_value(target_VAR,"target_VAR")
    [IVRPowerTerm(channels=[(:generator,d.id,k)],quantity=:q,
        target=d.sign*target/d.channels,quadratic=1e-6) for d in manifest.devices for k in 1:d.channels]
end

function profiles(net,manifest;target_VAR,nlp_scaling_method="none")
    [merge(p,(;options=IVRNLPOptions(;(k=>(k==:transformer_nameplate ? :bmopftools :
        deepcopy(getfield(p.options,k))) for k in fieldnames(IVRNLPOptions))...),
        factors=merge(p.factors,(;transformer_nameplate=:bmopftools))))
        for p in M.profiles_for_terms(net,terms(manifest;target_VAR);nlp_scaling_method)]
end

"""Manufactured passive pi line with unequal, coupled endpoint shunts.

The fixture declares a 200 A line override of a 250 A linecode rating, length
0.5, zero demand and 230 V source phase magnitude. `:inline` stores the same
physical matrices directly on the line, without a length multiplier. This is
a new research input, not a modification of an external feeder. Three-wire
receiving terminals are cyclically permuted to exercise positional recovery.
"""
function shunt_fixture(;conductors=2,storage=:linecode)
    conductors isa Integer && conductors in (2,3) || throw(ArgumentError("fixture requires two or three conductors"))
    storage in (:linecode,:inline) || throw(ArgumentError("unknown matrix storage"))
    n=conductors;net=P.ivr_compiler_case(;conductors,segments=1,loading=0.)
    code=net["linecode"]["wire"];empty!(code);code["i_max"]=fill(250.,n)
    line=net["line"]["l1"];line["length"]=.5;line["i_max"]=fill(200.,n)
    for i in 1:n,j in 1:n
        c=n==2 ? (i==j ? 1. : -1.) : (i==j ? 2/3 : -1/3)
        code["R_series_$(i)_$j"]=i==j ? .004 : .001
        code["X_series_$(i)_$j"]=i==j ? .002 : .0003
        for (side,g,b) in (("from",.001,.02),("to",.002,.08))
            code["G_$(side)_$(i)_$j"]=g*c
            code["B_$(side)_$(i)_$j"]=b*c
        end
    end
    n==3 && (line["terminal_map_to"]=["b","c","a"])
    if storage==:inline
        for (k,v) in code;k=="i_max" || (line[k]=.5v);end
        delete!(line,"linecode");delete!(line,"length");empty!(net["linecode"])
    end
    net
end

"""Finite SI terminal-current margins, independently at both line ends.

Ratings follow conductor positions, even when endpoint terminal names differ.
A line-level rating overrides the linecode. Negative slack is a violation and
is never reported as active. This is geometric activity, not a dual certificate.
"""
function current_activity(net,point;atol_A=1e-5)
    tol=finite_value(atol_A,"atol_A");tol>=0 || throw(ArgumentError("negative activity tolerance"))
    records=Any[]
    for id in sort!(collect(keys(get(net,"line",Dict()))))
        line=net["line"][id];code=haskey(line,"linecode") ? net["linecode"][line["linecode"]] : Dict()
        owner=haskey(line,"i_max") ? line : code
        haskey(owner,"i_max") || continue
        limits=owner["i_max"];n=length(line["terminal_map_from"])
        limits isa AbstractVector && length(limits)==n || throw(ArgumentError("invalid current-bound arity at $id"))
        all(x->x isa Real && !(x isa Bool) && !isnan(x) && x>=0,limits) || throw(ArgumentError("invalid current bound at $id"))
        length(line["terminal_map_to"])==n || throw(ArgumentError("endpoint arity mismatch at $id"))
        for side in (:from,:to)
            current=point.currents[(Symbol("line_",side),id)]
            length(current)==n || throw(ArgumentError("current arity mismatch at $id"))
            all(isfinite,current) || throw(ArgumentError("nonfinite terminal current at $id"))
            for (k,cap) in enumerate(limits)
                isfinite(cap) || continue
                value=abs(current[k]);slack=cap-value
                push!(records,(;id,side,channel=k,terminal=line["terminal_map_"*String(side)][k],
                    limit_A=cap,current_A=value,slack_A=slack,origin=owner===line ? :line : :linecode,
                    active=0<=slack<=tol,violated=slack<0))
            end
        end
    end
    (;atol_A=tol,records)
end
end
