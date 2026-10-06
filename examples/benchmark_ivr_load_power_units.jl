"""Isolate voltage-law power column units on the retained power-profile shortlist.

The four declared treatments keep electrical, generator and other power-lift
units fixed. Voltage classes use the declared native coil v_nom, not bus names:
all channels <= 1 kV receive 1 kVA; all > 1 kV receive 10 kVA. A load straddling
this threshold is refused. This is an experimental rule, not a voltage standard
or a topology-inferred transformer region. Nominal units use the maximum channel
hypot(P_nom,Q_nom), with a declared 1 VA floor (also for zero demand).
"""
module IVRLoadPowerUnitStudy
using FormulationLab
include("benchmark_ivr_threephase_transfer.jl")
const T=IVRThreePhaseTransferStudy
const P=T.P
vector(x)=x isa AbstractVector ? x : [x]
function assignments(net,treatment)
    treatment in (:uniform_1k,:uniform_10k,:voltage_class,:nominal_max) || throw(ArgumentError("unknown load unit treatment"))
    bases=Dict{String,Float64}()
    for (id,d) in get(net,"load",Dict())
        lowercase(get(d,"model","constant_power"))=="constant_power" && continue
        FormulationLab._sdp_is_impedance_load(d) && continue
        if treatment in (:uniform_1k,:uniform_10k)
            bases[id]=treatment==:uniform_1k ? 1e3 : 1e4
        elseif treatment==:voltage_class
            vs=vector(d["v_nom"])
            all(v->isfinite(v) && v>0,vs) || throw(ArgumentError("invalid nominal voltage at load $id"))
            bases[id]=all(v->v<=1e3,vs) ? 1e3 : all(v->v>1e3,vs) ? 1e4 :
                throw(ArgumentError("load $id straddles the declared 1 kV coil threshold"))
        else
            ps=vector(d["p_nom"]);qs=vector(d["q_nom"])
            length(ps)==length(qs) || throw(ArgumentError("inconsistent nominal power channels at load $id"))
            all(isfinite,ps) && all(isfinite,qs) || throw(ArgumentError("invalid nominal power at load $id"))
            bases[id]=max(1.,maximum(hypot.(ps,qs)))
        end
    end
    bases
end
function profiles(net,workload;kwargs...)
    selected=filter(p->p.name in ("full_powers","reduced_powers","reduced_reuse"),
        T.profiles(net,workload;load_power_lifting=true,kwargs...))
    [let bases=assignments(net,treatment)
        merge(p,(;name=p.name*"__"*String(treatment),formulation_name=p.name,
            options=IVRNLPOptions(;(k=>(k==:load_power_bases ? copy(bases) : deepcopy(getfield(p.options,k)))
                for k in fieldnames(IVRNLPOptions))...),
            factors=merge(p.factors,(;load_unit_treatment=treatment,load_power_bases=copy(bases)))))
    end for treatment in (:uniform_1k,:uniform_10k,:voltage_class,:nominal_max) for p in selected]
end
benchmark(path,output;checkpoint=:sweep,kwargs...)=T.M.F.benchmark_profiles(path,output,profiles,@__FILE__;checkpoint,kwargs...)
end
