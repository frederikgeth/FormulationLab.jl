"""Exact stored-coefficient certificates for omitted linear circuit rows."""
module IVRImpliedResidualCertificate
using FormulationLab, JuMP, LinearAlgebra
include("ivr_circuit_residual_trace.jl")
const C=IVRCircuitResidualTrace
const F=FormulationLab
const Q=Rational{BigInt}
const CQ=Complex{Q}
const Row=Dict{Int,CQ}
_q(x::Real)=isfinite(x) ? Q(x) : throw(ArgumentError("finite coefficients required"))
_q(x::Complex)=complex(_q(real(x)),_q(imag(x)))

function _add!(out,row,factor)
    for (k,a) in row
        out[k]=get(out,k,zero(CQ))+factor*a
        iszero(out[k]) && delete!(out,k)
    end
    out
end
function _compose(row,R)
    out=Row()
    for (k,a) in row;_add!(out,R[k],_q(a));end
    out
end
_dot(row,y)=sum((a*y[k] for (k,a) in row);init=zero(CQ))
_original(e,q)=q.kind==:kcl ? e.kcl[q.key] : e.equations[q.index]
function _divisor(build,q)
    e=build.electrical;row=_original(e,q)
    d=build.numerical_diagnostics[:composed_row_normalization] ?
        F._ivrn_scaled_row_norm(row,build.coordinates) : norm(collect(values(row)))
    q.kind==:kcl && (d=F._ivrn_kcl_row_divisor(d,e.ib,get(build.numerical_diagnostics,:kcl_row_max_base,nothing)))
    isfinite(d) && d>0 || throw(ArgumentError("positive finite retained divisor required"))
    _q(d)
end

"""Construct aRy = sum(c_j eta_j) + delta*y, with eta_j = a_j*R*y/d_j.

All products and cancellations use exact rationals of stored coefficients.
Specialization KCL uses minus the other retained KCL rows at that bus. Rows
removed by substitution have no dependencies. Any remaining coefficient is
kept in delta, including defects contributed by other omitted same-bus rows.
This neither fits dependencies numerically nor changes model coefficients.
"""
function certificates(build)
    cat=C.catalog(build)
    isempty(cat.unclassified_equations) || throw(ArgumentError("complete circuit-row provenance required"))
    R=[Row(k=>_q(a) for (k,a) in row) for row in build.coordinates.reconstruction]
    e=build.electrical
    rows=[_compose(_original(e,q),R) for q in cat.rows]
    divisors=Dict(i=>_divisor(build,q) for (i,q) in enumerate(cat.rows) if q.retained_constraint)
    result=NamedTuple[]
    for (i,q) in enumerate(cat.rows)
        q.retained_constraint && continue
        indices=q.reason==:specialization ?
            [j for (j,r) in enumerate(cat.rows) if r.kind==:kcl && r.key[1]==q.key[1] && r.retained_constraint] : Int[]
        defect=copy(rows[i]);dependencies=NamedTuple[]
        for j in indices
            # c_j=-d_j, so c_j*eta_j=-a_j*R*y exactly.
            _add!(defect,rows[j],one(Q))
            push!(dependencies,(;label=cat.rows[j].label,coefficient=-divisors[j],
                divisor=divisors[j],row=rows[j]))
        end
        push!(result,(;q...,method=q.reason==:specialization ? :same_bus_kcl : :reconstruction,
            coordinate_count=length(build.coordinates.real_variables),scale=_q(q.physical_scale),
            row=rows[i],dependencies,defect))
    end
    result
end

# Convert a nonnegative exact bound upward, including underflow/overflow.
function _upper(x::Q)
    x>=0 || throw(ArgumentError("nonnegative bound required"))
    f=Float64(x)
    isinf(f) && return f
    _q(f)<x ? nextfloat(f) : f
