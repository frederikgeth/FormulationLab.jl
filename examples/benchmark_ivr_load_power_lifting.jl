"""Matched original/lifted voltage-law powers, retaining all six transfer profiles.

The only within-pair option change is load_power_lifting. Failed original arms
remain explicit and cannot win a timing ranking. Both modes enforce the same
ordinary-transformer nameplate policy. Build time is not a ranking metric.
"""
module IVRLoadPowerStudy
using FormulationLab
include("benchmark_ivr_threephase_transfer.jl")
const T=IVRThreePhaseTransferStudy
const P=T.P
function profiles(net,workload;kwargs...)
    [merge(p,(;name=p.name*(enabled ? "__load_power" : "__original"),
        formulation_name=p.name,factors=merge(p.factors,(;load_power_lifting=enabled))))
        for enabled in (false,true) for p in T.profiles(net,workload;load_power_lifting=enabled,kwargs...)]
end
benchmark(path,output;checkpoint=:sweep,kwargs...)=T.M.F.benchmark_profiles(path,output,profiles,@__FILE__;checkpoint,kwargs...)
end
