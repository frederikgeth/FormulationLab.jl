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

# Overrides are explicit experimental inputs; resolve and record them before
# solving. Copy dictionaries so shared settings cannot be mutated by a profile.
solver_option_dict(x)=Dict{String,Any}(string(k)=>v for (k,v) in (x isa NamedTuple ? pairs(x) : x))
profile_solver_options(profile,shared)=merge(solver_option_dict(shared),
    solver_option_dict(get(profile,:solver_options,(;))))

"""Cross formulation candidates with explicit MUMPS ordering requests.

Only ordering and linear-solver selection are changed. Optional ordering
libraries may fall back; inspect a separate verbose diagnostic for actual order.
Order 1 requires a user permutation not supplied by this helper.
"""
function ordering_profiles(;candidates=profiles()[[1,10,12]],orders=(7,0,2,5,6))
    !isempty(orders) && allunique(orders) && all(o->o in (0,2,3,4,5,6,7),orders) ||
        throw(ArgumentError("distinct MUMPS order requests from 0,2,3,4,5,6,7 required"))
    [(;name="$(p.name)__mumps_$order",options=p.options,formulation_name=p.name,
      solver_options=merge(solver_option_dict(get(p,:solver_options,(;))),
          Dict("linear_solver"=>"mumps","mumps_pivot_order"=>order))) for p in candidates for order in orders]
end

"""Read diagnostic log fields without treating them as benchmark timings.

Missing fields remain missing; signed INFO(9/10) values are preserved verbatim.
Storage counters are not a measurement of process peak memory or factor fill.
"""
function mumps_diagnostics(log::AbstractString)
    ordering=[(;permuting_scaling=parse(Int,m.captures[1]),pivot_order=parse(Int,m.captures[2]))
        for m in eachmatch(r"MUMPS used permuting_scaling (\d+) and pivot_order (\d+)",log)]
    counts(i)=[parse(Int,m.captures[1]) for m in eachmatch(Regex("INFO\\($i\\)\\) = (-?\\d+)"),log)]
    wall=Dict{String,Float64}()
    for key in ("OverallAlgorithm","PDSystemSolverTotal","LinearSystemSymbolicFactorization",
                "LinearSystemFactorization","LinearSystemBackSolve")
        found=match(Regex(key*"\\.+:.*?wall:\\s*([0-9.]+)"),log)
        found===nothing || (wall[key]=parse(Float64,found.captures[1]))
    end
    (;ordering,observed_pivot_orders=sort!(unique(x.pivot_order for x in ordering)),
      factor_double_counts=counts(9),factor_integer_counts=counts(10),native_wall_s=wall,
      note="Verbose diagnostic only. Raw signed storage counters; no peak-memory/fill claim. Native timers are nested and rounded; do not sum them.")
end

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

