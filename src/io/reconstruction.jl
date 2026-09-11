# Conditional means of local moments. This neither completes a PSD matrix nor
# assumes that SOC blocks are PSD. The result is explicitly a phasor estimate.
function _candidate_state(b::SDPBuild)
    H=b.moment; a=b.anchor; anchor=b.anchor_voltage/b.voltage_base
    if H isa SDPSparseMoment
        z=fill(ComplexF64(NaN),size(H,1));z[a]=anchor
        remaining=Set(eachindex(H.cliques))
        while !isempty(remaining)
            progress=false
            for j in sort!(collect(remaining))
                C=H.cliques[j];known=findall(i->isfinite(z[i]),C)
                isempty(known) && continue
                G=ComplexF64.(JuMP.value.(H.grams[j]));fresh=setdiff(eachindex(C),known)
                z[C[fresh]]=G[fresh,known]*(pinv(G[known,known];rtol=1e-9)*z[C[known]])
                delete!(remaining,j);progress=true
            end
            progress || break
        end
    else
        W=ComplexF64.(JuMP.value.(H))
        z=b.nullspace*W*conj.(b.nullspace[a,:])/conj(anchor)
    end
    voltage=Dict(k=>(i==0 ? 0im : b.voltage_base*z[i]) for (k,i) in b.voltage_indices)
    currents=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    for (family,id,_,rows,_) in get(b.model.ext,:state_channels,[])
        currents[(family,id)]=[sum((c*z[i] for (i,c) in row);init=0im)*b.options.s_base/b.voltage_base for row in rows]
    end
    (;voltage,currents)
end

"""Original-network phasor estimates in SI units, alongside the untouched solve
result and diagnostics. `point` uses the same current channels as `ACPoint`.
"""
struct ReconstructedSolution{R}
    point::ACPoint
    buses::Dict{String,Any}
    lines::Dict{String,Any}
    raw_result::R
    diagnostics::Dict{String,Any}
end

function _reconstruction_seed(r;build=nothing)
    if r isa ACPoint
        return r
    elseif r isa SOCResult
        haskey(r.metadata,:candidate) || throw(ArgumentError("SOC result has no usable candidate; inspect solver status"))
        return ACPoint(;r.metadata.candidate...)
    elseif r isa SDPResult
        currents=r.current_candidate
        return ACPoint(voltage=r.voltage_candidate,currents=currents)
    elseif r isa L3FResult
        v=Dict((b,t)=>ComplexF64(d["vm"]*cis(d["reference_angle"])) for (b,ts) in r.buses for (t,d) in ts)
        currents=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
        divide(s,u)=iszero(u) ? (iszero(s) ? 0im : ComplexF64(NaN)) : conj(s/u)
        for (id,data) in r.sources
            d=r.network["voltage_source"][id];tm=d["terminal_map"]
            currents[(:voltage_source,id)]=[divide(complex(data["pg"][k],data["qg"][k]),v[(d["bus"],t)]) for (k,t) in enumerate(tm)]
        end
        for (family,table) in (("load",get(r.network,"load",Dict())),("generator",get(r.network,"generator",Dict())))
            for (id,d) in table
                tm=d["terminal_map"];n=family=="load" ? length(d["p_nom"]) : length(r.generators[id]["pg"])
                D=_vcheck_incidence(_vcheck_pairs(r.network,d["bus"],tm,d["configuration"],n),length(tm))
                u=D*[v[(d["bus"],t)] for t in tm]
                if family=="generator"
                    g=r.generators[id];s=complex.(g["pg"],g["qg"])
                else
                    law=lowercase(get(d,"model","constant_power"));ratio=abs.(u)./_vcheck_array(d,"v_nom",n,1.)
                    factor(prefix,gamma)=law=="constant_power" ? ones(n) : law=="constant_current" ? ratio : law=="constant_impedance" ? ratio.^2 : law=="exponential" ? ratio.^d[gamma] : law=="zip" ? d[prefix*"_z"].*ratio.^2+d[prefix*"_i"].*ratio+d[prefix*"_p"] : fill(NaN,n)
                    s=complex.(d["p_nom"].*factor("alpha","gamma_p"),d["q_nom"].*factor("beta","gamma_q"))
                end
                currents[(Symbol(family),id)]=divide.(s,u)
            end
        end
        return ACPoint(voltage=v,currents=currents)
    end
    throw(ArgumentError("expected ACPoint or a formulation result"))
end

