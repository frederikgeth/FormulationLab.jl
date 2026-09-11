using FormulationLab, JuMP, Clarabel

"""Compare the same static OPF domain with/without automatically derived LNCs.

Call twice to exclude initial Julia compilation from timing. Residuals below are
JuMP constraint violations in the model's scaled units, not AC recovery residuals.
An optimizer keyword permits the same comparison with optional MosekTools.
"""
function compare_lncs(input;optimizer=FormulationLab.default_sdp_optimizer(),s_base=1e4,objective=:source_import)
    records=[]
    for mode in (:off,:lines)
        build_seconds=@elapsed build=build_opf(input,IVRSDP(;lnc=mode,s_base,objective);optimizer)
        set_silent(build.model)
        solve_seconds=@elapsed optimize!(build.model)
        primal=has_values(build.model)
        violations=primal ? primal_feasibility_report(build.model;atol=0.0) : Dict()
        record=(;mode,build_seconds,solve_seconds,
            status=string(termination_status(build.model)),primal_status=string(primal_status(build.model)),
            objective=primal ? objective_value(build.model)*build.objective_scale : NaN,
            solver_bound=try objective_bound(build.model)*build.objective_scale catch;NaN;end,
            dual_status=string(dual_status(build.model)),
            dual_objective=has_duals(build.model) ? dual_objective_value(build.model)*build.objective_scale : NaN,
            max_scaled_constraint_violation=primal ? maximum(values(violations);init=0.0) : NaN,
            variables=num_variables(build.model),
            constraints=num_constraints(build.model;count_variable_in_set_constraints=true),
            applied=count(d->d.status==:applied,build.lnc_diagnostics),
            skipped=count(d->d.status==:skipped,build.lnc_diagnostics))
        push!(records,record)
    end
    records
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("Usage: julia --project=<environment with Clarabel> examples/compare_lncs.jl case.json")
    input=read_bmopf(only(ARGS))
    compare_lncs(input) # warm up both paths
    foreach(println,compare_lncs(input))
end
