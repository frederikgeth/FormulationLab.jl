"""Experimental exact static IVR options. Approximate network reduction is never applied.

Supports lines, fixed switches/sources/capacitors, fixed transformers/regulators, shunts/grounds, constant-power/impedance loads
and current/ZIP/exponential power laws on certified positive coil-voltage domains
and generator boxes with coil-based delta dispatch. Static IBRs use conductor-rated
THREE_LEG dispatch, fixed filters, capability bounds and optional internal-voltage
setpoints; control profiles are unsupported. Legacy `:cost` prices are linear, in the
same currency/kWh convention as LinIVR. An optimizer is supplied by the caller.
`objective_scale=nothing` divides the physical objective by `s_base` as before;
a positive explicit divisor separates objective normalization from electrical units.
`objective=:power` uses explicit `IVRPowerTerm` entries in `power_terms`, with
physical W/var targets and coefficients. It does not add legacy device costs.
`current_power_bases=Dict(bus=>VA, ...)` seeds current-unit power bases through
lines and closed switches, stopping at transformers. It requires nominal transformer
coordinates. Unseeded regions retain `s_base`; conflicts are refused.
`generator_power_bases=Dict(generator_id=>VA, ...)` independently sets both P and Q
dispatch units per generator (all native channels). Unspecified generators retain
`s_base`. It changes neither circuit-current nor lifted-power/ground units.
Bounds, prices, starts and results keep their SI contracts.
`specialization=:conductor_difference` attempts a certified radial zero-sum
current reduction and retains reference-conductor voltages. Ineligible networks
fall back to full IVR with a reason in the build diagnostics.
`:conductor_regions` instead certifies pendant radial regions behind retained
boundary buses, leaving other circuits physical. The default is :off.
`linear_elimination=:impedance_loads` substitutes exact impedance-load currents;
`:passive` also eliminates certified nonadjacent device-free degree-two buses
between unshunted lines. `:passive_chains` additionally permits adjacent buses
using surviving unit-pivot equations. `:passive_blocks` additionally allows
charged pi sections using conditioned local block solves. `:passive_hybrid` uses
the same block certificate but caps connected groups of eliminated original buses
at `passive_component_limit` (default 4). This is not a bound on expression support
or factorization fill. All preserve physical observations and
operating bounds and compose with conductor specialization. The default is :off.
`series_selection=:bound_support` retains a candidate series bus if any affected
operating bound would depend on more solver coordinates. Default :all.
`ground_scaling=:voltage` rescales retained free voltages attached to stiff
one-terminal finite shunts and normalizes circuit rows in solver coordinates.
This invertible numerical policy preserves the finite ground; default :off.
`:regional_voltage` instead selects the shunt multiplier using nominal regional
voltage bases and the common power base, independently of transformer scaling.
`:regional_multiwinding_voltage` also propagates multiwinding characteristic
voltage units when selecting that multiplier; it creates no physical reference.
Uncertain regional assignments retain the global base with diagnostics.
`transformer_scaling=:nominal` composes local voltage/current units inferred
from source magnitudes and nominal winding ratios. Uncertain assignments retain
the global base with diagnostics. `:nominal_multiwinding` additionally propagates
WYE/SINGLE_PHASE coil nominals and DELTA coil nominals divided by √3; these are
characteristic units, never an inferred ground reference. `:regional_voltage`
retains its independent ordinary-transformer policy. `row_scaling=:composed` independently normalizes
linear circuit rows after all coordinate maps; default :legacy retains the
previous ground-dependent normalization. Neither option changes physical data.
`kcl_row_max_base` optionally caps the ampere unit of each retained complex KCL
row: its existing divisor is limited to `kcl_row_max_base / current_A`.
The positive cap changes numerical equality scaling only, never an operating
current limit. `nothing` preserves existing normalization. It does not cap
omitted KCL rows or guarantee recovered SI accuracy; retain physical audits.
`lifting=:powers` introduces exact P/Q definitions for apparent-power limits
and selected non-generator objective ports.
`:bounded_observations` also materializes compound bounded voltage/current rows.
`lifted_power_base` optionally sets the common VA unit of power auxiliaries;
`nothing` keeps `s_base`. Circuit and generator units remain independent.
The default :off preserves direct expressions; physical outputs are unchanged.
`observation_support_threshold=2` lifts only rows with strictly more distinct
real solver variables. `observation_selection=:all` retains that default scope;
`:coil_voltages`, `:coil_currents` and `:coils` select rows matching original
ordinary or multiwinding coil observations, only when bounded-observation lifting
is enabled. The threshold still applies; all physical bounds remain enforced.
`observation_sharing=:exact` reuses identical composed
affine observations, including constants; default :off retains separate rows.
`:signed` also shares opposite rows; `:proportional` shares real scalar multiples
only when all coefficients and constants have an exact binary-rational
certificate and the reconstruction factor is a finite nonzero Float64.
Neither control changes power lifting or removes operating bounds.
`power_sharing=:generators` reuses existing generator dispatch definitions for
exactly matching voltage/current row pairs when lifting is enabled. Default :off.
`device_elimination=:transformer_currents` substitutes from-side coil currents
using fixed-transformer current balance. Retains circulation, bonds and grounds;
multiwinding devices remain explicit. `:all_transformer_currents` additionally
substitutes complete multiwinding coil-current blocks when the composed block
passes the condition and residual gates; singular or unsafe blocks remain
explicit. Every bound and recovery observation is composed through the map.
No pseudoinverse, regularization or star fit is used. Default :off.
`transformer_nameplate=:bmopftools` enforces positive ordinary-transformer
`s_rating` on the BMOPFTools rated port: from coil for single-phase/center-tap,
wye phase port for Yd/Dy (one third per phase), and from through-coil for
regulators (undivided per regulator). Missing ratings add no cap; the BMOPFTools
policy rejects a supplied zero rating, matching its native input validation.
Default :ignore retains the earlier native contract. This is a physical bound
policy, not a numerical transformation. General multiwinding `s_rating` remains
metadata in both policies. Under :bmopftools, scalar winding `s_max` is a total
VA rating divided equally among its coils; under :ignore it retains the native
per-coil interpretation. Explicit vectors remain per-coil in both policies.
Current limits remain per-coil amperes. This distinction changes the feasible
set, not numerical scaling; diagnostics and SI exports record the applied caps.
`load_power_lifting=true` separates voltage-dependent load power products from
their nonlinear voltage laws using exact complex-power auxiliaries. It uses
`load_power_base`, falling back to `lifted_power_base` (then `s_base`), and applies
independently of `lifting`. `load_power_bases=Dict(load_id=>VA, ...)` overrides
this unit per load, for all its native channels. Explicit load units require
`load_power_lifting=true`; per-load entries must identify voltage-law loads
that actually receive auxiliaries. Other power auxiliaries retain their units.
Constant-power and impedance loads are unchanged. Default false.
`load_power_row_scaling=:definitions/:laws/:both` independently rescales the
selected voltage-law load equalities; default :off preserves assembly-unit rows.
It requires load-power lifting. `load_power_row_base` and per-load
`load_power_row_bases` specify row units in VA, falling back to `s_base` (not
column units). Explicit row units require an active row-scaling mode. These
positive equality multipliers do not change physical bounds or primal recovery.
`coincident_voltage_bounds=:equality` replaces a positive, exactly coincident
bus-voltage lower/upper pair with one magnitude equality. Default :separate
retains both inequalities. Pairs on explicitly fixed source coordinates retain
their original inequalities to avoid adding redundant fixed-source equalities.
Zero limits and proper intervals retain their original representation. This
local rewrite does not remove dependencies on other voltage or circuit rows.
`:guarded_equality` also shares exactly identical normalized affine voltage
observations and retains pairs whose coordinates are fixed by single-unknown
propagation through the existing linear circuit equations. It uses no nominal
voltage, operating point, coefficient tolerance or numerical rank threshold.
"""
Base.@kwdef struct IVRNLPOptions
    s_base::Float64 = 1e4
    objective_scale::Union{Nothing,Float64} = nothing
    current_power_bases::Dict{String,Float64} = Dict{String,Float64}()
    generator_power_bases::Dict{String,Float64} = Dict{String,Float64}()
    lifted_power_base::Union{Nothing,Float64} = nothing
    power_sharing::Symbol = :off
    objective::Symbol = :cost
    power_terms::Vector{IVRPowerTerm} = IVRPowerTerm[]
    specialization::Symbol = :off
    linear_elimination::Symbol = :off
    passive_component_limit::Int = 4
    series_selection::Symbol = :all
    ground_scaling::Symbol = :off
    transformer_scaling::Symbol = :off
    row_scaling::Symbol = :legacy
    kcl_row_max_base::Union{Nothing,Float64} = nothing
    lifting::Symbol = :off
    observation_support_threshold::Int = 2
    observation_selection::Symbol = :all
    observation_sharing::Symbol = :off
    coincident_voltage_bounds::Symbol = :separate
    device_elimination::Symbol = :off
    transformer_nameplate::Symbol = :ignore
    load_power_lifting::Bool = false
    load_power_base::Union{Nothing,Float64} = nothing
    load_power_bases::Dict{String,Float64} = Dict{String,Float64}()
    load_power_row_scaling::Symbol = :off
    load_power_row_base::Union{Nothing,Float64} = nothing
    load_power_row_bases::Dict{String,Float64} = Dict{String,Float64}()
