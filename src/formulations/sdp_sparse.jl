# A chordal partial Gram matrix. Every electrical equation's support is covered
# by a clique and eliminated locally. PSD completion then implies A*W=0 globally.
struct SDPSparseMoment
    dimension::Int
    cliques::Vector{Vector{Int}}
    grams::Vector{Any}
    parents::Vector{Int}
    entries::Dict{Tuple{Int,Int},Any}
end
Base.size(H::SDPSparseMoment)=(H.dimension,H.dimension)
Base.size(H::SDPSparseMoment,k::Int)=k<=2 ? H.dimension : 1
function Base.getindex(H::SDPSparseMoment,i::Int,j::Int)
    haskey(H.entries,(i,j)) || throw(ArgumentError("voltage product is outside the SDP clique cover; declare its VoltageLNC in SDPOptions before building"))
    H.entries[(i,j)]
end

function _sdp_psd(model,m,cone)
    if haskey(model.ext,:soc_policy)
        H=@variable(model,[1:m,1:m] in HermitianMatrixSpace())
        _soc_block!(model,H)
        return H
    end
    m==0 && return zeros(ComplexF64,0,0)
    if m==1
        x=@variable(model,lower_bound=0)
        return reshape([x+0im],1,1)
    elseif m==2
        a=@variable(model);b=@variable(model);c=@variable(model);d=@variable(model)
        @constraint(model,[a,b,sqrt(2)*c,sqrt(2)*d] in RotatedSecondOrderCone())
        return [a+0im c+im*d;c-im*d b+0im]
    elseif cone==:hermitian
        return @variable(model,[1:m,1:m] in HermitianPSDCone())
    end
    X=@variable(model,[1:2m,1:2m],PSD)
    haskey(model.ext,:ac_audit) && push!(model.ext[:ac_audit].real_embeddings,X)
    [(X[i,j]+X[m+i,m+j]+im*(X[m+i,j]-X[i,m+j]))/2 for i in 1:m,j in 1:m]
end

