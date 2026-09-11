"""An externally supplied AC state in SI units. Currents follow the named physical
channels in the formulation (`:line_from`, `:load`, `:transformer_coil_from`, etc.).
Supplying a point does not assert physical feasibility. Missing observations are
reported; hidden electrical coordinates may be reconstructed by linear algebra.
"""
Base.@kwdef struct ACPoint
    voltage::Dict{Tuple{String,String},ComplexF64}
    currents::Dict{Tuple{Symbol,String},Vector{ComplexF64}}=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
end

# This is an encoding check, deliberately separate from physical validation.
# Linear least squares only: no optimizer, no projection accepted silently.
function _audit_linear(rows,targets,n)
    isempty(rows) && return zeros(ComplexF64,n),0.0
    A=zeros(ComplexF64,length(rows),n)
    for (j,row) in enumerate(rows),(i,c) in row;A[j,i]=c;end
    b=ComplexF64.(targets)
    for j in axes(A,1)
        scale=max(norm(A[j,:]),1.0);A[j,:]./=scale;b[j]/=scale
    end
    x=pinv(A)*b
    x,maximum(abs,A*x-b;init=0.0)
end

function _audit_affine_point(model,bindings)
    vars=JuMP.all_variables(model);indices=Dict(v=>i for (i,v) in enumerate(vars))
    rows=Dict{Int,ComplexF64}[];targets=ComplexF64[]
    function add(f,y)
        f=convert(JuMP.AffExpr,f)
        push!(rows,Dict(indices[v]=>ComplexF64(c) for (v,c) in f.terms if !iszero(c)))
        push!(targets,ComplexF64(y-f.constant))
    end
    for (f,y) in bindings;add(real(f),real(y));add(imag(f),imag(y));end
    x,residual=_audit_linear(rows,targets,length(vars))
    Dict(v=>real(x[i]) for (i,v) in enumerate(vars)),residual
end

"""Check whether an externally supplied AC state survives the compiled relaxation.
Requires `audit=true` at construction. Uses linear algebra and evaluates every
JuMP constraint without optimizing or changing the model. Binding residuals are
reported separately: a least-squares reconstruction is never accepted silently.
This does not independently certify that the supplied state solves the AC laws.
"""
function containment_report(build::SDPBuild,point::ACPoint)
    model=build.model
    haskey(model.ext,:ac_audit) || throw(ArgumentError("build with audit=true"))
    audit=model.ext[:ac_audit];vb=build.voltage_base;ib=build.options.s_base/vb
    z,state_error,missing,used=_audit_reconstruct(build,point)
    bindings=Tuple{Any,Any}[]
    H=build.moment
    if H isa SDPSparseMoment
        for (C,G) in zip(H.cliques,H.grams),i in eachindex(C),j in 1:i
            push!(bindings,(G[i,j],z[C[i]]*conj(z[C[j]])))
        end
    else
        y=build.nullspace\z
        for i in eachindex(y),j in 1:i;push!(bindings,(H[i,j],y[i]*conj(y[j])));end
    end
    # Canonical real embedding eliminates its otherwise free anti-linear part.
    # This selects [Re(H) -Im(H); Im(H) Re(H)], which is PSD for rank-one H.
    for X in audit.real_embeddings
        m=size(X,1)÷2
        for i in 1:m,j in 1:m
            push!(bindings,(X[i,j]-X[m+i,m+j],0.0))
            push!(bindings,(X[i,m+j]+X[m+i,j],0.0))
        end
    end
    values,_=_audit_affine_point(model,bindings)
    for (x,t,a) in audit.envelopes
        value=JuMP.value(v->values[v],x)
        value>=0 || throw(ArgumentError("negative squared voltage in supplied state"))
        push!(bindings,(t,value^a))
    end
    # Auxiliary SOC coordinates are fixed by their affine defining equations.
    for (F,S) in JuMP.list_of_constraint_types(model)
        if S==JuMP.MOI.EqualTo{Float64}
            for ref in JuMP.all_constraints(model,F,S)
                c=JuMP.constraint_object(ref);push!(bindings,(c.func,c.set.value))
            end
        elseif S==JuMP.MOI.Zeros
            for ref in JuMP.all_constraints(model,F,S)
                c=JuMP.constraint_object(ref)
                for f in c.func;push!(bindings,(f,0.0));end
            end
        end
    end
    values,binding_error=_audit_affine_point(model,bindings)
    raw=JuMP.primal_feasibility_report(model,values;atol=0.0)
    raw_max=maximum(Base.values(raw);init=0.0)
    violations=copy(raw)
    # MOI's default RSOC distance is an upper bound formed by changing one
    # diagonal only. Near a zero diagonal it can exaggerate 1e-16 roundoff into
    # order-one violations. Use the orthogonal SOC rotation and true L2 distance.
    for (F,S) in JuMP.list_of_constraint_types(model)
        S==JuMP.MOI.RotatedSecondOrderCone || continue
        for ref in JuMP.all_constraints(model,F,S)
            c=JuMP.constraint_object(ref);x=JuMP.value(v->values[v],c.func)
            y=[(x[1]+x[2])/sqrt(2),(x[1]-x[2])/sqrt(2),x[3:end]...]
            distance=JuMP.MOI.Utilities.distance_to_set(y,JuMP.MOI.SecondOrderCone(length(y)))
            distance>0 ? (violations[ref]=distance) : delete!(violations,ref)
        end
    end
    bound_error=0.0
    for entry in bound_report(build).entries
        magnitude=abs(sum((c*z[k] for (k,c) in entry.map);init=0im))
        bound_error=max(bound_error,entry.lower_pu-magnitude,magnitude-entry.upper_pu)
    end
    (;state_residual_pu=state_error,binding_residual=binding_error,max_bound_violation_pu=bound_error,
      max_constraint_violation=maximum(Base.values(violations);init=0.0),
      raw_moi_distance_upper_bound=raw_max,missing_voltage=missing,observed_current_channels=length(used),
      unobserved_current_channels=[(f,id) for (f,id,_,_,_) in audit.devices if !((f,id) in used)],
      violations,values,state=z,physical_feasibility_certified=false)