end

_ivrn_objective_scale(options)=something(options.objective_scale,options.s_base)
_ivrn_load_power_base(options,id)=get(options.load_power_bases,id,
    something(options.load_power_base,options.lifted_power_base,options.s_base))
_ivrn_load_power_row_base(options,id)=get(options.load_power_row_bases,id,
    something(options.load_power_row_base,options.s_base))
_ivrn_load_power_row_multiplier(options,id,kind)=
    options.load_power_row_scaling in (kind,:both) ? options.s_base/_ivrn_load_power_row_base(options,id) : 1.0

# Bound observations enter the common limit path before coordinate elimination,
# so direct and lifted formulations bind the same original physical quantity.
function _ivrn_nameplate_limits!(net,e,policy)
    policy in (:ignore,:bmopftools) || throw(ArgumentError("unknown transformer nameplate policy"))
    records=Any[]
    for (kind,table) in get(net,"transformer",Dict()),(id,d) in table
        kind=="n_winding" && continue
        rating=get(d,"s_rating",0.)
        rating isa Real && !(rating isa Bool) && isfinite(rating) && rating>=0 ||
            _ivrn_refuse("transformer/$kind/$id s_rating must be a nonnegative finite scalar")
        policy==:bmopftools && haskey(d,"s_rating") && rating==0 &&
            _ivrn_refuse("transformer/$kind/$id s_rating must be positive under the BMOPFTools nameplate policy")
        rating>0 || continue
        key="$kind/$id";side=kind=="delta_wye" ? :to : :from
        _,_,u,j,_=only(x for x in e.devices if x[1]==Symbol("transformer_coil_",side) && x[2]==key)
        channels=collect(eachindex(u));current_basis="series_coil"
        if kind in ("delta_wye","wye_delta")
            _,_,_,terminal,_=only(x for x in e.devices if x[1]==Symbol("transformer_",side) && x[2]==key)
            neutral=get(e.neutral_map,d["bus_$side"],nothing)
            channels=findall(!=(neutral),d["terminal_map_$side"])
            j=terminal[channels];current_basis="wye_phase_terminal"
        end
        per=kind in ("delta_wye","wye_delta") ? rating/3 : rating
        enforced=policy==:bmopftools
        if enforced
            push!(e.limits,(u,j,Dict("s_max"=>fill(per,length(u)))))
            _sdp_record_limit!(e.limit_metadata,e.limits;label="transformer/$kind/$id",
                family=:transformer,id=key,side,channels,voltage_basis=:connection_coil,
                current_basis=Symbol(current_basis),sources=Dict("s_max"=>_sdp_limit_source(
                    ("transformer",kind,id,"s_rating"),rating;
                    interpretation=kind in ("delta_wye","wye_delta") ? :nameplate_equal_shares : :per_coil_nameplate,
                    divisor=kind in ("delta_wye","wye_delta") ? 3 : 1)))
        end
        push!(records,(;id,kind,side,channels,current_basis,limit_VA=per,enforced))
    end
    records
end

# The common electrical assembler retains native per-coil limits for SDP/SOC.
# Resolve the opt-in scalar winding-total contract before exact-IVR elimination.
function _ivrn_nwinding_limits!(net,e,policy)
    records=Any[]
    for (id,d) in get(get(net,"transformer",Dict()),"n_winding",Dict()),(k,w) in enumerate(d["windings"])
        haskey(w,"s_max") || continue
        key="n_winding/$id/$k"
        _,_,u,j,_=only(x for x in e.devices if x[1]==:transformer_coil && x[2]==key)
        index=only(k for (k,x) in enumerate(e.limits) if x[1]===u && x[2]===j)
        bounds=e.limits[index][3]
        total=policy==:bmopftools && w["s_max"] isa Real
        total && (bounds["s_max"]=bounds["s_max"]./length(u))
        if e.limit_metadata!==nothing
            e.limit_metadata[index].sources["s_max"]=_sdp_limit_source(
                ("transformer","n_winding",id,"windings",k,"s_max"),w["s_max"];
                interpretation=total ? :winding_total_equal_shares : :per_coil,
                divisor=total ? length(u) : 1)
        end
        push!(records,(;id,winding=k,coil_count=length(u),
            interpretation=total ? :winding_total_equal_shares : :per_coil,
            current_basis=:series_coil,limits_VA=copy(bounds["s_max"])))
    end
    records
end

# Retain original declarations and the actual emitted rows, including tautologies.
# Observations may be lifted; physical tracing separately evaluates the original rows.
function _ivrn_equipment_upper!(model,e,z,meta,field,k,v,i,bound)
    source=meta.sources[field];power=field=="s_max"
    base=power ? e.sb : e.ib
    observation=power ? _ivrn_bound_power(model,v,i,z) : _ivrn_bound_observation(model,i,z)
    refs=_ivrn_upper!(model,observation,bound/base)
    declared=source.declared isa Real ? source.declared : source.declared[k]
    audit_label=(meta.family==:switch && meta.side==:from ? "switch/$(meta.id)" : meta.label)*"/"*last(source.path)
    push!(model.ext[:ivr_equipment_limit_rows],(;label=meta.label*"/"*last(source.path)*"/$(meta.channels[k])",
        audit_label,meta.family,meta.id,meta.side,meta.winding,channel=meta.channels[k],
        source_channel=source.declared isa Real ? nothing : k,source_path=source.path,
        declared_value=declared,source.interpretation,source.divisor,field,
        meta.voltage_basis,meta.current_basis,voltage_row=copy(v),current_row=copy(i),
        limit_SI=bound,unit=power ? :VA : :A,physical_scale=base,observation,
        form=isempty(refs) ? :identically_zero_upper : iszero(bound) ? :zero_upper : :magnitude_upper,
        constraints=refs))
    nothing
end

"""An exact-IVR scope refusal, carrying a stable `code` and explanatory `message`.

A failed optional conductor certificate instead produces full-model fallback
diagnostics when the electrical problem itself is supported.
"""
struct IVRNLPInapplicableError <: Exception
    code::String
    message::String
end
Base.showerror(io::IO,e::IVRNLPInapplicableError)=print(io,e.code,": ",e.message)
_ivrn_refuse(message)=throw(IVRNLPInapplicableError("E.IVRNLP.UNSUPPORTED",message))

"""Built exact-IVR JuMP model with an owned SI `network` snapshot.

Inspect `model`, `options` and `numerical_diagnostics`; use `update_ivr_loads!`
and `update_ivr_generators!` for supported changes. Directly editing `network`
does not update constraints. Electrical coordinate and constraint maps are
implementation details, not a persistence format.
"""
struct IVRNLPBuild
    model::JuMP.Model
    state::Any
    powers::Dict{Tuple{Symbol,String},Vector{Any}}
    electrical::Any
    network::Dict{String,Any}
    options::IVRNLPOptions
    load_constraints::Dict{String,Any}
    load_voltage_variables::Dict{String,Any}
    generator_variables::Dict{String,Any}
    numerical_diagnostics::Dict{Symbol,Any}
    coordinates::Any
end

