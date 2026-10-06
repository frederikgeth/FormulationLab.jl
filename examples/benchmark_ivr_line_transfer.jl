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
end
