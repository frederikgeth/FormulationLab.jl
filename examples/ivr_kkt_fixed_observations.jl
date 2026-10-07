"""Exact paired variable/equality elimination in a retained symmetric KKT system.

This is an offline linear-system control, not a capture of a substituted NLP.
Pairs require a multiplier row coupled only to its associated primal variable,
with zero multiplier regularization. RHS reduction and recovery use 256-bit
accumulation and explicitly round their outputs to Float64.
"""
module IVRKKTFirstOrderElimination
using LinearAlgebra, SparseArrays
include("ivr_kkt_factor.jl")
const F=IVRKKTOfflineFactor

function control(data,pairs)
    z=F.input(data)
    u=Int[first(p) for p in pairs];y=Int[last(p) for p in pairs]
    all(k->1<=k<=z.n,vcat(u,y)) && length(unique(vcat(u,y)))==2length(pairs) ||
        throw(ArgumentError("pairs must contain distinct valid indices"))
    lower=sparse(Int.(z.i),Int.(z.j),z.a,z.n,z.n)
    K=lower+transpose(lower)-spdiagm(0=>diag(lower))
    d=[K[y[k],u[k]] for k in eachindex(u)]
    all(x->isfinite(x)&&!iszero(x),d) || throw(ArgumentError("nonzero pair coefficient required"))
    for k in eachindex(y)
        rows,values=findnz(K[:,y[k]])
        all(t->iszero(values[t]) || rows[t]==u[k],eachindex(rows)) ||
            throw(ArgumentError("multiplier row has regularization or additional coupling"))
    end
    removed=Set(vcat(u,y));keep=[k for k in 1:z.n if !(k in removed)]
    isempty(keep) && throw(ArgumentError("empty retained system"))
    map=zeros(Int,z.n);map[keep]=eachindex(keep)
    mask=[k for k in eachindex(z.a) if map[z.i[k]]!=0 && map[z.j[k]]!=0]
    reduced=Dict{String,Any}("dimension"=>length(keep),"rows"=>map[z.i[mask]],
        "columns"=>map[z.j[mask]],"values"=>z.a[mask],
        "coordinate_map"=>z.t[keep],"rhs"=>z.b[keep])
    result=(;n=z.n,u,y,d,keep,E=K[keep,u],A=K[u,u],reduced)
    reduced["rhs"]=reduce_rhs(result,z.b)
    result
end

function check_rhs(c,b)
    length(b)==c.n && all(isfinite,b) || throw(ArgumentError("invalid full RHS"))
end

"""Return b_keep - E D^-1 b_y; never discard a nonzero defining-row RHS."""
function reduce_rhs(c,b)
    check_rhs(c,b)
    setprecision(BigFloat,256) do
        qu=BigFloat.(b[c.y])./BigFloat.(c.d)
        reduced=Float64.(BigFloat.(b[c.keep])-BigFloat.(c.E)*qu)
        all(isfinite,reduced) || throw(ArgumentError("nonfinite reduced RHS"))
        reduced
    end
end

"""Recover eliminated primal and multiplier directions in original row order."""
function recover(c,qr,b)
    check_rhs(c,b)
    length(qr)==length(c.keep) && all(isfinite,qr) || throw(ArgumentError("invalid reduced direction"))
    setprecision(BigFloat,256) do
        d=BigFloat.(c.d);qu=BigFloat.(b[c.y])./d
        qy=(BigFloat.(b[c.u])-transpose(BigFloat.(c.E))*BigFloat.(qr)-BigFloat.(c.A)*qu)./d
        q=zeros(Float64,c.n);q[c.keep]=qr;q[c.u]=Float64.(qu);q[c.y]=Float64.(qy)
        all(isfinite,q) || throw(ArgumentError("nonfinite recovered direction"))
        q
    end
end
end
