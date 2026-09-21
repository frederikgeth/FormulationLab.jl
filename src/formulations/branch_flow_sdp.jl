"""Options for the multiphase branch-flow SDP relaxation."""
Base.@kwdef struct BranchFlowSDPOptions
    s_base::Float64 = 1e4
    objective::Symbol = :cost
    cone::Symbol = :real
    recovery::Symbol = :tree
    scale_objective::Bool = true
    lnc::Symbol = :off
    voltage_lncs::Vector{VoltageLNC} = VoltageLNC[]
    implied_current_limits::Bool = true
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
        _bfm_refuse("$label field '$key' is outside the BranchFlowSDP contract")
    end
end

function _bfm_vector(data, key, n, label; default=nothing)
    haskey(data, key) || return default
    raw = data[key]
    values = try
        raw isa Real ? fill(Float64(raw), n) : Float64.(raw)
    catch
        _bfm_refuse("$label $key must contain $n finite numeric values")
    end
    length(values) == n && all(isfinite, values) ||
        _bfm_refuse("$label $key must contain $n finite values")
    values
end

function _bfm_required(data, keys, label)
    missing = [key for key in keys if !haskey(data, key)]
    isempty(missing) || _bfm_refuse(
        "$label is missing required field$(length(missing) == 1 ? "" : "s") " *
        join("'" .* missing .* "'", ", "))
end

function _bfm_nonnegative(values, label)
    values === nothing || all(>=(0), values) || _bfm_refuse("$label must be nonnegative")
    values
end

function _bfm_phase_vector(data, key, phase_positions, terminal_count, label;
                           default=nothing)
    haskey(data, key) || return default
    raw = data[key]
    values = try
        raw isa Real ? fill(Float64(raw), length(phase_positions)) : Float64.(raw)
    catch
        _bfm_refuse("$label $key must contain finite numeric values")
    end
    if length(values) == terminal_count
        values = values[phase_positions]
    end
    length(values) == length(phase_positions) && all(isfinite, values) ||
        _bfm_refuse("$label $key must match its phase channels or complete terminal map")
    values
end

function _bfm_line_phase_positions(net, line)
    declared_from = String(line["bus_from"])
    terms = string.(net["bus"][declared_from]["terminal_names"])
    neutral = get(_kr_neutral_map(net), declared_from, nothing)
    findall(!=(neutral), terms)
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
        subtype == "n_winding" && continue
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
    isempty(sources) && _bfm_refuse("at least one voltage source is required")
    for (id, source) in sources
        bus = String(get(source, "bus", ""))
        haskey(buses, bus) || _bfm_refuse(
            "voltage_source/$id references unknown bus '$bus'")
    end

    adjacency = Dict(String(b) => NamedTuple[] for b in keys(buses))
    binary_edges = NamedTuple[]
    function add_edge!(edge)
        push!(binary_edges, edge)
        push!(adjacency[edge.from], merge(edge, (; other=edge.to)))
        push!(adjacency[edge.to], merge(edge, (; other=edge.from)))
    end
    for (id_raw, line) in get(net, "line", Dict())
        id = String(id_raw)
        from = String(get(line, "bus_from", ""))
        to = String(get(line, "bus_to", ""))
        from != to || _bfm_refuse("line/$id is a self loop")
        haskey(adjacency, from) && haskey(adjacency, to) ||
            _bfm_refuse("line/$id references an unknown bus")
        add_edge!((; uid="line/$id", kind=:line, id, subtype="", from, to,
            data=line))
    end
    transformer_edges = _bfm_transformer_edges(net)
    for edge in transformer_edges
        edge.from != edge.to || _bfm_refuse(
            "transformer/$(edge.subtype)/$(edge.id) is a self loop")
        haskey(adjacency, edge.from) && haskey(adjacency, edge.to) ||
            _bfm_refuse("transformer/$(edge.subtype)/$(edge.id) references an unknown bus")
        add_edge!(merge(edge, (; uid="transformer/$(edge.subtype)/$(edge.id)")))
    end
    for (id_raw, switch) in get(net, "switch", Dict())
        get(switch, "open_switch", nothing) === false || continue
        id = String(id_raw)
        from, to = String(get(switch, "bus_from", "")),
                   String(get(switch, "bus_to", ""))
        from != to || _bfm_refuse("switch/$id is a self loop")
        haskey(adjacency, from) && haskey(adjacency, to) ||
            _bfm_refuse("switch/$id references an unknown bus")
        add_edge!((; uid="switch/$id", kind=:switch, id, subtype="", from, to,
            data=switch))
    end
    hyperedges = NamedTuple[]
    for (id_raw, data) in get(get(net, "transformer", Dict()), "n_winding", Dict())
        id = String(id_raw)
        windings = get(data, "windings", Any[])
        isempty(windings) && continue
        anchor = String(get(first(windings), "bus", ""))
        haskey(adjacency, anchor) || _bfm_refuse(
            "transformer/n_winding/$id references an unknown bus")
        for leg in 2:length(windings)
            winding = windings[leg]
            other = String(get(winding, "bus", ""))
            haskey(adjacency, other) || _bfm_refuse(
                "transformer/n_winding/$id references an unknown bus")
            other == anchor && continue
            edge = (; uid="transformer/n_winding/$id/$leg", kind=:n_winding,
                id, subtype="n_winding", from=anchor, to=other, data)
            add_edge!(edge)
            push!(hyperedges, edge)
        end
    end

    source_buses = Dict(String(id) => String(data["bus"]) for (id, data) in sources)
    roots = String[]
    parent = Dict{String,String}()
    parent_edge = Dict{String,String}()
    depth = Dict{String,Int}()
    component = Dict{String,Int}()
    source_free_components = 0
    for seed in sort!(String.(collect(keys(buses))))
        haskey(component, seed) && continue
        members = String[]
        queue = [seed]
        seen = Set([seed])
        while !isempty(queue)
            bus = popfirst!(queue)
            push!(members, bus)
            for edge in adjacency[bus]
                edge.other in seen && continue
                push!(seen, edge.other)
                push!(queue, edge.other)
            end
        end
        candidates = sort!([bus for bus in members if bus in values(source_buses)])
        isempty(candidates) && (source_free_components += 1)
        root = isempty(candidates) ? first(sort!(members)) : first(candidates)
        push!(roots, root)
        cid = length(roots)
        parent[root] = ""
        depth[root] = 0
        queue = [root]
        while !isempty(queue)
            bus = popfirst!(queue)
            component[bus] = cid
            for edge in adjacency[bus]
                other = edge.other
                haskey(depth, other) && continue
                parent[other] = bus
                parent_edge[other] = edge.uid
                depth[other] = depth[bus] + 1
                push!(queue, other)
            end
        end
    end
    oriented = NamedTuple[]
    for edge in binary_edges
        if depth[edge.from] <= depth[edge.to]
            p, c, reversed = edge.from, edge.to, false
        else
            p, c, reversed = edge.to, edge.from, true
        end
        tree_edge = get(parent_edge, c, "") == edge.uid && get(parent, c, "") == p
        push!(oriented, (; kind=edge.kind, id=edge.id, subtype=edge.subtype,
            parent=p, child=c, reversed, tree_edge, uid=edge.uid,
            depth=depth[c]))
    end
    source_id, source = first(sort!(collect(sources); by=first))
    root = String(source["bus"])
    cycle_count = length(binary_edges) - (length(buses) - length(roots))
    (; root, source_id=String(source_id), source, sources, source_buses, roots,
       parent, component, oriented, edge_count=length(binary_edges),
       cycle_count=max(cycle_count, 0),
       requires_global_voltage=length(sources) > 1 || cycle_count > 0 ||
           !isempty(hyperedges) || source_free_components > 0,
       source_free_components)
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
    channels = configuration == "DELTA" ? copy(terminals) :
        configuration == "SINGLE_PHASE" ? [first(terminals)] :
        [t for t in terminals if t != neutral]
    configuration == "SINGLE_PHASE" && !(length(terminals) in (1, 2)) &&
        _bfm_refuse("$label SINGLE_PHASE requires one terminal or one terminal pair")
    # Component arrays are in terminal_map order, while D embeds those channels
    # in bus-terminal order. Keep the two index spaces explicit.
    channel_positions = [something(findfirst(==(t), terminals), 0) for t in channels]
    terminal_bus_positions =
        [something(findfirst(==(t), bus_terms), 0) for t in terminals]
    (; bus, terminals, channels, channel_positions, terminal_bus_positions,
       terminal_count=length(terminals), configuration)
end

function _bfm_channel_count(device, label)
    if device.configuration == "DELTA"
        length(device.terminals) == 2 && return 1
        length(device.terminals) == 3 && return 3
        _bfm_refuse("$label DELTA requires two or three terminals")
    end
    length(device.channels)
end

function _bfm_dispatch_layout(device, label)
    if device.configuration == "DELTA"
        n = _bfm_channel_count(device, label)
        return (; count=n, positions=collect(1:n), terminal_count=n)
    end
    (; count=length(device.channel_positions), positions=device.channel_positions,
       terminal_count=device.terminal_count)
end

function _bfm_validate_dispatch(data, device, label)
    layout = _bfm_dispatch_layout(device, label)
    for key in ("p_min", "p_max", "q_min", "q_max", "cost", "energy_cost_rate")
        _bfm_phase_vector(data, key, layout.positions,
            layout.terminal_count, label)
    end
    for key in ("s_max", "i_max")
        values = _bfm_phase_vector(data, key, layout.positions,
            layout.terminal_count, label)
        _bfm_nonnegative(values, "$label $key")
    end
    haskey(data, "cost") && haskey(data, "energy_cost_rate") &&
        data["cost"] != data["energy_cost_rate"] &&
        _bfm_refuse("$label has conflicting cost aliases")
    nothing
end

