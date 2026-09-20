"""Options for the radial multiphase branch-flow SDP prototype."""
Base.@kwdef struct BranchFlowSDPOptions
    s_base::Float64 = 1e4
    objective::Symbol = :cost
    cone::Symbol = :real
    recovery::Symbol = :tree
    scale_objective::Bool = true
end

struct BranchFlowSDPInapplicableError <: Exception
    code::String
    message::String
end
Base.showerror(io::IO, e::BranchFlowSDPInapplicableError) =
    print(io, e.code, ": ", e.message)
_bfm_refuse(message) = throw(BranchFlowSDPInapplicableError(
    "E.BFM.UNSUPPORTED", String(message)))

"""Result of the conservative branch-flow SDP applicability check."""
struct BranchFlowSDPApplicabilityReport
    status::Symbol
    findings::Vector{String}
end
is_branch_flow_sdp_applicable(r::BranchFlowSDPApplicabilityReport) =
    r.status == :applicable

function _bfm_fields(data, allowed, label; matrix=())
    for key_raw in keys(data)
        key = String(key_raw)
        key in allowed && continue
        if any(prefix -> occursin(Regex("^" * prefix * raw"\d+_\d+$"), key), matrix)
            continue
        end
        _bfm_refuse("$label field '$key' is outside the branch-flow SDP prototype")
    end
end

function _bfm_vector(data, key, n, label; default=nothing)
    haskey(data, key) || return default
    raw = data[key]
    values = raw isa Real ? fill(Float64(raw), n) : Float64.(raw)
    length(values) == n && all(isfinite, values) ||
        _bfm_refuse("$label $key must contain $n finite values")
    values
end

function _bfm_phase_vector(data, key, phase_positions, terminal_count, label;
                           default=nothing)
    haskey(data, key) || return default
    raw = data[key]
    values = raw isa Real ? fill(Float64(raw), length(phase_positions)) : Float64.(raw)
    if length(values) == terminal_count
        values = values[phase_positions]
    end
    length(values) == length(phase_positions) && all(isfinite, values) ||
        _bfm_refuse("$label $key must match its phase channels or complete terminal map")
    values
end

function _bfm_line_matrix(data, prefix, n, label)
    matrix = try
        _kr_matrix(data, prefix; label)
    catch err
        _bfm_refuse(sprint(showerror, err))
    end
    matrix === nothing && return zeros(n, n), false
    size(matrix, 1) <= n || _bfm_refuse("$label $prefix matrix exceeds terminal arity")
    out = zeros(n, n)
    out[1:size(matrix, 1), 1:size(matrix, 2)] .= matrix
    out, true
end

function _bfm_topology(net)
    buses = get(net, "bus", Dict())
    isempty(buses) && _bfm_refuse("the network has no buses")
    sources = get(net, "voltage_source", Dict())
    length(sources) == 1 || _bfm_refuse(
        "the first branch-flow SDP slice requires exactly one voltage source")
    source_id, source = only(collect(sources))
    root = String(get(source, "bus", ""))
    haskey(buses, root) || _bfm_refuse("voltage source references unknown bus '$root'")

    adjacency = Dict(String(b) => Tuple{String,String}[] for b in keys(buses))
    for (id_raw, line) in get(net, "line", Dict())
        id = String(id_raw)
        from = String(get(line, "bus_from", ""))
        to = String(get(line, "bus_to", ""))
        from != to || _bfm_refuse("line/$id is a self loop")
        haskey(adjacency, from) && haskey(adjacency, to) ||
            _bfm_refuse("line/$id references an unknown bus")
        push!(adjacency[from], (id, to)); push!(adjacency[to], (id, from))
    end
    length(get(net, "line", Dict())) == length(buses) - 1 ||
        _bfm_refuse("the branch-flow SDP prototype requires a radial tree")

    parent = Dict(root => "")
    queue = [root]
    oriented = NamedTuple[]
    while !isempty(queue)
        bus = popfirst!(queue)
        for (id, other) in adjacency[bus]
            other == get(parent, bus, "") && continue
            haskey(parent, other) && _bfm_refuse("the network contains a cycle")
            parent[other] = bus
            line = net["line"][id]
            reversed = String(line["bus_from"]) != bus
            push!(oriented, (; id, parent=bus, child=other, reversed))
            push!(queue, other)
        end
    end
    length(parent) == length(buses) || _bfm_refuse(
        "every bus must be connected to the voltage-source root")
    (; root, source_id=String(source_id), source, oriented)
