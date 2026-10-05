"""Bounded passive components, with full and unrestricted-block controls."""
module IVRHybridStudy
using FormulationLab
include("benchmark_ivr_power_finalists.jl")
const F=IVRPowerFinalistStudy
const E=F.E
const P=F.P

"""Fixed total series impedance, charging and CP demand as segmentation changes.

Terminal or alternating loads; a bounded terminal DER gives genuine power-based
cost/tracking workloads. Charging and reversed/permuted ports define explicit
manufactured circuits, not equivalent preprocessing of another supplied input.
"""
function case(;conductors=2,segments=12,loads=:terminal,charged=false,alternate=false)
    conductors in (2,3,4) || throw(ArgumentError("two, three or four conductors required"))
    segments>=2 && iseven(segments) || throw(ArgumentError("positive even segment count required"))
    loads in (:terminal,:alternating) || throw(ArgumentError("unknown load placement"))
    net=P.ivr_compiler_case(;conductors,segments)
    keep=loads==:terminal ? [segments] : collect(2:2:segments)
    for k in 1:segments
        d=net["load"]["d$k"]
        if k in keep
            d["p_nom"] .*= segments/length(keep);d["q_nom"] .*= segments/length(keep)
        else
            delete!(net["load"],"d$k")
        end
        line=net["line"]["l$k"];line["length"]=1/segments
        line["s_max"]=fill(1e5,conductors==2 ? 1 : 3)
        if alternate && isodd(k)
            line["bus_from"],line["bus_to"]=line["bus_to"],line["bus_from"]
            line["terminal_map_from"],line["terminal_map_to"]=line["terminal_map_to"],line["terminal_map_from"]
        end
    end
    if alternate && conductors>=3
        tm=net["line"]["l2"]["terminal_map_from"];tm[1],tm[2]=tm[2],tm[1]
    end
    if charged
        code=net["linecode"]["wire"]
        for j in 1:conductors
            code["B_from_$(j)_$(j)"]=1e-4*j;code["B_to_$(j)_$(j)"]=2e-4*j
            code["G_from_$(j)_$(j)"]=1e-6*j
        end
    end
    demand=sum(d["p_nom"] for d in values(net["load"]))
    template=net["load"]["d$segments"];n=length(demand);pmax=1.5demand
    net["generator"]=Dict("der"=>Dict("bus"=>"b$segments","terminal_map"=>copy(template["terminal_map"]),
        "configuration"=>template["configuration"],"p_min"=>zeros(n),"p_max"=>pmax,
        "q_min"=>-.5pmax,"q_max"=>.5pmax,"s_max"=>copy(pmax)))
    net
end

function profiles(net,workload;exchange_target_W=nothing,nlp_scaling_method="none")
    prior=F.profiles(net,workload;exchange_target_W,nlp_scaling_method)
    base=only(p for p in prior if p.name=="reduced_lifts_1k")
    specs=[("full",:off,4,false),("blocks",:passive_blocks,4,true),
        ("nonadjacent",:passive,4,true),[("hybrid_$k",:passive_hybrid,k,true) for k in (1,2,4,8)]...]
    [begin
        changes=(;linear_elimination=mode,passive_component_limit=cap,
            specialization=reduced ? :conductor_regions : :off,
            device_elimination=reduced ? :transformer_currents : :off)
        options=IVRNLPOptions(; (k=>deepcopy(get(changes,k,getfield(base.options,k))) for k in fieldnames(IVRNLPOptions))...)
        (;name,options,solver_options=base.solver_options,
            factors=merge(base.factors,(;reduced,linear_elimination=mode,passive_component_limit=cap)))
    end for (name,mode,cap,reduced) in specs]
end
benchmark(path,output;kwargs...) = F.benchmark_profiles(path,output,profiles,@__FILE__;kwargs...)
end
