const _L3F_BRANCH_LIMIT_FAMILIES = (
    :line_current, :line_apparent_power,
    :transformer_current, :transformer_apparent_power,
    :transformer_winding_apparent_power,
    :source_current, :source_apparent_power,
)

function _l3f_monitor_current_rating(build, family, key)
    net = build.network
    if family == :line_current
        id, _, k = key
        line = net["line"][id]
        code = get(get(net, "linecode", Dict()), get(line, "linecode", ""), nothing)
        return _l3f_rating(line, code, "i_max", k)
    elseif family == :source_current
        id, k = key
        return _l3f_scalar_or_indexed(net["voltage_source"][id], "i_max", k)
    else
        kind, id, side, k = key
        return _l3f_scalar_or_indexed(net["transformer"][kind][id], "i_max_$side", k)
    end
end

function _l3f_fixed_dispatch!(build, dispatch)
    dispatch === nothing && (dispatch = Dict())
    dispatch isa AbstractDict || throw(ArgumentError("dispatch must map generator IDs to SI pg/qg vectors"))
    generators = get(build.network, "generator", Dict())
    isempty(setdiff(Set(keys(dispatch)), Set(keys(generators)))) ||
        throw(ArgumentError("dispatch contains unknown generator IDs; use IDs after IBR lowering"))
    values = Dict{String,Any}()
    # Validate the complete request before adding constraints.
    for (id, gen) in generators
        n = length(gen["p_min"])
        point = get(dispatch, id, nothing)
        if point === nothing
            all(k -> gen["p_min"][k] == gen["p_max"][k] &&
                gen["q_min"][k] == gen["q_max"][k], 1:n) ||
                throw(ArgumentError("power_flow requires fixed pg/qg dispatch for generator '$id'"))
            point = Dict("pg" => gen["p_min"], "qg" => gen["q_min"])
        end
        point isa AbstractDict || throw(ArgumentError("dispatch for '$id' must be an object"))
        if haskey(point, "terminal_map")
            string.(point["terminal_map"]) == string.(gen["terminal_map"]) ||
                throw(ArgumentError("dispatch terminal_map for '$id' does not match the retained model"))
        end
        for field in ("pg", "qg")
            raw = get(point, field, nothing)
            raw isa AbstractVector && length(raw) == n &&
                all(v -> v isa Real && !(v isa Bool) && isfinite(v), raw) ||
                throw(ArgumentError("dispatch '$id.$field' must contain $n finite SI values"))
        end
        values[id] = Dict("pg" => Float64.(point["pg"]), "qg" => Float64.(point["qg"]))
    end
    scale = build.options.per_unit ? build.options.s_base : 1.0
    for (id, point) in values, (field, family) in (("pg", :p_generator), ("qg", :q_generator))
        for k in eachindex(point[field])
            variable = build.variables[family][(id, k)]
            target = point[field][k] / scale
            # Equality preserves existing capability bounds; fix(force=true)
            # would erase them and could hide an invalid operating point.
            _l3f_register_constraint!(build.constraints, :fixed_dispatch, (id, field, k),
                @constraint(build.model, variable == target))
        end
    end
    build.model.ext[:l3f_fixed_dispatch] = values
end

function _l3f_monitor_power_factor(build, family, key)
    family == :transformer_winding_apparent_power || return 1.0
    kind, id, side, j = key
    tx = build.network["transformer"][kind][id]
    pairs = _L3F_OPEN_DELTA_PAIRS[uppercase(String(tx["connection"]))]
    shared = only(intersect(collect(pairs[1]), collect(pairs[2])))
    pair = pairs[j]; other = pair[1] == shared ? pair[2] : pair[1]
    bus, tm = _l3f_physical_endpoint(tx, side)
    v = build.reference.voltage
    abs(v[(bus,tm[pair[1]])] - v[(bus,tm[pair[2]])]) / abs(v[(bus,tm[other])])
end

