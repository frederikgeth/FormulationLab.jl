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

function _bfm_transformer_edges(net)
    edges = NamedTuple[]
    for (subtype_raw, table) in get(net, "transformer", Dict())
        subtype = String(subtype_raw)
        subtype == "n_winding" && _bfm_refuse(
            "transformer/n_winding is a hyperedge and is not implemented by BranchFlowSDP")
        subtype in _SDP_TRANSFORMERS || _bfm_refuse(
            "transformer/$subtype is not implemented by BranchFlowSDP")
        for (id_raw, data) in table
            id = String(id_raw)
            from = String(get(data, "bus_from", ""))
            to = String(get(data, "bus_to", ""))
            push!(edges, (; kind=:transformer, id, subtype, from, to, data))
        end
    end
    edges
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

    adjacency = Dict(String(b) => NamedTuple[] for b in keys(buses))
    for (id_raw, line) in get(net, "line", Dict())
        id = String(id_raw)
        from = String(get(line, "bus_from", ""))
        to = String(get(line, "bus_to", ""))
        from != to || _bfm_refuse("line/$id is a self loop")
        haskey(adjacency, from) && haskey(adjacency, to) ||
            _bfm_refuse("line/$id references an unknown bus")
        edge = (; kind=:line, id, subtype="", from, to, data=line)
        push!(adjacency[from], merge(edge, (; other=to)))
        push!(adjacency[to], merge(edge, (; other=from)))
    end
    transformer_edges = _bfm_transformer_edges(net)
    for edge in transformer_edges
        edge.from != edge.to || _bfm_refuse(
            "transformer/$(edge.subtype)/$(edge.id) is a self loop")
        haskey(adjacency, edge.from) && haskey(adjacency, edge.to) ||
            _bfm_refuse("transformer/$(edge.subtype)/$(edge.id) references an unknown bus")
        push!(adjacency[edge.from], merge(edge, (; other=edge.to)))
        push!(adjacency[edge.to], merge(edge, (; other=edge.from)))
    end
    edge_count = length(get(net, "line", Dict())) + length(transformer_edges)
    edge_count == length(buses) - 1 ||
        _bfm_refuse("the branch-flow SDP prototype requires a radial tree")

    parent = Dict(root => "")
    queue = [root]
    oriented = NamedTuple[]
    while !isempty(queue)
        bus = popfirst!(queue)
        for edge in adjacency[bus]
            other = edge.other
            other == get(parent, bus, "") && continue
            haskey(parent, other) && _bfm_refuse("the network contains a cycle")
            parent[other] = bus
            reversed = edge.from != bus
            push!(oriented, (; kind=edge.kind, id=edge.id, subtype=edge.subtype,
                parent=bus, child=other, reversed))
            push!(queue, other)
        end
    end
    length(parent) == length(buses) || _bfm_refuse(
        "every bus must be connected to the voltage-source root")
    (; root, source_id=String(source_id), source, oriented, edge_count)
end

function _bfm_device_positions(net, data, label; allow_delta=false)
    bus = String(get(data, "bus", ""))
    buses = get(net, "bus", Dict())
    haskey(buses, bus) || _bfm_refuse("$label references unknown bus '$bus'")
    bus_terms = string.(buses[bus]["terminal_names"])
    terminals = string.(get(data, "terminal_map", String[]))
    !isempty(terminals) && allunique(terminals) && all(in(bus_terms), terminals) ||
        _bfm_refuse("$label has an invalid terminal_map")
    configuration = uppercase(String(get(data, "configuration", "WYE")))
    configuration in ("WYE", "SINGLE_PHASE") ||
        allow_delta && configuration == "DELTA" ||
        _bfm_refuse("$label has unsupported connection '$configuration'")
    neutral = get(_kr_neutral_map(net), bus, nothing)
    neutral_position = findfirst(==(neutral), terminals)
    channels = configuration == "DELTA" ? copy(terminals) :
        configuration == "SINGLE_PHASE" ? [first(terminals)] :
        [t for t in terminals if t != neutral]
    configuration == "SINGLE_PHASE" && !(length(terminals) in (1, 2)) &&
        _bfm_refuse("$label SINGLE_PHASE requires one terminal or one terminal pair")
    positions = [something(findfirst(==(t), bus_terms), 0) for t in channels]
    (; bus, terminals, channels, positions, terminal_count=length(terminals),
       configuration)