function _ivrn_check(net)
    for family in ("control_profile",)
        isempty(get(net,family,Dict())) || _ivrn_refuse("$family is outside the initial static IVR scope")
    end
    for (kind,table) in get(net,"transformer",Dict())
        isempty(table) && continue
        kind in (_SDP_TRANSFORMERS...,"n_winding") ||
            _ivrn_refuse("transformer/$kind is outside the fixed winding IVR scope")
    end
    _sdp_check(net)
    for (id,d) in get(net,"ibr",Dict())
        _ivrn_check_ibr(net,id,d)
    end
    for (id,d) in get(net,"load",Dict())
        _ivrn_check_load(id,d)
    end
end

function _ivrn_check_ibr(net,id,d)
    label="ibr/$id"
    all(haskey(d,k) for k in ("bus","terminal_map","topology","s_max")) ||
        _ivrn_refuse("$label requires bus, terminal_map, topology and s_max")
    any(haskey(d,k) for k in ("control_profile","voltage_aggregation")) &&
        _ivrn_refuse("$label control profiles and voltage aggregation are not evaluated")
    for field in ("grid_forming","dc_link_coupled")
        get(d,field,false) isa Bool || _ivrn_refuse("$label $field must be Boolean")
    end
    valid(x)=x isa Real && !(x isa Bool) && isfinite(x)
    ratings=d["s_max"]
    ratings isa AbstractVector && !isempty(ratings) && all(x->valid(x)&&x>=0,ratings) ||
        _ivrn_refuse("$label s_max must be a nonnegative finite vector")
    n=length(ratings);tm=d["terminal_map"];top=d["topology"]
    nt=get(_kr_neutral_map(net),d["bus"],nothing)
    if top=="THREE_LEG"
        n==3 && length(tm)==3 && !(nt in tm) || _ivrn_refuse("$label THREE_LEG requires three phase conductors")
    elseif top=="FOUR_LEG"
        nt in tm && length(tm)==n+1 || _ivrn_refuse("$label FOUR_LEG requires an explicit neutral return")
    elseif top=="SINGLE_PHASE"
        n==1 && length(tm) in (1,2) || _ivrn_refuse("$label SINGLE_PHASE requires one connection channel")
    else
        _ivrn_refuse("$label unknown topology")
    end
    for field in ("p_min","p_max","q_min","q_max","cost","energy_cost_rate","i_max","r_filter","x_filter")
        haskey(d,field) || continue
        raw=d[field];xs=raw isa Real ? [raw] : raw
        xs isa AbstractVector && all(valid,xs) || _ivrn_refuse("$label $field must be finite real values")
        if field in ("r_filter","x_filter")
            raw isa Real || length(xs)==n || _ivrn_refuse("$label $field must match channels")
        elseif field=="i_max"
            length(xs) in (n,length(tm)) || _ivrn_refuse("$label i_max must match phases or terminals")
            all(>=(0),xs) || _ivrn_refuse("$label negative current rating")
        else
            length(xs)==n || _ivrn_refuse("$label $field must match phases")
        end
    end
    for field in ("p_avail","p_dc_min","p_dc_max","b_filter_shunt","v_ref_internal")
        haskey(d,field) && !valid(d[field]) && _ivrn_refuse("$label $field must be a finite scalar")
    end
    for (lo,hi) in (("p_min","p_max"),("q_min","q_max"),("p_dc_min","p_dc_max"))
        haskey(d,lo) && haskey(d,hi) && any(d[lo].>d[hi]) && _ivrn_refuse("$label inverted $lo/$hi bounds")
    end
    haskey(d,"p_avail") && d["p_avail"]<0 && _ivrn_refuse("$label negative availability")
    any(haskey(d,k) for k in ("p_dc_min","p_dc_max")) && !get(d,"dc_link_coupled",false) &&
        _ivrn_refuse("$label DC-link limits require dc_link_coupled=true")
    if get(d,"grid_forming",false)
        get(d,"v_ref_internal",0)>0 || _ivrn_refuse("$label requires positive v_ref_internal")
    elseif haskey(d,"v_ref_internal")
        _ivrn_refuse("$label v_ref_internal requires grid_forming=true")
    end
end

# Unloaded source propagation supplies starts only; it does not constrain any
# operating currents. All fixed source coordinates are handled by the NLP.
_ivrn_needs_circuit_start(net)=any(!isempty,values(get(net,"transformer",Dict()))) ||
    !isempty(get(net,"switch",Dict())) || !isempty(get(net,"capacitor",Dict())) || !isempty(get(net,"ibr",Dict()))

function _ivrn_start(net,e)
    if _ivrn_needs_circuit_start(net)
        # The unloaded linear circuit retains leakage, excitation, grounding,
        # impedance loads, capacitors and fixed switches. It supplies starts only, never
        # NLP constraints. Open switches provide no voltage reference.
        try
            z,_,_=_linivr_reference(e;fixed_coordinates=e.fixed_source_coordinates)
            return z
        catch err
            err isa LinIVRInapplicableError && _ivrn_refuse(err.message)
            rethrow()
        end
    end
    adjacency=Dict(key=>Tuple{String,String}[] for key in keys(e.voltage))
    for l in values(get(net,"line",Dict()))
        for (a,b) in zip(l["terminal_map_from"],l["terminal_map_to"])
            f=(l["bus_from"],a);t=(l["bus_to"],b)
            push!(adjacency[f],t);push!(adjacency[t],f)
        end
    end
    known=Dict{Tuple{String,String},ComplexF64}()
    for (key,k) in e.voltage
        k==0 ? (known[key]=0im) : haskey(e.fixed_source_coordinates,k) &&
            (known[key]=e.fixed_source_coordinates[k])
    end
    # Propagate actual source/ideal-ground references first. Seeding a finite
    # shunt at zero before this traversal can otherwise erase the source-fed
    # phase start of an entire downstream region.
    queue=sort!(collect(keys(known)));cursor=1
    function propagate!()
        while cursor<=length(queue)
            f=queue[cursor];cursor+=1
            for t in adjacency[f]
                haskey(known,t) && continue
                known[t]=known[f];push!(queue,t)
            end
        end
    end
    propagate!()
    # Only an as-yet unreferenced conductor component uses a finite ground as
    # a zero starting reference. Its admittance and KCL remain physical.
    for s in values(get(net,"shunt",Dict()))
        length(s["terminal_map"])==1 || continue
        y=only(_l3f_shunt_matrix(s,1))
        isfinite(y) && !iszero(y) || continue
        key=(s["bus"],only(s["terminal_map"]))
        if !haskey(known,key)
            known[key]=0im;push!(queue,key);propagate!()
        end
    end
    length(known)==length(e.voltage) ||
        _ivrn_refuse("every conductor must have a line path to a fixed source, ideal ground or finite one-terminal ground")
    z=zeros(ComplexF64,e.coordinate_count[])
    for (key,k) in e.voltage;k==0 || (z[k]=known[key]);end
    z
end

_ivrn_power(v,i,z)=_linivr_eval(v,z)*conj(_linivr_eval(i,z))

# Auxiliary definitions are exact graph extensions. Their records also encode
# starts and supplied physical points; they never become independent observations.
function _ivrn_lift!(model,u,key,kind;power_ratio=nothing,row_multiplier=1.0)
    policy=model.ext[:ivr_lifting]
    get!(policy.cache,key) do
        signature=kind==:observation ? _ivrn_observation_signature(u,policy.sharing) : nothing
        if signature!==nothing && haskey(policy.observations,signature.key)
            for entry in policy.observations[signature.key]
                factor=_ivrn_observation_factor(signature.pivot,entry.pivot)
                factor===nothing && continue
                policy.shared_count[]+=1
                push!(policy.sharing_report,(;representative_record=entry.record,factor))
                return factor*entry.lifted
            end
        end
        k=length(policy.records)+1
        scale=kind==:power ? something(power_ratio,policy.power_ratio) : 1.0
        expression=u/scale
        value=JuMP.value(v->JuMP.is_fixed(v) ? JuMP.fix_value(v) : JuMP.start_value(v),expression)
        a=@variable(model,base_name="lift_$(kind)_$(k)_real",start=real(value))
        b=@variable(model,base_name="lift_$(kind)_$(k)_imag",start=imag(value))
        definition_real=@constraint(model,(row_multiplier*scale)*a==row_multiplier*real(u))
        definition_imag=@constraint(model,(row_multiplier*scale)*b==row_multiplier*imag(u))
        push!(policy.records,(;real=a,imag=b,expression,kind,scale,key,row_multiplier,definition_real,definition_imag))
        lifted=scale*(a+im*b)
        if signature!==nothing
            entries=get!(()->NamedTuple[],policy.observations,signature.key)
            push!(entries,(;pivot=signature.pivot,lifted,record=k))
        end
        lifted
    end
