# Construct feasible circuits forward from winding EMFs and chosen currents.
# No formulation builder, optimizer or _sdp_* coefficient helper is used.
function _audit_transformer_state(kind;tap=1.03,rotation=0.0,reverse=false)
    net=_sdp_tx_case(kind;tap)
    tx=net["transformer"][kind]["tx"];mf=tx["terminal_map_from"];mt=tx["terminal_map_to"]
    nf,nt=length(mf),length(mt)
    incidence(pairs,n)=[Float64(k==a)-Float64(k==b) for (a,b) in pairs,k in 1:n]
    tx["r_series_from"]=.12;tx["x_series_from"]=.05;tx["r_series_to"]=.03;tx["x_series_to"]=.015
    zf=.12+.05im;zt=.03+.015im
    if kind=="single_phase"
        pf,pt=[(1,2)],[(1,2)];gain=fill(.5/tap,1,1);zf*=tap^2;bonds=Int[]
    elseif kind=="center_tap"
        pf,pt=[(1,2)],[(1,2),(2,3)];gain=fill(.5/tap,2,1);zf*=tap^2;bonds=Int[]
    elseif kind=="delta_wye"
        pf,pt=[(1,3),(2,1),(3,2)],[(1,4),(2,4),(3,4)];gain=Matrix{Float64}(I,3,3)*(.5/(sqrt(3)*tap));zf*=3tap^2;bonds=Int[]
    elseif kind=="wye_delta"
        pf,pt=[(1,4),(2,4),(3,4)],[(1,2),(2,3),(3,1)];gain=Matrix{Float64}(I,3,3)*(.5sqrt(3)/tap);zf*=tap^2;zt*=3;bonds=Int[]
    elseif kind=="single_phase_autotransformer"
        pf,pt=[(1,2)],[(1,2)];gain=fill(tap,1,1);bonds=[2]
    else
        pf=pt=[(1,2),(2,3)];gain=Matrix(Diagonal([tap,1/tap]));bonds=[2]
    end
    Df,Dt=incidence(pf,nf),incidence(pt,nt)
    s=net["voltage_source"]["s"];vf=s["v_magnitude"].*cis.(s["v_angle"].+rotation)
    s["v_angle"] .+= rotation
    nominal=gain*(Df*vf)
    jt=-(1-.2im).*nominal./abs.(nominal).*[1+0.2k for k in eachindex(nominal)]
    kind=="wye_delta" && (jt[3]=-sum(jt[1:2]))
    reverse && (jt .*= -1)
    jf=-transpose(gain)*jt;ut=gain*(Df*vf-zf*jf)+zt*jt
    constraints=copy(Dt);rhs=copy(ut)
    for k in bonds
        constraints=vcat(constraints,reshape([j==k ? 1. : 0. for j in 1:nt],1,:));push!(rhs,vf[k])
    end
    for t in get(net["bus"]["t"],"perfectly_grounded_terminals",String[])
        k=findfirst(==(t),mt)
        constraints=vcat(constraints,reshape([j==k ? 1. : 0. for j in 1:nt],1,:));push!(rhs,0im)
    end
    vt=constraints\rhs
    for t in get(net["bus"]["t"],"perfectly_grounded_terminals",String[])
        vt[findfirst(==(t),mt)]=0im
    end
    cf,ct=transpose(Df)*jf,transpose(Dt)*jt
    voltage=Dict{Tuple{String,String},ComplexF64}(("f",t)=>v for (t,v) in zip(mf,vf))
    merge!(voltage,Dict(("t",t)=>v for (t,v) in zip(mt,vt)))
    currents=Dict{Tuple{Symbol,String},Vector{ComplexF64}}((:voltage_source,"s")=>cf,
        (:transformer_from,"$kind/tx")=>cf,(:transformer_to,"$kind/tx")=>ct,
        (:transformer_coil_from,"$kind/tx")=>jf,(:transformer_coil_to,"$kind/tx")=>jt)
    # Source-ground allocation is eliminated in the common-earth representation.
    for (k,t) in enumerate(mf)
        t in get(net["bus"]["f"],"perfectly_grounded_terminals",[]) && (currents[(:voltage_source,"s")]=copy(cf);currents[(:voltage_source,"s")][k]=0)
    end
    net["load"]=Dict{String,Any}()
    for (k,(a,b)) in enumerate(pt)
        id="l$k";tm=[mt[a],mt[b]];S=ut[k]*conj(-jt[k])
        net["load"][id]=Dict("bus"=>"t","terminal_map"=>tm,"configuration"=>"SINGLE_PHASE","model"=>"constant_power","p_nom"=>[real(S)],"q_nom"=>[imag(S)])
        currents[(:load,id)]=[-jt[k]]
    end
    # Binding winding/conductor limits use the schema's side-specific convention.
    tx["i_max_from"]=abs.(kind=="delta_wye" ? jf : cf).*(1+1e-9)
    tx["i_max_to"]=abs.(kind=="wye_delta" ? jt : ct).*(1+1e-9)
    for (b,d) in net["bus"]
        v=[abs(voltage[(b,t)]) for t in d["terminal_names"]]
        d["v_min"]=0.8v;d["v_max"]=1.2v
    end
    net,ACPoint(;voltage,currents)
