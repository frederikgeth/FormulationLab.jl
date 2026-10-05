# Controlled model-reuse and primal-initialization study; no default changes.
module IVRReuseStudy
using FormulationLab, JuMP, Ipopt, JSON3, SHA, LinearAlgebra, Statistics
include("benchmark_ivr_profiles.jl")
include("ivr_dual_starts.jl")
const P=IVRProfileStudy
const RUNNER_SHA=bytes2hex(sha256(read(@__FILE__)))
const SETTINGS=merge(P.STRICT,(linear_solver="mumps",mumps_pivot_order=0,warm_start_init_point="no"))

"""Fresh/reused crossed with fixed/previous-primal starts, for every profile."""
function workflows(;profiles=P.profiles(objective=:cost)[[1,10]])
    [(;name="$(p.name)__$(reuse ? "reuse" : "fresh")__$(start)",profile=p,reuse,start)
        for p in profiles for reuse in (false,true) for start in (:fixed,:previous_primal)]
end

# Shared controls for the *separate* reconstructed-dual experiment. The zero-dual
# arm distinguishes the warm initializer from information in carried multipliers.
const DUAL_CONTROLS=(fixed_variable_treatment="make_parameter",warm_start_same_structure="no",
    mu_strategy="monotone",mu_init=.1,warm_start_bound_push=.001,warm_start_bound_frac=.001,
    warm_start_slack_bound_push=.001,warm_start_slack_bound_frac=.001,warm_start_mult_bound_push=.001)
function dual_workflows(;profiles=P.profiles(objective=:cost)[[1,10]])
    [(;name="$(p.name)__reuse__$(start)",
        profile=merge(p,(solver_options=merge(P.solver_option_dict(get(p,:solver_options,(;))),
            P.solver_option_dict(DUAL_CONTROLS)),)),reuse=true,start)
     for p in profiles for start in (:previous_primal,:zero_dual,:reconstructed_dual)]
end

"""Independent cumulative scenario data, without using the model update API."""
function scenario_inputs(net,schedule)
    current=deepcopy(net);inputs=Any[]
    for step in schedule
        for (id,u) in step.loads
            Set(keys(u))==Set((:p,:q)) || throw(ArgumentError("load update needs p and q"))
            d=current["load"][id]
            lowercase(get(d,"model","constant_power"))=="constant_power" ||
                throw(ArgumentError("only constant-power updates are supported"))
            d["p_nom"]=copy(u.p);d["q_nom"]=copy(u.q)
        end
        for (id,u) in step.generators
            d=current["generator"][id]
            for (field,value) in pairs(u)
                field in (:p_min,:p_max,:q_min,:q_max,:cost) || throw(ArgumentError("unsupported generator update"))
                if value===nothing
                    field==:cost && throw(ArgumentError("price cannot be removed"))
                    pop!(d,string(field),nothing)
                else
                    d[string(field)]=copy(value)
                    field==:cost && haskey(d,"energy_cost_rate") && (d["energy_cost_rate"]=copy(value))
                end
            end
        end
        push!(inputs,deepcopy(current))
    end
    inputs
end

start_digest(names,values)=bytes2hex(sha256(JSON3.write((;names,values))))
function set_starts!(variables,values)
    length(variables)==length(values) || throw(ArgumentError("start layout changed"))
    all(x->x===nothing || isfinite(x),values) || throw(ArgumentError("nonfinite start"))
    for (v,x) in zip(variables,values);set_start_value(v,x);end
end

