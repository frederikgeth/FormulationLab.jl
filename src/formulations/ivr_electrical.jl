# Optional provenance records never change a stamped row or its insertion order.
# Multipliers undo any normalization performed inside a physical stamp.
function _sdp_record_equation!(records,equations,label,unit;multiplier=1.0)
    records===nothing && return nothing
    push!(records,(;index=length(equations),label,unit,assembly_multiplier=Float64(multiplier)))
    nothing
end

# Sources are recorded at stamping time, never inferred from coincident rows.
_sdp_limit_source(path,value;interpretation=:per_channel,divisor=1)=
    (;path=Tuple(path),declared=deepcopy(value),interpretation,divisor)
function _sdp_record_limit!(records,limits;label,family,id,side=nothing,winding=nothing,
                           voltage_basis,current_basis,channels=nothing,sources)
    records===nothing && return nothing
    v,i,d=last(limits)
    Set(keys(sources))==Set(k for k in ("i_max","s_max") if haskey(d,k)) || error("incomplete equipment limit provenance")
    channels===nothing && (channels=collect(eachindex(v)))
    length(channels)==length(v)==length(i) || error("equipment provenance channel mismatch")
    push!(records,(;index=length(limits),label,family,id,side,winding,voltage_basis,current_basis,
        channels=collect(channels),sources))
    nothing
end