end

function _audit_nwinding_state()
    names=["a","b","c"];neutral=[names;"n"]
    vsource=230cis.([0.,-2pi/3,2pi/3]);ratios=[1.,.5,.25,.8];taps=[1.05,.98,1.02,1.]
    turns=ratios.*taps;r=[.02,.01,.03,.02];X=[.08 .02 .03;.02 .10 .04;.03 .04 .12]
    Z=ComplexF64[(a==b ? r[1]+r[a+1] : r[1])+im*X[a,b] for a in 1:3,b in 1:3]
    J=[zeros(ComplexF64,3) for k in 1:4]
    for k in 2:4
        J[k]=-(1-.25im).*cis.([0.,-2pi/3,2pi/3]).*[1.0+.1k,1.2+.1k,1.]
        J[k][3]=-sum(J[k][1:2])
    end
    J[1]=-sum(J[2:4]);voltage=Dict{Tuple{String,String},ComplexF64}();currents=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    buses=Dict{String,Any}();loads=Dict{String,Any}();ws=Dict{String,Any}[]
    for k in 1:4
        bus="b$k";delta=k==3;tm=delta ? copy(names) : copy(neutral)
        D=delta ? [1. -1. 0.;0. 1. -1.;-1. 0. 1.] : [Matrix{Float64}(I,3,3) -ones(3)]
        u=k==1 ? vsource : turns[k].*(vsource/turns[1]+sum(Z[k-1,j-1].*J[j] for j in 2:4))
        v=delta ? pinv(D)*u : [u;0im]
        delta && (v .-= v[3])
        buses[bus]=Dict("terminal_names"=>tm,"perfectly_grounded_terminals"=>[delta ? "c" : "n"])
        merge!(voltage,Dict((bus,t)=>a for (t,a) in zip(tm,v)))
        j=J[k]/turns[k];y=k==3 ? .002-.001im : 0im;ci=j+y.*u;terminal=transpose(D)*ci
        currents[(:transformer_coil,"n_winding/tx/$k")]=j;currents[(:transformer_winding,"n_winding/tx/$k")]=terminal
        push!(ws,Dict("bus"=>bus,"terminal_map"=>tm,"configuration"=>delta ? "DELTA" : "WYE","v_nom"=>230ratios[k],
            "r_winding"=>r[k]*ratios[k]^2,"tap_ratio"=>taps[k],"i_max"=>maximum(abs,j)*(1+1e-8)))
        if k>1
            S=u.*conj.(-ci);id="l$k"
            loads[id]=Dict("bus"=>bus,"terminal_map"=>tm,"configuration"=>delta ? "DELTA" : "WYE","model"=>"constant_power","p_nom"=>real.(S),"q_nom"=>imag.(S))
            currents[(:load,id)]=-ci
        else
            currents[(:voltage_source,"s")]=[terminal[1:3];0im]
        end
    end
    xsc=Dict("$(a)_$(b)"=>a==1 ? X[b-1,b-1] : X[a-1,a-1]+X[b-1,b-1]-2X[a-1,b-1] for a in 1:4 for b in a+1:4)
    net=Dict{String,Any}("bus"=>buses,"load"=>loads,"transformer"=>Dict("n_winding"=>Dict("tx"=>Dict("windings"=>ws,"x_sc"=>xsc,
        "no_load_shunt"=>Dict("winding"=>3,"g"=>.002,"b"=>-.001)))),
        "voltage_source"=>Dict("s"=>Dict("bus"=>"b1","terminal_map"=>neutral,"v_magnitude"=>[abs.(vsource);0.],"v_angle"=>[angle.(vsource);0.])))
    net,ACPoint(;voltage,currents)
end
