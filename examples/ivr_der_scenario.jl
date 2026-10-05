"""Explicit, additive DER scenarios for constant-power external feeder inputs.

This changes the physical OPF. It is not an equivalent input normalization.
No original equipment, load, rating, voltage bound or accounting field is edited.
"""
module IVRDERScenario
using JSON3, SHA

function augment(input;capacity_ratio=1.5,reactive_ratio=0.5,prefix="study_der_")
    capacity_ratio isa Real && isfinite(capacity_ratio) && capacity_ratio>0 || throw(ArgumentError("positive finite capacity_ratio required"))
    reactive_ratio isa Real && isfinite(reactive_ratio) && reactive_ratio>=0 || throw(ArgumentError("nonnegative finite reactive_ratio required"))
    prefix isa AbstractString && !isempty(prefix) || throw(ArgumentError("nonempty generator prefix required"))
    isempty(get(input,"generator",Dict())) && isempty(get(input,"ibr",Dict())) ||
        throw(ArgumentError("scenario requires an input without existing generators or IBRs"))
    sites=Tuple{String,Any}[]
    for (id,d) in sort!(collect(get(input,"load",Dict()));by=first)
        p=get(d,"p_nom",nothing)
        p isa AbstractVector && !isempty(p) && all(x->x isa Real && isfinite(x) && x>=0,p) ||
            throw(ArgumentError("load/$id requires finite nonnegative active demand"))
        any(>(0),p) || continue
        lowercase(get(d,"model","constant_power"))=="constant_power" || throw(ArgumentError("load/$id is not constant power"))
        get(d,"configuration",nothing) in ("SINGLE_PHASE","WYE","DELTA") || throw(ArgumentError("load/$id has unsupported channel semantics"))
        haskey(d,"bus") && haskey(d,"terminal_map") || throw(ArgumentError("load/$id needs bus and terminal map"))
        haskey(input["bus"],d["bus"]) && all(t->t in input["bus"][d["bus"]]["terminal_names"],d["terminal_map"]) ||
            throw(ArgumentError("load/$id has invalid bus terminals"))
        n=d["configuration"]=="SINGLE_PHASE" ? 1 : 3
        length(p)==n || throw(ArgumentError("load/$id active demand does not match native channels"))
        push!(sites,(string(id),d))
    end
    isempty(sites) && throw(ArgumentError("at least one positive constant-power load required"))
    net=deepcopy(input);generators=get!(net,"generator",Dict{String,Any}());changes=Any[]
    for (id,d) in sites
        capacity=Float64.(d["p_nom"]).*capacity_ratio;reactive=capacity.*reactive_ratio
        all(isfinite,capacity) && all(isfinite,reactive) && all((capacity.>0).==(d["p_nom"].>0)) ||
            throw(ArgumentError("nonrepresentable DER capacity for load/$id"))
        gid=prefix*id
        generators[gid]=Dict("bus"=>d["bus"],"terminal_map"=>copy(d["terminal_map"]),"configuration"=>d["configuration"],
            "p_min"=>zeros(length(capacity)),"p_max"=>capacity,"q_min"=>-reactive,"q_max"=>reactive,
            "s_max"=>copy(capacity))
        push!(changes,(;generator_id=gid,source_load=id,before=nothing,after=deepcopy(generators[gid])))
    end
    manifest=(;kind="added_colocated_static_DER",capacity_ratio=Float64(capacity_ratio),reactive_ratio=Float64(reactive_ratio),
        input_sha256=bytes2hex(sha256(JSON3.write(input))),scenario_sha256=bytes2hex(sha256(JSON3.write(net))),changes,
        total_load_W=sum(sum(d["p_nom"]) for (_,d) in sites),
        total_active_capacity_W=sum(sum(d["p_max"]) for d in values(generators)),
        note="Explicit new dispatch scenario: add DER at every positive constant-power load, preserving native connections. P in [0,capacity_ratio*Pload], |Q|<=reactive_ratio*Pmax, |S|<=Pmax. All original fields retained. Zero-load sites skipped; zero-demand channels remain fixed zero. Static generation, no storage/time coupling. Not equivalent to the source network.")
    net,manifest
end

function write_scenario(path,output;kwargs...)
    canonical(p)=ispath(p) ? realpath(p) : abspath(p)
    any(p->canonical(p)==canonical(path),(output,output*".manifest.json")) &&
        throw(ArgumentError("scenario output and manifest must not overwrite the source"))
    raw=read(path);input=JSON3.read(String(copy(raw)),Dict{String,Any})
    net,details=augment(input;kwargs...)
    manifest=merge(details,(;source_path=abspath(path),source_sha256=bytes2hex(sha256(raw))))
    open(io->JSON3.write(io,net),output,"w")
    open(io->JSON3.write(io,manifest),output*".manifest.json","w")
    bytes2hex(sha256(read(path)))==manifest.source_sha256 || error("source changed during scenario creation")
    net,manifest
end
end
