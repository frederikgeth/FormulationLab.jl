using FormulationLab, JuMP, Clarabel, JSON3, LinearAlgebra

# Benchmark-only cleanup; original input dictionaries and files are not changed.
_sdp_benchmark_clean(x::AbstractDict)=Dict(String(k)=>_sdp_benchmark_clean(v) for (k,v) in x if !startswith(String(k),"_"))
_sdp_benchmark_clean(x::AbstractVector)=_sdp_benchmark_clean.(x)
_sdp_benchmark_clean(x)=x

"""Compare reference and Clarabel SDP profiles on an identical import objective.

Input is a BMOPF dictionary. Removing source-bus generators is opt-in and recorded.
No failed-solver iterate is published as an objective/bound. Residuals are in
scaled model units, not independent AC feasibility certificates. Mosek can be
passed as `optimizer` without adding it to the package dependencies.
"""
function benchmark_sdp(input;remove_source_generators=false,s_base=1e4,
        optimizer=FormulationLab.default_sdp_optimizer(),time_limit=60.0,
        variants=(:reference,:clarabel,:clarabel_lnc))
    net=_sdp_benchmark_clean(input);removed=String[]
    if remove_source_generators
        source_buses=Set(s["bus"] for s in values(net["voltage_source"]))
        for (id,g) in collect(get(net,"generator",Dict()))
            if g["bus"] in source_buses;delete!(net["generator"],id);push!(removed,id);end
        end
    end
    rows=[]
    for variant in variants
        profile=variant==:reference ? :reference : :clarabel
        options=SDPOptions(;profile,s_base,objective=:source_import,lnc=variant==:clarabel_lnc ? :lines : :off)
        build_seconds=@elapsed b=build_sdp_opf(net,optimizer;options)
        set_silent(b.model);set_time_limit_sec(b.model,time_limit)
        solve_seconds=@elapsed optimize!(b.model)
        accepted=termination_status(b.model)==MOI.OPTIMAL && primal_status(b.model)==MOI.FEASIBLE_POINT
        numerics=copy(b.numerical_diagnostics)
        report=bound_report(b)
        numerics[:bound_report]=(sweeps=report.sweeps, maps=length(report.entries),
            finite_upper_bounds=count(e->isfinite(e.upper_pu),report.entries),
            missing_capabilities=report.missing_capabilities)
        row=Dict("variant"=>string(variant),"s_base_VA"=>s_base,"v_base_V"=>b.voltage_base,
            "objective"=>"source_import_W","removed_generators"=>sort(removed),
            "build_seconds"=>build_seconds,"solve_seconds"=>solve_seconds,
            "termination_status"=>string(termination_status(b.model)),"primal_status"=>string(primal_status(b.model)),
            "source_import_W"=>accepted ? objective_value(b.model)*b.objective_scale : nothing,
            "solver_dual_W"=>accepted && has_duals(b.model) ? dual_objective_value(b.model)*b.objective_scale : nothing,
            "max_scaled_violation"=>has_values(b.model) ? maximum(values(primal_feasibility_report(b.model;atol=0.0));init=0.0) : nothing,
            "variables"=>num_variables(b.model),"numerics"=>numerics,
            "lncs_applied"=>count(d->d.status==:applied,b.lnc_diagnostics))
        push!(rows,row)
    end
    rows
end

if abspath(PROGRAM_FILE)==@__FILE__
    files=filter(!=("--remove-source-generators"),ARGS)
    isempty(files) && error("Usage: julia --project=test examples/benchmark_sdp.jl [--remove-source-generators] case.json ...")
    BLAS.set_num_threads(1)
    for file in files
        net=JSON3.read(read(file,String),Dict{String,Any})
        rows=benchmark_sdp(net;remove_source_generators="--remove-source-generators" in ARGS)
        println(JSON3.write(Dict("file"=>abspath(file),"results"=>rows)));flush(stdout)
    end
end
