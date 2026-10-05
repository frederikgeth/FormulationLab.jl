"""Explicit mixed-device power workloads and source-preserving feeder scenarios.

IBR cost prices internal active power (including filter losses); dispatch tracking
uses PCC power. This is a new declared experiment, not legacy-price inference.
"""
module IVRMixedDeviceStudy
using FormulationLab
include("benchmark_ivr_power_finalists.jl")
const F=IVRPowerFinalistStudy
const E=F.E
const P=F.P

function channels(net)
    dispatch=Tuple{Symbol,String,Int}[]
    free=false
    for family in ("generator","ibr"),id in sort!(collect(keys(get(net,family,Dict()))))
        d=net[family][id]
        keys4=("p_min","p_max","q_min","q_max")
        all(k->haskey(d,k) && d[k] isa AbstractVector,keys4) || throw(ArgumentError("$family/$id requires explicit P/Q vectors"))
        n=length(d["p_min"])
        n>0 && all(k->length(d[k])==n && all(x->x isa Real && !(x isa Bool) && isfinite(x),d[k]),keys4) ||
            throw(ArgumentError("$family/$id requires finite equally sized P/Q boxes"))
        all(d["p_min"].<=d["p_max"]) && all(d["q_min"].<=d["q_max"]) || throw(ArgumentError("inverted dispatch box"))
        free |= any(d["p_min"].<d["p_max"])
        append!(dispatch,[(Symbol(family),id,k) for k in 1:n])
    end
    free || throw(ArgumentError("active dispatch freedom required"))
    sources=[(:voltage_source,id,k) for id in sort!(collect(keys(get(net,"voltage_source",Dict()))))
        for k in eachindex(net["voltage_source"][id]["terminal_map"])]
    isempty(sources) && throw(ArgumentError("voltage-source exchange required"))
    sources,dispatch
end

function terms(net,workload;exchange_target_W=nothing)
    workload in (:quadratic_cost,:exchange_tracking) || throw(ArgumentError("unknown mixed power workload"))
    sources,dispatch=channels(net)
    if workload==:quadratic_cost
        return [IVRPowerTerm(channels=sources,linear=.25/1000);
            [IVRPowerTerm(channels=[(f==:ibr ? :ibr_internal : f,id,k)],linear=.10/1000) for (f,id,k) in dispatch];
            [IVRPowerTerm(channels=[c],quadratic=.02/1e6) for c in dispatch];
            [IVRPowerTerm(channels=[c],quantity=:q,quadratic=.002/1e6) for c in dispatch]]
    end
    exchange_target_W isa Real && !(exchange_target_W isa Bool) && isfinite(exchange_target_W) ||
        throw(ArgumentError("finite explicit exchange_target_W required"))
    [IVRPowerTerm(channels=sources,target=exchange_target_W,quadratic=1e-6);
     IVRPowerTerm(channels=sources,quantity=:q,quadratic=1e-6);
     [IVRPowerTerm(channels=[c];quantity,target=quantity==:p ?
        (net[string(c[1])][c[2]]["p_min"][c[3]]+net[string(c[1])][c[2]]["p_max"][c[3]])/2 : 0.,
        quadratic=1e-8) for c in dispatch for quantity in (:p,:q)]]
end

function profiles(net,workload;exchange_target_W=nothing,nlp_scaling_method="none")
    nlp_scaling_method in ("none","gradient-based") || throw(ArgumentError("unknown solver scaling policy"))
    ts=terms(net,workload;exchange_target_W)
    specs=[("full_powers",false,:off,:powers,:off),
        ("reduced_powers",true,:passive_blocks,:powers,:off),
        ("reduced_reuse",true,:passive_blocks,:powers,:generators),
        ("blocks_signed",true,:passive_blocks,:bounded_observations,:off),
        ("blocks_signed_reuse",true,:passive_blocks,:bounded_observations,:generators),
        ("cap4_signed_reuse",true,:passive_hybrid,:bounded_observations,:generators)]
    [(;name,factors=(;reduced,linear_elimination=mode,lifting,power_sharing=reuse),
        options=IVRNLPOptions(;objective=:power,power_terms=deepcopy(ts),objective_scale=1.,s_base=1e4,
            generator_power_bases=Dict(id=>1e4 for id in keys(get(net,"generator",Dict()))),
            lifted_power_base=1e3,power_sharing=reuse,lifting,observation_support_threshold=2,
            observation_sharing=:signed,passive_component_limit=4,
            transformer_scaling=:nominal,row_scaling=:composed,ground_scaling=:voltage,
            specialization=reduced ? :conductor_regions : :off,linear_elimination=mode,
            device_elimination=reduced ? :transformer_currents : :off),
        solver_options=(linear_solver="mumps",mumps_pivot_order=0,nlp_scaling_method))
        for (name,reduced,mode,lifting,reuse) in specs]
