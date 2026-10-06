"""Read-only SI residual traces with explicit row provenance and omission status."""
module IVRCircuitResidualTrace
using FormulationLab, JuMP, LinearAlgebra
include("ivr_kcl_residual_trace.jl")
const F=FormulationLab
const K=IVRKCLResidualTrace

"""Catalogue only equations whose physical units follow recorded stamp provenance.

Current IVRNLP builds record every linear electrical row at assembly time.
The older partial catalogue remains a fallback; unclassified equations are
returned explicitly. A non-KCL row is not necessarily
a voltage equation: winding balances and impedance-load laws have ampere units.
The multiwinding record orders each coil's ampere balance before its leakage rows.
"""
function catalog(build)
    e=build.electrical;d=build.numerical_diagnostics
    linear=d[:linear_elimination_report];device=d[:device_elimination_report]
    selected=Set(values(linear.selected_series_lines));loads=Set(linear.impedance_loads)
    omitted_device=Set(device.equation_indices);known=Dict{Int,Any}()
    function add(index,label,unit,omission;multiplier=1.0)
        index in eachindex(e.equations) || throw(ArgumentError("invalid recorded circuit-row index"))
        haskey(known,index) && throw(ArgumentError("duplicate circuit-row provenance"))
        unit in (:A,:V) && isfinite(multiplier) && multiplier>0 || throw(ArgumentError("invalid physical row unit"))
        reason=isempty(e.equations[index]) ? :empty_row : omission
        known[index]=(;kind=:equation,index,key=nothing,label,unit,
            physical_scale=(unit==:A ? e.ib : e.vb)*multiplier,retained_constraint=reason==:retained,reason)
    end
    if hasproperty(e,:equation_metadata) && e.equation_metadata!==nothing
        records=e.equation_metadata
        length(records)==length(e.equations) && [q.index for q in records]==collect(eachindex(e.equations)) ||
            throw(ArgumentError("incomplete circuit equation provenance"))
        omitted_lines=Set(i for l in e.lnc_lines if l.id in selected for i in l.equation_indices)
        omitted_loads=Set(i for l in e.impedance_loads if l.id in loads for i in l.equation_indices)
        for q in records
            reason=q.index in omitted_device ? :device_elimination : q.index in omitted_lines ? :passive_elimination :
                q.index in omitted_loads ? :impedance_elimination : :retained
            add(q.index,q.label,q.unit,reason;multiplier=q.assembly_multiplier)
        end
    else
        # Retain the narrower catalogue for older builds and external toy data.
        for l in e.lnc_lines,(k,index) in enumerate(l.equation_indices)
            add(index,"line/$(l.id)/drop/$k",:V,l.id in selected ? :passive_elimination : :retained)
        end
        for tx in e.transformer_current_balances,(k,index) in enumerate(tx.equation_indices)
            add(index,"transformer/$(tx.id)/balance/$k",:A,index in omitted_device ? :device_elimination : :retained)
        end
        for tx in e.nwinding_current_blocks
            id=split(tx.id,'/';limit=2)[2];n=length(build.network["transformer"]["n_winding"][id]["windings"])
            length(tx.equation_indices)==length(tx.current) && length(tx.current)%n==0 ||
                throw(ArgumentError("incomplete multiwinding row provenance"))
            for (k,index) in enumerate(tx.equation_indices)
                coil=cld(k,n);winding=mod1(k,n);unit=winding==1 ? :A : :V
                label=winding==1 ? "transformer/$(tx.id)/balance/$coil" : "transformer/$(tx.id)/leakage/$winding/$coil"
                add(index,label,unit,index in omitted_device ? :device_elimination : :retained)
            end
        end
        for l in e.impedance_loads,(k,index) in enumerate(l.equation_indices)
            add(index,"load/$(l.id)/impedance/$k",:A,l.id in loads ? :impedance_elimination : :retained)
        end
    end
    specialized=get(d,:specialization_report,nothing)
    omitted=specialized!==nothing && hasproperty(specialized,:omitted_kcl) ? Set(specialized.omitted_kcl) : Set{Tuple{String,String}}()
    series=Set(linear.series_buses)
    rows=Any[known[k] for k in sort!(collect(keys(known)))]
    for key in sort!(collect(keys(e.kcl)))
        reason=isempty(e.kcl[key]) ? :empty_row : key in omitted ? :specialization :
            key[1] in series ? :passive_elimination : :retained
        push!(rows,(;kind=:kcl,index=nothing,key,label="kcl/$(key[1])/$(key[2])",unit=:A,
            physical_scale=e.ib,retained_constraint=reason==:retained,reason))
    end
    (;rows,unclassified_equations=sort!(collect(setdiff(eachindex(e.equations),keys(known)))))
