# Matched fresh/reused generator-availability and price scenarios on external
# feeders. No previous-primal warm starts, data rewrites, or implicit repairs.
include("benchmark_ivr_feeders.jl")

function dispatch_schedule(net,N)
    roots=Set(s["bus"] for s in values(net["voltage_source"]))
    generators=sort!([id for (id,g) in get(net,"generator",Dict()) if g["bus"] ∉ roots &&
        haskey(g,"p_min") && haskey(g,"p_max") && all(>=(0),g["p_min"])])
    isempty(generators) && error("No nonroot generators with nonnegative finite active-power boxes")
    availability=(1.,0.,.25,.5,.75,1.,.75,.5,.25,1.)
    price=(1.,1.,2.,.5,1.5,2.,.5,1.5,2.,1.)
    [Dict(id=>(p_min=availability[mod1(k,10)].*net["generator"][id]["p_min"],
                p_max=availability[mod1(k,10)].*net["generator"][id]["p_max"],
                cost=price[mod1(k,10)].*get(net["generator"][id],"energy_cost_rate",
                    get(net["generator"][id],"cost",zeros(length(net["generator"][id]["p_max"])))))
          for id in generators) for k in 1:N]
end

# Independently apply the declared scenario to data for fresh construction;
# this deliberately does not call the model-update API under test.
function dispatch_input(net,updates)
    scenario=deepcopy(net)
    for (id,values) in updates,(field,v) in pairs(values)
        scenario["generator"][id][string(field)]=copy(v)
        field==:cost && haskey(scenario["generator"][id],"energy_cost_rate") &&
            (scenario["generator"][id]["energy_cost_rate"]=copy(v))
    end
    scenario
end

function dispatch_trial(net,specialization,reuse,schedule;max_cpu_time=30.)
    build=nothing;initial_s=0.;initial_bytes=0;rows=Any[]
    if reuse
        initial=@timed build_opf(net,IVRNLP(;specialization);optimizer=Ipopt.Optimizer)
        build=initial.value;initial_s=initial.time;initial_bytes=initial.bytes
    end
    costs=[abs(Float64(c)) for family in ("generator","voltage_source") for d in values(get(net,family,Dict()))
        for c in get(d,"energy_cost_rate",get(d,"cost",[0.]))]
    scale=isempty(costs) || maximum(costs)==0 ? 1. : 1000/maximum(costs)
    for (k,updates) in enumerate(schedule)
        preparation=@timed if reuse
            update_ivr_generators!(build,updates)
        else
            build_opf(dispatch_input(net,updates),IVRNLP(;specialization);optimizer=Ipopt.Optimizer)
        end
        build=preparation.value
        solve=@timed solve_ivr_nlp_opf(build;solver_options=(print_level=0,tol=1e-9,constr_viol_tol=1e-10,
            bound_relax_factor=0.,obj_scaling_factor=scale,max_iter=1000,max_cpu_time=max_cpu_time))
        r=solve.value
        row=Dict{String,Any}("scenario"=>k,"preparation_s"=>preparation.time,"preparation_bytes"=>preparation.bytes,
            "solve_and_extract_s"=>solve.time,"solve_bytes"=>solve.bytes,"status"=>r.solve.termination_status,
            "objective"=>isfinite(r.objective) ? r.objective : nothing,"physical_passed"=>false)
        row["iterations"]=try JuMP.MOI.get(JuMP.backend(build.model),JuMP.MOI.BarrierIterations()) catch; nothing end
        if r.solve.optimal
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            audit=@timed physical_residuals(build.network,point;delta_dispatch=:coil)
            row["physical_passed"]=audit.value.passed;row["physical_maxima"]=audit.value.maxima
            row["unassessed"]=audit.value.unassessed;row["audit_s"]=audit.time
            # Cross both dimensions: supplied reused points go to fresh,
            # opposite-formulation models. Fresh points check the opposite
            # formulation's base model after applying the update API.
            check=@timed begin
                other=specialization==:off ? :conductor_difference : :off
                counterpart=build_opf(reuse ? dispatch_input(net,updates) : net,IVRNLP(specialization=other))
                reuse || update_ivr_generators!(counterpart,updates)
                ivr_nlp_point_report(counterpart,point)
            end
            mapped=check.value
            row["mapping_s"]=check.time
            row["point_report"]=(;passed=mapped.passed,objective=mapped.objective,
                binding=mapped.max_binding_residual_pu,reconstruction=mapped.max_reconstruction_residual_pu,
                constraint=mapped.max_constraint_violation)
            row["objective_agrees"]=isapprox(r.objective,mapped.objective;rtol=1e-8,atol=1e-9)
        end
        push!(rows,row)
        # Retain the failed scenario and explicitly mark the batch incomplete.
        # Do not repeat 100 expensive solves after a demonstrated failure.
        row["physical_passed"] && row["point_report"].passed && row["objective_agrees"] || break
    end
    Dict("specialization"=>string(specialization),"reuse"=>reuse,"requested_N"=>length(schedule),
        "completed_N"=>length(rows),
        "accepted_N"=>count(r->r["physical_passed"] && r["point_report"].passed && r["objective_agrees"],rows),
        "initial_build_s"=>initial_s,"initial_build_bytes"=>initial_bytes,
        "workflow_s"=>initial_s+sum(r["preparation_s"]+r["solve_and_extract_s"] for r in rows),
        "objective_solver_scale"=>scale,"variables"=>num_variables(build.model),
        "assembly_count"=>build.numerical_diagnostics[:assembly_count],
        "structure_analysis_count"=>build.numerical_diagnostics[:structure_analysis_count],
        "generator_update_count"=>build.numerical_diagnostics[:generator_update_count],
        "actual_specialization"=>string(build.numerical_diagnostics[:specialization]),"scenarios"=>rows)