function _bfm_validate(net)
    tables = Set(("bus", "line", "linecode", "load", "generator",
                  "voltage_source", "shunt", "transformer", "switch",
                  "capacitor"))
    metadata = Set(("name", "meta", "_meta", "extras", "terminal_conventions",
                    "wire_data", "line_geometry"))
    for (key_raw, value) in net
        key = String(key_raw)
        empty_value = (value isa AbstractDict || value isa AbstractVector) && isempty(value)
        key in tables || key in metadata || empty_value ||
            _bfm_refuse("nonempty table '$key' is outside the BranchFlowSDP contract")
    end
    plan = _bfm_topology(net)
    buses = net["bus"]
    for (id, bus) in buses
        _bfm_fields(bus, ("terminal_names", "perfectly_grounded_terminals",
            "neutral_terminal", "v_min", "v_max", "vn_max", "vpn_min",
            "vpn_max", "vpp_min", "vpp_max", "vpos_min", "vpos_max",
            "vneg_max", "vzero_max"), "bus/$id")
        terms = string.(get(bus, "terminal_names", String[]))
        !isempty(terms) && allunique(terms) ||
            _bfm_refuse("bus/$id requires distinct terminal_names")
        all(in(terms), string.(get(bus, "perfectly_grounded_terminals", String[]))) ||
            _bfm_refuse("bus/$id grounds an undeclared terminal")
        maps = _bfm_voltage_maps(net, String(id))
        for key in ("v_min", "v_max", "vpn_min", "vpn_max", "vpp_min",
                    "vpp_max", "vn_max", "vpos_min", "vpos_max", "vneg_max",
                    "vzero_max")
            haskey(bus, key) || continue
            prefix = startswith(key, "v_") ? key : first(split(key, "_"))
            haskey(maps, prefix) || _bfm_refuse(
                "bus/$id $key requires the corresponding terminals")
            _bfm_nonnegative(_bfm_vector(bus, key, length(maps[prefix]),
                "bus/$id"), "bus/$id $key")
        end
    end
    for (id, line) in get(net, "line", Dict())
        label = "line/$id"
        _bfm_fields(line, ("bus_from", "bus_to", "terminal_map_from",
            "terminal_map_to", "linecode", "length", "i_max", "s_max"),
            label; matrix=("R_series_", "X_series_", "G_from_", "B_from_",
                           "G_to_", "B_to_"))
        _bfm_required(line,
            ("bus_from", "bus_to", "terminal_map_from", "terminal_map_to"), label)
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
        n = length(from_terms)
        _, has_r = _bfm_line_matrix(coefficient_data, "R_series_", n, label)
        _, has_x = _bfm_line_matrix(coefficient_data, "X_series_", n, label)
        has_r || has_x || _bfm_refuse("$label has no series impedance")
        for prefix in ("G_from_", "B_from_", "G_to_", "B_to_")
            _bfm_line_matrix(coefficient_data, prefix, n, label)
        end
        if haskey(line, "length")
            length_scale = line["length"]
            length_scale isa Real && isfinite(length_scale) && length_scale > 0 ||
                _bfm_refuse("$label length must be positive and finite")
        end
        ratings = Dict{String,Any}()
        for key in ("i_max", "s_max")
            if haskey(line, key)
                ratings[key] = line[key]
            elseif haskey(coefficient_data, key)
                ratings[key] = coefficient_data[key]
            end
        end
        _bfm_nonnegative(_bfm_vector(ratings, "i_max", n, label), "$label i_max")
        phase_positions = _bfm_line_phase_positions(net, line)
        _bfm_nonnegative(
            _bfm_phase_vector(ratings, "s_max", phase_positions, n, label),
            "$label s_max")
    end
    for (id, code) in get(net, "linecode", Dict())
        _bfm_fields(code, ("i_max", "s_max", "source", "line_geometry", "derivation"), "linecode/$id";
            matrix=("R_series_", "X_series_", "G_from_", "B_from_",
                    "G_to_", "B_to_"))
    end
    for (id, load) in get(net, "load", Dict())
        _bfm_fields(load, ("bus", "terminal_map", "configuration", "model",
            "p_nom", "q_nom", "v_nom", "alpha_z", "alpha_i", "alpha_p",
            "beta_z", "beta_i", "beta_p", "gamma_p", "gamma_q"), "load/$id")
        law = lowercase(String(get(load, "model", "constant_power")))
        law in ("constant_power", "constant_impedance", "constant_current",
                "zip", "exponential") ||
            _bfm_refuse("load/$id model '$law' is not implemented")
        device = _bfm_device_positions(net, load, "load/$id"; allow_delta=true)
        _bfm_required(load, ("p_nom", "q_nom"), "load/$id")
        n = _bfm_channel_count(device, "load/$id")
        _bfm_vector(load, "p_nom", n, "load/$id")
        _bfm_vector(load, "q_nom", n, "load/$id")
        if law != "constant_power"
            vnom = _bfm_vector(load, "v_nom", n, "load/$id")
            vnom === nothing && _bfm_refuse("load/$id $law requires v_nom")
            all(>(0), vnom) || _bfm_refuse("load/$id v_nom must be positive")
        end
        if law == "zip"
            for keys in (("alpha_z", "alpha_i", "alpha_p"),
                         ("beta_z", "beta_i", "beta_p"))
                values = [_bfm_vector(load, key, n, "load/$id") for key in keys]
                all(x -> x !== nothing, values) || _bfm_refuse(
                    "load/$id requires all ZIP fractions")
                all(v -> all(>=(0), v), values) &&
                    all(isapprox.(sum(values), 1; atol=1e-10)) ||
                    _bfm_refuse("load/$id has invalid ZIP fractions")
            end
        elseif law == "exponential"
            _bfm_vector(load, "gamma_p", n, "load/$id") === nothing &&
                _bfm_refuse("load/$id requires gamma_p")
            _bfm_vector(load, "gamma_q", n, "load/$id") === nothing &&
                _bfm_refuse("load/$id requires gamma_q")
        end
    end
    for (id, generator) in get(net, "generator", Dict())
        _bfm_fields(generator, ("bus", "terminal_map", "configuration", "p_min",
            "p_max", "q_min", "q_max", "s_max", "i_max", "cost",
            "energy_cost_rate"), "generator/$id")
        device = _bfm_device_positions(net, generator, "generator/$id";
            allow_delta=true)
        _bfm_validate_dispatch(generator, device, "generator/$id")
    end
    for (id, source) in get(net, "voltage_source", Dict())
        _bfm_fields(source, ("bus", "terminal_map", "configuration", "v_magnitude",
            "v_angle", "p_min", "p_max", "q_min", "q_max", "s_max", "i_max",
            "cost", "energy_cost_rate"), "voltage_source/$id")
        label = "voltage_source/$id"
        _bfm_required(source,
            ("bus", "terminal_map", "v_magnitude", "v_angle"), label)
        string.(source["terminal_map"]) ==
            string.(buses[String(source["bus"])]["terminal_names"]) ||
            _bfm_refuse("voltage_source/$id must cover its complete root-bus terminal map")
        device = _bfm_device_positions(net, source, label)
        _bfm_vector(source, "v_magnitude", device.terminal_count, label)
        _bfm_vector(source, "v_angle", device.terminal_count, label)
        _bfm_validate_dispatch(source, device, label)
    end
    for (id, shunt) in get(net, "shunt", Dict())
        label = "shunt/$id"
        _bfm_fields(shunt, ("bus", "terminal_map"), label;
            matrix=("G_", "B_"))
        _bfm_required(shunt, ("bus", "terminal_map"), label)
        bus = String(shunt["bus"])
        haskey(buses, bus) || _bfm_refuse("$label references unknown bus '$bus'")
        string.(shunt["terminal_map"]) == string.(buses[bus]["terminal_names"]) ||
            _bfm_refuse("$label must cover its complete bus terminal map")
        Y = try
            _l3f_shunt_matrix(shunt, length(shunt["terminal_map"]))
        catch err
            _bfm_refuse("$label: $(sprint(showerror, err))")
        end
        all(isfinite, real.(Y)) && all(isfinite, imag.(Y)) ||
            _bfm_refuse("$label admittance must be finite")
    end
    for (id, switch) in get(net, "switch", Dict())
        label = "switch/$id"
        _bfm_fields(switch, ("bus_from", "bus_to", "terminal_map_from",
            "terminal_map_to", "open_switch", "i_max", "s_max"), label)
        _bfm_required(switch, ("bus_from", "bus_to", "terminal_map_from",
            "terminal_map_to", "open_switch"), label)
        get(switch, "open_switch", nothing) isa Bool ||
            _bfm_refuse("$label open_switch must be a fixed Boolean")
        from, to = String(switch["bus_from"]), String(switch["bus_to"])
        haskey(buses, from) && haskey(buses, to) ||
            _bfm_refuse("$label references an unknown bus")
        mf, mt = string.(switch["terminal_map_from"]),
                 string.(switch["terminal_map_to"])
        length(mf) == length(mt) && !isempty(mf) && allunique(mf) && allunique(mt) ||
            _bfm_refuse("$label requires aligned nonempty endpoint maps")
        all(in(string.(buses[from]["terminal_names"])), mf) &&
            all(in(string.(buses[to]["terminal_names"])), mt) ||
            _bfm_refuse("$label maps an undeclared terminal")
        _bfm_nonnegative(_bfm_vector(switch, "i_max", length(mf), label),
            "$label i_max")
        _bfm_nonnegative(_bfm_vector(switch, "s_max", length(mf), label),
            "$label s_max")
    end
    for (id, capacitor) in get(net, "capacitor", Dict())
        label = "capacitor/$id"
        _bfm_fields(capacitor, ("bus", "terminal_map", "configuration",
            "q_rated", "v_nom"), label)
        device = _bfm_device_positions(net, capacitor, label; allow_delta=true)
        n = _bfm_channel_count(device, label)
        q = _bfm_vector(capacitor, "q_rated", n, label)
        q === nothing && _bfm_refuse("$label requires q_rated")
        all(>=(0), q) || _bfm_refuse("$label q_rated must be nonnegative")
        vn = _bfm_vector(capacitor, "v_nom", n, label)
        vn !== nothing && all(>(0), vn) || _bfm_refuse("$label requires positive v_nom")
    end
    for (subtype, table) in get(net, "transformer", Dict()), (id, data) in table
        kind = String(subtype)
        label = "transformer/$kind/$id"
        if kind == "n_winding"
            nwplan = try
                _sdp_nwinding_plan(net, String(id), data)
            catch err
                err isa SDPInapplicableError || rethrow()
                _bfm_refuse(err.message)
            end
            for (k, winding) in enumerate(nwplan.ws)
                bus = String(winding["bus"])
                haskey(buses, bus) || _bfm_refuse(
                    "$label winding $k references unknown bus '$bus'")
                tm = string.(winding["terminal_map"])
                !isempty(tm) && allunique(tm) &&
                    all(in(string.(buses[bus]["terminal_names"])), tm) ||
                    _bfm_refuse("$label winding $k has an invalid terminal_map")
                nc = size(nwplan.Ds[k], 1)
                for field in ("i_max", "s_max")
                    values = _bfm_vector(winding, field, nc, "$label winding $k")
                    _bfm_nonnegative(values, "$label winding $k $field")
                end
            end
            continue
        end
        transformer_plan = try
            _sdp_transformer_plan(kind, data, label)
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
            delta = kind == "delta_wye" && side == "from" ||
                    kind == "wye_delta" && side == "to"
            count = delta ? size(side == "from" ? transformer_plan.Df : transformer_plan.Dt, 1) :
                            length(tm)
            _bfm_nonnegative(
                _bfm_vector(data, "i_max_$side", count, label),
                "$label i_max_$side")
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
    for (local_position, bus_position) in enumerate(device.terminal_bus_positions)
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

