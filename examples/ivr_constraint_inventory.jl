"""Reconcile recorded IVRNLP declarations with the current emitted JuMP rows."""
module IVRConstraintInventory
using FormulationLab, JuMP
include("ivr_circuit_residual_trace.jl")
include("ivr_nonlinear_residual_trace.jl")
const C=IVRCircuitResidualTrace
const N=IVRNonlinearResidualTrace

"""Return live references and declaration multiplicity, including omitted rows.

Completeness means every current emitted constraint has recorded provenance.
It does not prove input-schema completeness, physical feasibility or equivalence.
Missing/stale provenance throws; unrecorded added constraints report incomplete.
"""
function catalog(build)
    model=build.model;e=build.electrical
    for key in (:ivr_circuit_rows,:ivr_source_fixes,:ivr_lifting)
        haskey(model.ext,key) || throw(ArgumentError("missing inventory provenance: $key"))
    end
    circuit=C.catalog(build);nonlinear=N.catalog(build)
    isempty(circuit.unclassified_equations) || throw(ArgumentError("unclassified circuit equations"))
    emitted=model.ext[:ivr_circuit_rows];fixes=model.ext[:ivr_source_fixes]
    expected=Set{Any}((:equation,k) for k in eachindex(e.equations))
    union!(expected,((:kcl,k) for k in keys(e.kcl)))
    Set(keys(emitted))==expected || throw(ArgumentError("incomplete circuit emission provenance"))
    Set(keys(fixes))==Set(keys(e.fixed_source_coordinates)) || throw(ArgumentError("incomplete source-fix provenance"))
    declarations=Any[];owners=Dict{Any,Vector{String}}()
    function checkrow(ref,expected,label)
        is_valid(model,ref) || throw(ArgumentError("stale or foreign constraint reference: $label"))
        actual=constraint_object(ref)
        actual.set==expected.set && isequal_canonical(actual.func,expected.func) ||
            throw(ArgumentError("changed emitted circuit row: $label"))
    end
    function add(label,category,refs;status=:emitted,metadata=nothing)
        length(unique(refs))==length(refs) || throw(ArgumentError("duplicate reference within $label"))
        for ref in refs
            is_valid(model,ref) || throw(ArgumentError("stale or foreign constraint reference: $label"))
            push!(get!(owners,ref,String[]),label)
        end
        push!(declarations,(;label,category,status,constraints=collect(refs),metadata))
    end
    for q in circuit.rows
        identity=(q.kind,q.kind==:equation ? q.index : q.key);r=emitted[identity]
        original=q.kind==:equation ? e.equations[q.index] : e.kcl[q.key]
        r.row==original || throw(ArgumentError("changed circuit provenance: $(q.label)"))
        retained=r.status==:retained
        retained==q.retained_constraint || throw(ArgumentError("inconsistent circuit omission: $(q.label)"))
        if retained
            length(r.constraints)==2 && r.divisor isa Real && isfinite(r.divisor) && r.divisor>0 ||
                throw(ArgumentError("invalid circuit emission: $(q.label)"))
            expression=FormulationLab._linivr_eval(original,build.state)/r.divisor
            checkrow(r.constraints[1],@build_constraint(real(expression)==0),q.label)
            checkrow(r.constraints[2],@build_constraint(imag(expression)==0),q.label)
        else
            isempty(r.constraints) && r.divisor===nothing || throw(ArgumentError("omitted circuit row has emitted references"))
        end
        add(q.label,:circuit,r.constraints;status=q.reason,metadata=(;q...,divisor=r.divisor))
    end
    for k in sort!(collect(keys(fixes)))
        q=fixes[k];j,a=only(build.coordinates.reconstruction[k])
        q.coordinate==k && q.native_coordinate==j && q.coefficient==a && q.value==e.fixed_source_coordinates[k] ||
            throw(ArgumentError("changed source-fix provenance"))
        vars=(build.coordinates.real_variables[j],build.coordinates.imaginary_variables[j])
        all(is_fixed,vars) && q.constraints==(FixRef(vars[1]),FixRef(vars[2])) ||
            throw(ArgumentError("changed source coordinate fixes"))
        fix_value(vars[1])==real(q.value/a) && fix_value(vars[2])==imag(q.value/a) ||
            throw(ArgumentError("changed source coordinate values"))
        add("source_coordinate/$k",:source_fix,q.constraints;metadata=q)
    end
    for (category,rows) in ((:load_law,nonlinear.loads),(:bus_limit,nonlinear.bounds),
            (:equipment_limit,nonlinear.equipment),(:dispatch,nonlinear.dispatch),
            (:generator_definition,nonlinear.definitions),(:ibr_limit,nonlinear.ibr))
        for q in rows
            refs=hasproperty(q,:constraints) ? q.constraints : (q.constraint,)
            label=category==:bus_limit ? "bus/$(q.b)/$(q.key)/$(q.channel)" : q.label
            add(label,category,refs;status=isempty(refs) ? :no_emitted_row : :emitted,metadata=q)
        end
    end
    # P and Q share this domain and definition: one auxiliary declaration per channel.
    for q in nonlinear.loads
        q.quantity==:p || continue
        q.voltage_definition===nothing || add("load/$(q.id)/voltage_definition/$(q.channel)",
            :load_voltage_definition,(q.voltage_definition,);metadata=q)
        x=q.voltage_coordinate
        x isa VariableRef || continue
        for (suffix,present,ref) in (("lower",has_lower_bound(x),LowerBoundRef),
                                    ("upper",has_upper_bound(x),UpperBoundRef))
            present && add("load/$(q.id)/voltage_domain/$suffix/$(q.channel)",:auxiliary_domain,(ref(x),);metadata=q)
        end
    end
    for (k,q) in enumerate(model.ext[:ivr_lifting].records)
        add("lifting/$k/$(q.kind)",:lifting_definition,(q.definition_real,q.definition_imag);metadata=q)
    end
    allrefs=all_constraints(model;include_variable_in_set_constraints=true)
    uncovered=[ref for ref in allrefs if !haskey(owners,ref)]
    (;declarations,owners,uncovered_constraints=uncovered,
        emitted_constraint_count=length(allrefs),covered_constraint_count=length(owners),
        complete_emitted_coverage=isempty(uncovered),complete_input_coverage=false)
end

"""JSON-compatible inventory; references are local identifiers, never solver results."""
function report(build)
    c=catalog(build)
    refs=all_constraints(build.model;include_variable_in_set_constraints=true)
    ids=Dict(ref=>k for (k,ref) in enumerate(refs))
    declarations=[(;q.label,q.category,q.status,constraint_ids=[ids[r] for r in q.constraints]) for q in c.declarations]
    (;schema="FormulationLab.constraint_inventory.v1",c.emitted_constraint_count,c.covered_constraint_count,
        c.complete_emitted_coverage,c.complete_input_coverage,declarations,
        shared_constraints=[(;constraint_id=ids[r],declarations=labels) for (r,labels) in
            sort!(collect(c.owners);by=p->ids[first(p)]) if length(labels)>1],
        uncovered_constraint_ids=[ids[r] for r in c.uncovered_constraints])
end
end