end
_pair(r,i)=(;real=_upper(r),imag=_upper(i))
function _target(target,label)
    v=target isa Real ? target : get(target,label,nothing)
    v isa Real && !(v isa Bool) && isfinite(v) && v>=0 ||
        throw(ArgumentError("a finite nonnegative scalar target is required for retained row $label"))
    _q(v)
end

"""Evaluate a certificate at a finite native vector without solving.

The observed bound uses exact normalized retained-row residuals. An optional
scalar target (one number or a label-to-target dictionary) supplies a separate
conditional bound. It is never inferred from solver settings. Both bounds use
the supplied state's component magnitudes for the coefficient-defect term;
they are not uniform over a feasible set. Float64 bounds are rounded upward.
"""
function evaluate(cert,y;retained_scalar_target=nothing)
    length(y)==cert.coordinate_count || throw(ArgumentError("native coordinate count mismatch"))
    all(isfinite,y) || throw(ArgumentError("finite native state required"))
    if retained_scalar_target isa Real
        _target(retained_scalar_target,"all") # Also validate for dependency-free rows.
    elseif retained_scalar_target!==nothing && !(retained_scalar_target isa AbstractDict)
        throw(ArgumentError("scalar target must be a number or label-to-target dictionary"))
    end
    yq=CQ[_q(v) for v in y];s=cert.scale
    er=zero(Q);ei=zero(Q)
    for (k,a) in cert.defect
        er+=abs(real(a))*abs(real(yq[k]))+abs(imag(a))*abs(imag(yq[k]))
        ei+=abs(imag(a))*abs(real(yq[k]))+abs(real(a))*abs(imag(yq[k]))
    end
    inherited_r=zero(Q);inherited_i=zero(Q);conditional=zero(Q)
    signed=zero(CQ);dependencies=NamedTuple[];targets_met=true
    for d in cert.dependencies
        eta=_dot(d.row,yq)/d.divisor
        contribution=d.coefficient*eta;signed+=contribution
        inherited_r+=abs(real(contribution));inherited_i+=abs(imag(contribution))
        target=retained_scalar_target===nothing ? nothing : _target(retained_scalar_target,d.label)
        target===nothing || (conditional+=abs(d.coefficient)*target)
        target===nothing || (targets_met &= max(abs(real(eta)),abs(imag(eta)))<=target)
        push!(dependencies,(;d.label,normalized_coefficient_exact=string(d.coefficient),
            observed_normalized_components=_pair(abs(real(eta)),abs(imag(eta))),
            scalar_target=target===nothing ? nothing : _upper(target)))
    end
    physical=s*_dot(cert.row,yq);defect_value=_dot(cert.defect,yq)
    identity=_dot(cert.row,yq)==signed+defect_value
    br=s*(inherited_r+er);bi=s*(inherited_i+ei)
    enclosed=abs(real(physical))<=br && abs(imag(physical))<=bi
    (;label=cert.label,unit=cert.unit,reason=cert.reason,method=cert.method,
        dependencies,defect_support=length(cert.defect),exact_zero_defect=isempty(cert.defect),
        exact_identity_verified=identity,exact_enclosure_verified=enclosed,
        retained_targets_satisfied=retained_scalar_target===nothing ? nothing : targets_met,
        physical_components_SI=_pair(abs(real(physical)),abs(imag(physical))),
        inherited_components_SI=_pair(s*inherited_r,s*inherited_i),
        defect_components_bound_SI=_pair(s*er,s*ei),
        observed_components_bound_SI=_pair(br,bi),
        # The complex 1-norm bounds the Euclidean modulus without a rounded sqrt.
        observed_modulus_bound_SI=_upper(br+bi),
        conditional_components_bound_SI=retained_scalar_target===nothing ? nothing : _pair(s*(conditional+er),s*(conditional+ei)),
        conditional_modulus_bound_SI=retained_scalar_target===nothing ? nothing : _upper(s*(2conditional+er+ei)))
end
end
