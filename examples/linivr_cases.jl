# Deterministic unreduced four-wire circuits for tests and the exploratory panel.
# Ohms and SI powers; all lines retain full phase/neutral mutual coupling.
function linivr_case(;segments=4,loading=1.0,ground=Inf,dispatch=false,delta=false)
    tm=["a","b","c","n"]
    buses=Dict{String,Any}("b0"=>Dict{String,Any}("terminal_names"=>tm,"perfectly_grounded_terminals"=>["n"]))
    lines=Dict{String,Any}();loads=Dict{String,Any}();shunts=Dict{String,Any}()
    code=Dict{String,Any}("i_max"=>[250.,250.,250.,150.])
    for a in 1:4,b in a:4
        code["R_series_$(a)_$(b)"]=a==b ? (a==4 ? .12 : .08) : .015
        code["X_series_$(a)_$(b)"]=a==b ? .04 : .01
    end
    for k in 1:segments
        bus="b$k"
        buses[bus]=Dict("terminal_names"=>copy(tm),"vpn_min"=>fill(180.,3),
            "vpn_max"=>fill(253.,3),"vn_max"=>dispatch ? 6.0 : 40.0)
        lines["l$k"]=Dict("bus_from"=>"b$(k-1)","bus_to"=>bus,
            "terminal_map_from"=>copy(tm),"terminal_map_to"=>copy(tm),"linecode"=>"wire")
        p=loading.*[4000.,1500.,500.]
        loads["d$k"]=Dict("bus"=>bus,"terminal_map"=>delta ? tm[1:3] : copy(tm),
            "configuration"=>delta ? "DELTA" : "WYE","model"=>"constant_power","p_nom"=>p,"q_nom"=>.25p)
        if isfinite(ground)
            shunts["earth$k"]=Dict("bus"=>bus,"terminal_map"=>["n"],"G_1_1"=>1/ground)
        end
    end
    net=Dict{String,Any}("bus"=>buses,"line"=>lines,"linecode"=>Dict("wire"=>code),
        "load"=>loads,"shunt"=>shunts,"terminal_conventions"=>Dict("phase"=>tm[1:3],"neutral"=>["n"]),
        "voltage_source"=>Dict("source"=>Dict("bus"=>"b0","terminal_map"=>copy(tm),
            "v_magnitude"=>[230.,230.,230.,0.],"v_angle"=>[0.,-2pi/3,2pi/3,0.],"cost"=>ones(3))))
    if dispatch
        net["generator"]=Dict("der"=>Dict("bus"=>"b$segments","terminal_map"=>["a","n"],
            "configuration"=>"SINGLE_PHASE","p_min"=>[0.],"p_max"=>[20_000.],
            "q_min"=>[-5000.],"q_max"=>[5000.],"cost"=>[.5]))
    end
    net
end

function linivr_ibr_case(topology)
    tm=topology=="SINGLE_PHASE" ? ["a","n"] : topology=="FOUR_LEG" ? ["a","b","c","n"] : ["a","b","c"]
    n=topology=="SINGLE_PHASE" ? 1 : 3
    v=topology=="SINGLE_PHASE" ? ComplexF64[230,0] : 230cis.([0.,-2pi/3,2pi/3])
    topology=="FOUR_LEG" && push!(v,0)
    ps=topology=="SINGLE_PHASE" ? [200.] : [100.,200.,300.]
    net=Dict{String,Any}("bus"=>Dict("b"=>Dict{String,Any}("terminal_names"=>tm,"perfectly_grounded_terminals"=>filter(==("n"),tm))),
        "voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>tm,"v_magnitude"=>abs.(v),"v_angle"=>angle.(v))),
        "ibr"=>Dict("pv"=>Dict{String,Any}("bus"=>"b","terminal_map"=>tm,"topology"=>topology,
            "s_max"=>fill(1000.,n),"i_max"=>fill(10.,length(tm)),"p_min"=>ps,"p_max"=>ps,
            "q_min"=>fill(40.,n),"q_max"=>fill(40.,n),"r_filter"=>fill(.2,n),
            "x_filter"=>fill(.1,n),"b_filter_shunt"=>.0001)))
    net
end
