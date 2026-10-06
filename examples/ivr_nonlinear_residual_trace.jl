"""Original load-law and bus-voltage residuals, with explicit partial coverage."""
module IVRNonlinearResidualTrace
using FormulationLab, JuMP
const F=FormulationLab

"""Catalogue original declarations and their emitted rows, without solving.

This deliberately covers load power laws and bus-voltage bounds only. Impedance
loads belong to the linear-circuit catalogue. Other constraints are enumerated
as outside this catalogue; they are not declared absent from the model.
"""
function catalog(build)
    e=build.electrical;model=build.model;loads=Any[];linear_loads=String[]
    law_rows=get(model.ext,:ivr_load_law_rows,Dict())
    for (family,id,v,i,_) in e.devices
        family==:load || continue
        d=build.network["load"][id];law=lowercase(get(d,"model","constant_power"))
        if F._sdp_is_impedance_load(d);push!(linear_loads,id);continue;end
        for k in eachindex(v)
            rec=if law=="constant_power"
                refs=build.load_constraints[id]
                s=F._ivrn_power(v[k],i[k],build.state)
                (;p=refs.p[k],q=refs.q[k],row_multiplier=1.,voltage_coordinate=nothing,
                    voltage_definition=nothing,voltage_nominal=nothing,voltage_bounds=nothing,
                    power_expressions=(p=real(s),q=imag(s)))
            else
                haskey(law_rows,(id,k)) || throw(ArgumentError("missing load-law provenance: $id/$k"))
                law_rows[(id,k)]
            end
            for quantity in (:p,:q)
                push!(loads,(;label="load/$id/$(quantity)/$k",id,channel=k,quantity,law,
                    unit=quantity==:p ? :W : :var,voltage_row=copy(v[k]),current_row=copy(i[k]),
                    constraint=getproperty(rec,quantity),physical_scale=e.sb/rec.row_multiplier,
                    rec.voltage_coordinate,rec.voltage_definition,rec.voltage_nominal,rec.voltage_bounds,
                    power_expression=getproperty(rec.power_expressions,quantity)))
            end
        end
    end
    sort!(loads;by=q->q.label)
    haskey(model.ext,:ivr_bus_limit_rows) || throw(ArgumentError("missing bus-bound provenance"))
    bounds=model.ext[:ivr_bus_limit_rows]
    all(q->q.form!=:unrecorded,bounds) || throw(ArgumentError("incomplete bus-bound provenance"))
    covered=Set{Any}(q.constraint for q in loads)
    for q in loads
        q.voltage_definition===nothing || push!(covered,q.voltage_definition)
        if q.voltage_coordinate isa VariableRef
            has_lower_bound(q.voltage_coordinate) && push!(covered,LowerBoundRef(q.voltage_coordinate))
            has_upper_bound(q.voltage_coordinate) && push!(covered,UpperBoundRef(q.voltage_coordinate))
        end
    end
    for q in bounds;union!(covered,q.constraints);end
    outside=[c for c in all_constraints(model;include_variable_in_set_constraints=true) if c ∉ covered]
    (;loads,bounds,linear_loads=sort!(linear_loads),outside_scope_constraints=outside,
        covered_constraint_count=length(covered),complete_model_coverage=false,
        scope=(:load_power_laws,:bus_voltage_bounds))
end

function _residual(c,evaluate)
    q=constraint_object(c);s=q.set;x=evaluate(q.func)
    if s isa JuMP.MOI.EqualTo
        r=x-s.value;return (;sense=:equality,signed_residual=r,violation=abs(r))
    elseif s isa JuMP.MOI.LessThan
        r=x-s.upper;return (;sense=:upper,signed_residual=r,violation=max(r,0.))
    elseif s isa JuMP.MOI.GreaterThan
        r=x-s.lower;return (;sense=:lower,signed_residual=r,violation=max(-r,0.))
    end
    throw(ArgumentError("unsupported scalar constraint set"))
end

function _factor(d,law,k,n,quantity,x)
    law=="constant_power" && return 1.
    isfinite(x) && x>=0 || throw(DomainError(x,"load voltage-square coordinate must be finite and nonnegative"))
    law=="constant_current" && return sqrt(x)
    if law=="zip"
        prefix=quantity==:p ? "alpha" : "beta"
        return F._sdp_vector(d,prefix*"_z",n)[k]*x+
            F._sdp_vector(d,prefix*"_i",n)[k]*sqrt(x)+F._sdp_vector(d,prefix*"_p",n)[k]
    elseif law=="exponential"
        a=F._sdp_vector(d,quantity==:p ? "gamma_p" : "gamma_q",n)[k]/2
        return a==0 ? 1. : a==1 ? x : x^a
    end
    throw(ArgumentError("unsupported load law $law"))