end

function _bfm_validate(net)
    tables = Set(("bus", "line", "linecode", "load", "generator",
                  "voltage_source", "shunt", "transformer"))
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
        device = _bfm_device_positions(net, load, "load/$id"; allow_delta=true)
        haskey(load, "p_nom") && haskey(load, "q_nom") ||
            _bfm_refuse("load/$id requires p_nom and q_nom")
        n = load["p_nom"] isa Real ? 1 : length(load["p_nom"])
        if device.configuration == "DELTA"
            n == (length(device.terminals) == 2 ? 1 : 3) ||
                _bfm_refuse("load/$id DELTA power arity must be one for two terminals or three for three terminals")
        end
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
        _bfm_device_positions(net, source, "voltage_source/$id")
    end
    for (id, shunt) in get(net, "shunt", Dict())
        _bfm_fields(shunt, ("bus", "terminal_map"), "shunt/$id";
            matrix=("G_", "B_"))
        bus = String(shunt["bus"])
        string.(shunt["terminal_map"]) == string.(buses[bus]["terminal_names"]) ||
            _bfm_refuse("shunt/$id must cover its complete bus terminal map")
    end
    for (subtype, table) in get(net, "transformer", Dict()), (id, data) in table
        label = "transformer/$subtype/$id"
        try
            _sdp_transformer_plan(String(subtype), data, label)
        catch err
            err isa SDPInapplicableError || rethrow()
            _bfm_refuse(err.message)
        end
        for side in ("from", "to")
            bus = String(data["bus_$side"])
            haskey(buses, bus) || _bfm_refuse("$label references unknown bus '$bus'")
            tm = string.(data["terminal_map_$side"])
            !isempty(tm) && allunique(tm) && all(in(string.(buses[bus]["terminal_names"])), tm) ||
                _bfm_refuse("$label has an invalid terminal_map_$side")
        end
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

function _bfm_connection(net, device, coils, label)
    bus_terms = string.(net["bus"][device.bus]["terminal_names"])
    local_incidence = try
        _sdp_connection(net, device.bus, device.terminals,
            device.configuration, coils)
    catch err
        err isa SDPInapplicableError || rethrow()
        _bfm_refuse("$label: $(err.message)")
    end
    D = zeros(Float64, coils, length(bus_terms))
    for (local_position, terminal) in enumerate(device.terminals)
        bus_position = something(findfirst(==(terminal), bus_terms), 0)
        D[:, bus_position] .= local_incidence[:, local_position]
    end
    D
end

function _bfm_overlap_voltage!(model, block, W, n)
    for a in 1:n, b in a:n
        @constraint(model, block[a, b] == W[a, b])
    end
end

function _bfm_cross(block, A, B)
    Any[sum(A[a, k] * block[k, h] * conj(B[b, h])
            for k in axes(A, 2), h in axes(B, 2))
        for a in axes(A, 1), b in axes(B, 1)]
end

function _bfm_add_matrix!(target, source, sign=1)
    size(target) == size(source) || throw(DimensionMismatch("lifted KCL matrix"))
    for index in eachindex(target, source)
        target[index] += sign * source[index]
    end
    target
end

function _bfm_component_block!(model, W, D, cone, live=collect(axes(W, 1)))
    n, m = size(W, 1), size(D, 1)
    nl = length(live)
    block = _sdp_psd(model, nl + m, cone)
    for a in 1:nl, b in a:nl
        @constraint(model, block[a, b] == W[live[a], live[b]])
    end
    C_live = block[1:nl, nl+1:nl+m]
    C = Any[JuMP.AffExpr(0.0) + 0im for _ in 1:n, _ in 1:m]
    for (a, position) in enumerate(live), k in 1:m
        C[position, k] = C_live[a, k]
    end
    J = block[nl+1:nl+m, nl+1:nl+m]
    terminal = Any[sum(C[a, k] * D[k, b] for k in 1:m)
                   for a in 1:n, b in 1:n]
    coil = Any[sum(D[k, a] * C[a, h] for a in 1:n)
               for k in 1:m, h in 1:m]
    (; block, C, J, live, terminal, power=Any[coil[k, k] for k in 1:m])
end

