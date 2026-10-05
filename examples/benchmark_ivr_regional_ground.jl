module IVRRegionalGroundStudy
using FormulationLab, JuMP, JSON3, SHA
include("benchmark_ivr_transformer_stress.jl")
const H=IVRTransformerStressStudy

function profiles(;nlp_scaling_method="none")
    nlp_scaling_method in ("none","gradient-based") || throw(ArgumentError("unknown solver scaling policy"))
    [(;name="$(transformer_scaling)_$(ground_scaling)",
        options=IVRNLPOptions(;objective=:source_import,transformer_scaling,ground_scaling,row_scaling=:composed),
        solver_options=(linear_solver="mumps",mumps_pivot_order=0,nlp_scaling_method))
        for transformer_scaling in (:off,:nominal) for ground_scaling in (:off,:voltage,:regional_voltage)]
end

function benchmark(output;limit=:capability,segments=48,nlp_scaling_method="none",repetitions=12)
    repetitions>0 && repetitions%12==0 || throw(ArgumentError("twelve-sweep multiples balance six profiles"))
    net=H.C.case(;limit,segments);expected=H.C.expected(limit);candidates=profiles(;nlp_scaling_method)
    point=H.S.L.start_point(net)
    checks=map(candidates) do p
        b=build_opf(net,IVRNLP(p.options));r=ivr_nlp_point_report(b,point)
        isempty(r.missing_channels) && length(r.variable_values)==num_variables(b.model) &&
            all(isfinite,values(r.variable_values)) &&
            max(r.max_binding_residual_pu,r.max_reconstruction_residual_pu)<=1e-10 || error("unrepresentable shared start")
        (;name=p.name,variables=num_variables(b.model),ground=b.numerical_diagnostics[:ground_scaling_report],
            transformer=b.numerical_diagnostics[:transformer_scaling_report])
    end
    open(io->JSON3.write(io,net),output*".input.json","w")
    open(io->JSON3.write(io,(;limit,segments,expected,repetitions,nlp_scaling_method,checks,
        note="Manufactured SI active-limit panel. Global/nominal coordinates crossed with no/global/regional ground multiplier; composed circuit rows, fixed common 10 kVA base. Same physical input/unloaded start. Full IVR, MUMPS AMD, twelve balanced sweeps, no instrumented callbacks. Rank Ipopt wall time only; retain failures and outliers.")),output*".manifest.json","w")
    r=H.S.P.benchmark(net,output;repetitions,candidates,initial_point=point,
        source_sha256=bytes2hex(sha256(read(joinpath(@__DIR__,"ivr_transformer_stress_cases.jl")))))
    r["position_balanced"]=all(count(o->o[k]==p.name,r["orders"])==repetitions/6 for p in candidates for k in 1:6)
    r["position_balanced"] || error("unbalanced profile positions")
    r["analytical_expected"]=expected
    r["analytical_admission"]=all(get(t,"accepted",false) && isapprox(t["objective"],expected.source_W;atol=1e-4,rtol=0.)
        for p in r["profiles"] for t in [p["warmup"];p["trials"]])
    r["analytical_admission"] || (r["ranking"]["fastest_ipopt"]=nothing)
    open(io->JSON3.write(io,r),output,"w")
    r
end
end