end

function _bfm_device_positions(net, data, label)
    bus = String(get(data, "bus", ""))
    buses = get(net, "bus", Dict())
    haskey(buses, bus) || _bfm_refuse("$label references unknown bus '$bus'")
    bus_terms = string.(buses[bus]["terminal_names"])
    terminals = string.(get(data, "terminal_map", String[]))
    !isempty(terminals) && allunique(terminals) && all(in(bus_terms), terminals) ||
        _bfm_refuse("$label has an invalid terminal_map")
    configuration = uppercase(String(get(data, "configuration", "WYE")))
    configuration in ("WYE", "SINGLE_PHASE") ||
        _bfm_refuse("$label requires a direct wye or ground-referenced single-phase connection")
    neutral = get(_kr_neutral_map(net), bus, nothing)
    neutral_position = findfirst(==(neutral), terminals)
    if neutral_position !== nothing
        neutral == last(terminals) || _bfm_refuse("$label requires a trailing neutral")
        neutral in get(buses[bus], "perfectly_grounded_terminals", String[]) ||
            _bfm_refuse("$label phase-to-neutral power requires a grounded neutral in this prototype")
    end
    channels = [t for t in terminals if t != neutral]
    configuration == "SINGLE_PHASE" && length(channels) != 1 &&
        _bfm_refuse("$label SINGLE_PHASE requires one energized terminal and optional grounded neutral")
    positions = [something(findfirst(==(t), bus_terms), 0) for t in channels]
    (; bus, terminals, channels, positions, terminal_count=length(terminals))
end

