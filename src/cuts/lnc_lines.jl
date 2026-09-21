# Conservative physical bounds; no nominal-angle assumptions or power-flow samples.
function _lnc_voltage_bounds(net,bus,row,terminal_rows,fixed)
    if all(haskey(fixed,k) for k in keys(row))
        value=abs(sum((c*fixed[k] for (k,c) in row);init=0im))
        return value,value
    end
    lo,hi=_sdp_load_range(net,bus,row,terminal_rows,1.0)
    sqrt(lo),sqrt(hi)
end
_lnc_abs_sum(coeff,bounds)=sum((abs(c)*v for (c,v) in zip(coeff,bounds) if !iszero(c));init=0.0)

function _add_line_lncs!(build,lines,terminal_rows,fixed;voltage_range=nothing)
    physical_bounds(bus,row)=voltage_range===nothing ? _lnc_voltage_bounds(build.network,bus,row,terminal_rows,fixed) : voltage_range(row)
    net=build.network;neutral=_kr_neutral_map(net)
    for line in lines
        (;id,from,to,tmf,tmt,vf,vt,Z,Yf,Yt,ratings)=line
        n=length(vf)
        ni=findfirst(==(get(neutral,from,nothing)),tmf)
        nj=findfirst(==(get(neutral,to,nothing)),tmt)
        phases=[k for k in 1:n if k!=ni && k!=nj]
        pairs=Tuple{String,Vector{Float64}}[]
        for k in phases
            d=zeros(n);d[k]=1
            ni!==nothing && ni==nj && (d[ni]=-1)
            push!(pairs,("$(tmf[k])-$(tmt[k])",d))
        end
        # Phase-pair voltages are especially useful for delta-connected devices.
        for k in eachindex(phases),h in k+1:length(phases)
            d=zeros(n);d[phases[k]]=1;d[phases[h]]=-1
            push!(pairs,("pair-$(tmf[phases[k]])-$(tmf[phases[h]])",d))
        end
        current = if hasproperty(line, :series_current)
            line.series_current
        else
            highf=[last(physical_bounds(from,r)) for r in vf]
            hight=[last(physical_bounds(to,r)) for r in vt]
            imax=get(ratings,"i_max",nothing)
            imax===nothing ? fill(Inf,n) : [min(
                imax[k]+_lnc_abs_sum(Yf[k,:],highf),
                imax[k]+_lnc_abs_sum(Yt[k,:],hight)) for k in 1:n]
        end
        for (name,d) in pairs
            key="line/$id/$name"
            provenance="Coupled line voltage drop; declared or apparent-power-derived endpoint current bounds; bounded pi-shunt currents; physical voltage bounds"
            a=_SDPRow();b=_SDPRow()
            for k in 1:n;_sdp_add!(a,vf[k],d[k]);_sdp_add!(b,vt[k],d[k]);end
            lu,hu=physical_bounds(from,a)
            lv,hv=physical_bounds(to,b)
            reason = if !(0<lu<=hu<Inf && 0<lv<=hv<Inf)
                "missing positive lower or finite upper magnitude bound"
            elseif !any(isfinite,current)
                "missing endpoint current ratings or apparent-power-derived current bounds"
            else
                ""
            end
            epsilon=_lnc_abs_sum(vec(transpose(d)*Z),current)
            isempty(reason) && !isfinite(epsilon) && (reason="unbounded series current after pi-shunt correction")
            isempty(reason) && iszero(epsilon) && (reason="zero voltage drop already enforced by electrical equations")
            bounds=nothing
            if isempty(reason)
                # Modest outward padding guards ordinary coefficient roundoff;
                # these Float64 bounds are not interval-arithmetic certificates.
                lu*=1-1e-12;lv*=1-1e-12;hu*=1+1e-12;hv*=1+1e-12
                ratio=epsilon*(1+1e-12)/(2sqrt(lu*lv))
                if ratio>=sqrt(0.5)
                    reason="derived angle sector is not narrower than π"
                else
                    delta=2asin(ratio)
                    bounds=LNCBounds((lu,hu),(lv,hv),(-delta,delta))
                end
            end
            if !isempty(reason)
                push!(build.lnc_diagnostics,LNCDiagnostic(key,:skipped,:derived,provenance,reason,nothing))
                continue
            end
            u=VoltagePhasor(Dict((from,tmf[k])=>d[k] for k in 1:n if !iszero(d[k])))
            v=VoltagePhasor(Dict((to,tmt[k])=>d[k] for k in 1:n if !iszero(d[k])))
            add_voltage_lnc!(build,VoltageLNC(key,u,v,bounds;origin=:derived,provenance))
        end
    end
end
