"""Controlled three-phase transfer: filter impedance × parallel demand law.

Original electrical records and limits are retained. Both filter levels are
finite; the experiment does not equate a three-leg converter with a delta
generator or remove its internal circulating-current freedom.
"""
module IVRThreePhaseTransferStudy
using FormulationLab
include("benchmark_ivr_mixed_devices.jl")
const M=IVRMixedDeviceStudy
const P=M.P
function profiles(net,workload;kwargs...)
    [merge(p,(;options=IVRNLPOptions(;(k=>(k==:transformer_nameplate ? :bmopftools : deepcopy(getfield(p.options,k)))
        for k in fieldnames(IVRNLPOptions))...),factors=merge(p.factors,(;transformer_nameplate=:bmopftools))))
        for p in M.profiles(net,workload;kwargs...)]
end
benchmark(path,output;checkpoint=:sweep,kwargs...)=M.F.benchmark_profiles(path,output,profiles,@__FILE__;checkpoint,kwargs...)

"""Add colocated three-phase DERs and 10% parallel demand, with exact manifests.

Select nonnegative three-channel WYE/DELTA loads with positive total P. Capacity
is balanced at twice mean nominal P per channel. Every delta site and every
even-indexed site in the sorted selected list receives an IBR; remaining wye
sites receive static generators.
Filter R/X are 0.005/0.002 or 0.05/0.02 times Vcoil²/Pmax. Shunt susceptance,
dispatch boxes and internal DC budgets are fixed across filter levels. Parallel
demand has the same nominal P/Q in both law treatments. No limits are added to
or changed on original equipment. This is a declared scenario, not original DER.
"""
function scenario(original;filter_level=:low,load_law=:constant_power)
    filter_level in (:low,:high) || throw(ArgumentError("filter_level must be :low or :high"))
    load_law in (:constant_power,:voltage_dependent) || throw(ArgumentError("unknown load-law treatment"))
    isempty(get(original,"generator",Dict())) && isempty(get(original,"ibr",Dict())) ||
        throw(ArgumentError("scenario requires an input without DERs"))
    net=deepcopy(original);start=M.E.S.U.G.H.S.L.start_point(net)
    net["generator"]=Dict{String,Any}();net["ibr"]=Dict{String,Any}()
    selected=String[];sites=Any[]
    for id in sort!(collect(keys(get(original,"load",Dict()))))
        d=original["load"][id];cfg=get(d,"configuration",nothing);tm=d["terminal_map"]
        cfg in ("WYE","DELTA") && length(tm)==(cfg=="WYE" ? 4 : 3) || continue
        p=d["p_nom"];q=d["q_nom"]
        length(p)==length(q)==3 && all(x->x isa Real && !(x isa Bool) && isfinite(x) && x>=0,p) &&
            all(x->x isa Real && !(x isa Bool) && isfinite(x),q) && sum(p)>0 || continue
        vn=[abs(start.voltage[(d["bus"],tm[k])]-start.voltage[(d["bus"],tm[cfg=="WYE" ? 4 : mod1(k+1,3)])]) for k in 1:3]
        all(x->isfinite(x) && x>0,vn) || throw(ArgumentError("invalid unloaded coil voltage at $id"))
        name="threephase_"*id
        haskey(net["load"],name) && throw(ArgumentError("scenario load name collision"))
        push!(selected,id);k=length(selected);pm=2sum(p)/3
        device=Dict{String,Any}("bus"=>d["bus"],"terminal_map"=>copy(tm),
            "p_min"=>zeros(3),"p_max"=>fill(pm,3),"q_min"=>fill(-pm/2,3),
            "q_max"=>fill(pm/2,3),"s_max"=>fill(pm,3))
        converter=cfg=="DELTA" || iseven(k)
        if converter
            zbase=vn.^2 ./ pm;factor=filter_level==:low ? 1. : 10.
            merge!(device,Dict("topology"=>cfg=="WYE" ? "FOUR_LEG" : "THREE_LEG",
                "prime_mover"=>"BATTERY","r_filter"=>factor*.005zbase,"x_filter"=>factor*.002zbase,
                "b_filter_shunt"=>.002/(sum(zbase)/3),"dc_link_coupled"=>true,
                "p_dc_min"=>0.,"p_dc_max"=>.6*3pm,"p_avail"=>.8*3pm))
            net["ibr"][name]=device
        else
            device["configuration"]=cfg;net["generator"][name]=device
        end
        law=load_law==:constant_power ? "constant_power" : ("constant_current","zip","exponential")[mod1(k,3)]
        extra=Dict{String,Any}("bus"=>d["bus"],"terminal_map"=>copy(tm),"configuration"=>cfg,
            "p_nom"=>.1p,"q_nom"=>.1q,"v_nom"=>vn,"model"=>law)
        if law=="zip"
            for (pre,values) in (("alpha",(.2,.3,.5)),("beta",(.4,.5,.1))),(s,v) in zip(("z","i","p"),values)
                extra[pre*"_"*s]=fill(v,3)
            end
        elseif law=="exponential"
            extra["gamma_p"]=fill(.4,3);extra["gamma_q"]=fill(-.5,3)
        end
        net["load"][name]=extra
        push!(sites,(;load=id,device=name,family=converter ? "ibr" : "generator",configuration=cfg,coil_voltage=vn,p_max=pm))
    end
    isempty(selected) && throw(ArgumentError("no positive three-phase loads selected"))
    changes=Any[]
    for family in ("load","generator","ibr"),id in sort!(collect(keys(net[family])))
        before=get(get(original,family,Dict()),id,nothing);after=net[family][id]
        isequal(before,after) || push!(changes,(;family,id,before=deepcopy(before),after=deepcopy(after)))
    end
    net,(;filter_level,load_law,selected_loads=selected,sites,changes,original_fields_preserved=true,
        note="Declared DERs and parallel demand only; original limits retained. Finite filter impedance levels; source conversion semantics are inherited.")
end
end