function _bfm_validate(net)
    tables = Set(("bus", "line", "linecode", "load", "generator",
                  "voltage_source", "shunt"))
    metadata = Set(("name", "meta", "_meta", "extras", "terminal_conventions",
                    "wire_data", "line_geometry"))
    for (key_raw, value) in net
        key = String(key_raw)
        empty_value = (value isa AbstractDict || value isa AbstractVector) && isempty(value)
        key in tables || key in metadata || empty_value ||
            _bfm_refuse("nonempty table '$key' is outside the branch-flow SDP prototype")
    end
    plan = _bfm_topology(net)
    buses = net["bus"]
    for (id, bus) in buses
        _bfm_fields(bus, ("terminal_names", "perfectly_grounded_terminals",
            "neutral_terminal", "v_min", "v_max"), "bus/$id")
        terms = string.(get(bus, "terminal_names", String[]))
        !isempty(terms) && allunique(terms) ||
            _bfm_refuse("bus/$id requires distinct terminal_names")
        all(in(terms), string.(get(bus, "perfectly_grounded_terminals", String[]))) ||
            _bfm_refuse("bus/$id grounds an undeclared terminal")
    end
    for (id, line) in get(net, "line", Dict())
        _bfm_fields(line, ("bus_from", "bus_to", "terminal_map_from",
            "terminal_map_to", "linecode", "length", "i_max", "s_max"),
            "line/$id"; matrix=("R_series_", "X_series_"))
        from, to = String(line["bus_from"]), String(line["bus_to"])
        from_terms, to_terms = string.(buses[from]["terminal_names"]),
                                   string.(buses[to]["terminal_names"])
        map_from, map_to = string.(line["terminal_map_from"]),
                           string.(line["terminal_map_to"])
        map_from == from_terms && map_to == to_terms && map_from == map_to ||
            _bfm_refuse("line/$id must cover aligned complete bus terminal maps")
        coded = haskey(line, "linecode")
        inline = any(startswith(String(k), "R_series_") ||
                     startswith(String(k), "X_series_") for k in keys(line))
        coded != inline || _bfm_refuse("line/$id must declare exactly one impedance source")
        coded && !haskey(get(net, "linecode", Dict()), line["linecode"]) &&
            _bfm_refuse("line/$id references an unknown linecode")
        coefficient_data = coded ? net["linecode"][line["linecode"]] : line
        any(startswith(String(k), p) for k in keys(coefficient_data),
            p in ("G_from_", "B_from_", "G_to_", "B_to_")) &&
            _bfm_refuse("line/$id endpoint shunts are not in the first branch-flow SDP slice")
    end
    for (id, code) in get(net, "linecode", Dict())
        _bfm_fields(code, ("i_max", "s_max", "source", "line_geometry", "derivation"), "linecode/$id";
            matrix=("R_series_", "X_series_"))
    end
    for (id, load) in get(net, "load", Dict())
        _bfm_fields(load, ("bus", "terminal_map", "configuration", "model",
            "p_nom", "q_nom", "v_nom"), "load/$id")
        law = lowercase(String(get(load, "model", "constant_power")))
        law in ("constant_power", "constant_impedance") ||
            _bfm_refuse("load/$id model '$law' is not in the first branch-flow SDP slice")
        _bfm_device_positions(net, load, "load/$id")
    end
    for (id, generator) in get(net, "generator", Dict())
        _bfm_fields(generator, ("bus", "terminal_map", "configuration", "p_min",
            "p_max", "q_min", "q_max", "s_max", "i_max", "cost",
            "energy_cost_rate"), "generator/$id")
        _bfm_device_positions(net, generator, "generator/$id")
    end
    for (id, source) in get(net, "voltage_source", Dict())
        _bfm_fields(source, ("bus", "terminal_map", "configuration", "v_magnitude",
            "v_angle", "p_min", "p_max", "q_min", "q_max", "s_max", "i_max",
            "cost", "energy_cost_rate"), "voltage_source/$id")
        string.(source["terminal_map"]) ==
            string.(buses[String(source["bus"])]["terminal_names"]) ||
            _bfm_refuse("voltage_source/$id must cover its complete root-bus terminal map")
    end
    for (id, shunt) in get(net, "shunt", Dict())
        _bfm_fields(shunt, ("bus", "terminal_map"), "shunt/$id";
            matrix=("G_", "B_"))
        bus = String(shunt["bus"])
        string.(shunt["terminal_map"]) == string.(buses[bus]["terminal_names"]) ||
            _bfm_refuse("shunt/$id must cover its complete bus terminal map")
    end
    plan
end

function check_branch_flow_sdp_applicability(input)
    try
        _bfm_validate(_l3f_input(input))
        BranchFlowSDPApplicabilityReport(:applicable, String[])
    catch err
        err isa BranchFlowSDPInapplicableError || rethrow()
        BranchFlowSDPApplicabilityReport(:inapplicable,
            [err.code * ": " * err.message])
    end
end

function _bfm_hermitian(model, n)
    if n == 1
        value = @variable(model)
        return reshape([value + 0im], 1, 1)
    end
    @variable(model, [1:n, 1:n] in HermitianMatrixSpace())
end

struct BranchFlowSDPBuild
    model::JuMP.Model
    voltage_moments::Dict{String,Any}
    edge_blocks::Dict{String,Any}
    edge_records::Vector{NamedTuple}
    powers::Dict{Tuple{Symbol,String},Vector{Any}}
    network::Dict{String,Any}
    options::BranchFlowSDPOptions
    voltage_base::Float64
    current_base::Float64
    root::String
    root_voltage::Vector{ComplexF64}
    objective_scale::Float64
    numerical_diagnostics::Dict{Symbol,Any}
end

function _bfm_box!(model, p, q, data, positions, terminal_count, label, sb)
    for (low_key, high_key, values) in (("p_min", "p_max", p),
                                         ("q_min", "q_max", q))
        lower = _bfm_phase_vector(data, low_key, positions, terminal_count, label)
        upper = _bfm_phase_vector(data, high_key, positions, terminal_count, label)
        for k in eachindex(values)
            if lower !== nothing && upper !== nothing && lower[k] == upper[k]
                @constraint(model, values[k] == lower[k] / sb)
            else
                lower === nothing || @constraint(model, values[k] >= lower[k] / sb)
                upper === nothing || @constraint(model, values[k] <= upper[k] / sb)
            end
        end
    end