function _sdp_basis(A,kind)
    if kind in (:sparse,:auto)
        F=qr(sparse(A));r=rank(F);n=size(A,2);m=n-r
        kind==:auto && m<=32 && return _sdp_basis(A,:physical)
        R=F.R
        coefficients=UpperTriangular(Matrix{ComplexF64}(R[1:r,1:r])) \ Matrix{ComplexF64}(-R[1:r,r+1:n])
        N=zeros(ComplexF64,n,m)
        N[F.pcol,:]=[coefficients;Matrix{ComplexF64}(I,m,m)]
        return N
    end
    N=nullspace(A)
    if kind==:physical && size(N,2)>0
        pivots=qr(Matrix{ComplexF64}(N'),ColumnNorm()).p[1:size(N,2)]
        N=N/N[pivots,:]
        N[pivots,:]=Matrix{ComplexF64}(I,length(pivots),length(pivots))
    end
    N
end

function _sdp_cliques(n,supports)
    graph=[Set{Int}() for _ in 1:n]
    for support in supports, i in support,j in support
        i==j || push!(graph[i],j)
    end
    active=trues(n);bags=Vector{Int}[]
    for _ in 1:n
        candidates=findall(active)
        i=candidates[argmin([length(graph[k]) for k in candidates])]
        neighbors=sort!(collect(graph[i]));push!(bags,sort!([i;neighbors]))
        for j in neighbors,k in neighbors;j==k || push!(graph[j],k);end
        for j in neighbors;delete!(graph[j],i);end
        active[i]=false;empty!(graph[i])
    end
    # Retain maximal cliques, deterministically.
    order=sortperm(bags;by=b->(-length(b),Tuple(b)))
    maximal=Vector{Int}[]
    for k in order
        any(all(in(c),bags[k]) for c in maximal) || push!(maximal,bags[k])
    end
    # Maximum-weight clique tree has the running-intersection property.
    selected=[1];remaining=Set(2:length(maximal));parents=[0]
    while !isempty(remaining)
        best=(-1,0,0)
        for k in sort!(collect(remaining)), (position,j) in enumerate(selected)
            weight=length(intersect(maximal[k],maximal[j]))
            weight>best[1] && (best=(weight,k,position))
        end
        push!(selected,best[2]);push!(parents,best[3]);delete!(remaining,best[2])
    end
    maximal[selected],parents
end

# Amalgamate adjacent tree bags. This adds fill products, preserves running
# intersection and PSD-completion equivalence, and avoids hundreds of tiny cones.
function _sdp_merge_cliques(cliques,parents,limit)
    bags=copy(cliques);neighbors=[Set{Int}() for _ in bags];active=trues(length(bags))
    for (i,p) in enumerate(parents)
        p==0 && continue
        push!(neighbors[i],p);push!(neighbors[p],i)
    end
    while true
        best=(limit+1,0,0)
        for i in findall(active),j in neighbors[i]
            i<j || continue
            size=length(union(bags[i],bags[j]))
            size<best[1] && (best=(size,i,j))
        end
        best[2]==0 && break
        _,i,j=best;bags[i]=sort!(union(bags[i],bags[j]))
        for k in neighbors[j]
            delete!(neighbors[k],j)
            if k!=i;push!(neighbors[k],i);push!(neighbors[i],k);end
        end
        delete!(neighbors[i],j);empty!(neighbors[j]);active[j]=false
    end
    order=[first(findall(active))];outparents=[0];visited=Set(order)
    for i in order
        for j in sort!(collect(neighbors[i]))
            j in visited && continue
            push!(visited,j);push!(order,j);push!(outparents,findfirst(==(i),order))
        end
    end
    bags[order],outparents
end

function _sdp_sparse_moment(model,A,supports,options,diagnostics)
    N=_sdp_basis(A,options.basis);m=size(N,2)
    diagnostics[:basis]=options.basis==:auto ? (m<=32 ? :physical : :sparse) : options.basis
    n=size(A,2)
    if options.decomposition==:auto && m<=32
        diagnostics[:decomposition]=:dense
        diagnostics[:electrical_residual]=norm(A*N,Inf);diagnostics[:reduced_dimension]=m
        return _sdp_psd(model,m,options.cone),N
    end
    diagnostics[:decomposition]=:chordal
    cliques,parents=_sdp_cliques(n,supports)
    diagnostics[:unmerged_cliques]=length(cliques)
    cliques,parents=_sdp_merge_cliques(cliques,parents,options.clique_size)
    selections=Vector{Int}[]
    for clique in cliques
        C=N[clique,:];singular=svdvals(C)
        r=count(>(maximum(size(C))*eps(Float64)*maximum(singular;init=0.0)),singular)
        push!(selections,clique[qr(Matrix{ComplexF64}(C'),ColumnNorm()).p[1:r]])
    end
    if any(length(c)==m for c in selections)
        diagnostics[:decomposition]=:dense
        diagnostics[:electrical_residual]=norm(A*N,Inf)
        diagnostics[:reduced_dimension]=m
        return _sdp_psd(model,m,options.cone),N
    end
    consistency=options.consistency==:auto ? (m<=32 ? :shared : :local) : options.consistency
    diagnostics[:consistency]=consistency
    if consistency==:local
        return _sdp_local_cliques(model,A,N,cliques,parents,selections,options,diagnostics),Matrix{ComplexF64}(I,n,n)
    end
    # One shared reduced Hermitian matrix gives overlap consistency by
    # construction. Only clique restrictions must be PSD. PSD completion gives
    # an equivalent global feasible moment, possibly with different free entries.
    H=@variable(model,[1:m,1:m] in HermitianMatrixSpace())
    function entry(i,j)
        out=JuMP.GenericAffExpr{ComplexF64,JuMP.VariableRef}(0im)
        for a in 1:m,b in 1:m
            c=N[i,a]*conj(N[j,b])
            iszero(c) || JuMP.add_to_expression!(out,c,H[a,b])
        end
        out
    end
    entries=Dict{Tuple{Int,Int},Any}();grams=Any[]
    for (clique,selected) in zip(cliques,selections)
        for i in clique,j in clique
            get!(entries,(i,j)) do;entry(i,j);end
        end
        push!(grams,[entries[(i,j)] for i in clique,j in clique])
        r=length(selected)
        C=[entries[(i,j)] for i in selected,j in selected]
        if haskey(model.ext,:soc_policy)
            _soc_block!(model,C)
        elseif r==1
            @constraint(model,real(C[1,1])>=0)
        elseif r==2
            @constraint(model,[real(C[1,1]),real(C[2,2]),sqrt(2)*real(C[1,2]),sqrt(2)*imag(C[1,2])] in RotatedSecondOrderCone())
        elseif r>2
            @constraint(model,Symmetric([real.(C) -imag.(C);imag.(C) real.(C)]) in PSDCone())
        end
    end
    diagnostics[:clique_orders]=length.(selections);diagnostics[:cliques]=length(cliques)
    diagnostics[:electrical_residual]=norm(A*N,Inf)
    diagnostics[:reduced_dimension]=m
    SDPSparseMoment(n,cliques,grams,parents,entries),Matrix{ComplexF64}(I,n,n)
end

function _sdp_local_cliques(model,A,N,cliques,parents,selections,options,diagnostics)
    grams=Any[];entries=Dict{Tuple{Int,Int},Any}();projection_residual=0.0
    for (index,(clique,selected)) in enumerate(zip(cliques,selections))
        r=length(selected)
        T=r==0 ? zeros(ComplexF64,length(clique),0) : N[clique,:]/N[selected,:]
        for (k,i) in enumerate(selected)
            T[findfirst(==(i),clique),:]=[j==k ? 1.0 : 0.0 for j in 1:r]
        end
        projection_residual=max(projection_residual,norm(N[clique,:]-T*N[selected,:],Inf)/max(norm(N[clique,:],Inf),eps()))
        # A neutral voltage behind a large grounding admittance can be 1e-12
        # of a phase voltage. Normalize local coordinates BEFORE imposing PSD.
        scales=[norm(N[i,:]) for i in selected]
        T=T*Diagonal(scales)
        H=_sdp_psd(model,r,options.cone)
        function entry(i,j)
            out=JuMP.GenericAffExpr{ComplexF64,JuMP.VariableRef}(0im)
            for a in 1:r,b in 1:r
                c=T[i,a]*conj(T[j,b]);iszero(c) || JuMP.add_to_expression!(out,c,H[a,b])
            end
            out
        end
        G=[entry(i,j) for i in eachindex(clique),j in eachindex(clique)]
        push!(grams,G)
        if parents[index]!=0
            shared=intersect(clique,cliques[parents[index]])
            if !isempty(shared)
                C=N[shared,:];singular=svdvals(C)
                rank=count(>(maximum(size(C))*eps(Float64)*maximum(singular;init=0.0)),singular)
                shared=shared[qr(Matrix{ComplexF64}(C'),ColumnNorm()).p[1:rank]]
            end
            # Independent separator coordinates suffice: every other separator
            # coordinate is already an electrical linear combination of these.
            for (ki,i) in enumerate(shared),j in shared[ki:end]
                f=(G[findfirst(==(i),clique),findfirst(==(j),clique)]-entries[(i,j)])/(norm(N[i,:])*norm(N[j,:]))
                @constraint(model,real(f)==0)
                i==j || @constraint(model,imag(f)==0)
            end
        end
        for (i,gi) in enumerate(clique),(j,gj) in enumerate(clique)
            get!(entries,(gi,gj),G[i,j])
        end
    end
    diagnostics[:clique_orders]=length.(selections);diagnostics[:cliques]=length(cliques)
    diagnostics[:clique_basis_residual]=projection_residual
    diagnostics[:electrical_residual]=norm(A*N,Inf);diagnostics[:reduced_dimension]=size(N,2)
    SDPSparseMoment(size(A,2),cliques,grams,parents,entries)
end

# The partial matrix is sufficient for optimization. Completion is needed only
# to report a voltage candidate. A pseudoinverse handles singular separators;
# this numerical completion is not an AC or PSD feasibility certificate.
function _sdp_moment_value(H::SDPSparseMoment)
    W=zeros(ComplexF64,size(H));seen=Int[]
    for (clique,gram) in zip(H.cliques,H.grams)
        G=ComplexF64.(JuMP.value.(gram));shared=intersect(clique,seen);fresh=setdiff(clique,seen)
        if !isempty(shared) && !isempty(fresh)
            ri=findall(in(fresh),clique);si=findall(in(shared),clique)
            W[fresh,seen]=G[ri,si]*pinv(Hermitian(W[shared,shared]);rtol=sqrt(eps(Float64)))*W[shared,seen]
            W[seen,fresh]=W[fresh,seen]'
        end
        W[fresh,fresh]=G[findall(in(fresh),clique),findall(in(fresh),clique)]
        # Retain directly constrained entries for each newly introduced variable.
        if !isempty(shared)
            W[fresh,shared]=G[findall(in(fresh),clique),findall(in(shared),clique)]
            W[shared,fresh]=W[fresh,shared]'
        end
        append!(seen,fresh)
    end
    W
end
Base.Broadcast.broadcasted(::typeof(JuMP.value),H::SDPSparseMoment)=_sdp_moment_value(H)
function _lnc_lift(H::SDPSparseMoment,N,a,b)
    sum((c*conj(d)*H[i,j] for (i,c) in a for (j,d) in b);init=JuMP.AffExpr(0.0)+0im)
end
