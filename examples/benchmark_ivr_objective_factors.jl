"""Matched power-objective comparisons with four independently varied options."""
module IVRObjectiveFactorStudy
using FormulationLab, JSON3, SHA, Random
include("benchmark_ivr_power_objectives.jl")
const S=IVRPowerObjectiveStudy

function profiles(net,workload;nlp_scaling_method="none")
    nlp_scaling_method in ("none","gradient-based") || throw(ArgumentError("unknown solver scaling policy"))
    terms=S.terms(net,workload)
    seeds=Dict("hv"=>1e6,"mv"=>1e5,"lv1_b0"=>1e3,"lv2_b0"=>1e3)
    [(;name="$(regional_current ? "regional" : "common")_b$(Int(passive_blocks))_t$(Int(transformer_currents))_$(lifting)",
        factors=(;regional_current,passive_blocks,transformer_currents,lifting),
        options=IVRNLPOptions(objective=workload==:linear_cost ? :cost : :power,power_terms=terms,
            objective_scale=workload==:losses ? 1e4 : 1.,s_base=1e4,
            current_power_bases=regional_current ? seeds : Dict{String,Float64}(),
            specialization=:conductor_regions,ground_scaling=:voltage,
            transformer_scaling=:nominal,row_scaling=:composed,
            linear_elimination=passive_blocks ? :passive_blocks : :off,
            device_elimination=transformer_currents ? :transformer_currents : :off,
            lifting=lifting,observation_sharing=:exact),
        solver_options=(linear_solver="mumps",mumps_pivot_order=0,nlp_scaling_method))
        for regional_current in (false,true) for passive_blocks in (false,true)
        for transformer_currents in (false,true) for lifting in (:off,:powers,:bounded_observations)]
end

"""Randomized permutation/reversal blocks; equal mean position, not all positions.

Every candidate appears once per sweep. Pairing each permutation with its
reverse gives every candidate mean position (n+1)/2 in each block. The realized
orders are saved because seeded RNG behavior is environment-dependent.
"""
function orders(n;blocks=4,seed=20261005)
    n isa Integer && n>=1 && blocks isa Integer && blocks>=1 || throw(ArgumentError("positive candidate and block counts required"))
    rng=MersenneTwister(seed)
    reduce(vcat,[[p,reverse(p)] for _ in 1:blocks for p in [randperm(rng,n)]])
end

function benchmark(output;workload=:quadratic_cost,segments=12,nlp_scaling_method="none",blocks=4,seed=20261005)
    net=S.case(workload;segments);candidates=profiles(net,workload;nlp_scaling_method)
    trial_orders=orders(length(candidates);blocks,seed)
    start=S.U.G.H.S.L.start_point(net)
    open(io->JSON3.write(io,net),output*".input.json","w")
    report=S.P.benchmark(net,output;repetitions=length(trial_orders),candidates,initial_point=start,
        trial_orders,source_sha256=bytes2hex(sha256(read(@__FILE__))))
    report["workload"]=workload
    report["factors"]=Dict(p.name=>p.factors for p in candidates)
    report["order_design"]=(;blocks,seed,kind="random_permutation_then_reverse",mean_position=(length(candidates)+1)/2,
        note="Equal mean position within each two-sweep block. Not fully position-balanced; no Latin-square claim.")
    report["mean_position_balanced"]=all(sum(findfirst(==(p.name),o) for o in report["orders"])==blocks*(length(candidates)+1) for p in candidates)
    report["mean_position_balanced"] || error("mean-position balance failed")
    report["global_optimum_certified"]=false
    open(io->JSON3.write(io,report),output,"w")
    report
end
end