function trial(net,profile,reference,anchor;solver_options=STRICT,initial_point=nothing)
    settings=profile_solver_options(profile,solver_options)
    try
        t=@timed build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer);b=t.value
        start_report=nothing
        if initial_point!==nothing
            encoded=ivr_nlp_point_report(b,initial_point)
            isempty(encoded.missing_channels) && length(encoded.variable_values)==num_variables(b.model) &&
                max(encoded.max_binding_residual_pu,encoded.max_reconstruction_residual_pu)<=1e-10 ||
                error("shared physical start is not representable in this profile")
            for (variable,value) in encoded.variable_values
                isfinite(value) || error("nonfinite shared start")
                set_start_value(variable,value)
            end
            start_report=(;encoded_variables=length(encoded.variable_values),
                max_binding_residual_pu=encoded.max_binding_residual_pu,
                max_reconstruction_residual_pu=encoded.max_reconstruction_residual_pu,
                max_constraint_violation=encoded.max_constraint_violation)
        end
        s=@timed solve_ivr_nlp_opf(b;solver_options=settings);r=s.value
        p=r.solve.optimal ? ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate) : nothing
        physical=p===nothing ? nothing : physical_residuals(net,r)
        own=p===nothing ? nothing : ivr_nlp_point_report(b,p)
        full=p===nothing ? nothing : ivr_nlp_point_report(reference,p)
        reverse=anchor===nothing ? nothing : ivr_nlp_point_report(b,anchor).passed
        physical_objective=p===nothing || profile.options.objective!=:power ? nothing :
            sum(profile.options.power_terms) do term
                residual=sum(w*(term.quantity==:p ? real(r.powers[(f,id)][k]) : imag(r.powers[(f,id)][k]))
                    for ((f,id,k),w) in zip(term.channels,term.weights))-term.target
                term.linear*residual+term.quadratic*residual^2
            end
        accepted=p!==nothing && physical.passed && own.passed && full.passed && reverse!==false &&
            isfinite(r.objective) && isapprox(own.objective,full.objective;atol=1e-6,rtol=1e-8) &&
            (physical_objective===nothing || isapprox(r.objective,physical_objective;atol=1e-6,rtol=1e-8))
        row=Dict{String,Any}("build_s"=>t.time,"build_bytes"=>t.bytes,"build_gc_s"=>t.gctime,
            "ipopt_wall_s"=>JuMP.solve_time(b.model),
            "solve_s"=>s.time,"solve_bytes"=>s.bytes,"solve_gc_s"=>s.gctime,"status"=>r.solve.termination_status,
            "accepted"=>accepted,"physical_passed"=>(p!==nothing&&physical.passed),
            "own_model_passed"=>(p!==nothing&&own.passed),"full_model_passed"=>(p!==nothing&&full.passed),
            "anchor_in_profile"=>reverse,"objective"=>(isfinite(r.objective) ? r.objective : nothing),
            "physical_power_objective"=>physical_objective,
            "variables"=>num_variables(b.model),"derivatives"=>feeder_derivative_structure(b.model),
            "shared_start"=>start_report,"lifted_real_variables"=>b.numerical_diagnostics[:lifted_real_variables],
            "shared_observation_count"=>b.numerical_diagnostics[:shared_observation_count],
            "observation_sharing_report"=>b.numerical_diagnostics[:observation_sharing_report],
            "generator_s_max_slack_VA"=>(p===nothing ? nothing : Dict(id=>d["s_max"].-abs.(r.powers[(:generator,id)])
                for (id,d) in get(net,"generator",Dict()) if haskey(d,"s_max"))),
            "vpn_max_slack_V"=>(p===nothing ? nothing : Dict(bus=>d["vpn_max"].-abs.([p.voltage[(bus,t)]-p.voltage[(bus,b.electrical.neutral_map[bus])]
                for t in d["terminal_names"] if t!=b.electrical.neutral_map[bus]])
                for (bus,d) in net["bus"] if haskey(d,"vpn_max") && haskey(b.electrical.neutral_map,bus))),
            "vpn_min_slack_V"=>(p===nothing ? nothing : Dict(bus=>abs.([p.voltage[(bus,t)]-p.voltage[(bus,b.electrical.neutral_map[bus])]
                for t in d["terminal_names"] if t!=b.electrical.neutral_map[bus]]).-d["vpn_min"]
                for (bus,d) in net["bus"] if haskey(d,"vpn_min") && haskey(b.electrical.neutral_map,bus))),
            "specialization"=>b.numerical_diagnostics[:specialization],
            "specialization_report"=>b.numerical_diagnostics[:specialization_report],
            "elimination"=>b.numerical_diagnostics[:linear_elimination_report],
            "device_elimination"=>b.numerical_diagnostics[:device_elimination_report],
            "ground_scaling"=>b.numerical_diagnostics[:ground_scaling_report],
            "transformer_scaling"=>b.numerical_diagnostics[:transformer_scaling_report],
            "row_scaling"=>b.numerical_diagnostics[:row_scaling],
            "composed_row_normalization"=>b.numerical_diagnostics[:composed_row_normalization],
            "per_unit_bases"=>b.numerical_diagnostics[:per_unit_bases],
            "objective_scale"=>b.numerical_diagnostics[:objective_scale],
            "generator_power_bases"=>b.numerical_diagnostics[:generator_power_bases],
            "lifted_power_base"=>b.numerical_diagnostics[:lifted_power_base],
            "power_sharing"=>b.numerical_diagnostics[:power_sharing],
            "reused_generator_power_count"=>b.numerical_diagnostics[:reused_generator_power_count],
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

`checkpoint=:trial` retains legacy per-trial reports; `:sweep` saves every
completed measured sweep, retaining all rows while avoiding repeated large-file
writes. Warm-ups still save individually. An interrupted sweep may have unsaved
rows; checkpoint frequency is outside the solver timer.

Primary ranking uses `ipopt_wall_s`, obtained from `JuMP.solve_time`; model
construction does not enter that ranking. Warm-ups are excluded. Four or more rotated/reversed sweeps are exploratory,
not a fully position-balanced design. Confirm a chosen profile with fresh paired
measurements. All electrical inputs/objectives are retained. The solve-only
ranking excludes construction but does not measure updated-model reuse.
"""
function benchmark(net,output;repetitions=4,candidates=profiles(),solver_options=STRICT,source_sha256=nothing,initial_point=nothing,trial_orders=nothing,checkpoint=:trial)
    checkpoint in (:trial,:sweep) || throw(ArgumentError("checkpoint must be :trial or :sweep"))
    started=time_ns()
    repetitions>0 || throw(ArgumentError("positive repetitions required"))
    !isempty(candidates) && allunique(p.name for p in candidates) || throw(ArgumentError("unique nonempty profiles required"))
    orders=trial_orders===nothing ? [iseven(rep) ? reverse(circshift(collect(eachindex(candidates)),(rep-1)÷2)) :
        circshift(collect(eachindex(candidates)),(rep-1)÷2) for rep in 1:repetitions] : deepcopy(trial_orders)
    length(orders)==repetitions && all(order->order isa AbstractVector &&
        all(i->i isa Integer && !(i isa Bool),order) && sort(order)==collect(eachindex(candidates)),orders) ||
        throw(ArgumentError("trial_orders must contain one complete candidate-index permutation per repetition"))
    objective=first(candidates).options.objective
    all(p.options.objective==objective for p in candidates) || throw(ArgumentError("profiles must share an objective"))
    terms=first(candidates).options.power_terms
    # Compare the complete physical definition, not just the :power mode label.
    all(JSON3.write(p.options.power_terms)==JSON3.write(terms) for p in candidates) ||
        throw(ArgumentError("profiles must share power objective terms"))
    nameplate=first(candidates).options.transformer_nameplate
    all(p.options.transformer_nameplate==nameplate for p in candidates) ||
        throw(ArgumentError("profiles must share transformer nameplate bounds"))
    reference=build_opf(net,IVRNLP(;objective,power_terms=terms,transformer_nameplate=nameplate))
    rows=[Dict{String,Any}("name"=>p.name,"formulation_name"=>get(p,:formulation_name,p.name),
        "options"=>option_record(p.options),"solver_options"=>profile_solver_options(p,solver_options),
        "warmup"=>nothing,"trials"=>[]) for p in candidates]
    report=Dict{String,Any}("profiles"=>rows,"repetitions"=>repetitions,"objective"=>objective,
        "source_sha256"=>source_sha256,"network_sha256"=>bytes2hex(sha256(JSON3.write(net))),
        "reference_transformer_nameplate"=>string(nameplate),
        "julia"=>string(VERSION),"jump"=>string(pkgversion(JuMP)),"ipopt"=>string(pkgversion(Ipopt)),
        "cpu"=>Sys.CPU_NAME,"blas_threads"=>BLAS.get_num_threads(),"julia_threads"=>Threads.nthreads(),
        "solver_options"=>solver_options,"runner_sha256"=>RUNNER_SHA,"orders"=>[],
        "primary_metric"=>"ipopt_wall_s",
        "shared_physical_start"=>initial_point!==nothing,"checkpoint"=>string(checkpoint),
        "timing_contract"=>"MOI.SolveTimeSec from Ipopt.jl: wall time of its optimizer call, including backend setup and native IpoptSolve; excludes FormulationLab build, JuMP cache transfer before the backend call, result extraction and physical/model audits. build_s and solve_s (wrapper plus extraction) are secondary diagnostics only.",
        "note"=>"Exploratory shortlist; no universal fastest claim. Primary ranking uses Ipopt wall time; build and solve/extraction timings are retained as secondary diagnostics. All timings exclude audits and warm-ups. Rejected/error trials retained. Unchanged electrical data and explicit shared objective. A first accepted warm-up supplies the full-feasible anchor for reverse mapping. Confirm winners independently; rankings do not measure parameter-update reuse.")
    save()=open(io->JSON3.write(io,report),output,"w")
    anchor=nothing
    for (j,p) in enumerate(candidates)
        row,point=trial(net,p,reference,anchor;solver_options,initial_point);rows[j]["warmup"]=row
        if anchor===nothing && row["accepted"];anchor=point;report["anchor_profile"]=p.name;end
        save()
    end
    for rep in 1:repetitions
        order=orders[rep]
        push!(report["orders"],[candidates[j].name for j in order])
        for j in order
            row,_=trial(net,candidates[j],reference,anchor;solver_options,initial_point)
            anchor===nothing && (row["accepted"]=false)
            push!(rows[j]["trials"],row);checkpoint==:trial && save()
        end
        checkpoint==:sweep && save()
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
