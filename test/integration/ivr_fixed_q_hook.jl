# Diagnostic only: mutate a privately built BMOPFTools model, never its source
# network or checkout. Fixed-Q inequalities remain the unmodified control.
function _fixed_q_equalities!(ctx)
    replaced=0
    for lower in collect(BMOPFTools.opf_object_keys(ctx;kind=:constraint))
        lower.family==:generator_q_lower || continue
        upper=BMOPFTools.OpfModelKey(:constraint,:generator_q_upper,lower.index)
        haskey(ctx.objects,upper) || continue
        lo=BMOPFTools.opf_object(ctx,lower);hi=BMOPFTools.opf_object(ctx,upper)
        a=JuMP.constraint_object(lo);b=JuMP.constraint_object(hi)
        a.set isa JuMP.MOI.GreaterThan && b.set isa JuMP.MOI.LessThan || continue
        a.set.lower==b.set.upper || continue
        JuMP.isequal_canonical(a.func,b.func) || error("Coincident Q limits have different functions")
        # This experiment supports static constraints only. Do not invalidate a
        # parameter binding or pretend the equality retains inequality duals.
        any(haskey(ctx.parameter_bindings,k) for k in (lower,upper)) &&
            error("Diagnostic fixed-Q hook does not support parameter-bound limits")
        equality=JuMP.add_constraint(ctx.model,JuMP.ScalarConstraint(a.func,JuMP.MOI.EqualTo(a.set.lower)))
        JuMP.delete(ctx.model,lo);JuMP.delete(ctx.model,hi)
        # Registry removal currently needs the context dictionary; this hook is
        # version-pinned integration infrastructure, not a public compiler API.
        delete!(ctx.objects,lower);delete!(ctx.objects,upper)
        BMOPFTools.register_opf_constraint!(ctx,:diagnostic_generator_q_fixed,lower.index,equality)
        replaced+=1
    end
    replaced
end
