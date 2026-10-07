"""Certified zero-load current elimination on an explicitly supplied DER scenario.

Use the INPUT.json saved by the external-observation preflight, not an implicit
modification of the original feeder. All physical inputs and power terms are
shared. This screen emits canonical SI results and does not rank timings.
"""
module IVRZeroLoadStudy
using FormulationLab, JSON3, SHA, LinearAlgebra
include("benchmark_ivr_external_observations.jl")
const E=IVRExternalObservationStudy
const P=E.P
clone(o,enabled)=IVRNLPOptions(;(k=>(k==:zero_load_elimination ? enabled : deepcopy(getfield(o,k))) for k in fieldnames(IVRNLPOptions))...)
function profiles(net,workload;exchange_target_W,include_broad=false)
    [(;name="$(p.name)__zero_$(enabled)",options=clone(p.options,enabled))
        for p in E.profiles(net,workload;exchange_target_W) if include_broad || p.options.lifting==:powers
        for enabled in (false,true)]
end
function run(input,folder)
    isdir(folder) && !isempty(readdir(folder)) && throw(ArgumentError("use a new empty evidence folder"))
    mkpath(folder);BLAS.set_num_threads(1)
    net=JSON3.read(read(input,String),Dict{String,Any});digest=bytes2hex(sha256(JSON3.write(net)))
    target=.35sum(sum(d["p_nom"]) for d in values(net["load"]))
    report=Dict{String,Any}("input"=>abspath(input),"source_sha256"=>bytes2hex(sha256(read(input))),
        "network_sha256"=>digest,"exchange_target_W"=>target,"trials"=>Any[],"timing_eligible"=>false,"ranking"=>nothing)
    path=joinpath(folder,"REPORT.json");E.save(path,report);start=E.start_point(net)
    for workload in (:quadratic_cost,:exchange_tracking)
        ps=profiles(net,workload;exchange_target_W=target,include_broad=true)
        reference=build_opf(net,IVRNLP(;objective=:power,power_terms=first(ps).options.power_terms,transformer_nameplate=:bmopftools))
        anchor=nothing
        for p in ps
            stem="$(workload)__$(p.name)";report["pending_trial"]=stem;E.save(path,report)
            row,point=E.preflight_trial(net,p,reference,anchor,start,joinpath(folder,stem))
            row["workload"]=string(workload)
            anchor===nothing && row["accepted"] && (anchor=point)
            push!(report["trials"],row);report["pending_trial"]=nothing;E.save(path,report)
            println(stem," accepted=",row["accepted"]," ",get(row,"error",get(row,"status","")));flush(stdout)
        end
    end
    report["network_unchanged"]=digest==bytes2hex(sha256(JSON3.write(net)))
    report["source_unchanged"]=report["source_sha256"]==bytes2hex(sha256(read(input)))
    report["all_trials_accepted"]=all(t["accepted"] for t in report["trials"])
    report["objectives_comparable"]=all((:quadratic_cost,:exchange_tracking)) do workload
        rows=filter(t->t["workload"]==string(workload),report["trials"])
        all(t->t["accepted"] && isapprox(t["objective"],first(rows)["objective"];atol=1e-6,rtol=1e-8),rows)
    end
    E.save(path,report);report
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("usage: declared-scenario.json new-output-folder")
    IVRZeroLoadStudy.run(ARGS...)
end