function _bfm_live_positions(net, bus)
    terms = string.(net["bus"][bus]["terminal_names"])
    grounded = Set(string.(get(net["bus"][bus],
        "perfectly_grounded_terminals", String[])))
    findall(t -> !(t in grounded), terms)
end

function _bfm_transformer_plan(subtype, data, label)
    try
        _sdp_transformer_plan(subtype, data, label)
    catch err
        err isa SDPInapplicableError || rethrow()
        _bfm_refuse(err.message)
    end
end

function _bfm_selection(bus_terms, terminal_map, label)
    P = zeros(Float64, length(terminal_map), length(bus_terms))
    for (row, terminal) in enumerate(terminal_map)
        column = findfirst(==(terminal), bus_terms)
        column === nothing && _bfm_refuse("$label references undeclared terminal '$terminal'")
        P[row, column] = 1.0
    end
    P
end

function _bfm_transformer_block!(model, net, subtype, id, data, voltage_moments,
                                 balance, powers, cone, ib, zb, root, root_pu)
    label = "transformer/$subtype/$id"
    plan = _bfm_transformer_plan(subtype, data, label)
    from, to = String(data["bus_from"]), String(data["bus_to"])
    from_terms = string.(net["bus"][from]["terminal_names"])
    to_terms = string.(net["bus"][to]["terminal_names"])
    map_from = string.(data["terminal_map_from"])
    map_to = string.(data["terminal_map_to"])
    Pf = _bfm_selection(from_terms, map_from, label)
    Pt = _bfm_selection(to_terms, map_to, label)
    Uf, Ut = plan.Df * Pf, plan.Dt * Pt
    nf, nt = length(from_terms), length(to_terms)
    mf, mt = size(Uf, 1), size(Ut, 1)
    ideal_ground = Tuple{Symbol,Int}[]
    finite_ground = Tuple{Symbol,Int,ComplexF64}[]
    for (side, bus, tm) in ((:from, from, map_from), (:to, to, map_to))
        rkey, xkey = "r_neutral_$side", "x_neutral_$side"
        haskey(data, rkey) || haskey(data, xkey) || continue
        neutral = get(_kr_neutral_map(net), bus, nothing)
        position = findfirst(==(neutral), tm)
        position === nothing && _bfm_refuse("$label $side grounding requires an explicit neutral")
        z = complex(Float64(get(data, rkey, 0.0)), Float64(get(data, xkey, 0.0)))
        isfinite(z) && real(z) >= 0 && imag(z) >= 0 ||
            _bfm_refuse("$label has invalid $side grounding impedance")
        iszero(z) ? push!(ideal_ground, (side, position)) :
                    push!(finite_ground, (side, position, z / zb))
    end
    nb = length(plan.bonds)
    ng = length(ideal_ground)
    vf = 1:nf
    vt = nf+1:nf+nt
    jf = nf+nt+1:nf+nt+mf
    jt = nf+nt+mf+1:nf+nt+mf+mt
    bond = nf+nt+mf+mt+1:nf+nt+mf+mt+nb
    ground = nf+nt+mf+mt+nb+1:nf+nt+mf+mt+nb+ng
    dimension = nf + nt + mf + mt + nb + ng

    equations = Vector{Vector{ComplexF64}}()
    for k in 1:mt
        row = zeros(ComplexF64, dimension)
        row[vt] .= Ut[k, :]
        row[jt[k]] -= plan.Zt[k] / zb
        row[vf] .-= vec(plan.R[k:k, :] * Uf)
        row[jf] .+= plan.R[k, :] .* (plan.Zf ./ zb)
        push!(equations, row)
    end
    for k in 1:mf
        row = zeros(ComplexF64, dimension)
        row[jf[k]] = 1
        row[jt] .+= adjoint(plan.R)[k, :]
        push!(equations, row)
    end
    for (f, t) in plan.bonds
        row = zeros(ComplexF64, dimension)
        row[vf[findfirst(==(map_from[f]), from_terms)]] = 1
        row[vt[findfirst(==(map_to[t]), to_terms)]] = -1
        push!(equations, row)
    end
    for (side, position) in ideal_ground
        row = zeros(ComplexF64, dimension)
        if side == :from
            row[vf[findfirst(==(map_from[position]), from_terms)]] = 1
        else
            row[vt[findfirst(==(map_to[position]), to_terms)]] = 1
        end
        push!(equations, row)
    end
    for (bus, indices) in ((from, vf), (to, vt))
        bus == root || continue
        anchor = something(findfirst(!iszero, root_pu), 0)
        anchor > 0 || _bfm_refuse("$label root side has no nonzero reference voltage")
        for k in eachindex(root_pu)
            k == anchor && continue
            row = zeros(ComplexF64, dimension)
            row[indices[k]] = 1
            row[indices[anchor]] = -root_pu[k] / root_pu[anchor]
            push!(equations, row)
        end
    end
    for (bus, terms, indices) in ((from, from_terms, vf), (to, to_terms, vt))
        bus == root && continue
        grounded = Set(string.(get(net["bus"][bus],
            "perfectly_grounded_terminals", String[])))
        for k in eachindex(terms)
            terms[k] in grounded || continue
            row = zeros(ComplexF64, dimension)
            row[indices[k]] = 1
            push!(equations, row)
        end
    end

    A = isempty(equations) ? zeros(ComplexF64, 0, dimension) :
        reduce(vcat, (reshape(row, 1, :) for row in equations))
    N = nullspace(A)
    size(N, 2) > 0 || _bfm_refuse("$label winding equations leave no electrical state")
    reduced = _sdp_psd(model, size(N, 2), cone)
    block = Any[sum(N[a, k] * reduced[k, h] * conj(N[b, h])
                    for k in axes(N, 2), h in axes(N, 2))
                for a in 1:dimension, b in 1:dimension]
    for (bus, indices, count) in ((from, vf, nf), (to, vt, nt))
        if bus == root
            anchor = something(findfirst(!iszero, root_pu), 1)
            @constraint(model, block[indices[anchor], indices[anchor]] ==
                               voltage_moments[bus][anchor, anchor])
        else
            terms = string.(net["bus"][bus]["terminal_names"])
            grounded = Set(string.(get(net["bus"][bus],
                "perfectly_grounded_terminals", String[])))
            live = findall(t -> !(t in grounded), terms)
            for a in live, b in live
                a <= b || continue
                @constraint(model, block[indices[a], indices[b]] ==
                                   voltage_moments[bus][a, b])
            end
        end
    end

    Tf = zeros(ComplexF64, nf, dimension)
    Tt = zeros(ComplexF64, nt, dimension)
    Cf = transpose(Pf) * transpose(plan.Df)
    Ct = transpose(Pt) * transpose(plan.Dt)
    Tf[:, vf] .+= Cf * Diagonal(plan.Yf .* zb) * Uf
    Tf[:, jf] .+= Cf
    Tt[:, vt] .+= Ct * Diagonal(plan.Yt .* zb) * Ut
    Tt[:, jt] .+= Ct
    for (k, (f, t)) in enumerate(plan.bonds)
        Tf[findfirst(==(map_from[f]), from_terms), bond[k]] += 1
        Tt[findfirst(==(map_to[t]), to_terms), bond[k]] -= 1
    end
    for (side, position, zpu) in finite_ground
        if side == :from
            p = findfirst(==(map_from[position]), from_terms)
            Tf[p, vf[p]] += inv(zpu)
        else
            p = findfirst(==(map_to[position]), to_terms)
            Tt[p, vt[p]] += inv(zpu)
        end
    end
    for (k, (side, position)) in enumerate(ideal_ground)
        if side == :from
            p = findfirst(==(map_from[position]), from_terms)
            Tf[p, ground[k]] += 1
        else
            p = findfirst(==(map_to[position]), to_terms)
            Tt[p, ground[k]] += 1
        end
    end
    Ef = zeros(ComplexF64, nf, dimension)
    Et = zeros(ComplexF64, nt, dimension)
    for k in 1:nf; Ef[k, vf[k]] = 1; end
    for k in 1:nt; Et[k, vt[k]] = 1; end
    Mf = _bfm_cross(block, Ef, Tf)
    Mt = _bfm_cross(block, Et, Tt)
    _bfm_add_matrix!(balance[from], Mf)
    _bfm_add_matrix!(balance[to], Mt)
    key = "$subtype/$id"
    powers[(:transformer_from, key)] = Any[Mf[k, k] for k in 1:nf]
    powers[(:transformer_to, key)] = Any[Mt[k, k] for k in 1:nt]
    Ajf = zeros(ComplexF64, mf, dimension)
    Ajt = zeros(ComplexF64, mt, dimension)
    for k in 1:mf; Ajf[k, jf[k]] = 1; end
    for k in 1:mt; Ajt[k, jt[k]] = 1; end
    coil_from = _bfm_cross(block, hcat(Uf, zeros(mf, dimension - nf)), Ajf)
    coil_to_map = zeros(ComplexF64, mt, dimension); coil_to_map[:, vt] .= Ut
    coil_to = _bfm_cross(block, coil_to_map, Ajt)
    powers[(:transformer_coil_from, key)] = Any[coil_from[k, k] for k in 1:mf]
    powers[(:transformer_coil_to, key)] = Any[coil_to[k, k] for k in 1:mt]

    for side in (:from, :to)
        rating_key = "i_max_$side"
        haskey(data, rating_key) || continue
        delta = subtype == "delta_wye" && side == :from ||
                subtype == "wye_delta" && side == :to
        map = side == :from ? (delta ? Ajf : Tf) : (delta ? Ajt : Tt)
        count = size(map, 1)
        limits = _bfm_vector(data, rating_key, count, label)
        gram = _bfm_cross(block, map, map)
        for k in 1:count
            limits[k] >= 0 || _bfm_refuse("$label has negative $rating_key")
            @constraint(model, real(gram[k, k]) <= (limits[k] / ib)^2)
        end
    end
    (; key, subtype, id=String(id), from, to, block, reduced, nullspace=N,
       vf, vt, jf, jt, Tf, Tt, Uf, Ut, Ajf, Ajt, dimension)