end

"""Trace retained and implied rows at a fixed native state; never optimize or repair.

Only retained rows have a solver normalization divisor/gain/target. Those fields
are `nothing` for omitted rows, whose physical and arithmetic residuals are still
reported. High precision evaluates stored Float64 coefficients, not exact stamps.
Targets are SI reporting tolerances, not changes to solver acceptance settings.
"""
function trace(build;bits=256,atol_A=1e-6,atol_V=1e-6)
    bits isa Integer && !(bits isa Bool) && bits>=128 || throw(ArgumentError("at least 128 precision bits required"))
    all(x->isfinite(x) && x>0,(atol_A,atol_V)) || throw(ArgumentError("positive finite SI reporting targets required"))
    c=catalog(build);e=build.electrical;R=build.coordinates.reconstruction
    y=value.(build.coordinates.real_variables)+im*value.(build.coordinates.imaginary_variables)
    all(isfinite,y) || throw(ArgumentError("finite native state values required"))
    z=[K._dot(row,y) for row in R]
    rows=setprecision(BigFloat,bits) do
        yb=K._big.(y);zb=[K._bigdot(row,yb) for row in R]
        [let row=q.kind==:kcl ? e.kcl[q.key] : e.equations[q.index]
            composed=F._ivrn_compose_row(row,R);scale=q.physical_scale
            target=q.unit==:A ? atol_A : atol_V
            divisor=if q.retained_constraint
                d=build.numerical_diagnostics[:composed_row_normalization] ? F._ivrn_scaled_row_norm(row,build.coordinates) : norm(collect(values(row)))
                q.kind==:kcl ? F._ivrn_kcl_row_divisor(d,e.ib,get(build.numerical_diagnostics,:kcl_row_max_base,nothing)) : d
            else
                nothing
            end
            gain=divisor===nothing ? nothing : scale*divisor
            native=value(F._linivr_eval(row,build.state))
            normalized=divisor===nothing ? nothing : value(F._linivr_eval(row,build.state)/divisor)
            nested=K._dot(row,z);flat=K._dot(composed,y)
            big_nested=K._bigdot(row,zb);big_flat=K._bigdot(composed,yb)
            (;q...,divisor,gain_SI=gain,reporting_target_SI=target,
                sufficient_scalar_target=gain===nothing ? nothing : target/(sqrt(2)*gain),
                normalized_complex_residual=normalized===nothing ? nothing : abs(normalized),
                normalized_scalar_residual=normalized===nothing ? nothing : max(abs(real(normalized)),abs(imag(normalized))),
                native_residual_SI=abs(native)*scale,float_nested_SI=abs(nested)*scale,
                big_nested_SI=Float64(abs(big_nested)*BigFloat(scale)),
                float_composed_SI=abs(flat)*scale,big_composed_SI=Float64(abs(big_flat)*BigFloat(scale)),
                nested_roundoff_SI=Float64(abs(K._big(nested)-big_nested)*BigFloat(scale)),
                composition_roundoff_SI=Float64(abs(big_flat-big_nested)*BigFloat(scale)),
                composed_evaluation_roundoff_SI=Float64(abs(K._big(flat)-big_flat)*BigFloat(scale)),
                original_support=length(row),composed_support=length(composed),precision_bits=bits)
        end for q in c.rows]
    end
    (;rows,unclassified_equations=c.unclassified_equations)
end
end