end

"""Evaluate native and original physical residuals at a finite native assignment.

No optimization, repair, tolerance relaxation or performance ranking. Physical
quantities use original voltage/current rows, bypassing observation and power
auxiliaries. Auxiliary gaps explain why a native law residual alone need not
bound the original SI law. These Float64 identities are diagnostics, not
interval bounds or uniform nonlinear residual certificates.
"""
function trace(build;variable_values=nothing)
    c=catalog(build);e=build.electrical
    values=variable_values===nothing ? Dict(v=>value(v) for v in all_variables(build.model)) : variable_values
    all(v->haskey(values,v) && isfinite(values[v]),all_variables(build.model)) ||
        throw(ArgumentError("complete finite native variable assignment required"))
    evaluate(x)=x isa Real ? Float64(x) : value(v->values[v],x)
    observe(row)=let u=F._linivr_eval(row,build.state)
        evaluate(real(u))+im*evaluate(imag(u))
    end
    loads=map(c.loads) do q
        d=build.network["load"][q.id];n=length(d["p_nom"]);k=q.channel
        u=e.vb*observe(q.voltage_row);i=e.ib*observe(q.current_row)
        actual=q.quantity==:p ? real(u*conj(i)) : imag(u*conj(i))
        nominal=e.values_for(d,q.quantity==:p ? "p_nom" : "q_nom",n)[k]
        xp=q.law=="constant_power" ? nothing : abs2(u/q.voltage_nominal)
        xm=q.voltage_coordinate===nothing ? nothing : evaluate(q.voltage_coordinate)
        requested=nominal*_factor(d,q.law,k,n,q.quantity,xp)
        modeled_request=nominal*_factor(d,q.law,k,n,q.quantity,xm)
        native=_residual(q.constraint,evaluate).signed_residual*q.physical_scale
        power_gap=e.sb*evaluate(q.power_expression)-actual
        demand_gap=modeled_request-requested
        physical=actual-requested
        all(isfinite,(actual,requested,modeled_request,native,power_gap,demand_gap,physical)) ||
            throw(DomainError(q.label,"nonfinite load-law evaluation"))
        (;q.label,q.id,q.channel,q.quantity,q.law,q.unit,q.physical_scale,
            electrical_power_SI=actual,requested_power_SI=requested,
            physical_residual_SI=physical,native_residual_SI=native,
            power_auxiliary_gap_SI=power_gap,demand_auxiliary_gap_SI=demand_gap,
            reconciliation_error_SI=physical-(native-power_gap+demand_gap),
            voltage_V=abs(u),modeled_voltage_V=xm===nothing ? nothing : q.voltage_nominal*sqrt(xm),
            voltage_definition=q.voltage_definition===nothing ? nothing : _residual(q.voltage_definition,evaluate),
            voltage_domain_V=q.voltage_bounds===nothing ? nothing :
                (lower=q.voltage_bounds.lower,upper=isfinite(q.voltage_bounds.upper) ? q.voltage_bounds.upper : nothing))
    end
    bounds=map(c.bounds) do q
        magnitude=e.vb*abs(observe(q.row))
        slack=q.relation==:lower ? magnitude-q.bound : q.bound-magnitude
        (;label="bus/$(q.b)/$(q.key)/$(q.channel)",bus=q.b,field=q.key,q.channel,q.relation,q.form,
            limit_V=q.bound,magnitude_V=magnitude,slack_V=slack,violation_V=max(-slack,0.),
            native=[_residual(ref,evaluate) for ref in q.constraints])
    end
    (;loads,bounds,c.linear_loads,c.scope,c.complete_model_coverage,c.covered_constraint_count,
        outside_scope_constraint_count=length(c.outside_scope_constraints),
        note="Partial provenance: load power laws and bus-voltage bounds. Native squared-magnitude residuals have no constant SI-voltage conversion. Float64 diagnostics, not a certificate.")
end

function trace(build,point::ACPoint)
    report=ivr_nlp_point_report(build,point)
    isempty(report.missing_channels) || throw(ArgumentError("physical point is missing channels"))
    trace(build;variable_values=report.variable_values)
end
end
