"""Matched assembly-base, reduction-bundle and power-lifting comparisons."""
module IVRBaseFormulationStudy
using FormulationLab, JSON3, SHA, Random
include("benchmark_ivr_external_objectives.jl")
const E=IVRExternalObjectiveStudy
const P=E.P

function profiles(net,workload;exchange_target_W=nothing,nlp_scaling_method="none")
    nlp_scaling_method in ("none","gradient-based") || throw(ArgumentError("unknown solver scaling policy"))
    power_terms=E.terms(net,workload;exchange_target_W)
    [(;name="$(reduced ? "reduced" : "full")_$(Int(sb/1000))k_$(lifting)",
        factors=(;s_base=sb,reduced,lifting),
        options=IVRNLPOptions(;objective=:power,power_terms=deepcopy(power_terms),objective_scale=1.,s_base=sb,
            transformer_scaling=:nominal,row_scaling=:composed,ground_scaling=:voltage,
            specialization=reduced ? :conductor_regions : :off,
            linear_elimination=reduced ? :passive_blocks : :off,
            device_elimination=reduced ? :transformer_currents : :off,
            lifting,observation_sharing=:exact),
        solver_options=(linear_solver="mumps",mumps_pivot_order=0,nlp_scaling_method))
        for sb in (1e3,1e4,1e5) for reduced in (false,true) for lifting in (:off,:powers)]
end

"""Randomized cyclic blocks: every candidate occupies every position once.

Randomize candidate labels and sweep order within each complete cyclic block.
This balances positions, not all possible predecessor pairs. Save realized
orders; seeded RNG output need not be identical across Julia versions.
"""
function orders(n;blocks=1,seed=20261006)
    n isa Integer && !(n isa Bool) && n>=1 && blocks isa Integer && !(blocks isa Bool) && blocks>=1 ||
        throw(ArgumentError("positive integer candidate and block counts required"))
    rng=MersenneTwister(seed);result=Vector{Int}[]
    for _ in 1:blocks
        labels=randperm(rng,n)
        append!(result,shuffle!(rng,[circshift(labels,k) for k in 0:n-1]))
    end
    result
end

function benchmark(path,output;workload=:quadratic_cost,exchange_target_W=nothing,
                   nlp_scaling_method="none",blocks=1,seed=20261006)
    canonical(p)=ispath(p) ? realpath(p) : abspath(p)
    any(p->canonical(p)==canonical(path),(output,output*".input.json",output*".manifest.json")) &&
        throw(ArgumentError("output and sidecars must not overwrite the source"))
    digest=bytes2hex(sha256(read(path)))
    net,detached=P.compiler_feeder_input(path;detach_legacy_provenance=true)
    before=bytes2hex(sha256(JSON3.write(net)))
    candidates=profiles(net,workload;exchange_target_W,nlp_scaling_method)
    trial_orders=orders(length(candidates);blocks,seed)
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
