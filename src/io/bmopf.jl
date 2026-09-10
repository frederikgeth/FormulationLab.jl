"""A BMOPF document read by PowerIO, with retained parser diagnostics and schema identity.

`network` is an independent SI snapshot. Retained-source diagnostics are not
claims of formulation support; every formulation must run its own applicability check.
"""
struct BMOPFInput
    network::Dict{String,Any}
    diagnostics::Vector{PowerIO.Diagnostic}
    schema_version::Union{Nothing,String}
    source_sha256::String
end

"""Read a BMOPF path, JSON string, IO, or PowerIO multiconductor module.

PowerIO owns exchange parsing. This migration adapter consumes its source-preserving
BMOPF emission so retained component fields reach applicability checks unchanged.
Programmatic dictionaries can also be passed directly to formulation builders;
they are not represented as schema-validated inputs.
"""
function read_bmopf(input::Union{AbstractString,IO})
    module_value = if input isa IO
        PowerIO.parse(input; format="bmopf-json")
    elseif startswith(lstrip(input), "{")
        PowerIO.parse(IOBuffer(input); format="bmopf-json")
    else
        PowerIO.parse(input; format="bmopf-json")
    end
    read_bmopf(module_value)
end

function read_bmopf(input::PowerIO.PioModule{PowerIO.MulticonductorNetwork})
    emitted = PowerIO.emit(input, "bmopf-json")
    raw = emitted.text
    raw === nothing && throw(ArgumentError("PowerIO did not emit a single BMOPF document"))
    net = JSON3.read(raw, Dict{String,Any})
    meta = get(net, "meta", Dict())
    version = get(meta, "schema_version", nothing)
    BMOPFInput(net, vcat(input.diagnostics, emitted.diagnostics),
        version === nothing ? nothing : String(version), bytes2hex(SHA.sha256(raw)))
end

# The migrated L3F compiler uses the 0.1 transformer tap spelling internally.
# 0.2 names the same multiplier tap_ratio. Never silently prefer conflicting values.
function _normalize_bmopf_snapshot(input::AbstractDict)
    net = deepcopy(Dict{String,Any}(string(k) => v for (k,v) in input))
    for subtype in ("single_phase", "center_tap", "wye_delta", "delta_wye"),
        tx in values(get(get(net,"transformer",Dict()),subtype,Dict()))
        for (canonical, legacy) in (("tap_ratio","tap"), ("tap_ratio_min","tap_min"), ("tap_ratio_max","tap_max"))
            haskey(tx,canonical) || continue
            haskey(tx,legacy) && tx[canonical] != tx[legacy] &&
                throw(ArgumentError("Conflicting $canonical and $legacy on $subtype transformer"))
            tx[legacy] = deepcopy(tx[canonical])
        end
    end
    net
end
