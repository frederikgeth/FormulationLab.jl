# External transfer study: source files are read-only; no data are bundled.
module IVRFeederLiftingStudy
using FormulationLab, JuMP, JSON3, SHA, LinearAlgebra
include("benchmark_ivr_lifting_blocks.jl")
const L=IVRLiftingBlockStudy
const P=L.P
const SOURCE_SHA=bytes2hex(sha256(read(@__FILE__)))

"""Frozen transfer shortlist. All profiles use voltage ground scaling and AMD.

The feasibility objective preserves source/generator accounting in the input;
this is not an economic-dispatch experiment. No candidate changes input physics.
"""
function profiles()
    specs=[("full",:off,:off,:off),
        ("regional_passive",:conductor_regions,:passive,:off),
        ("blocks_off",:conductor_regions,:passive_blocks,:off),
        ("blocks_powers",:conductor_regions,:passive_blocks,:powers),
        ("blocks_bounded_observations",:conductor_regions,:passive_blocks,:bounded_observations),
        ("full_powers",:off,:off,:powers)]
    [(;name,options=IVRNLPOptions(;objective=:feasibility,ground_scaling=:voltage,
        specialization,linear_elimination,lifting),
        solver_options=(linear_solver="mumps",mumps_pivot_order=0))
     for (name,specialization,linear_elimination,lifting) in specs]
end

"""Check the common unloaded circuit start before timing; retain every failure."""
function preflight(net)
    point=try L.start_point(net) catch err
        err isa InterruptException && rethrow()
        return (;passed=false,checks=Any[],error=sprint(showerror,err)),nothing
    end
    checks=map(profiles()) do p
        try
            b=build_opf(net,IVRNLP(p.options));r=ivr_nlp_point_report(b,point)
            passed=isempty(r.missing_channels) && length(r.variable_values)==num_variables(b.model) &&
                all(isfinite,values(r.variable_values)) &&
                max(r.max_binding_residual_pu,r.max_reconstruction_residual_pu)<=1e-10
            (;name=p.name,passed,variables=num_variables(b.model),
                encoded_variables=length(r.variable_values),missing_channels=r.missing_channels,
                binding=r.max_binding_residual_pu,reconstruction=r.max_reconstruction_residual_pu,
                constraint_violation=r.max_constraint_violation)
        catch err
            err isa InterruptException && rethrow()
            (;name=p.name,passed=false,error=sprint(showerror,err))
        end
    end
    (;passed=all(c.passed for c in checks),checks),point
end

function benchmark(path,output;repetitions=12)
    repetitions>0 && repetitions%12==0 || throw(ArgumentError("twelve-sweep multiples balance six profiles"))
    canonical(p)=ispath(p) ? realpath(p) : abspath(p)
    any(p->canonical(p)==canonical(path),(output,output*".input.json",output*".manifest.json")) &&
        throw(ArgumentError("output and sidecars must not overwrite the source"))
    digest=bytes2hex(sha256(read(path)))
    net,detached=P.compiler_feeder_input(path;detach_legacy_provenance=true)
    before=bytes2hex(sha256(JSON3.write(net)))
    candidates=profiles();check,point=preflight(net)
    manifest=Dict("source_path"=>abspath(path),"source_sha256"=>digest,
        "runner_sha256"=>SOURCE_SHA,"network_sha256"=>before,
        "detached_provenance_paths"=>detached,"accounting"=>P.feeder_accounting(net),
        "buses"=>length(net["bus"]),"repetitions"=>repetitions,"preflight"=>check,
        "profiles"=>[(;name=p.name,options=P.option_record(p.options),solver_options=p.solver_options) for p in candidates],
        "initial_state"=>"shared unloaded linear circuit, not a converged OPF",
        "note"=>"Electrical fields unchanged. Known legacy provenance relocated on an owned copy. Feasibility objective; no dispatch claim. Matched voltage ground scaling and AMD. Rank Ipopt wall time only. Preserve rejected and slow trials; no relaxed retries or case substitution.")
    save(p,x)=open(io->JSON3.write(io,x),p,"w")
    save(output*".input.json",net);save(output*".manifest.json",manifest)
    report=if check.passed
        P.benchmark(net,output;repetitions,candidates,initial_point=point,source_sha256=digest)
    else
        Dict{String,Any}("status"=>"preflight_failed","profiles"=>[],"orders"=>[],
            "primary_metric"=>"ipopt_wall_s","ranking"=>nothing)
    end
    report["feeder_input"]=manifest
    report["source_unchanged"]=bytes2hex(sha256(read(path)))==digest
    report["network_unchanged"]=bytes2hex(sha256(JSON3.write(net)))==before
    report["position_balanced"]=check.passed && all(count(o->o[k]==p.name,report["orders"])==repetitions/6
        for p in candidates for k in eachindex(candidates))
    save(output,report)
    report["source_unchanged"] && report["network_unchanged"] || error("input changed during study; reject this batch")
    check.passed && !report["position_balanced"] && error("unbalanced profile position")
    report
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("usage: input.json output.json")
    IVRFeederLiftingStudy.BLAS.set_num_threads(1)
    report=IVRFeederLiftingStudy.benchmark(ARGS...)
    println(report["ranking"])
end
