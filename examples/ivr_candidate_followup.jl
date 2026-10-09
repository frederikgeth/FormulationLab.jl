"""Finite correctness follow-up for three exact candidates and a two-value pivot.

This module declares paired configurations and executes correctness checks only.
It never measures/ranks wall time or authorizes a timing campaign. A calling study
must freeze code, complete plans and original evidence before external execution.
"""
module IVRCandidateFollowup
using FormulationLab, JSON3, JuMP
include("ivr_transfer_preflight.jl")
const P=IVRTransferPreflight
const WORKLOADS=("quadratic_cost","exchange_tracking")
const PROFILES=Set(["full_powers";["$(d)__$(l)__zero_$(z)" for d in ("off","transformer_currents")
    for l in ("powers","bounded_observations") for z in ("false","true")]])
const GATES=("accepted","complete_declared_bound_coverage","complete_emitted_coverage",
    "start_representable","physical_passed","own_model_passed","full_model_passed",
    "objective_reconciled","native_reader_equal","physical_export_shape_equal")

"""Audit baseline admission, not execution eligibility or a physical certificate.

The caller must authenticate report bytes and preparation provenance separately.
Missing/refused/failed/incomplete outcomes remain explicit, never replacements.
Preparation-ready failures still belong in the follow-up robustness experiment.
"""
function admission(report)
    get(report,"schema",nothing)=="FormulationLab.transfer_preflight.v1" ||
        return (;eligible=false,reason="unknown_report_schema")
    haskey(report,"preparation_refusal") && return (;eligible=false,reason="preparation_refused")
    get(report,"pending_trial",nothing)===nothing || return (;eligible=false,reason="baseline_running")
    trials=get(report,"trials",Any[])
    trials isa AbstractVector && all(t->t isa AbstractDict,trials) || return (;eligible=false,reason="incomplete_baseline")
    expected=Set((w,p) for w in WORKLOADS for p in PROFILES)
    length(trials)==18 && Set((get(t,"workload",nothing),get(t,"profile",nothing)) for t in trials)==expected ||
        return (;eligible=false,reason="incomplete_baseline")
    get(report,"inputs_unchanged",false)===true || return (;eligible=false,reason="input_verification_failed")
    all(t->all(k->get(t,k,false)===true,GATES) && get(t,"anchor_in_profile",nothing)!==false,trials) ||
        return (;eligible=false,reason="baseline_correctness_failed")
    get(report,"all_trials_accepted",false)===true && get(report,"objectives_comparable",false)===true ||
        return (;eligible=false,reason="baseline_comparison_failed")
    for w in WORKLOADS
        rows=filter(t->t["workload"]==w,trials);a=get(first(rows),"objective",nothing)
        all(t->P.W.finite_real(get(t,"objective",nothing)) && isapprox(t["objective"],a;
            atol=P.TOLERANCES.objective_atol,rtol=P.TOLERANCES.objective_rtol),rows) ||
            return (;eligible=false,reason="baseline_objectives_differ")
    end
    (;eligible=true,reason="complete_baseline_correctness")
end

"""Explicit one-field schema migration; unknown/missing older fields are refused."""
function migrate_options(raw)
    d=deepcopy(raw);current=Set(string.(fieldnames(IVRNLPOptions)))
    old=setdiff(current,Set(["fixed_bound_elimination"]))
    Set(keys(d))==old && (d["fixed_bound_elimination"]=false)
    Set(keys(d))==current || throw(ArgumentError("unrecognized option schema"))
    d["fixed_bound_elimination"]===false || throw(ArgumentError("baseline already enables the candidate"))
    P.read_options(d);d
