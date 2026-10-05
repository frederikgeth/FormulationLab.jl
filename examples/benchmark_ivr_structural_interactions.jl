"""Controlled line-condensation × signed-observation × generator-reuse study.

Eight bounded-observation factorial arms and full/reduced power-only controls.
All units, physical objectives and other reduction settings remain fixed.
"""
module IVRStructuralInteractionStudy
using FormulationLab
include("benchmark_ivr_affine_sharing.jl")
const A=IVRAffineSharingStudy
const F=A.H.F
const E=A.E
const P=A.P

function profiles(net,workload;exchange_target_W=nothing,nlp_scaling_method="none")
    prior=A.profiles(net,workload;exchange_target_W,nlp_scaling_method)
    template=only(p for p in prior if p.name=="observations_exact")
    arms=[begin
        overrides=(;linear_elimination=mode,observation_sharing=sharing,power_sharing=reuse)
        options=IVRNLPOptions(;(k=>deepcopy(get(overrides,k,getfield(template.options,k)))
            for k in fieldnames(IVRNLPOptions))...)
        (;name="$(label)_$(sharing)_$(reuse)",options,
            factors=merge(template.factors,(;linear_elimination=mode,observation_sharing=sharing,power_sharing=reuse)),
            solver_options=template.solver_options)
    end for (label,mode) in (("blocks",:passive_blocks),("cap4",:passive_hybrid))
        for sharing in (:exact,:signed) for reuse in (:off,:generators)]
    [only(p for p in prior if p.name=="full_powers");
     only(p for p in prior if p.name=="reduced_powers");arms]
end
benchmark(path,output;kwargs...)=F.benchmark_profiles(path,output,profiles,@__FILE__;kwargs...)
end