end
containment_report(build::SOCBuild,point::ACPoint)=containment_report(build.electrical,point)

function _audit_reconstruct(build,point)
    audit=build.model.ext[:ac_audit];vb=build.voltage_base;ib=build.options.s_base/vb
    n=size(audit.equations,2)
    rows=[Dict(k=>c for (k,c) in enumerate(row) if !iszero(c)) for row in eachrow(audit.equations)]
    targets=zeros(ComplexF64,length(rows));missing=String[];ground_error=0.0
    for (key,idx) in sort!(collect(audit.voltage);by=first)
        if !haskey(point.voltage,key);push!(missing,"voltage/$key");continue;end
        value=point.voltage[key]/vb
        if idx==0;ground_error=max(ground_error,abs(value));continue;end
        push!(rows,Dict(idx=>1.0+0im));push!(targets,value)
    end
    used=Set{Tuple{Symbol,String}}()
    for (family,id,v,i,d) in audit.devices
        key=(family,id)
        haskey(point.currents,key) || continue
        length(point.currents[key])==length(i) || throw(ArgumentError("current arity mismatch for $key"))
        push!(used,key)
        for (row,value) in zip(i,point.currents[key]);push!(rows,row);push!(targets,value/ib);end
    end
    unknown=setdiff(Set(keys(point.currents)),used)
    isempty(unknown) || throw(ArgumentError("unknown current channels: $unknown"))
    z,state_error=_audit_linear(rows,targets,n)
    state_error=max(state_error,ground_error)
    z,state_error,missing,used
end

"""Reconstruct unobserved electrical currents by linear equations and supplied
observations, without an optimizer. Keeps all supplied observations unchanged.
Returns the completed point, reconstruction residual and inferred channel names;
inferred currents are not independent reference measurements.
"""
function complete_ac_point(build::SDPBuild,point::ACPoint)
    haskey(build.model.ext,:ac_audit) || throw(ArgumentError("build with audit=true"))
    z,residual,missing,used=_audit_reconstruct(build,point)
    isempty(missing) || throw(ArgumentError("missing voltage observations: $missing"))
    audit=build.model.ext[:ac_audit];ib=build.options.s_base/build.voltage_base
    currents=copy(point.currents);inferred=Tuple{Symbol,String}[]
    for (f,id,v,i,d) in audit.devices
        key=(f,id);haskey(currents,key) && continue
        currents[key]=ComplexF64[sum((c*z[k] for (k,c) in row);init=0im)*ib for row in i]
        push!(inferred,key)
    end
    (;point=ACPoint(;voltage=copy(point.voltage),currents),state_residual_pu=residual,inferred_channels=inferred)
end
complete_ac_point(build::SOCBuild,point::ACPoint)=complete_ac_point(build.electrical,point)
