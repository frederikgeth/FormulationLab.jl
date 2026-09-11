using FormulationLab, JuMP, Clarabel, JSON3, LinearAlgebra
include("benchmark_sdp.jl")

"""Compare matching SDP, physical SOC and fixed strengthening.

Source-bus generator removal is opt-in. Bases and all electrical options are
identical across variants. Times include result extraction but exclude building.
The first invocation includes Julia compilation; warm up before timing.
"""
function benchmark_soc(input;remove_source_generators=false,s_base=1e4,time_limit=90.,
                       variants=(:sdp,:physical,:linear,:kim,:lnc))
    net=_sdp_benchmark_clean(input);removed=String[]
    if remove_source_generators
        buses=Set(d["bus"] for d in values(net["voltage_source"]))
        for (id,d) in collect(get(net,"generator",Dict()))
            if d["bus"] in buses;delete!(net["generator"],id);push!(removed,id);end
        end
    end
    rows=[]
    for variant in variants
        variant in (:sdp,:physical,:linear,:kim,:lnc) || throw(ArgumentError("unknown variant"))
        f=variant==:sdp ? IVRSDP(;s_base,objective=:source_import) :
            IVRSOC(;s_base,objective=:source_import,strengthening=variant==:lnc ? :linear : variant in (:linear,:kim) ? variant : :none,
                lnc=variant==:lnc ? :lines : :off)
        bt=@elapsed b=build_opf(net,f)
        JuMP.set_time_limit_sec(b.model,time_limit)
        st=@elapsed r=variant==:sdp ? solve_sdp_opf(b;solver_options=(verbose=false,)) :
            solve_soc_opf(b;solver_options=(verbose=false,))
        types=[string(S) for (_,S) in list_of_constraint_types(b.model)]
        variant==:sdp || @assert all(!occursin("Semidefinite",s) for s in types)
        numerical=variant==:sdp ? b.numerical_diagnostics : b.electrical.numerical_diagnostics
        profile=get(numerical,:fixed_strengthening,nothing)
        report=bound_report(b)
        push!(rows,Dict("bound_sweeps"=>report.sweeps,"missing_capabilities"=>report.missing_capabilities,
            "finite_magnitude_bounds"=>count(e->isfinite(e.upper_pu),report.entries),
            "derived_current_bounds"=>numerical[:derived_current_bounds],
            "lncs_applied"=>count(d->d.status==:applied,variant==:sdp ? b.lnc_diagnostics : b.electrical.lnc_diagnostics),
            "secants"=>profile===nothing ? 0 : profile.secants,
            "triplets"=>profile===nothing ? 0 : length(profile.triplets),
            "projection_cones"=>profile===nothing ? 0 : profile.cones,
            "variant"=>string(variant),"removed_generators"=>sort(removed),
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
