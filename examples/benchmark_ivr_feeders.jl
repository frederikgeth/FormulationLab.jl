# Matched declared-OPF experiments on external files; no datasets are bundled.
using FormulationLab, JuMP, Ipopt, JSON3, LinearAlgebra, SHA
include("census_ivr_compiler.jl")
include("ivr_compiler_cases.jl")

function feeder_accounting(net)
    sources=get(net,"voltage_source",Dict());generators=get(net,"generator",Dict())
    overlaps=[(;source=sid,generator=gid,bus=s["bus"]) for (sid,s) in sources
        for (gid,g) in generators if s["bus"]==g["bus"]]
    (;colocated_sources_and_generators=overlaps,
      unpriced_sources=[id for (id,s) in sources if !haskey(s,"cost") && !haskey(s,"energy_cost_rate")],
      note="Declared cost objective and all electrical data retained. Colocated free sources can invalidate an economic-import interpretation; do not interpret objective parity as a meaningful dispatch benefit.")
end

# Explicit experimental scenario, NOT an equivalence-preserving input cleanup.
# The named colocated grid generator carries supply, while the ideal source
# specifies voltages with zero power. Preserve all generator and network limits.
function feeder_source_zero_power!(net)
    changes=Any[]
    for (id,s) in net["voltage_source"]
        any(g->g["bus"]==s["bus"],values(get(net,"generator",Dict()))) ||
            error("source/$id needs a colocated supply generator for this scenario")
        for key in ("p_min","p_max","q_min","q_max")
            old=get(s,key,nothing);new=zeros(length(s["terminal_map"]))
            push!(changes,(;path="/voltage_source/$id/$key",before=old,after=new))
            s[key]=new
        end
    end
    changes
end

function feeder_derivative_structure(model)
    # Count the entries supplied to Ipopt, before its fixed-variable removal
    # and linear-solver factorization. Duplicates are legal in MOI structures.
    try
        backend=JuMP.unsafe_backend(model)
        J=JuMP.MOI.jacobian_structure(backend)
        H=JuMP.MOI.hessian_lagrangian_structure(backend)
        (;jacobian_entries=length(J),jacobian_unique=length(unique(J)),
          hessian_entries=length(H),hessian_unique=length(unique(H)),
          note="Backend structures before solver preprocessing; not KKT fill or factorization memory.")
    catch err
        (;unavailable=sprint(showerror,err))
    end
end

function feeder_trial(net,specialization;factors=(1.,),opposite=nothing)
    preparation=@timed build_opf(net,IVRNLP(;specialization,objective=:cost);optimizer=Ipopt.Optimizer)
    build=preparation.value
    costs=[abs(Float64(c)) for family in ("generator","voltage_source") for d in values(get(net,family,Dict()))
           for c in get(d,"energy_cost_rate",get(d,"cost",[0.]))]
    # Scale the solver objective, not the declared costs, to avoid treating the
    # small currency/kWh coefficients as a numerically negligible objective.
    scaling=isempty(costs) || maximum(costs)==0 ? 1. : 1000/maximum(costs)
    rows=Any[];points=ACPoint[]
    for (k,factor) in enumerate(factors)
        update=@timed update_ivr_loads!(build,Dict(id=>(p=factor*d["p_nom"],q=factor*d["q_nom"])
            for (id,d) in net["load"] if lowercase(get(d,"model","constant_power"))=="constant_power"))
        solve=@timed solve_ivr_nlp_opf(build;solver_options=(print_level=0,tol=1e-9,
            constr_viol_tol=1e-10,bound_relax_factor=0.,obj_scaling_factor=scaling,max_iter=1000,max_cpu_time=60.))
        r=solve.value
        row=Dict{String,Any}("factor"=>factor,"update_s"=>update.time,"update_bytes"=>update.bytes,
            "solve_and_extract_s"=>solve.time,"solve_bytes"=>solve.bytes,"status"=>r.solve.termination_status,
            "objective"=>isfinite(r.objective) ? r.objective : nothing,"physical_passed"=>false)
        row["iterations"]=try JuMP.MOI.get(JuMP.backend(build.model),JuMP.MOI.BarrierIterations()) catch; nothing end
        if r.solve.optimal
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate);push!(points,point)
            audit=@timed physical_residuals(build.network,point;delta_dispatch=:coil)
            row["audit_s"]=audit.time;row["physical_passed"]=audit.value.passed
            row["physical_maxima"]=audit.value.maxima;row["unassessed"]=audit.value.unassessed
            row["worst_physical_records"]=sort(audit.value.records;by=x->-x.residual)[1:min(5,end)]
            row["source_p_W"]=Dict(id=>real.(s) for ((f,id),s) in r.powers if f==:voltage_source)
            row["root_generator_p_W"]=Dict(id=>real.(s) for ((f,id),s) in r.powers if f==:generator &&
                any(v->v["bus"]==net["generator"][id]["bus"],values(net["voltage_source"])))
            if opposite!==nothing
                update_ivr_loads!(opposite,Dict(id=>(p=factor*d["p_nom"],q=factor*d["q_nom"])
                    for (id,d) in net["load"] if lowercase(get(d,"model","constant_power"))=="constant_power"))
                mapped=ivr_nlp_point_report(opposite,point)
                row["opposite_point_report"]=(;passed=mapped.passed,binding=mapped.max_binding_residual_pu,
                    reconstruction=mapped.max_reconstruction_residual_pu,constraint=mapped.max_constraint_violation,
                    objective=mapped.objective)
            end
        end
        push!(rows,row)
    end
    report=Dict("specialization"=>string(specialization),"build_s"=>preparation.time,"build_bytes"=>preparation.bytes,
        "variables"=>num_variables(build.model),"constraints"=>num_constraints(build.model;count_variable_in_set_constraints=true),
        "derivative_structure"=>feeder_derivative_structure(build.model),
        "objective_solver_scale"=>scaling,"structure_report"=>build.numerical_diagnostics[:specialization_report],
        "workflow_s"=>preparation.time+sum(r["update_s"]+r["solve_and_extract_s"] for r in rows),"scenarios"=>rows)
    report,build,points