function _bfm_voltage_rows(net, bus, terminals)
    declared = string.(net["bus"][bus]["terminal_names"])
    rows = _SDPRow[]
    for terminal in string.(terminals)
        position = findfirst(==(terminal), declared)
        position === nothing && _bfm_refuse(
            "bus/$bus voltage map references undeclared terminal '$terminal'")
        push!(rows, _sdp_e(position))
    end
    rows
end

function _bfm_voltage_maps(net, bus)
    # The BMOPF schema permits scalar phase-to-ground bounds. Preserve the
    # BranchFlowSDP contract while keeping the shared SDP helper unchanged:
    # present scalar v_min/v_max as per-phase arrays in this local view.
    mapped_net = net
    data = net["bus"][bus]
    if any(key -> haskey(data, key) && data[key] isa Real, ("v_min", "v_max"))
        terms = string.(data["terminal_names"])
        neutral = get(_kr_neutral_map(net), bus, nothing)
        phase_count = count(!=(neutral), terms)
        mapped_data = copy(data)
        for key in ("v_min", "v_max")
            haskey(data, key) && data[key] isa Real || continue
            mapped_data[key] = fill(Float64(data[key]), phase_count)
        end
        mapped_buses = copy(net["bus"])
        mapped_buses[bus] = mapped_data
        mapped_net = copy(net)
        mapped_net["bus"] = mapped_buses
    end
    terminal_rows = (b, terminals) -> _bfm_voltage_rows(net, String(b), terminals)
    try
        _sdp_voltage_maps(mapped_net, bus, terminal_rows)
    catch err
        err isa SDPInapplicableError || rethrow()
        _bfm_refuse(err.message)
    end
end

function _bfm_voltage_product(W, a::_SDPRow, b::_SDPRow)
    out = JuMP.GenericAffExpr{ComplexF64,JuMP.VariableRef}(0im)
    for (i, ci) in a, (j, cj) in b
        JuMP.add_to_expression!(out, ci * conj(cj), W[i, j])
    end
    out
end

function _bfm_bus_limits!(model, net, voltage_moments, vb)
    fields = ("v_min", "v_max", "vpn_min", "vpn_max", "vpp_min", "vpp_max",
              "vn_max", "vpos_min", "vpos_max", "vneg_max", "vzero_max")
    for (bus, data) in sort!(collect(net["bus"]); by=first)
        maps = _bfm_voltage_maps(net, bus)
        for key in fields
            haskey(data, key) || continue
            prefix = startswith(key, "v_") ? key : first(split(key, "_"))
            haskey(maps, prefix) || _bfm_refuse(
                "bus/$bus $key requires the corresponding terminals")
            rows = maps[prefix]
            bounds = _bfm_vector(data, key, length(rows), "bus/$bus")
            for (row, value) in zip(rows, bounds)
                value >= 0 || _bfm_refuse("bus/$bus $key must be nonnegative")
                w = real(_bfm_voltage_product(voltage_moments[bus], row, row))
                limit = (value / vb)^2
                if endswith(key, "min")
                    iszero(value) || @constraint(model, w >= limit)
                else
                    @constraint(model, w <= limit)
                end
            end
        end
    end
end

function _bfm_load_range(net, bus, row::_SDPRow, vb)
    lo, hi = 0.0, Inf
    data = net["bus"][bus]
    terms = string.(data["terminal_names"])
    grounded = Set(string.(get(data, "perfectly_grounded_terminals", String[])))
    canonical(candidate) = _SDPRow(i => c for (i, c) in candidate
        if !(terms[i] in grounded))
    target = canonical(row)
    for (prefix, rows) in _bfm_voltage_maps(net, bus)
        keys = startswith(prefix, "v_") ? (prefix,) :
               (prefix * "_min", prefix * "_max")
        for key in keys
            haskey(data, key) || continue
            bounds = _bfm_vector(data, key, length(rows), "bus/$bus")
            for (candidate, value) in zip(rows, bounds)
                candidate = canonical(candidate)
                if candidate == target ||
                   candidate == _sdp_add!(_SDPRow(), target, -1)
                    endswith(key, "min") ? (lo = max(lo, (value / vb)^2)) :
                                           (hi = min(hi, (value / vb)^2))
                end
            end
        end
    end
    lo <= hi || _bfm_refuse("load voltage bounds are inconsistent at bus/$bus")
    lo, hi
end

function _bfm_terminal_voltage_ranges(net, bus, source_pu, vb)
    terms = string.(net["bus"][bus]["terminal_names"])
    grounded = Set(string.(get(net["bus"][bus],
        "perfectly_grounded_terminals", String[])))
    if haskey(source_pu, bus)
        values = abs.(source_pu[bus]) .* vb
        return collect(zip(values, values))
    end
    [if terminal in grounded
         (0.0, 0.0)
     else
         lo, hi = _bfm_load_range(net, bus, _sdp_e(k), 1.0)
         (sqrt(max(0.0, lo)), sqrt(hi))
     end for (k, terminal) in enumerate(terms)]
end

function _bfm_shunt_current_bound(Y, row, voltage_ranges, zb)
    total = 0.0
    for column in axes(Y, 2)
        coefficient = abs(Y[row, column] / zb)
        iszero(coefficient) && continue
        upper = voltage_ranges[column][2]
        isfinite(upper) || return Inf
        total += coefficient * upper
    end
    total
end

function _bfm_load_law!(model, net, id, data, device, D, W, powers, vb, sb)
    n = length(powers)
    p = _bfm_vector(data, "p_nom", n, "load/$id")
    q = _bfm_vector(data, "q_nom", n, "load/$id")
    law = lowercase(String(get(data, "model", "constant_power")))
    _sdp_is_impedance_load(data) && return
    vn = law == "constant_power" ? ones(n) :
         _bfm_vector(data, "v_nom", n, "load/$id")
    vn !== nothing && all(>(0), vn) || _bfm_refuse(
        "load/$id requires positive v_nom")
    for k in 1:n
        row = _SDPRow(j => ComplexF64(D[k, j]) for j in axes(D, 2)
                      if !iszero(D[k, j]))
        x = real(_bfm_voltage_product(W, row, row)) * (vb / vn[k])^2
        low, high = _bfm_load_range(net, device.bus, row, vb)
        low *= (vb / vn[k])^2
        high *= (vb / vn[k])^2
        cache = Dict{Float64,Any}()
        power(a) = get!(cache, Float64(a)) do
            _sdp_power_envelope!(model, x, Float64(a), low, high)
        end
        rhs = if law == "constant_power"
            (1.0, 1.0)
        elseif law == "constant_current"
            (power(0.5), power(0.5))
        elseif law == "zip"
            tuple((sum(_bfm_vector(data, prefix * suffix, n, "load/$id")[k] *
                       power(a) for (suffix, a) in
                       (("_z", 1), ("_i", 0.5), ("_p", 0)))
                   for prefix in ("alpha", "beta"))...)
        elseif law == "exponential"
            gp = _bfm_vector(data, "gamma_p", n, "load/$id")
            gq = _bfm_vector(data, "gamma_q", n, "load/$id")
            (power(gp[k] / 2), power(gq[k] / 2))
        else
            _bfm_refuse("load/$id model '$law' is not implemented")
        end
        @constraint(model, real(powers[k]) == p[k] / sb * rhs[1])
        @constraint(model, imag(powers[k]) == q[k] / sb * rhs[2])
    end
end

function _bfm_voltage_closure!(model, net, voltage_moments, cone)
    indices = Dict{Tuple{String,String},Int}()
    cursor = 0
    for (bus, data) in sort!(collect(net["bus"]); by=first)
        grounded = Set(string.(get(data, "perfectly_grounded_terminals", String[])))
        for terminal in string.(data["terminal_names"])
            if terminal in grounded
                indices[(String(bus), terminal)] = 0
            else
                cursor += 1
                indices[(String(bus), terminal)] = cursor
            end
        end
    end
    block = _sdp_psd(model, cursor, cone)
    for (bus, data) in sort!(collect(net["bus"]); by=first)
        terms = string.(data["terminal_names"])
        for a in eachindex(terms), b in a:length(terms)
            ia, ib = indices[(String(bus), terms[a])], indices[(String(bus), terms[b])]
            (ia == 0 || ib == 0) && continue
            @constraint(model, block[ia, ib] == voltage_moments[String(bus)][a, b])
        end
    end
    block, indices
end

