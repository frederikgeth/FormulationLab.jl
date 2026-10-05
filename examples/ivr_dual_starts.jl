# Experimental same-model dual transfer; not a production warm-start API.
module IVRDualStarts
using JuMP, JSON3, SHA
const SOURCE_SHA=bytes2hex(sha256(read(@__FILE__)))
rows(model)=[c for (F,S) in list_of_constraint_types(model) for c in all_constraints(model,F,S)]
rowkey(c)=string(typeof(index(c)),":",index(c).value)
digest(entries)=bytes2hex(sha256(JSON3.write(entries)))
# Copy expression containers while retaining the original variable references.
copy_function(x::Union{Real,VariableRef})=x
copy_function(x::Union{GenericAffExpr,GenericQuadExpr})=copy(x)
copy_function(x::GenericNonlinearExpr{V}) where V=GenericNonlinearExpr{V}(x.head,Any[copy_function(a) for a in x.args])
box(v)=(lower=has_lower_bound(v) ? lower_bound(v) : nothing,
        upper=has_upper_bound(v) ? upper_bound(v) : nothing,
        fixed=is_fixed(v) ? fix_value(v) : nothing)

function objective_without_prices(model,priced)
    obj=copy_function(objective_function(model))
    obj isa Union{GenericAffExpr,GenericQuadExpr} || throw(ArgumentError("polynomial objective required"))
    for v in priced;add_to_expression!(obj,-coefficient(obj,v),v);end
    obj
end

"""Cache all dual values and structure before any model update.

Bound duals are JuMP's reconstructed signed reduced costs, not a copy of both
native Ipopt multipliers. Only supported CP RHS and generator-box/price updates
are allowed between capture and apply; model/coordinate changes are refused.
"""
function capture(build)
    model=build.model
    has_duals(model) || throw(ArgumentError("an accepted solution with duals is required"))
    constraints=rows(model)
    data=Dict(c=>(value=dual(c),func=copy_function(constraint_object(c).func),set=constraint_object(c).set)
              for c in constraints)
    all(x->x.value isa Real && isfinite(x.value),values(data)) || throw(ArgumentError("finite scalar duals required"))
    vars=all_variables(model)
    rhs=Set(c for r in values(build.load_constraints) for c in vcat(r.p,r.q))
    generators=Set(v for g in values(build.generator_variables) for v in vcat(g.p,g.q))
    priced=Set(v for g in values(build.generator_variables) for v in g.p)
    (;build,model,vars,priced,sense=objective_sense(model),
      objective=objective_without_prices(model,priced),boxes=Dict(v=>box(v) for v in vars),data,rhs,generators,
      sha256=digest([(rowkey(c),data[c].value) for c in sort(constraints;by=rowkey)]))
end

"""Validate correspondence, then assign all current dual starts.

For reconstructed starts, retain unchanged rows and bounds; reset *both* sides
of any changed generator box to zero. New sides start at zero and removed sides
are discarded. `mode=:zero` assigns every current dual zero as an initializer
control. Schema/identity errors are detected before assigning any starts;
optimizer errors during assignment do not have a rollback guarantee.
"""
function apply!(build,cache;mode=:reconstructed)
    mode in (:reconstructed,:zero) || throw(ArgumentError("unknown dual policy"))
    build===cache.build && build.model===cache.model || throw(ArgumentError("dual cache belongs to another model"))
    model=build.model;vars=all_variables(model)
    vars==cache.vars || throw(ArgumentError("variable layout changed"))
    objective_sense(model)==cache.sense &&
        isequal_canonical(objective_without_prices(model,cache.priced),cache.objective) ||
        throw(ArgumentError("objective changed outside generator prices"))
    current=rows(model);old=Set(keys(cache.data));now=Set(current)
    nonvariable(c)=!(constraint_object(c).func isa VariableRef)
    Set(c for c in current if nonvariable(c))==Set(c for c in old if !(cache.data[c].func isa VariableRef)) ||
        throw(ArgumentError("non-variable-bound constraint layout changed"))
    changed=Set(v for v in vars if box(v)!=cache.boxes[v])
    issubset(changed,cache.generators) || throw(ArgumentError("non-generator box changed"))
    assignments=Pair{Any,Float64}[];reset_bounds=0;carried=0
    for c in current
        obj=constraint_object(c);variable=obj.func isa VariableRef
        JuMP.MOI.supports(backend(model),JuMP.MOI.ConstraintDualStart(),typeof(index(c))) ||
            throw(ArgumentError("dual starts unsupported for $(typeof(index(c)))"))
        if !variable
            saved=cache.data[c]
            isequal_canonical(obj.func,saved.func) && typeof(obj.set)==typeof(saved.set) ||
                throw(ArgumentError("constraint function or set type changed"))
            (c in cache.rhs || obj.set==saved.set) || throw(ArgumentError("non-load constraint set changed"))
        end
        reset=variable && (obj.func in changed || !(c in old))
        reset_bounds+=reset
        keep=mode==:reconstructed && !reset
        keep && !(c in old) && throw(ArgumentError("unmapped dual constraint"))
        value=keep ? cache.data[c].value : 0.
        isfinite(value) || throw(ArgumentError("nonfinite cached dual"))
        carried+=keep;push!(assignments,c=>Float64(value))
    end
    # All solution queries and validation precede the first mutation.
    for (c,value) in assignments;set_dual_start_value(c,value);end
    all(dual_start_value(c)==value for (c,value) in assignments) || error("dual starts differ from policy")
    (;mode,carried,reset_bounds,zeroed=length(current)-carried,
      added=length(setdiff(now,old)),removed=length(setdiff(old,now)),
      changed_boxes=sort!(name.(collect(changed))),matches_policy=true,
      source_sha256=cache.sha256,
      start_sha256=digest([(rowkey(c),value) for (c,value) in sort(assignments;by=p->rowkey(first(p)))]))
end
end
