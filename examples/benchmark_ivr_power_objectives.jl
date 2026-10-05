"""Power-objective workloads on the fixed unbalanced leakage circuit.

Each objective is compared only against itself. The six candidates are explicit
formulation bundles, not a factorial causal attribution to individual options.
"""
module IVRPowerObjectiveStudy
using FormulationLab, JuMP, JSON3, SHA
include("benchmark_ivr_unbalanced_power_bases.jl")
const U=IVRUnbalancedPowerBaseStudy
const P=U.P
const WORKLOADS=(:linear_cost,:quadratic_cost,:dispatch_tracking,:exchange_tracking,:curtailment,:losses)

function case(workload;segments=12)
    workload in WORKLOADS || throw(ArgumentError("unknown power workload"))
    net=U.case(limit=:voltage,segments=segments)
    net["voltage_source"]["grid"]["cost"]=[.25,.25,.25,0.]
    for (j,id) in enumerate(sort!(collect(keys(net["generator"]))))
        d=net["generator"][id];d["q_min"]=[-1500.];d["q_max"]=[1500.]
        d["cost"]=[.10+.01j]
        # Prevent the loss-only workload from eliminating every feeder current
        # by serving each load entirely with its colocated generator.
        workload==:losses && (d["p_max"]=[.7only(net["load"][id]["p_nom"])])
    end
    net
end

function terms(net,workload)
    workload in WORKLOADS || throw(ArgumentError("unknown power workload"))
    workload==:linear_cost && return IVRPowerTerm[]
    generators=[(:generator,id,1) for id in sort!(collect(keys(net["generator"])))]
    sources=[(:voltage_source,"grid",k) for k in 1:3]
    one(channel;kwargs...)=IVRPowerTerm(channels=[channel];kwargs...)
    if workload==:quadratic_cost
        return [IVRPowerTerm(channels=sources,linear=.25/1000);
            [one(c,linear=only(net["generator"][c[2]]["cost"])/1000,quadratic=.02/1e6) for c in generators]]
    elseif workload==:dispatch_tracking
        return [one(c;quantity,target=quantity==:p ? 1000. : 200.,quadratic=1e-6)
            for c in generators for quantity in (:p,:q)]
    elseif workload==:exchange_tracking
        return [[IVRPowerTerm(channels=sources,target=4500.,quadratic=1e-6),
            IVRPowerTerm(channels=sources,quantity=:q,quadratic=1e-6)];
            [one(c;quantity,target=quantity==:p ? 1000. : 200.,quadratic=1e-8)
                for c in generators for quantity in (:p,:q)]]
    elseif workload==:curtailment
        return [[one(c,target=only(net["generator"][c[2]]["p_max"]),linear=-1/1000) for c in generators];
            [one(c,quantity=:q,quadratic=1e-6) for c in generators]]
    end
    loads=[(:load,id,1) for id in sort!(collect(keys(net["load"])))]
    [IVRPowerTerm(channels=[sources;generators;loads],weights=[ones(length(sources)+length(generators));-ones(length(loads))],linear=1.)]
end

function profiles(net,workload;nlp_scaling_method="none")
    nlp_scaling_method in ("none","gradient-based") || throw(ArgumentError("unknown solver scaling policy"))
    objective=workload==:linear_cost ? :cost : :power
    power_terms=terms(net,workload);objective_scale=workload==:losses ? 1e4 : 1.
    regional=Dict("hv"=>1e6,"mv"=>1e5,"lv1_b0"=>1e3,"lv2_b0"=>1e3)
    specs=[("full_10k",1e4,false,false,:off),("full_1k",1e3,false,false,:off),
        ("full_regional",1e4,true,false,:off),("reduced_10k",1e4,false,true,:off),
        ("reduced_1k_powers",1e3,false,true,:powers),("reduced_regional_observations",1e4,true,true,:bounded_observations)]
    [(;name,options=IVRNLPOptions(;objective,power_terms,objective_scale,s_base=sb,
        current_power_bases=local_power ? regional : Dict{String,Float64}(),
        transformer_scaling=:nominal,row_scaling=:composed,ground_scaling=:voltage,
        specialization=reduced ? :conductor_regions : :off,
        linear_elimination=reduced ? :passive_blocks : :off,
        device_elimination=reduced ? :transformer_currents : :off,lifting,
        observation_sharing=reduced ? :exact : :off),
        solver_options=(linear_solver="mumps",mumps_pivot_order=0,nlp_scaling_method))
        for (name,sb,local_power,reduced,lifting) in specs]
end

"""Evaluate declared objective from exported physical powers, outside JuMP."""
function physical_objective(net,workload,powers)
    workload==:linear_cost && return sum(sum(d["cost"].*real.(powers[(family,id)]))/1000
        for family in (:voltage_source,:generator) for (id,d) in net[string(family)])
    sum(terms(net,workload)) do t
        x=sum(w*(t.quantity==:p ? real(powers[(f,id)][k]) : imag(powers[(f,id)][k]))
            for ((f,id,k),w) in zip(t.channels,t.weights))-t.target
        t.linear*x+t.quadratic*x^2
    end
end

function benchmark(output;workload=:quadratic_cost,segments=12,nlp_scaling_method="none",repetitions=12)
    repetitions>0 && repetitions%12==0 || throw(ArgumentError("twelve-sweep multiples required"))
    net=case(workload;segments);candidates=profiles(net,workload;nlp_scaling_method)
    start=U.G.H.S.L.start_point(net)
    open(io->JSON3.write(io,net),output*".input.json","w")
    r=P.benchmark(net,output;repetitions,candidates,initial_point=start,
        source_sha256=bytes2hex(sha256(read(@__FILE__))))
    r["workload"]=workload
    r["position_balanced"]=all(count(o->o[k]==p.name,r["orders"])==repetitions/6 for p in candidates for k in 1:6)
    r["position_balanced"] || error("unbalanced positions")
    r["global_optimum_certified"]=false
    open(io->JSON3.write(io,r),output,"w")
    r
end
end