function _bfm_overlap_global!(model, block, indices, bus_from, terms_from,
                              bus_to, terms_to, cross)
    for a in eachindex(terms_from), b in eachindex(terms_to)
        ia = indices[(String(bus_from), String(terms_from[a]))]
        ib = indices[(String(bus_to), String(terms_to[b]))]
        (ia == 0 || ib == 0) && continue
        @constraint(model, block[ia, ib] == cross[a, b])
    end
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
                                 balance, powers, cone, ib, zb, source_pu,
                                 voltage_global, voltage_indices)
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
        haskey(source_pu, bus) || continue
        prescribed = source_pu[bus]
        anchor = something(findfirst(!iszero, prescribed), 0)
        anchor > 0 || _bfm_refuse("$label root side has no nonzero reference voltage")
        for k in eachindex(prescribed)
            k == anchor && continue
            row = zeros(ComplexF64, dimension)
            row[indices[k]] = 1
            row[indices[anchor]] = -prescribed[k] / prescribed[anchor]
            push!(equations, row)
        end
    end
    for (bus, terms, indices) in ((from, from_terms, vf), (to, to_terms, vt))
        haskey(source_pu, bus) && continue
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
        if haskey(source_pu, bus)
            anchor = something(findfirst(!iszero, source_pu[bus]), 1)
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
    if voltage_global !== nothing
        cross = Any[block[vf[a], vt[b]] for a in 1:nf, b in 1:nt]
        _bfm_overlap_global!(model, voltage_global, voltage_indices,
            from, from_terms, to, to_terms, cross)
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
    terminal_from = Pf * Tf
    terminal_to = Pt * Tt
    mapped_from = _bfm_cross(block, Pf * Ef, terminal_from)
    mapped_to = _bfm_cross(block, Pt * Et, terminal_to)
    powers[(:transformer_from, key)] =
        Any[mapped_from[k, k] for k in axes(mapped_from, 1)]
    powers[(:transformer_to, key)] =
        Any[mapped_to[k, k] for k in axes(mapped_to, 1)]
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
        map = side == :from ? (delta ? Ajf : terminal_from) :
                              (delta ? Ajt : terminal_to)
        count = size(map, 1)
        limits = _bfm_vector(data, rating_key, count, label)
        gram = _bfm_cross(block, map, map)
        for k in 1:count
            limits[k] >= 0 || _bfm_refuse("$label has negative $rating_key")
            @constraint(model, real(gram[k, k]) <= (limits[k] / ib)^2)
        end
    end
    (; key, subtype, id=String(id), from, to, block, reduced, nullspace=N,
       vf, vt, jf, jt, Tf, Tt, terminal_from, terminal_to,
       Uf, Ut, Ajf, Ajt, dimension,
       voltage_state_indices=vcat(collect(vf), collect(vt)),
       voltage_state_buses=vcat(fill(from, nf), fill(to, nt)),
       voltage_state_terminals=vcat(from_terms, to_terms))
end

function _bfm_nwinding_block!(model, net, id, data, voltage_moments, balance,
                              powers, cone, sb, ib, zb, source_pu, voltage_global,
                              voltage_indices)
    label = "transformer/n_winding/$id"
    plan = try
        _sdp_nwinding_plan(net, id, data)
    catch err
        err isa SDPInapplicableError || rethrow()
        _bfm_refuse(err.message)
    end
    nw = length(plan.ws)
    buses = String[String(w["bus"]) for w in plan.ws]
    bus_terms = [string.(net["bus"][bus]["terminal_names"]) for bus in buses]
    maps = [string.(w["terminal_map"]) for w in plan.ws]
    selections = [_bfm_selection(bus_terms[k], maps[k], label) for k in 1:nw]
    U = [plan.Ds[k] * selections[k] for k in 1:nw]
    nc = size(first(U), 1)
    nv = sum(length, bus_terms)
    voltage_ranges = UnitRange{Int}[]
    cursor = 0
    for terms in bus_terms
        push!(voltage_ranges, cursor + 1:cursor + length(terms))
        cursor += length(terms)
    end
    current_ranges = UnitRange{Int}[]
    for _ in 1:nw
        push!(current_ranges, cursor + 1:cursor + nc)
        cursor += nc
    end
    ideal_ground = Tuple{Int,Int}[]
    finite_ground = Tuple{Int,Int,ComplexF64}[]
    for k in 1:nw
        w = plan.ws[k]
        haskey(w, "r_neutral") || haskey(w, "x_neutral") || continue
        neutral = get(_kr_neutral_map(net), buses[k], nothing)
        position = findfirst(==(neutral), maps[k])
        position === nothing && _bfm_refuse(
            "$label winding $k grounding requires an explicit neutral")
        z = complex(Float64(get(w, "r_neutral", 0.0)),
                    Float64(get(w, "x_neutral", 0.0)))
        isfinite(z) && real(z) >= 0 && imag(z) >= 0 ||
            _bfm_refuse("$label winding $k has invalid grounding impedance")
        iszero(z) ? push!(ideal_ground, (k, position)) :
                    push!(finite_ground, (k, position, z / zb))
    end
    ground_range = cursor + 1:cursor + length(ideal_ground)
    dimension = cursor + length(ideal_ground)
    equations = Vector{Vector{ComplexF64}}()
    for c in 1:nc
        amp = zeros(ComplexF64, dimension)
        for k in 1:nw
            amp[current_ranges[k][c]] += plan.turns[k]
        end
        push!(equations, amp)
        for i in 2:nw
            row = zeros(ComplexF64, dimension)
            row[voltage_ranges[1]] .+= U[1][c, :] ./ plan.turns[1]
            row[voltage_ranges[i]] .-= U[i][c, :] ./ plan.turns[i]
            for k in 2:nw
                row[current_ranges[k][c]] +=
                    plan.Z[i - 1, k - 1] * plan.turns[k] / zb
            end
            push!(equations, row)
        end
    end
    for (g, (k, position)) in enumerate(ideal_ground)
        row = zeros(ComplexF64, dimension)
        bus_position = findfirst(==(maps[k][position]), bus_terms[k])
        row[voltage_ranges[k][bus_position]] = 1
        push!(equations, row)
    end
    for k in 1:nw
        bus, indices = buses[k], voltage_ranges[k]
        if haskey(source_pu, bus)
            prescribed = source_pu[bus]
            anchor = something(findfirst(!iszero, prescribed), 0)
            anchor > 0 || _bfm_refuse("$label source winding has no nonzero voltage")
            for h in eachindex(prescribed)
                h == anchor && continue
                row = zeros(ComplexF64, dimension)
                row[indices[h]] = 1
                row[indices[anchor]] = -prescribed[h] / prescribed[anchor]
                push!(equations, row)
            end
        else
            grounded = Set(string.(get(net["bus"][bus],
                "perfectly_grounded_terminals", String[])))
            for h in eachindex(bus_terms[k])
                bus_terms[k][h] in grounded || continue
                row = zeros(ComplexF64, dimension)
                row[indices[h]] = 1
                push!(equations, row)
            end
        end
    end
    A = isempty(equations) ? zeros(ComplexF64, 0, dimension) :
        reduce(vcat, (reshape(row, 1, :) for row in equations))
    N = nullspace(A)
    size(N, 2) > 0 || _bfm_refuse("$label equations leave no electrical state")
    reduced = _sdp_psd(model, size(N, 2), cone)
    block = Any[sum(N[a, k] * reduced[k, h] * conj(N[b, h])
                    for k in axes(N, 2), h in axes(N, 2))
                for a in 1:dimension, b in 1:dimension]
    for k in 1:nw
        bus, indices, terms = buses[k], voltage_ranges[k], bus_terms[k]
        if haskey(source_pu, bus)
            anchor = something(findfirst(!iszero, source_pu[bus]), 1)
            @constraint(model, block[indices[anchor], indices[anchor]] ==
                               voltage_moments[bus][anchor, anchor])
        else
            live = _bfm_live_positions(net, bus)
            for a in live, b in live
                a <= b || continue
                @constraint(model, block[indices[a], indices[b]] ==
                                   voltage_moments[bus][a, b])
            end
        end
        if voltage_global !== nothing
            for h in k+1:nw
                cross = Any[block[indices[a], voltage_ranges[h][b]]
                            for a in eachindex(terms), b in eachindex(bus_terms[h])]
                _bfm_overlap_global!(model, voltage_global, voltage_indices,
                    bus, terms, buses[h], bus_terms[h], cross)
            end
        end
    end

    terminal_maps = Matrix{ComplexF64}[]
    coil_maps = Matrix{ComplexF64}[]
    for k in 1:nw
        nt = length(bus_terms[k])
        T = zeros(ComplexF64, nt, dimension)
        coil = zeros(ComplexF64, nc, dimension)
        for c in 1:nc
            coil[c, current_ranges[k][c]] = 1
        end
        C = transpose(selections[k]) * transpose(plan.Ds[k])
        T[:, current_ranges[k]] .+= C
        if k == plan.shunt
            T[:, voltage_ranges[k]] .+= C * (plan.y * zb .* U[k])
        end
        for (kg, position, zpu) in finite_ground
            kg == k || continue
            p = findfirst(==(maps[k][position]), bus_terms[k])
            T[p, voltage_ranges[k][p]] += inv(zpu)
        end
        for (g, (kg, position)) in enumerate(ideal_ground)
            kg == k || continue
            p = findfirst(==(maps[k][position]), bus_terms[k])
            T[p, ground_range[g]] += 1
        end
        push!(coil_maps, coil)
        E = zeros(ComplexF64, nt, dimension)
        for h in 1:nt
            E[h, voltage_ranges[k][h]] = 1
        end
        terminal_moment = _bfm_cross(block, E, T)
        _bfm_add_matrix!(balance[buses[k]], terminal_moment)
        # KCL uses full-bus coordinates, but public winding currents and powers
        # follow terminal_map order and arity, just as in the two-winding path.
        mapped_voltage = selections[k] * E
        mapped_terminal = selections[k] * T
        push!(terminal_maps, mapped_terminal)
        mapped_moment = _bfm_cross(block, mapped_voltage, mapped_terminal)
        terminal_power = Any[mapped_moment[h, h]
                             for h in axes(mapped_moment, 1)]
        key = "n_winding/$id/$k"
        powers[(:transformer_winding, key)] = terminal_power
        coil_voltage = zeros(ComplexF64, nc, dimension)
        coil_voltage[:, voltage_ranges[k]] .= U[k]
        coil_moment = _bfm_cross(block, coil_voltage, coil)
        coil_power = Any[coil_moment[c, c] for c in 1:nc]
        powers[(:transformer_coil, key)] = coil_power
        w = plan.ws[k]
        imax = _bfm_vector(w, "i_max", nc, "$label winding $k")
        smax = _bfm_vector(w, "s_max", nc, "$label winding $k")
        current_gram = _bfm_cross(block, coil, coil)
        for c in 1:nc
            imax === nothing || @constraint(model,
                real(current_gram[c, c]) <= (imax[c] / ib)^2)
            smax === nothing || @constraint(model,
                [smax[c] / sb,
                 real(coil_power[c]), imag(coil_power[c])] in SecondOrderCone())
        end
    end
    key = "n_winding/$id"
    (; key, subtype="n_winding", id=String(id), buses, bus_terms, block, reduced,
       nullspace=N, dimension, voltage_ranges, current_ranges, terminal_maps,
       coil_maps, voltage_state_indices=reduce(vcat, collect.(voltage_ranges)),
       voltage_state_buses=reduce(vcat, [fill(buses[k], length(bus_terms[k]))
                                        for k in 1:nw]),
       voltage_state_terminals=reduce(vcat, bus_terms))
