"""Matched-state Jacobian diagnostics for regional current-unit changes only.

No optimizer is called. Supply the optional NLPDiagnostics module to `evaluate`.
Matrices include explicit variable-domain rows, unlike Ipopt's internal KKT.
"""
module IVRMatchedJacobian
using FormulationLab, JuMP, LinearAlgebra, SparseArrays
const MOI=JuMP.MOI
same_option(x,y)=isequal(x,y)
same_option(x::Vector{IVRPowerTerm},y::Vector{IVRPowerTerm})=isequal(
    [Tuple(getfield(t,k) for k in fieldnames(IVRPowerTerm)) for t in x],
    [Tuple(getfield(t,k) for k in fieldnames(IVRPowerTerm)) for t in y])
sourcekey(s)=(s.index,s.function_type,s.set_type)
function refkey(ref)
    idx=index(ref);F,S=typeof(idx).parameters
    (idx.value,string(F),string(S))
end

"""Construct the predicted x_reference = D*x_candidate and row scaling maps.

Only current_power_bases may differ. Row scales include composed circuit-row
normalization and variable-domain rows. All other physical/power units stay fixed.
The mapping requires unchanged variable order, row identities and lifting records.
Use `compare` to check values and derivatives at a supplied point; this is not a
global identity proof for arbitrary post-build mutations.
"""
function maps(a,b)
    isequal(a.network,b.network) || throw(ArgumentError("physical inputs differ"))
    all(k==:current_power_bases || same_option(getfield(a.options,k),getfield(b.options,k))
        for k in fieldnames(IVRNLPOptions)) || throw(ArgumentError("only current power units may differ"))
    av=all_variables(a.model);bv=all_variables(b.model)
    name.(av)==name.(bv) && length(unique(name.(av)))==length(av) || throw(ArgumentError("variable identities differ or are ambiguous"))
    column=ones(length(av));positions=Dict(v=>j for (j,v) in enumerate(av))
    length(a.coordinates.projection)==length(b.coordinates.projection) || throw(ArgumentError("coordinate dimensions differ"))
    for (j,(x,y)) in enumerate(zip(a.coordinates.projection,b.coordinates.projection))
        keys(x)==keys(y) && !isempty(x) || throw(ArgumentError("coordinate support differs"))
        k=minimum(keys(x));ratio=x[k]/y[k]
        isreal(ratio) && isfinite(ratio) && real(ratio)>0 || throw(ArgumentError("invalid coordinate ratio"))
        all(isapprox(x[k],ratio*y[k];rtol=1e-12,atol=0.) for k in keys(x)) || throw(ArgumentError("non-diagonal coordinate change"))
        for v in (a.coordinates.real_variables[j],a.coordinates.imaginary_variables[j]);column[positions[v]]=real(ratio);end
    end
    [q.key for q in a.model.ext[:ivr_lifting].records]==[q.key for q in b.model.ext[:ivr_lifting].records] ||
        throw(ArgumentError("lifting identities differ"))
    ar=Dict(refkey(r)=>r for r in all_constraints(a.model;include_variable_in_set_constraints=true))
    br=Dict(refkey(r)=>r for r in all_constraints(b.model;include_variable_in_set_constraints=true))
    keys(ar)==keys(br) || throw(ArgumentError("constraint identities differ"))
    row=Dict(k=>1. for k in keys(ar));groups=Dict(k=>"other" for k in keys(ar))
    aa=a.model.ext[:ivr_circuit_rows];bb=b.model.ext[:ivr_circuit_rows]
    keys(aa)==keys(bb) || throw(ArgumentError("circuit identities differ"))
    labels=Dict(q.index=>q.label for q in a.electrical.equation_metadata)
    for k in keys(aa)
        x,y=aa[k],bb[k]
        x.status==y.status && x.row==y.row && refkey.(x.constraints)==refkey.(y.constraints) || throw(ArgumentError("circuit structure differs"))
        x.status==:retained || continue
        for ref in x.constraints
            key=refkey(ref);row[key]=x.divisor/y.divisor
            groups[key]=first(k)==:kcl ? "kcl" : startswith(labels[k[2]],"transformer/") ? "transformer" : "other_circuit"
        end
    end
    for (k,ref) in ar
        obj=constraint_object(ref)
        if obj.func isa VariableRef
            row[k]=inv(column[positions[obj.func]]);groups[k]="variable_domain"
        end
        isfinite(row[k]) && row[k]>0 || throw(ArgumentError("invalid row scale"))
        s,t=obj.set,constraint_object(br[k]).set
        if s isa MOI.EqualTo
            isapprox(t.value,row[k]*s.value;rtol=1e-12,atol=1e-12) || throw(ArgumentError("fixed bound changed"))
        elseif s isa MOI.LessThan
            isapprox(t.upper,row[k]*s.upper;rtol=1e-12,atol=1e-12) || throw(ArgumentError("upper bound changed"))
        elseif s isa MOI.GreaterThan
            isapprox(t.lower,row[k]*s.lower;rtol=1e-12,atol=1e-12) || throw(ArgumentError("lower bound changed"))
        else
            throw(ArgumentError("unsupported constraint set"))
        end
    end
    (;column,row,groups)
