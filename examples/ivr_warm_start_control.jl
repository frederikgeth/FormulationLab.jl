"""Diagnostic, representable Ipopt warm starts; not arbitrary internal-state replay."""
module IVRWarmStartControl
using JuMP, Ipopt
const MOI=JuMP.MOI
const EXT=Base.get_extension(Ipopt,:IpoptMathOptInterfaceExt)

"""Options for paired warm starts with inactive multiplier clipping.

The caller must verify native initial vectors: positive bound pushes remain,
slacks are reconstructed from g(x), and bound multipliers are derived from lambda.
"""
settings()=(;warm_start_init_point="yes",warm_start_entire_iterate="no",
    warm_start_bound_push=1e-8,warm_start_bound_frac=1e-8,
    warm_start_slack_bound_push=1e-8,warm_start_slack_bound_frac=1e-8,
    warm_start_mult_bound_push=1e-8,warm_start_mult_init_max=0.,warm_start_target_mu=0.)

"""Seed a representable state in the original TNLP dual units.

`row_scales` and `objective_scale` refer to a reference run. Reuse these SAME
arguments in both scaling arms. The reference's one-sided inequality multipliers
have magnitude one internally, and its variable-bound multipliers equal one.
Equality multipliers are zero. These are new warm starts, not the cold-start
state: the latter generally has y_d=0 and v=1, which ordinary dual starts cannot
independently prescribe. Only scalar equalities and one-sided rows are supported.
Call after attaching the Ipopt optimizer; only dual starts are changed.
"""
function seed!(model;objective_scale,row_scales)
    pkgversion(Ipopt)==v"1.16.0" || throw(ArgumentError("Ipopt.jl 1.16.0 required"))
    objective_sense(model)==MOI.MIN_SENSE || throw(ArgumentError("minimization required"))
    isfinite(objective_scale) && objective_scale>0 || throw(ArgumentError("invalid objective scale"))
    all(r->isfinite(r)&&r>0,row_scales) || throw(ArgumentError("invalid row scales"))
    opt=unsafe_backend(model)
    opt isa Ipopt.Optimizer || throw(ArgumentError("attached Ipopt optimizer required"))
    changes=Pair[];seen=Set{Int}()
    for c in all_constraints(model;include_variable_in_set_constraints=true)
        obj=constraint_object(c);s=obj.set
        (s isa MOI.EqualTo || s isa MOI.GreaterThan || s isa MOI.LessThan) ||
            throw(ArgumentError("only equalities and one-sided scalar bounds supported"))
        factor=if obj.func isa VariableRef
            1/objective_scale
        else
            i=EXT.row(opt,optimizer_index(c))
            i isa Int && 1<=i<=length(row_scales) && !(i in seen) || error("invalid row mapping")
            push!(seen,i);row_scales[i]/objective_scale
        end
        value=s isa MOI.EqualTo ? 0. : s isa MOI.GreaterThan ? factor : -factor
        isfinite(value) || throw(ArgumentError("nonfinite dual seed"))
        push!(changes,c=>value)
    end
    seen==Set(1:length(row_scales)) || error("incomplete row mapping")
    # Validate the entire plan before changing any start values.
    for (c,value) in changes;set_dual_start_value(c,value);end
    (;seeded_constraints=length(changes),rows=length(seen),timing_eligible=false)
end
end
