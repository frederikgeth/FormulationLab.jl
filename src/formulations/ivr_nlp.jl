"""Experimental exact static IVR options. Approximate network reduction is never applied.

Supports lines, fixed sources, fixed isolated winding transformers, shunts/grounds, constant-power/impedance loads
and generator boxes with coil-based delta dispatch. Costs are linear, in the
same currency/kWh convention as LinIVR. An optimizer is supplied by the caller.
`specialization=:conductor_difference` attempts a certified radial zero-sum
current reduction and retains reference-conductor voltages. Ineligible networks
fall back to full IVR with a reason in the build diagnostics; the default is :off.
"""
Base.@kwdef struct IVRNLPOptions
    s_base::Float64 = 1e4
    objective::Symbol = :cost
    specialization::Symbol = :off
end

struct IVRNLPInapplicableError <: Exception
    code::String
    message::String
end
Base.showerror(io::IO,e::IVRNLPInapplicableError)=print(io,e.code,": ",e.message)
_ivrn_refuse(message)=throw(IVRNLPInapplicableError("E.IVRNLP.UNSUPPORTED",message))

struct IVRNLPBuild
    model::JuMP.Model
    state::Any
    powers::Dict{Tuple{Symbol,String},Vector{Any}}
    electrical::Any
    network::Dict{String,Any}
    options::IVRNLPOptions
    load_constraints::Dict{String,Any}
    generator_variables::Dict{String,Any}
    numerical_diagnostics::Dict{Symbol,Any}
    coordinates::Any
end

function _ivrn_check(net)
    for family in ("switch","capacitor","ibr","control_profile")
        isempty(get(net,family,Dict())) || _ivrn_refuse("$family is outside the initial static IVR scope")
    end
    for (kind,table) in get(net,"transformer",Dict())
        isempty(table) && continue
        kind in ("single_phase","center_tap","delta_wye","wye_delta","n_winding") ||
            _ivrn_refuse("transformer/$kind is outside the fixed isolated-winding IVR scope")
    end
    _sdp_check(net)
    for (id,d) in get(net,"load",Dict())
        lowercase(get(d,"model","constant_power")) in ("constant_power","constant_impedance") ||
            _ivrn_refuse("load/$id requires constant_power or constant_impedance")
    end
end

# Unloaded source propagation supplies starts only; it does not constrain any
# operating currents. All fixed source coordinates are handled by the NLP.
function _ivrn_start(net,e)
    if any(!isempty,values(get(net,"transformer",Dict())))
        # The unloaded linear circuit retains leakage, excitation, grounding
        # and impedance loads. It supplies starts only, never NLP constraints.
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
    # A finite one-terminal ground supplies a no-load starting reference, not
    # a fixed voltage. Its actual admittance and terminal KCL stay in the NLP.
    for s in values(get(net,"shunt",Dict()))
        length(s["terminal_map"])==1 || continue
        y=only(_l3f_shunt_matrix(s,1))
        isfinite(y) && !iszero(y) || continue
        get!(known,(s["bus"],only(s["terminal_map"])),0im)
    end
    queue=sort!(collect(keys(known)));cursor=1
    while cursor<=length(queue)
        f=queue[cursor];cursor+=1
        for t in adjacency[f]
            haskey(known,t) && continue
            known[t]=known[f];push!(queue,t)
        end
    end
    length(known)==length(e.voltage) ||
        _ivrn_refuse("every conductor must have a line path to a fixed source, ideal ground or finite one-terminal ground")
    z=zeros(ComplexF64,e.coordinate_count[])
    for (key,k) in e.voltage;k==0 || (z[k]=known[key]);end
    z
end

_ivrn_power(v,i,z)=_linivr_eval(v,z)*conj(_linivr_eval(i,z))

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
    iszero(u) && return
    if iszero(bound)
        @constraint(model,real(u)==0)
        @constraint(model,imag(u)==0)
    else
        # A small neutral-voltage rating can be orders below the phase base.
        # Normalize by its declared rating so a solver's absolute constraint
        # tolerance does not turn into an excessive physical violation.
        @constraint(model,(real(u)/bound)^2+(imag(u)/bound)^2<=1)
    end