end
_ivrn_row_key(row)=Tuple(sort!(collect(row);by=first))
# Exact coefficient identity in this model, after coordinate composition.
function _ivrn_affine_key(u)
    key(x)=(iszero(x.constant) ? 0.0 : x.constant,
        Tuple(sort!([(JuMP.index(v).value,c) for (v,c) in x.terms if !iszero(c)];by=first)))
    (key(real(u)),key(imag(u)))
end
function _ivrn_observation_signature(u,sharing)
    sharing==:off && return nothing
    raw=_ivrn_affine_key(u)
    sharing==:exact && return (;key=raw,pivot=1.0)
    coefficients=[c for part in raw for c in (part[1],last.(part[2])...)]
    all(isfinite,coefficients) || return nothing
    k=findfirst(!iszero,coefficients)
    k===nothing && return nothing
    pivot=coefficients[k]
    if sharing==:signed
        factor=sign(pivot)
        return (;key=factor>0 ? raw : _ivrn_affine_key(-u),pivot=factor)
    end
    # Interpret stored floating coefficients exactly as binary rationals. Rounded
    # normalized floating keys could falsely identify nearly proportional rows.
    q=Rational{BigInt}(pivot)
    normalize(part)=(Rational{BigInt}(part[1])/q,
        Tuple((v,Rational{BigInt}(c)/q) for (v,c) in part[2]))
    (;key=(normalize(raw[1]),normalize(raw[2])),pivot)
end
function _ivrn_observation_factor(pivot,representative)
    factor=pivot/representative
    isfinite(factor) && !iszero(factor) || return nothing
    Rational{BigInt}(factor)*Rational{BigInt}(representative)==Rational{BigInt}(pivot) ? factor : nothing
end
function _ivrn_selected_observation_rows(options,e)
    options.lifting==:bounded_observations && options.observation_selection!=:all || return nothing
    e===nothing && throw(ArgumentError("coil observation selection requires electrical provenance"))
    rows=Set{Any}()
    for (family,_,v,i,_) in e.devices
        family in (:transformer_coil,:transformer_coil_from,:transformer_coil_to) || continue
        if options.observation_selection in (:coil_voltages,:coils)
            union!(rows,(_ivrn_row_key(row) for row in v))
        end
        if options.observation_selection in (:coil_currents,:coils)
            union!(rows,(_ivrn_row_key(row) for row in i))
        end
    end
    rows
end
_ivrn_lifting_policy(options,e=nothing)=(;mode=options.lifting,threshold=options.observation_support_threshold,
    selection=options.observation_selection,selection_rows=_ivrn_selected_observation_rows(options,e),
    power_ratio=something(options.lifted_power_base,options.s_base)/options.s_base,
    sharing=options.observation_sharing,power_sharing=options.power_sharing,
    generator_powers=Dict{Any,Any}(),reused_generator_count=Ref(0),
    cache=Dict{Any,Any}(),observations=Dict{Any,Any}(),
    shared_count=Ref(0),sharing_report=NamedTuple[],records=NamedTuple[])
function _ivrn_bound_observation(model,row,z)
    u=_linivr_eval(row,z);policy=model.ext[:ivr_lifting]
    # The default threshold leaves physical coordinates direct. No threshold
    # lifts an identically zero channel or changes the original operating bound.
    if policy.mode==:bounded_observations &&
       (policy.selection_rows===nothing || _ivrn_row_key(row) in policy.selection_rows) &&
       length(Set(v for x in (real(u),imag(u)) for (v,c) in x.terms if !iszero(c)))>policy.threshold
        return _ivrn_lift!(model,u,(:observation,_ivrn_row_key(row)),:observation)
    end
    u
end
function _ivrn_bound_power(model,v,i,z)
    policy=model.ext[:ivr_lifting]
    policy.mode==:off && return _ivrn_power(v,i,z)
    key=(:power,_ivrn_row_key(v),_ivrn_row_key(i))
    if policy.power_sharing==:generators && haskey(policy.generator_powers,key)
        return get!(policy.cache,key) do
            policy.reused_generator_count[]+=1
            policy.generator_powers[key]
        end
    end
    u=_ivrn_bound_observation(model,v,z);j=_ivrn_bound_observation(model,i,z)
    s=u*conj(j)
    iszero(s) && return s
    _ivrn_lift!(model,s,key,:power)
end

function _ivrn_generator_bounds!(variables,low,high,sb)
    low!==nothing && high!==nothing && any(low .> high) &&
        throw(ArgumentError("generator lower bounds must not exceed upper bounds"))
    for (k,x) in enumerate(variables)
        if low===nothing
            JuMP.has_lower_bound(x) && JuMP.delete_lower_bound(x)
        else
            JuMP.set_lower_bound(x,low[k]/sb)
        end
        if high===nothing
            JuMP.has_upper_bound(x) && JuMP.delete_upper_bound(x)
        else
            JuMP.set_upper_bound(x,high[k]/sb)
        end
    end
end

function _ivrn_upper!(model,u,bound)
    isfinite(bound) && bound>=0 || _ivrn_refuse("magnitude limits must be finite and nonnegative")
    # Grounded voltage channels are identically zero. Emitting 0 == 0 for
    # their zero ratings can make an otherwise square NLP overdetermined.
    iszero(u) && return Any[]
    if iszero(bound)
        cr=@constraint(model,real(u)==0)
        ci=@constraint(model,imag(u)==0)
        return Any[cr,ci]
    else
        # A small neutral-voltage rating can be orders below the phase base.
        # Normalize by its declared rating so a solver's absolute constraint
        # tolerance does not turn into an excessive physical violation.
        c=@constraint(model,(real(u)/bound)^2+(imag(u)/bound)^2<=1)
        return Any[c]
    end
end

function _ivrn_each_bus_limit(f,net,e;buses=nothing)
    for (b,d) in net["bus"]
        buses===nothing || b in buses || continue
        maps=_sdp_voltage_maps(net,b,e.terminal_rows;neutral=get(e.neutral_map,b,nothing))
        for key in ("v_min","v_max","vpn_min","vpn_max","vpp_min","vpp_max",
                    "vn_max","vpos_min","vpos_max","vneg_max","vzero_max")
            haskey(d,key) || continue
            prefix=startswith(key,"v_") ? key : first(split(key,"_"))
            haskey(maps,prefix) || _ivrn_refuse("bus/$b $key requires corresponding terminals")
            rows=maps[prefix];bounds=_sdp_vector(d,key,length(rows))
            for (row,bound) in zip(rows,bounds)
                bound>=0 || _ivrn_refuse("negative voltage limit")
                f(b,key,row,bound)
            end
        end
    end
end

# Structural certificate only: if all but one nonzero term in an existing
# homogeneous circuit equation are fixed, its remaining coordinate is fixed.
# We need no value estimate because certified voltage pairs remain inequalities.
function _ivrn_circuit_fixed_coordinates(e)
    fixed=Set(keys(e.fixed_source_coordinates));derivations=NamedTuple[]
    supports=[[k for (k,a) in row if !iszero(a)] for row in e.equations]
    uses=Dict{Int,Vector{Int}}()
    for (j,ks) in enumerate(supports),k in ks;push!(get!(()->Int[],uses,k),j);end
    remaining=[count(k->k ∉ fixed,ks) for ks in supports]
    queue=findall(==(1),remaining);cursor=1
    while cursor<=length(queue)
        j=queue[cursor];cursor+=1
        remaining[j]==1 || continue
        k=only(k for k in supports[j] if k ∉ fixed)
        push!(fixed,k);push!(derivations,(;coordinate=k,equation=j))
        for index in uses[k]
            remaining[index]-=1
            remaining[index]==1 && push!(queue,index)
        end
    end
    (;fixed,derivations)
end

# Compare stored binary coefficients relative to the physical limit exactly.
# Rounded floating division is insufficient: nearby declarations can normalize
# to the same float without defining the same real-valued observation.
function _ivrn_voltage_equality_key(u,bound)
    raw=_ivrn_affine_key(u);q=Rational{BigInt}(bound)
    normalize(part)=(Rational{BigInt}(part[1])/q,
        Tuple((v,Rational{BigInt}(c)/q) for (v,c) in part[2]))
    normalize(raw[1]),normalize(raw[2])
end

