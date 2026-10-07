"""Retrospective rowwise diagnostics for retained, rounded KKT systems.

No solve, production tolerance or prior acceptance flag is changed. Absolute
allowances have reference KKT row units, not a physical SI feasibility meaning.
"""
module IVRKKTResiduals

function diagnose(data,q,b;transformed=false,dimensions,
        absolute_tolerances=(0.,1e-16,1e-14,1e-12,1e-10),relative_tolerance=1e-10,top=5)
    n=Int(data["dimension"]);i=Int.(data["rows"]);j=Int.(data["columns"])
    a=Float64.(data["values"]);t=Float64.(data["coordinate_map"])
    length(q)==length(b)==length(t)==n || error("vector dimensions differ")
    length(i)==length(j)==length(a) && length(Set(zip(i,j)))==length(a) || error("invalid canonical entries")
    all(k->1<=j[k]<=i[k]<=n,eachindex(a)) || error("invalid lower triangle")
    all(isfinite,a) && all(isfinite,q) && all(isfinite,b) && all(x->isfinite(x)&&x>0,t) || error("nonfinite inputs")
    length(dimensions)==4 && all(>=(0),dimensions) && sum(dimensions)==n || error("invalid blocks")
    all(x->isfinite(x)&&x>=0,absolute_tolerances) && !isempty(absolute_tolerances) || error("invalid absolute thresholds")
    isfinite(relative_tolerance) && relative_tolerance>0 && top>0 || error("invalid reporting options")
    # Match the original factor experiment's Float64 multiply order exactly.
    transformed && (a=a.*t[i].*t[j];b=Float64.(b).*t)
    all(isfinite,a) && all(isfinite,b) || error("nonfinite transformed data")
    setprecision(BigFloat,256) do
        aa=BigFloat.(a);qq=BigFloat.(q);bb=BigFloat.(b)
        weights=transformed ? BigFloat.(t) : ones(BigFloat,n)
        r=copy(bb);den=abs.(bb);anorm=zeros(BigFloat,n)
        for k in eachindex(aa)
            u=i[k];v=j[k];x=aa[k]
            r[u]-=x*qq[v];den[u]+=abs(x)*abs(qq[v]);anorm[u]+=abs(x)
            if u!=v;r[v]-=x*qq[u];den[v]+=abs(x)*abs(qq[u]);anorm[v]+=abs(x);end
        end
        residual=abs.(r);ratio(x,y)=y==0 ? (x==0 ? zero(x) : error("zero denominator")) : x/y
        eta=ratio.(residual,den)
        blocks=(:x,:slack,:equality,:inequality);limits=cumsum(collect(dimensions))
        block(k)=blocks[findfirst(>=(k),limits)]
        point(k;score=eta[k])=(;row=k,block=block(k),score=Float64(score),
            absolute_residual=Float64(residual[k]),denominator=Float64(den[k]),
            reference_absolute_residual=Float64(residual[k]/weights[k]),
            reference_denominator=Float64(den[k]/weights[k]),weight=Float64(weights[k]))
        function worst(values)
            [point(k;score=values[k]) for k in sortperm(values;rev=true)[1:min(top,n)]]
        end
        thresholds=[]
        for atol in absolute_tolerances
            ratios=ratio.(residual,BigFloat(atol).*weights.+BigFloat(relative_tolerance).*den)
            failing=findall(>(1),ratios)
            push!(thresholds,(;absolute_tolerance=atol,relative_tolerance,passed=isempty(failing),
                failing_rows=length(failing),failing_by_block=Dict(k=>count(v->block(v)==k,failing) for k in blocks),
                maximum_ratio=Float64(maximum(ratios)),worst=worst(ratios)))
        end
        normden=maximum(anorm)*maximum(abs,qq)+maximum(abs,bb)
        (;schema="FormulationLab.kkt_residual_diagnostics.v1",timing_eligible=false,
          backward_error=Float64(maximum(eta)),residual_max=Float64(maximum(residual)),
          normwise_backward_error=Float64(ratio(maximum(residual),normden)),
          strict_worst=worst(eta),absolute_worst=worst(residual./weights),thresholds)
    end
end
end
