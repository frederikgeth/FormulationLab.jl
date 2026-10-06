# Lossless, unequal-turn three-winding circuit with an analytical dispatch oracle.
# No compiler winding-plan or limit helper is used to construct expected values.
function _nwinding_limit_case(;phases=3,reverse=false,rating=300.)
    phase=["a","b","c"][1:phases];tm=[phase;"n"]
    angles=[0.,-2pi/3,2pi/3][1:phases];sign=reverse ? -1. : 1.
    buses=Dict("b$k"=>Dict("terminal_names"=>copy(tm),"perfectly_grounded_terminals"=>["n"]) for k in 1:3)
    ws=[Dict{String,Any}("bus"=>"b$k","terminal_map"=>copy(tm),"configuration"=>"WYE",
        "v_nom"=>230.0 / 2.0^(k-1),"r_winding"=>0.) for k in 1:3]
    rating===nothing || (ws[2]["s_max"]=deepcopy(rating))
    demand=[200.,160.,120.][1:phases]
    net=Dict{String,Any}("bus"=>buses,
        "transformer"=>Dict("n_winding"=>Dict("tx"=>Dict("windings"=>ws,"x_sc"=>Dict("1_2"=>0.,"1_3"=>0.,"2_3"=>0.)))),
        "voltage_source"=>Dict("source"=>Dict("bus"=>"b1","terminal_map"=>copy(tm),"v_magnitude"=>[fill(230.,phases);0.],"v_angle"=>[angles;0.])),
        "load"=>Dict("d"=>Dict("bus"=>"b2","terminal_map"=>copy(tm),"configuration"=>"WYE","p_nom"=>sign*demand,"q_nom"=>zeros(phases))),
        "generator"=>Dict("g"=>Dict("bus"=>"b2","terminal_map"=>copy(tm),"configuration"=>"WYE",
            "p_min"=>fill(reverse ? -300. : 0.,phases),"p_max"=>fill(reverse ? 0. : 300.,phases),
            "q_min"=>zeros(phases),"q_max"=>zeros(phases),"s_max"=>fill(300.,phases),"cost"=>fill(sign,phases))))
    net,demand
end

# Finite-leakage connection transfer. Delta secondary common-mode voltage is
# fixed by explicitly grounding c; no transformer coil or circulation is removed.
# Single-phase dispatch devices avoid conflating transformer and generator-delta
# conventions in the independent reference comparison.
function _nwinding_connection_case(;connection=:YDY,roll=1,reverse=false,bounded=true)
    connection in (:YYY,:YDY,:DYY) || throw(ArgumentError("unknown connection case"))
    roll in (-1,1) || throw(ArgumentError("delta roll must be -1 or 1"))
    net,_=_nwinding_limit_case(;rating=bounded ? 300. : nothing)
    ws=net["transformer"]["n_winding"]["tx"]["windings"]
    for k in 1:3
        delta=string(connection)[k]=='D'
        ws[k]["r_winding"]=.02/4.0^(k-1)
        if delta
            ws[k]["configuration"]="DELTA";ws[k]["terminal_map"]=["a","b","c"]
            ws[k]["v_nom"]*=sqrt(3.);ws[k]["delta_roll"]=roll
            k==1 || (net["bus"]["b$k"]=Dict("terminal_names"=>["a","b","c"],"perfectly_grounded_terminals"=>["c"]))
        end
    end
    net["transformer"]["n_winding"]["tx"]["x_sc"]=Dict("1_2"=>.04,"1_3"=>.06,"2_3"=>.05)
    empty!(net["load"]);empty!(net["generator"])
    sign=reverse ? -1. : 1.;phase=["a","b","c"]
    for k in 1:3
        tm=[phase[k],connection==:YDY ? phase[mod1(k+1,3)] : "n"]
        net["load"]["d$k"]=Dict("bus"=>"b2","terminal_map"=>tm,"configuration"=>"SINGLE_PHASE",
            "p_nom"=>[sign*[200.,160.,120.][k]],"q_nom"=>[0.])
        net["generator"]["g$k"]=Dict("bus"=>"b2","terminal_map"=>copy(tm),"configuration"=>"SINGLE_PHASE",
            "p_min"=>[reverse ? -300. : 0.],"p_max"=>[reverse ? 0. : 300.],
            "q_min"=>[0.],"q_max"=>[0.],"s_max"=>[300.],"cost"=>[sign])
    end
    net
