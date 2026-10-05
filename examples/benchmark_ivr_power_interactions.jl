"""Controlled dispatch-unit × lifted-unit × generator-reuse interactions.

Eight reduced factorial arms and two explicit controls. Assembly units, physical
objective, reduction bundle and solver policy stay fixed within each panel.
"""
module IVRPowerInteractionStudy
using FormulationLab
include("benchmark_ivr_power_finalists.jl")
const F=IVRPowerFinalistStudy
const E=F.E
const P=F.P

function profiles(net,workload;exchange_target_W=nothing,nlp_scaling_method="none")
    prior=F.profiles(net,workload;exchange_target_W,nlp_scaling_method)
    template=only(p for p in prior if p.name=="reduced_lifts_10k")
    arms=[begin
        overrides=(;generator_power_bases=Dict(id=>gb for id in keys(net["generator"])),
            lifted_power_base=lb,power_sharing=sharing)
        options=IVRNLPOptions(; (k=>deepcopy(get(overrides,k,getfield(template.options,k)))
            for k in fieldnames(IVRNLPOptions))...)
        (;name="dispatch_$(Int(gb/1e3))k_lifts_$(Int(lb/1e3))k_$(sharing)",options,
            factors=merge(template.factors,(;generator_base=gb,lifted_power_base=lb,power_sharing=sharing)),
            solver_options=template.solver_options)
    end for gb in (1e4,1e5) for lb in (1e3,1e4) for sharing in (:off,:generators)]
    [only(p for p in prior if p.name=="full_10k");
     only(p for p in prior if p.name=="reduced_dispatch_100k");arms]
end

benchmark(path,output;kwargs...) = F.benchmark_profiles(path,output,profiles,@__FILE__;kwargs...)
end