end

function _bfm_switch_block!(model, net, id, data, voltage_moments, balance,
                            powers, cone, sb, ib, source_pu, voltage_global,
                            voltage_indices)
    label = "switch/$id"
    from, to = String(data["bus_from"]), String(data["bus_to"])
    from_terms = string.(net["bus"][from]["terminal_names"])
    to_terms = string.(net["bus"][to]["terminal_names"])
    map_from, map_to = string.(data["terminal_map_from"]),
                       string.(data["terminal_map_to"])
    m = length(map_from)
    if data["open_switch"]
        zero_power = Any[JuMP.AffExpr(0.0) + 0im for _ in 1:m]
        powers[(:switch_from, String(id))] = copy(zero_power)
        powers[(:switch_to, String(id))] = copy(zero_power)
        return (; key=String(id), id=String(id), from, to, block=nothing,
            open=true, map_from, map_to)
    end
    Pf = _bfm_selection(from_terms, map_from, label)
    Pt = _bfm_selection(to_terms, map_to, label)
    nf, nt = length(from_terms), length(to_terms)
    vf, vt, current = 1:nf, nf+1:nf+nt, nf+nt+1:nf+nt+m
    dimension = nf + nt + m
    equations = Vector{Vector{ComplexF64}}()
    for k in 1:m
        row = zeros(ComplexF64, dimension)
        row[vf] .+= Pf[k, :]
        row[vt] .-= Pt[k, :]
        push!(equations, row)
    end
    for (bus, indices, terms) in ((from, vf, from_terms), (to, vt, to_terms))
        if haskey(source_pu, bus)
            prescribed = source_pu[bus]
            anchor = something(findfirst(!iszero, prescribed), 0)
            anchor > 0 || _bfm_refuse("$label source side has no nonzero voltage")
            for k in eachindex(prescribed)
                k == anchor && continue
                row = zeros(ComplexF64, dimension)
                row[indices[k]] = 1
                row[indices[anchor]] = -prescribed[k] / prescribed[anchor]
                push!(equations, row)
            end
        else
            grounded = Set(string.(get(net["bus"][bus],
                "perfectly_grounded_terminals", String[])))
            for k in eachindex(terms)
                terms[k] in grounded || continue
                row = zeros(ComplexF64, dimension)
                row[indices[k]] = 1
                push!(equations, row)
            end
        end
    end
    A = reduce(vcat, (reshape(row, 1, :) for row in equations))
    N = nullspace(A)
    size(N, 2) > 0 || _bfm_refuse("$label equations leave no electrical state")
    reduced = _sdp_psd(model, size(N, 2), cone)
    block = Any[sum(N[a, k] * reduced[k, h] * conj(N[b, h])
                    for k in axes(N, 2), h in axes(N, 2))
                for a in 1:dimension, b in 1:dimension]
    for (bus, indices, terms) in ((from, vf, from_terms), (to, vt, to_terms))
        if haskey(source_pu, bus)
            anchor = something(findfirst(!iszero, source_pu[bus]), 1)
            @constraint(model, block[indices[anchor], indices[anchor]] ==
                               voltage_moments[bus][anchor, anchor])
        else
            live = _bfm_live_positions(net, bus)
            for a in live, b in live
                a <= b || continue
                @constraint(model, block[indices[a], indices[b]] ==
                                   voltage_moments[bus][a, b])
            end
        end
    end
    if voltage_global !== nothing
        cross = Any[block[vf[a], vt[b]] for a in 1:nf, b in 1:nt]
        _bfm_overlap_global!(model, voltage_global, voltage_indices,
            from, from_terms, to, to_terms, cross)
    end
    Ef = zeros(ComplexF64, nf, dimension)
    Et = zeros(ComplexF64, nt, dimension)
    J = zeros(ComplexF64, m, dimension)
    for k in 1:nf; Ef[k, vf[k]] = 1; end
    for k in 1:nt; Et[k, vt[k]] = 1; end
    for k in 1:m; J[k, current[k]] = 1; end
    Tf = transpose(Pf) * J
    Tt = -transpose(Pt) * J
    Mf, Mt = _bfm_cross(block, Ef, Tf), _bfm_cross(block, Et, Tt)
    _bfm_add_matrix!(balance[from], Mf)
    _bfm_add_matrix!(balance[to], Mt)
    mapped_from = _bfm_cross(block, Pf * Ef, J)
    mapped_to = _bfm_cross(block, Pt * Et, -J)
    sf = Any[mapped_from[k, k] for k in 1:m]
    st = Any[mapped_to[k, k] for k in 1:m]
    powers[(:switch_from, String(id))] = sf
    powers[(:switch_to, String(id))] = st
    gram = _bfm_cross(block, J, J)
    imax = _bfm_vector(data, "i_max", m, label)
    smax = _bfm_vector(data, "s_max", m, label)
    for k in 1:m
        imax === nothing || @constraint(model,
            real(gram[k, k]) <= (imax[k] / ib)^2)
        if smax !== nothing
            @constraint(model, [smax[k] / sb, real(sf[k]), imag(sf[k])]
                in SecondOrderCone())
            @constraint(model, [smax[k] / sb, real(st[k]), imag(st[k])]
                in SecondOrderCone())
        end
    end
    (; key=String(id), id=String(id), from, to, block, reduced, open=false,
       map_from, map_to, Pf, Pt, vf, vt, current, J, Tf, Tt, dimension,
       voltage_state_indices=vcat(collect(vf), collect(vt)),
       voltage_state_buses=vcat(fill(from, nf), fill(to, nt)),
       voltage_state_terminals=vcat(from_terms, to_terms))
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
    switch_records::Vector{NamedTuple}
    topology::Vector{NamedTuple}
    powers::Dict{Tuple{Symbol,String},Vector{Any}}
    network::Dict{String,Any}
    options::BranchFlowSDPOptions
    voltage_base::Float64
    current_base::Float64
    root::String
    root_voltage::Vector{ComplexF64}
    source_voltages::Dict{String,Vector{ComplexF64}}
    voltage_global::Any
    voltage_indices::Dict{Tuple{String,String},Int}
    load_envelopes::Vector{String}
    lnc_diagnostics::Vector{LNCDiagnostic}
    objective_scale::Float64
    numerical_diagnostics::Dict{Symbol,Any}
end

function phasor_products(build::BranchFlowSDPBuild, u::VoltagePhasor,
                         v::VoltagePhasor)
    build.voltage_global === nothing && throw(ArgumentError(
        "this BranchFlowSDP build has no global voltage closure"))
    function coefficients(phasor)
        out = Dict{Int,ComplexF64}()
        for (key, value) in phasor.terms
            haskey(build.voltage_indices, key) ||
                throw(ArgumentError("unknown voltage terminal $key"))
            index = build.voltage_indices[key]
            index == 0 || (out[index] = get(out, index, 0im) + value)
        end
        out
    end
    a, b = coefficients(u), coefficients(v)
    product(x, y) = build.voltage_base^2 *
        sum((cx * conj(cy) * build.voltage_global[ix, iy]
             for (ix, cx) in x, (iy, cy) in y); init=0im)
    cross = product(a, b)
    (; wu=real(product(a, a)), wv=real(product(b, b)), cross)
end

function add_voltage_lnc!(build::BranchFlowSDPBuild, spec::VoltageLNC)
    any(d -> d.id == spec.id, build.lnc_diagnostics) &&
        throw(ArgumentError("duplicate LNC id $(spec.id)"))
    p = phasor_products(build, spec.u, spec.v)
    refs = add_lnc!(build.model, p.wu, p.wv, real(p.cross), imag(p.cross),
        spec.bounds)
    push!(build.lnc_diagnostics, LNCDiagnostic(spec.id, :applied, spec.origin,
        spec.provenance, "", spec.bounds))
    refs
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