end

# Independent legacy-SI adapter for the connection fixture only. No hidden
# current is fitted: winding terminal currents follow the declared incidence.
function _nwinding_connection_point(net,d)
    voltage=Dict((b,t)=>complex(x["vr"],x["vi"]) for (b,ts) in d["bus"] for (t,x) in ts)
    currents=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    for (family,re,im) in (("load","crd","cid"),("generator","crg","cig"))
        for (id,g) in net[family]
            @assert g["configuration"]=="SINGLE_PHASE"
            x=d[family][id][first(g["terminal_map"])]
            currents[(Symbol(family),id)]=[complex(x[re],x[im])]
        end
    end
    for (id,s) in net["voltage_source"]
        grounded=get(net["bus"][s["bus"]],"perfectly_grounded_terminals",[])
        currents[(:voltage_source,id)]=[t in grounded ? 0im : complex(d["voltage_source"][id][t]["cr"],d["voltage_source"][id][t]["ci"]) for t in s["terminal_map"]]
    end
    tx=net["transformer"]["n_winding"]["tx"]
    @assert !any(haskey(tx,k) for k in ("g_no_load","b_no_load"))
    excitation=get(tx,"no_load_shunt",nothing)
    for (k,w) in enumerate(tx["windings"])
        j=[complex(d["transformer"]["tx"]["w$k"][string(c)]["cr"],d["transformer"]["tx"]["w$k"][string(c)]["ci"]) for c in 1:3]
        terminal=zeros(ComplexF64,length(w["terminal_map"]))
        for c in 1:3
            other=w["configuration"]=="DELTA" ? mod1(c+get(w,"delta_roll",1),3) : 4
            injection=j[c]
            if excitation!==nothing && excitation["winding"]==k
                u=voltage[(w["bus"],w["terminal_map"][c])]-voltage[(w["bus"],w["terminal_map"][other])]
                injection+=complex(excitation["g"],excitation["b"])*u
            end
            terminal[c]+=injection
            terminal[other]-=injection
        end
        currents[(:transformer_coil,"n_winding/tx/$k")]=j
        currents[(:transformer_winding,"n_winding/tx/$k")]=terminal
    end
    ACPoint(;voltage,currents)
end

# Explicit SI per-coil admittance, attached at the physical winding terminals.
# At nominal coil voltage each branch consumes 2 W and 3 var. Nothing is moved
# through leakage or inferred from either package's legacy excitation fields.
function _nwinding_excitation_case(;winding=2,kwargs...)
    winding in 1:3 || throw(ArgumentError("excitation winding must be 1, 2 or 3"))
    net=_nwinding_connection_case(;kwargs...)
    tx=net["transformer"]["n_winding"]["tx"]
    v=tx["windings"][winding]["v_nom"]
    tx["no_load_shunt"]=Dict("winding"=>winding,"g"=>2/v^2,"b"=>-3/v^2)
    net
end