function sequence(net,schedule,inputs,references,anchors,workflow;solver_options=SETTINGS)
    rows=Any[];points=Any[];previous=nothing;dual_cache=nothing;build=nothing;builds=0
    dual_policy=workflow.start in (:zero_dual,:reconstructed_dual)
    dual_policy && !workflow.reuse && throw(ArgumentError("dual transfer requires the same reused model"))
    initial=@timed build_opf(net,IVRNLP(workflow.profile.options);optimizer=Ipopt.Optimizer)
    origin=initial.value;variables=all_variables(origin.model);names=name.(variables)
    allunique(names) || error("unique variable names required for start-layout verification")
    fixed=start_value.(variables);build=workflow.reuse ? origin : nothing
    builds=workflow.reuse ? 1 : 0
    settings=P.profile_solver_options(workflow.profile,solver_options)
    get(settings,"warm_start_init_point",nothing)=="no" ||
        throw(ArgumentError("first solve must use warm_start_init_point=no; policy controls later solves"))
    if dual_policy
        all(get(settings,string(k),nothing)==v for (k,v) in pairs(DUAL_CONTROLS)) ||
            throw(ArgumentError("dual experiment requires its declared shared controls"))
    end
    for (k,step) in enumerate(schedule)
        try
            prep=@timed if workflow.reuse
                update_ivr_loads!(build,step.loads)
                update_ivr_generators!(build,step.generators)
                build
            else
                build_opf(inputs[k],IVRNLP(workflow.profile.options);optimizer=Ipopt.Optimizer)
            end
            build=prep.value;builds+=!workflow.reuse
            vars=all_variables(build.model)
            name.(vars)==names || error("fresh/reused coordinate layout changed")
            workflow.reuse && vars!=variables && error("reused variable identity changed")
            seed=workflow.start!=:fixed && previous!==nothing ? previous : fixed
            startprep=@timed set_starts!(vars,seed)
            starts=start_value.(vars)
            starts==seed || error("submitted starts differ from declared policy")
            dual_prep=@timed (dual_policy && dual_cache!==nothing ? IVRDualStarts.apply!(build,dual_cache;
                mode=workflow.start==:zero_dual ? :zero : :reconstructed) : nothing)
            effective=merge(settings,Dict("warm_start_init_point"=>(dual_policy && dual_cache!==nothing ? "yes" : "no")))
            solve=@timed solve_ivr_nlp_opf(build;solver_options=effective);r=solve.value
            point=r.solve.optimal ? ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate) : nothing
            physical=point===nothing ? nothing : physical_residuals(inputs[k],r)
            own=point===nothing ? nothing : ivr_nlp_point_report(build,point)
            full=point===nothing ? nothing : ivr_nlp_point_report(references[k],point)
            # Independent fresh model of this formulation catches stale updates.
            fresh=build_opf(inputs[k],IVRNLP(workflow.profile.options))
            mapped=point===nothing ? nothing : ivr_nlp_point_report(fresh,point)
            reverse=anchors[k]===nothing ? nothing : ivr_nlp_point_report(build,anchors[k]).passed
            values=point===nothing ? nothing : value.(vars)
            accepted=point!==nothing && physical.passed && own.passed && full.passed && mapped.passed &&
                reverse!==false && all(isfinite,values) && isfinite(r.objective) &&
                isapprox(r.objective,full.objective;atol=1e-6,rtol=1e-8) &&
                isapprox(own.objective,mapped.objective;atol=1e-6,rtol=1e-8)
            captured=accepted && dual_policy ? IVRDualStarts.capture(build) : nothing
            row=Dict{String,Any}("scenario"=>k,"label"=>step.label,"accepted"=>accepted,
                "ipopt_wall_s"=>JuMP.solve_time(build.model),"solve_extract_s"=>solve.time,
                "solve_gc_s"=>solve.gctime,"preparation_s"=>prep.time,"preparation_bytes"=>prep.bytes,
                "start_preparation_s"=>startprep.time,"dual_preparation_s"=>dual_prep.time,
                "dual_start"=>dual_prep.value,"dual_solution_sha256"=>(captured===nothing ? nothing : captured.sha256),
                "effective_solver_options"=>effective,"status"=>r.solve.termination_status,
                "objective"=>(isfinite(r.objective) ? r.objective : nothing),
                "physical_passed"=>(point!==nothing && physical.passed),
                "own_passed"=>(point!==nothing && own.passed),"full_passed"=>(point!==nothing && full.passed),
                "fresh_same_formulation_passed"=>(point!==nothing && mapped.passed),"anchor_passed"=>reverse,
                "start_source"=>(seed===previous ? "previous_primal" : "fixed"),
                "start_sha256"=>start_digest(names,starts),"solution_sha256"=>(values===nothing ? nothing : start_digest(names,values)),
                "start_matches_policy"=>true,"variables"=>length(vars),
                "variable_identity_preserved"=>(!workflow.reuse || vars==variables),
                "assembly_count"=>build.numerical_diagnostics[:assembly_count],
                "update_count"=>build.numerical_diagnostics[:update_count],
                "generator_update_count"=>build.numerical_diagnostics[:generator_update_count],
                "iterations"=>JuMP.MOI.get(JuMP.backend(build.model),JuMP.MOI.BarrierIterations()),
                "bad_physical_records"=>(point===nothing ? [] : [(;label=x.label,residual=x.residual,unit=x.unit)
                    for x in physical.records if x.residual>getproperty(physical.tolerances,x.unit)]))
            push!(rows,row);push!(points,point)
            accepted || break # Preserve incomplete batches; no repaired retry.
            previous=values;dual_cache=captured
        catch err
            err isa InterruptException && rethrow()
            push!(rows,Dict("scenario"=>k,"label"=>step.label,"accepted"=>false,"error"=>sprint(showerror,err)))
            push!(points,nothing);break
        end
    end
    complete=length(rows)==length(schedule) && all(r->r["accepted"],rows)
    Dict{String,Any}("accepted"=>complete,"requested_N"=>length(schedule),"completed_N"=>length(rows),
        "scenario_model_builds"=>builds,"start_template_build_s"=>initial.time,"scenarios"=>rows,
        "solver_options"=>settings,"total_ipopt_wall_s"=>(complete ? sum(r["ipopt_wall_s"] for r in rows) : nothing)),points
end