end

function benchmark_ivr_dispatch(path,output;batches=(1,10),repetitions=3,source_zero_power=false)
    BLAS.set_num_threads(1)
    net,detached=compiler_feeder_input(path;detach_legacy_provenance=true)
    accounting=feeder_accounting(net)
    changes=source_zero_power ? feeder_source_zero_power!(net) : Any[]
    schedules=Dict(N=>dispatch_schedule(net,N) for N in batches)
    report=Dict{String,Any}("input"=>abspath(path),"input_sha256"=>bytes2hex(sha256(read(path))),
        "buses"=>length(net["bus"]),"lines"=>length(net["line"]),"detached_provenance_paths"=>detached,
        "original_accounting"=>accounting,"initial_electrical_changes"=>changes,"schedules"=>schedules,
        "julia"=>string(VERSION),"jump"=>string(pkgversion(JuMP)),"ipopt"=>string(pkgversion(Ipopt)),
        "cpu"=>Sys.CPU_NAME,"julia_threads"=>Threads.nthreads(),"blas_threads"=>BLAS.get_num_threads(),
        "base_revision"=>readchomp(`git -C $(dirname(@__DIR__)) rev-parse HEAD`),"trials"=>Any[],
        "note"=>"Working tree may be uncommitted. Raw dictionary input, known legacy provenance relocated in memory. Source files untouched. Any initial accounting changes and every parameter scenario are recorded. Fresh models use direct scenario-data edits; reused models use the update API. Fixed unloaded starts; no previous-primal warm start. Workflow excludes physical audits and supplied-point counterpart construction. A failed batch stops and remains incomplete; do not compare its timing with a completed batch.")
    report["warmup_s"]=Dict("$s/$reuse"=>@elapsed(dispatch_trial(net,s,reuse,dispatch_schedule(net,2)))
        for s in (:off,:conductor_difference) for reuse in (false,true))
    for N in batches,rep in 1:repetitions
        variants=[(s,reuse) for s in (:off,:conductor_difference) for reuse in (false,true)]
        iseven(rep) && reverse!(variants)
        for (s,reuse) in variants
            try
                row=dispatch_trial(net,s,reuse,schedules[N]);row["repetition"]=rep
                push!(report["trials"],row)
                println(basename(path)," N=",N," / ",s," / reuse=",reuse," / ",rep," completed ",row["completed_N"]);flush(stdout)
            catch err
                err isa InterruptException && rethrow()
                push!(report["trials"],Dict("requested_N"=>N,"specialization"=>string(s),"reuse"=>reuse,
                    "repetition"=>rep,"error"=>sprint(showerror,err)))
            end
            open(io->JSON3.write(io,report),output,"w")
        end
    end
    report
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)>=2 || error("Supply one feeder path, output path and optional --source-zero-power/--hundred")
    all(x->x in ("--source-zero-power","--hundred"),ARGS[3:end]) || error("Unknown flag")
    benchmark_ivr_dispatch(ARGS[1],ARGS[2];source_zero_power="--source-zero-power" in ARGS,
        batches="--hundred" in ARGS ? (1,10,100) : (1,10))
end
