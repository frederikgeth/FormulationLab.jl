# Independent electrical checks: closed-form impedance-load circuits and
# prescribed ideal winding ratios, not a second implementation of the SDP.
function _sdp_tx_case(kind; tap=1.0)
    if kind in ("single_phase","single_phase_autotransformer")
        mf=["p","n"];mt=["p","n"];v=[230.0,0.0];angles=[0.0,0.0];vf=230.0;vt=115.0
    elseif kind=="center_tap"
        mf=["p","n"];mt=["x1","n","x2"];v=[240.0,0.0];angles=[0.0,0.0];vf=240.0;vt=120.0
    elseif kind=="wye_delta"
        mf=["a","b","c","n"];mt=["a","b","c"];v=[230.0,230.0,230.0,0.0]
        angles=[0.0,-2pi/3,2pi/3,0.0];vf=230.0;vt=115.0
    else
        mf=["a","b","c"];mt=kind=="delta_wye" ? ["a","b","c","n"] : copy(mf)
        v=fill(230.0,3);angles=[0.0,-2pi/3,2pi/3];vf=230.0;vt=115.0
    end
    bus=Dict("f"=>Dict{String,Any}("terminal_names"=>mf,"perfectly_grounded_terminals"=>filter(==("n"),mf)),
             "t"=>Dict{String,Any}("terminal_names"=>mt,"perfectly_grounded_terminals"=>filter(==("n"),mt)))
    # A delta-only secondary has a free common-mode voltage. Ground a declared
    # terminal for these analytical cases, rather than inserting an artificial gauge.
    kind=="wye_delta" && (bus["t"]["perfectly_grounded_terminals"]=["c"])
    tx=Dict{String,Any}("bus_from"=>"f","bus_to"=>"t","terminal_map_from"=>mf,"terminal_map_to"=>mt)
    if kind in ("single_phase_autotransformer","open_delta_regulator")
        tx["tap_ratio"]=kind=="open_delta_regulator" ? [tap,1/tap] : tap
        tx["regulator_type"]="B"
        kind=="open_delta_regulator" && (tx["connection"]="ABBC")
    else
        merge!(tx,Dict("v_nom_from"=>vf,"v_nom_to"=>vt,"tap"=>tap))
    end
    Dict{String,Any}("bus"=>bus,"transformer"=>Dict(kind=>Dict("tx"=>tx)),
        "voltage_source"=>Dict("s"=>Dict("bus"=>"f","terminal_map"=>mf,"v_magnitude"=>v,"v_angle"=>angles)))
end
function _sdp_zload!(net,id,tm,y)
    get!(net,"load",Dict{String,Any}())[id]=Dict("bus"=>"t","terminal_map"=>tm,
        "configuration"=>"SINGLE_PHASE","model"=>"constant_impedance",
        "v_nom"=>[100.0],"p_nom"=>[real(y)*1e4],"q_nom"=>[-imag(y)*1e4])
end
