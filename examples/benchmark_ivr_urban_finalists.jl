"""Common panel for retained power-base, reuse and signed/hybrid finalists.

Selected whole profiles plus matched controls; not a complete factorial or an
exhaustive search. No defaults or historical benchmark definitions are changed.
"""
module IVRUrbanFinalistStudy
using FormulationLab
include("benchmark_ivr_structural_interactions.jl")
const S=IVRStructuralInteractionStudy
const F=S.F
const E=S.E
const P=S.P

function profiles(net,workload;exchange_target_W=nothing,nlp_scaling_method="none")
    old=F.profiles(net,workload;exchange_target_W,nlp_scaling_method)
    structural=S.profiles(net,workload;exchange_target_W,nlp_scaling_method)
    specs=[("full_10k",old,"full_10k",(;)),
        ("full_1k",old,"full_1k",(;)),
        ("full_powers",structural,"full_powers",(;)),
        ("reduced_1k",old,"reduced_1k",(;)),
        ("dispatch100_unlifted",old,"reduced_dispatch_100k",(;)),
        ("powers",structural,"reduced_powers",(;)),
        ("powers_reuse",structural,"reduced_powers",(;power_sharing=:generators)),
        ("lifts10_reuse",old,"reduced_reuse",(;)),
        ("dispatch100_lifts1",old,"reduced_lifts_1k",(;generator_power_bases=Dict(id=>1e5 for id in keys(net["generator"])))),
        ("dispatch100_lifts10",old,"reduced_lifts_10k",(;generator_power_bases=Dict(id=>1e5 for id in keys(net["generator"])))),
        ("cap4_powers",structural,"reduced_powers",(;linear_elimination=:passive_hybrid)),
        ("cap4_powers_reuse",structural,"reduced_powers",(;linear_elimination=:passive_hybrid,power_sharing=:generators)),
        ("blocks_signed",structural,"blocks_signed_off",(;)),
        ("blocks_signed_reuse",structural,"blocks_signed_generators",(;)),
        ("cap4_signed",structural,"cap4_signed_off",(;)),
        ("cap4_signed_reuse",structural,"cap4_signed_generators",(;))]
    [begin
        base=only(p for p in source if p.name==parent)
        options=IVRNLPOptions(;(k=>deepcopy(get(changes,k,getfield(base.options,k))) for k in fieldnames(IVRNLPOptions))...)
        factors=(;parent,s_base=options.s_base,generator_power_bases=deepcopy(options.generator_power_bases),
            lifted_power_base=options.lifted_power_base,lifting=options.lifting,power_sharing=options.power_sharing,
            linear_elimination=options.linear_elimination,passive_component_limit=options.passive_component_limit,
            observation_sharing=options.observation_sharing)
        (;name,options,factors,solver_options=base.solver_options)
    end for (name,source,parent,changes) in specs]
end
benchmark(path,output;checkpoint=:sweep,kwargs...)=F.benchmark_profiles(path,output,profiles,@__FILE__;checkpoint,kwargs...)
end
