# Certificates concern the represented polynomial over the reals: Float64
# coefficients/fixings are converted exactly, with no tolerance or rationalize.
struct _IVRNFixedBoundUncertified <: Exception end
_ivrn_exact_scalar(x::Union{Integer,Rational,AbstractFloat}) =
    isfinite(x) ? Rational{BigInt}(x) : throw(_IVRNFixedBoundUncertified())
_ivrn_exact_scalar(x) = throw(_IVRNFixedBoundUncertified())
_ivrn_fixed_value(x::Real,deps)=_ivrn_exact_scalar(x)
function _ivrn_fixed_value(x::JuMP.VariableRef,deps)
    JuMP.is_fixed(x) || throw(_IVRNFixedBoundUncertified())
    v=_ivrn_exact_scalar(JuMP.fix_value(x));deps[x]=v;v
end
function _ivrn_fixed_value(x::JuMP.GenericAffExpr,deps)
    v=_ivrn_exact_scalar(JuMP.constant(x))
    for (a,z) in JuMP.linear_terms(x)
        iszero(a) || (v+=_ivrn_exact_scalar(a)*_ivrn_fixed_value(z,deps))
    end
    v
end
function _ivrn_fixed_value(x::JuMP.GenericQuadExpr,deps)
    v=_ivrn_fixed_value(x.aff,deps)
    for (a,z,w) in JuMP.quad_terms(x)
        iszero(a) || (v+=_ivrn_exact_scalar(a)*_ivrn_fixed_value(z,deps)*_ivrn_fixed_value(w,deps))
    end
    v
end
_ivrn_fixed_value(x,deps)=throw(_IVRNFixedBoundUncertified())
_ivrn_fixed_slack(v,s::JuMP.MOI.LessThan)=_ivrn_exact_scalar(s.upper)-v
_ivrn_fixed_slack(v,s::JuMP.MOI.GreaterThan)=v-_ivrn_exact_scalar(s.lower)
_ivrn_fixed_slack(v,s::JuMP.MOI.EqualTo)=-abs(v-_ivrn_exact_scalar(s.value))
_ivrn_fixed_slack(v,s::JuMP.MOI.Interval)=min(v-_ivrn_exact_scalar(s.lower),_ivrn_exact_scalar(s.upper)-v)
_ivrn_fixed_slack(v,s)=throw(_IVRNFixedBoundUncertified())
function _ivrn_fixed_bound_certificate(c)
    dependencies=Dict{JuMP.VariableRef,Rational{BigInt}}()
    try
        value=_ivrn_fixed_value(c.func,dependencies);slack=_ivrn_fixed_slack(value,c.set)
        (;status=slack>=0 ? :implied : :violated,value,slack,dependencies)
    catch err
        err isa _IVRNFixedBoundUncertified || rethrow()
        (;status=:uncertified,value=nothing,slack=nothing,dependencies)
    end
end
_ivrn_fixed_bound_certificate(c::JuMP.ConstraintRef)=_ivrn_fixed_bound_certificate(JuMP.constraint_object(c))
const _IVRN_FIXED_BOUND_TABLES=(:ivr_bus_limit_rows,:ivr_equipment_limit_rows,:ivr_ibr_operating_rows)

# Dispatch boxes are intentionally excluded: supported generator updates may
# delete/recreate them. Immutable operating declarations remain in their tables.
function _ivrn_remove_fixed_bounds!(model)
    certificates=Dict{Any,Any}()
    for key in _IVRN_FIXED_BOUND_TABLES, q in model.ext[key], ref in q.constraints
        haskey(certificates,ref) && continue
        c=JuMP.constraint_object(ref);proof=_ivrn_fixed_bound_certificate(c)
        proof.status==:implied || continue
        f=c.func isa Union{JuMP.GenericAffExpr,JuMP.GenericQuadExpr} ? copy(c.func) : c.func
        certificates[ref]=(;constraint=JuMP.ScalarConstraint(f,c.set),proof)
    end
    for key in _IVRN_FIXED_BOUND_TABLES
        rows=model.ext[key]
        for j in eachindex(rows)
            q=rows[j];removed=[ref for ref in q.constraints if haskey(certificates,ref)]
            isempty(removed) && continue
            retained=[ref for ref in q.constraints if !haskey(certificates,ref)]
            rows[j]=merge(q,(;constraints=retained,original_form=q.form,
                original_constraints=[haskey(certificates,ref) ? certificates[ref].constraint : ref for ref in q.constraints],
                form=isempty(retained) ? :certified_fixed : :partially_certified_fixed,
                fixed_certificates=[(;ref,certificates[ref]...) for ref in removed]))
        end
    end
    for ref in keys(certificates);JuMP.delete(model,ref);end
    model.ext[:ivr_fixed_bound_certificates]=certificates
    [(;constraint_type=string(typeof(ref)),constraint_index=JuMP.index(ref).value,value=string(q.proof.value),slack=string(q.proof.slack),
        dependencies=[(;variable_index=JuMP.index(v).value,value=string(x))
            for (v,x) in sort!(collect(q.proof.dependencies);by=t->JuMP.index(first(t)).value)])
        for (ref,q) in sort!(collect(certificates);by=t->(string(typeof(first(t))),JuMP.index(first(t)).value))]
end

# Omission is conditional on these exact fixings. Detect stale certificates at
# public solve/update/point-audit boundaries and when cataloguing declarations.
function _ivrn_validate_fixed_bounds(model)
    certificates=get(model.ext,:ivr_fixed_bound_certificates,nothing)
    certificates===nothing && return
    for (ref,q) in certificates
        JuMP.is_valid(model,ref) && throw(ArgumentError("removed fixed-bound row was restored; rebuild"))
        for (v,x) in q.proof.dependencies
            JuMP.is_valid(model,v) && JuMP.is_fixed(v) &&
                isfinite(JuMP.fix_value(v)) && _ivrn_exact_scalar(JuMP.fix_value(v))==x ||
                throw(ArgumentError("fixed-bound certificate dependency changed; rebuild the model"))
        end
        proof=_ivrn_fixed_bound_certificate(q.constraint)
        proof.status==:implied && proof.value==q.proof.value && proof.slack==q.proof.slack ||
            throw(ArgumentError("invalid fixed-bound certificate"))
    end
    recorded=Set{Any}()
    for key in _IVRN_FIXED_BOUND_TABLES, q in model.ext[key]
        for c in get(q,:fixed_certificates,())
            haskey(certificates,c.ref) && c.proof==certificates[c.ref].proof ||
                throw(ArgumentError("missing fixed-bound provenance"))
            push!(recorded,c.ref)
        end
    end
    recorded==Set(keys(certificates)) || throw(ArgumentError("incomplete fixed-bound provenance"))
    nothing
end
_ivrn_original_bound_constraints(q) = get(q,:original_constraints,q.constraints)
