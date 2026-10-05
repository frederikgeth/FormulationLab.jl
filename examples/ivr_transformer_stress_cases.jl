"""Manufactured SI transformer-cascade OPFs with independent scalar optima.

These cases isolate active limits; they are not representative feeder samples.
Two ideal transformers feed a resistive two-wire chain. The demand neutral has
a finite 2 ohm ground, so the loop resistance is Rp + (Rn || Rg).
"""
module IVRTransformerStressCases

function case(;limit=:capability,segments=12,ratio=11000/230)
    limit in (:capability,:current,:voltage) || throw(ArgumentError("unknown active limit"))
    segments isa Integer && segments>=1 || throw(ArgumentError("positive integer segments required"))
    isfinite(ratio) && ratio>0 || throw(ArgumentError("positive finite ratio required"))
    bus=Dict{String,Any}(id=>Dict("terminal_names"=>["a","n"],
        "perfectly_grounded_terminals"=>["n"]) for id in ("hv","mv","b0"))
    for k in 1:segments
        bus["b$k"]=Dict("terminal_names"=>["a","n"],"vpn_min"=>[180.],
            "vpn_max"=>[limit==:voltage && k==segments ? 232. : 260.],"vn_max"=>[30.])
    end
    tx=Dict{String,Any}()
    for (id,f,t,vf,vt) in (("upstream","hv","mv",230ratio,2300.),("downstream","mv","b0",2300.,230.))
        tx[id]=Dict("bus_from"=>f,"bus_to"=>t,"terminal_map_from"=>["a","n"],
            "terminal_map_to"=>["a","n"],"v_nom_from"=>vf,"v_nom_to"=>vt,
            "r_series_from"=>0.,"x_series_from"=>0.,"r_series_to"=>0.,"x_series_to"=>0.,
            "i_max_from"=>fill(100.,2),"i_max_to"=>fill(100.,2))
    end
    lines=Dict("l$k"=>Dict("bus_from"=>"b$(k-1)","bus_to"=>"b$k",
        "terminal_map_from"=>["a","n"],"terminal_map_to"=>["a","n"],
        "R_series_1_1"=>.2/segments,"R_series_2_2"=>.3/segments,
        "X_series_1_1"=>0.,"X_series_2_2"=>0.,
        "i_max"=>[limit==:current && k==segments ? 5. : 100.,100.]) for k in 1:segments)
    net=Dict{String,Any}("terminal_conventions"=>Dict("phase"=>["a"],"neutral"=>["n"]),
        "bus"=>bus,"line"=>lines,"transformer"=>Dict("single_phase"=>tx),
        "voltage_source"=>Dict("grid"=>Dict("bus"=>"hv","terminal_map"=>["a","n"],
            "v_magnitude"=>[230ratio,0.],"v_angle"=>[0.,0.])),
        "shunt"=>Dict("finite_ground"=>Dict("bus"=>"b$segments","terminal_map"=>["n"],"G_1_1"=>.5)),
        "load"=>Dict("demand"=>Dict("bus"=>"b$segments","terminal_map"=>["a","n"],
            "configuration"=>"SINGLE_PHASE","model"=>"constant_power","p_nom"=>[2000.],"q_nom"=>[0.])),
        "generator"=>Dict("der"=>Dict("bus"=>"b$segments","terminal_map"=>["a","n"],
            "configuration"=>"SINGLE_PHASE","p_min"=>[0.],"p_max"=>[4000.],
            "q_min"=>[0.],"q_max"=>[0.],"s_max"=>[limit==:capability ? 250. : 5000.],"cost"=>[0.])))
    net
end

"""High-voltage branch optimum: U=230-R*I, Pg=2000-U*I, Pgrid=230*I.

All bus lower limits exclude the other constant-power root. On the admitted
voltage interval, increasing generation reduces source import monotonically.
Positive I denotes import; current and voltage cases have reverse flow.
"""
function expected(limit)
    r=.2+inv(inv(.3)+inv(2.))
    i=limit==:capability ? (230-sqrt(230^2-4r*1750))/(2r) :
      limit==:current ? -5. : limit==:voltage ? -2/r : throw(ArgumentError("unknown active limit"))
    u=230-r*i
    (;loop_resistance_ohm=r,current_A=i,voltage_V=u,generator_W=2000-u*i,source_W=230i)
end
end