end

function _ivrn_bus_limits!(model,net,e,z)
    for (b,d) in net["bus"]
        maps=_sdp_voltage_maps(net,b,e.terminal_rows;neutral=get(e.neutral_map,b,nothing))
        for key in ("v_min","v_max","vpn_min","vpn_max","vpp_min","vpp_max",
                    "vn_max","vpos_min","vpos_max","vneg_max","vzero_max")
            haskey(d,key) || continue
            prefix=startswith(key,"v_") ? key : first(split(key,"_"))
            haskey(maps,prefix) || _ivrn_refuse("bus/$b $key requires corresponding terminals")
            rows=maps[prefix];bounds=_sdp_vector(d,key,length(rows))
            for (row,bound) in zip(rows,bounds)
                bound>=0 || _ivrn_refuse("negative voltage limit")
                u=_linivr_eval(row,z)
                if endswith(key,"max")
                    _ivrn_upper!(model,u,bound/e.vb)
                elseif bound>0
                    scale=bound/e.vb
                    @constraint(model,(real(u)/scale)^2+(imag(u)/scale)^2>=1)
                end
            end
        end
    end
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
    options.objective in (:cost,:source_import,:feasibility) || throw(ArgumentError("unknown IVRNLP objective"))
    options.specialization in (:off,:conductor_difference) || throw(ArgumentError("unknown IVRNLP specialization"))
    net=_l3f_input(input);_ivrn_check(net)
    e=_ivr_electrical_data(net;s_base=options.s_base,line_records=true,
                           delta_dispatch=:coil,source_mode=:affine)
    z0=_ivrn_start(net,e)
    report,plan=options.specialization==:off ? ((;status=:disabled,code=:disabled,components=String[]),nothing) : _ivrn_structure(net,e)
    maps=_ivrn_coordinates(e,plan)
    model=optimizer===nothing ? JuMP.Model() : JuMP.Model(optimizer)
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
        j=only(keys(maps.reconstruction[k])) # Source coordinates stay physical.
        JuMP.fix(xr[j],real(v));JuMP.fix(xi[j],imag(v))
    end
    omitted=plan===nothing ? Set{Tuple{String,String}}() : Set(plan.omitted_kcl)
    for row in vcat(e.equations,[row for (key,row) in e.kcl if key ∉ omitted])
        isempty(row) && continue
        a=_linivr_eval(row,z)/norm(collect(values(row)))
        @constraint(model,real(a)==0);@constraint(model,imag(a)==0)
    end
    powers=Dict{Tuple{Symbol,String},Vector{Any}}()
    loads=Dict{String,Any}();generators=Dict{String,Any}()
    objective=JuMP.QuadExpr(JuMP.AffExpr(0.0))
    for (family,id,v,i,d) in e.devices
        count=length(v)
        s=Any[_ivrn_power(v[k],i[k],z) for k in 1:count]
        powers[(family,id)]=s
        p=real.(s);q=imag.(s)
        if family==:generator
            # Explicit dispatch variables keep the power equations fixed as
            # boxes change between fixed, free and one-sided dispatch.
            pg=@variable(model,[1:count],base_name="generator_$(id)_p",start=0.)
            qg=@variable(model,[1:count],base_name="generator_$(id)_q",start=0.)
            cp=[@constraint(model,p[k]==pg[k]) for k in 1:count]
            cq=[@constraint(model,q[k]==qg[k]) for k in 1:count]
            generators[id]=(;p=pg,q=qg,p_equations=cp,q_equations=cq)
            p=pg;q=qg
        end
        if family==:load && !_sdp_is_impedance_load(d)
            pn=e.values_for(d,"p_nom",count);qn=e.values_for(d,"q_nom",count)
            pn===nothing || qn===nothing ? _ivrn_refuse("load/$id requires P and Q") : nothing
            cp=[@constraint(model,p[k]==pn[k]/e.sb) for k in 1:count]
            cq=[@constraint(model,q[k]==qn[k]/e.sb) for k in 1:count]
            loads[id]=(;p=cp,q=cq)
        elseif family in (:generator,:voltage_source)
            for (lo,hi,x) in (("p_min","p_max",p),("q_min","q_max",q))
                low=family==:voltage_source ? get(d,lo,nothing) : e.values_for(d,lo,count)
                high=family==:voltage_source ? get(d,hi,nothing) : e.values_for(d,hi,count)
                if family==:generator
                    _ivrn_generator_bounds!(x,low,high,e.sb)
                    continue
                end
                for k in 1:count
                    if low!==nothing && high!==nothing && low[k]==high[k]
                        @constraint(model,x[k]==low[k]/e.sb)
                    else
                        low===nothing || !isfinite(low[k]) || @constraint(model,x[k]>=low[k]/e.sb)
                        high===nothing || !isfinite(high[k]) || @constraint(model,x[k]<=high[k]/e.sb)
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
                coefficient=options.objective==:cost ? cost[k]*e.sb/1000 :
                    options.objective==:source_import && family==:voltage_source ? e.sb : 0.0
                JuMP.add_to_expression!(objective,coefficient,p[k])
            end
            if family==:voltage_source && haskey(d,"s_max")
                nt=get(e.neutral_map,d["bus"],nothing)
                phases=findall(!=(nt),d["terminal_map"])
                for (k,bound) in zip(phases,_sdp_vector(d,"s_max",length(phases)))
                    _ivrn_upper!(model,s[k],bound/e.sb)
                end
            end
        end
    end
    for (v,i,d) in e.limits
        imax=e.values_for(d,"i_max",length(i));smax=e.values_for(d,"s_max",length(v))
        for k in eachindex(v)
            imax===nothing || _ivrn_upper!(model,_linivr_eval(i[k],z),imax[k]/e.ib)
            smax===nothing || _ivrn_upper!(model,_ivrn_power(v[k],i[k],z),smax[k]/e.sb)
        end
    end
    _ivrn_bus_limits!(model,net,e,z)
    @objective(model,Min,objective/e.sb)
    unavailable=[(id,t) for (id,d) in net["voltage_source"] for t in d["terminal_map"]
                 if e.voltage[(d["bus"],t)]==0]
    diagnostics=Dict{Symbol,Any}(:power_model=>:exact,:delta_dispatch=>:coil,
        :specialization=>plan===nothing ? :off : :conductor_difference,
        :specialization_report=>report,:structure_analysis_count=>options.specialization==:off ? 0 : 1,
        :network_reduction=>:off,:assembly_count=>1,
        :update_count=>0,:generator_update_count=>0,
        :dispatch_variable_count=>sum(length(g.p)+length(g.q) for g in values(generators);init=0),
        :state_dimension=>e.coordinate_count[],
        :solver_state_dimension=>n,:discharged_complex_kcl=>length(omitted),:source_mode=>:affine,
        :initialization=>any(!isempty,values(get(net,"transformer",Dict()))) ? :linear_circuit : :line_propagation,
        :legacy_slack_generators=>sort!([id for (id,d) in get(net,"generator",Dict()) if get(d,"_slack",false)]),
        :unobserved_grounded_source_currents=>unavailable)
    coordinates=(;maps...,real_variables=xr,imaginary_variables=xi)
    IVRNLPBuild(model,z,powers,e,net,options,loads,generators,diagnostics,coordinates)
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
            _ivrn_generator_bounds!(x,low,high,build.electrical.sb)
        end
        if haskey(values,:cost) && build.options.objective==:cost
            for (x,c) in zip(refs.p,values[:cost])
                JuMP.set_objective_coefficient(build.model,x,c/1000)
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
    _set_solver_options!(build.model,solver_options);JuMP.optimize!(build.model)
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
        objective=JuMP.objective_value(build.model)*e.sb
    end
    IVRNLPResult(objective,voltage,currents,powers,SolveStatus(outcome),copy(build.numerical_diagnostics))
end
