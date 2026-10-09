"""Prospective power workloads and finite formulation arms for transfer studies.

This module constructs declarations only. It neither solves nor authorizes timing.
Original fixed-load networks are valid workloads but are not dispatch evidence.
No legacy price is inferred, no physical field is edited, and no DER is added.
"""
module IVRTransferSpecification
using FormulationLab

finite_real(x)=x isa Real && !(x isa Bool) && isfinite(x)
function table(net,key)
    rows=get(net,key,Dict())
    rows isa AbstractDict && all(id isa String && d isa AbstractDict for (id,d) in rows) ||
        throw(ArgumentError("$key must contain named records"))
    rows
end
function terminals(d,label)
    tm=get(d,"terminal_map",nothing)
    tm isa AbstractVector && !isempty(tm) && all(x->x isa String,tm) && allunique(tm) ||
        throw(ArgumentError("$label requires distinct named terminals"))
    tm
end

"""Declare source-terminal and native dispatch-coil channels in stable ID order.

Explicit finite P/Q boxes are required for any supplied generator or IBR; absence
of dispatch devices is allowed. Box freedom is an input feature, not a claim of
feasible controllability after all circuit constraints are applied.
"""
function channels(net)
    sources=Tuple{Symbol,String,Int}[]; dispatch=Tuple{Symbol,String,Int}[]
    active=false; reactive=false
    for (id,d) in sort!(collect(table(net,"voltage_source"));by=first)
        append!(sources,[(:voltage_source,id,k) for k in eachindex(terminals(d,"source/$id"))])
    end
    isempty(sources) && throw(ArgumentError("source exchange workload requires a voltage source"))
    for family in ("generator","ibr"),(id,d) in sort!(collect(table(net,family));by=first)
        tm=terminals(d,"$family/$id")
        cfg=get(d,family=="generator" ? "configuration" : "topology",nothing)
        n=if family=="generator" && cfg=="WYE" && length(tm)>=2
            length(tm)-1
        elseif cfg=="SINGLE_PHASE" && length(tm)==2
            1
        elseif (family=="generator" && cfg=="DELTA" && length(tm)==3) ||
               (family=="ibr" && ((cfg=="THREE_LEG" && length(tm)==3) || (cfg=="FOUR_LEG" && length(tm)==4)))
            3
        else
            throw(ArgumentError("unsupported objective port shape for $family/$id"))
        end
        for key in ("p_min","p_max","q_min","q_max")
            v=get(d,key,nothing)
            v isa AbstractVector && length(v)==n && all(finite_real,v) ||
                throw(ArgumentError("$family/$id requires $n finite values for $key"))
        end
        all(d["p_min"].<=d["p_max"]) && all(d["q_min"].<=d["q_max"]) ||
            throw(ArgumentError("inverted dispatch box at $family/$id"))
        active |= any(d["p_min"].<d["p_max"])
        reactive |= any(d["q_min"].<d["q_max"])
        append!(dispatch,[(Symbol(family),id,k) for k in 1:n])
    end
    (;sources,dispatch,active_dispatch_box_freedom=active,reactive_dispatch_box_freedom=reactive)
end

"""Versioned experimental objective, with coefficients on SI powers.

Cost: 0.25 Pgrid[kW] + 0.02 Pgrid[kW]^2 + 0.002 Qgrid[kvar]^2,
plus 0.10 Pinternal[kW] + 0.02 Ppcc[kW]^2 + 0.002 Qpcc[kvar]^2 per
dispatch coil. Generator internal/PCC powers coincide; IBR powers do not.
Tracking: squared aggregate source P-target/Q errors in kW/kvar, plus 0.01
times dispatch deviations from P-box midpoint and Q=0 in those units.
The physical objective divisor is one. Coefficients are study choices, not tariffs.
"""
function workload(net,kind;exchange_target_W=nothing)
    kind in (:quadratic_cost,:exchange_tracking) || throw(ArgumentError("unknown transfer workload"))
    c=channels(net)
    ts=IVRPowerTerm[]
    if kind==:quadratic_cost
        push!(ts,IVRPowerTerm(channels=c.sources,linear=.25/1000,quadratic=.02/1e6),
            IVRPowerTerm(channels=c.sources,quantity=:q,quadratic=.002/1e6))
        for (f,id,k) in c.dispatch
            push!(ts,IVRPowerTerm(channels=[(f==:ibr ? :ibr_internal : f,id,k)],linear=.10/1000),
                IVRPowerTerm(channels=[(f,id,k)],quadratic=.02/1e6),
                IVRPowerTerm(channels=[(f,id,k)],quantity=:q,quadratic=.002/1e6))
        end
    else
        finite_real(exchange_target_W) || throw(ArgumentError("explicit finite source-P target required"))
        push!(ts,IVRPowerTerm(channels=c.sources,target=exchange_target_W,quadratic=1e-6),
            IVRPowerTerm(channels=c.sources,quantity=:q,quadratic=1e-6))
        for (f,id,k) in c.dispatch
            d=net[string(f)][id]
            midpoint=d["p_min"][k]/2+d["p_max"][k]/2
            push!(ts,IVRPowerTerm(channels=[(f,id,k)],target=midpoint,quadratic=1e-8),
                IVRPowerTerm(channels=[(f,id,k)],quantity=:q,quadratic=1e-8))
        end
    end
    (;schema="FormulationLab.transfer_power_workload.v1",kind,terms=ts,objective_scale=1.,
        exchange_target_W=kind==:exchange_tracking ? Float64(exchange_target_W) : nothing,
        channels=c,legacy_prices_used=false,input_modified=false)
end

clone(o;kwargs...)=IVRNLPOptions(;merge((;(k=>deepcopy(getfield(o,k)) for k in fieldnames(IVRNLPOptions))...), (;kwargs...))...)
arm(mode,lifting,zero)="$(mode)__$(lifting)__zero_$(zero)"

"""One full control and eight factorial arms sharing an explicit unit policy.

`common` supplies scaling and observation settings, not a previously reduced
profile. Unrelated transformations are refused so they cannot silently confound
this experiment. Every arm owns its nested options. Network applicability is
checked by the compiler later; this constructor has no transformer-kind filter.
"""
function profiles(net,kind;common::IVRNLPOptions,exchange_target_W=nothing)
    common.specialization==:off && common.linear_elimination==:off &&
        common.device_elimination==:off && !common.zero_load_elimination &&
        common.lifting==:off && common.power_sharing==:off &&
        !common.fixed_observation_elimination && !common.fixed_bound_elimination && common.coincident_voltage_bounds==:separate &&
        common.series_selection==:all && common.observation_selection==:all ||
        throw(ArgumentError("common options must not enable experimental reductions or selective lifting"))
    common.transformer_nameplate==:bmopftools || throw(ArgumentError("retain BMOPFTools nameplate limits"))
    w=workload(net,kind;exchange_target_W)
    base=clone(common;objective=:power,power_terms=w.terms,objective_scale=w.objective_scale)
    ps=[(;name="full_powers",options=clone(base;lifting=:powers))]
    for mode in (:off,:transformer_currents),lifting in (:powers,:bounded_observations),zero in (false,true)
        push!(ps,(;name=arm(mode,lifting,zero),options=clone(base;specialization=:conductor_regions,
            linear_elimination=:passive_blocks,device_elimination=mode,lifting,zero_load_elimination=zero)))
    end
    # Separate unlifted model for representation checks, not a tenth timing arm.
    (;workload=w,reference=clone(base;load_power_lifting=false),candidates=ps)
end
end