function _reconstruction_line(net,l)
    n=length(l["terminal_map_from"])
    length(l["terminal_map_to"])==n || throw(ArgumentError("line terminal arity mismatch"))
    d=haskey(l,"linecode") ? net["linecode"][l["linecode"]] : l
    len=haskey(l,"linecode") ? get(l,"length",1.0) : 1.0
    function matrix(prefix)
        M=_kr_matrix(d,prefix)
        M===nothing && return zeros(n,n)
        size(M,1)<=n || throw(ArgumentError("line matrix exceeds terminal arity"))
        out=zeros(n,n);out[1:size(M,1),1:size(M,2)]=M;out*len
    end
    (matrix("R_series_")+im*matrix("X_series_"),matrix("G_from_")+im*matrix("B_from_"),matrix("G_to_")+im*matrix("B_to_"))
end

"""Reconstruct eliminated passive buses and every original line from retained
endpoint phasors. A sparse current–voltage solve supports π shunts and singular
series impedances. No optimizer or incumbent-dependent refinement is used.
Original component currents supplied by the seed are retained; missing channels
are reported by `physical_residuals`. This is an estimate, not an inverse OPF.
"""
function reconstruct_solution(p::PreparedNetwork,r;build=nothing,warn::Bool=true)
    seed=_reconstruction_seed(r;build)
    net=p.plan.original;alias(b)=get(p.plan.bus_alias,b,b)
    key(b,t)=(alias(b),String(t))
    fixed=copy(seed.voltage)
    all(isfinite,values(fixed)) || throw(ArgumentError("nonfinite voltage candidate"))
    for (b,d) in net["bus"],t in get(d,"perfectly_grounded_terminals",[]);fixed[key(b,t)]=0im;end
    # Removed bus voltages are the only free voltages. Every line has a series
    # current coordinate; this avoids inverting Z, including ideal conductors.
    unknown=sort!(unique([key(b,t) for (b,d) in net["bus"] for t in d["terminal_names"] if !haskey(fixed,key(b,t))]))
    vi=Dict(k=>i for (i,k) in enumerate(unknown));nc=length(unknown)
    lineids=sort!(collect(keys(get(net,"line",Dict()))));ci=Dict{String,UnitRange{Int}}()
    for id in lineids
        n=length(net["line"][id]["terminal_map_from"]);ci[id]=nc+1:nc+n;nc+=n
    end
    rr=Int[];cc=Int[];vv=ComplexF64[];rhs=zeros(ComplexF64,nc);row=length(unknown)
    add(row,col,c)=(iszero(c) || (push!(rr,row);push!(cc,col);push!(vv,c));nothing)
    function voltage!(row,k,c)
        if haskey(vi,k);add(row,vi[k],c);else;rhs[row]-=c*fixed[k];end
    end
    params=Dict{String,Any}()
    for id in lineids
        l=net["line"][id];Z,Yf,Yt=_reconstruction_line(net,l);params[id]=(Z,Yf,Yt)
        f=[key(l["bus_from"],t) for t in l["terminal_map_from"]]
        t=[key(l["bus_to"],t) for t in l["terminal_map_to"]]
        for k in eachindex(f)
            row+=1;voltage!(row,f[k],1);voltage!(row,t[k],-1)
            for j in eachindex(f);add(row,ci[id][j],-Z[k,j]);end
            for (ks,Y,sgn) in ((f,Yf,1),(t,Yt,-1))
                haskey(vi,ks[k]) || continue
                q=vi[ks[k]];add(q,ci[id][k],sgn)
                for j in eachindex(ks);voltage!(q,ks[j],Y[k,j]);end
            end
        end
    end
    A=sparse(rr,cc,vv,nc,nc)
    # Zero-impedance loops can have indeterminate currents. Sparse QR gives a
    # convention in that case; report the residual and nonunique assignment.
    unique_state=true
    x=if nc==0
        ComplexF64[]
    else
        F=lu(A;check=false)
        if issuccess(F);F\rhs
        else;unique_state=false;qr(A)\rhs
        end
    end
    for (k,i) in vi;fixed[k]=x[i];end
    voltage=Dict((b,String(t))=>fixed[key(b,t)] for (b,d) in net["bus"] for t in d["terminal_names"])
    currents=deepcopy(seed.currents);lines=Dict{String,Any}();mismatch=0.0
    for id in lineids
        l=net["line"][id];_,Yf,Yt=params[id];vf=[voltage[(l["bus_from"],t)] for t in l["terminal_map_from"]];vt=[voltage[(l["bus_to"],t)] for t in l["terminal_map_to"]]
        cf=x[ci[id]]+Yf*vf;ct=-x[ci[id]]+Yt*vt
        currents[(:line_from,id)]=cf;currents[(:line_to,id)]=ct
        sf=vf.*conj.(cf);st=vt.*conj.(ct)
        lines[id]=Dict("current_from"=>cf,"current_to"=>ct,"power_from"=>sf,"power_to"=>st,"loss"=>sum(sf+st),"provenance"=>"passive_circuit_reconstruction")
    end
    # Compare net line injection at retained terminals, so merged IDs and
    # reversed orientations do not corrupt the boundary mismatch metric.
    injection=Dict{Tuple{String,String},ComplexF64}()
    for (network,sign,cs) in ((net,1,currents),(p.network,-1,seed.currents)),(id,l) in get(network,"line",Dict())
        for (side,family) in (("from",:line_from),("to",:line_to))
            haskey(cs,(family,id)) || continue
            for (t,i) in zip(l["terminal_map_"*side],cs[(family,id)])
                k=key(l["bus_"*side],t);injection[k]=get(injection,k,0im)+sign*i
            end
        end
    end
    has_line_seed=any(k[1]==:line_from for k in keys(seed.currents))
    mismatch=has_line_seed ? maximum((abs(get(injection,k,0im)) for k in keys(seed.voltage));init=0.0) : NaN
    inferred_transformers=_reconstruct_transformers!(net,voltage,currents,r)
    # Open switches have exactly zero current. Collapsed switch currents remain
    # explicitly unobserved until a device-balanced current assignment is known.
    for (id,s) in get(net,"switch",Dict())
        if get(s,"open_switch",false)
            currents[(:switch_from,id)]=zeros(ComplexF64,length(s["terminal_map_from"]))
            currents[(:switch_to,id)]=zeros(ComplexF64,length(s["terminal_map_to"]))
        end
    end
    # Complete inverter filter currents from observed terminal/channel currents.
    # A three-leg delta has a free circulating mode; use its least-norm value.
    for (id,d) in get(net,"ibr",Dict())
        haskey(currents,(:ibr,id)) || continue
        haskey(currents,(:ibr_internal,id)) && continue
        tm=d["terminal_map"];n=length(d["s_max"]);top=d["topology"]
        cfg=top=="FOUR_LEG" ? "WYE" : top=="THREE_LEG" ? "DELTA" : "SINGLE_PHASE"
        D=_vcheck_incidence(_vcheck_pairs(net,d["bus"],tm,cfg,n),length(tm))
        u=D*[voltage[(d["bus"],t)] for t in tm]
        i=currents[(:ibr,id)];coil=top=="THREE_LEG" ? pinv(transpose(D))*i : i
        currents[(:ibr_internal,id)]=coil+im*get(d,"b_filter_shunt",0.).*u
    end
    # Recover removed switch currents on the original contraction forest. Each contraction
    # joins distinct buses, so the removed edges form a forest. Balancing the
    # absorbed component gives its tree-edge flow. Residual at the survivor is
    # retained (and exposed), not silently assigned to a source.
    collapsed=[e for e in p.plan.events if e["code"]=="SWITCH_COLLAPSED"]
    for e in collapsed
        id=e["element_id"];sw=net["switch"][id]
        currents[(:switch_from,id)]=zeros(ComplexF64,length(sw["terminal_map_from"]))
        currents[(:switch_to,id)]=zeros(ComplexF64,length(sw["terminal_map_to"]))
    end
    switch_assignments=String[]
    if !isempty(collapsed)
        balance=physical_residuals(net,ACPoint(;voltage,currents)).nodal_balance
        graph=Dict{String,Vector{Tuple{String,String}}}()
        for e in collapsed
            id=e["element_id"];sw=net["switch"][id];f,t=sw["bus_from"],sw["bus_to"]
            push!(get!(graph,f,Tuple{String,String}[]),(t,id))
            push!(get!(graph,t,Tuple{String,String}[]),(f,id))
        end
        seen=Set{String}()
        for start in sort!(collect(keys(graph)))
            start in seen && continue
            root=alias(start);order=[root];push!(seen,root)
            parent=Dict{String,Tuple{String,String}}()
            for b in order,(next,id) in graph[b]
                next in seen && continue
                parent[next]=(b,id);push!(seen,next);push!(order,next)
            end
            for b in reverse(order[2:end])
                up,id=parent[b];sw=net["switch"][id]
                tm=sw["terminal_map_from"]
                demand=ComplexF64[get(balance,(b,t),0im) for t in tm]
                if all(isfinite,demand)
                    i=sw["bus_from"]==up ? demand : -demand
                    currents[(:switch_from,id)]=i;currents[(:switch_to,id)]=-i
                    push!(switch_assignments,id)
                    for (t,x) in zip(tm,demand);balance[(up,t)]=get(balance,(up,t),0im)+x;end
                else
                    delete!(currents,(:switch_from,id));delete!(currents,(:switch_to,id))
                end
            end
        end
    end
    point=ACPoint(;voltage,currents)
    residuals=physical_residuals(net,point)
    buses=Dict{String,Any}(b=>Dict(t=>Dict("vr"=>real(voltage[(b,t)]),"vi"=>imag(voltage[(b,t)]),"vm"=>abs(voltage[(b,t)]),"va"=>angle(voltage[(b,t)]),
        "provenance"=>haskey(seed.voltage,(b,t)) ? "retained_candidate" : "reconstructed") for t in d["terminal_names"]) for (b,d) in net["bus"])
    diagnostics=Dict{String,Any}("reduction"=>reduction_report(p),"boundary_current_mismatch_A"=>mismatch,
        "linear_system_residual"=>maximum(abs,A*x-rhs;init=0.0),"unique_passive_state"=>unique_state,
        "physical"=>residuals,"phasors_are_estimates"=>true,"switch_current_estimates"=>switch_assignments,"inferred_transformers"=>inferred_transformers)
    warn && !unique_state && @warn "Passive reconstruction contains indeterminate coordinates; inspect diagnostics"
    warn && !residuals.passed && @warn "Reconstructed phasors do not satisfy all original-network checks; inspect full.diagnostics[\"physical\"]" maxima=residuals.maxima unassessed=length(residuals.unassessed)
    ReconstructedSolution(point,buses,lines,r,diagnostics)