end

function _bfm_capability!(model, p, q, W, positions, data, terminal_count,
                          label, sb, ib)
    smax = _bfm_phase_vector(data, "s_max", positions, terminal_count, label)
    imax = _bfm_phase_vector(data, "i_max", positions, terminal_count, label)
    for k in eachindex(p)
        if smax !== nothing
            smax[k] >= 0 || _bfm_refuse("$label has a negative apparent-power limit")
            @constraint(model, [smax[k] / sb, p[k], q[k]] in SecondOrderCone())
        end
        if imax !== nothing
            imax[k] >= 0 || _bfm_refuse("$label has a negative current limit")
            @constraint(model, [real(W[positions[k], positions[k]]),
                (imax[k] / ib)^2 / 2, p[k], q[k]] in RotatedSecondOrderCone())
        end
    end
end

"""Build the first radial, series-line, unbalanced branch-flow SDP slice."""
function build_branch_flow_sdp(input, optimizer=default_sdp_optimizer();
                               options::BranchFlowSDPOptions=BranchFlowSDPOptions())
    isfinite(options.s_base) && options.s_base > 0 ||
        throw(ArgumentError("s_base must be positive and finite"))
    options.objective in (:cost, :source_import, :feasibility) ||
        throw(ArgumentError("unknown branch-flow SDP objective"))
    options.cone in (:real, :hermitian) || throw(ArgumentError("unknown SDP cone"))
    options.recovery == :tree || throw(ArgumentError("only recovery=:tree is implemented"))
    net = _l3f_input(input)
    plan = _bfm_validate(net)
    source = plan.source
    root_terms = string.(net["bus"][plan.root]["terminal_names"])
    root_voltage = Float64.(source["v_magnitude"]) .*
                   cis.(Float64.(source["v_angle"]))
    length(root_voltage) == length(root_terms) && all(isfinite, root_voltage) ||
        _bfm_refuse("the root source has invalid phasors")
    vb = maximum(abs, root_voltage)
    vb > 0 || _bfm_refuse("the root source needs a nonzero phasor")
    sb = options.s_base
    ib = sb / vb
    zb = vb / ib
    model = optimizer === nothing || optimizer isa _SDPDefaultOptimizer ?
        JuMP.Model() : JuMP.Model(optimizer)

    voltage_moments = Dict{String,Any}()
    incoming_p = Dict{String,Vector{Any}}()
    incoming_q = Dict{String,Vector{Any}}()
    outgoing_p = Dict{String,Vector{Any}}()
    outgoing_q = Dict{String,Vector{Any}}()
    injection_p = Dict{String,Vector{Any}}()
    injection_q = Dict{String,Vector{Any}}()
    for (bus, data) in sort!(collect(net["bus"]); by=first)
        n = length(data["terminal_names"])
        voltage_moments[bus] = _bfm_hermitian(model, n)
        incoming_p[bus] = Any[JuMP.AffExpr(0.0) for _ in 1:n]
        incoming_q[bus] = Any[JuMP.AffExpr(0.0) for _ in 1:n]
        outgoing_p[bus] = Any[JuMP.AffExpr(0.0) for _ in 1:n]
        outgoing_q[bus] = Any[JuMP.AffExpr(0.0) for _ in 1:n]
        injection_p[bus] = Any[JuMP.AffExpr(0.0) for _ in 1:n]
        injection_q[bus] = Any[JuMP.AffExpr(0.0) for _ in 1:n]
    end

    edge_blocks = Dict{String,Any}()
    edge_records = NamedTuple[]
    powers = Dict{Tuple{Symbol,String},Vector{Any}}()
    for oriented in plan.oriented
        id, parent, child = oriented.id, oriented.parent, oriented.child
        line = net["line"][id]
        n = length(net["bus"][parent]["terminal_names"])
        code = haskey(line, "linecode") ? net["linecode"][line["linecode"]] : line
        length_scale = haskey(line, "linecode") ? Float64(get(line, "length", 1.0)) : 1.0
        isfinite(length_scale) && length_scale > 0 ||
            _bfm_refuse("line/$id length must be positive")
        resistance, has_r = _bfm_line_matrix(code, "R_series_", n, "line/$id")
        reactance, has_x = _bfm_line_matrix(code, "X_series_", n, "line/$id")
        has_r || has_x || _bfm_refuse("line/$id has no series impedance")
        Z = complex.(resistance, reactance) .* length_scale ./ zb
        block = _sdp_psd(model, 2n, options.cone)
        edge_blocks[id] = block
        Wp, Wc = voltage_moments[parent], voltage_moments[child]
        S = block[1:n, n+1:2n]
        L = block[n+1:2n, n+1:2n]
        for a in 1:n, b in a:n
            @constraint(model, block[a, b] == Wp[a, b])
            drop = Wp[a, b]
            for k in 1:n
                drop -= S[a, k] * conj(Z[b, k])
                drop -= Z[a, k] * conj(S[b, k])
                for h in 1:n
                    drop += Z[a, k] * L[k, h] * conj(Z[b, h])
                end
            end
            @constraint(model, Wc[a, b] == drop)
        end
        sending = Any[S[k, k] for k in 1:n]
        receiving = Any[S[k, k] - sum(Z[k, h] * L[h, k] for h in 1:n)
                        for k in 1:n]
        if oriented.reversed
            powers[(:line_from, id)] = Any[-s for s in receiving]
            powers[(:line_to, id)] = sending
        else
            powers[(:line_from, id)] = sending
            powers[(:line_to, id)] = Any[-s for s in receiving]
        end
        for k in 1:n
            outgoing_p[parent][k] += real(sending[k])
            outgoing_q[parent][k] += imag(sending[k])
            incoming_p[child][k] += real(receiving[k])
            incoming_q[child][k] += imag(receiving[k])
        end
        ratings = Dict{String,Any}()
        for key in ("i_max", "s_max")
            if haskey(line, key)
                ratings[key] = line[key]
            elseif haskey(code, key)
                ratings[key] = code[key]
            end
        end
        imax = _bfm_vector(ratings, "i_max", n, "line/$id")
        terms = string.(net["bus"][parent]["terminal_names"])
        phase_positions = findall(!=(get(_kr_neutral_map(net), parent, nothing)), terms)
        smax = _bfm_phase_vector(ratings, "s_max", phase_positions, n, "line/$id")
        for k in 1:n
            imax === nothing || @constraint(model,
                real(L[k, k]) <= (imax[k] / ib)^2)
        end
        if smax !== nothing
            for (k, position) in enumerate(phase_positions)
                @constraint(model, [smax[k] / sb, real(sending[position]), imag(sending[position])]
                    in SecondOrderCone())
                @constraint(model, [smax[k] / sb, real(receiving[position]), imag(receiving[position])]
                    in SecondOrderCone())
            end
        end
        push!(edge_records, (; id, parent, child, reversed=oriented.reversed,
            Z, sending, receiving, S, L))
    end

    # Fixed source voltage Gram, grounding, and phase-to-ground voltage bounds.
    Wroot = voltage_moments[plan.root]
    root_pu = root_voltage ./ vb
    for a in eachindex(root_pu), b in a:length(root_pu)
        @constraint(model, Wroot[a, b] == root_pu[a] * conj(root_pu[b]))
    end
    neutrals = _kr_neutral_map(net)
    for (bus, data) in net["bus"]
        W = voltage_moments[bus]
        terms = string.(data["terminal_names"])
        grounded = Set(string.(get(data, "perfectly_grounded_terminals", String[])))
        for (k, terminal) in enumerate(terms)
            if terminal in grounded
                for h in eachindex(terms)
                    a, b = minmax(k, h)
                    @constraint(model, W[a, b] == 0)
                end
            end
        end
        phase_positions = findall(!=(get(neutrals, bus, nothing)), terms)
        for (key, lower) in (("v_min", true), ("v_max", false))
            haskey(data, key) || continue
            values = data[key] isa Real ? fill(Float64(data[key]), length(phase_positions)) :
                     Float64.(data[key])
            positions = if length(values) == length(terms)
                collect(eachindex(terms))
            elseif length(values) == length(phase_positions)
                phase_positions
            else
                _bfm_refuse("bus/$bus $key must match phases or all terminals")
            end
            all(x -> isfinite(x) && x >= 0, values) ||
                _bfm_refuse("bus/$bus $key must be finite and nonnegative")
            for (position, value) in zip(positions, values)
                lower ? @constraint(model, real(W[position, position]) >= (value / vb)^2) :
                        @constraint(model, real(W[position, position]) <= (value / vb)^2)
            end
        end
    end

    objective = JuMP.AffExpr(0.0)
    function add_dispatch!(family, id, data, device, sign)
        bus, positions = device.bus, device.positions
        n = length(positions)
        p = Any[@variable(model) for _ in 1:n]
        q = Any[@variable(model) for _ in 1:n]
        _bfm_box!(model, p, q, data, positions, device.terminal_count,
                  "$family/$id", sb)
        _bfm_capability!(model, p, q, voltage_moments[bus], positions, data,
                         device.terminal_count, "$family/$id", sb, ib)
        s = Any[p[k] + im * q[k] for k in 1:n]
        powers[(Symbol(family), String(id))] = s
        for k in 1:n
            injection_p[bus][positions[k]] += sign * p[k]
            injection_q[bus][positions[k]] += sign * q[k]
        end
        priced = data
        if haskey(data, "energy_cost_rate")
            haskey(data, "cost") && data["cost"] != data["energy_cost_rate"] &&
                _bfm_refuse("$family/$id has conflicting cost aliases")
            priced = copy(data); priced["cost"] = data["energy_cost_rate"]
        end
        costs = _bfm_phase_vector(priced, "cost", positions,
            device.terminal_count, "$family/$id"; default=zeros(n))
        for k in 1:n
            coefficient = options.objective == :cost ? costs[k] * sb / 1000 :
                options.objective == :source_import && family == "voltage_source" ? sb : 0.0
            JuMP.add_to_expression!(objective, coefficient, p[k])
        end
        s
    end

    source_device = _bfm_device_positions(net, source, "voltage_source/$(plan.source_id)")
    add_dispatch!("voltage_source", plan.source_id, source, source_device, 1)

    for (id, generator) in sort!(collect(get(net, "generator", Dict())); by=first)
        device = _bfm_device_positions(net, generator, "generator/$id")
        add_dispatch!("generator", id, generator, device, 1)
    end
    for (id, load) in sort!(collect(get(net, "load", Dict())); by=first)
        device = _bfm_device_positions(net, load, "load/$id")
        n = length(device.positions)
        p = _bfm_vector(load, "p_nom", n, "load/$id")
        q = _bfm_vector(load, "q_nom", n, "load/$id")
        (p === nothing || q === nothing) &&
            _bfm_refuse("load/$id requires p_nom and q_nom")
        law = lowercase(String(get(load, "model", "constant_power")))
        s = Any[]
        if law == "constant_power"
            append!(s, complex.(p, q) ./ sb)
        else
            vnom = _bfm_vector(load, "v_nom", n, "load/$id")
            vnom === nothing && _bfm_refuse("load/$id constant impedance requires v_nom")
            all(>(0), vnom) || _bfm_refuse("load/$id v_nom must be positive")
            W = voltage_moments[device.bus]
            for k in 1:n
                push!(s, complex(p[k], q[k]) / sb * (vb / vnom[k])^2 *
                         real(W[device.positions[k], device.positions[k]]))
            end
        end
        powers[(:load, String(id))] = s
        for k in 1:n
            injection_p[device.bus][device.positions[k]] -= real(s[k])
            injection_q[device.bus][device.positions[k]] -= imag(s[k])
        end
    end
    for (id, shunt) in sort!(collect(get(net, "shunt", Dict())); by=first)
        bus = String(shunt["bus"])
        terms = string.(net["bus"][bus]["terminal_names"])
        Y = _l3f_shunt_matrix(shunt, length(terms)) * zb
        W = voltage_moments[bus]
        s = Any[sum(W[k, h] * conj(Y[k, h]) for h in eachindex(terms))
                for k in eachindex(terms)]
        powers[(:shunt, String(id))] = s
        for k in eachindex(terms)
            injection_p[bus][k] -= real(s[k])
            injection_q[bus][k] -= imag(s[k])
        end
    end

    for (bus, data) in net["bus"], k in eachindex(data["terminal_names"])
        @constraint(model, incoming_p[bus][k] - outgoing_p[bus][k] +
            injection_p[bus][k] == 0)
        @constraint(model, incoming_q[bus][k] - outgoing_q[bus][k] +
            injection_q[bus][k] == 0)
    end
    objective_scale = options.scale_objective ?
        max(maximum(abs, values(objective.terms); init=0.0), 1e-12) : 1.0
    @objective(model, Min, objective / objective_scale)
    diagnostics = Dict{Symbol,Any}(
        :formulation => :branch_flow_sdp,
        :scope => :radial_series_v1,
        :bus_count => length(net["bus"]),
        :edge_count => length(edge_records),
        :cone => options.cone,
        :objective_scale => objective_scale,
    )
    if optimizer isa _SDPDefaultOptimizer
        JuMP.set_optimizer(model, default_sdp_optimizer(:dense))
        diagnostics[:optimizer_profile] = :clarabel_dense
    else
        diagnostics[:optimizer_profile] = :caller_supplied
    end
    BranchFlowSDPBuild(model, voltage_moments, edge_blocks, edge_records,
        powers, net, options, vb, ib, plan.root, root_voltage,
        objective_scale, diagnostics)
