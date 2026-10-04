# Synthetic, unreduced cases for the exact-IVR compiler tests and timings.
# Total demand is fixed while size/depth changes; there is no dataset license.
function ivr_compiler_case(;conductors=4,segments=4,shape=:chain,loading=1.)
    conductors in (2,3,4) || throw(ArgumentError("conductors must be 2, 3 or 4"))
    segments>0 || throw(ArgumentError("segments must be positive"))
    shape in (:chain,:tree) || throw(ArgumentError("shape must be :chain or :tree"))
    m=conductors;tm=m==2 ? ["a","n"] : m==3 ? ["a","b","c"] : ["a","b","c","n"]
    neutral=m==3 ? String[] : ["n"]
    n=m==2 ? 1 : 3
    buses=Dict{String,Any}("b0"=>Dict("terminal_names"=>copy(tm),"perfectly_grounded_terminals"=>neutral))
    lines=Dict{String,Any}();loads=Dict{String,Any}();code=Dict{String,Any}("i_max"=>fill(200.,m))
    for a in 1:m,b in a:m
        code["R_series_$(a)_$(b)"]=a==b ? .08+.01a : .01+.001(a+b)
        code["X_series_$(a)_$(b)"]=a==b ? .04+.002a : .008+.0001(a+b)
    end
    for k in 1:segments
        b="b$k";parent=shape==:chain ? k-1 : (k-1)÷2
        buses[b]=Dict{String,Any}("terminal_names"=>copy(tm))
        if m==3
            buses[b]["vpp_min"]=fill(300.,3);buses[b]["vpp_max"]=fill(440.,3)
        else
            buses[b]["vpn_min"]=fill(180.,n);buses[b]["vpn_max"]=fill(260.,n);buses[b]["vn_max"]=[30.]
        end
        lines["l$k"]=Dict("bus_from"=>"b$parent","bus_to"=>b,
            "terminal_map_from"=>copy(tm),"terminal_map_to"=>copy(tm),"linecode"=>"wire")
        p=(loading/segments).*(m==2 ? [2000.] : [2000.,750.,250.])
        loads["d$k"]=Dict("bus"=>b,"terminal_map"=>copy(tm),
            "configuration"=>m==2 ? "SINGLE_PHASE" : m==3 ? "DELTA" : "WYE",
            "model"=>"constant_power","p_nom"=>p,"q_nom"=>.25p)
    end
    v=m==2 ? ComplexF64[230,0] : 230cis.([0.,-2pi/3,2pi/3])
    m==4 && push!(v,0im)
    Dict{String,Any}("bus"=>buses,"line"=>lines,"linecode"=>Dict("wire"=>code),"load"=>loads,
        "terminal_conventions"=>Dict("phase"=>filter(!=("n"),tm),"neutral"=>neutral),
        "voltage_source"=>Dict("source"=>Dict("bus"=>"b0","terminal_map"=>copy(tm),
            "v_magnitude"=>abs.(v),"v_angle"=>angle.(v),"cost"=>ones(n))))
end
