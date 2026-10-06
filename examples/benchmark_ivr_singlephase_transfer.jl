"""Single-phase DER/load channels on an unchanged MV/LV network.

The declared voltage bands are physical scenarios, not numerical treatments.
Full, reduced and generator-reuse formulations share each scenario, objective,
physical start and bound policy. Timing ranks Ipopt wall time only.
"""
module IVRSinglePhaseTransferStudy
using FormulationLab
include("benchmark_ivr_load_power_units.jl")
const U=IVRLoadPowerUnitStudy
const T=U.T
const M=T.M
const P=U.P

"""Add mixed single-phase devices and missing phase-neutral voltage bounds.

`:wide` adds 200–260 V; `:tight` adds 0.98–1.02 and `:narrow` adds
0.995–1.005 times each unloaded phase-neutral voltage. Existing fields are
preserved, even if they are looser.
The band names do not assert feasibility or an active constraint. Bounds cover
every non-neutral terminal at selected buses, not just the loaded phase.
"""
function scenario(original;voltage_band=:wide)
    voltage_band in (:wide,:tight,:narrow) || throw(ArgumentError("voltage_band must be :wide, :tight or :narrow"))
    # Check raw electrical declarations before computing a start or making additions.
    FormulationLab._ivrn_check(original)
    net,base=M.scenario(original;mixed=true)
    start=M.E.S.U.G.H.S.L.start_point(original)
    additions=Any[]
    buses=sort!(unique([net["load"][id]["bus"] for id in base.selected_loads]))
    for id in buses
        b=net["bus"][id];old=original["bus"][id]
        neutral=get(b,"neutral_terminal","n")
        neutral in b["terminal_names"] || throw(ArgumentError("selected bus $id has no declared neutral"))
        phases=filter(!=(neutral),b["terminal_names"])
        nominal=[abs(start.voltage[(id,t)]-start.voltage[(id,neutral)]) for t in phases]
        all(v->isfinite(v) && v>0,nominal) || throw(ArgumentError("invalid unloaded phase-neutral voltage at $id"))
        halfwidth=voltage_band==:narrow ? .005 : .02
        for (field,factor,wide) in (("vpn_min",1-halfwidth,200.),("vpn_max",1+halfwidth,260.))
            haskey(old,field) && continue
            limits=voltage_band==:wide ? fill(wide,length(phases)) : factor.*nominal
            b[field]=limits
            push!(additions,(;bus=id,field,terminals=copy(phases),unloaded_voltage_V=nominal,limits_V=copy(limits)))
        end
    end
    changes=Any[]
    for family in ("bus","load","generator","ibr"),id in sort!(collect(keys(get(net,family,Dict()))))
        before=get(get(original,family,Dict()),id,nothing);after=net[family][id]
        isequal(before,after) || push!(changes,(;family,id,before=deepcopy(before),after=deepcopy(after)))
    end
    net,(;voltage_band,mixed=true,selected_loads=copy(base.selected_loads),voltage_additions=additions,
        changes,original_fields_preserved=true,
        note="Single-phase channels on the supplied network; all original fields retained. Added voltage bands are declared scenarios, not statutory limits or evidence of activity.")
end

"""Nine retained arms: three formulations by three load-unit treatments.

The common control uses 1 kVA columns and unscaled load rows. Nominal columns
use max(1 VA, max channel hypot(P_nom,Q_nom)); the third treatment additionally
scales load-law rows with those nominal units. Other numerical factors stay fixed.
"""
function profiles(net,workload;kwargs...)
    selected=filter(p->p.name in ("full_powers","reduced_powers","reduced_reuse"),
        T.profiles(net,workload;load_power_lifting=true,kwargs...))
    nominal=U.assignments(net,:nominal_max)
    [let columns=U.assignments(net,column),rows=mode==:off ? Dict{String,Float64}() : copy(nominal)
        merge(p,(;name=p.name*"__"*String(column)*"__"*String(mode),formulation_name=p.name,
            options=IVRNLPOptions(;(k=>(k==:load_power_bases ? copy(columns) :
                k==:load_power_row_bases ? copy(rows) : k==:load_power_row_scaling ? mode :
                deepcopy(getfield(p.options,k))) for k in fieldnames(IVRNLPOptions))...),
            factors=merge(p.factors,(;column_treatment=column,row_mode=mode,
                load_power_bases=copy(columns),load_power_row_bases=copy(rows)))))
    end for p in selected for (column,mode) in ((:uniform_1k,:off),(:nominal_max,:off),(:nominal_max,:laws))]
end
benchmark(path,output;checkpoint=:sweep,kwargs...)=
    M.F.benchmark_profiles(path,output,profiles,@__FILE__;checkpoint,kwargs...)

"""Independent SI voltage slacks; activity is geometric, not a dual claim.

Returns every finite phase-neutral bound, with its origin and signed slack.
Violations are never labelled active. The physical auditor remains the acceptance
gate; this helper describes the accepted point rather than changing tolerances.
"""
function voltage_activity(net,point,manifest;atol_V=1e-4)
    atol_V isa Real && !(atol_V isa Bool) && isfinite(atol_V) && atol_V>=0 ||
        throw(ArgumentError("activity tolerance must be finite and nonnegative"))
    added=Set((x.bus,x.field) for x in manifest.voltage_additions)
    records=Any[]
    for id in sort!(collect(keys(net["bus"])))
        b=net["bus"][id];neutral=get(b,"neutral_terminal","n")
        any(haskey(b,f) for f in ("vpn_min","vpn_max")) || continue
        phases=filter(!=(neutral),b["terminal_names"])
        for field in ("vpn_min","vpn_max")
            haskey(b,field) || continue
            limits=b[field] isa AbstractVector ? b[field] : fill(b[field],length(phases))
            length(limits)==length(phases) || throw(ArgumentError("invalid voltage-bound arity at $id"))
            for (t,limit) in zip(phases,limits)
                isfinite(limit) || continue
                voltage=abs(point.voltage[(id,t)]-point.voltage[(id,neutral)])
                slack=field=="vpn_min" ? voltage-limit : limit-voltage
                push!(records,(;bus=id,terminal=t,field,limit_V=limit,voltage_V=voltage,slack_V=slack,
                    origin=(id,field) in added ? :added : :inherited,
                    active=0<=slack<=atol_V,violated=slack<0))
            end
        end
    end
    (;atol_V,records,note="Geometric activity only; negative slack is a violation, and no multiplier or sensitivity claim is made.")
end
end