function rank_workflows(rows,repetitions,n;atol=1e-6,rtol=1e-8)
    eligible=[r for r in rows if r["warmup"]["accepted"] && length(r["trials"])==repetitions &&
        all(t->t["accepted"] && length(t["scenarios"])==n && all(P.valid_ipopt_time,t["scenarios"]),r["trials"])]
    comparable=!isempty(eligible)
    by_scenario=Bool[]
    for k in 1:n
        objectives=[t["scenarios"][k]["objective"] for r in eligible for t in r["trials"]]
        ok=!isempty(objectives) && all(isfinite,objectives) &&
            all(v->isapprox(v,minimum(objectives);atol,rtol),objectives)
        push!(by_scenario,ok);comparable &= ok
    end
    ranking=[Dict("name"=>r["name"],"median_sequence_ipopt_s"=>median(t["total_ipopt_wall_s"] for t in r["trials"]),
        "median_scenario_ipopt_s"=>[median(t["scenarios"][k]["ipopt_wall_s"] for t in r["trials"]) for k in 1:n]) for r in eligible]
    sort!(ranking;by=r->(r["median_sequence_ipopt_s"],r["name"]))
    Dict("eligible"=>ranking,"objective_comparable"=>comparable,"scenario_objective_comparable"=>by_scenario,
        "fastest_ipopt"=>(comparable ? first(ranking)["name"] : nothing),"objective_atol"=>atol,"objective_rtol"=>rtol)
end

"""Benchmark complete ordered sequences with explicit initialization policies.

Rank the median sum of Ipopt wall seconds in a sequence. Construction, updates,
start assignment, extraction and audits are outside this score. Every repeated
sequence starts independently; previous primals never cross repetitions.
"""
function benchmark(net,schedule,output;repetitions=4,candidates=workflows(),solver_options=SETTINGS,source_sha256=nothing)
    !isempty(schedule) && repetitions>0 || throw(ArgumentError("nonempty schedule and positive repetitions required"))
    !isempty(candidates) && allunique(w.name for w in candidates) || throw(ArgumentError("unique workflows required"))
    all(w->w.start in (:fixed,:previous_primal,:zero_dual,:reconstructed_dual),candidates) || throw(ArgumentError("unknown start policy"))
    any(w->w.start in (:zero_dual,:reconstructed_dual) && !w.reuse,candidates) &&
        throw(ArgumentError("dual transfer requires reused models"))
    objective=first(candidates).profile.options.objective
    all(w->w.profile.options.objective==objective,candidates) || throw(ArgumentError("shared objective required"))
    inputs=scenario_inputs(net,schedule)
    refs=[build_opf(x,IVRNLP(;objective)) for x in inputs]
    anchors=Any[nothing for _ in inputs]
    rows=[Dict{String,Any}("name"=>w.name,"profile"=>w.profile.name,"reuse"=>w.reuse,"start"=>w.start,
        "options"=>P.option_record(w.profile.options),"warmup"=>nothing,"trials"=>[]) for w in candidates]
    report=Dict{String,Any}("profiles"=>rows,"schedule"=>schedule,"repetitions"=>repetitions,"orders"=>[],
        "primary_metric"=>"median_sequence_ipopt_s","solver_options"=>solver_options,"source_sha256"=>source_sha256,
        "network_sha256"=>bytes2hex(sha256(JSON3.write(net))),"scenario_sha256"=>[bytes2hex(sha256(JSON3.write(x))) for x in inputs],
        "dual_helper_sha256"=>IVRDualStarts.SOURCE_SHA,"runner_sha256"=>RUNNER_SHA,"profile_runner_sha256"=>P.RUNNER_SHA,"julia"=>string(VERSION),
        "jump"=>string(pkgversion(JuMP)),"ipopt"=>string(pkgversion(Ipopt)),"cpu"=>Sys.CPU_NAME,
        "julia_threads"=>Threads.nthreads(),"blas_threads"=>BLAS.get_num_threads(),
        "note"=>"Complete ordered sequences only. Compare objectives within each scenario, not across changing prices/demand. Fixed starts reset explicitly; previous_primal carries every named variable from the preceding accepted scenario in the same workflow/repetition. Default workflows have no dual starts. Explicit zero_dual/reconstructed_dual policies use the normal initializer first and warm_start_init_point=yes thereafter; effective per-scenario settings and dual reset/digest evidence are recorded. Reconstructed bound duals are not both native multipliers. No construction/update/extraction penalty in ranking. Failed/incomplete sequences retained, no repair. JuMP model reuse does not imply native factorization reuse.")
    save()=open(io->JSON3.write(io,report),output,"w")
    for (j,w) in enumerate(candidates)
        t,points=sequence(net,schedule,inputs,refs,anchors,w;solver_options);rows[j]["warmup"]=t
        if t["accepted"] && all(isnothing,anchors);anchors=points;report["anchor_workflow"]=w.name;end
        save()
    end
    for rep in 1:repetitions
        order=circshift(collect(eachindex(candidates)),(rep-1)÷2);iseven(rep) && reverse!(order)
        push!(report["orders"],[candidates[j].name for j in order])
        for j in order
            t,_=sequence(net,schedule,inputs,refs,anchors,candidates[j];solver_options)
            any(isnothing,anchors) && (t["accepted"]=false)
            push!(rows[j]["trials"],t);save()
        end
    end
    report["ranking"]=rank_workflows(rows,repetitions,length(schedule));save();report
end
end
