# A numerical KCL row unit in amperes; never a physical operating bound.
_ivrn_kcl_row_divisor(divisor,current_A,cap)=cap===nothing ? divisor : min(divisor,cap/current_A)

# Reversible finite-ground voltage scaling, after all coordinate elimination.
# Physical assembly, observation channels and bounds remain unchanged.
function _ivrn_ground_coordinates(net,e,maps,mode)
    scaled=NamedTuple[];retained=Dict{String,String}()
    region=mode==:regional_voltage ? _ivrn_region_bases(net,e) : nothing
    report()=(;scaled_terminals=scaled,retained_shunts=retained,region_assignment=region)
    mode==:off && return maps,report()
    scales=ones(length(maps.projection));terminals=Dict{Int,Tuple{String,String}}()
    for (id,s) in sort!(collect(get(net,"shunt",Dict()));by=first)
        if length(s["terminal_map"])!=1
            retained[id]="multi_terminal_shunt";continue
        end
        key=(s["bus"],only(s["terminal_map"]));k=e.voltage[key]
        if k==0 || haskey(e.fixed_source_coordinates,k)
            retained[id]="fixed_voltage";continue
        end
        row=maps.reconstruction[k]
        if length(row)!=1 || only(values(row))!=1
            retained[id]="nonphysical_coordinate";continue
        end
        j=only(keys(row))
        if maps.projection[j]!=_sdp_e(k)
            retained[id]="nonphysical_coordinate";continue
        end
        # Independent of whether nominal transformer coordinates are enabled.
        # With them enabled, this makes the ground coordinate current-like in
        # the same local units, rather than retaining the global admittance.
        zb=region===nothing ? e.zb : (region.bases[s["bus"]]/e.sb)*region.bases[s["bus"]]
        scale=abs(only(_l3f_shunt_matrix(s,1)))*zb
        isfinite(scale) || _ivrn_refuse("shunt/$id has nonfinite per-unit grounding scale")
        if scale<=1
            retained[id]="unit_or_smaller_admittance";continue
        end
        scales[j]=max(scales[j],scale);terminals[j]=key
    end
    isempty(terminals) && return maps,report()
    for j in sort!(collect(keys(terminals)))
        b,t=terminals[j];push!(scaled,(;bus=b,terminal=t,coordinate=j,scale=scales[j]))
    end
    projection=[_SDPRow(k=>a*scales[j] for (k,a) in row) for (j,row) in enumerate(maps.projection)]
    reconstruction=[_SDPRow(k=>a/scales[k] for (k,a) in row) for row in maps.reconstruction]
    if mode==:regional_voltage
        valid(new,old)=all(length(a)==length(b) && all(k->isfinite(a[k]) && (iszero(b[k]) || !iszero(a[k])),keys(b)) for (a,b) in zip(new,old))
        valid(projection,maps.projection) && valid(reconstruction,maps.reconstruction) ||
            _ivrn_refuse("regional ground scaling has unrepresentable coordinate coefficients")
    end
    (;projection,reconstruction),report()
end

# Normalize in the coordinates actually presented to the solver. A row that
# cancels identically under reconstruction needs no normalization.
function _ivrn_scaled_row_norm(row,maps)
    value=norm(collect(values(_ivrn_compose_row(row,maps.reconstruction))))
    isfinite(value) || _ivrn_refuse("nonfinite composed circuit-row norm")
    iszero(value) ? 1.0 : value
end

# Nominal voltage levels select units only. They never alter transformer stamps,
# infer a missing physical reference, or impose an operating voltage.
function _ivrn_region_bases(net,e)
    adjacency=Dict(b=>Tuple{String,Float64}[] for b in keys(net["bus"]))
    skipped=Dict{String,String}()
    function edge(f,t,ratio)
        isfinite(ratio) && ratio>0 && isfinite(inv(ratio)) || return false
        push!(adjacency[f],(t,ratio));push!(adjacency[t],(f,inv(ratio)));true
    end
    for family in ("line","switch"), (id,d) in sort!(collect(get(net,family,Dict()));by=first)
        # Open switches do not establish a voltage-level connection.
        family=="switch" && get(d,"open_switch",false) && continue
        edge(d["bus_from"],d["bus_to"],1.0)
    end
    for (kind,table) in sort!(collect(get(net,"transformer",Dict()));by=first), (id,d) in sort!(collect(table);by=first)
        key="$kind/$id"
        if kind in ("single_phase","center_tap","delta_wye","wye_delta")
            ratio=Float64(d["v_nom_to"])/Float64(d["v_nom_from"])
            edge(d["bus_from"],d["bus_to"],ratio) || (skipped[key]="invalid_nominal_ratio")
        elseif kind in ("single_phase_autotransformer","open_delta_regulator")
            edge(d["bus_from"],d["bus_to"],1.0) # Taps remain in the physical equations.
        else
            skipped[key]="unsupported_nominal_base_contract"
        end
    end
    seeds=Dict(b=>Float64[] for b in keys(adjacency))
    for (_,d) in sort!(collect(net["voltage_source"]);by=first)
        v=maximum(abs,Float64.(d["v_magnitude"]))
        v>0 && push!(seeds[d["bus"]],v)
    end
    bases=Dict{String,Float64}();retained=Dict{String,String}();seen=Set{String}()
    for root in sort!(collect(keys(adjacency)))
        root in seen && continue
        relative=Dict(root=>1.0);queue=[root];consistent=true
        for b in queue
            push!(seen,b)
            for (t,ratio) in sort(adjacency[b];by=first)
                value=relative[b]*ratio
                if !(isfinite(value) && value>0 && isfinite(inv(value)))
                    consistent=false;value=1.0
                end
                if haskey(relative,t)
                    isapprox(relative[t],value;rtol=1e-10,atol=0.) || (consistent=false)
                else
                    relative[t]=value;push!(queue,t)
                end
            end
        end
        anchors=[s/relative[b] for b in sort(queue) for s in seeds[b]]
        reason=!consistent ? "inconsistent_nominal_cycle" : isempty(anchors) ? "no_nonzero_source_base" :
            !all(a->isfinite(a) && a>0 && isapprox(a,first(anchors);rtol=1e-10,atol=0.),anchors) ? "inconsistent_source_bases" : nothing
        if reason===nothing && !all(b->isfinite(relative[b]*first(anchors)) && relative[b]*first(anchors)>0 &&
                isfinite(e.vb/(relative[b]*first(anchors))) && isfinite((relative[b]*first(anchors))/e.vb),queue)
            reason="nonfinite_region_base"
        end
        for b in queue
            bases[b]=reason===nothing ? relative[b]*first(anchors) : e.vb
            reason===nothing || (retained[b]=reason)
        end
    end
    (;bases,retained_buses=retained,skipped_transformers=skipped)
