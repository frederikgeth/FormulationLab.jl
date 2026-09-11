# All selections use physical maps and affine coefficients, never JuMP values.
function _soc_projection!(model,w,l,s)
    ws=max(maximum(abs,values(w.terms);init=0.0),abs(w.constant))
    ls=max(maximum(abs,values(l.terms);init=0.0),abs(l.constant))
    if iszero(ws) || iszero(ls)
        @constraint(model,w>=0);@constraint(model,l>=0)
        @constraint(model,real(s)==0);@constraint(model,imag(s)==0)
        return
    end
    g=sqrt(ws)*sqrt(ls)
    x=@variable(model,[1:4])
    for (y,f) in zip(x,(w/ws,l/ls,real(s)/g,imag(s)/g));@constraint(model,y==f);end
    @constraint(model,[x[1],x[2],sqrt(2)*x[3],sqrt(2)*x[4]] in RotatedSecondOrderCone())
end

# Equation (4) of Geth & Foster (2021), constructed in the complex domain.
function _soc_kim!(model,G,eta)
    for pivot in 1:3
        others=filter(!=(pivot),1:3);j,k=others
        alpha=real(G[pivot,pivot])
        t=real(G[j,j]+abs2(eta)*G[k,k]+eta*G[j,k]+conj(eta)*G[k,j])
        s=G[pivot,j]+eta*G[pivot,k]
        _soc_projection!(model,alpha,t,s)
    end
end

function _soc_strengthen!(model,H,N,lift,devices,range,sb,diagnostics,policy;fixed=Dict())
    o=policy.options;secants=0;triplets=NamedTuple[]
    if o.strengthening!=:none
        for (family,id,v,i,d) in devices
            family==:load && lowercase(get(d,"model","constant_power"))=="constant_power" || continue
            for k in eachindex(v)
                lo,hi=range(v[k]);0<lo<=hi<Inf || continue
                a=lo^2;b=hi^2;c=abs2(complex(d["p_nom"][k],d["q_nom"][k])/sb)
                w=real(lift(v[k],v[k]));ell=real(lift(i[k],i[k]))
                # Chord of c/w; coefficients avoid division by a*b.
                @constraint(model,ell+(c/a)/b*w <= c/a+c/b)
                secants+=1
            end
        end
    end
    if o.strengthening==:kim && o.max_triplets>0
        seen=Set{Any}()
        # Small physical groups keep the existing clique cover intact.
        # Voltage groups precede current groups, then rotate through components.
        candidates=Tuple[]
        for (family,id,v,i,d) in devices
            for (kind,rows) in ((:voltage,v),(:current,i))
                rows=filter(!isempty,rows);length(rows)>=3 || continue
                for j in 1:length(rows)-2
                    selected=rows[j:j+2]
                    push!(candidates,(j,kind==:voltage ? 0 : 1,string(family),id,selected))
                end
            end
        end
        for (_,kind,family,id,rows) in sort!(candidates;by=x->x[1:4])
            length(triplets)>=o.max_triplets && break
            key=sort!([collect(first(_sdp_map_key(r))) for r in rows];by=string)
            key in seen && continue;push!(seen,key)
            support=Set(k for r in rows for k in keys(r))
            all(haskey(fixed,k) for k in support) && continue
            if H isa SDPSparseMoment
                any(C->issubset(support,Set(C)),H.cliques) || continue
            end
            G=[lift(a,b) for a in rows,b in rows]
            # Rank <= 2 electrical groups need no three-way strengthening if
            # the entire underlying block already has order <= 2.
            !(H isa SDPSparseMoment) && size(H,1)<=2 && continue
            for j in 1:3,k in 1:j-1
                _soc_projection!(model,real(G[j,j]),real(G[k,k]),G[j,k])
            end
            for eta in unique(o.directions);_soc_kim!(model,G,eta);end
            push!(triplets,(component="$family/$id",quantity=kind==0 ? :voltage : :current,maps=key))
        end
    end
    diagnostics[:fixed_strengthening]=(profile=o.strengthening,secants=secants,
        triplets=triplets,cones=length(triplets)*(3+3length(unique(o.directions))))
end
