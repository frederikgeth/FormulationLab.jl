# Exact voltage-dependent powers on physical connection coils. A positive
# engineering voltage domain is required; no epsilon or nominal-voltage floor.
function _ivrn_check_load(id,d)
    law=lowercase(get(d,"model","constant_power"))
    law in ("constant_current","zip","exponential") || return
    label="load/$id"
    p=get(d,"p_nom",nothing);q=get(d,"q_nom",nothing)
    valid(x)=x isa Real && !(x isa Bool) && isfinite(x)
    p isa AbstractVector && q isa AbstractVector && !isempty(p) &&
        length(p)==length(q) && all(valid,p) && all(valid,q) ||
        _ivrn_refuse("$label requires finite P/Q vectors with matching channels")
    n=length(p)
    function vector(key)
        raw=get(d,key,nothing)
        raw isa Real ? valid(raw) || _ivrn_refuse("$label invalid $key") :
            raw isa AbstractVector && all(valid,raw) || _ivrn_refuse("$label requires finite $key")
        _sdp_vector(d,key,n)
    end
    all(>(0),vector("v_nom")) || _ivrn_refuse("$label requires positive coil v_nom")
    zipkeys=("alpha_z","alpha_i","alpha_p","beta_z","beta_i","beta_p")
    expkeys=("gamma_p","gamma_q")
    extras=law=="zip" ? expkeys : law=="exponential" ? zipkeys : (zipkeys...,expkeys...)
    any(haskey(d,k) for k in extras) && _ivrn_refuse("$label coefficients do not match $law")
    if law=="zip"
        for prefix in ("alpha","beta")
            fractions=[vector(prefix*suffix) for suffix in ("_z","_i","_p")]
            all(x->all(>=(0),x),fractions) && all(isapprox.(sum(fractions),1.;atol=1e-10,rtol=0)) ||
                _ivrn_refuse("$label ZIP fractions must be nonnegative and sum to one per channel")
        end
    elseif law=="exponential"
        vector("gamma_p");vector("gamma_q")
    end
end

function _ivrn_load_law!(model,id,d,rows,p,q,z,z0,e,voltage_range)
    n=length(rows);vn=_sdp_vector(d,"v_nom",n)
    pn=_sdp_vector(d,"p_nom",n);qn=_sdp_vector(d,"q_nom",n)
    law=lowercase(d["model"]);observations=Any[]
    for k in 1:n
        row=rows[k];lo,hi=voltage_range(row)
        isfinite(lo) && 0<lo<=hi ||
            _ivrn_refuse("load/$id channel $k requires a positive lower bound on its coil voltage or a fixed nonzero source phasor")
        scale=(e.vb/vn[k])^2
        # Equal engineering bounds also fix the magnitude. Evaluate the law
        # directly; a fixed auxiliary plus its defining equality would add a
        # redundant equality to an otherwise square power-flow NLP.
        if lo==hi
            x=(lo/vn[k])^2
        else
            x=@variable(model,lower_bound=(lo/vn[k])^2,base_name="load_$(id)_v2_$k")
            isfinite(hi) && JuMP.set_upper_bound(x,(hi/vn[k])^2)
            JuMP.set_start_value(x,clamp(abs2(_linivr_eval(row,z0))*scale,(lo/vn[k])^2,(hi/vn[k])^2))
            u=_linivr_eval(row,z)
            @constraint(model,x==scale*(real(u)^2+imag(u)^2))
            push!(observations,(;variable=x,row,scale))
        end
        factor(prefix,gamma)=if law=="constant_current"
            sqrt(x)
        elseif law=="zip"
            _sdp_vector(d,prefix*"_z",n)[k]*x+
                _sdp_vector(d,prefix*"_i",n)[k]*sqrt(x)+_sdp_vector(d,prefix*"_p",n)[k]
        else
            a=_sdp_vector(d,gamma,n)[k]/2
            a==0 ? 1.0 : a==1 ? x : x^a
        end
        fp=factor("alpha","gamma_p");fq=factor("beta","gamma_q")
        @constraint(model,p[k]==pn[k]/e.sb*fp)
        @constraint(model,q[k]==qn[k]/e.sb*fq)
    end
    observations
end