end
function candidate_pairs(workload,settings)
    workload["kind"] in WORKLOADS || throw(ArgumentError("unknown power workload"))
    candidates=workload["candidates"]
    length(candidates)==9 && Set(p["name"] for p in candidates)==PROFILES || throw(ArgumentError("complete nine-arm baseline required"))
    byname=Dict(p["name"]=>migrate_options(p["options"]) for p in candidates)
    base=byname["full_powers"];reference=migrate_options(workload["reference"])
    base["lifting"]=="powers" && base["specialization"]==base["linear_elimination"]==base["device_elimination"]=="off" &&
        base["zero_load_elimination"]===false || throw(ArgumentError("full control profile changed"))
    for (name,o) in byname
        name=="full_powers" && continue
        d,l,z=split(name,"__")
        o["device_elimination"]==d && o["lifting"]==l && o["zero_load_elimination"]==endswith(z,"true") &&
            o["linear_elimination"]=="passive_blocks" && o["specialization"]=="conductor_regions" ||
            throw(ArgumentError("factorial profile changed"))
    end
    base["objective"]==reference["objective"]=="power" || throw(ArgumentError("power objective required"))
    all(o->o["power_terms"]==base["power_terms"],values(byname)) && reference["power_terms"]==base["power_terms"] ||
        throw(ArgumentError("baseline objective definitions differ"))
    P.solver_settings(settings)==Dict(string(k)=>v for (k,v) in Base.pairs(P.SETTINGS)) ||
        throw(ArgumentError("frozen strict control settings required"))
    result=Any[]
    function add(name,original,common,a,b;pivot=false)
        control=merge(deepcopy(original),deepcopy(common),deepcopy(a))
        candidate=merge(deepcopy(original),deepcopy(common),deepcopy(b))
        P.read_options(control);P.read_options(candidate)
        sc=deepcopy(settings);st=deepcopy(settings);pivot && (st["mumps_pivtol"]=1e-3)
        push!(result,Dict("name"=>name,"workload"=>workload["kind"],"reference"=>reference,
            "control"=>Dict("name"=>"control","options"=>control),
            "candidate"=>Dict("name"=>"candidate","options"=>candidate),
            "control_solver"=>sc,"candidate_solver"=>st,"timing_eligible"=>false))
    end
    empty=Dict{String,Any}()
    add("fixed_powers",base,empty,Dict("fixed_bound_elimination"=>false),Dict("fixed_bound_elimination"=>true))
    add("fixed_broad_inline",base,Dict("lifting"=>"bounded_observations","fixed_observation_elimination"=>true),
        Dict("fixed_bound_elimination"=>false),Dict("fixed_bound_elimination"=>true))
    add("complex_sharing",base,Dict("lifting"=>"bounded_observations","fixed_observation_elimination"=>false),
        Dict("observation_sharing"=>"proportional"),Dict("observation_sharing"=>"complex_proportional"))
    add("expression_support",base,Dict("linear_elimination"=>"passive_blocks"),
        Dict("series_selection"=>"bound_support"),Dict("series_selection"=>"expression_support"))
    for d in ("off","transformer_currents")
        add("pivot_"*d,byname[d*"__powers__zero_true"],empty,empty,empty;pivot=true)
    end
    result
end

"""Execute one frozen pair from a common SI start; no timing admission is implied."""
function run_pair(net,start,pair,tolerances,folder)
    a=pair["control"]["options"];b=pair["candidate"]["options"];ref=pair["reference"]
    all(o->o["objective"]=="power" && o["power_terms"]==ref["power_terms"],(a,b,ref)) ||
        throw(ArgumentError("pair objective semantics differ"))
    name=pair["name"]
    change=name in ("fixed_powers","fixed_broad_inline") ? "fixed_bound_elimination" :
        name=="complex_sharing" ? "observation_sharing" : name=="expression_support" ? "series_selection" :
        name in ("pivot_off","pivot_transformer_currents") ? nothing : throw(ArgumentError("unknown contrast"))
    Set(keys(a))==Set(keys(b)) && Set(k for k in keys(a) if a[k]!=b[k])==
        (change===nothing ? Set{String}() : Set([change])) || throw(ArgumentError("confounded option contrast"))
    if change!==nothing
        values=name in ("fixed_powers","fixed_broad_inline") ? (false,true) :
            name=="complex_sharing" ? ("proportional","complex_proportional") :
            ("bound_support","expression_support")
        (a[change],b[change])==values || throw(ArgumentError("reversed or undeclared contrast values"))
    end
    sc=P.solver_settings(pair["control_solver"]);st=P.solver_settings(pair["candidate_solver"])
    sc==Dict(string(k)=>v for (k,v) in Base.pairs(P.SETTINGS)) || throw(ArgumentError("control solver settings changed"))
    expected=copy(sc);change===nothing && (expected["mumps_pivtol"]=1e-3)
    st==expected || throw(ArgumentError("confounded solver contrast"))
    P.newfolder(folder)
    reference=build_opf(net,IVRNLP(P.read_options(pair["reference"])))
    control,cp,cs=P.trial(net,pair["control"],reference,start,nothing,
        joinpath(folder,"control"),pair["control_solver"],tolerances;save_failed_primal=true)
    P.save(joinpath(folder,"control.trial.json"),control)
    candidate,tp,ts=P.trial(net,pair["candidate"],reference,start,control["accepted"] ? cp : nothing,
        joinpath(folder,"candidate"),pair["candidate_solver"],tolerances;save_failed_primal=true)
    P.save(joinpath(folder,"candidate.trial.json"),candidate)
    reverse=false;reverse_error=nothing
    if candidate["accepted"]
        try
            cb=build_opf(net,IVRNLP(P.read_options(pair["control"]["options"])))
            reverse=ivr_nlp_point_report(cb,tp;atol=tolerances["model_pu"]).passed
        catch err
            err isa InterruptException && rethrow()
            reverse_error=sprint(showerror,err)
        end
    end
    shape=control["accepted"] && candidate["accepted"] && isequal(cs,ts)
    comparable=control["accepted"] && candidate["accepted"] && reverse && shape &&
        isapprox(control["objective"],candidate["objective"];atol=tolerances["objective_atol"],rtol=tolerances["objective_rtol"])
    report=Dict("schema"=>"FormulationLab.candidate_pair_correctness.v1","name"=>pair["name"],"workload"=>pair["workload"],
        "control"=>control,"candidate"=>candidate,"candidate_in_control"=>reverse,"reverse_check_error"=>reverse_error,
        "physical_export_shape_equal"=>shape,"correctness_admitted"=>comparable,
        "timing_eligible"=>false,"ranking"=>nothing)
    P.save(joinpath(folder,"REPORT.json"),report);report
end
end