"""Build the matrix-KCL branch-flow SDP on its declared component slice."""
function build_branch_flow_sdp(input, optimizer=default_sdp_optimizer();
                               options::BranchFlowSDPOptions=BranchFlowSDPOptions())
    isfinite(options.s_base) && options.s_base > 0 ||
        throw(ArgumentError("s_base must be positive and finite"))
    options.objective in (:cost, :source_import, :feasibility) ||
        throw(ArgumentError("unknown branch-flow SDP objective"))
    options.cone in (:real, :hermitian) || throw(ArgumentError("unknown SDP cone"))
    options.recovery == :tree || throw(ArgumentError("only recovery=:tree is implemented"))
    options.lnc in (:off, :lines) || throw(ArgumentError("lnc must be :off or :lines"))
    net = _l3f_input(input)
    plan = _bfm_validate(net)
    source_voltages = Dict{String,Vector{ComplexF64}}()
    for (id_raw, source) in sort!(collect(plan.sources); by=first)
        id = String(id_raw)
        bus = String(source["bus"])
        terms = string.(net["bus"][bus]["terminal_names"])
        values = _bfm_vector(source, "v_magnitude", length(terms),
                             "voltage_source/$id") .*
                 cis.(_bfm_vector(source, "v_angle", length(terms),
                                  "voltage_source/$id"))
        all(isfinite, values) || _bfm_refuse("voltage_source/$id has invalid phasors")
        source_voltages[id] = ComplexF64.(values)
    end
    vb = maximum((maximum(abs, values) for values in values(source_voltages)); init=0.0)
    vb > 0 || _bfm_refuse("the root source needs a nonzero phasor")
    source_pu = Dict{String,Vector{ComplexF64}}()
    for (id, values) in sort!(collect(source_voltages); by=first)
        bus = String(plan.sources[id]["bus"])
        if haskey(source_pu, bus)
            source_pu[bus] ≈ values ./ vb || _bfm_refuse(
                "voltage sources at bus '$bus' prescribe conflicting phasors")
        else
            source_pu[bus] = values ./ vb
        end
    end
    root_voltage = source_voltages[plan.source_id]
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
    closed_switch = any(switch -> !switch["open_switch"],
        values(get(net, "switch", Dict())))
    use_global_voltage = plan.requires_global_voltage ||
        !isempty(options.voltage_lncs) || options.lnc == :lines ||
        closed_switch ||
        !isempty(get(get(net, "transformer", Dict()), "n_winding", Dict()))
    voltage_global, voltage_indices = use_global_voltage ?
        _bfm_voltage_closure!(model, net, voltage_moments, options.cone) :
        (nothing, Dict{Tuple{String,String},Int}())

    edge_blocks = Dict{String,Any}()
    component_blocks = Dict{Tuple{Symbol,String},Any}()
    transformer_blocks = Dict{String,Any}()
    edge_records = NamedTuple[]
    component_records = NamedTuple[]
    transformer_records = NamedTuple[]
    switch_records = NamedTuple[]
    powers = Dict{Tuple{Symbol,String},Vector{Any}}()
    lnc_lines = NamedTuple[]
    line_bound_diagnostics = NamedTuple[]
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
        gf, _ = _bfm_line_matrix(code, "G_from_", n, "line/$id")
        bf, _ = _bfm_line_matrix(code, "B_from_", n, "line/$id")
        gt, _ = _bfm_line_matrix(code, "G_to_", n, "line/$id")
        bt, _ = _bfm_line_matrix(code, "B_to_", n, "line/$id")
        Yfrom = complex.(gf, bf) .* length_scale .* zb
        Yto = complex.(gt, bt) .* length_scale .* zb
        Yp, Yc = oriented.reversed ? (Yto, Yfrom) : (Yfrom, Yto)
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
        series_receiving_matrix = Any[
            S[a, b] - sum(Z[a, h] * L[h, b] for h in 1:n)
            for a in 1:n, b in 1:n]
        parent_matrix = Any[S[a, b] +
            sum(Wp[a, h] * conj(Yp[b, h]) for h in 1:n)
            for a in 1:n, b in 1:n]
        child_matrix = Any[-series_receiving_matrix[a, b] +
            sum(Wc[a, h] * conj(Yc[b, h]) for h in 1:n)
            for a in 1:n, b in 1:n]
        sending = Any[parent_matrix[k, k] for k in 1:n]
        receiving = Any[-child_matrix[k, k] for k in 1:n]
        if oriented.reversed
            powers[(:line_from, id)] = Any[-s for s in receiving]
            powers[(:line_to, id)] = sending
        else
            powers[(:line_from, id)] = sending
            powers[(:line_to, id)] = Any[-s for s in receiving]
        end
        _bfm_add_matrix!(balance[parent], parent_matrix)
        _bfm_add_matrix!(balance[child], child_matrix)
        if voltage_global !== nothing
            cross = Any[Wp[a, b] - sum(S[a, k] * conj(Z[b, k]) for k in 1:n)
                        for a in 1:n, b in 1:n]
            _bfm_overlap_global!(model, voltage_global, voltage_indices,
                parent, net["bus"][parent]["terminal_names"], child,
                net["bus"][child]["terminal_names"], cross)
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
        phase_positions = _bfm_line_phase_positions(net, line)
        smax = _bfm_phase_vector(ratings, "s_max", phase_positions, n, "line/$id")
        _bfm_nonnegative(imax, "line/$id i_max")
        _bfm_nonnegative(smax, "line/$id s_max")
        parent_voltage_ranges = _bfm_terminal_voltage_ranges(
            net, parent, source_pu, vb)
        child_voltage_ranges = _bfm_terminal_voltage_ranges(
            net, child, source_pu, vb)
        endpoint_parent = imax === nothing ? fill(Inf, n) : copy(imax)
        endpoint_child = copy(endpoint_parent)
        derived_parent = fill(Inf, n)
        derived_child = fill(Inf, n)
        if options.implied_current_limits && smax !== nothing
            for (channel, position) in enumerate(phase_positions)
                lower_parent = parent_voltage_ranges[position][1]
                lower_child = child_voltage_ranges[position][1]
                if isfinite(lower_parent) && lower_parent > 0
                    derived_parent[position] = smax[channel] / lower_parent
                    endpoint_parent[position] = min(
                        endpoint_parent[position], derived_parent[position])
                end
                if isfinite(lower_child) && lower_child > 0
                    derived_child[position] = smax[channel] / lower_child
                    endpoint_child[position] = min(
                        endpoint_child[position], derived_child[position])
                end
            end
        end
        Jp = Any[L[a, b] +
            sum(conj(S[h, a]) * conj(Yp[b, h]) for h in 1:n) +
            sum(Yp[a, h] * S[h, b] for h in 1:n) +
            sum(Yp[a, h] * Wp[h, g] * conj(Yp[b, g]) for h in 1:n, g in 1:n)
            for a in 1:n, b in 1:n]
        Jc = Any[L[a, b] -
            sum(conj(series_receiving_matrix[h, a]) * conj(Yc[b, h]) for h in 1:n) -
            sum(Yc[a, h] * series_receiving_matrix[h, b] for h in 1:n) +
            sum(Yc[a, h] * Wc[h, g] * conj(Yc[b, g]) for h in 1:n, g in 1:n)
            for a in 1:n, b in 1:n]
        for k in 1:n
            isfinite(endpoint_parent[k]) && @constraint(model,
                real(Jp[k, k]) <= (endpoint_parent[k] / ib)^2)
            isfinite(endpoint_child[k]) && @constraint(model,
                real(Jc[k, k]) <= (endpoint_child[k] / ib)^2)
        end
        if smax !== nothing
            for (k, position) in enumerate(phase_positions)
                @constraint(model, [smax[k] / sb, real(sending[position]), imag(sending[position])]
                    in SecondOrderCone())
                @constraint(model, [smax[k] / sb, real(receiving[position]), imag(receiving[position])]
                    in SecondOrderCone())
            end
        end
        series_limit = fill(Inf, n)
        for k in 1:n
            from_shunt = _bfm_shunt_current_bound(
                Yp, k, parent_voltage_ranges, zb)
            to_shunt = _bfm_shunt_current_bound(
                Yc, k, child_voltage_ranges, zb)
            from_bound = isfinite(endpoint_parent[k]) && isfinite(from_shunt) ?
                endpoint_parent[k] + from_shunt : Inf
            to_bound = isfinite(endpoint_child[k]) && isfinite(to_shunt) ?
                endpoint_child[k] + to_shunt : Inf
            series_limit[k] = min(from_bound, to_bound)
            if options.implied_current_limits && isfinite(series_limit[k])
                @constraint(model,
                    real(L[k, k]) <= (series_limit[k] / ib)^2)
            end
        end
        push!(line_bound_diagnostics, (; id, parent, child,
            explicit_endpoint_current=imax === nothing ? nothing : copy(imax),
            apparent_power=smax === nothing ? nothing : copy(smax),
            derived_endpoint_current_parent=derived_parent,
            derived_endpoint_current_child=derived_child,
            effective_endpoint_current_parent=endpoint_parent,
            effective_endpoint_current_child=endpoint_child,
            implied_series_current=series_limit))
        push!(edge_records, (; id, parent, child, reversed=oriented.reversed,
            tree_edge=oriented.tree_edge, Z, Yp, Yc, sending, receiving,
            receiving_matrix=series_receiving_matrix, parent_matrix,
            child_matrix, endpoint_current_parent=Jp, endpoint_current_child=Jc,
            S, L))
        if options.lnc == :lines
            rows(bus, terminals) = [_sdp_e(voltage_indices[(String(bus), String(t))])
                                    for t in terminals]
            ratings_lnc = Dict{String,Any}()
            for key in ("i_max", "s_max")
                if haskey(line, key)
                    ratings_lnc[key] = line[key]
                elseif haskey(code, key)
                    ratings_lnc[key] = code[key]
                end
            end
            parent_terms = string.(net["bus"][parent]["terminal_names"])
            child_terms = string.(net["bus"][child]["terminal_names"])
            push!(lnc_lines, (; id, from=parent, to=child,
                tmf=parent_terms, tmt=child_terms,
                vf=rows(parent, parent_terms), vt=rows(child, child_terms),
                Z=Z * zb, Yf=Yp / zb, Yt=Yc / zb, ratings=ratings_lnc,
                series_current=series_limit))
        end
    end

    # Fixed source voltage Grams and their common cross-source angle reference.
    fixed_source_coordinates = Dict{Tuple{String,String},ComplexF64}()
    for (id, values) in sort!(collect(source_voltages); by=first)
        source = plan.sources[id]
        bus = String(source["bus"])
        terms = string.(net["bus"][bus]["terminal_names"])
        pu = values ./ vb
        W = voltage_moments[bus]
        for a in eachindex(pu), b in a:length(pu)
            @constraint(model, W[a, b] == pu[a] * conj(pu[b]))
        end
        for (terminal, value) in zip(terms, pu)
            fixed_source_coordinates[(bus, terminal)] = value
        end
    end
    if voltage_global !== nothing
        fixed = [(voltage_indices[key], value)
                 for (key, value) in sort!(collect(fixed_source_coordinates); by=first)
                 if voltage_indices[key] != 0]
        for (ia, va) in fixed, (ibx, vbv) in fixed
            ia <= ibx || continue
            @constraint(model, voltage_global[ia, ibx] == va * conj(vbv))
        end
    end
    neutrals = _kr_neutral_map(net)
    for (bus, data) in sort!(collect(net["bus"]); by=first)
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
    end
    _bfm_bus_limits!(model, net, voltage_moments, vb)

    objective = JuMP.AffExpr(0.0)
    function add_dispatch!(family, id, data, device)
        bus = device.bus
        layout = _bfm_dispatch_layout(device, "$family/$id")
        n = layout.count
        coils = _bfm_channel_count(device, "$family/$id")
        D = _bfm_connection(net, device, coils, "$family/$id")
        delta_terminal = device.configuration == "DELTA" &&
                         length(device.terminals) == 3
        terminal_positions = device.terminal_bus_positions
        fixed_voltage = family == "voltage_source"
        if fixed_voltage
            jr = Any[@variable(model) for _ in 1:coils]
            ji = Any[@variable(model) for _ in 1:coils]
            current = Any[jr[k] + im * ji[k] for k in 1:coils]
            bus_pu = source_voltages[String(id)] ./ vb
            coil_voltage = D * bus_pu
            terminal_current = transpose(D) * current
            terminal = Any[bus_pu[a] * conj(terminal_current[b])
                           for a in eachindex(bus_pu), b in eachindex(bus_pu)]
            s = delta_terminal ?
                Any[terminal[k, k] for k in terminal_positions] :
                Any[coil_voltage[k] * conj(current[k]) for k in 1:coils]
            push!(component_records, (; family=Symbol(family), id=String(id), bus,
                D, block=nothing, C=nothing, J=nothing, law=:fixed_voltage,
                current, current_kind=:terminal))
        else
            local_moment = _bfm_component_block!(model, voltage_moments[bus], D,
                options.cone, _bfm_live_positions(net, bus))
            component_blocks[(Symbol(family), String(id))] = local_moment.block
            s = delta_terminal ?
                Any[local_moment.terminal[k, k] for k in terminal_positions] :
                local_moment.power
            terminal = local_moment.terminal
            push!(component_records, (; family=Symbol(family), id=String(id), bus,
                D, block=local_moment.block, C=local_moment.C, J=local_moment.J,
                live=local_moment.live, law=:dispatch,
                current_kind=delta_terminal ? :terminal : :coil))
        end
        p = Any[real(value) for value in s]
        q = Any[imag(value) for value in s]
        _bfm_box!(model, p, q, data, layout.positions, layout.terminal_count,
                  "$family/$id", sb)
        smax = _bfm_phase_vector(data, "s_max", layout.positions,
            layout.terminal_count, "$family/$id")
        imax = _bfm_phase_vector(data, "i_max", layout.positions,
            layout.terminal_count, "$family/$id")
        for k in 1:n
            if smax !== nothing
                smax[k] >= 0 || _bfm_refuse("$family/$id has a negative apparent-power limit")
                @constraint(model, [smax[k] / sb, p[k], q[k]] in SecondOrderCone())
            end
            if imax !== nothing
                imax[k] >= 0 || _bfm_refuse("$family/$id has a negative current limit")
                if fixed_voltage
                    rated_current = delta_terminal ?
                        terminal_current[terminal_positions[k]] : current[k]
                    @constraint(model, [imax[k] / ib,
                        real(rated_current), imag(rated_current)] in SecondOrderCone())
                else
                    gram = delta_terminal ?
                        transpose(D) * local_moment.J * D : local_moment.J
                    position = delta_terminal ? terminal_positions[k] : k
                    @constraint(model,
                        real(gram[position, position]) <= (imax[k] / ib)^2)
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
        costs = _bfm_phase_vector(priced, "cost", layout.positions,
            layout.terminal_count, "$family/$id"; default=zeros(n))
        for k in 1:n
            coefficient = options.objective == :cost ? costs[k] * sb / 1000 :
                options.objective == :source_import && family == "voltage_source" ? sb : 0.0
            JuMP.add_to_expression!(objective, coefficient * p[k])
        end
        s
    end

    for (id, source) in sort!(collect(plan.sources); by=first)
        source_device = _bfm_device_positions(net, source, "voltage_source/$id")
        add_dispatch!("voltage_source", String(id), source, source_device)
    end

    for (id, generator) in sort!(collect(get(net, "generator", Dict())); by=first)
        device = _bfm_device_positions(net, generator, "generator/$id";
            allow_delta=true)
        add_dispatch!("generator", id, generator, device)
    end
    for (id, load) in sort!(collect(get(net, "load", Dict())); by=first)
        device = _bfm_device_positions(net, load, "load/$id"; allow_delta=true)
        n = _bfm_channel_count(device, "load/$id")
        p = _bfm_vector(load, "p_nom", n, "load/$id")
        q = _bfm_vector(load, "q_nom", n, "load/$id")
        (p === nothing || q === nothing) &&
            _bfm_refuse("load/$id requires p_nom and q_nom")
        law = lowercase(String(get(load, "model", "constant_power")))
        D = _bfm_connection(net, device, n, "load/$id")
        W = voltage_moments[device.bus]
        s = Any[]; terminal = nothing
        if !_sdp_is_impedance_load(load)
            local_moment = _bfm_component_block!(model, W, D, options.cone,
                _bfm_live_positions(net, device.bus))
            component_blocks[(:load, String(id))] = local_moment.block
            _bfm_load_law!(model, net, String(id), load, device, D, W,
                local_moment.power, vb, sb)
            append!(s, local_moment.power)
            terminal = local_moment.terminal
            push!(component_records, (; family=:load, id=String(id), bus=device.bus,
                D, block=local_moment.block, C=local_moment.C, J=local_moment.J,
                live=local_moment.live, law=Symbol(law), current_kind=:coil))
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
                admittance=conj.(complex.(p, q)) ./ vnom.^2,
                current_kind=:coil))
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

    for (id, capacitor) in sort!(collect(get(net, "capacitor", Dict())); by=first)
        device = _bfm_device_positions(net, capacitor, "capacitor/$id";
            allow_delta=true)
        n = _bfm_channel_count(device, "capacitor/$id")
        q = _bfm_vector(capacitor, "q_rated", n, "capacitor/$id")
        vn = _bfm_vector(capacitor, "v_nom", n, "capacitor/$id")
        D = _bfm_connection(net, device, n, "capacitor/$id")
        W = voltage_moments[device.bus]
        factors = -im .* q ./ sb .* (vb ./ vn).^2
        C = Any[sum(W[a, b] * D[k, b] for b in axes(W, 2)) * factors[k]
                for a in axes(W, 1), k in 1:n]
        coil = Any[sum(D[k, a] * C[a, h] for a in axes(W, 1))
                   for k in 1:n, h in 1:n]
        terminal = Any[sum(C[a, k] * D[k, b] for k in 1:n)
                       for a in axes(W, 1), b in axes(W, 2)]
        powers[(:capacitor, String(id))] = Any[coil[k, k] for k in 1:n]
        _bfm_add_matrix!(balance[device.bus], terminal)
        push!(component_records, (; family=:capacitor, id=String(id),
            bus=device.bus, D, block=nothing, C, J=nothing, law=:capacitor,
            admittance=im .* q ./ vn.^2, current_kind=:coil))
    end

    for (id, switch) in sort!(collect(get(net, "switch", Dict())); by=first)
        record = _bfm_switch_block!(model, net, String(id), switch,
            voltage_moments, balance, powers, options.cone, sb, ib, source_pu,
            voltage_global, voltage_indices)
        record.block === nothing ||
            (component_blocks[(:switch, String(id))] = record.block)
        push!(switch_records, record)
    end

    for (subtype, table) in sort!(collect(get(net, "transformer", Dict())); by=first),
        (id, data) in sort!(collect(table); by=first)
        String(subtype) == "n_winding" && continue
        record = _bfm_transformer_block!(model, net, String(subtype), String(id),
            data, voltage_moments, balance, powers, options.cone, ib, zb,
            source_pu, voltage_global, voltage_indices)
        transformer_blocks[record.key] = record.block
        push!(transformer_records, record)
    end
    for (id, data) in sort!(collect(get(get(net, "transformer", Dict()),
                                      "n_winding", Dict())); by=first)
        record = _bfm_nwinding_block!(model, net, String(id), data,
            voltage_moments, balance, powers, options.cone, sb, ib, zb,
            source_pu, voltage_global, voltage_indices)
        transformer_blocks[record.key] = record.block
        push!(transformer_records, record)
    end

    matrix_kcl_count = 0
    matrix_kcl = Dict{Tuple{String,Int,Int,Symbol},JuMP.ConstraintRef}()
    for (bus, data) in sort!(collect(net["bus"]); by=first)
        terms = string.(data["terminal_names"])
        grounded = Set(string.(get(data, "perfectly_grounded_terminals", String[])))
        # W_root is a prescribed rank-one Gram. One nonzero voltage row is an
        # exact basis for v_root*r_root^H and avoids dependent equalities on
        # the exposed PSD faces. Other buses retain every voltage row.
        rows = haskey(source_pu, bus) ?
            [something(findfirst(!iszero, source_pu[bus]), 1)] :
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
        :scope => :matrix_kcl_v3,
        :bus_count => length(net["bus"]),
        :edge_count => plan.edge_count,
        :cycle_count => plan.cycle_count,
        :source_free_components => plan.source_free_components,
        :source_count => length(plan.sources),
        :line_count => length(edge_records),
        :transformer_count => length(transformer_records),
        :switch_count => length(switch_records),
        :capacitor_count => length(get(net, "capacitor", Dict())),
        :line_bound_diagnostics => line_bound_diagnostics,
        :implied_current_limits => options.implied_current_limits,
        :component_block_count => length(component_blocks),
        :matrix_kcl_entries => matrix_kcl_count,
        :global_voltage_closure => voltage_global !== nothing,
        :cone => options.cone,
        :objective_scale => objective_scale,
    )
    if optimizer isa _SDPDefaultOptimizer
        JuMP.set_optimizer(model, default_sdp_optimizer(:branch_flow))
        diagnostics[:optimizer_profile] = :clarabel_branch_flow
    else
        diagnostics[:optimizer_profile] = :caller_supplied
    end
    envelopes = sort!([String(id) for (id, data) in get(net, "load", Dict())
                       if _sdp_has_load_envelope(data)])
    build = BranchFlowSDPBuild(model, voltage_moments, edge_blocks,
        component_blocks, transformer_blocks, edge_records, component_records,
        transformer_records, switch_records, plan.oriented, powers, net,
        options, vb, ib, plan.root, root_voltage, source_voltages,
        voltage_global, voltage_indices, envelopes, LNCDiagnostic[],
        objective_scale, diagnostics)
    for spec in options.voltage_lncs
        add_voltage_lnc!(build, spec)
    end
    if options.lnc == :lines
        terminal_rows = (bus, terminals) ->
            [_sdp_e(voltage_indices[(String(bus), String(t))]) for t in terminals]
        fixed = Dict(index => value * vb
            for (key, value) in fixed_source_coordinates
            for index in (voltage_indices[key],) if index != 0)
        _add_line_lncs!(build, lnc_lines, terminal_rows, fixed)
    end
    build
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
    load_envelopes::Vector{String}
    lnc_diagnostics::Vector{LNCDiagnostic}
    numerical_diagnostics::Dict{Symbol,Any}
