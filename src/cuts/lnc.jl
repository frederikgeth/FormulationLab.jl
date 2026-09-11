"""Magnitude intervals and an unwrapped relative-angle interval (radians).

Both magnitude lower bounds must be positive and upper bounds finite. The angle
interval must have width less than π; its center may be anywhere on the circle.
"""
struct LNCBounds
    u::Tuple{Float64,Float64}
    v::Tuple{Float64,Float64}
    angle::Tuple{Float64,Float64}
    function LNCBounds(u,v,angle)
        all(length(x)==2 for x in (u,v,angle)) || throw(ArgumentError("LNC intervals require two endpoints"))
        a,b,t=Tuple(Float64.(u)),Tuple(Float64.(v)),Tuple(Float64.(angle))
        all(isfinite,(a...,b...,t...)) || throw(ArgumentError("LNC bounds must be finite"))
        0<a[1]<=a[2] && 0<b[1]<=b[2] || throw(ArgumentError("LNC magnitudes require 0 < lower <= upper"))
        0<=t[2]-t[1]<Float64(pi) || throw(ArgumentError("LNC angle interval must be ordered, unwrapped, and narrower than π"))
        new(a,b,t)
    end
end

"""Add the two lifted nonlinear cuts and, by default, their magnitude/sector domain.

`wu`, `wv`, `wr`, `wi` represent |u|², |v|², Re(u*conj(v)), Im(u*conj(v)).
They may be JuMP affine expressions. Bounds and expressions must use matching
units. Cuts are normalized by the two upper magnitudes and introduce no variables
or nonlinear cones. `include_domain=false` requires the caller to enforce the
stated domain separately. Returns named tuples of constraint references.
"""
function add_lnc!(model,wu,wv,wr,wi,bounds::LNCBounds;include_domain=true)
    all(x->x isa Union{Real,JuMP.AbstractVariableRef,JuMP.GenericAffExpr{<:Real}},(wu,wv,wr,wi)) ||
        throw(ArgumentError("LNC products must be real affine expressions"))
    lu=bounds.u[1]/bounds.u[2];lv=bounds.v[1]/bounds.v[2]
    # Normalize products separately to avoid fourth-power voltage coefficients.
    x=wu/bounds.u[2]^2;y=wv/bounds.v[2]^2
    re=wr/(bounds.u[2]*bounds.v[2]);impart=wi/(bounds.u[2]*bounds.v[2])
    phi=bounds.angle[1]/2+bounds.angle[2]/2;delta=(bounds.angle[2]-bounds.angle[1])/2
    c=cos(phi)*re+sin(phi)*impart;t=-sin(phi)*re+cos(phi)*impart
    k=cos(delta);su=1+lu;sv=1+lv
    upper=@constraint(model,su*sv*c-k*sv*x-k*su*y >= k*(lu*lv-1))
    lower=@constraint(model,su*sv*c-lv*k*sv*x-lu*k*su*y >= lu*lv*k*(1-lu*lv))
    domain=JuMP.ConstraintRef[]
    if include_domain
        for (w,l) in ((x,lu),(y,lv))
            if l==1
                push!(domain,@constraint(model,w==1))
            else
                push!(domain,@constraint(model,w>=l^2));push!(domain,@constraint(model,w<=1))
            end
        end
        push!(domain,@constraint(model,c>=0))
        if delta==0
            push!(domain,@constraint(model,t==0))
        else
            push!(domain,@constraint(model,k*t<=sin(delta)*c))
            push!(domain,@constraint(model,-k*t<=sin(delta)*c))
        end
    end
    (;cuts=(upper,lower),domain)
end

"""A complex linear map of physical terminal voltages.

Use `VoltagePhasor(bus, phase; return_terminal="n")` for a phase-neutral voltage,
or a dictionary `(bus,terminal)=>coefficient` for delta/sequence/other maps.
"""
struct VoltagePhasor
    terms::Dict{Tuple{String,String},ComplexF64}
    function VoltagePhasor(terms::AbstractDict)
        out=Dict{Tuple{String,String},ComplexF64}()
        for (key,value) in terms
            length(key)==2 || throw(ArgumentError("phasor keys require (bus,terminal)"))
            isfinite(value) || throw(ArgumentError("nonfinite phasor coefficient"))
            iszero(value) || (out[(String(key[1]),String(key[2]))]=ComplexF64(value))
        end
        isempty(out) && throw(ArgumentError("phasor map must not be empty"))
        new(out)
    end
end
function VoltagePhasor(bus::AbstractString,phase::AbstractString;return_terminal=nothing)
    terms=Dict((String(bus),String(phase))=>1.0+0im)
    if return_terminal!==nothing
        key=(String(bus),String(return_terminal));terms[key]=get(terms,key,0im)-1
    end
    VoltagePhasor(terms)
end

"""Explicit voltage-pair domain and its LNCs.

`origin=:operating_limit` adds a stated domain to the OPF problem. `:derived`
records the caller's assertion that the bounds follow from the original problem;
FormulationLab does not prove external assertions. Supply a provenance description.
"""
struct VoltageLNC
    id::String
    u::VoltagePhasor
    v::VoltagePhasor
    bounds::LNCBounds
    origin::Symbol
    provenance::String
    function VoltageLNC(id,u,v,bounds;origin=:operating_limit,provenance)
        origin in (:operating_limit,:derived) || throw(ArgumentError("invalid LNC origin"))
        isempty(strip(provenance)) && throw(ArgumentError("LNC provenance must not be empty"))
        new(String(id),u,v,bounds,origin,String(provenance))
    end
end

"""Applied/skipped LNC pair, its bound provenance, and any reason for skipping."""
struct LNCDiagnostic
    id::String
    status::Symbol
    origin::Symbol
    provenance::String
    reason::String
    bounds::Union{Nothing,LNCBounds}
end

function _lnc_row(phasor::VoltagePhasor,indices)
    row=_SDPRow()
    for (key,c) in phasor.terms
        haskey(indices,key) || throw(ArgumentError("unknown voltage terminal $key"))
        _sdp_add!(row,_sdp_e(indices[key]),c)
    end
    row
end
function _lnc_lift(H,N,a,b)
    ca=zeros(ComplexF64,size(N,2));cb=copy(ca)
    for (i,c) in a;ca .+= c.*N[i,:];end
    for (i,c) in b;cb .+= c.*N[i,:];end
    sum(ca[i]*conj(cb[j])*H[i,j] for i in eachindex(ca),j in eachindex(cb))
end

"""Return the physical squared magnitudes and complex cross-product of two voltage maps."""
function phasor_products(build,u::VoltagePhasor,v::VoltagePhasor)
    a=_lnc_row(u,build.voltage_indices);b=_lnc_row(v,build.voltage_indices)
    f(x,y)=build.voltage_base^2*_lnc_lift(build.moment,build.nullspace,x,y)
    (;wu=real(f(a,a)),wv=real(f(b,b)),cross=f(a,b))
end

"""Add an explicit voltage LNC to an existing SDP build and record its domain provenance."""
function add_voltage_lnc!(build,spec::VoltageLNC)
    any(d->d.id==spec.id,build.lnc_diagnostics) && throw(ArgumentError("duplicate LNC id $(spec.id)"))
    p=phasor_products(build,spec.u,spec.v)
    refs=add_lnc!(build.model,p.wu,p.wv,real(p.cross),imag(p.cross),spec.bounds)
    push!(build.lnc_diagnostics,LNCDiagnostic(spec.id,:applied,spec.origin,spec.provenance,"",spec.bounds))
    refs
end