end

struct BranchFlowSDPBuild
    model::JuMP.Model
    voltage_moments::Dict{String,Any}
    edge_blocks::Dict{String,Any}
    component_blocks::Dict{Tuple{Symbol,String},Any}
    transformer_blocks::Dict{String,Any}
    edge_records::Vector{NamedTuple}
    component_records::Vector{NamedTuple}
    transformer_records::Vector{NamedTuple}
    topology::Vector{NamedTuple}
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

"""Build the radial matrix-KCL branch-flow SDP on its declared component slice."""
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
    balance = Dict{String,Matrix{Any}}()
    for (bus, data) in sort!(collect(net["bus"]); by=first)
        n = length(data["terminal_names"])
        voltage_moments[bus] = _bfm_hermitian(model, n)
        balance[bus] = Any[JuMP.AffExpr(0.0) + 0im for _ in 1:n, _ in 1:n]
    end

    edge_blocks = Dict{String,Any}()
    component_blocks = Dict{Tuple{Symbol,String},Any}()
    transformer_blocks = Dict{String,Any}()
    edge_records = NamedTuple[]
    component_records = NamedTuple[]
    transformer_records = NamedTuple[]
    powers = Dict{Tuple{Symbol,String},Vector{Any}}()
    for oriented in filter(edge -> edge.kind == :line, plan.oriented)
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
        receiving_matrix = Any[S[a, b] - sum(Z[a, h] * L[h, b] for h in 1:n)
                               for a in 1:n, b in 1:n]
        receiving = Any[receiving_matrix[k, k] for k in 1:n]
        if oriented.reversed
            powers[(:line_from, id)] = Any[-s for s in receiving]
            powers[(:line_to, id)] = sending
        else
            powers[(:line_from, id)] = sending
            powers[(:line_to, id)] = Any[-s for s in receiving]
        end
        _bfm_add_matrix!(balance[parent], S)
        _bfm_add_matrix!(balance[child], receiving_matrix, -1)
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
            Z, sending, receiving, receiving_matrix, S, L))
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
    function add_dispatch!(family, id, data, device)
        bus, positions = device.bus, device.positions
        n = length(positions)
        D = _bfm_connection(net, device, n, "$family/$id")
        fixed_voltage = family == "voltage_source"
        if fixed_voltage
            jr = Any[@variable(model) for _ in 1:n]
            ji = Any[@variable(model) for _ in 1:n]
            current = Any[jr[k] + im * ji[k] for k in 1:n]
            coil_voltage = D * root_pu
            s = Any[coil_voltage[k] * conj(current[k]) for k in 1:n]
            terminal = Any[root_pu[a] *
                sum(D[k, b] * conj(current[k]) for k in 1:n)
                for a in eachindex(root_pu), b in eachindex(root_pu)]
            push!(component_records, (; family=Symbol(family), id=String(id), bus,
                D, block=nothing, C=nothing, J=nothing, law=:fixed_voltage,
                current))
        else
            local_moment = _bfm_component_block!(model, voltage_moments[bus], D,
                options.cone, _bfm_live_positions(net, bus))
            component_blocks[(Symbol(family), String(id))] = local_moment.block
            s = local_moment.power
            terminal = local_moment.terminal
            push!(component_records, (; family=Symbol(family), id=String(id), bus,
                D, block=local_moment.block, C=local_moment.C, J=local_moment.J,
                live=local_moment.live, law=:dispatch))
        end
        p = Any[real(value) for value in s]
        q = Any[imag(value) for value in s]
        _bfm_box!(model, p, q, data, positions, device.terminal_count,
                  "$family/$id", sb)
        smax = _bfm_phase_vector(data, "s_max", positions,
            device.terminal_count, "$family/$id")
        imax = _bfm_phase_vector(data, "i_max", positions,
            device.terminal_count, "$family/$id")
        for k in 1:n
            if smax !== nothing
                smax[k] >= 0 || _bfm_refuse("$family/$id has a negative apparent-power limit")
                @constraint(model, [smax[k] / sb, p[k], q[k]] in SecondOrderCone())
            end
            if imax !== nothing
                imax[k] >= 0 || _bfm_refuse("$family/$id has a negative current limit")
                if fixed_voltage
                    @constraint(model, [imax[k] / ib,
                        real(current[k]), imag(current[k])] in SecondOrderCone())
                else
                    @constraint(model, real(local_moment.J[k, k]) <= (imax[k] / ib)^2)
                end
            end
        end
        powers[(Symbol(family), String(id))] = s
        _bfm_add_matrix!(balance[bus], terminal, -1)
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
            JuMP.add_to_expression!(objective, coefficient * p[k])
        end
        s
    end

    source_device = _bfm_device_positions(net, source, "voltage_source/$(plan.source_id)")
    add_dispatch!("voltage_source", plan.source_id, source, source_device)

    for (id, generator) in sort!(collect(get(net, "generator", Dict())); by=first)
        device = _bfm_device_positions(net, generator, "generator/$id")
        add_dispatch!("generator", id, generator, device)
    end
    for (id, load) in sort!(collect(get(net, "load", Dict())); by=first)
        device = _bfm_device_positions(net, load, "load/$id"; allow_delta=true)
        n = load["p_nom"] isa Real ? 1 : length(load["p_nom"])
        p = _bfm_vector(load, "p_nom", n, "load/$id")
        q = _bfm_vector(load, "q_nom", n, "load/$id")
        (p === nothing || q === nothing) &&
            _bfm_refuse("load/$id requires p_nom and q_nom")
        law = lowercase(String(get(load, "model", "constant_power")))
        D = _bfm_connection(net, device, n, "load/$id")
        W = voltage_moments[device.bus]
        s = Any[]; terminal = nothing
        if law == "constant_power"
            local_moment = _bfm_component_block!(model, W, D, options.cone,
                _bfm_live_positions(net, device.bus))
            component_blocks[(:load, String(id))] = local_moment.block
            for k in 1:n
                @constraint(model, real(local_moment.power[k]) == p[k] / sb)
                @constraint(model, imag(local_moment.power[k]) == q[k] / sb)
            end
            append!(s, local_moment.power)
            terminal = local_moment.terminal
            push!(component_records, (; family=:load, id=String(id), bus=device.bus,
                D, block=local_moment.block, C=local_moment.C, J=local_moment.J,
                live=local_moment.live, law=:constant_power))
        else
            vnom = _bfm_vector(load, "v_nom", n, "load/$id")
            vnom === nothing && _bfm_refuse("load/$id constant impedance requires v_nom")
            all(>(0), vnom) || _bfm_refuse("load/$id v_nom must be positive")
            factors = complex.(p, q) ./ sb .* (vb ./ vnom).^2
            C = Any[sum(W[a, b] * D[k, b] for b in axes(W, 2)) * factors[k]
                    for a in axes(W, 1), k in 1:n]
            coil = Any[sum(D[k, a] * C[a, h] for a in axes(W, 1))
                       for k in 1:n, h in 1:n]
            append!(s, Any[coil[k, k] for k in 1:n])
            terminal = Any[sum(C[a, k] * D[k, b] for k in 1:n)
                           for a in axes(W, 1), b in axes(W, 2)]
            push!(component_records, (; family=:load, id=String(id), bus=device.bus,
                D, block=nothing, C, J=nothing, law=:constant_impedance,
                admittance=conj.(complex.(p, q)) ./ vnom.^2))
        end
        powers[(:load, String(id))] = s
        _bfm_add_matrix!(balance[device.bus], terminal)
    end
    for (id, shunt) in sort!(collect(get(net, "shunt", Dict())); by=first)
        bus = String(shunt["bus"])
        terms = string.(net["bus"][bus]["terminal_names"])
        Y = _l3f_shunt_matrix(shunt, length(terms)) * zb
        W = voltage_moments[bus]
        terminal = Any[sum(W[a, h] * conj(Y[b, h]) for h in eachindex(terms))
                       for a in eachindex(terms), b in eachindex(terms)]
        s = Any[terminal[k, k] for k in eachindex(terms)]
        powers[(:shunt, String(id))] = s
        _bfm_add_matrix!(balance[bus], terminal)
    end

    for (subtype, table) in sort!(collect(get(net, "transformer", Dict())); by=first),
        (id, data) in sort!(collect(table); by=first)
        record = _bfm_transformer_block!(model, net, String(subtype), String(id),
            data, voltage_moments, balance, powers, options.cone, ib, zb,
            plan.root, root_pu)
        transformer_blocks[record.key] = record.block
        push!(transformer_records, record)
    end

    matrix_kcl_count = 0
    matrix_kcl = Dict{Tuple{String,Int,Int,Symbol},JuMP.ConstraintRef}()
    for (bus, data) in net["bus"]
        terms = string.(data["terminal_names"])
        grounded = Set(string.(get(data, "perfectly_grounded_terminals", String[])))
        # W_root is a prescribed rank-one Gram. One nonzero voltage row is an
        # exact basis for v_root*r_root^H and avoids dependent equalities on
        # the exposed PSD faces. Other buses retain every voltage row.
        rows = bus == plan.root ? [something(findfirst(!iszero, root_pu), 1)] :
                                  collect(eachindex(terms))
        for a in rows, b in eachindex(terms)
            terms[b] in grounded && continue
            matrix_kcl[(bus, a, b, :real)] =
                @constraint(model, real(balance[bus][a, b]) == 0)
            matrix_kcl[(bus, a, b, :imag)] =
                @constraint(model, imag(balance[bus][a, b]) == 0)
            matrix_kcl_count += 1
        end
    end
    model.ext[:branch_flow_balance] = balance
    model.ext[:branch_flow_matrix_kcl] = matrix_kcl
    objective_scale = options.scale_objective ?
        max(maximum(abs, values(objective.terms); init=0.0), 1e-12) : 1.0
    @objective(model, Min, objective / objective_scale)
    diagnostics = Dict{Symbol,Any}(
        :formulation => :branch_flow_sdp,
        :scope => :radial_matrix_kcl_v2,
        :bus_count => length(net["bus"]),
        :edge_count => plan.edge_count,
        :line_count => length(edge_records),
        :transformer_count => length(transformer_records),
        :component_block_count => length(component_blocks),
        :matrix_kcl_entries => matrix_kcl_count,
        :cone => options.cone,
        :objective_scale => objective_scale,
    )
    if optimizer isa _SDPDefaultOptimizer
        JuMP.set_optimizer(model, default_sdp_optimizer(:dense))
        diagnostics[:optimizer_profile] = :clarabel_dense
    else
        diagnostics[:optimizer_profile] = :caller_supplied
    end
    BranchFlowSDPBuild(model, voltage_moments, edge_blocks, component_blocks,
        transformer_blocks, edge_records, component_records, transformer_records,
        plan.oriented, powers, net, options, vb, ib, plan.root, root_voltage,
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
    ratios = Float64[]; edge_ratios = Float64[]
    rank_ratios = Dict{String,Float64}()
    function record_ratio!(label, block)
        eigenvalues = eigvals(Hermitian(block))
        value = length(eigenvalues) > 1 ?
            max(0.0, eigenvalues[end-1]) / max(eps(), eigenvalues[end]) : 0.0
        push!(ratios, value); rank_ratios[label] = value
    end
    for edge in build.edge_records
        block = Matrix{ComplexF64}(JuMP.value.(build.edge_blocks[edge.id]))
        n = size(edge.S, 1)
        S[edge.id] = block[1:n, n+1:2n] * sb
        L[edge.id] = block[n+1:2n, n+1:2n] * ib^2
        record_ratio!("line/$(edge.id)", block)
        push!(edge_ratios, rank_ratios["line/$(edge.id)"])
    end
    component_values = Dict(key => Matrix{ComplexF64}(JuMP.value.(block))
        for (key, block) in build.component_blocks)
    transformer_values = Dict(key => Matrix{ComplexF64}(JuMP.value.(block))
        for (key, block) in build.transformer_blocks)
    for (key, block) in component_values
        record_ratio!("$(key[1])/$(key[2])", block)
    end
    for (key, block) in transformer_values
        record_ratio!("transformer/$key", block)
    end
    voltage = Dict{Tuple{String,String},ComplexF64}()
    for (terminal, value) in zip(build.network["bus"][build.root]["terminal_names"],
                                 build.root_voltage)
        voltage[(build.root, terminal)] = value
    end
    currents = Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    line_records = Dict(edge.id => edge for edge in build.edge_records)
    transformer_records = Dict(record.key => record for record in build.transformer_records)
    for oriented in build.topology
        terms_parent = build.network["bus"][oriented.parent]["terminal_names"]
        parent_voltage = ComplexF64[voltage[(oriented.parent, t)] / vb
                                    for t in terms_parent]
        denominator = real(dot(parent_voltage, parent_voltage))
        if oriented.kind == :line
            edge = line_records[oriented.id]
            Smat = S[edge.id] / sb
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
        else
            key = "$(oriented.subtype)/$(oriented.id)"
            record = transformer_records[key]
            block = transformer_values[key]
            parent_indices = oriented.parent == record.from ? record.vf : record.vt
            state = denominator > eps() ?
                block[:, parent_indices] * parent_voltage / denominator :
                zeros(ComplexF64, record.dimension)
            child_indices = oriented.child == record.from ? record.vf : record.vt
            for (terminal, value) in zip(
                build.network["bus"][oriented.child]["terminal_names"], state[child_indices])
                voltage[(oriented.child, terminal)] = value * vb
            end
            currents[(:transformer_from, key)] = record.Tf * state * ib
            currents[(:transformer_to, key)] = record.Tt * state * ib
            currents[(:transformer_coil_from, key)] = record.Ajf * state * ib
            currents[(:transformer_coil_to, key)] = record.Ajt * state * ib
        end
    end
    powers = Dict(key => ComplexF64.(JuMP.value.(values)) .* sb
                  for (key, values) in build.powers)
    for record in build.component_records
        terms = string.(build.network["bus"][record.bus]["terminal_names"])
        bus_voltage = ComplexF64[voltage[(record.bus, terminal)] for terminal in terms]
        if record.law == :fixed_voltage
            coil_current = ComplexF64.(JuMP.value.(record.current)) .* ib
        elseif record.law == :constant_impedance
            coil_current = record.admittance .* (record.D * bus_voltage)
        else
            block = component_values[(record.family, record.id)]
            live_voltage = bus_voltage[record.live] / vb
            nl = length(live_voltage)
            denominator = real(dot(live_voltage, live_voltage))
            coil_current = denominator > eps() ?
                block[nl+1:end, 1:nl] * live_voltage / denominator * ib :
                zeros(ComplexF64, size(record.D, 1))
        end
        if record.family == :voltage_source
            terminal_current = transpose(record.D) * coil_current
            data = build.network["voltage_source"][record.id]
            positions = [findfirst(==(terminal), terms) for terminal in data["terminal_map"]]
            currents[(record.family, record.id)] = terminal_current[positions]
        else
            currents[(record.family, record.id)] = coil_current
        end
    end
    bound = try JuMP.objective_bound(build.model) catch; NaN end
    isfinite(bound) || (bound = try JuMP.dual_objective_value(build.model) catch; NaN end)
    bound *= build.objective_scale
    ratio = maximum(edge_ratios; init=0.0)
    diagnostics[:local_rank_ratios] = rank_ratios
    diagnostics[:recovery] = :tree
    BranchFlowSDPResult(JuMP.objective_value(build.model) * build.objective_scale,
        bound, W, S, L, voltage, currents, powers, ratio, status, diagnostics)
end
