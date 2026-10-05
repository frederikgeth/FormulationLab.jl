"""Matched exact, signed and proportional bounded-observation graph extensions."""
module IVRAffineSharingStudy
using FormulationLab
include("benchmark_ivr_hybrid.jl")
const H=IVRHybridStudy
const P=H.P
const E=H.E

function profiles(net,workload;exchange_target_W=nothing,nlp_scaling_method="none")
    prior=H.profiles(net,workload;exchange_target_W,nlp_scaling_method)
    specs=[("full_powers","full",:powers,:exact),
        ("reduced_powers","blocks",:powers,:exact),
        [("observations_$(sharing)","blocks",:bounded_observations,sharing)
            for sharing in (:off,:exact,:signed,:proportional)]...]
    [begin
        base=only(p for p in prior if p.name==parent)
        changes=(;lifting,observation_sharing=sharing)
        options=IVRNLPOptions(;(k=>deepcopy(get(changes,k,getfield(base.options,k))) for k in fieldnames(IVRNLPOptions))...)
        (;name,options,solver_options=base.solver_options,
            factors=merge(base.factors,(;lifting,observation_sharing=sharing)))
    end for (name,parent,lifting,sharing) in specs]
end
benchmark(path,output;kwargs...)=H.F.benchmark_profiles(path,output,profiles,@__FILE__;kwargs...)
end
