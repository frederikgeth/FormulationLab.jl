"""Diagnostic Ipopt iterate capture; never eligible for performance rankings.

Requires Ipopt.jl 1.16.0 and its scalar MOI row layout. The returned arrays are
TNLP coordinates, not the internal slack-augmented/regularized KKT system.
"""
module IVRIterateCapture
using JuMP, Ipopt, LinearAlgebra, SparseArrays
const MOI = JuMP.MOI
const EXT = Base.get_extension(Ipopt, :IpoptMathOptInterfaceExt)

function supported(model)
    pkgversion(Ipopt) == v"1.16.0" || throw(ArgumentError("Ipopt.jl 1.16.0 required"))
    opt = unsafe_backend(model)
    opt isa Ipopt.Optimizer || throw(ArgumentError("Ipopt optimizer required"))
    opt
end

function snapshot(prob, scaled)
    x=zeros(prob.n); z_L=similar(x); z_U=similar(x)
    g=zeros(prob.m); lambda=similar(g)
    Ipopt.GetIpoptCurrentIterate(prob,scaled,prob.n,x,z_L,z_U,prob.m,g,lambda)
    all(a->all(isfinite,a),(x,z_L,z_U,g,lambda)) || error("nonfinite iterate")
    (;x,z_L,z_U,g,lambda)
end

"""Attach before solving. Capture both Ipopt-scaled and unscaled TNLP arrays.

No model evaluation is performed inside the callback. Errors stop the solve and
are reported by `finish`; an existing callback is never silently replaced.
"""
function attach!(model)
    # The caching optimizer is populated by optimize!, so check its backend then.
    pkgversion(Ipopt)==v"1.16.0" || throw(ArgumentError("Ipopt.jl 1.16.0 required"))
    records=Any[]; errors=String[]
    # Attach the optimizer before checking whether it already has a callback.
    if backend(model) isa MOI.Utilities.CachingOptimizer &&
       MOI.Utilities.state(backend(model))==MOI.Utilities.EMPTY_OPTIMIZER
        MOI.Utilities.attach_optimizer(backend(model))
    end
    opt=supported(model)
    opt.callback===nothing || throw(ArgumentError("existing callback would be overwritten"))
    function callback(mode,iteration,objective,inf_pr,inf_du,mu,d_norm,regularization,alpha_du,alpha_pr,ls_trials)
        try
            mode==0 || error("restoration iterates unsupported")
            iteration==length(records) || error("nonconsecutive callback iterations")
            unscaled=snapshot(opt.inner,false); scaled=snapshot(opt.inner,true)
            push!(records,(;iteration=Int(iteration),mode=Int(mode),objective,inf_pr,inf_du,
                mu,d_norm,regularization,alpha_du,alpha_pr,ls_trials=Int(ls_trials),unscaled,scaled))
            return true
        catch err
            push!(errors,sprint(showerror,err)); return false
        end
    end
    MOI.set(model,Ipopt.CallbackFunction(),callback)
    (;records,errors)
end

