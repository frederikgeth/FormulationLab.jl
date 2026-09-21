# A chordal partial Gram matrix. Every electrical equation's support is covered
# by a clique and eliminated locally. PSD completion then implies A*W=0 globally.
struct SDPSparseMoment
    dimension::Int
    cliques::Vector{Vector{Int}}
    grams::Vector{Any}
    parents::Vector{Int}
    entries::Dict{Tuple{Int,Int},Any}
end

# Lazy local congruence G = (T*H)*Tᴴ. Optimization only needs products declared
# by the support graph and separator constraints; materializing every affine
# entry can dominate construction even though numerical recovery eventually
# needs the full local Gram.
struct SDPLocalGram
    T::Matrix{ComplexF64}
    TH::Matrix{Any}
end
Base.size(G::SDPLocalGram)=(size(G.T,1),size(G.T,1))
Base.size(G::SDPLocalGram,k::Int)=k<=2 ? size(G.T,1) : 1
function Base.getindex(G::SDPLocalGram,i::Int,j::Int)
    sum((G.TH[i,a]*conj(G.T[j,a]) for a in axes(G.T,2)
         if !iszero(G.T[j,a]));init=0im)
end
function Base.Broadcast.broadcasted(::typeof(JuMP.value),G::SDPLocalGram)
    values=Matrix{ComplexF64}(undef,size(G.TH))
    for i in eachindex(values)
        values[i]=ComplexF64(JuMP.value(G.TH[i]))
    end
    values*G.T'
end
Base.size(H::SDPSparseMoment)=(H.dimension,H.dimension)
Base.size(H::SDPSparseMoment,k::Int)=k<=2 ? H.dimension : 1
function Base.getindex(H::SDPSparseMoment,i::Int,j::Int)
    haskey(H.entries,(i,j)) || throw(ArgumentError("voltage product is outside the SDP clique cover; declare its VoltageLNC in SDPOptions before building"))
    H.entries[(i,j)]
end

function _sdp_sorted_subset(a, b)
    ia = ib = 1
    while ia <= length(a) && ib <= length(b)
        if a[ia] == b[ib]
            ia += 1
            ib += 1
        elseif b[ib] < a[ia]
            ib += 1
        else
            return false
        end
    end
    ia > length(a)
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

