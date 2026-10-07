"""Selective observation lifting after certified zero-load elimination.

Supply a declared external DER scenario, as saved by the external-observation
screen. This harness does not change its loads, bounds or objective data. It
compares all five existing observation choices under each ordinary-transformer
current representation. Single preflight timings are diagnostic, never ranked.
"""
module IVRZeroLoadObservationStudy
using FormulationLab, JSON3, SHA, LinearAlgebra
include("benchmark_ivr_zero_loads.jl")
const Z=IVRZeroLoadStudy
const E=Z.E
const P=E.P
clone(o;kwargs...)=IVRNLPOptions(;merge((; (k=>deepcopy(getfield(o,k)) for k in fieldnames(IVRNLPOptions))...), (;kwargs...))...)
function profiles(net,workload,mode;exchange_target_W)
    mode in (:off,:transformer_currents) || throw(ArgumentError("unknown ordinary-transformer current representation"))
    base=only(p.options for p in Z.profiles(net,workload;exchange_target_W)
        if p.options.device_elimination==mode && p.options.zero_load_elimination)
    [(;name="powers",options=base);
     [(;name=string(selection),options=clone(base;lifting=:bounded_observations,observation_selection=selection))
      for selection in (:coil_voltages,:coil_currents,:coils,:all)]]
end

"""Ten Williams sweeps balance positions and within-sweep predecessors twice.

Confirmation reverses the predeclared sweep order. Between-sweep transitions
are not balanced. A separate fresh-process and isolation protocol is required.
"""
function orders(batch)
    batch in ("exploration","confirmation") || throw(ArgumentError("unknown batch"))
    block=[[mod1(i+k,5) for i in (1,2,5,3,4)] for k in 0:4]
    result=vcat(block,reverse.(block))
    batch=="confirmation" ? reverse(result) : result
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
        anchor=nothing
        for mode in (:off,:transformer_currents)
            ps=profiles(net,workload,mode;exchange_target_W=target)
            reference=build_opf(net,IVRNLP(;objective=:power,power_terms=first(ps).options.power_terms,transformer_nameplate=:bmopftools))
            for p in ps
                stem="$(workload)__$(mode)__$(p.name)";report["pending_trial"]=stem;E.save(path,report)
                row,point=E.preflight_trial(net,p,reference,anchor,start,joinpath(folder,stem))
                row["workload"]=string(workload);row["device_elimination"]=string(mode)
                anchor===nothing && row["accepted"] && (anchor=point)
                push!(report["trials"],row);report["pending_trial"]=nothing;E.save(path,report)
                println(stem," accepted=",row["accepted"]," ",get(row,"error",get(row,"status","")));flush(stdout)
            end
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
    IVRZeroLoadObservationStudy.run(ARGS...)
end