# Shared, solver-independent current–voltage circuit assembly. All coordinates
# are per unit; ideal grounds are fixed at zero, finite grounds remain shunts.
# No Kron reduction, power approximation, lifting, or operational-bound tightening.
function _ivr_electrical_data(net; s_base, shunt_coordinates=:admittance,
                              line_records=false, delta_dispatch=:conductor,
                              source_mode=:homogeneous, ibr_delta_dispatch=delta_dispatch,
                              record_transformer_bonds=false,record_transformer_currents=false,record_equations=false,record_limits=false)
    delta_dispatch in (:conductor,:coil) || throw(ArgumentError("unknown delta dispatch convention"))
    ibr_delta_dispatch in (:conductor,:coil) || throw(ArgumentError("unknown IBR dispatch convention"))
    source_mode in (:homogeneous,:affine) || throw(ArgumentError("unknown source mode"))
    candidates=[d for (_,d) in sort!(collect(net["voltage_source"]);by=first) if any(!iszero,d["v_magnitude"])]
    isempty(candidates) && _sdp_refuse("at least one nonzero reference phasor is required")
    source = first(candidates)
    source_v = Float64.(source["v_magnitude"]) .* cis.(Float64.(source["v_angle"]))
    vb = maximum(abs,source_v); sb = s_base
    isfinite(vb) && vb > 0 || _sdp_refuse("source voltages must be finite with a nonzero magnitude")
    all(isfinite,source_v) || _sdp_refuse("nonfinite source voltage")
    vb = maximum(maximum(abs,Float64.(d["v_magnitude"])) for d in values(net["voltage_source"]))
    ib = sb/vb; zb = vb/ib
    coordinate_count = Ref(0)
    newvar() = (coordinate_count[] += 1)
    voltage = Dict{Tuple{String,String},Int}()
    neutral_map = _kr_neutral_map(net)
    for (b,d) in sort!(collect(net["bus"]);by=first), t in d["terminal_names"]
        voltage[(b,t)] = t in get(d,"perfectly_grounded_terminals",[]) ? 0 : newvar()
    end
    function terminal_rows(bus,tm)
        !isempty(tm) && allunique(tm) || _sdp_refuse("empty or repeated terminal map at $bus")
        all(haskey(voltage,(bus,t)) for t in tm) || _sdp_refuse("undeclared terminal at $bus")
        [_sdp_e(voltage[(bus,t)]) for t in tm]
    end
    kcl = Dict(key => _SDPRow() for (key,i) in voltage if i != 0)
    equations = _SDPRow[]
    equation_metadata = record_equations ? NamedTuple[] : nothing
    limit_metadata = record_limits ? NamedTuple[] : nothing
    function inject(bus,tm,rows,sign=1)
        for (t,row) in zip(tm,rows)
            haskey(kcl,(bus,t)) && _sdp_add!(kcl[(bus,t)],row,sign)
        end
    end
    function matrows(A,rows)
        out = [_SDPRow() for _ in axes(A,1)]
        for i in axes(A,1),j in axes(A,2)
            _sdp_add!(out[i],rows[j],A[i,j])
        end
        out
    end
    function values_for(d,key,n; default=nothing)
        haskey(d,key) || return default
        raw=d[key]; v=raw isa Number ? [Float64(raw)] : Float64.(raw)
        length(v)==n && all(isfinite,v) || _sdp_refuse("$key must have $n finite entries")
        v
    end
    # Constraints recorded as physical channel voltage/current pairs.
    devices = []
    limits = []
    lnc_lines = []
    impedance_loads = []
    transformer_current_balances = []
    nwinding_current_blocks = []
    # Decode shared physical linecodes once per arity within this assembly.
    # Length and per-unit scaling are applied separately to every branch.
    line_matrices_cache = Dict{Tuple{String,Int},NTuple{3,Matrix{ComplexF64}}}()
    function line_matrices(code,n,id)
        function matrix(prefix)
            M=_kr_matrix(code,prefix;label="line/$id")
            M===nothing && return zeros(n,n)
            size(M,1)<=n || _sdp_refuse("line/$id matrix exceeds terminal arity")
            out=zeros(n,n);out[1:size(M,1),1:size(M,2)].=M;out
        end
        (matrix("R_series_")+im*matrix("X_series_"),
         matrix("G_from_")+im*matrix("B_from_"),matrix("G_to_")+im*matrix("B_to_"))
    end
    for (id,l) in sort!(collect(get(net,"line",Dict()));by=first)
        tmf=l["terminal_map_from"]; tmt=l["terminal_map_to"]; n=length(tmf)
        n==length(tmt) || _sdp_refuse("line/$id endpoint arity mismatch")
        vf=terminal_rows(l["bus_from"],tmf); vt=terminal_rows(l["bus_to"],tmt)
        code=haskey(l,"linecode") ? net["linecode"][l["linecode"]] : l
        len=haskey(l,"linecode") ? Float64(get(l,"length",1.0)) : 1.0
        isfinite(len) && len>0 || _sdp_refuse("line/$id length must be positive")
        physical = if haskey(l,"linecode")
            get!(line_matrices_cache,(String(l["linecode"]),n)) do
                line_matrices(code,n,id)
            end
        else
            line_matrices(code,n,id)
        end
        Z=physical[1]*len/zb;Yf=physical[2]*len*zb;Yt=physical[3]*len*zb
        current=[_sdp_e(newvar()) for _ in 1:n]
        drop=matrows(Z,current)
        equation_indices=collect(length(equations)+1:length(equations)+n)
        for k in 1:n
            push!(equations,_sdp_add!(_sdp_add!(copy(vf[k]),vt[k],-1),drop[k],-1))
            _sdp_record_equation!(equation_metadata,equations,"line/$id/drop/$k",:V)
        end
        cf=matrows(Yf,vf); ct=matrows(Yt,vt)
        for k in 1:n;_sdp_add!(cf[k],current[k]);_sdp_add!(ct[k],current[k],-1);end
        inject(l["bus_from"],tmf,cf);inject(l["bus_to"],tmt,ct)
        ratings=Dict(k=>get(l,k,get(code,k,nothing)) for k in ("i_max","s_max") if haskey(l,k)||haskey(code,k))
        current_ratings=Dict(k=>ratings[k] for k in ("i_max",) if haskey(ratings,k))
        rating_source(k)=_sdp_limit_source(haskey(l,k) ? ("line",id,k) : ("linecode",l["linecode"],k),ratings[k])
        for (side,v,i) in ((:from,vf,cf),(:to,vt,ct))
            push!(limits,(v,i,current_ratings))
            _sdp_record_limit!(limit_metadata,limits;label="line/$id/$side",family=:line,id,side,
                voltage_basis=:terminal_to_ground,current_basis=:terminal,
                sources=Dict(k=>rating_source(k) for k in keys(current_ratings)))
        end
        if haskey(ratings,"s_max")
            neutral=get(neutral_map,l["bus_from"],nothing)
            phases=findall(!=(neutral),tmf)
            for (side,v,i) in ((:from,vf,cf),(:to,vt,ct))
                push!(limits,(v[phases],i[phases],Dict("s_max"=>ratings["s_max"])))
                _sdp_record_limit!(limit_metadata,limits;label="line/$id/$side",family=:line,id,side,
                    voltage_basis=:terminal_to_ground,current_basis=:terminal,channels=phases,
                    sources=Dict("s_max"=>rating_source("s_max")))
            end
        end
        line_records && push!(lnc_lines,(;id,from=l["bus_from"],to=l["bus_to"],tmf,tmt,vf,vt,
            Z=Z*zb,Yf=Yf/zb,Yt=Yt/zb,ratings,current,equation_indices))
        # Exactly zero shunts are passive without an eigendecomposition. Keep
        # the existing scaled-matrix numerical test for every nonzero matrix.
        passive=all(M->iszero(M) || minimum(eigvals(Hermitian((M+M')/2));init=0.0)>=0,(Z,Yf,Yt))
        push!(devices,(:line_from,id,vf,cf,Dict("passive"=>passive)));push!(devices,(:line_to,id,vt,ct,Dict()))
    end
    _sdp_stamp_transformers!(net,newvar,terminal_rows,matrows,inject,equations,devices,limits,zb;
                            record_bonds=record_transformer_bonds,neutral_map,equation_metadata,limit_metadata,
                            current_balances=record_transformer_currents ? transformer_current_balances : nothing)
    _sdp_stamp_nwinding!(net,newvar,terminal_rows,matrows,inject,equations,devices,limits,zb;neutral_map,equation_metadata,limit_metadata,
        current_blocks=record_transformer_currents ? nwinding_current_blocks : nothing)
    _sdp_stamp_static!(net,newvar,terminal_rows,matrows,inject,equations,devices,limits,zb;neutral_map,equation_metadata,limit_metadata)
    for (id,d) in get(net,"shunt",Dict())
        rows=terminal_rows(d["bus"],d["terminal_map"])
        Y=_l3f_shunt_matrix(d,length(rows))*zb
        if shunt_coordinates==:current
            currents=_SDPRow[]
            for k in eachindex(rows)
                scale=maximum(abs,Y[k,:];init=0.0)
                if iszero(scale)
                    push!(currents,_SDPRow())
                else
                    j=_sdp_e(newvar());push!(currents,j)
                    equation=_sdp_add!(_SDPRow(),j,1/scale)
                    for h in eachindex(rows);_sdp_add!(equation,rows[h],-Y[k,h]/scale);end
                    push!(equations,equation)
                    _sdp_record_equation!(equation_metadata,equations,"shunt/$id/current/$k",:A;multiplier=scale)
                end
            end
            inject(d["bus"],d["terminal_map"],currents)
        else
            inject(d["bus"],d["terminal_map"],matrows(Y,rows))
        end
    end
    for family in ("load","generator","ibr"), (id,d) in sort!(collect(get(net,family,Dict()));by=first)
        tm=d["terminal_map"]; vr=terminal_rows(d["bus"],tm)
        if family=="ibr"
            _sdp_fields(d,("bus","terminal_map","topology","prime_mover","s_max","i_max","p_avail","p_min","p_max","q_min","q_max",
                "cost","energy_cost_rate","control_profile","voltage_aggregation","dc_link_coupled","p_dc_min","p_dc_max",
                "r_filter","x_filter","b_filter_shunt","grid_forming","v_ref_internal"),"ibr/$id")
            cfg=get(Dict("FOUR_LEG"=>"WYE","THREE_LEG"=>"DELTA","SINGLE_PHASE"=>"SINGLE_PHASE"),get(d,"topology",""),nothing)
            cfg===nothing && _sdp_refuse("ibr/$id unknown topology")
            n=length(d["s_max"])
        else
            cfg=uppercase(d["configuration"])
            nt=get(neutral_map,d["bus"],nothing)
            n=family=="load" ? length(d["p_nom"]) : cfg=="SINGLE_PHASE" ? 1 :
                cfg=="DELTA" ? (length(tm)==2 ? 1 : 3) : count(!=(nt),tm)
        end
        D=_sdp_connection(net,d["bus"],tm,cfg,n;neutral=get(neutral_map,d["bus"],nothing))
        vc=matrows(D,vr); ic=[_sdp_e(newvar()) for _ in 1:n]
        terminal_current=matrows(transpose(D),ic)
        if family=="ibr"
            rf=_sdp_vector(d,"r_filter",n;default=zeros(n));xf=_sdp_vector(d,"x_filter",n;default=zeros(n))
            all(>=(0),rf) || _sdp_refuse("ibr/$id negative filter resistance")
            bf=_sdp_scalar(d,"b_filter_shunt")
            # Port powers are measured at PCC. Filter current also supplies the
            # shunt at PCC; internal voltage is U + Z*(I + jB*U).
            jf=[_sdp_add!(copy(ic[k]),vc[k],im*bf*zb) for k in 1:n]
            internal=[_sdp_add!(copy(vc[k]),jf[k],complex(rf[k],xf[k])/zb) for k in 1:n]
            push!(devices,(:ibr_internal,id,internal,jf,d))
        end
        inject(d["bus"],tm,terminal_current,family=="load" ? 1 : -1)
        if family=="load" && _sdp_is_impedance_load(d)
            p=values_for(d,"p_nom",n);q=values_for(d,"q_nom",n);vn=values_for(d,"v_nom",n)
            vn===nothing && _sdp_refuse("load/$id requires v_nom")
            all(>(0),vn) || _sdp_refuse("load/$id requires positive v_nom")
            first_equation=length(equations)+1
            for k in 1:n
                y=conj(complex(p[k],q[k]))/vn[k]^2*zb
                push!(equations,_sdp_add!(copy(ic[k]),vc[k],-y))
                _sdp_record_equation!(equation_metadata,equations,"load/$id/impedance/$k",:A)
            end
            push!(impedance_loads,(;id,current=ic,equation_indices=collect(first_equation:length(equations))))
        end
        # Preserve the existing SDP conductor-power convention by default.
        # LinIVR selects coil powers, matching BMOPFTools' delta dispatch.
        dispatch=family=="ibr" ? ibr_delta_dispatch : delta_dispatch
        conductor_dispatch=dispatch==:conductor && cfg=="DELTA" && length(tm)==3
        port_v,port_i = family in ("generator","ibr") && conductor_dispatch ?
            (vr,terminal_current) : (vc,ic)
        push!(devices,(Symbol(family),id,port_v,port_i,d))
        if family in ("generator","ibr")
            # Scalar apparent ratings and vector current ratings can coexist.
            bounds=Dict{String,Any}(k=>d[k] for k in ("s_max",) if haskey(d,k))
            if haskey(d,"i_max")
                imax=d["i_max"]
                if cfg=="DELTA" && dispatch==:coil && length(imax)==n
                    bounds["i_max"]=imax
                elseif length(imax)==length(tm)
                    push!(limits,(vr,terminal_current,Dict("i_max"=>imax)))
                    _sdp_record_limit!(limit_metadata,limits;label="$family/$id",family=Symbol(family),id,
                        voltage_basis=:terminal_to_ground,current_basis=:terminal,
                        sources=Dict("i_max"=>_sdp_limit_source((family,id,"i_max"),imax)))
                elseif length(imax)==n
                    bounds["i_max"]=imax
                else
                    _sdp_refuse("$family/$id current ratings must match coils or terminals")
                end
            end
            push!(limits,(port_v,port_i,bounds))
            _sdp_record_limit!(limit_metadata,limits;label="$family/$id",family=Symbol(family),id,
                voltage_basis=conductor_dispatch ? :terminal_to_ground : :connection_coil,
                current_basis=conductor_dispatch ? :terminal : :connection_coil,
                sources=Dict(k=>_sdp_limit_source((family,id,k),d[k]) for k in keys(bounds)))
        end
    end
    tm=source["terminal_map"]; vs=terminal_rows(source["bus"],tm)
    length(source_v)==length(tm) || _sdp_refuse("source phasor arity mismatch")
    anchor_k=findfirst(v -> !iszero(v),source_v)
    anchor=voltage[(source["bus"],tm[anchor_k])]
    anchor!=0 || _sdp_refuse("nonzero prescribed source voltage on a grounded terminal")
    fixed_source_coordinates=Dict{Int,ComplexF64}()
    for (source_id,d) in sort!(collect(net["voltage_source"]);by=first)
        dvolts=Float64.(d["v_magnitude"]).*cis.(Float64.(d["v_angle"]))
        rows=terminal_rows(d["bus"],d["terminal_map"])
        length(rows)==length(dvolts) && all(isfinite,dvolts) || _sdp_refuse("source/$source_id invalid phasors")
        for k in eachindex(rows)
            idx=voltage[(d["bus"],d["terminal_map"][k])]
            if source_mode==:affine
                idx==0 && !iszero(dvolts[k]) && _sdp_refuse("nonzero source voltage on a grounded terminal")
                if haskey(fixed_source_coordinates,idx) && fixed_source_coordinates[idx]!=dvolts[k]/vb
                    _sdp_refuse("inconsistent prescribed source voltages")
                end
            end
            idx!=0 && (fixed_source_coordinates[idx]=dvolts[k]/vb)
            # Exact NLP consumers fix each prescribed coordinate directly.
            source_mode==:affine && continue
            # The first anchor equation is an algebraic tautology.
            d===source && k==anchor_k && continue
            push!(equations,_sdp_add!(copy(rows[k]),vs[anchor_k],-dvolts[k]/source_v[anchor_k]))
            _sdp_record_equation!(equation_metadata,equations,"source/$source_id/phasor/$k",:V)
        end
        # Ideal source ground-terminal current allocation is underdetermined in
        # a common-earth model. Do not manufacture a neutral rating certificate.
        any(isempty,rows) && haskey(d,"i_max") && _sdp_refuse("source ground-terminal current allocation is not implemented")
        is=[isempty(v) ? _SDPRow() : _sdp_e(newvar()) for v in rows]
        inject(d["bus"],d["terminal_map"],is,-1)
        # Power boxes are per phase; current limits, where supported, are per conductor.
        neutral=get(neutral_map,d["bus"],nothing)
        phases=findall(!=(neutral),d["terminal_map"])
        powerdata=copy(d)
        for key in ("p_min","p_max","q_min","q_max")
            haskey(d,key) || continue
            raw=values_for(d,key,length(d[key])==length(rows) ? length(rows) : length(phases))
            # Preserve the full terminal powers for result reporting, including neutral power.
            expanded=fill(key in ("p_min","q_min") ? -Inf : Inf,length(rows))
            length(raw)==length(rows) ? (expanded=raw) : (expanded[phases]=raw)
            powerdata[key]=expanded
        end
        for key in ("cost","energy_cost_rate")
            haskey(d,key) && length(d[key])==length(phases) || continue
            expanded=zeros(length(rows));expanded[phases]=values_for(d,key,length(phases));powerdata[key]=expanded
        end
        push!(devices,(:voltage_source,source_id,rows,is,powerdata));push!(limits,(rows,is,Dict(k=>d[k] for k in ("i_max",) if haskey(d,k))))
        _sdp_record_limit!(limit_metadata,limits;label="source/$source_id",family=:voltage_source,id=source_id,
            voltage_basis=:terminal_to_ground,current_basis=:terminal,
            sources=Dict(k=>_sdp_limit_source(("voltage_source",source_id,k),d[k]) for k in ("i_max",) if haskey(d,k)))
    end
    equation_metadata===nothing || length(equation_metadata)==length(equations) || error("incomplete circuit equation provenance")
    limit_metadata===nothing || length(limit_metadata)==length(limits) || error("incomplete equipment limit provenance")
    (; voltage, equations, equation_metadata, kcl, devices, limits, limit_metadata, lnc_lines, impedance_loads, transformer_current_balances, nwinding_current_blocks, terminal_rows,
       values_for, coordinate_count, newvar, fixed_source_coordinates, neutral_map,
       vs, anchor_k, anchor, source_v, vb, sb, ib, zb)
end