end

struct BranchFlowSDPResult <: AbstractSolveResult
    objective::Float64
    solver_objective_bound::Float64
    voltage_moments::Dict{String,Matrix{ComplexF64}}
    branch_power_moments::Dict{String,Matrix{ComplexF64}}
    branch_current_moments::Dict{String,Matrix{ComplexF64}}
    voltage_candidate::Dict{Tuple{String,String},ComplexF64}
    current_candidate::Dict{Tuple{Symbol,String},Vector{ComplexF64}}
    relaxed_powers::Dict{Tuple{Symbol,String},Vector{ComplexF64}}
    rank_ratio::Float64
    solve::SolveStatus
    numerical_diagnostics::Dict{Symbol,Any}
end
solve_status(r::BranchFlowSDPResult) = r.solve
solve_diagnostics(r::BranchFlowSDPResult) = (
    model_kind=:relaxation, rank_ratio=r.rank_ratio,
    numerical=r.numerical_diagnostics,
    physical_feasibility_certified=false, bound_certified=false)

function solve_branch_flow_sdp(input, optimizer=default_sdp_optimizer();
                               options::BranchFlowSDPOptions=BranchFlowSDPOptions(),
                               solver_options=())
    solve_branch_flow_sdp(build_branch_flow_sdp(input, optimizer; options);
                          solver_options)