end

function benchmark_ivr_feeders(directory,output,files;repetitions=3,factors=(1.,.9,1.1),accounting=:declared)
    accounting in (:declared,:source_zero_power) || error("unknown accounting scenario")
    BLAS.set_num_threads(1)
    warm=Dict{String,Float64}()
    for s in (:off,:conductor_difference)
        warm[string(s)]=@elapsed feeder_trial(ivr_compiler_case(segments=2),s)
    end
    report=Dict{String,Any}("julia"=>string(VERSION),"ipopt"=>string(pkgversion(Ipopt)),"jump"=>string(pkgversion(JuMP)),
        "cpu"=>Sys.CPU_NAME,"julia_threads"=>Threads.nthreads(),"blas_threads"=>BLAS.get_num_threads(),"warmup_s"=>warm,
        "base_revision"=>readchomp(`git -C $(dirname(@__DIR__)) rev-parse HEAD`),"accounting_scenario"=>string(accounting),
        "note"=>"Working tree may be uncommitted. Raw dictionaries, no schema validation. Known legacy provenance relocated in memory. Any experimental electrical changes are explicitly recorded; source files untouched. Existing topology reduction is inherited. Fixed unloaded starts, no previous-solution warm starts. Audit and cross-mapping excluded from workflow time. Supplied-point checks establish feasibility correspondence; different local solutions need not coincide.",
        "cases"=>Any[])
    for file in files
        path=joinpath(directory,file);net,detached=compiler_feeder_input(path;detach_legacy_provenance=true)
        original_accounting=feeder_accounting(net)
        changes=accounting==:source_zero_power ? feeder_source_zero_power!(net) : Any[]
        case=Dict{String,Any}("file"=>file,"sha256"=>bytes2hex(sha256(read(path))),"buses"=>length(net["bus"]),
            "lines"=>length(get(net,"line",Dict())),"detached_provenance_paths"=>detached,"original_accounting"=>original_accounting,
            "electrical_changes"=>changes,"scenario_sha256"=>bytes2hex(sha256(JSON3.write(net))),"trials"=>Any[])
        push!(report["cases"],case)
        # Cross-check against a separate optimizer-free instance, outside timers.
        counterparts=Dict(s=>build_opf(net,IVRNLP(specialization=s,objective=:cost)) for s in (:off,:conductor_difference))
        case["warmup_s"]=Dict(string(s)=>@elapsed(feeder_trial(net,s;factors=(1.,),
            opposite=counterparts[s==:off ? :conductor_difference : :off])) for s in (:off,:conductor_difference))
        for rep in 1:repetitions,s in (iseven(rep) ? (:conductor_difference,:off) : (:off,:conductor_difference))
            try
                trial,_,_=feeder_trial(net,s;factors,opposite=counterparts[s==:off ? :conductor_difference : :off])
                trial["repetition"]=rep;push!(case["trials"],trial)
                println(file," / ",s," / ",rep," : ",[(r["status"],r["physical_passed"]) for r in trial["scenarios"]]);flush(stdout)
            catch err
                err isa InterruptException && rethrow()
                push!(case["trials"],Dict("specialization"=>string(s),"repetition"=>rep,"error"=>sprint(showerror,err)))
            end
            open(io->JSON3.write(io,report),output,"w")
        end
    end
    report
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)>=3 || error("Supply input directory, output JSON path, and selected file names")
    files=filter(!=("--source-zero-power"),ARGS[3:end])
    benchmark_ivr_feeders(ARGS[1],ARGS[2],files;accounting="--source-zero-power" in ARGS ? :source_zero_power : :declared)
end