"""Check complete callback coverage and expose the actual solver row order.

Variable-domain bounds are separate from g/lambda. Fixed variables remain in the
TNLP arrays even if Ipopt removes them internally. Scalar constraints only; an
unmapped row (including an opaque legacy NLPBlock) causes a refusal.
"""
function finish(model,trace)
    isempty(trace.errors) || error(join(trace.errors,"; "))
    opt=supported(model); prob=opt.inner
    isempty(trace.records) && error("no callback states")
    length(trace.records)==MOI.get(opt,MOI.BarrierIterations())+1 || error("incomplete iterate coverage")
    columns=Vector{Any}(undef,prob.n); rows=Vector{Any}(undef,prob.m)
    column_seen=Set{Int}(); row_seen=Set{Int}(); domains=Any[]
    for v in all_variables(model)
        j=Ipopt.column(optimizer_index(v))
        j in column_seen && error("duplicate column")
        push!(column_seen,j); columns[j]=(;column=j,name=name(v),jump_index=index(v).value)
    end
    for c in all_constraints(model;include_variable_in_set_constraints=true)
        obj=constraint_object(c)
        if obj.func isa VariableRef
            push!(domains,(;column=Ipopt.column(optimizer_index(obj.func)),set=string(obj.set)))
        else
            i=EXT.row(opt,optimizer_index(c))
            i isa Int || error("non-scalar row")
            i in row_seen && error("duplicate row")
            push!(row_seen,i)
            rows[i]=(;row=i,name=name(c),jump_index=index(c).value,
                function_type=string(typeof(obj.func)),set=string(obj.set))
        end
    end
    column_seen==Set(1:prob.n) && row_seen==Set(1:prob.m) || error("incomplete solver layout")
    last=trace.records[end].unscaled
    gap=maximum(abs.(last.x-prob.x);init=0.)
    gap<=1e-10 || error("callback endpoint differs from solver endpoint")
    (;schema="FormulationLab.ipopt_iterates.v1",ipopt_jl_version=string(pkgversion(Ipopt)),
      solver_version=MOI.get(opt,MOI.SolverVersion()),timing_eligible=false,
      columns,rows,variable_domains=domains,records=trace.records,endpoint_max_gap=gap,
      conventions="Arrays follow the original TNLP order. Unscaled means model units, not SI. "*
      "Ipopt lambda uses grad(f)+J'lambda-z_L+z_U. Scaled arrays include Ipopt scaling. "*
      "Callback mu/regularization describe the callback stage; the following solve can update them. "*
      "No internal inequality slacks, KKT matrix, pivot permutation or refinement RHS is captured.")
end

"""Evaluate exact model derivatives after solving, at a retained unscaled state.

H is the lower-triangular Hessian of f + lambda'g, with objective factor one.
It excludes barrier and regularization terms and is not Ipopt's internal KKT.
Do not mutate the model between capture and evaluation.
"""
function derivatives(model,record)
    objective_sense(model)==MOI.MIN_SENSE || throw(ArgumentError("minimization objective required"))
    opt=supported(model); p=record.unscaled; n=opt.inner.n; m=opt.inner.m
    length(p.x)==n && length(p.lambda)==m || throw(ArgumentError("state dimensions differ"))
    g=zeros(m); grad=zeros(n)
    MOI.eval_constraint(opt,g,p.x); MOI.eval_objective_gradient(opt,grad,p.x)
    objective=MOI.eval_objective(opt,p.x)
    relative(a,b)=maximum(abs.(a.-b)./max.(1.,abs.(a),abs.(b));init=0.)
    value_gap=relative(g,p.g); objective_gap=abs(objective-record.objective)/max(1.,abs(objective),abs(record.objective))
    max(value_gap,objective_gap)<=1e-10 || error("re-evaluated state differs from callback")
    js=MOI.jacobian_structure(opt); hs=MOI.hessian_lagrangian_structure(opt)
    jv=zeros(length(js)); hv=zeros(length(hs))
    MOI.eval_constraint_jacobian(opt,jv,p.x)
    MOI.eval_hessian_lagrangian(opt,hv,p.x,1.,p.lambda)
    all(a->all(isfinite,a),(g,grad,jv,hv)) || error("nonfinite derivative")
    jr=first.(js); jc=last.(js)
    # MOI quadratic and nonlinear blocks can use opposite triangles and repeat
    # positions. Canonicalize each contribution; sparse consumers must sum them.
    hr=[max(i,j) for (i,j) in hs]; hc=[min(i,j) for (i,j) in hs]
    J=sparse(jr,jc,jv,m,n)
    stationarity=grad+J'*p.lambda-p.z_L+p.z_U
    (;iteration=record.iteration,objective_factor=1.,objective,value_gap,objective_gap,
      gradient=grad,jacobian=(;rows=jr,columns=jc,values=jv,shape=(m,n)),
      hessian=(;rows=hr,columns=hc,values=hv,shape=(n,n),triangle="lower",duplicates="sum"),
      stationarity_max=norm(stationarity,Inf),timing_eligible=false)
end
end