function _ivrn_bus_limits!(model,net,e,z;coincident=:separate)
    coincident in (:separate,:equality,:guarded_equality) || throw(ArgumentError("unknown coincident voltage bound policy"))
    certificate=coincident==:guarded_equality ? _ivrn_circuit_fixed_coordinates(e) : nothing
    model.ext[:ivr_voltage_fixed_dependencies]=certificate===nothing ? NamedTuple[] : certificate.derivations
    representatives=Dict{Any,Any}()
    limits=Any[];channels=Dict{Tuple{String,String},Int}()
    _ivrn_each_bus_limit(net,e) do b,key,row,bound
        channel=get(channels,(b,key),0)+1;channels[(b,key)]=channel
        push!(limits,(;b,key,row,bound,channel))
    end
    upper=Dict((x.b,x.key,x.channel)=>x for x in limits if endswith(x.key,"max"))
    # One provenance entry per original declaration, even when two bounds
    # share an equality or an identically zero observation needs no row.
    records=Any[merge(x,(;row=copy(x.row),relation=endswith(x.key,"min") ? :lower : :upper,
        form=:unrecorded,constraints=Any[])) for x in limits]
    model.ext[:ivr_bus_limit_rows]=records
    indices=Dict((x.b,x.key,x.channel)=>j for (j,x) in enumerate(limits))
    function record!(b,key,channel,form,refs)
        j=indices[(b,key,channel)]
        records[j]=merge(records[j],(;form,constraints=Any[refs...]))
    end
    skipped=Set{Tuple{String,String,Int}}();report=Any[]
    for (;b,key,row,bound,channel) in limits
        (b,key,channel) in skipped && continue
        if coincident!=:separate && endswith(key,"min") && isfinite(bound) && bound>0
            upper_key=(b,replace(key,r"min$"=>"max"),channel)
            hi=get(upper,upper_key,nothing)
            if hi!==nothing && hi.bound==bound && _ivrn_row_key(hi.row)==_ivrn_row_key(row)
                source_fixed=all(k->haskey(e.fixed_source_coordinates,k),keys(row))
                circuit_fixed=certificate!==nothing && all(k->k in certificate.fixed,keys(row))
                entry=(;bus=b,lower=key,upper=upper_key[2],channel,limit_V=bound)
                if source_fixed || circuit_fixed
                    push!(report,merge(entry,(;action=source_fixed ? :fixed_source_pair_retained : :circuit_fixed_pair_retained)))
                else
                    signature=coincident==:guarded_equality ? _ivrn_voltage_equality_key(_linivr_eval(row,z),bound) : nothing
                    if signature!==nothing && haskey(representatives,signature)
                        representative=representatives[signature]
                        push!(report,merge(entry,(;action=:shared_equality,representative_bus=representative.bus,
                            representative_lower=representative.lower,representative_channel=representative.channel)))
                        record!(b,key,channel,:shared_equality,[representative.constraint])
                        record!(upper_key...,:shared_equality,[representative.constraint])
                        push!(skipped,upper_key)
                        continue
                    end
                    u=_ivrn_bound_observation(model,row,z);scale=bound/e.vb
                    c=@constraint(model,(real(u)/scale)^2+(imag(u)/scale)^2==1)
                    record!(b,key,channel,:coincident_equality,[c])
                    record!(upper_key...,:coincident_equality,[c])
                    push!(report,merge(entry,(;action=:equality)))
                    signature===nothing || (representatives[signature]=merge(entry,(;constraint=c)))
                    push!(skipped,upper_key)
                    continue
                end
            end
        end
        u=_ivrn_bound_observation(model,row,z)
        if endswith(key,"max")
            refs=_ivrn_upper!(model,u,bound/e.vb)
            form=isempty(refs) ? :identically_zero_upper : iszero(bound) ? :zero_upper : :magnitude_upper
            record!(b,key,channel,form,refs)
        elseif bound>0
            scale=bound/e.vb
            c=@constraint(model,(real(u)/scale)^2+(imag(u)/scale)^2>=1)
            record!(b,key,channel,:magnitude_lower,[c])
        else
            record!(b,key,channel,:nonnegative_magnitude,Any[])
        end
    end
    report
end

"""Build exact IVR without topology reduction; `optimizer=nothing` is supported."""
function build_ivr_nlp_opf(input,optimizer=nothing;options=IVRNLPOptions())
    try
        _build_ivr_nlp_opf(input,optimizer,options)
    catch err
        err isa SDPInapplicableError && _ivrn_refuse(err.message)
        rethrow()
    end
end

