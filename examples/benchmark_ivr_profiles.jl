# Empirical profile comparison. Keeps every formulation option available.
# julia --project=test examples/benchmark_ivr_profiles.jl input.json output.json
module IVRProfileStudy
using FormulationLab, JuMP, Ipopt, JSON3, LinearAlgebra, Statistics, SHA
include("benchmark_ivr_feeders.jl")
const RUNNER_SHA = bytes2hex(sha256(read(@__FILE__)))

const STRICT = (print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,
                bound_relax_factor=0.,max_iter=500,max_cpu_time=30.)

"""A declared shortlist, not an exhaustive option search or a new default."""
function profiles(;objective=:feasibility)
    specs=[("full",:off,:off,:all,:off),
        ("difference",:conductor_difference,:off,:all,:off),
        ("regions",:conductor_regions,:off,:all,:off),
        ("passive",:off,:passive,:all,:off),
        ("difference_passive",:conductor_difference,:passive,:all,:off),
        ("regional_passive",:conductor_regions,:passive,:all,:off),
        ("scaled_full",:off,:off,:all,:voltage),
        ("scaled_regions",:conductor_regions,:off,:all,:voltage),
        ("scaled_passive",:off,:passive,:all,:voltage),
        ("scaled_regional_passive",:conductor_regions,:passive,:all,:voltage),
        ("selected_passive",:off,:passive,:bound_support,:voltage),
        ("selected_regional_passive",:conductor_regions,:passive,:bound_support,:voltage)]
    [(;name,options=IVRNLPOptions(;objective,specialization,linear_elimination,series_selection,ground_scaling))
     for (name,specialization,linear_elimination,series_selection,ground_scaling) in specs]
end
option_record(x)=(; (k=>getfield(x,k) for k in fieldnames(typeof(x)))...)

# Separate admission from timing. A fast failed trial must never win; a profile
# with missing/rejected repeats or warm-up is ineligible. Nonconvex objective
# differences are not silently traded against runtime.
valid_ipopt_time(t)=get(t,"ipopt_wall_s",nothing) isa Real && isfinite(t["ipopt_wall_s"]) && t["ipopt_wall_s"]>=0

function rank_profiles(rows,repetitions;objective_atol=1e-6,objective_rtol=1e-8)
    eligible=[r for r in rows if r["warmup"]["accepted"] && length(r["trials"])==repetitions &&
              all(t->t["accepted"],r["trials"])]
    values=[t["objective"] for r in eligible for t in r["trials"]]
    comparable=!isempty(values) && all(v->isapprox(v,minimum(values);atol=objective_atol,rtol=objective_rtol),values)
    ranking=[Dict("name"=>r["name"],"median_build_s"=>median(t["build_s"] for t in r["trials"]),
        "median_solve_s"=>median(t["solve_s"] for t in r["trials"]),
        "median_ipopt_wall_s"=>(all(t->valid_ipopt_time(t),r["trials"]) ? median(t["ipopt_wall_s"] for t in r["trials"]) : nothing),
        "median_total_s"=>median(t["build_s"]+t["solve_s"] for t in r["trials"]),
        "median_build_bytes"=>median(t["build_bytes"] for t in r["trials"])) for r in eligible]
    timing_complete=!isempty(ranking) && all(r->r["median_ipopt_wall_s"]!==nothing,ranking)
    # Missing historical solver timings cannot be inferred from solve+extraction.
    sort!(ranking;by=r->(something(r["median_ipopt_wall_s"],Inf),r["name"]))
    Dict("eligible"=>ranking,"objective_comparable"=>comparable,
         "primary_metric"=>"ipopt_wall_s","ipopt_timing_complete"=>timing_complete,
         "fastest_ipopt"=>(comparable && timing_complete ? first(ranking)["name"] : nothing),
         "fastest_total"=>(comparable ? first(sort(ranking;by=r->(r["median_total_s"],r["name"])))["name"] : nothing),
         "fastest_solve"=>(comparable ? first(sort(ranking;by=r->(r["median_solve_s"],r["name"])))["name"] : nothing),
         "objective_atol"=>objective_atol,"objective_rtol"=>objective_rtol)
end

