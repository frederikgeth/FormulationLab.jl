"""
    ivr_nlp_point_report(build::IVRNLPBuild, point::ACPoint; atol=1e-7)

Encode supplied SI phasors directly, then evaluate the built NLP without solving
or repairing the point. Required voltage/current channels must be present. Line
series currents are derived from supplied endpoint currents and endpoint shunts;
the opposite endpoint is independently checked as a binding. Projection onto a
reduced representation is accepted only when reconstruction matches the supplied
state. Also use `physical_residuals` for independent original-network physics.
Transformer coil and conductive-bond currents are bound directly; ideal
winding-ground currents are derived from supplied terminal currents after those
channels and voltages are bound. Bond observations are required when present in
the circuit; no arbitrary split between bond and ideal-earth currents is chosen.
IBR coil currents are derived from supplied internal filter currents and voltages;
the PCC current channels are then checked independently.
Closed-switch through currents bind directly from `:switch_from`; the opposite
endpoint and both open-switch zero-current channels are checked independently.
Voltage-dependent load auxiliaries are calculated from supplied coil voltages;
zero-voltage inputs reject before evaluating fractional or negative powers.

Residuals for coordinate/channel bindings are per unit; constraint residuals use
the built model's normalization. Grounded source-current allocations remain
unobserved, as in the full IVR contract. No optimizer is needed.
"""
function ivr_nlp_point_report(build::IVRNLPBuild,point::ACPoint;atol=1e-7)
    isfinite(atol) && atol>=0 || throw(ArgumentError("atol must be finite and nonnegative"))
    e=build.electrical;z=fill(ComplexF64(NaN),e.coordinate_count[])
    missing=String[];binding=0.0
    voltage(b,t)=get(point.voltage,(b,t),ComplexF64(NaN))
    function current(f,id,n)
        key=(f,id)
        if !haskey(point.currents,key)
            push!(missing,"current/$f/$id");return fill(ComplexF64(NaN),n)
        end
        length(point.currents[key])==n || throw(DimensionMismatch("current/$f/$id"))
        point.currents[key]
    end
    for (key,k) in e.voltage
        haskey(point.voltage,key) || push!(missing,"voltage/$(key[1])/$(key[2])")
        v=get(point.voltage,key,ComplexF64(NaN))/e.vb
        k==0 ? (binding=max(binding,abs(v))) : (z[k]=v)
    end
    for l in e.lnc_lines
        cf=current(:line_from,l.id,length(l.tmf))
        vf=[voltage(l.from,t) for t in l.tmf]
        series=(cf-l.Yf*vf)/e.ib
        for (row,value) in zip(l.current,series)
            z[only(keys(row))]=value
        end
    end
    for (f,id,_,rows,_) in e.devices
        f in (:load,:generator,:voltage_source,:switch_from,:transformer_coil_from,:transformer_coil_to,:transformer_coil,:transformer_bond) || continue
        values=current(f,id,length(rows))/e.ib
        for (row,value) in zip(rows,values)
            isempty(row) && continue # Grounded source or open-switch current.
            z[only(keys(row))]=value
        end
    end
    # Winding terminal currents reveal any ideal-ground branch current after
    # the supplied coil/bond currents and voltages have been bound.
    # IBR internal currents similarly reveal coil currents once voltages are bound.
    # Solve only a single remaining coordinate, without a least-squares fit or
    # changes to observed channels. All terminal bindings are checked below.
    for (f,id,_,rows,_) in e.devices
        f in (:transformer_from,:transformer_to,:transformer_winding,:ibr_internal) || continue
        observed=current(f,id,length(rows))/e.ib
        for (row,value) in zip(rows,observed)
            unknown=[k for k in keys(row) if !isfinite(z[k])]
            length(unknown)==1 || continue
            k=only(unknown)
            z[k]=(value-sum((a*z[j] for (j,a) in row if j!=k);init=0im))/row[k]
        end
    end
    y=[_linivr_eval(row,z) for row in build.coordinates.projection]
    reconstructed=[_linivr_eval(row,y) for row in build.coordinates.reconstruction]
    reconstruction=maximum(abs,reconstructed-z;init=0.0)
    for (f,id,_,rows,_) in e.devices
        observed=current(f,id,length(rows))/e.ib
        for (row,value) in zip(rows,observed)
            f==:voltage_source && isempty(row) && continue
            binding=max(binding,abs(_linivr_eval(row,reconstructed)-value))
        end
    end
    finite=all(isfinite,z)&&all(isfinite,y)&&isfinite(binding)&&isfinite(reconstruction)
    supplied=Dict{JuMP.VariableRef,Float64}()
    violation=Inf;objective=NaN
    if finite && isempty(missing)
        for k in eachindex(y)
            supplied[build.coordinates.real_variables[k]]=real(y[k])
            supplied[build.coordinates.imaginary_variables[k]]=imag(y[k])
        end
        # Dispatch variables are uniquely determined by the supplied physical
        # voltage/current products, even when their boxes are fixed or absent.
        for (id,refs) in build.generator_variables
            power=build.powers[(:generator,id)]
            for k in eachindex(power)
                s=JuMP.value(v->supplied[v],power[k])
                supplied[refs.p[k]]=real(s)*(e.sb/refs.power_base)
                supplied[refs.q[k]]=imag(s)*(e.sb/refs.power_base)
            end
        end
        # Voltage-law auxiliaries are physical magnitudes, never fitted values.
        domain=true
        for refs in values(build.load_voltage_variables),ref in refs
            x=abs2(_linivr_eval(ref.row,reconstructed))*ref.scale
            supplied[ref.variable]=x;domain &= isfinite(x) && x>0
        end
        for ref in build.model.ext[:ivr_lifting].records
            value=JuMP.value(v->supplied[v],ref.expression)
            supplied[ref.real]=real(value);supplied[ref.imag]=imag(value)
        end
        if domain
            residuals=JuMP.primal_feasibility_report(build.model,supplied;atol=0.0)
            violation=maximum(values(residuals);init=0.0)
            objective=JuMP.value(v->supplied[v],JuMP.objective_function(build.model))*_ivrn_objective_scale(build.options)
        end
    end
    volts=Dict(key=>(k==0 ? 0im : reconstructed[k]*e.vb) for (key,k) in e.voltage)
    amps=Dict((f,id)=>ComplexF64[_linivr_eval(row,reconstructed)*e.ib for row in rows]
              for (f,id,_,rows,_) in e.devices)
    (;passed=finite&&isempty(missing)&&max(binding,reconstruction,violation)<=atol,
      max_binding_residual_pu=finite ? binding : Inf,
      max_reconstruction_residual_pu=finite ? reconstruction : Inf,
      max_constraint_violation=violation,objective,missing_channels=unique(missing),
      unobserved_grounded_source_currents=build.numerical_diagnostics[:unobserved_grounded_source_currents],
      derived_series_currents=[l.id for l in e.lnc_lines],
      reconstructed_point=ACPoint(voltage=volts,currents=amps),variable_values=supplied,tolerance=atol)
end
