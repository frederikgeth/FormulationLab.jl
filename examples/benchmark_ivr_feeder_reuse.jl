# julia --project=test examples/benchmark_ivr_feeder_reuse.jl input.json output.json
# External feeder data are read only; demand scenarios are explicit experiments.
module IVRFeederReuseStudy
using JSON3, SHA, LinearAlgebra
include("benchmark_ivr_reuse.jl")
const R=IVRReuseStudy
const RUNNER_SHA=bytes2hex(sha256(read(@__FILE__)))

"""Reused full/regional models crossed with fixed/previous-primal starts."""
reused_workflows()=filter(w->w.reuse,R.workflows(profiles=R.P.profiles(objective=:feasibility)[[1,10]]))

"""Absolute constant-power demand scenarios; all other loads remain unchanged."""
function demand_schedule(net;factors=(1.,1.,.9,1.),labels=("base","repeat","lower_demand","restore"))
    length(factors)==length(labels)>0 || throw(ArgumentError("one label per nonempty factor sequence required"))
    all(f->f isa Real && !(f isa Bool) && isfinite(f) && f>=0,factors) ||
        throw(ArgumentError("demand factors must be finite nonnegative numbers"))
    allunique(labels) || throw(ArgumentError("distinct scenario labels required"))
    loads=get(net,"load",Dict())
    ids=sort!([id for (id,d) in loads if lowercase(get(d,"model","constant_power"))=="constant_power"])
    isempty(ids) && throw(ArgumentError("no constant-power loads to update"))
    [(;label,loads=Dict(id=>(p=factor*loads[id]["p_nom"],q=factor*loads[id]["q_nom"]) for id in ids),
        generators=Dict{String,Any}()) for (label,factor) in zip(labels,factors)]
end

"""Feasibility-only feeder transfer, with source and scenario provenance.

Save an input manifest before solving, so interrupted runs retain provenance.
No source/equipment bound or accounting changes are made. Only declared CP
loads vary. The default four workflows use eight balanced reversed/rotated
sweeps; other candidate counts require a separate order-balance check.
"""
function benchmark(path,output;repetitions=8,candidates=reused_workflows(),
                   factors=(1.,1.,.9,1.),labels=("base","repeat","lower_demand","restore"))
    abspath(path) in (abspath(output),abspath(output*".input.json")) &&
        throw(ArgumentError("output must not overwrite the input"))
    !isempty(candidates) && all(w->w.profile.options.objective==:feasibility,candidates) ||
        throw(ArgumentError("this feeder transfer requires a feasibility objective"))
    net,detached=R.P.compiler_feeder_input(path;detach_legacy_provenance=true)
    schedule=demand_schedule(net;factors,labels)
    selected=sort!(collect(keys(first(schedule).loads)))
    accounting=R.P.feeder_accounting(net)
    manifest=Dict("source_path"=>abspath(path),"source_sha256"=>bytes2hex(sha256(read(path))),
        "runner_sha256"=>RUNNER_SHA,"reuse_runner_sha256"=>R.RUNNER_SHA,
        "detached_provenance_paths"=>detached,"buses"=>length(net["bus"]),
        "updated_load_ids"=>selected,"unchanged_load_ids"=>sort!(setdiff(collect(keys(net["load"])),selected)),
        "factors"=>collect(factors),"labels"=>collect(labels),
        "accounting"=>Dict("colocated_sources_and_generators"=>accounting.colocated_sources_and_generators,
            "unpriced_sources"=>accounting.unpriced_sources,
            "note"=>"Feasibility objective; existing source/generator accounting retained, without economic-dispatch interpretation."),
        "note"=>"Explicit demand-change scenarios; source file, generator/source accounting, equipment and bounds unchanged. Known legacy provenance relocated on the owned copy. Feasibility only: no economic-dispatch or global-optimality claim.")
    open(io->JSON3.write(io,manifest),output*".input.json","w")
    report=R.benchmark(net,schedule,output;repetitions,candidates,source_sha256=manifest["source_sha256"])
    report["feeder_input"]=manifest
    open(io->JSON3.write(io,report),output,"w")
    report
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("Supply input JSON and output JSON paths")
    IVRFeederReuseStudy.BLAS.set_num_threads(1)
    IVRFeederReuseStudy.benchmark(ARGS[1],ARGS[2])
end