end

function solve_branch_flow_sdp(build::BranchFlowSDPBuild; solver_options=())
    _set_solver_options!(build.model, solver_options)
    JuMP.optimize!(build.model)
    outcome = _solve_outcome(build.model)
    status = SolveStatus(outcome)
    diagnostics = copy(build.numerical_diagnostics)
    if !outcome.optimal
        return BranchFlowSDPResult(NaN, NaN, Dict{String,Matrix{ComplexF64}}(),
            Dict{String,Matrix{ComplexF64}}(), Dict{String,Matrix{ComplexF64}}(),
            Dict{Tuple{String,String},ComplexF64}(),
            Dict{Tuple{Symbol,String},Vector{ComplexF64}}(),
            Dict{Tuple{Symbol,String},Vector{ComplexF64}}(), NaN, status, diagnostics)
    end
    vb, ib, sb = build.voltage_base, build.current_base, build.options.s_base
    W = Dict(id => Matrix{ComplexF64}(JuMP.value.(moment)) * vb^2
             for (id, moment) in build.voltage_moments)
    S = Dict{String,Matrix{ComplexF64}}()
    L = Dict{String,Matrix{ComplexF64}}()
    ratios = Float64[]
    for edge in build.edge_records
        block = Matrix{ComplexF64}(JuMP.value.(build.edge_blocks[edge.id]))
        n = size(edge.S, 1)
        S[edge.id] = block[1:n, n+1:2n] * sb
        L[edge.id] = block[n+1:2n, n+1:2n] * ib^2
        eigenvalues = eigvals(Hermitian(block))
        push!(ratios, length(eigenvalues) > 1 ?
            max(0.0, eigenvalues[end-1]) / max(eps(), eigenvalues[end]) : 0.0)
    end
    voltage = Dict{Tuple{String,String},ComplexF64}()
    for (terminal, value) in zip(build.network["bus"][build.root]["terminal_names"],
                                 build.root_voltage)
        voltage[(build.root, terminal)] = value
    end
    currents = Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    for edge in build.edge_records
        terms_parent = build.network["bus"][edge.parent]["terminal_names"]
        parent_voltage = ComplexF64[voltage[(edge.parent, t)] / vb for t in terms_parent]
        Smat = S[edge.id] / sb
        denominator = real(dot(parent_voltage, parent_voltage))
        current_pu = denominator > eps() ? Smat' * parent_voltage / denominator :
                     zeros(ComplexF64, length(parent_voltage))
        child_voltage = parent_voltage - edge.Z * current_pu
        for (terminal, value) in zip(build.network["bus"][edge.child]["terminal_names"],
                                     child_voltage)
            voltage[(edge.child, terminal)] = value * vb
        end
        physical_current = current_pu * ib
        input_current = edge.reversed ? -physical_current : physical_current
        currents[(:line_series, edge.id)] = input_current
        currents[(:line_from, edge.id)] = input_current
        currents[(:line_to, edge.id)] = -input_current
    end
    powers = Dict(key => ComplexF64.(JuMP.value.(values)) .* sb
                  for (key, values) in build.powers)
    for family in ("load", "generator")
        for (id, data) in get(build.network, family, Dict())
            device = _bfm_device_positions(build.network, data, "$family/$id")
            u = ComplexF64[voltage[(device.bus, terminal)] for terminal in device.channels]
            s = powers[(Symbol(family), String(id))]
            currents[(Symbol(family), String(id))] = ComplexF64[
                iszero(v) ? (iszero(power) ? 0im : ComplexF64(NaN)) : conj(power / v)
                for (power, v) in zip(s, u)]
        end
    end
    source_id, source = only(collect(build.network["voltage_source"]))
    device = _bfm_device_positions(build.network, source, "voltage_source/$source_id")
    u = ComplexF64[voltage[(device.bus, terminal)] for terminal in device.channels]
    source_power = powers[(:voltage_source, String(source_id))]
    channel_current = ComplexF64[
        iszero(v) ? (iszero(power) ? 0im : ComplexF64(NaN)) : conj(power / v)
        for (power, v) in zip(source_power, u)]
    terminal_current = zeros(ComplexF64, device.terminal_count)
    for (k, terminal) in enumerate(device.channels)
        terminal_current[findfirst(==(terminal), device.terminals)] = channel_current[k]
    end
    neutral = get(_kr_neutral_map(build.network), device.bus, nothing)
    neutral_position = findfirst(==(neutral), device.terminals)
    neutral_position === nothing || (terminal_current[neutral_position] = -sum(channel_current))
    currents[(:voltage_source, String(source_id))] = terminal_current
    bound = try JuMP.objective_bound(build.model) catch; NaN end
    isfinite(bound) || (bound = try JuMP.dual_objective_value(build.model) catch; NaN end)
    bound *= build.objective_scale
    ratio = maximum(ratios; init=0.0)
    diagnostics[:edge_rank_ratios] = Dict(edge.id => ratios[k]
        for (k, edge) in enumerate(build.edge_records))
    diagnostics[:recovery] = :tree
    BranchFlowSDPResult(JuMP.objective_value(build.model) * build.objective_scale,
        bound, W, S, L, voltage, currents, powers, ratio, status, diagnostics)
end
