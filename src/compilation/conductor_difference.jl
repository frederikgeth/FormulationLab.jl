# Internal algebraic building blocks. These maps do not certify that a network
# has zero common-mode current: a topology/device certificate must precede use.
struct _ConductorDifference
    voltage::Matrix{Float64}
    current_projection::Matrix{Float64}
end

function _conductor_difference(kind::Symbol)
    P = if kind==:two_wire
        [1.0 -1.0]
    elseif kind==:three_wire
        [1.0 -1.0 0.0; 0.0 1.0 -1.0]
    elseif kind==:four_wire
        [1.0 0.0 0.0 -1.0; 0.0 1.0 0.0 -1.0; 0.0 0.0 1.0 -1.0]
    else
        throw(ArgumentError("unknown conductor-difference rule: $kind"))
    end
    _ConductorDifference(P,(P*transpose(P))\P)
end

function _difference_line(map::_ConductorDifference,Z::AbstractMatrix)
    P=map.voltage;m=size(P,2)
    size(Z)==(m,m) || throw(DimensionMismatch("impedance must match conductor count"))
    all(isfinite,Z) || throw(ArgumentError("impedance must be finite"))
    # Retain the coefficients needed for common-mode recovery and diagnostics.
    (; impedance=P*Z*transpose(P),
       common_drop=vec(sum(Z*transpose(P);dims=1)),
       differential_coupling=P*Z*ones(m), common_impedance=sum(Z))
end

function _difference_current(map::_ConductorDifference,i::AbstractVector;
                             atol=1e-12,rtol=1e-12)
    length(i)==size(map.voltage,2) || throw(DimensionMismatch("current conductor count"))
    all(isfinite,i) || throw(ArgumentError("current must be finite"))
    all(x->isfinite(x)&&x>=0,(atol,rtol)) || throw(ArgumentError("invalid tolerances"))
    abs(sum(i))<=atol+rtol*sum(abs,i) ||
        throw(ArgumentError("nonzero common-mode current cannot be discarded"))
    map.current_projection*i
end

function _difference_voltage(map::_ConductorDifference,u::AbstractVector,sigma::Number)
    length(u)==size(map.voltage,1) || throw(DimensionMismatch("voltage difference count"))
    all(isfinite,u) && isfinite(sigma) || throw(ArgumentError("voltage must be finite"))
    transpose(map.current_projection)*u .+ sigma/size(map.voltage,2)
end
