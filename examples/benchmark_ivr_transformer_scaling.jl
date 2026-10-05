# Separate model coordinates, row normalization and the solver scaling policy.
# Run without concurrent tests/docs. Instrumented diagnostics are separate runs.
module IVRTransformerScalingStudy
using FormulationLab, JuMP, JSON3, SHA, LinearAlgebra
include("benchmark_ivr_lifting_blocks.jl")
const L=IVRLiftingBlockStudy
const P=L.P
const SOURCE_SHA=bytes2hex(sha256(read(@__FILE__)))

function profiles(;nlp_scaling_method="none",objective=:feasibility)
    nlp_scaling_method in ("none","gradient-based") || throw(ArgumentError("unknown study solver scaling policy"))
    [(;name="$(transformer_scaling)_$(row_scaling)",
        options=IVRNLPOptions(;objective,transformer_scaling,row_scaling,ground_scaling=:voltage),
        solver_options=(linear_solver="mumps",mumps_pivot_order=0,nlp_scaling_method))
     for transformer_scaling in (:off,:nominal) for row_scaling in (:legacy,:composed)]
end

function benchmark(net,output;nlp_scaling_method="none",objective=:feasibility,repetitions=8,source_sha256=nothing)
    repetitions>0 && repetitions%8==0 || throw(ArgumentError("eight-sweep multiples balance four profiles"))
    candidates=profiles(;nlp_scaling_method,objective);point=L.start_point(net)
    checks=map(candidates) do p
        b=build_opf(net,IVRNLP(p.options));r=ivr_nlp_point_report(b,point)
        isempty(r.missing_channels) && length(r.variable_values)==num_variables(b.model) &&
            all(isfinite,values(r.variable_values)) &&
            max(r.max_binding_residual_pu,r.max_reconstruction_residual_pu)<=1e-10 || error("unrepresentable shared start")
        (;name=p.name,variables=num_variables(b.model),binding=r.max_binding_residual_pu,
            reconstruction=r.max_reconstruction_residual_pu,
            transformer_scaling=b.numerical_diagnostics[:transformer_scaling_report],
            composed_row_normalization=b.numerical_diagnostics[:composed_row_normalization],
            per_unit_bases=b.numerical_diagnostics[:per_unit_bases])
    end
    open(io->JSON3.write(io,net),output*".input.json","w")
    manifest=(;objective,repetitions,nlp_scaling_method,source_sha256,runner_sha256=SOURCE_SHA,checks,
        note="Full IVR only: isolate local coordinates and composed row normalization before studying reduction interactions. Fixed global 10 kVA power base and physical objective, voltage ground scaling, MUMPS AMD; same unloaded physical point. Solver scaling is explicit and separate. Balanced eight-sweep multiples. Ipopt wall time only; diagnostics/extraction/compilation excluded; no instrumented callbacks.")
    open(io->JSON3.write(io,manifest),output*".manifest.json","w")
    report=P.benchmark(net,output;repetitions,candidates,source_sha256,initial_point=point)
    report["position_balanced"]=all(count(o->o[k]==p.name,report["orders"])==repetitions/4
        for p in candidates for k in eachindex(candidates))
    report["position_balanced"] || error("unbalanced profile position")
    open(io->JSON3.write(io,report),output,"w")
    report
end
end
