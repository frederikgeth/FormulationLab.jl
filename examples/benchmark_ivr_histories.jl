# Synthetic operation histories, independent of external data and saved drivers.
module IVRHistoryStudy
using JSON3, SHA
include("benchmark_ivr_reuse.jl")
const R=IVRReuseStudy
const SOURCE_SHA=bytes2hex(sha256(read(@__FILE__)))

"""Manufactured single-phase/delta dispatch with six distinct operating points.

`:fixed_boxes` and `:changing_boxes` share demand and price paths, but define
different feasible sets. Compare initialization policies within each history;
do not require objectives to agree between the two histories.
"""
function history_case(;conductors=2,segments=100,history=:fixed_boxes)
    conductors in (2,3) || throw(ArgumentError("two-wire or three-wire delta required"))
    segments>=2 && iseven(segments) || throw(ArgumentError("positive even segment count required"))
    history in (:fixed_boxes,:changing_boxes) || throw(ArgumentError("unknown history"))
    net=R.P.ivr_compiler_case(;conductors,segments)
    for k in 1:2:segments;delete!(net["load"],"d$k");end
    tm=conductors==2 ? ["a","n"] : ["a","b","c"]
    pcap=conductors==2 ? [600.] : [500.,150.,50.]
    qcap=conductors==2 ? [80.] : [70.,30.,15.]
    n=length(pcap)
    net["generator"]=Dict("der"=>Dict("bus"=>"b$segments","terminal_map"=>tm,
        "configuration"=>conductors==2 ? "SINGLE_PHASE" : "DELTA",
        "p_min"=>zeros(n),"p_max"=>copy(pcap),"q_min"=>-qcap,"q_max"=>copy(qcap),
        "s_max"=>fill(2000.,n),"i_max"=>fill(200.,conductors),"cost"=>fill(.2,n)))
    # Absolute factors refer to the input demand, never the preceding scenario.
    path=[(label="initial",p=1.,q=1.,price=.2,a=1.,lo=-1.,hi=1.),
          (label="lower_P_higher_Q",p=.92,q=1.1,price=.35,a=.75,lo=-1.,hi=.4),
          (label="higher_P_lower_Q",p=1.06,q=.85,price=1.6,a=.5,lo=0.,hi=0.),
          (label="lowest_demand",p=.88,q=.7,price=1.8,a=0.,lo=-1.,hi=.8),
          (label="highest_demand",p=1.12,q=1.25,price=.25,a=.9,lo=nothing,hi=1.),
          (label="moderate_demand",p=1.02,q=.95,price=1.2,a=1.,lo=-1.,hi=1.)]
    schedule=map(path) do step
        limits=history==:changing_boxes ? step : (;a=1.,lo=-1.,hi=1.)
        (label=step.label,
         loads=Dict(id=>(p=step.p*d["p_nom"],q=step.q*d["q_nom"]) for (id,d) in net["load"]),
         generators=Dict("der"=>(cost=fill(step.price,n),p_max=limits.a*pcap,
             q_min=limits.lo===nothing ? nothing : limits.lo*qcap,q_max=limits.hi*qcap)))
    end
    net,schedule
end

"""Run a history study with explicit provenance; default twelve sweeps balance six workflows."""
function benchmark(output;conductors=2,segments=100,history=:fixed_boxes,repetitions=12,
                   candidates=R.dual_workflows())
    net,schedule=history_case(;conductors,segments,history)
    n=length(candidates);orders=R.workflow_orders(n,repetitions)
    position_balanced=all(count(o->o[k]==j,orders)==repetitions/n for j in 1:n for k in 1:n)
    metadata=(;conductors,segments,history,repetitions,position_balanced,history_source_sha256=SOURCE_SHA,
        note="Manufactured CP dispatch, no consecutive repeated operating points. Absolute demand factors; fixed equipment and source accounting. Compare policies within one history, not objectives across different feasible sets. No automatic defaults or fallback retries.")
    open(io->JSON3.write(io,metadata),output*".manifest.json","w")
    result=R.benchmark(net,schedule,output;repetitions,candidates,
        solver_options=merge(R.SETTINGS,(obj_scaling_factor=1000.,)))
    result["history_input"]=metadata
    open(io->JSON3.write(io,result),output,"w")
    result
end
end
