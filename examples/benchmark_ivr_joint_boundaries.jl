"""Manufactured P/Q dispatch at simultaneous terminal-current and voltage limits."""
module IVRJointBoundaryStudy
using FormulationLab
include("benchmark_ivr_line_transfer.jl")
const L=IVRLineTransferStudy
const P=L.P

"""Declare a joint-boundary case or one single-bound relaxation control.

The underlying pi-line fixture is manufactured. Added generators may consume
or produce active power. Positive reactive targets use a nominal lower voltage
bound; negative targets use a nominal upper bound. `:wide_voltage` restores the
fixture voltage band at the same 200 A rating; `:loose_current` uses 250 A at
the same nominal voltage bound. Matrices, shunts and objectives are unchanged.
All physical changes, including tightened fixture bounds, are recorded.
"""
function scenario(;conductors=2,direction=1,treatment=:joint)
    direction isa Integer && !(direction isa Bool) && direction in (-1,1) ||
        throw(ArgumentError("direction must be -1 or 1"))
    treatment in (:joint,:wide_voltage,:loose_current) || throw(ArgumentError("unknown boundary treatment"))
    original=L.shunt_fixture(;conductors)
    net,base=L.scenario(original;line_id="l1",terminal_indices=1:conductors,q_capacity_VAR=1.2e6)
    for g in values(net["generator"])
        g["p_min"]=-copy(g["q_max"]);g["p_max"]=copy(g["q_max"])
    end
    field=(conductors==2 ? "vpn_" : "vpp_")*(direction==1 ? "min" : "max")
    nominal=conductors==2 ? 230. : sqrt(3.)*230.
    if treatment!=:wide_voltage
        net["bus"]["b1"][field]=fill(nominal,conductors==2 ? 1 : 3)
    end
    treatment==:loose_current && (net["line"]["l1"]["i_max"]=fill(250.,conductors))
    changes=Any[]
    for family in ("bus","line","generator"),id in sort!(collect(keys(net[family])))
        before=get(get(original,family,Dict()),id,nothing);after=net[family][id]
        isequal(before,after) || push!(changes,(;family,id,before=deepcopy(before),after=deepcopy(after)))
    end
    net,(;conductors,direction,treatment,devices=base.devices,changes,
        voltage_bus="b1",voltage_field=field,nominal_voltage_V=nominal,
        target_VAR=direction*6e5,original_fields_preserved=false,
        note="Declared manufactured boundary interventions; all matrix and shunt data retained. No external feeder is modified.")
end

"""Track opposite Q requests and zero active power on every native device coil."""
function profiles(net,manifest;nlp_scaling_method="none")
    ts=[L.terms(manifest;target_VAR=manifest.target_VAR);
        [IVRPowerTerm(channels=[(:generator,d.id,k)],quantity=:p,quadratic=1e-6)
            for d in manifest.devices for k in 1:d.channels]]
    [merge(p,(;options=IVRNLPOptions(;(k=>(k==:power_terms ? deepcopy(ts) : deepcopy(getfield(p.options,k)))
        for k in fieldnames(IVRNLPOptions))...)))
        for p in L.profiles(net,manifest;target_VAR=manifest.target_VAR,nlp_scaling_method)]
end

"""SI slacks for the selected receiving-voltage bound, in declared bus order."""
function voltage_activity(net,point,manifest;atol_V=1e-5)
    tol=L.finite_value(atol_V,"atol_V");tol>=0 || throw(ArgumentError("negative activity tolerance"))
    b=manifest.voltage_bus;field=manifest.voltage_field;bus=net["bus"][b]
    field in ("vpn_min","vpn_max","vpp_min","vpp_max") || throw(ArgumentError("unknown voltage-bound field"))
    tm=bus["terminal_names"];neutral=get(bus,"neutral_terminal","n")
    phases=filter(!=(neutral),tm)
    (startswith(field,"vpn_") ? neutral in tm : length(phases)==3) || throw(ArgumentError("unsupported voltage channel layout"))
    pairs=startswith(field,"vpn_") ? [(t,neutral) for t in phases] :
        [(phases[1],phases[2]),(phases[2],phases[3]),(phases[3],phases[1])]
    caps=bus[field]
    caps isa AbstractVector && length(caps)==length(pairs) || throw(ArgumentError("voltage-bound arity mismatch"))
    all(x->x isa Real && !(x isa Bool) && isfinite(x) && x>=0,caps) || throw(ArgumentError("invalid voltage bound"))
    records=Any[]
    for (k,(a,z)) in enumerate(pairs)
        voltage=abs(point.voltage[(b,a)]-point.voltage[(b,z)])
        isfinite(voltage) || throw(ArgumentError("nonfinite voltage observation"))
        cap=caps[k];slack=endswith(field,"min") ? voltage-cap : cap-voltage
        push!(records,(;bus=b,field,channel=k,terminals=(a,z),voltage_V=voltage,limit_V=cap,
            slack_V=slack,active=0<=slack<=tol,violated=slack<0))
    end
    (;atol_V=tol,records)
end
end
