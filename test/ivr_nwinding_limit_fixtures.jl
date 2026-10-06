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