end

# Small, independent transformer current fits for voltage-only/L3F seeds. This
# reuses fixed-tap electrical stamps, not an optimizer or global moment model.
function _reconstruct_transformers!(net,voltage,currents,result)
    inferred=String[]
    for (kind,table) in get(net,"transformer",Dict()),(id,d) in table
        prefix="$kind/$id"
        kind in (_SDP_TRANSFORMERS...,"n_winding") || continue
        any(k->startswith(string(k[1]),"transformer") && (k[2]==prefix || startswith(k[2],prefix*"/")),keys(currents)) && continue
        localnet=copy(net);localnet["transformer"]=Dict(kind=>Dict(id=>d))
        vs=ComplexF64[];nv=Ref(0);counter=Ref(0)
        terminals=Dict{Tuple{String,String},Int}()
        buses=kind=="n_winding" ? [(w["bus"],w["terminal_map"]) for w in d["windings"]] : [(d["bus_from"],d["terminal_map_from"]),(d["bus_to"],d["terminal_map_to"])]
        for (b,tm) in buses,t in tm
            haskey(terminals,(b,t)) && continue
            push!(vs,voltage[(b,t)]);terminals[(b,t)]=length(vs)
        end
        nv[]=length(vs);counter[]=nv[]
        newvar()=(counter[]+=1)
        terminal_rows(b,tm)=[_sdp_e(terminals[(b,t)]) for t in tm]
        function matrows(M,rows)
            out=[_SDPRow() for _ in axes(M,1)]
            for i in axes(M,1),j in axes(M,2);_sdp_add!(out[i],rows[j],M[i,j]);end
            out
        end
        equations=_SDPRow[];devices=Any[];limits=Any[]
        stamp=kind=="n_winding" ? _sdp_stamp_nwinding! : _sdp_stamp_transformers!
        stamp(localnet,newvar,terminal_rows,matrows,(args...)->nothing,equations,devices,limits,1.)
        targets=ComplexF64[];rows=Dict{Int,ComplexF64}[]
        for row in equations
            push!(rows,Dict(i-nv[]=>c for (i,c) in row if i>nv[]))
            push!(targets,-sum((c*vs[i] for (i,c) in row if i<=nv[]);init=0im))
        end
        if result isa L3FResult && haskey(result.transformers,id)
            data=result.transformers[id];side=data["child"]==get(d,"bus_from",nothing) ? :from : :to
            coil=Symbol("transformer_coil_",side)
            for (family,_,u,j,_) in devices
                family==coil || continue
                s=complex.(data["p"],data["q"])
                if length(s)!=length(u)
                    inds=findall(!=(_vcheck_neutral(net,data["child"])),data["terminal_map_child"])
                    s=s[inds]
                end
                length(s)==length(u) || continue
                for k in eachindex(u)
                    v=sum((c*vs[i] for (i,c) in u[k]);init=0im)
                    iszero(v) && continue
                    push!(rows,Dict(i-nv[]=>c for (i,c) in j[k] if i>nv[]));push!(targets,-conj(s[k]/v))
                end
            end
        end
        x,_=_audit_linear(rows,targets,counter[]-nv[])
        state=[vs;x]
        for (family,key,_,js,_) in devices
            currents[(family,key)]=[sum((c*state[i] for (i,c) in row);init=0im) for row in js]
        end
        push!(inferred,prefix)
    end
    inferred
