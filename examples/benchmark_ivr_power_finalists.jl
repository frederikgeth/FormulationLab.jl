"""Matched numerical finalists, isolated lifted-power units and generator reuse."""
module IVRPowerFinalistStudy
using FormulationLab, JSON3, SHA, Random
include("benchmark_ivr_base_formulations.jl")
const F=IVRBaseFormulationStudy
const E=F.E
const P=E.P

function profiles(net,workload;exchange_target_W=nothing,nlp_scaling_method="none")
    nlp_scaling_method in ("none","gradient-based") || throw(ArgumentError("unknown solver scaling policy"))
    terms=E.terms(net,workload;exchange_target_W)
    # The first five arms compare previous finalists. Three further arms change
    # only lifted-power units; the last changes only generator-definition reuse.
    specs=[("full_10k",1e4,false,1e4,:off,1e4,:off),
        ("full_1k",1e3,false,1e3,:off,1e3,:off),
        ("reduced_10k",1e4,true,1e4,:off,1e4,:off),
        ("reduced_1k",1e3,true,1e3,:off,1e3,:off),
        ("reduced_dispatch_100k",1e4,true,1e5,:off,1e4,:off),
        ("reduced_lifts_1k",1e4,true,1e4,:powers,1e3,:off),
        ("reduced_lifts_10k",1e4,true,1e4,:powers,1e4,:off),
        ("reduced_lifts_100k",1e4,true,1e4,:powers,1e5,:off),
        ("reduced_reuse",1e4,true,1e4,:powers,1e4,:generators)]
    profiles=[(;name,factors=(;s_base=sb,reduced,generator_base=gb,lifting,lifted_power_base=lb,power_sharing=sharing,linear_elimination=reduced ? :passive_blocks : :off),
        options=IVRNLPOptions(;objective=:power,power_terms=deepcopy(terms),objective_scale=1.,s_base=sb,
            generator_power_bases=Dict(id=>gb for id in keys(net["generator"])),
            lifted_power_base=lb,power_sharing=sharing,lifting,
            transformer_scaling=:nominal,row_scaling=:composed,ground_scaling=:voltage,
            specialization=reduced ? :conductor_regions : :off,
            linear_elimination=reduced ? :passive_blocks : :off,
            device_elimination=reduced ? :transformer_currents : :off,observation_sharing=:exact),
        solver_options=(linear_solver="mumps",mumps_pivot_order=0,nlp_scaling_method))
        for (name,sb,reduced,gb,lifting,lb,sharing) in specs]
    base=only(p for p in profiles if p.name=="reduced_10k")
    push!(profiles,(;name="reduced_nonadjacent",factors=merge(base.factors,(;linear_elimination=:passive)),
        options=IVRNLPOptions(; (k=>(k==:linear_elimination ? :passive : deepcopy(getfield(base.options,k)))
            for k in fieldnames(IVRNLPOptions))...),solver_options=base.solver_options))
    profiles
end


benchmark(path,output;kwargs...) = benchmark_profiles(path,output,profiles,@__FILE__;kwargs...)

# Shared source-safe protocol; the caller supplies its own candidate design and provenance.
function benchmark_profiles(path,output,profile_builder,runner_path;workload=:quadratic_cost,exchange_target_W=nothing,
                   nlp_scaling_method="none",blocks=1,seed=20261006)
    canonical(p)=ispath(p) ? realpath(p) : abspath(p)
    any(p->canonical(p)==canonical(path),(output,output*".input.json",output*".manifest.json")) &&
        throw(ArgumentError("output and sidecars must not overwrite the source"))
    digest=bytes2hex(sha256(read(path)))
    net,detached=P.compiler_feeder_input(path;detach_legacy_provenance=true)
    before=bytes2hex(sha256(JSON3.write(net)))
    candidates=profile_builder(net,workload;exchange_target_W,nlp_scaling_method)
    trial_orders=F.orders(length(candidates);blocks,seed)
    manifest=(;source_path=abspath(path),source_sha256=digest,network_sha256=before,
        runner_sha256=bytes2hex(sha256(read(runner_path))),workload,exchange_target_W,
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
