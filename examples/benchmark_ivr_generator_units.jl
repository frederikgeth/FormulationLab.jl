"""Isolate generator dispatch units while holding circuit and lifted-power units fixed."""
module IVRGeneratorUnitStudy
using FormulationLab, JSON3, SHA, Random
include("benchmark_ivr_base_formulations.jl")
const F=IVRBaseFormulationStudy
const E=F.E
const P=E.P

function profiles(net,workload;exchange_target_W=nothing,nlp_scaling_method="none")
    controls=filter(p->p.factors.s_base==1e4 && p.factors.lifting==:off,
        F.profiles(net,workload;exchange_target_W,nlp_scaling_method))
    [(;name="$(p.factors.reduced ? "reduced" : "full")_dispatch_$(Int(gb/1000))k",
        factors=(;generator_base=gb,reduced=p.factors.reduced),
        options=IVRNLPOptions(; (k=>(k==:generator_power_bases ?
            Dict(id=>gb for id in keys(net["generator"])) : deepcopy(getfield(p.options,k)))
            for k in fieldnames(IVRNLPOptions))...),solver_options=p.solver_options)
        for gb in (1e3,1e4,1e5) for p in controls]
end


function benchmark(path,output;workload=:quadratic_cost,exchange_target_W=nothing,
                   nlp_scaling_method="none",blocks=2,seed=20261006)
    canonical(p)=ispath(p) ? realpath(p) : abspath(p)
    any(p->canonical(p)==canonical(path),(output,output*".input.json",output*".manifest.json")) &&
        throw(ArgumentError("output and sidecars must not overwrite the source"))
    digest=bytes2hex(sha256(read(path)))
    net,detached=P.compiler_feeder_input(path;detach_legacy_provenance=true)
    before=bytes2hex(sha256(JSON3.write(net)))
    candidates=profiles(net,workload;exchange_target_W,nlp_scaling_method)
    trial_orders=F.orders(length(candidates);blocks,seed)
    manifest=(;source_path=abspath(path),source_sha256=digest,network_sha256=before,
        runner_sha256=bytes2hex(sha256(read(@__FILE__))),workload,exchange_target_W,
        detached_provenance_paths=detached,electrical_changes=Any[],legacy_prices_used=false,
        power_terms=first(candidates).options.power_terms,objective_scale=1.,
        note="Unchanged supplied physical input, declared economic/tracking objective. If input is a derived scenario, retain its original-source/addition manifest separately. Raw dictionary boundary, not schema validation.")
    save(p,x)=open(io->JSON3.write(io,x),p,"w")
    save(output*".input.json",net);save(output*".manifest.json",manifest)
    start=E.S.U.G.H.S.L.start_point(net)
    report=P.benchmark(net,output;repetitions=length(trial_orders),candidates,initial_point=start,
        trial_orders,source_sha256=digest)
    report["feeder_input"]=manifest
    report["factors"]=Dict(p.name=>p.factors for p in candidates)
    report["order_design"]=(;kind="randomized_cyclic_blocks",blocks,seed,
        note="Each candidate occupies each position once per block; not predecessor-balanced.")
    report["position_balanced"]=all(count(o->o[k]==p.name,report["orders"])==blocks for p in candidates for k in eachindex(candidates))
    report["source_unchanged"]=bytes2hex(sha256(read(path)))==digest
    report["network_unchanged"]=bytes2hex(sha256(JSON3.write(net)))==before
    report["global_optimum_certified"]=false
    save(output,report)
    report["source_unchanged"] && report["network_unchanged"] && report["position_balanced"] || error("input or ordering audit failed")
    report
end
end
