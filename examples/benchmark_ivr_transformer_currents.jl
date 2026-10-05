# Run separately from tests/docs and other timing experiments.
module IVRTransformerCurrentStudy
using FormulationLab, JuMP, JSON3, SHA, LinearAlgebra
include("benchmark_ivr_lifting_blocks.jl")
const L=IVRLiftingBlockStudy
const P=L.P
const SOURCE_SHA=bytes2hex(sha256(read(@__FILE__)))

"""A factorial comparison of full/block coordinates and coil-current removal."""
function profiles(;objective=:source_import)
    [(;name="$(regional ? "blocks" : "full")_$(device_elimination)",
        options=IVRNLPOptions(;objective,ground_scaling=:voltage,
            specialization=regional ? :conductor_regions : :off,
            linear_elimination=regional ? :passive_blocks : :off,device_elimination),
        solver_options=(linear_solver="mumps",mumps_pivot_order=0))
     for regional in (false,true) for device_elimination in (:off,:transformer_currents)]
end

function benchmark(net,output;objective=:source_import,repetitions=8,source_sha256=nothing)
    repetitions>0 && repetitions%8==0 || throw(ArgumentError("eight-sweep multiples balance four profiles"))
    candidates=profiles(;objective);point=L.start_point(net)
    checks=map(candidates) do p
        b=build_opf(net,IVRNLP(p.options));r=ivr_nlp_point_report(b,point)
        isempty(r.missing_channels) && length(r.variable_values)==num_variables(b.model) &&
            max(r.max_binding_residual_pu,r.max_reconstruction_residual_pu)<=1e-10 || error("unrepresentable shared start")
        (;name=p.name,variables=num_variables(b.model),binding=r.max_binding_residual_pu,
            reconstruction=r.max_reconstruction_residual_pu,
            device_elimination=b.numerical_diagnostics[:device_elimination_report])
    end
    open(io->JSON3.write(io,net),output*".input.json","w")
    manifest=(;objective,repetitions,source_sha256,runner_sha256=SOURCE_SHA,checks,
        note="Same physical input and unloaded circuit start, matched voltage ground scaling and AMD; eight balanced sweeps. Primary metric Ipopt wall time only. All failures and outliers retained. No compilation/start/extraction/audit penalty.")
    open(io->JSON3.write(io,manifest),output*".manifest.json","w")
    report=P.benchmark(net,output;repetitions,candidates,source_sha256,initial_point=point)
    report["position_balanced"]=all(count(o->o[k]==p.name,report["orders"])==repetitions/4
        for p in candidates for k in eachindex(candidates))
    report["position_balanced"] || error("unbalanced profile position")
    open(io->JSON3.write(io,report),output,"w")
    report
end
end
