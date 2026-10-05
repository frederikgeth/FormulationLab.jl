"""Explicit economic/dispatch workloads on external BMOPF dictionaries.

No dataset is bundled. Physical fields and existing limits are retained; the
objective is an explicitly declared experiment, not an interpretation of legacy
prices. This runner requires bounded generator dispatch and does not add DERs.
"""
module IVRExternalObjectiveStudy
using FormulationLab, JSON3, SHA
include("benchmark_ivr_power_objectives.jl")
const S=IVRPowerObjectiveStudy
const P=S.P

function channels(net)
    isempty(get(net,"ibr",Dict())) || throw(ArgumentError("this panel requires explicit IBR objective design"))
    generators=get(net,"generator",Dict())
    isempty(generators) && throw(ArgumentError("bounded generators required; fixed-load feasibility is not dispatch evidence"))
    for (id,d) in generators
        all(k->haskey(d,k), ("p_min","p_max","q_min","q_max")) || throw(ArgumentError("generator/$id needs explicit P/Q boxes"))
        n=length(d["p_max"])
        n>0 && all(k->length(d[k])==n && all(isfinite,d[k]),("p_min","p_max","q_min","q_max")) ||
            throw(ArgumentError("generator/$id needs finite equally sized P/Q boxes"))
        all(d["p_min"].<=d["p_max"]) && all(d["q_min"].<=d["q_max"]) || throw(ArgumentError("inverted generator box"))
    end
    any(any(d["p_min"].<d["p_max"]) for d in values(generators)) || throw(ArgumentError("active dispatch freedom required"))
    sources=[(:voltage_source,id,k) for id in sort!(collect(keys(get(net,"voltage_source",Dict()))))
        for k in eachindex(net["voltage_source"][id]["terminal_map"])]
    isempty(sources) && throw(ArgumentError("voltage-source exchange required"))
    gens=[(:generator,id,k) for id in sort!(collect(keys(generators))) for k in eachindex(generators[id]["p_max"])]
    sources,gens
end

"""Declared benchmark coefficients in W/var; legacy price fields are unused.

Quadratic cost: 0.25 currency/kWh source exchange, 0.10 currency/kWh generator
P, 0.02 currency/(kW² h) generator P² and 0.002 currency/(kvar² h) generator Q².
Exchange: squared source P target error and source Q, plus 0.01 times squared
generator deviations from P-box midpoints and Q=0, all in kW/kvar units.
"""
function terms(net,workload;exchange_target_W=nothing)
    workload in (:quadratic_cost,:exchange_tracking) || throw(ArgumentError("unknown external power workload"))
    sources,gens=channels(net)
    if workload==:quadratic_cost
        return [IVRPowerTerm(channels=sources,linear=.25/1000);
            [IVRPowerTerm(channels=[c],linear=.10/1000,quadratic=.02/1e6) for c in gens];
            [IVRPowerTerm(channels=[c],quantity=:q,quadratic=.002/1e6) for c in gens]]
    end
    exchange_target_W isa Real && isfinite(exchange_target_W) || throw(ArgumentError("finite explicit exchange_target_W required"))
    [IVRPowerTerm(channels=sources,target=exchange_target_W,quadratic=1e-6);
     IVRPowerTerm(channels=sources,quantity=:q,quadratic=1e-6);
     [IVRPowerTerm(channels=[c];quantity,
        target=quantity==:p ? (net["generator"][c[2]]["p_min"][c[3]]+net["generator"][c[2]]["p_max"][c[3]])/2 : 0.,
        quadratic=1e-8) for c in gens for quantity in (:p,:q)]]
end

function profiles(net,workload;regional_bases,exchange_target_W=nothing,nlp_scaling_method="none")
    nlp_scaling_method in ("none","gradient-based") || throw(ArgumentError("unknown solver scaling policy"))
    !isempty(regional_bases) && all(k->haskey(net["bus"],k),keys(regional_bases)) &&
        all(v->v isa Real && isfinite(v) && v>0,values(regional_bases)) || throw(ArgumentError("explicit positive regional bases on known buses required"))
    power_terms=terms(net,workload;exchange_target_W)
    specs=[("full_10k",1e4,false,false,:off),("reduced_10k",1e4,false,true,:off),
        ("reduced_10k_powers",1e4,false,true,:powers),("reduced_10k_observations",1e4,false,true,:bounded_observations),
        ("reduced_1k_powers",1e3,false,true,:powers),("reduced_regional_observations",1e4,true,true,:bounded_observations)]
    [(;name,options=IVRNLPOptions(;objective=:power,power_terms=deepcopy(power_terms),objective_scale=1.,s_base=sb,
        current_power_bases=regional ? deepcopy(regional_bases) : Dict{String,Float64}(),
        transformer_scaling=:nominal,row_scaling=:composed,ground_scaling=:voltage,
        specialization=reduced ? :conductor_regions : :off,
        linear_elimination=reduced ? :passive_blocks : :off,
        device_elimination=reduced ? :transformer_currents : :off,lifting,
        observation_sharing=reduced ? :exact : :off),
        solver_options=(linear_solver="mumps",mumps_pivot_order=0,nlp_scaling_method))
        for (name,sb,regional,reduced,lifting) in specs]
end

function benchmark(path,output;workload=:quadratic_cost,regional_bases,exchange_target_W=nothing,
                   nlp_scaling_method="none",repetitions=12)
    repetitions>0 && repetitions%12==0 || throw(ArgumentError("twelve-sweep multiples balance six profiles"))
    canonical(p)=ispath(p) ? realpath(p) : abspath(p)
    any(p->canonical(p)==canonical(path),(output,output*".input.json",output*".manifest.json")) &&
        throw(ArgumentError("output and sidecars must not overwrite the source"))
    digest=bytes2hex(sha256(read(path)))
    net,detached=P.compiler_feeder_input(path;detach_legacy_provenance=true)
    before=bytes2hex(sha256(JSON3.write(net)))
    candidates=profiles(net,workload;regional_bases,exchange_target_W,nlp_scaling_method)
    manifest=Dict("source_path"=>abspath(path),"source_sha256"=>digest,"network_sha256"=>before,
        "detached_provenance_paths"=>detached,"original_accounting"=>P.feeder_accounting(net),
        "electrical_changes"=>[],"workload"=>workload,"exchange_target_W"=>exchange_target_W,
        "regional_bases"=>deepcopy(regional_bases),"power_terms"=>deepcopy(first(candidates).options.power_terms),
        "objective_scale"=>1.,"legacy_prices_used"=>false,"buses"=>length(net["bus"]),
        "note"=>"Declared experimental objective, unchanged physical fields/limits. Known provenance relocated on an owned copy. Inherited preprocessing is not reversed. Raw dictionary boundary, not schema validation. No global AC certificate.")
    save(p,x)=open(io->JSON3.write(io,x),p,"w")
    save(output*".input.json",net);save(output*".manifest.json",manifest)
    start=S.U.G.H.S.L.start_point(net)
    report=P.benchmark(net,output;repetitions,candidates,initial_point=start,source_sha256=digest)
    report["feeder_input"]=manifest
    report["source_unchanged"]=bytes2hex(sha256(read(path)))==digest
    report["network_unchanged"]=bytes2hex(sha256(JSON3.write(net)))==before
    report["global_optimum_certified"]=false
    report["position_balanced"]=all(count(o->o[k]==p.name,report["orders"])==repetitions/6 for p in candidates for k in 1:6)
    save(output,report)
    report["source_unchanged"] && report["network_unchanged"] && report["position_balanced"] || error("input or ordering audit failed")
    report
end
end
