# Synthetic full/reduced x fresh/reused ablation. Timings are not CI assertions.
using FormulationLab, JuMP, Ipopt, JSON3, LinearAlgebra, SHA
include("ivr_compiler_cases.jl")

function compiler_trial(net,specialization,reuse,N)
    rows=Any[];build=nothing;initial_build_s=0.;initial_bytes=0
    if reuse
        t=@timed build_opf(net,IVRNLP(;specialization,objective=:source_import);optimizer=Ipopt.Optimizer)
        build=t.value;initial_build_s=t.time;initial_bytes=t.bytes
    end
    for k in 1:N
        factor=1+.25sin(2pi*k/10)
        updates=Dict(id=>(p=factor*d["p_nom"],q=factor*d["q_nom"]) for (id,d) in net["load"])
        preparation=@timed if reuse
            update_ivr_loads!(build,updates)
        else
            scenario=deepcopy(net)
            for (id,v) in updates
                scenario["load"][id]["p_nom"]=v.p;scenario["load"][id]["q_nom"]=v.q
            end
            build_opf(scenario,IVRNLP(;specialization,objective=:source_import);optimizer=Ipopt.Optimizer)
        end
        build=preparation.value
        # Both representations use mapped, fixed unloaded physical starts.
        # No reuse of previous primal solutions is requested in this ablation.
        solve=@timed solve_ivr_nlp_opf(build;solver_options=(print_level=0,tol=1e-9,bound_relax_factor=0.))
        r=solve.value
        audit=@timed r.solve.optimal ? physical_residuals(build.network,
            ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate);delta_dispatch=:coil) : nothing
        push!(rows,Dict("scenario"=>k,"factor"=>factor,"preparation_s"=>preparation.time,
            "preparation_bytes"=>preparation.bytes,"solve_and_extract_s"=>solve.time,"solve_bytes"=>solve.bytes,
            "audit_s"=>audit.time,"status"=>r.solve.termination_status,
            "physical_passed"=>audit.value!==nothing && audit.value.passed,
            "objective_W"=>isfinite(r.objective) ? r.objective : nothing))
    end
    Dict("specialization"=>string(specialization),"reuse"=>reuse,"N"=>N,
        "initial_build_s"=>initial_build_s,"initial_build_bytes"=>initial_bytes,
        "workflow_s"=>initial_build_s+sum(r["preparation_s"]+r["solve_and_extract_s"] for r in rows),
        "variables"=>num_variables(build.model),"constraints"=>num_constraints(build.model;count_variable_in_set_constraints=true),
        "structure_analysis_count"=>build.numerical_diagnostics[:structure_analysis_count],
        "failures"=>count(r->!r["physical_passed"],rows),"scenarios"=>rows)
end

function benchmark_ivr_compiler(output;repetitions=3)
    BLAS.set_num_threads(1)
    warm=Dict{String,Any}()
    for m in (2,3,4),s in (:off,:conductor_difference),reuse in (false,true)
        net=ivr_compiler_case(conductors=m,segments=2)
        warm["$m/$s/$reuse"]=@elapsed compiler_trial(net,s,reuse,2)
    end
    report=Dict{String,Any}("julia"=>string(VERSION),"ipopt"=>string(pkgversion(Ipopt)),
        "jump"=>string(pkgversion(JuMP)),"cpu"=>Sys.CPU_NAME,"julia_threads"=>Threads.nthreads(),
        "blas_threads"=>BLAS.get_num_threads(),"warmup_s"=>warm,
        "note"=>"Synthetic inputs, fixed physical starts, no automatic previous-solution warm start. Workflow includes build/update and solve/extraction; independent audits are timed separately. Reduced form retains reference-conductor voltages. Working tree may be uncommitted.",
        "base_revision"=>readchomp(`git -C $(dirname(@__DIR__)) rev-parse HEAD`),"cases"=>Any[])
    for m in (2,3,4),shape in (:chain,:tree)
        net=ivr_compiler_case(conductors=m,segments=8;shape)
        case=Dict{String,Any}("conductors"=>m,"segments"=>8,"shape"=>string(shape),
            "input_sha256"=>bytes2hex(sha256(JSON3.write(net))),"trials"=>Any[])
        push!(report["cases"],case)
        # Include a longer reuse batch in the four-wire chain experiment.
        batches=m==4 && shape==:chain ? (1,10,100) : (1,10)
        for N in batches,rep in 1:repetitions
            variants=[(s,reuse) for s in (:off,:conductor_difference) for reuse in (false,true)]
            iseven(rep) && reverse!(variants) # Reduce systematic ordering bias.
            for (s,reuse) in variants
                trial=compiler_trial(net,s,reuse,N);trial["repetition"]=rep
                push!(case["trials"],trial)
            end
            open(io->JSON3.write(io,report),output,"w")
        end
        println("Completed ",m," conductors / ",shape);flush(stdout)
    end
    report
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("Supply output JSON path")
    benchmark_ivr_compiler(only(ARGS))
end