end

# Voltage-only maximum-correlation spanning forest. Unlike conditional means on
# indefinite SOC separators, it never divides by a nearly singular Gram block.
function _soc_voltage_state(b::SDPBuild)
    H=b.moment;indices=sort!(unique(filter(!iszero,collect(values(b.voltage_indices)))))
    pos=Dict(i=>k for (k,i) in enumerate(indices));n=length(indices)
    diagonal=zeros(n);edges=Tuple{Float64,Int,Int,Float64}[]
    if H isa SDPSparseMoment
        for (k,i) in enumerate(indices);diagonal[k]=real(JuMP.value(H[i,i]));end
        for ((i,j),f) in H.entries
            i<j && haskey(pos,i) && haskey(pos,j) || continue
            a,c=pos[i],pos[j];w=ComplexF64(JuMP.value(f))
            scale=sqrt(max(0.,diagonal[a])*max(0.,diagonal[c]))
            scale>1e-16 && abs(w)>1e-16 || continue
            push!(edges,(min(1.,abs(w)/scale),a,c,angle(w)))
        end
    else
        N=b.nullspace[indices,:];W=N*ComplexF64.(JuMP.value.(H))*N'
        diagonal=real.(diag(W))
        for i in 1:n,j in i+1:n
            scale=sqrt(max(0.,diagonal[i])*max(0.,diagonal[j]))
            scale>1e-16 && abs(W[i,j])>1e-16 || continue
            push!(edges,(min(1.,abs(W[i,j])/scale),i,j,angle(W[i,j])))
        end
    end
    # Kruskal forest with a virtual reference joining prescribed sources.
    parent=collect(1:n+1)
    function root(i)
        while parent[i]!=i;parent[i]=parent[parent[i]];i=parent[i];end
        i
    end
    adjacency=[Tuple{Int,Float64}[] for _ in 1:n];angles=fill(NaN,n);queue=Int[]
    for source in values(b.network["voltage_source"]),(t,mag,ang) in zip(source["terminal_map"],source["v_magnitude"],source["v_angle"])
        i=b.voltage_indices[(source["bus"],t)];i==0 && continue
        a=pos[i];mag>0 || continue
        angles[a]=ang;diagonal[a]=(mag/b.voltage_base)^2;push!(queue,a);parent[root(a)]=root(n+1)
    end
    sort!(edges;by=e->(-e[1],e[2],e[3]))
    for (_,i,j,angleij) in edges
        ri,rj=root(i),root(j);ri==rj && continue
        parent[ri]=rj;push!(adjacency[i],(j,-angleij));push!(adjacency[j],(i,angleij))
    end
    for i in queue
        for (j,delta) in adjacency[i]
            isfinite(angles[j]) && continue
            angles[j]=angles[i]+delta;push!(queue,j)
        end
    end
    unanchored=count(!isfinite,angles)
    for k in eachindex(angles);isfinite(angles[k]) || (angles[k]=0.);end
    z=sqrt.(max.(0.,diagonal)).*cis.(angles)*b.voltage_base
    voltage=Dict(k=>(i==0 ? 0im : z[pos[i]]) for (k,i) in b.voltage_indices)
    byindex=Dict(i=>z[pos[i]] for i in indices)
    currents=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    for (family,id,vs,_,_) in b.model.ext[:state_channels]
        key=(family,id);haskey(b.powers,key) || continue
        all(all(haskey(byindex,i) for i in keys(row)) for row in vs) || continue
        u=[sum((c*byindex[i] for (i,c) in row);init=0im) for row in vs]
        s=ComplexF64.(JuMP.value.(b.powers[key]))*b.options.s_base
        currents[key]=[abs(u[k])>1e-10 ? conj(s[k]/u[k]) : iszero(s[k]) ? 0im : ComplexF64(NaN) for k in eachindex(u)]
    end
    # Count unanchored nonzero-magnitude coordinates separately from the exact
    # zero-voltage convention. Neither count modifies optimization constraints.
    b.numerical_diagnostics[:recovery_unanchored_coordinates]=unanchored
    (;voltage,currents)
end