function _sdp_basis(A,kind;diagnostics=nothing)
    if kind in (:sparse,:auto)
        F=qr(sparse(A));r=rank(F);n=size(A,2);m=n-r
        kind==:auto && m<=32 && return _sdp_basis(A,:physical_sparse;diagnostics)
        R=F.R
        coefficients=UpperTriangular(Matrix{ComplexF64}(R[1:r,1:r])) \ Matrix{ComplexF64}(-R[1:r,r+1:n])
        N=zeros(ComplexF64,n,m)
        N[F.pcol,:]=[coefficients;Matrix{ComplexF64}(I,m,m)]
        return N
    end
    N=nullspace(A)
    if kind in (:physical,:physical_sparse) && size(N,2)>0
        pivots=qr(Matrix{ComplexF64}(N'),ColumnNorm()).p[1:size(N,2)]
        N=N/N[pivots,:]
        N[pivots,:]=Matrix{ComplexF64}(I,length(pivots),length(pivots))
        kind==:physical_sparse && return _sdp_physical_sparse(A,pivots,N,diagnostics)
    end
    N
end

# With free physical coordinates fixed, disconnected components of the dependent
# column incidence graph cannot respond to free coordinates outside their rows.
# Solve only structurally present RHS columns. No magnitude threshold removes data.
function _sdp_physical_sparse(A,free,reference,diagnostics)
    n=size(A,2);m=length(free);dependent=setdiff(1:n,free)
    N=zeros(ComplexF64,n,m);N[free,:]=Matrix{ComplexF64}(I,m,m)
    B=sparse(A[:,dependent]);C=sparse(A[:,free])
    rowcols=[Int[] for _ in axes(A,1)]
    for j in axes(B,2), k in nzrange(B,j)
        iszero(nonzeros(B)[k]) || push!(rowcols[rowvals(B)[k]],j)
    end
    parent=collect(eachindex(dependent))
    function root(i)
        while parent[i]!=i
            parent[i]=parent[parent[i]];i=parent[i]
        end
        i
    end
    for js in rowcols
        isempty(js) && continue
        for j in js;parent[root(j)]=root(first(js));end
    end
    groups=Dict{Int,Vector{Int}}()
    for j in eachindex(dependent);push!(get!(groups,root(j),Int[]),j);end
    components=sort!(collect(values(groups));by=first)
    solved_columns=0
    for js in components
        rows=findall(r->!isempty(rowcols[r]) && root(first(rowcols[r]))==root(first(js)),axes(A,1))
        # A dependent component with no forcing is exactly zero in every basis column.
        rhs=findall(j->any(!iszero,C[rows,j]),1:m)
        isempty(rhs) && continue
        F=qr(B[rows,js])
        if rank(F)!=length(js)
            if diagnostics!==nothing
                diagnostics[:basis_structural_components]=length(components)
                diagnostics[:basis_fallback]=true
                diagnostics[:basis_fallback_reason]=:dependent_rank
            end
            return reference
        end
        N[dependent[js],rhs]=F \ Matrix(-C[rows,rhs])
        solved_columns+=length(rhs)
    end
    difference=norm(N-reference,Inf)/max(1.,norm(reference,Inf))
    residual=norm(A*N,Inf)/max(1.,norm(A,Inf)*norm(N,Inf))
    # Retain the original representation when floating-point solves disagree.
    fallback=!isfinite(difference) || !isfinite(residual) || difference>1e-8 || residual>1e-10
    if diagnostics!==nothing
        diagnostics[:basis_structural_components]=length(components)
        diagnostics[:basis_rhs_columns]=solved_columns
        diagnostics[:basis_map_difference]=difference
        diagnostics[:basis_relative_residual]=residual
        diagnostics[:basis_fallback]=fallback
        diagnostics[:basis_fallback_reason]=fallback ? :map_residual : :none
    end
    fallback ? reference : N
end

function _sdp_cliques(n,supports; ordering=:minimum_degree, diagnostics=nothing)
    ordering in (:minimum_degree,:minimum_fill) ||
        throw(ArgumentError("unknown chordal ordering"))
    graph=[Set{Int}() for _ in 1:n]
    for support in supports, i in support,j in support
        i==j || push!(graph[i],j)
    end
    original_edges=sum(length,graph) ÷ 2
    active=trues(n);bags=Vector{Int}[]
    fill_edges=0
    for _ in 1:n
        candidates=findall(active)
        function score(k)
            degree=length(graph[k])
            ordering==:minimum_degree && return (degree,degree,k)
            neighbors=collect(graph[k]);missing=0
            for a in eachindex(neighbors),b in a+1:length(neighbors)
                neighbors[b] in graph[neighbors[a]] || (missing+=1)
            end
            (missing,degree,k)
        end
        i=argmin(score,candidates)
        neighbors=sort!(collect(graph[i]));push!(bags,sort!([i;neighbors]))
        for a in eachindex(neighbors),b in a+1:length(neighbors)
            j,k=neighbors[a],neighbors[b]
            if !(k in graph[j])
                push!(graph[j],k);push!(graph[k],j);fill_edges+=1
            end
        end
        for j in neighbors;delete!(graph[j],i);end
        active[i]=false;empty!(graph[i])
    end
    # Retain maximal cliques, deterministically.
    # Compare the already sorted vectors directly. Materializing variable-length
    # tuples here gives the compiler a pathological `Tuple{Int,Vararg{Int}}`
    # ordering problem on large sparse feeders.
    function bag_order(i, j)
        a, b = bags[i], bags[j]
        length(a) == length(b) || return length(a) > length(b)
        for k in eachindex(a)
            a[k] == b[k] || return a[k] < b[k]
        end
        i < j
    end
    order=sortperm(eachindex(bags);lt=bag_order)
    maximal=Vector{Int}[]
    containing=[Int[] for _ in 1:n]
    for k in order
        bag=bags[k]
        pivot=argmin(i -> length(containing[i]),bag)
        any(j -> _sdp_sorted_subset(bag,maximal[j]),containing[pivot]) && continue
        push!(maximal,bag)
        index=length(maximal)
        for i in bag
            push!(containing[i],index)
        end
    end
    # Maximum-weight clique tree has the running-intersection property.
    # Prim's algorithm only updates cliques that share a vertex with the newly
    # selected clique. An inverted vertex-to-clique index avoids constructing
    # every pairwise intersection, which is prohibitive for wide feeders.
    memberships=[Int[] for _ in 1:n]
    for (k,clique) in enumerate(maximal), i in clique
        push!(memberships[i],k)
    end
    selected=[1];parents=[0];chosen=falses(length(maximal));chosen[1]=true
    best_weights=zeros(Int,length(maximal));best_parents=ones(Int,length(maximal))
    counts=zeros(Int,length(maximal));touched=Int[];overlap_updates=0
    function update_weights!(clique,position)
        empty!(touched)
        for i in clique, k in memberships[i]
            chosen[k] && continue
            iszero(counts[k]) && push!(touched,k)
            counts[k]+=1
        end
        for k in touched
            if counts[k]>best_weights[k]
                best_weights[k]=counts[k]
                best_parents[k]=position
            end
            counts[k]=0
        end
        overlap_updates+=length(touched)
    end
    update_weights!(maximal[1],1)
    for _ in 2:length(maximal)
        best_weight=-1;best=0
        for k in eachindex(maximal)
            if !chosen[k] && best_weights[k]>best_weight
                best_weight=best_weights[k];best=k
            end
        end
        push!(selected,best);push!(parents,best_parents[best]);chosen[best]=true
        update_weights!(maximal[best],length(selected))
    end
    out=maximal[selected]
    if diagnostics!==nothing
        diagnostics[:chordal_ordering]=ordering
        diagnostics[:aggregate_sparsity_edges]=original_edges
        diagnostics[:chordal_fill_edges]=fill_edges
        diagnostics[:unmerged_maximal_cliques]=length(out)
        diagnostics[:unmerged_max_clique_order]=maximum(length,out;init=0)
        diagnostics[:clique_tree_overlap_updates]=overlap_updates
    end
    out,parents
end

# PSD-completion representation for a partial Hermitian matrix. The aggregate
# support graph is chordally extended, each maximal-clique principal submatrix
# is PSD, and a clique tree supplies only the independent separator equalities.
function _sdp_chordal_psd(model,n,supports,cone;
                          ordering=:minimum_degree,clique_size=32,
                          diagnostics=Dict{Symbol,Any}())
    cliques,parents=_sdp_cliques(n,supports;ordering,diagnostics)
    diagnostics[:unmerged_cliques]=length(cliques)
    cliques,parents=_sdp_merge_cliques(cliques,parents,clique_size)
    grams=Any[];entries=Dict{Tuple{Int,Int},Any}()
    separator_orders=Int[]
    for (index,clique) in enumerate(cliques)
        G=_sdp_psd(model,length(clique),cone);push!(grams,G)
        if parents[index]!=0
            parent=cliques[parents[index]]
            shared=intersect(clique,parent);push!(separator_orders,length(shared))
            for (a,i) in enumerate(clique),j in clique[a:end]
                j in shared && i in shared || continue
                b=findfirst(==(j),clique)
                reference=entries[(i,j)]
                @constraint(model,real(G[a,b])==real(reference))
                i==j || @constraint(model,imag(G[a,b])==imag(reference))
            end
        end
        for (a,i) in enumerate(clique),(b,j) in enumerate(clique)
            get!(entries,(i,j),G[a,b])
        end
    end
    diagnostics[:cliques]=length(cliques)
    diagnostics[:clique_orders]=length.(cliques)
    diagnostics[:separator_ranks]=separator_orders
    diagnostics[:separator_real_dimension]=sum(abs2,separator_orders;init=0)
    SDPSparseMoment(n,cliques,grams,parents,entries)
end

# Amalgamate adjacent tree bags. This adds fill products, preserves running
# intersection and PSD-completion equivalence, and avoids hundreds of tiny cones.
function _sdp_merge_cliques(cliques,parents,limit;N=nothing,weight=1.0)
    bags=copy(cliques);neighbors=[Set{Int}() for _ in bags];active=trues(length(bags))
    ranks=Dict{Tuple,Int}()
    reduced(c)=get!(ranks,Tuple(sort(c))) do
        C=N[c,:];s=svdvals(C)
        count(>(maximum(size(C))*eps(Float64)*maximum(s;init=0.0)),s)
    end
    # Surrogate for cone algebra plus separator coupling, NOT a prediction of
    # KKT factorization time. A complex separator of rank s has s^2 real rows.
    cone_cost(r)=Float64(r)^3+8.0
    overlap_cost(c)=weight*Float64(reduced(c))^3
    for (i,p) in enumerate(parents)
        p==0 && continue
        push!(neighbors[i],p);push!(neighbors[p],i)
    end
    while true
        best=(N===nothing ? Float64(limit+1) : 0.0,0,0)
        for i in findall(active),j in neighbors[i]
            i<j || continue
            merged=union(bags[i],bags[j])
            if N===nothing
                score=Float64(length(merged))
            else
                r=reduced(merged);r<=limit || continue
                score=cone_cost(r)-cone_cost(reduced(bags[i]))-cone_cost(reduced(bags[j]))-
                    overlap_cost(intersect(bags[i],bags[j]))
                # Adjacent amalgamation leaves other separator ranks unchanged
                # by running intersection. Only this edge disappears.
            end
            score<best[1] && (best=(score,i,j))
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

function _sdp_sparse_moment(model,A,supports,options,diagnostics;scales=ones(size(A,2)))
    N=_sdp_scaled_basis(A,options.basis,scales;diagnostics);m=size(N,2)
    diagnostics[:basis]=options.basis==:auto ? (m<=32 ? :physical_sparse : :sparse) : options.basis
    n=size(A,2)
    if options.decomposition==:auto && m<=32
        diagnostics[:decomposition]=:dense
        diagnostics[:electrical_residual]=norm(A*N,Inf);diagnostics[:reduced_dimension]=m
        return _sdp_psd(model,m,options.cone),N
    end
    diagnostics[:decomposition]=:chordal
    cliques,parents=_sdp_cliques(n,supports;
        ordering=options.chordal_ordering,diagnostics)
    diagnostics[:unmerged_cliques]=length(cliques)
    diagnostics[:clique_merge]=options.clique_merge
    cliques,parents=_sdp_merge_cliques(cliques,parents,options.clique_size;
        N=options.clique_merge==:cost ? N : nothing,weight=options.clique_overlap_weight)
    selections=Vector{Int}[]
    for clique in cliques
        C=N[clique,:];singular=svdvals(C)
        r=count(>(maximum(size(C))*eps(Float64)*maximum(singular;init=0.0)),singular)
        push!(selections,clique[qr(Matrix{ComplexF64}(C'),ColumnNorm()).p[1:r]])
    end
    separator_ranks=Int[]
    for (k,p) in enumerate(parents)
        p==0 && continue
        C=N[intersect(cliques[k],cliques[p]),:];s=svdvals(C)
        push!(separator_ranks,count(>(maximum(size(C))*eps(Float64)*maximum(s;init=0.0)),s))
    end
    diagnostics[:separator_ranks]=separator_ranks
    diagnostics[:separator_real_dimension]=sum(abs2,separator_ranks;init=0)
    diagnostics[:clique_cost_proxy]=sum(r->Float64(r)^3+8.0,length.(selections);init=0.0)+
        options.clique_overlap_weight*sum(r->Float64(r)^3,separator_ranks;init=0.0)
    if any(length(c)==m for c in selections)
        diagnostics[:decomposition]=:dense
        diagnostics[:electrical_residual]=norm(A*N,Inf)
        diagnostics[:reduced_dimension]=m
        return _sdp_psd(model,m,options.cone),N
    end
    consistency=options.consistency==:auto ? (m<=32 ? :shared : :local) : options.consistency
    diagnostics[:consistency]=consistency
    if consistency==:local
        return _sdp_local_cliques(model,A,N,cliques,parents,selections,
            supports,options,diagnostics),Matrix{ComplexF64}(I,n,n)
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

function _sdp_local_cliques(model,A,N,cliques,parents,selections,supports,
                            options,diagnostics)
    grams=Any[];entries=Dict{Tuple{Int,Int},Any}();projection_residual=0.0
    required=Dict{Int,Set{Int}}()
    require!(i,j)=push!(get!(required,i,Set{Int}()),j)
    for support in supports,i in support,j in support
        require!(i,j)
    end
    separator_coordinates=[Int[] for _ in cliques]
    for index in eachindex(cliques)
        parents[index]==0 && continue
        shared=intersect(cliques[index],cliques[parents[index]])
        if !isempty(shared)
            C=N[shared,:];singular=svdvals(C)
            rank=count(>(maximum(size(C))*eps(Float64)*maximum(singular;init=0.0)),singular)
            shared=shared[qr(Matrix{ComplexF64}(C'),ColumnNorm()).p[1:rank]]
        end
        separator_coordinates[index]=shared
        for i in shared,j in shared
            require!(i,j)
        end
    end
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
        # Associate the symbolic congruence as (T*H)*Tᴴ. Expanding every
        # G[i,j] independently costs O(|C|²r²); the factored construction is
        # O(|C|r² + |C|²r) and is algebraically identical.
        TH=Any[sum((T[i,a]*H[a,b] for a in 1:r if !iszero(T[i,a]));init=0im)
               for i in eachindex(clique),b in 1:r]
        G=SDPLocalGram(T,TH)
        push!(grams,G)
        if parents[index]!=0
            shared=separator_coordinates[index]
            # Independent separator coordinates suffice: every other separator
            # coordinate is already an electrical linear combination of these.
            for (ki,i) in enumerate(shared),j in shared[ki:end]
                f=(G[findfirst(==(i),clique),findfirst(==(j),clique)]-entries[(i,j)])/(norm(N[i,:])*norm(N[j,:]))
                @constraint(model,real(f)==0)
                i==j || @constraint(model,imag(f)==0)
            end
        end
        position=Dict(value=>i for (i,value) in enumerate(clique))
        for (i,gi) in enumerate(clique),gj in get(required,gi,Set{Int}())
            haskey(position,gj) || continue
            get!(entries,(gi,gj),G[i,position[gj]])
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
