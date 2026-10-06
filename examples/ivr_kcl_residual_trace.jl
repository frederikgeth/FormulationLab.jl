"""Read-only KCL residual tracing on stored exact-IVR coordinate maps."""
module IVRKCLResidualTrace
using FormulationLab, JuMP, LinearAlgebra
const F=FormulationLab

_big(x)=Complex{BigFloat}(BigFloat(real(x)),BigFloat(imag(x)))
_dot(row,x)=sum((a*x[k] for (k,a) in row);init=0.0im)
_bigdot(row,x)=sum((_big(a)*x[k] for (k,a) in row);init=zero(Complex{BigFloat}))

"""Compare evaluations at fixed Float64 solver coordinates, without repairing them.

High precision evaluates the stored Float64 stamp/map coefficients, not an
exact physical model or a new optimum. The composed expression is the same
construction used for retained circuit rows. Omitted rows are identified from
specialization and passive-elimination reports and must not be mistaken for
independently enforced constraints. SI auditing remains independent of this
compiler-based trace. `atol_A` is a reporting target, never a solver setting.
"""
function trace(build;keys=sort!(collect(Base.keys(build.electrical.kcl))),bits=256,atol_A=1e-6)
    bits isa Integer && !(bits isa Bool) && bits>=128 || throw(ArgumentError("at least 128 precision bits required"))
    isfinite(atol_A) && atol_A>0 || throw(ArgumentError("positive finite SI reporting target required"))
    all(k->haskey(build.electrical.kcl,k),keys) || throw(ArgumentError("unknown KCL row"))
    y=value.(build.coordinates.real_variables)+im*value.(build.coordinates.imaginary_variables)
    all(isfinite,y) || throw(ArgumentError("finite native state values required"))
    R=build.coordinates.reconstruction;e=build.electrical
    z=[_dot(row,y) for row in R]
    specialized=get(build.numerical_diagnostics,:specialization_report,nothing)
    omitted=specialized!==nothing && hasproperty(specialized,:omitted_kcl) ? Set(specialized.omitted_kcl) : Set{Tuple{String,String}}()
    series=Set(build.numerical_diagnostics[:linear_elimination_report].series_buses)
    setprecision(BigFloat,bits) do
        yb=_big.(y);zb=[_bigdot(row,yb) for row in R]
        [let row=e.kcl[key],c=F._ivrn_compose_row(e.kcl[key],R)
            divisor=build.numerical_diagnostics[:composed_row_normalization] ?
                F._ivrn_scaled_row_norm(row,build.coordinates) : norm(collect(values(row)))
            retained=!(key in omitted || key[1] in series || isempty(row))
            cap=get(build.numerical_diagnostics,:kcl_row_max_base,nothing)
            retained && (divisor=F._ivrn_kcl_row_divisor(divisor,e.ib,cap))
            isempty(row) && (divisor=1.)
            native=isempty(row) ? 0im : value(F._linivr_eval(row,build.state)/divisor)
            nested=_dot(row,z);composed=_dot(c,y)
            big_nested=_bigdot(row,zb);big_composed=_bigdot(c,yb)
            gain=e.ib*divisor
            (;bus=key[1],terminal=key[2],retained_constraint=retained,
                divisor,gain_A=gain,complex_target=atol_A/gain,
                sufficient_scalar_target=atol_A/(sqrt(2)*gain),
                normalized_complex_residual=abs(native),normalized_scalar_residual=max(abs(real(native)),abs(imag(native))),
                native_residual_A=abs(native)*gain,float_nested_A=abs(nested)*e.ib,
                big_nested_A=Float64(abs(big_nested)*BigFloat(e.ib)),float_composed_A=abs(composed)*e.ib,
                big_composed_A=Float64(abs(big_composed)*BigFloat(e.ib)),
                nested_roundoff_A=Float64(abs(_big(nested)-big_nested)*BigFloat(e.ib)),
                composition_roundoff_A=Float64(abs(big_composed-big_nested)*BigFloat(e.ib)),
                composed_evaluation_roundoff_A=Float64(abs(_big(composed)-big_composed)*BigFloat(e.ib)),
                native_vs_nested_A=abs(native*divisor-nested)*e.ib,
                original_support=length(row),composed_support=length(c),precision_bits=bits)
        end for key in keys]
    end
end
end