function _build_ivr_nlp_opf(input,optimizer,options)
    isfinite(options.s_base) && options.s_base>0 || throw(ArgumentError("s_base must be positive and finite"))
    isfinite(_ivrn_objective_scale(options)) && _ivrn_objective_scale(options)>0 || throw(ArgumentError("objective_scale must be positive and finite"))
    if options.lifted_power_base!==nothing
        base=options.lifted_power_base
        isfinite(base) && base>0 && isfinite(base/options.s_base) && base/options.s_base>0 &&
            isfinite(options.s_base/base) || throw(ArgumentError("lifted power base and coordinate ratios must be positive and finite"))
    end
    isempty(options.current_power_bases) || options.transformer_scaling in (:nominal,:nominal_multiwinding) || throw(ArgumentError("current_power_bases requires nominal transformer coordinates"))
    options.load_power_row_scaling in (:off,:definitions,:laws,:both) || throw(ArgumentError("unknown load power row scaling"))
    options.load_power_row_scaling==:off || options.load_power_lifting || throw(ArgumentError("load power row scaling requires load_power_lifting=true"))
    if options.load_power_row_base!==nothing || !isempty(options.load_power_row_bases)
        options.load_power_row_scaling!=:off || throw(ArgumentError("load power row units require an active row scaling mode"))
        for base in (options.load_power_row_base,values(options.load_power_row_bases)...)
            base===nothing && continue
            isfinite(base) && base>0 && isfinite(base/options.s_base) && base/options.s_base>0 &&
                isfinite(options.s_base/base) || throw(ArgumentError("load power row bases and ratios must be positive and finite"))
        end
    end
    if options.load_power_base!==nothing || !isempty(options.load_power_bases)
        options.load_power_lifting || throw(ArgumentError("load power units require load_power_lifting=true"))
        for base in (options.load_power_base,values(options.load_power_bases)...)
            base===nothing && continue
            isfinite(base) && base>0 && isfinite(base/options.s_base) && base/options.s_base>0 &&
                isfinite(options.s_base/base) || throw(ArgumentError("load power bases and coordinate ratios must be positive and finite"))
        end
    end
    # Own mutable base declarations just as the build owns its physical input.
    options=IVRNLPOptions(; (k=>(k in (:current_power_bases,:generator_power_bases,:load_power_bases,:load_power_row_bases,:power_terms) ? deepcopy(getfield(options,k)) : getfield(options,k)) for k in fieldnames(IVRNLPOptions))...)
    options.objective in (:cost,:source_import,:feasibility,:power) || throw(ArgumentError("unknown IVRNLP objective"))
    _ivrn_check_power_terms(options)
    options.specialization in (:off,:conductor_difference,:conductor_regions) || throw(ArgumentError("unknown IVRNLP specialization"))
    options.linear_elimination in (:off,:impedance_loads,:passive,:passive_chains,:passive_blocks,:passive_hybrid) || throw(ArgumentError("unknown IVRNLP linear elimination"))
    options.passive_component_limit>0 || throw(ArgumentError("passive_component_limit must be positive"))
    options.series_selection in (:all,:bound_support) || throw(ArgumentError("unknown IVRNLP series selection"))
    options.ground_scaling in (:off,:voltage,:regional_voltage,:regional_multiwinding_voltage) || throw(ArgumentError("unknown IVRNLP ground scaling"))
    options.transformer_scaling in (:off,:nominal,:nominal_multiwinding) || throw(ArgumentError("unknown IVRNLP transformer scaling"))
    options.row_scaling in (:legacy,:composed) || throw(ArgumentError("unknown IVRNLP row scaling"))
    options.power_sharing in (:off,:generators) || throw(ArgumentError("unknown IVRNLP power sharing"))
    options.lifting in (:off,:powers,:bounded_observations) || throw(ArgumentError("unknown IVRNLP lifting"))
    options.observation_support_threshold>=0 || throw(ArgumentError("observation support threshold must be nonnegative"))
    options.observation_selection in (:all,:coil_voltages,:coil_currents,:coils) || throw(ArgumentError("unknown IVRNLP observation selection"))
    options.observation_sharing in (:off,:exact,:signed,:proportional) || throw(ArgumentError("unknown IVRNLP observation sharing"))
    options.coincident_voltage_bounds in (:separate,:equality,:guarded_equality) || throw(ArgumentError("unknown coincident voltage bound policy"))
    options.device_elimination in (:off,:transformer_currents,:all_transformer_currents) || throw(ArgumentError("unknown IVRNLP device elimination"))
    options.transformer_nameplate in (:ignore,:bmopftools) || throw(ArgumentError("unknown transformer nameplate policy"))
    net=_l3f_input(input);_ivrn_check(net)
    for field in (:load_power_bases,:load_power_row_bases),id in keys(getfield(options,field))
        haskey(get(net,"load",Dict()),id) || throw(ArgumentError("unknown load in $field: $id"))
        d=net["load"][id]
        lowercase(get(d,"model","constant_power"))!="constant_power" && !_sdp_is_impedance_load(d) ||
            throw(ArgumentError("$field entry $id has no voltage-law power auxiliaries"))
    end
    if options.load_power_row_scaling!=:off
        for (id,d) in get(net,"load",Dict())
            lowercase(get(d,"model","constant_power"))=="constant_power" && continue
            _sdp_is_impedance_load(d) && continue
            # Individually representable row/column ratios can still overflow
            # or underflow when composed in the auxiliary coefficient.
            coefficient=(_ivrn_load_power_base(options,id)/options.s_base)*
                (options.s_base/_ivrn_load_power_row_base(options,id))
            isfinite(coefficient) && coefficient>0 || throw(ArgumentError("composed load power row/column coefficient must be positive and finite: $id"))
        end
    end
    for (id,base) in options.generator_power_bases
        haskey(get(net,"generator",Dict()),id) || throw(ArgumentError("unknown generator in generator_power_bases: $id"))
        isfinite(base) && base>0 && isfinite(base/options.s_base) && base/options.s_base>0 &&
            isfinite(options.s_base/base) || throw(ArgumentError("generator power bases and coordinate ratios must be positive and finite"))
    end
    e=_ivr_electrical_data(net;s_base=options.s_base,line_records=true,
                           delta_dispatch=:coil,ibr_delta_dispatch=:conductor,source_mode=:affine,
                           record_transformer_bonds=true,record_transformer_currents=true,record_equations=true,record_limits=true)
    if options.kcl_row_max_base!==nothing
        cap=options.kcl_row_max_base
        isfinite(cap) && cap>0 && isfinite(cap/e.ib) && cap/e.ib>0 ||
            throw(ArgumentError("KCL row cap and ampere-to-assembly ratio must be positive and finite"))
    end
    nameplates=_ivrn_nameplate_limits!(net,e,options.transformer_nameplate)
    winding_limits=_ivrn_nwinding_limits!(net,e,options.transformer_nameplate)
    z0=_ivrn_start(net,e)
    report,plan=options.specialization==:off ? ((;status=:disabled,code=:disabled,components=String[]),nothing) :
        options.specialization==:conductor_regions ? _ivrn_regions(net,e) : _ivrn_structure(net,e)
    maps=_ivrn_coordinates(e,plan)
    omitted=plan===nothing ? Set{Tuple{String,String}}() : Set(plan.omitted_kcl)
    maps,omitted_equations,omitted,elimination=_ivrn_linear_coordinates(net,e,maps,omitted,options.linear_elimination;
                                                                    series_selection=options.series_selection,component_limit=options.passive_component_limit)
    maps,omitted_equations,device_elimination=_ivrn_device_coordinates(net,e,maps,omitted_equations,options.device_elimination)
    maps,scaling=_ivrn_ground_coordinates(net,e,maps,options.ground_scaling)
    maps,transformer_scaling=_ivrn_transformer_coordinates(net,e,maps,options.transformer_scaling,options.current_power_bases)
    scaled_rows=options.row_scaling==:composed || !isempty(scaling.scaled_terminals)
    model=optimizer===nothing ? JuMP.Model() : JuMP.Model(optimizer)
    model.ext[:ivr_lifting]=_ivrn_lifting_policy(options,e)
    model.ext[:ivr_equipment_limit_rows]=Any[]
    model.ext[:ivr_dispatch_rows]=Dict{Tuple{Symbol,String,String,Int},Any}()
    n=length(maps.projection)
    xr=@variable(model,[1:n],base_name="state_real")
    xi=@variable(model,[1:n],base_name="state_imag")
    y=xr+im*xi
    z=[_linivr_eval(row,y) for row in maps.reconstruction]
    y0=[_linivr_eval(row,z0) for row in maps.projection]
    for k in 1:n
        JuMP.set_start_value(xr[k],real(y0[k]));JuMP.set_start_value(xi[k],imag(y0[k]))
    end
    for (k,v) in e.fixed_source_coordinates
        j,a=only(maps.reconstruction[k]) # Source coordinates remain singleton, possibly scaled.
        JuMP.fix(xr[j],real(v/a));JuMP.fix(xi[j],imag(v/a))
    end
    for (row,is_kcl) in Iterators.flatten(( ((row,false) for (k,row) in enumerate(e.equations) if k ∉ omitted_equations),
                                  ((row,true) for (key,row) in e.kcl if key ∉ omitted)))
        isempty(row) && continue
        divisor=scaled_rows ? _ivrn_scaled_row_norm(row,maps) : norm(collect(values(row)))
        is_kcl && (divisor=_ivrn_kcl_row_divisor(divisor,e.ib,options.kcl_row_max_base))
        isfinite(divisor) && divisor>0 || _ivrn_refuse("invalid circuit-row normalization")
        a=_linivr_eval(row,z)/divisor
        @constraint(model,real(a)==0);@constraint(model,imag(a)==0)
    end
    powers=Dict{Tuple{Symbol,String},Vector{Any}}()
    loads=Dict{String,Any}();load_voltages=Dict{String,Any}();generators=Dict{String,Any}()
    voltage_range=nothing # Build this index only for voltage-dependent powers.
    objective=JuMP.QuadExpr(JuMP.AffExpr(0.0))
    for (family,id,v,i,d) in e.devices
        count=length(v)
        s=Any[_ivrn_power(v[k],i[k],z) for k in 1:count]
        powers[(family,id)]=s
        # Retain every reported complex power, but split P/Q only for the
        # device equations, dispatch bounds and objective terms below.
        family in (:load,:generator,:voltage_source,:ibr,:ibr_internal) || continue
        p=real.(s);q=imag.(s)
        if family==:generator
            # Explicit dispatch variables keep the power equations fixed as
            # boxes change between fixed, free and one-sided dispatch.
            pg=@variable(model,[1:count],base_name="generator_$(id)_p",start=0.)
            qg=@variable(model,[1:count],base_name="generator_$(id)_q",start=0.)
            power_base=get(options.generator_power_bases,id,e.sb)
            ratio=power_base/e.sb
            # Preserve assembly-unit equation rows; change only dispatch columns.
            cp=[@constraint(model,p[k]==ratio*pg[k]) for k in 1:count]
            cq=[@constraint(model,q[k]==ratio*qg[k]) for k in 1:count]
            generators[id]=(;p=pg,q=qg,p_equations=cp,q_equations=cq,power_base)
            if options.power_sharing==:generators && options.lifting!=:off
                for k in 1:count
                    key=(:power,_ivrn_row_key(v[k]),_ivrn_row_key(i[k]))
                    model.ext[:ivr_lifting].generator_powers[key]=ratio*(pg[k]+im*qg[k])
                end
            end
            p=pg;q=qg
        end
        if family==:load && !_sdp_is_impedance_load(d)
            pn=e.values_for(d,"p_nom",count);qn=e.values_for(d,"q_nom",count)
            pn===nothing || qn===nothing ? _ivrn_refuse("load/$id requires P and Q") : nothing
            if lowercase(get(d,"model","constant_power"))=="constant_power"
                cp=[@constraint(model,p[k]==pn[k]/e.sb) for k in 1:count]
                cq=[@constraint(model,q[k]==qn[k]/e.sb) for k in 1:count]
                loads[id]=(;p=cp,q=cq)
            else
                if voltage_range===nothing
                    voltage_range=_sdp_voltage_ranges(net,e.terminal_rows,
                        Dict(k=>v*e.vb for (k,v) in e.fixed_source_coordinates))
                end
                load_voltages[id]=_ivrn_load_law!(model,id,d,v,p,q,z,z0,e,voltage_range;
                    power_lifting=options.load_power_lifting,
                    power_ratio=_ivrn_load_power_base(options,id)/e.sb,
                    definition_row_multiplier=_ivrn_load_power_row_multiplier(options,id,:definitions),
                    law_row_multiplier=_ivrn_load_power_row_multiplier(options,id,:laws))
            end
        elseif family==:ibr_internal
            if get(d,"dc_link_coupled",false)
                if haskey(d,"p_dc_min") && haskey(d,"p_dc_max") && d["p_dc_min"]==d["p_dc_max"]
                    @constraint(model,sum(p)==d["p_dc_min"]/e.sb)
                else
                    for (field,lower) in (("p_dc_min",true),("p_dc_max",false))
                        haskey(d,field) || continue
                        bound=d[field]/e.sb
                        lower ? @constraint(model,sum(p)>=bound) : @constraint(model,sum(p)<=bound)
                    end
                end
            end
            if get(d,"grid_forming",false)
                ref=d["v_ref_internal"]/e.vb
                for row in v
                    if all(haskey(e.fixed_source_coordinates,k) for k in keys(row))
                        known=sum((a*e.fixed_source_coordinates[k] for (k,a) in row);init=0im)
                        isapprox(abs(known),ref;rtol=1e-12,atol=0) || _ivrn_refuse("ibr/$id internal voltage conflicts with fixed source")
                        continue
                    end
                    u=_linivr_eval(row,z)
                    @constraint(model,(real(u)/ref)^2+(imag(u)/ref)^2==1)
                end
            end
        elseif family in (:generator,:voltage_source,:ibr)
            if family==:ibr && haskey(d,"p_avail")
                @constraint(model,sum(p)<=d["p_avail"]/e.sb)
            end
            for (lo,hi,x) in (("p_min","p_max",p),("q_min","q_max",q))
                low=family==:voltage_source ? get(d,lo,nothing) : e.values_for(d,lo,count)
                high=family==:voltage_source ? get(d,hi,nothing) : e.values_for(d,hi,count)
                if family==:generator
                    _ivrn_generator_bounds!(x,low,high,generators[id].power_base)
                    continue
                end
                for k in 1:count
                    if low!==nothing && high!==nothing && low[k]==high[k]
                        c=@constraint(model,x[k]==low[k]/e.sb)
                        model.ext[:ivr_dispatch_rows][(family,id,lo,k)]=c
                        model.ext[:ivr_dispatch_rows][(family,id,hi,k)]=c
                    else
                        if low!==nothing && isfinite(low[k])
                            c=@constraint(model,x[k]>=low[k]/e.sb)
                            model.ext[:ivr_dispatch_rows][(family,id,lo,k)]=c
                        end
                        if high!==nothing && isfinite(high[k])
                            c=@constraint(model,x[k]<=high[k]/e.sb)
                            model.ext[:ivr_dispatch_rows][(family,id,hi,k)]=c
                        end
                    end
                end
            end
            priced=copy(d)
            if haskey(d,"energy_cost_rate")
                haskey(d,"cost") && d["cost"]!=d["energy_cost_rate"] && _ivrn_refuse("$family/$id conflicting costs")
                priced["cost"]=d["energy_cost_rate"]
            end
            cost=e.values_for(priced,"cost",count;default=zeros(count))
            for k in 1:count
                coefficient=options.objective==:cost ? cost[k]*(family==:generator ? generators[id].power_base : e.sb)/1000 :
                    options.objective==:source_import && family==:voltage_source ? e.sb : 0.0
                JuMP.add_to_expression!(objective,coefficient,p[k])
            end
            if family==:voltage_source && haskey(d,"s_max")
                nt=get(e.neutral_map,d["bus"],nothing)
                phases=findall(!=(nt),d["terminal_map"])
                meta=(;label="source/$id",family,id,side=nothing,winding=nothing,channels=phases,
                    voltage_basis=:terminal_to_ground,current_basis=:terminal,
                    sources=Dict("s_max"=>_sdp_limit_source(("voltage_source",id,"s_max"),d["s_max"])))
                for (c,(k,bound)) in enumerate(zip(phases,_sdp_vector(d,"s_max",length(phases))))
                    _ivrn_equipment_upper!(model,e,z,meta,"s_max",c,v[k],i[k],bound)
                end
            end
        end
    end
    for (index,(v,i,d)) in enumerate(e.limits)
        meta=e.limit_metadata[index]
        imax=e.values_for(d,"i_max",length(i));smax=e.values_for(d,"s_max",length(v))
        for k in eachindex(v)
            imax===nothing || _ivrn_equipment_upper!(model,e,z,meta,"i_max",k,v[k],i[k],imax[k])
            smax===nothing || _ivrn_equipment_upper!(model,e,z,meta,"s_max",k,v[k],i[k],smax[k])
        end
    end
    voltage_bound_report=_ivrn_bus_limits!(model,net,e,z;coincident=options.coincident_voltage_bounds)
    options.objective==:power && (objective=_ivrn_power_objective(model,options.power_terms,e,z,generators))
    @objective(model,Min,objective/_ivrn_objective_scale(options))
    unavailable=[(id,t) for (id,d) in net["voltage_source"] for t in d["terminal_map"]
                 if e.voltage[(d["bus"],t)]==0]
    diagnostics=Dict{Symbol,Any}(:power_model=>:exact,:delta_dispatch=>:coil,:ibr_delta_dispatch=>:conductor,
        :transformer_nameplate=>options.transformer_nameplate,:transformer_nameplate_report=>nameplates,
        :nwinding_power_limit_report=>winding_limits,
        :specialization=>plan===nothing ? :off : options.specialization,
        :specialization_report=>report,:structure_analysis_count=>options.specialization==:off ? 0 : 1,
        :network_reduction=>:off,:assembly_count=>1,
        :linear_elimination=>options.linear_elimination,:linear_elimination_report=>elimination,
        :device_elimination=>options.device_elimination,:device_elimination_report=>device_elimination,
        :ground_scaling=>options.ground_scaling,:ground_scaling_report=>scaling,
        :transformer_scaling=>options.transformer_scaling,:transformer_scaling_report=>transformer_scaling,
        :row_scaling=>options.row_scaling,:composed_row_normalization=>scaled_rows,
        :kcl_row_max_base=>options.kcl_row_max_base,
        :per_unit_bases=>(voltage_V=e.vb,current_A=e.ib,power_VA=e.sb),
        :objective_scale=>_ivrn_objective_scale(options),
        :generator_power_bases=>Dict(id=>g.power_base for (id,g) in generators),
        :lifted_power_base=>something(options.lifted_power_base,options.s_base),
        :power_sharing=>options.power_sharing,
        :reused_generator_power_count=>model.ext[:ivr_lifting].reused_generator_count[],
        :lifting=>options.lifting,:lifted_real_variables=>2length(model.ext[:ivr_lifting].records),
        :observation_support_threshold=>options.observation_support_threshold,
        :observation_selection=>options.observation_selection,
        :observation_selected_row_count=>model.ext[:ivr_lifting].selection_rows===nothing ? nothing : length(model.ext[:ivr_lifting].selection_rows),
        :observation_sharing=>options.observation_sharing,
        :coincident_voltage_bounds=>options.coincident_voltage_bounds,
        :coincident_voltage_bound_report=>voltage_bound_report,
        :voltage_fixed_dependencies=>model.ext[:ivr_voltage_fixed_dependencies],
        :shared_observation_count=>model.ext[:ivr_lifting].shared_count[],
        :observation_sharing_report=>copy(model.ext[:ivr_lifting].sharing_report),
        :update_count=>0,:generator_update_count=>0,
        :dispatch_variable_count=>sum(length(g.p)+length(g.q) for g in values(generators);init=0),
        :load_voltage_variable_count=>sum(length,values(load_voltages);init=0),
        :load_power_lifting=>options.load_power_lifting,
        :load_power_bases=>Dict(id=>_ivrn_load_power_base(options,id) for id in keys(load_voltages) if options.load_power_lifting),
        :load_power_row_scaling=>options.load_power_row_scaling,
        :load_power_row_bases=>Dict(id=>_ivrn_load_power_row_base(options,id) for id in keys(load_voltages) if options.load_power_row_scaling!=:off),
        :load_power_lift_count=>count(k->first(k)==:load_law_power,keys(model.ext[:ivr_lifting].cache)),
        :state_dimension=>e.coordinate_count[],
        :solver_state_dimension=>n,:discharged_complex_kcl=>length(omitted),:source_mode=>:affine,
        :initialization=>_ivrn_needs_circuit_start(net) ? :linear_circuit : :line_propagation,
        :legacy_slack_generators=>sort!([id for (id,d) in get(net,"generator",Dict()) if get(d,"_slack",false)]),
        :unobserved_grounded_source_currents=>unavailable)
    coordinates=(;maps...,real_variables=xr,imaginary_variables=xi)
    IVRNLPBuild(model,z,powers,e,net,options,loads,load_voltages,generators,diagnostics,coordinates)
