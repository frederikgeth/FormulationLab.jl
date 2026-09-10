# Numerical coordinate preparation for the supported, already-lowered L3F network.
# SI data and result quantities are never mutated. Taps do not change voltage bases.
struct CoordinateBases
    s_base::Float64
    v_base::Dict{String,Float64}
    i_base::Dict{String,Float64}
    z_base::Dict{String,Float64}
end

function _l3f_bases(net, s_base)
    adjacency = Dict{String,Vector{Tuple{String,Float64}}}()
    function connect(a, b, ratio)
        isfinite(ratio) && ratio > 0 || throw(ArgumentError("Invalid nominal ratio at $(a)–$(b)"))
        push!(get!(adjacency, a, Tuple{String,Float64}[]), (b, ratio))
        push!(get!(adjacency, b, Tuple{String,Float64}[]), (a, inv(ratio)))
    end
    for line in values(get(net, "line", Dict()))
        connect(String(line["bus_from"]), String(line["bus_to"]), 1.0)
    end
    for table in values(get(net, "transformer", Dict())), tx in values(table)
        connect(String(tx["bus_from"]), String(tx["bus_to"]),
            Float64(get(tx, "v_nom_to", 1.0)) / Float64(get(tx, "v_nom_from", 1.0)))
    end
    vb = Dict{String,Float64}()
    # Seed every island, in deterministic order. Never assign a fallback base
    # to a disconnected bus: applicability and coordinates must agree.
    queue = String[]
    for (_, source) in sort!(collect(get(net, "voltage_source", Dict())); by=first)
        b = String(source["bus"])
        value = maximum(abs, source["v_magnitude"])
        isfinite(value) && value > 0 || throw(ArgumentError("Invalid source voltage base at $b"))
        haskey(vb, b) && !isapprox(vb[b], value) && throw(ArgumentError("Conflicting voltage bases at $b"))
        vb[b] = value
        push!(queue, b)
    end
    cursor = 1
    while cursor <= length(queue)
        b = queue[cursor]; cursor += 1
        for (other, ratio) in get(adjacency, b, Tuple{String,Float64}[])
            value = vb[b] * ratio
            if haskey(vb, other)
                isapprox(vb[other], value; rtol=1e-8) ||
                    throw(ArgumentError("Inconsistent nominal voltage bases at $other"))
            else
                vb[other] = value
                push!(queue, other)
            end
        end
    end
    all(haskey(vb, String(b)) for b in keys(net["bus"])) ||
        throw(ArgumentError("Cannot assign voltage bases to an unreferenced island"))
    CoordinateBases(s_base, vb, Dict(b => s_base / v for (b,v) in vb),
                    Dict(b => v^2 / s_base for (b,v) in vb))
end

function _scale_fields!(data, fields, divisor)
    for f in fields
        haskey(data, f) || continue
        v = data[f]
        data[f] = v isa AbstractArray ? Float64.(v) ./ divisor : Float64(v) / divisor
    end
end

function _scale_line_data!(data, zb, ib, sb)
    for (key, value) in data
        if occursin(r"^[RX]_series_\d+_\d+$", key)
            data[key] = Float64(value) / zb
        elseif occursin(r"^[GB]_(from|to)_\d+_\d+$", key)
            data[key] = Float64(value) * zb
        end
    end
    _scale_fields!(data, ("i_max",), ib)
    _scale_fields!(data, ("s_max",), sb)
end

function _l3f_scale_network(physical, sb)
    bases = _l3f_bases(physical, sb)
    net = deepcopy(physical)
    for (bid, bus) in net["bus"]
        _scale_fields!(bus, ("v_min", "v_max", "vpn_min", "vpn_max", "vpp_min",
            "vpp_max", "vn_max", "vpos_min", "vpos_max", "vneg_max", "vzero_max"), bases.v_base[bid])
    end
    for family in ("load", "generator", "voltage_source")
        for item in values(get(net, family, Dict()))
            b = String(item["bus"])
            _scale_fields!(item, ("p_nom", "q_nom", "p_min", "p_max", "q_min", "q_max", "s_max"), sb)
            _scale_fields!(item, ("v_nom", "v_magnitude"), bases.v_base[b])
            _scale_fields!(item, ("i_max",), bases.i_base[b])
            _scale_fields!(item, ("cost",), inv(sb))
        end
    end
    # Specialize each used linecode by voltage base; preserve existing ids at
    # the first base and use collision-free ids for additional voltage levels.
    codes = get(net, "linecode", Dict{String,Any}())
    original_codes = get(physical, "linecode", Dict())
    used = Dict{Tuple{String,Float64},String}()
    for (id, line) in sort!(collect(get(net, "line", Dict())); by=first)
        b = String(line["bus_from"]); zb = bases.z_base[b]; ib = bases.i_base[b]
        if haskey(line, "linecode")
            old = String(line["linecode"])
            key = (old, zb)
            new = get!(used, key) do
                name = old
                if any(k[1] == old for k in keys(used))
                    i = 1
                    while haskey(codes, name)
                        name = old * "__flbase" * string(i); i += 1
                    end
                end
                codes[name] = deepcopy(original_codes[old])
                _scale_line_data!(codes[name], zb, ib, sb)
                name
            end
            line["linecode"] = new
        end
        _scale_line_data!(line, zb, ib, sb)
    end
    for table in values(get(net, "transformer", Dict())), tx in values(table)
        for side in ("from", "to")
            b = String(tx["bus_$side"])
            _scale_fields!(tx, ("v_nom_$side",), bases.v_base[b])
            _scale_fields!(tx, ("r_series_$side", "x_series_$side", "r_neutral_$side", "x_neutral_$side"), bases.z_base[b])
        end
        # Ratings at original external endpoints are scaled by the caller.
    end
    for sh in values(get(net, "shunt", Dict()))
        zb = bases.z_base[String(sh["bus"])]
        for (key, value) in sh
            occursin(r"^[GB]_\d+_\d+$", key) && (sh[key] = Float64(value) * zb)
        end
    end
    net, bases
end