end

"""Explicit power-base seeds propagate through lines and closed switches only.

Transformer boundaries retain independent choices. Unseeded regions use the
assembly power base; conflicting declarations are input errors, not guesses.
"""
function _ivrn_current_power_bases(net,e,seeds)
    all(b->haskey(net["bus"],b),keys(seeds)) || throw(ArgumentError("unknown bus in current_power_bases"))
    all(s->isfinite(s) && s>0,values(seeds)) || throw(ArgumentError("current power bases must be positive and finite"))
    adjacency=Dict(b=>String[] for b in keys(net["bus"]))
    for family in ("line","switch"),d in values(get(net,family,Dict()))
        family=="switch" && get(d,"open_switch",false) && continue
        f=d["bus_from"];t=d["bus_to"];push!(adjacency[f],t);push!(adjacency[t],f)
    end
    bases=Dict{String,Float64}();seen=Set{String}()
    for root in sort!(collect(keys(adjacency)))
        root in seen && continue
        queue=[root];push!(seen,root)
        for b in queue,t in adjacency[b]
            t in seen && continue
            push!(seen,t);push!(queue,t)
        end
        assigned=unique([seeds[b] for b in queue if haskey(seeds,b)])
        length(assigned)<=1 || throw(ArgumentError("conflicting current power bases in one line/switch region"))
        sb=isempty(assigned) ? e.sb : only(assigned)
        for b in queue;bases[b]=sb;end
    end
    bases
end

function _ivrn_transformer_coordinates(net,e,maps,mode,power_seeds=Dict{String,Float64}())
    mode==:off && return maps,(;status=:disabled,bases=Dict{String,Float64}(),
        retained_buses=Dict{String,String}(),skipped_transformers=Dict{String,String}(),
        scaled_coordinates=NamedTuple[],retained_coordinates=Dict{Int,String}())
    region=_ivrn_region_bases(net,e)
    power_bases=_ivrn_current_power_bases(net,e,power_seeds)
    voltage_bases=Dict(k=>region.bases[b] for ((b,_),k) in e.voltage if k!=0)
    current_factors=Dict(k=>(region.bases[b]/e.vb)*(e.sb/power_bases[b]) for ((b,_),k) in e.voltage if k!=0)
    candidates=[Set{Float64}() for _ in 1:e.coordinate_count[]]
    for (k,base) in voltage_bases;push!(candidates[k],e.vb/base);end
    # Device observation rows include all winding/terminal currents. Voltage
    # terms from charging/filter admittances are excluded from current tagging.
    # A bond spanning different bases remains unscaled rather than choosing a side.
    for (_,_,volts,currents,_) in e.devices
        factors=Set(current_factors[k] for row in volts for (k,a) in row if !iszero(a) && haskey(current_factors,k))
        for row in currents, (k,a) in row
            if !iszero(a) && !haskey(voltage_bases,k)
                union!(candidates[k],factors)
            end
        end
    end
    scales=ones(length(maps.projection));scaled=NamedTuple[];retained=Dict{Int,String}()
    for (j,row) in enumerate(maps.projection)
        ks=[k for (k,a) in row if !iszero(a)]
        if isempty(ks) || any(k->isempty(candidates[k]),ks)
            retained[j]="unclassified_coordinate";continue
        end
        values=union((candidates[k] for k in ks)...)
        if length(values)!=1
            retained[j]="mixed_coordinate_bases";continue
        end
        scale=only(values)
        if !(isfinite(scale) && scale>0 && isfinite(inv(scale)))
            retained[j]="nonfinite_coordinate_scale";continue
        end
        scales[j]=scale
        scale==1 || push!(scaled,(;coordinate=j,scale))
    end
    projection=[_SDPRow(k=>a*scales[j] for (k,a) in row) for (j,row) in enumerate(maps.projection)]
    reconstruction=[_SDPRow(k=>a/scales[k] for (k,a) in row) for row in maps.reconstruction]
    # Reject the entire numerical intervention if finite coefficient maps cannot
    # be represented. Never regularize or delete overflowing/underflowing terms.
    valid(new,old)=all(length(a)==length(b) && all(k->isfinite(a[k]) && (iszero(b[k]) || !iszero(a[k])),keys(b)) for (a,b) in zip(new,old))
    if !valid(projection,maps.projection) || !valid(reconstruction,maps.reconstruction)
        return maps,(;status=:retained_nonfinite_map,region...,power_bases,scaled_coordinates=NamedTuple[],retained_coordinates=retained)
    end
    (;projection,reconstruction),(;status=:applied,region...,power_bases,scaled_coordinates=scaled,retained_coordinates=retained)
end
