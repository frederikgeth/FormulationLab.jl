# Numerical experiment only; does not change package defaults or constraints.
include("benchmark_nlp_soc.jl")
function tolerance_probe(panel_path,output)
    panel=JSON3.read(read(panel_path,String),Dict{String,Any});rows=Any[]
    warm,sb,_,_=prepare_case(first(panel["cases"])["path"])
    wb=build_opf(warm,IVRSOC(s_base=sb,objective=:source_import))
    solve_soc_opf(wb;solver_options=(verbose=false,tol_feas=1e-7,tol_gap_abs=1e-6,tol_gap_rel=1e-7))
    GC.gc()
    for c in panel["cases"]
        haskey(c,"nlp") && c["nlp"]["status"]=="LOCALLY_SOLVED" || continue
        s=filter(s->get(s,"variant","")=="linear",get(c,"soc",[]))
        isempty(s) && continue
        get(first(s),"termination","")=="ALMOST_OPTIMAL" || continue
        row=Dict{String,Any}("name"=>c["name"],"tolerances"=>Dict("tol_feas"=>1e-7,"tol_gap_abs"=>1e-6,"tol_gap_rel"=>1e-7));push!(rows,row)
        println("PROBE ",c["name"]);flush(stdout)
        try
            net,sb,_,_=prepare_case(c["path"])
            bt=@elapsed b=build_opf(net,IVRSOC(s_base=sb,objective=:source_import))
            set_time_limit_sec(b.model,90.)
            st=@elapsed r=solve_soc_opf(b;solver_options=(verbose=false,tol_feas=1e-7,tol_gap_abs=1e-6,tol_gap_rel=1e-7))
            merge!(row,Dict("status"=>r.solve.termination_status,"build_seconds"=>bt,"solve_seconds"=>st,
                "objective_W"=>finite(r.objective),"solver_bound_W"=>finite(r.solver_objective_bound),
                "nlp_minus_soc_W"=>finite(c["nlp"]["source_W"]-r.objective),
                "raw_primal_candidate_W"=>has_values(b.model) ? objective_value(b.model)*b.electrical.objective_scale : nothing))
            if has_values(b.model)
                violations=primal_feasibility_report(b.model;atol=0.)
                for (F,S) in list_of_constraint_types(b.model)
                    S==MOI.RotatedSecondOrderCone || continue
                    for ref in all_constraints(b.model,F,S)
                        x=value.(constraint_object(ref).func)
                        y=[(x[1]+x[2])/sqrt(2),(x[1]-x[2])/sqrt(2),x[3:end]...]
                        violations[ref]=MOI.Utilities.distance_to_set(y,MOI.SecondOrderCone(length(y)))
                    end
                end
                row["geometric_constraint_violation"]=maximum(values(violations);init=0.)
            end
            println(row["status"]);flush(stdout)
        catch e;row["error"]=sprint(showerror,e);end
        open(io->JSON3.write(io,finite(rows)),output,"w");GC.gc()
    end
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    tolerance_probe(ARGS[1],ARGS[2])
end