function trial(net,profile,reference,anchor;solver_options=STRICT)
    try
        t=@timed build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer);b=t.value
        s=@timed solve_ivr_nlp_opf(b;solver_options);r=s.value
        p=r.solve.optimal ? ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate) : nothing
        physical=p===nothing ? nothing : physical_residuals(net,r)
        own=p===nothing ? nothing : ivr_nlp_point_report(b,p)
        full=p===nothing ? nothing : ivr_nlp_point_report(reference,p)
        reverse=anchor===nothing ? nothing : ivr_nlp_point_report(b,anchor).passed
        accepted=p!==nothing && physical.passed && own.passed && full.passed && reverse!==false &&
            isfinite(r.objective) && isapprox(own.objective,full.objective;atol=1e-6,rtol=1e-8)
        row=Dict{String,Any}("build_s"=>t.time,"build_bytes"=>t.bytes,"build_gc_s"=>t.gctime,
            "ipopt_wall_s"=>JuMP.solve_time(b.model),
            "solve_s"=>s.time,"solve_bytes"=>s.bytes,"solve_gc_s"=>s.gctime,"status"=>r.solve.termination_status,
            "accepted"=>accepted,"physical_passed"=>(p!==nothing&&physical.passed),
            "own_model_passed"=>(p!==nothing&&own.passed),"full_model_passed"=>(p!==nothing&&full.passed),
            "anchor_in_profile"=>reverse,"objective"=>(isfinite(r.objective) ? r.objective : nothing),
            "variables"=>num_variables(b.model),"derivatives"=>feeder_derivative_structure(b.model),
            "specialization"=>b.numerical_diagnostics[:specialization],
            "specialization_report"=>b.numerical_diagnostics[:specialization_report],
            "elimination"=>b.numerical_diagnostics[:linear_elimination_report],
            "ground_scaling"=>b.numerical_diagnostics[:ground_scaling_report],
            "iterations"=>(try JuMP.MOI.get(JuMP.backend(b.model),JuMP.MOI.BarrierIterations()) catch; nothing end),
            "bad_physical_records"=>(p===nothing ? [] : [(;label=x.label,residual=x.residual,unit=x.unit)
                for x in physical.records if x.residual>getproperty(physical.tolerances,x.unit)]))
        return row,p
    catch err
        err isa InterruptException && rethrow()
        # Experimental errors are evidence too; no relaxed retry or fallback.
        return Dict{String,Any}("accepted"=>false,"error"=>sprint(showerror,err)),nothing
    end
end

"""Measure explicit profiles; save raw trials and workload-specific rankings.

Primary ranking uses `ipopt_wall_s`, obtained from `JuMP.solve_time`; model
construction does not enter that ranking. Warm-ups are excluded. Four or more rotated/reversed sweeps are exploratory,
not a fully position-balanced design. Confirm a chosen profile with fresh paired
measurements. All electrical inputs/objectives are retained. The solve-only
ranking excludes construction but does not measure updated-model reuse.
"""
function benchmark(net,output;repetitions=4,candidates=profiles(),solver_options=STRICT,source_sha256=nothing)
    started=time_ns()
    repetitions>0 || throw(ArgumentError("positive repetitions required"))
    !isempty(candidates) && allunique(p.name for p in candidates) || throw(ArgumentError("unique nonempty profiles required"))
    objective=first(candidates).options.objective
    all(p.options.objective==objective for p in candidates) || throw(ArgumentError("profiles must share an objective"))
    reference=build_opf(net,IVRNLP(objective=objective))
    rows=[Dict{String,Any}("name"=>p.name,"options"=>option_record(p.options),"warmup"=>nothing,"trials"=>[]) for p in candidates]
    report=Dict{String,Any}("profiles"=>rows,"repetitions"=>repetitions,"objective"=>objective,
        "source_sha256"=>source_sha256,"network_sha256"=>bytes2hex(sha256(JSON3.write(net))),
        "julia"=>string(VERSION),"jump"=>string(pkgversion(JuMP)),"ipopt"=>string(pkgversion(Ipopt)),
        "cpu"=>Sys.CPU_NAME,"blas_threads"=>BLAS.get_num_threads(),"julia_threads"=>Threads.nthreads(),
        "solver_options"=>solver_options,"runner_sha256"=>RUNNER_SHA,"orders"=>[],
        "primary_metric"=>"ipopt_wall_s",
        "timing_contract"=>"MOI.SolveTimeSec from Ipopt.jl: wall time of its optimizer call, including backend setup and native IpoptSolve; excludes FormulationLab build, JuMP cache transfer before the backend call, result extraction and physical/model audits. build_s and solve_s (wrapper plus extraction) are secondary diagnostics only.",
        "note"=>"Exploratory shortlist; no universal fastest claim. Primary ranking uses Ipopt wall time; build and solve/extraction timings are retained as secondary diagnostics. All timings exclude audits and warm-ups. Rejected/error trials retained. Unchanged electrical data and explicit shared objective. A first accepted warm-up supplies the full-feasible anchor for reverse mapping. Confirm winners independently; rankings do not measure parameter-update reuse.")
    save()=open(io->JSON3.write(io,report),output,"w")
    anchor=nothing
    for (j,p) in enumerate(candidates)
        row,point=trial(net,p,reference,anchor;solver_options);rows[j]["warmup"]=row
        if anchor===nothing && row["accepted"];anchor=point;report["anchor_profile"]=p.name;end
        save()
    end
    for rep in 1:repetitions
        order=circshift(collect(eachindex(candidates)),(rep-1)÷2)
        iseven(rep) && reverse!(order)
        push!(report["orders"],[candidates[j].name for j in order])
        for j in order
            row,_=trial(net,candidates[j],reference,anchor;solver_options)
            anchor===nothing && (row["accepted"]=false)
            push!(rows[j]["trials"],row);save()
        end
    end
    report["ranking"]=rank_profiles(rows,repetitions)
    report["total_study_s"]=(time_ns()-started)/1e9
    save()
    report
end

function main(args)
    length(args)==2 || error("usage: input.json output.json")
    BLAS.set_num_threads(1)
    net,_=compiler_feeder_input(args[1];detach_legacy_provenance=true)
    report=benchmark(net,args[2];source_sha256=bytes2hex(sha256(read(args[1]))))
    println(report["ranking"])
end
end
abspath(PROGRAM_FILE)==(@__FILE__) && IVRProfileStudy.main(ARGS)