end

"""Update constant-power loads in SI units without reassembly.

`updates` maps load IDs to `(p=[...], q=[...])`. Every entry is validated before
mutation; invalid input leaves the model usable. Equipment, source phasors and
normalization stay fixed. This does not promise rollback on optimizer errors.
"""
function update_ivr_loads!(build::IVRNLPBuild,updates::AbstractDict)
    staged=Dict{String,Any}()
    for (id,value) in updates
        id isa AbstractString && haskey(build.load_constraints,id) ||
            throw(ArgumentError("unknown or non-constant-power load $id"))
        value isa NamedTuple && Set(keys(value))==Set((:p,:q)) ||
            throw(ArgumentError("load updates require (p=[...], q=[...])"))
        n=length(build.load_constraints[id].p)
        p=Float64.(collect(value.p));q=Float64.(collect(value.q))
        length(p)==length(q)==n && all(isfinite,p) && all(isfinite,q) ||
            throw(ArgumentError("load/$id update requires $n finite P and Q values"))
        staged[String(id)]=(;p,q)
    end
    for (id,v) in staged
        refs=build.load_constraints[id]
        for k in eachindex(v.p)
            JuMP.set_normalized_rhs(refs.p[k],v.p[k]/build.electrical.sb)
            JuMP.set_normalized_rhs(refs.q[k],v.q[k]/build.electrical.sb)
        end
        build.network["load"][id]["p_nom"]=copy(v.p)
        build.network["load"][id]["q_nom"]=copy(v.q)
    end
    isempty(staged) || (build.numerical_diagnostics[:update_count]+=1)
    build