end
benchmark(path,output;kwargs...)=F.benchmark_profiles(path,output,profiles,@__FILE__;kwargs...)

"""Add declared LV dispatch and optional parallel voltage-dependent demand.

Select positive single-phase loads with unloaded coil voltage 200–260 V. Original
loads are untouched: mixed demand is an additional 10% branch, cycling current,
ZIP and exponential laws. Bounds are scenario values, not statutory limits.
The manifest lists every changed top-level record with exact before/after data.
"""
function scenario(original; mixed=false)
    net=deepcopy(original)
    isempty(get(net,"generator",Dict())) && isempty(get(net,"ibr",Dict())) ||
        throw(ArgumentError("scenario factory requires an input without DERs"))
    start=E.S.U.G.H.S.L.start_point(net)
    net["generator"]=Dict{String,Any}();mixed && (net["ibr"]=Dict{String,Any}())
    chosen=String[]
    for id in sort!(collect(keys(net["load"])))
        d=net["load"][id];tm=d["terminal_map"]
        d["configuration"]=="SINGLE_PHASE" && length(tm)==2 && length(d["p_nom"])==1 && only(d["p_nom"])>0 || continue
        vn=abs(start.voltage[(d["bus"],tm[1])]-start.voltage[(d["bus"],tm[2])])
        200<=vn<=260 || continue
        push!(chosen,id);k=length(chosen);name="study_"*id
        haskey(net["load"],name) && throw(ArgumentError("scenario load name collision"))
        pmax=2only(d["p_nom"])
        device=Dict{String,Any}("bus"=>d["bus"],"terminal_map"=>copy(tm),
            "p_min"=>[0.],"p_max"=>[pmax],"q_min"=>[-pmax/2],"q_max"=>[pmax/2],"s_max"=>[pmax],"i_max"=>[pmax/200])
        if mixed && iseven(k)
            merge!(device,Dict("topology"=>"SINGLE_PHASE","prime_mover"=>"BATTERY",
                "r_filter"=>[.2],"x_filter"=>[.08],"b_filter_shunt"=>.001,
                "dc_link_coupled"=>true,"p_dc_min"=>0.,"p_dc_max"=>.6pmax,"p_avail"=>.8pmax))
            net["ibr"][name]=device
        else
            device["configuration"]="SINGLE_PHASE";net["generator"][name]=device
        end
        if mixed
            law=("constant_current","zip","exponential")[mod1(k,3)]
            extra=Dict{String,Any}("bus"=>d["bus"],"terminal_map"=>copy(tm),"configuration"=>"SINGLE_PHASE",
                "p_nom"=>.1d["p_nom"],"q_nom"=>[.02only(d["p_nom"])],"v_nom"=>[vn],"model"=>law)
            if law=="zip"
                for (pre,values) in (("alpha",(.2,.3,.5)),("beta",(.4,.5,.1))),(s,v) in zip(("z","i","p"),values)
                    extra[pre*"_"*s]=[v]
                end
            elseif law=="exponential"
                extra["gamma_p"]=[.4];extra["gamma_q"]=[-.5]
            end
            net["load"][name]=extra
        end
        b=net["bus"][d["bus"]];n=count(!=(get(b,"neutral_terminal","n")),b["terminal_names"])
        get!(b,"vpn_min",fill(200.,n));get!(b,"vpn_max",fill(260.,n))
    end
    isempty(chosen) && throw(ArgumentError("no positive single-phase LV loads selected"))
    changes=Any[]
    for family in ("bus","load","generator","ibr"),id in sort!(collect(keys(get(net,family,Dict()))))
        before=get(get(original,family,Dict()),id,nothing);after=net[family][id]
        isequal(before,after) || push!(changes,(;family,id,before=deepcopy(before),after=deepcopy(after)))
    end
    net,(;mixed,selected_loads=chosen,changes,original_fields_preserved=true,
        note="Declared DERs, parallel demand and missing voltage bounds only; inherited preprocessing is not reversed.")
end
end
