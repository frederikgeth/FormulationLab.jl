using FormulationLab, JuMP, Clarabel, JSON3, LinearAlgebra
include("benchmark_sdp.jl")

"""Compare the matching SDP, pairwise SOC, physical SOC and eigenvector OA.

Source-bus generator removal is opt-in. Bases and all electrical options are
identical across variants. Times include result extraction but exclude building.
The first invocation includes Julia compilation; warm up before timing.
"""
function benchmark_soc(input;remove_source_generators=false,s_base=1e4,time_limit=90.,max_rounds=30,
                       variants=(:sdp,:pairwise,:physical,:oa))
    net=_sdp_benchmark_clean(input);removed=String[]
    if remove_source_generators
        buses=Set(d["bus"] for d in values(net["voltage_source"]))
        for (id,d) in collect(get(net,"generator",Dict()))
            if d["bus"] in buses;delete!(net["generator"],id);push!(removed,id);end
        end
    end
    rows=[]
    for variant in variants
        variant in (:sdp,:pairwise,:physical,:oa) || throw(ArgumentError("unknown variant"))
        f=variant==:sdp ? IVRSDP(;s_base,objective=:source_import) :
            IVRSOC(;s_base,objective=:source_import,physical_projections=variant!=:pairwise)
        bt=@elapsed b=build_opf(net,f)
        JuMP.set_time_limit_sec(b.model,time_limit)
        st=@elapsed r=variant==:sdp ? solve_sdp_opf(b;solver_options=(verbose=false,)) :
            solve_soc_opf(b;separation=variant==:oa ? PSDSeparationOptions(;max_rounds,time_limit) : nothing,
                          solver_options=(verbose=false,))
        types=[string(S) for (_,S) in list_of_constraint_types(b.model)]
        variant==:sdp || @assert all(!occursin("Semidefinite",s) for s in types)
        push!(rows,Dict("variant"=>string(variant),"removed_generators"=>sort(removed),
            "s_base_VA"=>s_base,"objective_W"=>isfinite(r.objective) ? r.objective : nothing,
            "solver_bound_W"=>isfinite(r.solver_objective_bound) ? r.solver_objective_bound : nothing,
            "termination"=>r.solve.termination_status,"primal_status"=>r.solve.primal_status,
            "build_seconds"=>bt,"solve_seconds"=>st,"variables"=>num_variables(b.model),
            "cone_types"=>types,"max_scaled_violation"=>has_values(b.model) ?
                maximum(values(primal_feasibility_report(b.model));init=0.) : nothing,
            "stop_reason"=>variant==:sdp ? nothing : string(r.stop_reason),
            "psd_residual"=>variant==:sdp || !isfinite(r.psd_residual) ? nothing : r.psd_residual,
            "cuts"=>variant==:sdp ? 0 : r.cuts,"history"=>variant==:sdp ? [] : r.history))
    end
    rows
end

if abspath(PROGRAM_FILE)==@__FILE__
    files=filter(!=("--remove-source-generators"),ARGS)
    isempty(files) && error("Usage: julia --project=test examples/benchmark_soc.jl [--remove-source-generators] case.json ...")
    BLAS.set_num_threads(1)
    for file in files
        input=JSON3.read(read(file,String),Dict{String,Any})
        rows=benchmark_soc(input;remove_source_generators="--remove-source-generators" in ARGS)
        println(JSON3.write(Dict("file"=>abspath(file),"results"=>rows)));flush(stdout)
    end
end