end

"""Update generator P/Q boxes and linear prices without reassembly.

`updates` maps generator IDs to named tuples containing any of `p_min`, `p_max`,
`q_min`, `q_max`, `cost`. Values are finite vectors in SI W/var or currency/kWh,
one per native connection channel (delta uses coils). Omitted fields stay
unchanged; `nothing` removes a bound. Prices must be finite vectors. All entries
and resulting boxes are validated before mutation. Invalid input leaves the
model usable; backend failures do not have a rollback guarantee. Source powers,
equipment ratings, topology and per-unit bases are not updated by this API.
"""
function update_ivr_generators!(build::IVRNLPBuild,updates::AbstractDict)
    allowed=Set((:p_min,:p_max,:q_min,:q_max,:cost))
    staged=Dict{String,Dict{Symbol,Any}}()
    for (id,entry) in updates
        id isa AbstractString && haskey(build.generator_variables,id) ||
            throw(ArgumentError("unknown generator $id"))
        entry isa NamedTuple && !isempty(entry) && all(in(allowed),keys(entry)) ||
            throw(ArgumentError("generator updates require P/Q bounds and/or cost"))
        n=length(build.generator_variables[id].p);values=Dict{Symbol,Any}()
        for (field,raw) in pairs(entry)
            if raw===nothing && field!=:cost
                values[field]=nothing
            else
                raw isa AbstractVector && all(x->x isa Real && !(x isa Bool),raw) ||
                    throw(ArgumentError("generator/$id/$field requires $n finite values"))
                v=Float64.(raw)
                length(v)==n && all(isfinite,v) ||
                    throw(ArgumentError("generator/$id/$field requires $n finite values"))
                values[field]=v
            end
        end
        d=build.network["generator"][id]
        for (lo,hi) in ((:p_min,:p_max),(:q_min,:q_max))
            low=get(values,lo,get(d,string(lo),nothing));high=get(values,hi,get(d,string(hi),nothing))
            low!==nothing && high!==nothing && any(low .> high) &&
                throw(ArgumentError("generator/$id lower bounds exceed upper bounds"))
        end
        staged[String(id)]=values
    end
    for (id,values) in staged
        d=build.network["generator"][id];refs=build.generator_variables[id]
        for (lo,hi,x) in ((:p_min,:p_max,refs.p),(:q_min,:q_max,refs.q))
            haskey(values,lo) || haskey(values,hi) || continue
            low=get(values,lo,get(d,string(lo),nothing));high=get(values,hi,get(d,string(hi),nothing))
            _ivrn_generator_bounds!(x,low,high,refs.power_base)
        end
        if haskey(values,:cost) && build.options.objective==:cost
            for (x,c) in zip(refs.p,values[:cost])
                JuMP.set_objective_coefficient(build.model,x,(c/1000)*(refs.power_base/_ivrn_objective_scale(build.options)))
            end
        end
        for (field,v) in values
            if v===nothing
                pop!(d,string(field),nothing)
            else
                d[string(field)]=copy(v)
                field==:cost && haskey(d,"energy_cost_rate") && (d["energy_cost_rate"]=copy(v))
            end
        end
    end
    if !isempty(staged)
        build.numerical_diagnostics[:update_count]+=1
        build.numerical_diagnostics[:generator_update_count]+=1
    end
    build
end

"""Exact-IVR solve result in SI units, subject to strict local solver acceptance.

`voltage_candidate` maps `(bus, terminal)` to complex volts. `current_candidate`
and `powers` map `(family, id)` to channel vectors in A and VA. `objective` is
watts for source import, currency/h for linear energy prices, user-defined units
for `:power`, or zero for
feasibility. Unaccepted results have empty candidate maps and a NaN objective.
Inspect `solve` before using candidates, then independently assess them with
`physical_residuals`. Local acceptance is not a global optimality certificate.
"""
struct IVRNLPResult <: AbstractSolveResult
    objective::Float64
    voltage_candidate::Dict{Tuple{String,String},ComplexF64}
    current_candidate::Dict{Tuple{Symbol,String},Vector{ComplexF64}}
    powers::Dict{Tuple{Symbol,String},Vector{ComplexF64}}
    solve::SolveStatus
    numerical_diagnostics::Dict{Symbol,Any}
end
solve_status(r::IVRNLPResult)=r.solve
solve_diagnostics(r::IVRNLPResult)=(model_kind=:exact,numerical=r.numerical_diagnostics,
    physical_feasibility_certified=false,bound_certified=false)

function solve_ivr_nlp_opf(input,optimizer;options=IVRNLPOptions(),solver_options=())
    solve_ivr_nlp_opf(build_ivr_nlp_opf(input,optimizer;options);solver_options)
end

"""Solve a built IVR model. Local solver success is not a global certificate."""
function solve_ivr_nlp_opf(build::IVRNLPBuild;solver_options=())
    _set_solver_options!(build.model,solver_options)
    export_meta=_result_export_start(build)
    JuMP.optimize!(build.model)
    build.numerical_diagnostics[:result_export]=_result_export_finish!(export_meta,build)
    outcome=_solve_outcome(build.model);e=build.electrical
    voltage=Dict{Tuple{String,String},ComplexF64}()
    currents=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    powers=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    objective=NaN
    if outcome.optimal
        z=ComplexF64.(JuMP.value.(build.state))
        for (key,k) in e.voltage;voltage[key]=k==0 ? 0im : z[k]*e.vb;end
        for (f,id,v,i,_) in e.devices
            currents[(f,id)]=ComplexF64[_linivr_eval(row,z)*e.ib for row in i]
            powers[(f,id)]=ComplexF64[_ivrn_power(v[k],i[k],z)*e.sb for k in eachindex(v)]
        end
        objective=JuMP.objective_value(build.model)*_ivrn_objective_scale(build.options)
    end
    IVRNLPResult(objective,voltage,currents,powers,SolveStatus(outcome),copy(build.numerical_diagnostics))
end