end
solve_status(r::BranchFlowSDPResult) = r.solve
solve_diagnostics(r::BranchFlowSDPResult) = (
    model_kind=:relaxation, rank_ratio=r.rank_ratio,
    load_envelopes=r.load_envelopes, lnc_diagnostics=r.lnc_diagnostics,
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
            Dict{Tuple{Symbol,String},Vector{ComplexF64}}(), NaN, status,
            copy(build.load_envelopes), copy(build.lnc_diagnostics), diagnostics)
    end
    vb, ib, sb = build.voltage_base, build.current_base, build.options.s_base
    W = Dict(id => Matrix{ComplexF64}(JuMP.value.(moment)) * vb^2
             for (id, moment) in build.voltage_moments)
    S = Dict{String,Matrix{ComplexF64}}()
    L = Dict{String,Matrix{ComplexF64}}()
    topology_ratios = Float64[]
    rank_ratios = Dict{String,Float64}()
    function record_ratio!(label, block)
        eigenvalues = eigvals(Hermitian(block))
        value = length(eigenvalues) > 1 ?
            max(0.0, eigenvalues[end-1]) / max(eps(), eigenvalues[end]) : 0.0
        rank_ratios[label] = value
        value
    end
    for edge in build.edge_records
        block = Matrix{ComplexF64}(JuMP.value.(build.edge_blocks[edge.id]))
        n = size(edge.S, 1)
        S[edge.id] = block[1:n, n+1:2n] * sb
        L[edge.id] = block[n+1:2n, n+1:2n] * ib^2
        push!(topology_ratios, record_ratio!("line/$(edge.id)", block))
    end
    component_values = Dict(key => Matrix{ComplexF64}(JuMP.value.(block))
        for (key, block) in build.component_blocks)
    transformer_values = Dict(key => Matrix{ComplexF64}(JuMP.value.(block))
        for (key, block) in build.transformer_blocks)
    for (key, block) in component_values
        record_ratio!("$(key[1])/$(key[2])", block)
    end
    for (key, block) in transformer_values
        push!(topology_ratios, record_ratio!("transformer/$key", block))
    end
    global_value = build.voltage_global === nothing ? nothing :
        Matrix{ComplexF64}(JuMP.value.(build.voltage_global))
    global_value === nothing ||
        push!(topology_ratios, record_ratio!("voltage/global", global_value))
    for record in build.switch_records
        record.block === nothing && continue
        push!(topology_ratios,
            get(rank_ratios, "switch/$(record.id)", 0.0))
    end
    voltage = Dict{Tuple{String,String},ComplexF64}()
    currents = Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    line_records = Dict(edge.id => edge for edge in build.edge_records)
    transformer_records = Dict(record.key => record for record in build.transformer_records)
    if global_value !== nothing
        source_id = first(sort!(collect(keys(build.source_voltages))))
        source = build.network["voltage_source"][source_id]
        source_values = build.source_voltages[source_id] ./ vb
        anchor_position = something(findfirst(!iszero, source_values), 0)
        anchor_position > 0 || error("source recovery anchor vanished")
        anchor_key = (String(source["bus"]), String(source["terminal_map"][anchor_position]))
        anchor_index = build.voltage_indices[anchor_key]
        recovered = global_value[:, anchor_index] ./ conj(source_values[anchor_position])
        for (key, index) in build.voltage_indices
            voltage[key] = index == 0 ? 0im : recovered[index] * vb
        end
        for (id, values) in build.source_voltages
            data = build.network["voltage_source"][id]
            for (terminal, value) in zip(data["terminal_map"], values)
                voltage[(String(data["bus"]), String(terminal))] = value
            end
        end
    else
        for (terminal, value) in zip(
            build.network["bus"][build.root]["terminal_names"], build.root_voltage)
            voltage[(build.root, terminal)] = value
        end
        for oriented in sort!(filter(edge -> edge.tree_edge, copy(build.topology));
                              by=edge -> edge.depth)
            terms_parent = build.network["bus"][oriented.parent]["terminal_names"]
            parent_voltage = ComplexF64[voltage[(oriented.parent, t)] / vb
                                        for t in terms_parent]
            denominator = real(dot(parent_voltage, parent_voltage))
            if oriented.kind == :line
                edge = line_records[oriented.id]
                current_pu = denominator > eps() ?
                    (S[edge.id] / sb)' * parent_voltage / denominator :
                    zeros(ComplexF64, length(parent_voltage))
                child_voltage = parent_voltage - edge.Z * current_pu
                for (terminal, value) in zip(
                    build.network["bus"][edge.child]["terminal_names"], child_voltage)
                    voltage[(edge.child, terminal)] = value * vb
                end
            elseif oriented.kind == :transformer
                key = "$(oriented.subtype)/$(oriented.id)"
                record = transformer_records[key]
                block = transformer_values[key]
                parent_indices = oriented.parent == record.from ? record.vf : record.vt
                state = denominator > eps() ?
                    block[:, parent_indices] * parent_voltage / denominator :
                    zeros(ComplexF64, record.dimension)
                child_indices = oriented.child == record.from ? record.vf : record.vt
                for (terminal, value) in zip(
                    build.network["bus"][oriented.child]["terminal_names"],
                    state[child_indices])
                    voltage[(oriented.child, terminal)] = value * vb
                end
            end
        end
    end
    for edge in build.edge_records
        parent_terms = string.(build.network["bus"][edge.parent]["terminal_names"])
        child_terms = string.(build.network["bus"][edge.child]["terminal_names"])
        vp = ComplexF64[voltage[(edge.parent, t)] / vb for t in parent_terms]
        vc = ComplexF64[voltage[(edge.child, t)] / vb for t in child_terms]
        denominator = real(dot(vp, vp))
        series_pu = denominator > eps() ?
            (S[edge.id] / sb)' * vp / denominator : zeros(ComplexF64, length(vp))
        parent_current = (series_pu + edge.Yp * vp) * ib
        child_current = (-series_pu + edge.Yc * vc) * ib
        if edge.reversed
            currents[(:line_series, edge.id)] = -series_pu * ib
            currents[(:line_from, edge.id)] = child_current
            currents[(:line_to, edge.id)] = parent_current
        else
            currents[(:line_series, edge.id)] = series_pu * ib
            currents[(:line_from, edge.id)] = parent_current
            currents[(:line_to, edge.id)] = child_current
        end
    end
    function recover_local_state(record, block)
        values = ComplexF64[voltage[(bus, terminal)] / vb
            for (bus, terminal) in zip(record.voltage_state_buses,
                                       record.voltage_state_terminals)]
        denominator = real(dot(values, values))
        denominator > eps() ? block[:, record.voltage_state_indices] * values /
            denominator : zeros(ComplexF64, record.dimension)
    end
    for record in build.transformer_records
        state = recover_local_state(record, transformer_values[record.key])
        if record.subtype == "n_winding"
            for k in eachindex(record.buses)
                key = "n_winding/$(record.id)/$k"
                currents[(:transformer_winding, key)] =
                    record.terminal_maps[k] * state * ib
                currents[(:transformer_coil, key)] =
                    record.coil_maps[k] * state * ib
            end
        else
            currents[(:transformer_from, record.key)] =
                record.terminal_from * state * ib
            currents[(:transformer_to, record.key)] =
                record.terminal_to * state * ib
            currents[(:transformer_coil_from, record.key)] = record.Ajf * state * ib
            currents[(:transformer_coil_to, record.key)] = record.Ajt * state * ib
        end
    end
    for record in build.switch_records
        if record.open
            currents[(:switch_from, record.id)] = zeros(ComplexF64, length(record.map_from))
            currents[(:switch_to, record.id)] = zeros(ComplexF64, length(record.map_to))
            continue
        end
        state = recover_local_state(record, component_values[(:switch, record.id)])
        currents[(:switch_from, record.id)] = record.Pf * record.Tf * state * ib
        currents[(:switch_to, record.id)] = record.Pt * record.Tt * state * ib
    end
    powers = Dict(key => ComplexF64.(JuMP.value.(values)) .* sb
                  for (key, values) in build.powers)
    for record in build.component_records
        terms = string.(build.network["bus"][record.bus]["terminal_names"])
        bus_voltage = ComplexF64[voltage[(record.bus, terminal)] for terminal in terms]
        if record.law == :fixed_voltage
            coil_current = ComplexF64.(JuMP.value.(record.current)) .* ib
        elseif record.law in (:constant_impedance, :capacitor)
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
        if record.current_kind == :terminal
            terminal_current = transpose(record.D) * coil_current
            data = build.network[String(record.family)][record.id]
            positions = [findfirst(==(terminal), terms)
                         for terminal in data["terminal_map"]]
            currents[(record.family, record.id)] = terminal_current[positions]
        else
            currents[(record.family, record.id)] = coil_current
        end
    end
    bound = try JuMP.objective_bound(build.model) catch; NaN end
    isfinite(bound) || (bound = try JuMP.dual_objective_value(build.model) catch; NaN end)
    bound *= build.objective_scale
    ratio = isempty(topology_ratios) ? NaN : maximum(topology_ratios)
    diagnostics[:local_rank_ratios] = rank_ratios
    diagnostics[:recovery] = global_value === nothing ? :tree : :global_anchor
    BranchFlowSDPResult(JuMP.objective_value(build.model) * build.objective_scale,
        bound, W, S, L, voltage, currents, powers, ratio, status,
        copy(build.load_envelopes), copy(build.lnc_diagnostics), diagnostics)
end