end

function evaluate(build,point,D;require_feasible=true)
    enc=ivr_nlp_point_report(build,point)
    isempty(enc.missing_channels) && length(enc.variable_values)==num_variables(build.model) &&
        all(isfinite,values(enc.variable_values)) && max(enc.max_binding_residual_pu,enc.max_reconstruction_residual_pu)<=1e-10 ||
        throw(ArgumentError("physical point is not exactly representable"))
    require_feasible && !enc.passed && throw(ArgumentError("physical point fails model membership"))
    backend=JuMP.backend(build.model);vars=MOI.get(backend,MOI.ListOfVariableIndices())
    values_by_index=Dict(index(v)=>x for (v,x) in enc.variable_values);x=[values_by_index[v] for v in vars]
    point_record=D.evaluation_point(backend,x;label="shared physical point",
        provenance=D.EvaluationPointProvenance(D.TransportedPoint;source="IVR SI phasors",complete=true))
    ev=D.evaluate_numerical(backend,point_record)
    isempty(ev.failures) && all(m->m in (:exact_symbolic,:exact_constructed_nonlinear_ad),ev.jacobian_row_methods) ||
        throw(ArgumentError("exact derivatives unavailable"))
    all(s->s.kind==:constraint && s.subindex===nothing,ev.constraint_sources) || throw(ArgumentError("unsupported row source"))
    rows=sourcekey.(ev.constraint_sources);length(unique(rows))==length(rows) || throw(ArgumentError("duplicate row identities"))
    entries=ev.jacobian_entries
    J=sparse([e.row for e in entries],[e.column for e in entries],[e.value for e in entries],length(rows),length(vars))
    all(isfinite,nonzeros(J)) || throw(ArgumentError("nonfinite derivatives"))
    (;J,x,rows,values=Float64.(ev.constraint_values),objective=enc.objective,membership=enc.passed,
      methods=unique(ev.jacobian_row_methods),names=[MOI.get(backend,MOI.VariableName(),v) for v in vars])
end

relative_gap(a,b)=maximum(abs.(a.-b)./max.(1.,abs.(a),abs.(b));init=0.)
function compare(a,b,map)
    a.rows==b.rows && a.names==b.names || throw(ArgumentError("matrix identities differ"))
    length(map.column)==length(a.x) && Set(keys(map.row))==Set(a.rows) || throw(ArgumentError("incomplete scaling map"))
    r=[map.row[k] for k in a.rows];d=map.column
    all(x->isfinite(x)&&x>0,r) && all(x->isfinite(x)&&x>0,d) || throw(ArgumentError("invalid positive scaling map"))
    expected=spdiagm(0=>r)*a.J*spdiagm(0=>d)
    ii,jj,vv=findnz(b.J-expected)
    jacobian_error=maximum((abs(v)/max(1.,abs(b.J[i,j]),abs(expected[i,j])) for (i,j,v) in zip(ii,jj,vv));init=0.)
    point_error=relative_gap(a.x,d.*b.x);value_error=relative_gap(b.values,r.*a.values)
    objective_error=abs(a.objective-b.objective)/max(1.,abs(a.objective),abs(b.objective))
    (;passed=max(jacobian_error,point_error,value_error,objective_error)<=1e-10,
        jacobian_error,point_error,value_error,objective_error)
end
end
