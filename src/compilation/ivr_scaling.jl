# Reversible finite-ground voltage scaling, after all coordinate elimination.
# Physical assembly, observation channels and bounds remain unchanged.
function _ivrn_ground_coordinates(net,e,maps,mode)
    scaled=NamedTuple[];retained=Dict{String,String}()
    report()=(;scaled_terminals=scaled,retained_shunts=retained)
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
        scale=abs(only(_l3f_shunt_matrix(s,1)))*e.zb
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
    (;projection,reconstruction),report()
end

# Normalize in the coordinates actually presented to the solver. A row that
# cancels identically under reconstruction needs no normalization.
function _ivrn_scaled_row_norm(row,maps)
    value=norm(collect(values(_ivrn_compose_row(row,maps.reconstruction))))
    iszero(value) ? 1.0 : value
end
