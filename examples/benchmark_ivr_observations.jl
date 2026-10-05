# Run separately from tests/docs and other performance experiments.
module IVRObservationStudy
using FormulationLab, JuMP, JSON3, SHA, LinearAlgebra
include("benchmark_ivr_lifting_blocks.jl")
const L=IVRLiftingBlockStudy
const P=L.P
const SOURCE_SHA=bytes2hex(sha256(read(@__FILE__)))

"""Full/direct-block controls and a 2×2 observation threshold/sharing ablation.

Thresholds 2 and 8 are explicit experimental choices, not an adaptive policy.
Power lifting is identical across the four observation profiles. Device-current
elimination remains off to isolate this experiment from that separate option.
"""
function profiles(;objective=:source_import)
    specs=[("full",:off,:off,2,:off), ("blocks_off",:passive_blocks,:off,2,:off),
        [("observations_$(threshold)_$(sharing)",:passive_blocks,:bounded_observations,threshold,sharing)
         for threshold in (2,8) for sharing in (:off,:exact)]...]
    [(;name,options=IVRNLPOptions(;objective,ground_scaling=:voltage,
        specialization=linear_elimination==:off ? :off : :conductor_regions,
        linear_elimination,lifting,observation_support_threshold=threshold,observation_sharing=sharing),
        solver_options=(linear_solver="mumps",mumps_pivot_order=0))
     for (name,linear_elimination,lifting,threshold,sharing) in specs]
end

function benchmark(net,output;objective=:source_import,repetitions=12,source_sha256=nothing)
    repetitions>0 && repetitions%12==0 || throw(ArgumentError("twelve-sweep multiples balance six profiles"))
    candidates=profiles(;objective);point=L.start_point(net)
    checks=map(candidates) do p
        b=build_opf(net,IVRNLP(p.options));r=ivr_nlp_point_report(b,point)
        isempty(r.missing_channels) && length(r.variable_values)==num_variables(b.model) &&
            all(isfinite,values(r.variable_values)) &&
            max(r.max_binding_residual_pu,r.max_reconstruction_residual_pu)<=1e-10 || error("unrepresentable shared start")
        (;name=p.name,variables=num_variables(b.model),binding=r.max_binding_residual_pu,
            reconstruction=r.max_reconstruction_residual_pu,
            lifted_real_variables=b.numerical_diagnostics[:lifted_real_variables],
            shared_observation_count=b.numerical_diagnostics[:shared_observation_count])
    end
    open(io->JSON3.write(io,net),output*".input.json","w")
    manifest=(;objective,repetitions,source_sha256,runner_sha256=SOURCE_SHA,checks,
        note="Identical physical input and unloaded circuit start; voltage ground scaling and AMD. Balanced twelve-sweep multiples. Primary metric Ipopt wall time only, excluding compilation/start/extraction/audits. All failures and outliers retained; no tolerance relaxation.")
    open(io->JSON3.write(io,manifest),output*".manifest.json","w")
    report=P.benchmark(net,output;repetitions,candidates,source_sha256,initial_point=point)
    report["position_balanced"]=all(count(o->o[k]==p.name,report["orders"])==repetitions/6
        for p in candidates for k in eachindex(candidates))
    report["position_balanced"] || error("unbalanced profile position")
    open(io->JSON3.write(io,report),output,"w")
    report
end
end
