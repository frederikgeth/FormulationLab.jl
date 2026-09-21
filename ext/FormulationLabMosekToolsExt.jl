module FormulationLabMosekToolsExt
using FormulationLab, JuMP, MosekTools

const MOI = JuMP.MOI
const Mosek = MosekTools.Mosek

function FormulationLab._solver_numerical_diagnostics(
    optimizer::MosekTools.Optimizer,
)
    task = MOI.get(optimizer, MOI.RawSolver())
    items = (
        "interior_point_primal_feasibility" => Mosek.MSK_DINF_INTPNT_PRIMAL_FEAS,
        "interior_point_dual_feasibility" => Mosek.MSK_DINF_INTPNT_DUAL_FEAS,
        "interior_point_optimality" => Mosek.MSK_DINF_INTPNT_OPT_STATUS,
        "interior_point_primal_objective" => Mosek.MSK_DINF_INTPNT_PRIMAL_OBJ,
        "interior_point_dual_objective" => Mosek.MSK_DINF_INTPNT_DUAL_OBJ,
        "solution_primal_constraint_violation" => Mosek.MSK_DINF_SOL_ITR_PVIOLCON,
        "solution_primal_cone_violation" => Mosek.MSK_DINF_SOL_ITR_PVIOLCONES,
        "solution_primal_variable_violation" => Mosek.MSK_DINF_SOL_ITR_PVIOLVAR,
        "solution_dual_constraint_violation" => Mosek.MSK_DINF_SOL_ITR_DVIOLCON,
        "solution_dual_cone_violation" => Mosek.MSK_DINF_SOL_ITR_DVIOLCONES,
        "solution_dual_variable_violation" => Mosek.MSK_DINF_SOL_ITR_DVIOLVAR,
    )
    Dict(name => Float64(Mosek.getdouinf(task, item)) for (name, item) in items)
end

end
