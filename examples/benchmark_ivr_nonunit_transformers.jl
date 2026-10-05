"""Physical non-unit observation sharing, with matched lifting-threshold controls."""
module IVRNonunitTransformerStudy
using FormulationLab, JuMP
include("benchmark_ivr_affine_sharing.jl")
include("ivr_transformer_stress_cases.jl")
const A=IVRAffineSharingStudy
const P=A.P
const E=A.E
const F=FormulationLab

"""Manufactured parallel single-phase transformer cascades in SI units.

Each branch has two ratio:1 transformers and a two-wire feeder with a finite
terminal neutral ground. Ratio eight gives 14.72 kV → 1.84 kV → 230 V.
Leakage is referred consistently to each winding; zero leakage remains a control.
Reversal swaps ports and winding data, preserving the physical circuit.
"""
function case(;branches=1,segments=6,ratio=8.,leakage=false,reverse=false,limit_side=:none)
    branches isa Integer && branches>=1 || throw(ArgumentError("positive branch count required"))
    segments isa Integer && segments>=2 || throw(ArgumentError("at least two segments required"))
    ratio isa Real && isfinite(ratio) && 1<=ratio<=16 || throw(ArgumentError("finite ratio in [1,16] required"))
    limit_side in (:none,:from,:to) || throw(ArgumentError("unknown winding limit side"))
    base=IVRTransformerStressCases.case(;segments,ratio=ratio^2)
    tx=base["transformer"]["single_phase"]
    tx["upstream"]["v_nom_to"]=230ratio
    tx["downstream"]["v_nom_from"]=230ratio
    # Permit genuine economic dispatch and source P/Q tracking.
    base["generator"]["der"]["s_max"]=[5000.]
    base["generator"]["der"]["q_min"]=[-1000.]
    base["generator"]["der"]["q_max"]=[1000.]
    for d in values(tx)
        d["r_series_from"]=leakage ? .01ratio^2 : 0.
        d["x_series_from"]=leakage ? .005ratio^2 : 0.
        d["r_series_to"]=leakage ? .01 : 0.
        d["x_series_to"]=leakage ? .005 : 0.
        if reverse
            for (a,b) in (("bus_from","bus_to"),("terminal_map_from","terminal_map_to"),
                ("v_nom_from","v_nom_to"),("r_series_from","r_series_to"),
                ("x_series_from","x_series_to"),("i_max_from","i_max_to"))
                d[a],d[b]=d[b],d[a]
            end
        end
    end
    if limit_side!=:none
        d=tx["downstream"];side=string(limit_side)
        d["i_max_$side"]=fill(1150/d["v_nom_$side"],2)
    end
    net=Dict{String,Any}("terminal_conventions"=>deepcopy(base["terminal_conventions"]),
        "bus"=>Dict{String,Any}("hv"=>deepcopy(base["bus"]["hv"])),
        "voltage_source"=>deepcopy(base["voltage_source"]),
        "transformer"=>Dict("single_phase"=>Dict{String,Any}()))
    for family in ("line","load","generator","shunt");net[family]=Dict{String,Any}();end
    for branch in 1:branches
        rename(id)=id=="hv" ? "hv" : "r$(branch)_$(id)"
        for (id,d) in base["bus"];id=="hv" || (net["bus"][rename(id)]=deepcopy(d));end
        for family in ("line","load","generator","shunt","transformer")
            source=family=="transformer" ? tx : base[family]
            destination=family=="transformer" ? net[family]["single_phase"] : net[family]
            for (id,d) in source
                copy=deepcopy(d)
                for key in ("bus","bus_from","bus_to");haskey(copy,key) && (copy[key]=rename(copy[key]));end
                destination[rename(id)]=copy
            end
        end
    end
    net
end

function profiles(net,workload;exchange_target_W=nothing,nlp_scaling_method="none")
    prior=A.profiles(net,workload;exchange_target_W,nlp_scaling_method)
    template=only(p for p in prior if p.name=="observations_exact")
    arms=[begin
        changes=(;observation_support_threshold=threshold,observation_sharing=sharing)
        options=IVRNLPOptions(;(k=>deepcopy(get(changes,k,getfield(template.options,k)))
            for k in fieldnames(IVRNLPOptions))...)
        (;name="$(sharing)_t$(threshold)",options,solver_options=template.solver_options,
            factors=merge(template.factors,changes))
    end for threshold in (2,0) for sharing in (:exact,:signed,:proportional)]
    [only(p for p in prior if p.name=="full_powers");
     only(p for p in prior if p.name=="reduced_powers");arms]
end
benchmark(path,output;kwargs...)=A.H.F.benchmark_profiles(path,output,profiles,@__FILE__;kwargs...)

"""Untimed graph audit at arbitrary coordinates, including named winding ports.

This tests affine identities, not feasibility of the arbitrary electrical point.
It distinguishes transformer-port sharing from other proportional observations.
"""
function observation_audit(b;samples=3)
    policy=b.model.ext[:ivr_lifting];errors=Float64[]
    for sample in 1:samples
        values=Dict(v=>sin(sample*k)+cos(2sample*k) for (k,v) in enumerate(all_variables(b.model)))
        for record in policy.records
            value=JuMP.value(v->values[v],record.expression)
            values[record.real]=real(value);values[record.imag]=imag(value)
        end
        for (key,expression) in policy.cache
            first(key)==:observation || continue
            original=F._linivr_eval(Dict(key[2]),b.state)
            x=JuMP.value(v->values[v],original);y=JuMP.value(v->values[v],expression)
            push!(errors,abs(x-y)/max(1.,abs(x),abs(y)))
        end
    end
    ports=Dict((family,id)=>i for (family,id,v,i,d) in b.electrical.devices)
    variables(u)=Set(v for x in (real(u),imag(u)) for (v,c) in x.terms if !iszero(c))
    windings=map(sort!(collect(keys(b.network["transformer"]["single_phase"])))) do id
        key="single_phase/$id"
        rows=[first(ports[(Symbol("transformer_",side),key)]) for side in ("from","to")]
        u=[F._linivr_eval(row,b.state) for row in rows]
        signatures=F._ivrn_observation_signature.(u,Ref(:proportional))
        factor=all(!isnothing,signatures) && signatures[1].key==signatures[2].key ?
            F._ivrn_observation_factor(signatures[2].pivot,signatures[1].pivot) : nothing
        keys=[(:observation,F._ivrn_row_key(row)) for row in rows]
        lifted=all(k->haskey(policy.cache,k),keys)
        shared=lifted && variables(policy.cache[keys[1]])==variables(policy.cache[keys[2]])
        (;id,factor_to_from=factor,both_lifted=lifted,shared_auxiliary=shared)
    end
    (;observations_checked=length(errors),max_relative_error=maximum(errors;init=0.),windings)
end
end