# Four-winding pair data that cannot be represented by an ordinary star:
# x12+x34=.16, x13+x24=.18, x14+x23=.17. The independently specified
# reduced X matrix is strictly diagonally dominant and positive definite.
function _nwinding_nonstar_case(;connection=:YYYY,roll=1,reverse=false,bounded=true,excitation=false)
    connection in (:YYYY,:YDYY,:YYYD,:DYYY) || throw(ArgumentError("unknown four-winding connection"))
    roll in (-1,1) || throw(ArgumentError("delta roll must be -1 or 1"))
    net,_=_nwinding_limit_case(;rating=nothing)
    tx=net["transformer"]["n_winding"]["tx"];ws=tx["windings"]
    push!(ws,deepcopy(ws[3]));phase=["a","b","c"]
    for k in 1:4
        delta=string(connection)[k]=='D';tm=delta ? copy(phase) : [phase;"n"]
        ws[k]=Dict{String,Any}("bus"=>"b$k","terminal_map"=>tm,
            "configuration"=>delta ? "DELTA" : "WYE","v_nom"=>230/2.0^(k-1)*(delta ? sqrt(3.) : 1.),
            "r_winding"=>.02/4.0^(k-1))
        delta && (ws[k]["delta_roll"]=roll)
        if k!=1
            net["bus"]["b$k"]=Dict("terminal_names"=>copy(tm),
                "perfectly_grounded_terminals"=>[delta ? "c" : "n"])
        end
    end
    tx["x_sc"]=Dict("1_2"=>.04,"1_3"=>.07,"1_4"=>.10,"2_3"=>.07,"2_4"=>.11,"3_4"=>.12)
    if bounded;ws[2]["s_max"]=300.;ws[4]["s_max"]=180.;end
    if excitation
        v=ws[4]["v_nom"];tx["no_load_shunt"]=Dict("winding"=>4,"g"=>2/v^2,"b"=>-3/v^2)
    end
    empty!(net["load"]);empty!(net["generator"]);sign=reverse ? -1. : 1.
    for k in 2:4,c in 1:3
        delta=string(connection)[k]=='D';tm=[phase[c],delta ? phase[mod1(c+1,3)] : "n"]
        demand=([200.,160.,120.],[60.,50.,40.],[100.,80.,60.])[k-1][c]
        id="w$(k)c$c"
        net["load"][id]=Dict("bus"=>"b$k","terminal_map"=>tm,"configuration"=>"SINGLE_PHASE",
            "p_nom"=>[sign*demand],"q_nom"=>[0.])
        k==3 && continue
        net["generator"][id]=Dict("bus"=>"b$k","terminal_map"=>copy(tm),"configuration"=>"SINGLE_PHASE",
            "p_min"=>[reverse ? -300. : 0.],"p_max"=>[reverse ? 0. : 300.],
            "q_min"=>[0.],"q_max"=>[0.],"s_max"=>[300.],"cost"=>[sign])
    end
    net
end

# Independent SI oracle for the declared four-winding fixture. The X matrix is
# specified directly, not obtained from either package's winding-plan helper.
function _nwinding_nonstar_equations(net,point)
    tx=net["transformer"]["n_winding"]["tx"];ws=tx["windings"]
    turns=[w["v_nom"]/ws[1]["v_nom"] for w in ws]
    u=[[point.voltage[(w["bus"],w["terminal_map"][c])]-
        point.voltage[(w["bus"],w["terminal_map"][w["configuration"]=="DELTA" ? mod1(c+get(w,"delta_roll",1),3) : 4])]
        for c in 1:3] for w in ws]
    j=[point.currents[(:transformer_coil,"n_winding/tx/$k")] for k in 1:4]
    X=[.04 .02 .015;.02 .07 .025;.015 .025 .10]
    r=[ws[k]["r_winding"]/turns[k]^2 for k in 1:4]
    Z=[(r[1]+(i==k ? r[i+1] : 0.))+im*X[i,k] for i in 1:3,k in 1:3]
    amp=maximum(abs(sum(turns[k]*j[k][c] for k in 1:4)) for c in 1:3)
    kvl=maximum(abs(u[1][c]-u[i+1][c]/turns[i+1]+sum(Z[i,k]*turns[k+1]*j[k+1][c] for k in 1:3)) for i in 1:3,c in 1:3)
    loss=sum(sum(u[k].*conj.(j[k])) for k in 1:4)
    expected=sum(sum(Z[i,k]*turns[k+1]*j[k+1][c] for k in 1:3)*conj(turns[i+1]*j[i+1][c]) for i in 1:3,c in 1:3)
    (;ampere_turn_A=amp,leakage_V=kvl,loss_identity_VA=abs(loss-expected),coil_power=[u[k].*conj.(j[k]) for k in 1:4])
end

function _nwinding_nonstar_options(sb,lifting)
    IVRNLPOptions(;s_base=sb,objective_scale=1.,transformer_nameplate=:bmopftools,
        lifting,lifted_power_base=500.,observation_sharing=:signed,
        specialization=:conductor_regions,linear_elimination=:passive_blocks,
        device_elimination=:transformer_currents,transformer_scaling=:nominal,row_scaling=:composed)
end
