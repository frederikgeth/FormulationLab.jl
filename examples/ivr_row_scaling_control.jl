"""Diagnostic Ipopt row-scaling controls; no production option defaults change."""
module IVRRowScalingControl

"""Hold a positive objective-gradient target while changing only the row cutoff.

The caller must verify the objective scale and actual row scales from the solve.
The native baseline is reproduced only when its starting objective-gradient norm
exceeds `target` and its standard scaling cutoff was `target`.
"""
function settings(;unit_rows=false,target=100.0)
    isfinite(target) && target>0 || throw(ArgumentError("positive finite target required"))
    (;nlp_scaling_method="gradient-based",nlp_scaling_obj_target_gradient=Float64(target),
      nlp_scaling_max_gradient=unit_rows ? 1e300 : Float64(target),nlp_scaling_min_value=1e-8)
end

"""Verify captured scaled/unscaled TNLP arrays against declared scales.

This checks objective/constraint scaling, not equality of internal initial slacks.
Native vectors must separately establish that initialization comparison.
"""
function verify(record,objective_scale,row_scales;atol=1e-10)
    isfinite(objective_scale) && objective_scale>0 || throw(ArgumentError("invalid objective scale"))
    all(x->isfinite(x)&&x>0,row_scales) || throw(ArgumentError("invalid row scales"))
    s=record.scaled;u=record.unscaled
    length(row_scales)==length(s.lambda)==length(u.lambda) || error("row dimension mismatch")
    gap(a,b)=begin
        length(a)==length(b) || error("array dimension mismatch")
        all(isfinite,a) && all(isfinite,b) || error("nonfinite state")
        maximum(abs.(a.-b)./max.(1.,abs.(a),abs.(b));init=0.)
    end
    gaps=(;x=gap(s.x,u.x),z_L=gap(s.z_L,objective_scale.*u.z_L),
           z_U=gap(s.z_U,objective_scale.*u.z_U),
           lambda=gap(s.lambda,objective_scale.*u.lambda./row_scales),
           g=gap(s.g,row_scales.*u.g))
    maximum(values(gaps))<=atol || error("scaling verification failed: $gaps")
    (;passed=true,gaps,objective_scale,timing_eligible=false)
end
end
