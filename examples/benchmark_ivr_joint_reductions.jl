"""Joint zero-load × observation-lifting × ordinary-current experiment.

The eight existing formulations share inputs, power objective, starts and units.
Preflight with IVRZeroLoadStudy.run first. Timing output remains provisional until
an external process-isolation, completeness and physical admission audit passes.
"""
module IVRJointReductionStudy
using FormulationLab, JSON3, SHA, LinearAlgebra
include("benchmark_ivr_zero_loads.jl")
const Z=IVRZeroLoadStudy
const E=Z.E
const P=Z.P
arm(mode,lifting,zero)="$(mode)__$(lifting)__zero_$(zero)"
arms()=[arm(m,l,z) for m in (:off,:transformer_currents)
    for l in (:powers,:bounded_observations) for z in (false,true)]
profiles(net;exchange_target_W)=Z.profiles(net,:exchange_tracking;exchange_target_W,include_broad=true)

"""Sixteen eight-arm sweeps; positions and within-sweep predecessors occur twice.

The second half reverses each first-half sweep. Confirmation reverses the full
schedule. Between-sweep transitions are not balanced. No outcome-dependent order.
"""
function orders(batch)
    batch in ("exploration","confirmation") || throw(ArgumentError("unknown batch"))
    block=[[mod1(i+k,8) for i in (1,2,8,3,7,4,6,5)] for k in 0:7]
    result=vcat(block,reverse.(block))
    batch=="confirmation" ? reverse(result) : result
end

"""Multiplicative matched contrasts of eight positive finite wall times.

`zero_lifting_interaction[m]` divides broad/powers with zero-load elimination by
broad/powers without it, holding the ordinary-current mode fixed. Below one means
zero-load elimination strengthens the relative broad-lifting benefit. The
three-way contrast divides this interaction with ordinary currents eliminated by
the interaction with them explicit. Descriptive contrasts are not significance
tests or a factorization/conditioning explanation.
"""
function contrasts(times)
    Set(keys(times))==Set(arms()) || throw(ArgumentError("exactly the eight declared arms are required"))
    all(x->x isa Real && isfinite(x) && x>0,values(times)) ||
        throw(ArgumentError("wall times must be positive and finite"))
    t(m,l,z)=log(times[arm(m,l,z)])
    zero=Dict("$(m)__$(l)"=>exp(t(m,l,true)-t(m,l,false))
        for m in (:off,:transformer_currents) for l in (:powers,:bounded_observations))
    lifting=Dict("$(m)__zero_$(z)"=>exp(t(m,:bounded_observations,z)-t(m,:powers,z))
        for m in (:off,:transformer_currents) for z in (false,true))
    current=Dict("$(l)__zero_$(z)"=>exp(t(:transformer_currents,l,z)-t(:off,l,z))
        for l in (:powers,:bounded_observations) for z in (false,true))
    interaction(m)=t(m,:bounded_observations,true)-t(m,:powers,true)-
        t(m,:bounded_observations,false)+t(m,:powers,false)
    (;zero_over_retained=zero,broad_over_powers=lifting,eliminated_over_explicit=current,
        zero_lifting_interaction=Dict(string(m)=>exp(interaction(m)) for m in (:off,:transformer_currents)),
        three_way_interaction=exp(interaction(:transformer_currents)-interaction(:off)))
end

include("ivr_joint_preflight.jl")

function run_timing(preflight_folder,folder,batch)
    schedule=orders(batch)
    isdir(folder) && !isempty(readdir(folder)) && throw(ArgumentError("use a new empty timing folder"))
    validation=validate_preflight(preflight_folder)
    pre=JSON3.read(read(joinpath(preflight_folder,"REPORT.json"),String),Dict{String,Any})
    net=JSON3.read(read(pre["input"],String),Dict{String,Any})
    bytes2hex(sha256(JSON3.write(net)))==pre["network_sha256"] || throw(ArgumentError("network digest differs from preflight"))
    ps=profiles(net;exchange_target_W=pre["exchange_target_W"])
    [p.name for p in ps]==arms() || error("unexpected factorial arm order")
    mkpath(folder);BLAS.set_num_threads(1)
    E.save(joinpath(folder,"PREFLIGHT_VALIDATION.json"),validation)
    E.save(joinpath(folder,"STATE.json"),(;batch,status="started",timing_eligible=false))
    path=joinpath(folder,"REPORT.json")
    r=P.benchmark(net,path;repetitions=length(schedule),candidates=ps,solver_options=E.SETTINGS,
        initial_point=E.start_point(net),trial_orders=schedule,checkpoint=:trial,source_sha256=pre["source_sha256"])
    r["batch"]=batch;r["timing_eligible"]=false
    r["admission_note"]="Within-block factorial; local ranking is provisional pending whole-campaign admission."
    r["input_unchanged"]=bytes2hex(sha256(read(pre["input"])))==pre["source_sha256"]
    r["network_unchanged"]=bytes2hex(sha256(JSON3.write(net)))==pre["network_sha256"]
    E.save(path,r)
    E.save(joinpath(folder,"STATE.json"),(;batch,status="completed",timing_eligible=false))
    r
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==3 || error("usage: accepted-preflight-folder new-timing-folder exploration|confirmation")
    IVRJointReductionStudy.run_timing(ARGS...)
end
