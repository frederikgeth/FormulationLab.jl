"""Solve-time topology reduction. `:bmopf` mirrors BMOPFTools' simplification
policies; `:off` makes an independent snapshot. Intermediate bus bounds are
retained by default. π length aggregation and stub/switch removal can be approximate.
"""
Base.@kwdef struct ReductionOptions
    profile::Symbol = :bmopf
    open_switches::Bool = true
    closed_switches::Bool = true
    dangling_lines::Bool = true
    series_lines::Bool = true
    series_merge_policy::Symbol = :allow_approximate
    allow_drop_bus_constraints::Bool = false
end

"""Versioned, solver-independent reduction provenance. Original SI data is retained."""
struct ReductionPlan
    version::Int
    original::Dict{String,Any}
    events::Vector{Any}
    bus_alias::Dict{String,String}
    options::ReductionOptions
end

"""Reduced compile target shared by all formulations, with its reconstruction plan.
Treat the contents as immutable; prepare again after changing topology/parameters.
"""
struct PreparedNetwork
    network::Dict{String,Any}
    plan::ReductionPlan
end
_l3f_input(p::PreparedNetwork) = _l3f_input(p.network)

"""Prepare a private network snapshot; never mutates the input or imports BMOPFTools."""
function prepare_network(input; reduction=ReductionOptions(), warn::Bool=true)
    options = reduction isa Symbol ? ReductionOptions(profile=reduction) : reduction
    options isa ReductionOptions || throw(ArgumentError("reduction must be a Symbol or ReductionOptions"))
    options.profile in (:off,:bmopf) || throw(ArgumentError("reduction profile must be :off or :bmopf"))
    options.series_merge_policy in (:off,:exact,:allow_approximate) || throw(ArgumentError("invalid series merge policy"))
    original = _l3f_input(input); net = deepcopy(original)
    # Provenance is kept outside the compile target; existing upstream logs are
    # retained only in the original snapshot, never mistaken for this pass.
    net["_simplification_log"] = Any[]
    if options.profile != :off
        isempty(get(net,"time_series",Dict())) || throw(ArgumentError("reduce a resolved static snapshot, not time_series data"))
        options.closed_switches && _BMOPFReduction._collapse_closed_switches!(net)
        options.open_switches && _BMOPFReduction._remove_open_switches!(net)
        options.dangling_lines && _BMOPFReduction._remove_dangling_lines!(net)
        options.series_lines && _BMOPFReduction._merge_series_lines!(net;
            series_merge_policy=options.series_merge_policy,
            allow_drop_bus_constraints=options.allow_drop_bus_constraints)
    end
    events = pop!(net,"_simplification_log")
    for e in copy(events)
        e["code"]=="LINE_REMOVED" || continue
        bus=e["detail"]["removed_bus"]
        fields=filter(k->endswith(k,"_min") || endswith(k,"_max"),collect(keys(original["bus"][bus])))
        isempty(fields) || push!(events,Dict("code"=>"BOUND_DROPPED","operation"=>"remove_dangling_lines",
            "severity"=>"warning","element_type"=>"bus","element_id"=>bus,
            "message"=>"Pruned leaf bus operating bounds; checked on reconstructed state", "detail"=>Dict("fields"=>fields)))
    end
    aliases = Dict{String,String}()
    for e in events
        e["code"] == "SWITCH_COLLAPSED" || continue
        d=e["detail"];aliases[d["bus_to_absorbed"]]=d["bus_from"]
    end
    for b in keys(aliases)
        t=aliases[b]
        while haskey(aliases,t);t=aliases[t];end
        aliases[b]=t
    end
    for l in values(get(net,"line",Dict()));pop!(l,"_merged_from",nothing);end
    prepared=PreparedNetwork(net,ReductionPlan(1,original,events,aliases,options))
    report=reduction_report(prepared)
    warn && report["approximate"] && @warn "Approximate network reduction; original-network reconstruction and diagnostics are available" buses_before=report["buses_before"] buses_after=report["buses_after"] approximation_events=report["approximation_events"]
    prepared
end

"""Compact counts and structured approximation events for a prepared network."""
function reduction_report(p::PreparedNetwork)
    approximate=filter(e->e["code"] in ("SERIES_MERGE_APPROXIMATE","SHUNT_DROPPED","BOUND_DROPPED","SWITCH_LIMIT_DROPPED"),p.plan.events)
    # Pruning also discards leaf operating limits, even with no π shunt.
    removed=Set(setdiff(keys(p.plan.original["bus"]),keys(p.network["bus"])))
    bounded=[b for b in removed if any(endswith(k,"_min") || endswith(k,"_max") for k in keys(p.plan.original["bus"][b]))]
    Dict{String,Any}("buses_before"=>length(p.plan.original["bus"]),"buses_after"=>length(p.network["bus"]),
        "lines_before"=>length(get(p.plan.original,"line",Dict())),"lines_after"=>length(get(p.network,"line",Dict())),
        "approximate"=>!isempty(approximate),"approximation_events"=>length(approximate),
        "removed_buses_with_bounds"=>sort(bounded),"events"=>p.plan.events)
end

"""Plain JSON-compatible representation, including original and reduced snapshots."""
reconstruction_plan(p::PreparedNetwork) = Dict("version"=>p.plan.version,"original"=>p.plan.original,
    "reduced"=>p.network,"events"=>p.plan.events,"bus_alias"=>p.plan.bus_alias,
    "options"=>Dict(string(k)=>getfield(p.plan.options,k) for k in fieldnames(ReductionOptions)))

"""Restore a JSON-decoded reconstruction plan. No Julia solver objects are serialized."""
function restore_prepared_network(d::AbstractDict)
    d["version"] == 1 || throw(ArgumentError("unsupported reduction plan version"))
    opts=Dict(Symbol(k)=>(k in ("profile","series_merge_policy") ? Symbol(v) : v) for (k,v) in d["options"])
    PreparedNetwork(_kr_copy(d["reduced"]),ReductionPlan(1,_kr_copy(d["original"]),Any[_kr_copy(e) for e in d["events"]],
        Dict{String,String}(d["bus_alias"]),ReductionOptions(;opts...)))
end
