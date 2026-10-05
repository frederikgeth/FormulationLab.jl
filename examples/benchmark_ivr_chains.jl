# Adjacent-chain experiment; existing profile lists and defaults are unchanged.
module IVRChainStudy
using FormulationLab, JuMP, JSON3, SHA, LinearAlgebra
include("benchmark_ivr_profiles.jl")
const P=IVRProfileStudy
const SOURCE_SHA=bytes2hex(sha256(read(@__FILE__)))

"""Unshunted chain with fixed total impedance and fixed total CP demand.

Every segment has length 1/segments. Terminal demand is 2000 W + 500 var for
single-phase, or [2000,750,250] W with Q=0.25P for delta. Alternating demand
splits the same total equally among even buses, a nonadjacent control.
All intermediate voltage and line current limits remain; every segment also
has a 100 kVA per-phase apparent-power rating at both ends.
"""
function chain_case(;conductors=2,segments=12,loads=:terminal)
    conductors in (2,3) || throw(ArgumentError("single-phase or delta required"))
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
        net["line"]["l$k"]["length"]=1/segments
        net["line"]["l$k"]["s_max"]=fill(1e5,conductors==2 ? 1 : 3)
    end
    net
end

function profiles()
    [(;name="$(specialization==:off ? "full" : "regional")_$(mode)",
       options=IVRNLPOptions(;objective=:source_import,specialization,
           linear_elimination=mode,ground_scaling=:voltage),
       solver_options=(linear_solver="mumps",mumps_pivot_order=0))
     for specialization in (:off,:conductor_regions) for mode in (:off,:passive,:passive_chains)]
end

"""Assert the declared flat physical starts agree before any timing experiment."""
function start_check(net,candidates=profiles())
    states=map(candidates) do p
        b=build_opf(net,IVRNLP(p.options))
        [JuMP.value(JuMP.start_value,x) for x in b.state]
    end
    residual=maximum(maximum(abs.(s.-first(states))) for s in states)
    residual<=1e-12 || error("physical starts differ across chain profiles")
    (;max_physical_start_difference_pu=residual)
end

function benchmark(output;conductors=2,segments=12,loads=:terminal,repetitions=12)
    repetitions>0 && repetitions%12==0 || throw(ArgumentError("multiples of twelve sweeps balance six profiles"))
    net=chain_case(;conductors,segments,loads);candidates=profiles()
    starts=start_check(net,candidates)
    metadata=(;conductors,segments,loads,repetitions,chain_source_sha256=SOURCE_SHA,starts,
        total_length=1.,primary_metric="ipopt_wall_s",
        note="Fixed total impedance and total demand as segmentation changes. All original limits preserved, including 100 kVA phase apparent-power bounds at both ends. Fixed flat physical starts agree. Full/passive/chains crossed with full/regional coordinates; MUMPS AMD. Twelve sweeps put every profile in every position twice. No relaxed retries; construction excluded from primary ranking.")
    open(io->JSON3.write(io,metadata),output*".manifest.json","w")
    result=P.benchmark(net,output;repetitions,candidates)
    result["chain_input"]=metadata
    orders=result["orders"]
    result["position_balanced"]=all(count(o->o[k]==p.name,orders)==repetitions/length(candidates)
        for p in candidates for k in eachindex(candidates))
    open(io->JSON3.write(io,result),output,"w")
    result["position_balanced"] || error("profile position balance failed")
    result
end
end
