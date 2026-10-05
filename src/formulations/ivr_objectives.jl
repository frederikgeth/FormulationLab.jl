"""One affine/quadratic term in an exact-IVR physical power objective.

For `quantity=:p` (W) or `:q` (var), let `x` be the weighted sum of the
one-based `(family, id, channel)` entries in `channels`. The term contributes
`linear*(x-target) + quadratic*(x-target)^2`. Weights default to one.
Coefficients and targets refer to SI power, independently of all per-unit bases.
Negative linear coefficients support export rewards and curtailment penalties.
Quadratic coefficients must be nonnegative; this does not make the AC OPF convex.
Use with `IVRNLP(objective=:power, power_terms=[...])`. No legacy cost is added.
"""
Base.@kwdef struct IVRPowerTerm
    channels::Vector{Tuple{Symbol,String,Int}}
    quantity::Symbol = :p
    weights::Vector{Float64} = ones(length(channels))
    target::Float64 = 0.0
    linear::Float64 = 0.0
    quadratic::Float64 = 0.0
end

function _ivrn_check_power_terms(options)
    terms=options.power_terms
    options.objective==:power ? !isempty(terms) || throw(ArgumentError("power objective requires terms")) :
        isempty(terms) || throw(ArgumentError("power_terms requires objective=:power"))
    for t in terms
        t.quantity in (:p,:q) || throw(ArgumentError("power quantity must be :p or :q"))
        !isempty(t.channels) && length(t.channels)==length(t.weights) ||
            throw(ArgumentError("power term requires equally sized nonempty channels and weights"))
        all(isfinite,t.weights) && all(isfinite,(t.target,t.linear,t.quadratic)) ||
            throw(ArgumentError("power objective data must be finite"))
        t.quadratic>=0 || throw(ArgumentError("power quadratic coefficient must be nonnegative"))
    end
end

# Assemble only selected channels. Generator terms use the existing explicit
# dispatch variables. Other terms reuse the exact bound-power lifting policy;
# without lifting a squared power expression is generally quartic in phasors.
function _ivrn_power_objective(model,terms,e,z,generators)
    devices=Dict((f,id)=>(v,i) for (f,id,v,i,_) in e.devices)
    selected=Dict{Tuple{Symbol,String,Int},Any}()
    objective=0.0
    for term in terms
        x=0.0
        for ((family,id,k),weight) in zip(term.channels,term.weights)
            haskey(devices,(family,id)) || throw(ArgumentError("unknown objective power channel $family/$id"))
            v,i=devices[(family,id)]
            1<=k<=length(v) || throw(ArgumentError("objective power channel index out of range: $family/$id/$k"))
            s=get!(selected,(family,id,k)) do
                family==:generator ? (generators[id].power_base/e.sb)*(generators[id].p[k]+im*generators[id].q[k]) :
                    _ivrn_bound_power(model,v[k],i[k],z)
            end
            x += weight*e.sb*(term.quantity==:p ? real(s) : imag(s))
        end
        residual=x-term.target
        iszero(term.linear) || (objective += term.linear*residual)
        iszero(term.quadratic) || (objective += term.quadratic*residual^2)
    end
    objective
end