function _l3f_apply_operating_mode!(build, dispatch)
    monitoring = build.options.operating_mode == :power_flow
    monitoring && _l3f_fixed_dispatch!(build, dispatch)
    records = []
    for family in _L3F_BRANCH_LIMIT_FAMILIES
        table = get(build.constraints, family, Dict())
        for (key, ref) in table
            obj = JuMP.constraint_object(ref)
            current = obj.set isa MOI.RotatedSecondOrderCone
            rating = current ? _l3f_monitor_current_rating(build, family, key) : nothing
            push!(records, (family=family, key=key, object=obj, current_rating=rating,
                power_factor=_l3f_monitor_power_factor(build, family, key)))
            monitoring && JuMP.delete(build.model, ref)
        end
        monitoring && empty!(table)
    end
    build.model.ext[:l3f_operating_limits] = records
    if monitoring
        @objective(build.model, Min, 0.0)
    end
end

"""
    l3f_limit_report(build::L3FBuild; rtol=1e-6)
    l3f_limit_report(result::L3FResult)

Report the supported branch/source thermal limits at an optimal feasible L3F
solution. `:opf` enforces these limits; `:power_flow` monitors them at fixed DER
P/Q. Other constraints remain enforced. Entries identify the semantic constraint
family/key and give SI limits, values and loading ratios. These are estimates
under L3F's voltage/power closure, not an AC feasibility certificate.

Before a successful solve, or for an infeasibility certificate, return
`status="unavailable"` and no evaluated entries. A zero current limit or zero
allowed transfer may make current/ratio undefined (`nothing`); the power-transfer
comparison still reports overload. A numerically zero transfer at zero allowed
transfer has no defined ratio. `rtol` applies to the cone power-transfer capacity.
"""
function l3f_limit_report(build::L3FBuild; rtol::Real=1e-6)
    isfinite(rtol) && rtol >= 0 || throw(ArgumentError("rtol must be finite and nonnegative"))
    records = get(build.model.ext, :l3f_operating_limits, [])
    report = Dict{String,Any}(
        "mode" => String(build.options.operating_mode),
        "enforced" => build.options.operating_mode == :opf,
        "status" => "unavailable", "entries" => Any[], "overload_count" => nothing,
        "monitored_count" => length(records), "rtol" => Float64(rtol),
        "scope" => "supported line, transformer and voltage-source thermal limits",
        "physical_feasibility_certified" => false,
    )
    _solve_outcome(build.model).optimal || return report
    scale = build.options.per_unit ? build.options.s_base : 1.0
    rows = report["entries"]
    for record in records
        obj = record.object
        v = JuMP.value.(obj.func)
        current = obj.set isa MOI.RotatedSecondOrderCone
        power = sqrt(sum(abs2, current ? v[3:end] : v[2:end])) * scale * record.power_factor
        capacity = (current ? sqrt(max(0.0, 2v[1]*v[2])) : max(0.0, v[1])) * scale * record.power_factor
        ratio = capacity > 0 ? power / capacity : nothing
        limit = current ? record.current_rating : capacity
        actual = current ? (ratio === nothing ? nothing : ratio * limit) : power
        overloaded = power > capacity * (1 + rtol) + 1e-6 # SI VA numerical floor
        push!(rows, Dict{String,Any}(
            "family" => String(record.family), "key" => collect(record.key),
            "quantity" => current ? "current" : "apparent_power",
            "unit" => current ? "A" : "VA", "limit" => limit, "value" => actual,
            "loading_ratio" => ratio, "overloaded" => overloaded,
            "power_VA" => power, "allowed_power_VA" => capacity,
        ))
    end
    sort!(rows; by = r -> (r["family"], string(r["key"])))
    report["overload_count"] = count(r -> r["overloaded"], rows)
    report["status"] = report["overload_count"] > 0 ? "overloaded" : "within_monitored_limits"
    report
end

l3f_limit_report(result::L3FResult) = deepcopy(result.formulation["operating_limits"])
