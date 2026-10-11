# BMOPFTools result dictionary compatibility, audited against revision
# 39523e8a5cc5543e0f644ab2d135dd43ef4d8c01. No BMOPFTools runtime dependency.
const _RESULT_NAN = ComplexF64(NaN,NaN)
const _RESULT_TABLES = ("bus","ground","line","switch","load","generator","ibr",
    "transformer","capacitor","voltage_source","dc_bus","dc_branch","modeled_volt_watt")
_result_network(b)=b.network
_result_network(b::SOCBuild)=b.electrical.network
_result_canonical(x::AbstractDict)="{"*join((JSON3.write(string(k))*":"*_result_canonical(x[k]) for k in sort!(collect(keys(x));by=string)),",")*"}"
_result_canonical(x::AbstractVector)="["*join(_result_canonical.(x),",")*"]"
# JSON parsers may read 230.0 as 230. Preserve numeric identity without rounding
# large integer annotations through Float64 or conflating booleans with numbers.
_result_canonical(x::AbstractFloat)=isfinite(x) && isinteger(x) ? string(BigInt(x)) : JSON3.write(x;allow_inf=true)
_result_canonical(x)=JSON3.write(x;allow_inf=true)
# Hash bytes, not the String: SHA.jl's CodeUnits path is ~600x slower and made
# every exact-IVR solve on a 22k-bus network spend ~10 minutes here.
_result_digest(net)=bytes2hex(SHA.sha256(Vector{UInt8}(_result_canonical(net))))
_result_voltage(v)=Dict{String,Any}("vr"=>real(v),"vi"=>imag(v),"vm"=>abs(v),"va"=>angle(v))
_result_current(i)=Dict{String,Any}("cr"=>real(i),"ci"=>imag(i),"cm"=>abs(i))
_result_ground(i)=Dict{String,Any}("cg_r"=>real(i),"cg_i"=>imag(i),"cgm"=>abs(i))
_result_json_tree(x::AbstractDict)=Dict{String,Any}(string(k)=>_result_json_tree(v) for (k,v) in x)
_result_json_tree(x::AbstractVector)=map(_result_json_tree,x)
_result_json_tree(x)=x isa AbstractFloat && iszero(x) ? 0.0 : x
_result_matrix(a)=Dict("real"=>[real.(collect(row)) for row in eachrow(a)],"imag"=>[imag.(collect(row)) for row in eachrow(a)])
_result_product(v,i)=(iszero(v)||iszero(i)) ? 0.0im : v*conj(i)
_result_powers(s)=Dict{String,Any}("p"=>real(s),"q"=>imag(s),"s"=>abs(s))

# Capture starts before optimize! and metadata after it. Each solve owns a new
# snapshot; exporting an earlier result after a parameter update stays safe.
function _result_export_start(b)
    net=_result_network(b);initial=Dict{String,Any}()
    for (id,d) in net["bus"]
        initial[id]=Dict(t=>Dict{String,Any}("vr_init"=>NaN,"vi_init"=>NaN,"vm_init"=>NaN,"va_init"=>NaN) for t in d["terminal_names"])
    end
    if b isa Union{IVRNLPBuild,LinIVRBuild}
        for (key,k) in b.electrical.voltage
            v=k==0 ? 0im : JuMP.value(v->JuMP.is_fixed(v) ? JuMP.fix_value(v) : something(JuMP.start_value(v),NaN),b.state[k])*b.electrical.vb
            initial[key[1]][key[2]]=Dict(field*"_init"=>value for (field,value) in _result_voltage(v))
        end
    end
    objective=b isa SOCBuild ? b.options.electrical.objective : b.options.objective
    meta=Dict{String,Any}("network_sha256"=>_result_digest(net),"initialisation"=>initial,
        "objective_units"=>objective in (:source_import,:losses) ? "W" : objective==:cost ? "currency/h" : objective==:power ? "user_defined" : "dimensionless",
        "initialisation_available"=>all(isfinite(x) for terminals in values(initial) for row in values(terminals) for x in values(row)))
    if b isa IVRNLPBuild && objective==:power
        meta["objective_definition"]=[Dict{String,Any}("quantity"=>string(t.quantity),
            "channels"=>[Any[string(f),id,k] for (f,id,k) in t.channels],"weights"=>copy(t.weights),
            "target"=>t.target,"linear"=>t.linear,"quadratic"=>t.quadratic) for t in b.options.power_terms]
    end
    meta
end
function _result_export_finish!(meta,b)
    model=b.model
    meta["solve_time"]=try JuMP.solve_time(model) catch; NaN end
    meta["result_count"]=JuMP.result_count(model)
    # Strict result wrappers keep their acceptance policy. Export can separately
    # preserve a returned diagnostic primal, but never an infeasibility ray.
    primal=JuMP.primal_status(model)
    available=meta["result_count"]>0 && primal in (JuMP.MOI.FEASIBLE_POINT,JuMP.MOI.NEARLY_FEASIBLE_POINT,JuMP.MOI.INFEASIBLE_POINT)
    meta["candidate_available"]=available
    if b isa Union{IVRNLPBuild,LinIVRBuild} && available && !_solve_outcome(model).optimal
        e=b.electrical;z=ComplexF64.(JuMP.value.(b.state))
        meta["diagnostic_point"]=ACPoint(voltage=Dict(k=>(j==0 ? 0im : z[j]*e.vb) for (k,j) in e.voltage),
            currents=Dict((f,id)=>ComplexF64[_linivr_eval(row,z)*e.ib for row in i] for (f,id,_,i,_) in e.devices))
        divisor=b isa IVRNLPBuild ? _ivrn_objective_scale(b.options) : e.sb
        meta["diagnostic_objective"]=JuMP.objective_value(model)*divisor
    end
    meta
end
_result_metadata(r)=get(r.numerical_diagnostics,:result_export,Dict{String,Any}())
_result_metadata(r::SOCResult)=get(r.metadata,:result_export,Dict{String,Any}())
_result_metadata(r::L3FResult)=get(r.formulation,"result_export",Dict{String,Any}())
_result_kind(::IVRNLPResult)="exact_coordinate_recovery"
_result_kind(::LinIVRResult)="approximate_state"
_result_kind(::L3FResult)="fixed_angle_estimate"
_result_kind(::Union{SDPResult,SOCResult,BranchFlowSDPResult})="relaxation_candidate"
_result_point(r)=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
_result_point(r::SOCResult)=haskey(r.metadata,:candidate) ? ACPoint(;r.metadata.candidate...) : ACPoint(voltage=Dict{Tuple{String,String},ComplexF64}())
_result_point(r::L3FResult)=_reconstruction_seed(r)

"""Convert a formulation result to the BMOPFTools component/ID/terminal dictionary.

`result_dict(network, result)` uses the original SI network and the owned solve
snapshot; `result_dict(build, result)` is a convenience overload. All formulations
share field names. `_formulationlab` records physical-state provenance, unavailable
paths, additional recoverable observations and native modeled/relaxed powers.
Compatibility of the output schema does not assert equivalence of device laws.
A non-rank-one relaxation's phasors remain estimates. No optimization is run.
"""
function result_dict(input::Union{AbstractDict,BMOPFInput,AbstractString,PowerIO.PioModule},r::AbstractSolveResult)
    net=_l3f_input(input);meta=_result_metadata(r)
    haskey(meta,"network_sha256") && meta["network_sha256"]!=_result_digest(net) &&
        throw(ArgumentError("result network differs from its solve snapshot; export with the matching original input"))
    # BMOPFTools flattens transformer subtype tables. Refuse ID collisions rather
    # than silently overwrite a physically different transformer.
    ids=[id for table in values(get(net,"transformer",Dict())) for id in keys(table)]
    allunique(ids) || throw(ArgumentError("BMOPFTools result layout requires transformer IDs unique across subtypes"))
    point=get(meta,"diagnostic_point",nothing)
    point===nothing && (point=_result_point(r))
    voltage=point.voltage;currents=point.currents
    quality=_result_kind(r);missing=Any[]
    out=Dict{String,Any}(key=>Dict{String,Any}() for key in _RESULT_TABLES)
    status=solve_status(r)
    merge!(out,Dict("termination_status"=>status.termination_status,"primal_status"=>status.primal_status,
        "feasible"=>status.primal_status in ("FEASIBLE_POINT","NEARLY_FEASIBLE_POINT"),"result_count"=>get(meta,"result_count",status.has_primal ? 1 : 0),
        "objective"=>get(meta,"diagnostic_objective",r.objective),"solve_time"=>get(meta,"solve_time",NaN),
        "initialisation"=>deepcopy(get(meta,"initialisation",Dict{String,Any}()))))
    extras=Dict{String,Any}("schema_version"=>1,"reference_revision"=>"39523e8a5cc5543e0f644ab2d135dd43ef4d8c01",
        "state_kind"=>quality,"units"=>"SI","physical_validation"=>"not_run",
        "formulation_result_type"=>string(nameof(typeof(r))),
        "native_power_kind"=>r isa Union{SDPResult,SOCResult,BranchFlowSDPResult} ? "relaxed_moment" : r isa LinIVRResult ? "linearized_power" : "physical_product",
        "objective_units"=>get(meta,"objective_units","unknown"),
        "unavailable"=>missing,"devices"=>Dict{String,Any}(),"native_powers"=>Dict{String,Any}(),
        "initialisation_available"=>get(meta,"initialisation_available",false),
        "network_sha256"=>_result_digest(net))
    out["_formulationlab"]=extras
    if r isa IVRNLPResult
        zero=get(r.numerical_diagnostics,:zero_load_elimination_report,nothing)
        if zero!==nothing && zero.enabled
            extras["zero_load_elimination_report"]=Dict(
                "eliminated_complex_coordinates"=>zero.eliminated_complex_coordinates,
                "channels"=>[Dict(string(k)=>(v isa Symbol ? string(v) : v) for (k,v) in pairs(q)) for q in zero.channels],
                "retained_channels"=>[Dict(string(k)=>(v isa Symbol ? string(v) : v) for (k,v) in pairs(q)) for q in zero.retained_channels])
        end
        extras["device_elimination"]=string(get(r.numerical_diagnostics,:device_elimination,:off))
        elimination=get(r.numerical_diagnostics,:device_elimination_report,nothing)
        if elimination!==nothing
            extras["device_elimination_report"]=Dict("transformers"=>copy(elimination.transformers),
                "retained_transformers"=>copy(elimination.retained_transformers),
                "equation_indices"=>copy(elimination.equation_indices),
                "eliminated_complex_coordinates"=>elimination.eliminated_complex_coordinates,
                "block_diagnostics"=>Dict(id=>Dict(string(k)=>v for (k,v) in pairs(d))
                    for (id,d) in get(elimination,:block_diagnostics,Dict())))
        end
        extras["fixed_bound_elimination"]=get(r.numerical_diagnostics,:fixed_bound_elimination,false)
        extras["fixed_bound_report"]=[Dict("constraint_type"=>q.constraint_type,
            "constraint_index"=>q.constraint_index,"value"=>q.value,"slack"=>q.slack,
            "dependencies"=>[Dict(string(k)=>v for (k,v) in pairs(d)) for d in q.dependencies])
            for q in get(r.numerical_diagnostics,:fixed_bound_report,Any[])]
        extras["coincident_voltage_bounds"]=string(get(r.numerical_diagnostics,:coincident_voltage_bounds,:separate))
        extras["coincident_voltage_bound_report"]=[Dict(string(k)=>(v isa Symbol ? string(v) : deepcopy(v))
            for (k,v) in pairs(entry)) for entry in get(r.numerical_diagnostics,:coincident_voltage_bound_report,Any[])]
        extras["transformer_nameplate_policy"]=string(get(r.numerical_diagnostics,:transformer_nameplate,:ignore))
        extras["transformer_nameplate_report"]=[Dict(string(k)=>(v isa Symbol ? string(v) : deepcopy(v))
            for (k,v) in pairs(entry)) for entry in get(r.numerical_diagnostics,:transformer_nameplate_report,Any[])]
        extras["nwinding_power_limit_report"]=[Dict(string(k)=>(v isa Symbol ? string(v) : deepcopy(v))
            for (k,v) in pairs(entry)) for entry in get(r.numerical_diagnostics,:nwinding_power_limit_report,Any[])]
    end
    haskey(meta,"objective_definition") && (extras["objective_definition"]=deepcopy(meta["objective_definition"]))
    V(b,t)=get(voltage,(b,t),_RESULT_NAN)
    function I(f,id,n)
        row=get(currents,(f,id),nothing)
        row===nothing && return fill(_RESULT_NAN,n)
        length(row)==n || throw(ArgumentError("current channel $f/$id has wrong arity"))
        copy(row)
    end
    function put!(table,id,record)
        out[table][id]=record
    end
    function device!(family,id,record)
        get!(extras["devices"],family,Dict{String,Any}())[id]=record
    end
    # Net outward current per terminal, for identifiable ideal-ground reactions.
    balance=Dict((b,t)=>0.0im for (b,d) in net["bus"] for t in d["terminal_names"])
    function inject!(b,tm,i,sign=1)
        for (t,j) in zip(tm,i);balance[(b,t)]+=sign*j;end
    end
    function loss(vectors)
        powers=ComplexF64[_result_product(v,i) for (v,i) in vectors]
        s=sum(powers;init=0im)
        Dict{String,Any}("p_loss"=>real(s),"q_loss"=>imag(s),"s_through"=>sum(abs,powers;init=0.))
    end
    totalp=0.;totalq=0.
    for (b,d) in net["bus"]
        put!("bus",b,Dict(t=>_result_voltage(V(b,t)) for t in d["terminal_names"]))
        neutral=_vcheck_neutral(net,b);phases=filter(!=(neutral),d["terminal_names"])
        vn=neutral===nothing ? 0im : V(b,neutral);u=[V(b,t)-vn for t in phases]
        record=Dict{String,Any}("reference_terminal"=>neutral===nothing ? "ground" : neutral,
            "phase_to_reference"=>Dict(t=>_result_voltage(v) for (t,v) in zip(phases,u)))
        if length(phases)==3
            a=cis(2pi/3)
            record["phase_to_phase"]=[_result_voltage(u[k]-u[mod1(k+1,3)]) for k in 1:3]
            # Match the sequence-bound convention without changing the local
            # indexing of phase-to-phase observations above. Bus storage order
            # alone must not swap positive and negative sequence components.
            order=get(get(net,"terminal_conventions",Dict()),"phase",["a","b","c"])
            length(order)==3 && allunique(order) && all(t->t in phases,order) || (order=["a","b","c"])
            all(t->t in phases,order) || (order=phases)
            sequence_u=[V(b,t)-vn for t in order]
            record["positive_sequence"]=_result_voltage(sum([1,a,a^2].*sequence_u)/3)
            record["negative_sequence"]=_result_voltage(sum([1,a^2,a].*sequence_u)/3)
            record["zero_sequence"]=_result_voltage(sum(sequence_u)/3)
        end
        device!("bus",b,record)
    end
    for (id,d) in get(net,"line",Dict())
        f=d["bus_from"];t=d["bus_to"];mf=d["terminal_map_from"];mt=d["terminal_map_to"];n=length(mf)
        vf=V.(f,mf);vt=V.(t,mt);cf=I(:line_from,id,n);ct=I(:line_to,id,n)
        inject!(f,mf,cf);inject!(t,mt,ct)
        rec=Dict{String,Any}(mf[k]=>Dict("cr_fr"=>real(cf[k]),"ci_fr"=>imag(cf[k]),"cm_fr"=>abs(cf[k]),
            "cr_to"=>real(ct[k]),"ci_to"=>imag(ct[k]),"cm_to"=>abs(ct[k])) for k in 1:n)
        rec["ground"]=_result_ground(sum(cf)+sum(ct));rec["loss"]=loss(vcat(collect(zip(vf,cf)),collect(zip(vt,ct))))
        totalp+=rec["loss"]["p_loss"];totalq+=rec["loss"]["q_loss"]
        put!("line",id,rec)
        _,Yf,Yt=_reconstruction_line(net,d)
        device!("line",id,Dict("from_power"=>_result_powers.(vf.*conj.(cf)),"to_power"=>_result_powers.(vt.*conj.(ct)),
            "series_current"=>_result_current.(cf-Yf*vf),"from_shunt_current"=>_result_current.(Yf*vf),
            "to_shunt_current"=>_result_current.(Yt*vt),"terminal_map_from"=>copy(mf),"terminal_map_to"=>copy(mt)))
    end
    for (id,d) in get(net,"switch",Dict())
        mf=d["terminal_map_from"];mt=d["terminal_map_to"]
        cf=get(d,"open_switch",false) ? zeros(ComplexF64,length(mf)) : I(:switch_from,id,length(mf))
        ct=-cf;inject!(d["bus_from"],mf,cf);inject!(d["bus_to"],mt,ct)
        put!("switch",id,Dict(t=>_result_current(i) for (t,i) in zip(mf,cf)))
        device!("switch",id,Dict("to_current"=>_result_current.(ct),
            "from_power"=>_result_powers.(V.(d["bus_from"],mf).*conj.(cf)),"to_power"=>_result_powers.(V.(d["bus_to"],mt).*conj.(ct))))
    end
    neutrals=_kr_neutral_map(net)
    for family in ("load","generator","ibr"),(id,d) in get(net,family,Dict())
        tm=d["terminal_map"];b=d["bus"];nt=get(neutrals,b,nothing)
        cfg=family=="ibr" ? Dict("FOUR_LEG"=>"WYE","THREE_LEG"=>"DELTA","SINGLE_PHASE"=>"SINGLE_PHASE")[d["topology"]] : uppercase(d["configuration"])
        n=family=="load" ? length(d["p_nom"]) : family=="ibr" ? length(d["s_max"]) : cfg=="SINGLE_PHASE" ? 1 : cfg=="DELTA" ? (length(tm)==2 ? 1 : 3) : count(!=(nt),tm)
        D=_sdp_connection(net,b,tm,cfg,n;neutral=nt);u=D*V.(b,tm)
        coil=I(Symbol(family),id,n)
        # Exact IVR THREE_LEG exports conductor PCC currents natively, but also
        # retains filter coil currents. Recover the original coil including its
        # circulation; never choose a pseudoinverse of delta incidence.
        conductor=(family=="ibr" && cfg=="DELTA" && length(tm)==3 && !(r isa LinIVRResult)) ||
            (family=="generator" && cfg=="DELTA" && length(tm)==3 && r isa Union{SDPResult,SOCResult,BranchFlowSDPResult})
        if conductor
            coil=family=="ibr" && haskey(currents,(:ibr_internal,id)) ?
                I(:ibr_internal,id,n).-im*get(d,"b_filter_shunt",0.)*u : fill(_RESULT_NAN,n)
        end
        terminal=conductor ? I(Symbol(family),id,length(tm)) : transpose(D)*coil
        inject!(b,tm,terminal,family=="load" ? 1 : -1)
        p=u.*conj.(coil);cr,ci,pk,qk=family=="load" ? ("crd","cid","pd","qd") : family=="generator" ? ("crg","cig","pg","qg") : ("cri","cii","pg","qg")
        # Positive incidence identifies coil labels even with a permuted neutral.
        labels=[tm[findfirst(==(1),D[k,:])] for k in axes(D,1)]
        put!(family,id,Dict(labels[k]=>Dict(cr=>real(coil[k]),ci=>imag(coil[k]),pk=>real(p[k]),qk=>imag(p[k])) for k in 1:n))
        record=Dict{String,Any}("terminal_map"=>copy(tm),"terminal_current"=>_result_current.(terminal),
            "terminal_power"=>_result_powers.(_result_product.(V.(b,tm),terminal)),
            "total_power"=>_result_powers(sum(_result_product.(V.(b,tm),terminal))),
            "coil_voltage"=>_result_voltage.(u),"coil_current"=>_result_current.(coil),"coil_power"=>_result_powers.(p))
        if family=="ibr"
            filter=coil.+im*get(d,"b_filter_shunt",0.)*u
            z=complex.(_sdp_vector(d,"r_filter",n;default=zeros(n)),_sdp_vector(d,"x_filter",n;default=zeros(n)))
            internal=u+z.*filter
            record["filter_current"]=_result_current.(filter);record["internal_voltage"]=_result_voltage.(internal)
            record["internal_power"]=_result_powers.(internal.*conj.(filter))
        end
        device!(family,id,record)
    end
    for (id,d) in get(net,"capacitor",Dict())
        b=d["bus"];tm=d["terminal_map"];plan=_sdp_capacitor_plan(net,d,"capacitor/$id";neutral_map=neutrals)
        u=plan.D*V.(b,tm);coil=im.*plan.b.*u;terminal=transpose(plan.D)*coil
        inject!(b,tm,terminal)
        put!("capacitor",id,Dict("terminals"=>Dict(t=>_result_current(i) for (t,i) in zip(tm,terminal)),
            "q"=>-imag(sum(V.(b,tm).*conj.(terminal)))))
        device!("capacitor",id,Dict("coil_voltage"=>_result_voltage.(u),"coil_current"=>_result_current.(coil),"coil_power"=>_result_powers.(u.*conj.(coil))))
    end
    for (id,d) in get(net,"shunt",Dict())
        b=d["bus"];tm=d["terminal_map"];n=length(tm)
        i=_l3f_shunt_matrix(d,n)*V.(b,tm)
        inject!(b,tm,i);device!("shunt",id,Dict("terminal_map"=>copy(tm),"current"=>_result_current.(i),"power"=>_result_powers.(V.(b,tm).*conj.(i))))
    end
    for (kind,table) in get(net,"transformer",Dict()),(id,d) in table
        rec=Dict{String,Any}();ports=Tuple{ComplexF64,ComplexF64}[];earth=0im;detail=Dict{String,Any}()
        if kind=="n_winding"
            p=_sdp_nwinding_plan(net,id,d;neutral_map=neutrals)
            for (k,w) in enumerate(p.ws)
                tm=w["terminal_map"];v=V.(w["bus"],tm);key="n_winding/$id/$k"
                coil=I(:transformer_coil,key,size(p.Ds[k],1));terminal=I(:transformer_winding,key,length(tm));u=p.Ds[k]*v
                rec["w$k"]=Dict(string(j)=>_result_current(coil[j]) for j in eachindex(coil))
                if haskey(w,"s_max")
                    ratings=_sdp_vector(w,"s_max",length(coil))
                    if r isa IVRNLPResult && get(r.numerical_diagnostics,:transformer_nameplate,:ignore)==:bmopftools && w["s_max"] isa Real
                        ratings ./= length(coil)
                    end
                    for j in eachindex(coil);merge!(rec["w$k"][string(j)],Dict("s"=>abs(u[j]*conj(coil[j])),"s_max"=>ratings[j]));end
                end
                inject!(w["bus"],tm,terminal);append!(ports,zip(v,terminal));earth+=sum(terminal)
                detail["w$k"]=Dict("terminal_map"=>copy(tm),"terminal_current"=>_result_current.(terminal),
                    "terminal_power"=>_result_powers.(_result_product.(v,terminal)),
                    "coil_current"=>_result_current.(coil),"coil_voltage"=>_result_voltage.(u),"coil_power"=>_result_powers.(u.*conj.(coil)))
            end
        else
            p=_sdp_transformer_plan(kind,d,"transformer/$kind/$id");key="$kind/$id"
            for (side,label,D) in ((:from,"fr",p.Df),(:to,"to",p.Dt))
                tm=d["terminal_map_$side"];v=V.(d["bus_$side"],tm);u=D*v
                coil=I(Symbol("transformer_coil_",side),key,size(D,1));terminal=I(Symbol("transformer_",side),key,length(tm))
                reported=kind in ("single_phase","single_phase_autotransformer","open_delta_regulator") ? coil : transpose(D)*coil
                rec[label]=Dict(string(j)=>_result_current(reported[j]) for j in eachindex(reported))
                inject!(d["bus_$side"],tm,terminal);append!(ports,zip(v,terminal));earth+=sum(terminal)
                detail[label]=Dict("terminal_map"=>copy(tm),"terminal_current"=>_result_current.(terminal),
                    "terminal_power"=>_result_powers.(_result_product.(v,terminal)),
                    "coil_current"=>_result_current.(coil),"coil_voltage"=>_result_voltage.(u),"coil_power"=>_result_powers.(u.*conj.(coil)))
            end
            if !isempty(p.bonds)
                detail["bond_current"]=_result_current.(I(:transformer_bond,key,length(p.bonds)))
            end
        end
        rec["ground"]=_result_ground(earth);rec["loss"]=loss(ports)
        if r isa IVRNLPResult
            for entry in get(r.numerical_diagnostics,:transformer_nameplate_report,Any[])
                entry.id==id && entry.kind==kind && entry.enforced || continue
                label=entry.side==:from ? "fr" : "to";port=detail[label]
                u=[complex(x["vr"],x["vi"]) for x in port["coil_voltage"]]
                field=entry.current_basis=="wye_phase_terminal" ? "terminal_current" : "coil_current"
                current=[complex(x["cr"],x["ci"]) for x in port[field]]
                rated=entry.current_basis=="wye_phase_terminal" ? current[entry.channels] : current
                for (k,channel) in enumerate(entry.channels)
                    merge!(rec[label][string(channel)],Dict("s"=>abs(u[k]*conj(rated[k])),"s_max"=>entry.limit_VA))
                end
            end
        end
        totalp+=rec["loss"]["p_loss"];totalq+=rec["loss"]["q_loss"]
        put!("transformer",id,rec);device!("transformer",id,detail)
    end
    for (id,d) in get(net,"voltage_source",Dict())
        b=d["bus"];tm=d["terminal_map"];nt=get(neutrals,b,nothing);v=V.(b,tm);i=I(:voltage_source,id,length(tm))
        for (k,t) in enumerate(tm)
            t in get(net["bus"][b],"perfectly_grounded_terminals",[]) && (i[k]=_RESULT_NAN)
        end
        inject!(b,tm,i,-1);vn=nt===nothing ? 0im : V(b,nt)
        rec=Dict{String,Any}()
        for k in eachindex(tm)
            tm[k]==nt && continue
            s=(v[k]-vn)*conj(i[k]);rec[tm[k]]=merge(_result_current(i[k]),Dict("ps"=>real(s),"qs"=>imag(s)))
        end
        put!("voltage_source",id,rec)
        device!("voltage_source",id,Dict("terminal_map"=>copy(tm),"terminal_current"=>_result_current.(i),"terminal_power"=>_result_powers.(_result_product.(v,i))))
    end
    for (b,d) in net["bus"],t in get(d,"perfectly_grounded_terminals",[])
        get!(out["ground"],b,Dict{String,Any}())[t]=_result_ground(balance[(b,t)])
    end
    out["losses"]=Dict("p_loss"=>totalp,"q_loss"=>totalq)
    native=hasproperty(r,:relaxed_powers) ? r.relaxed_powers : hasproperty(r,:powers) ? r.powers : Dict()
    for ((f,id),s) in native
        get!(extras["native_powers"],string(f),Dict{String,Any}())[id]=_result_powers.(s)
    end
    if r isa SDPResult
        extras["native_moments"]=Dict("coordinate_system"=>"internal reduced coordinates; not physical phasors","matrix"=>_result_matrix(r.moment))
    elseif r isa SOCResult
        extras["native_moments"]=Dict("coordinate_system"=>"internal local blocks; no PSD completion asserted","blocks"=>_result_matrix.(r.blocks))
    elseif r isa BranchFlowSDPResult
        extras["native_moments"]=Dict("voltage_V2"=>Dict(k=>_result_matrix(v) for (k,v) in r.voltage_moments),
            "branch_power_VA"=>Dict(k=>_result_matrix(v) for (k,v) in r.branch_power_moments),
            "branch_current_A2"=>Dict(k=>_result_matrix(v) for (k,v) in r.branch_current_moments))
    end
    if r isa L3FResult
        extras["native_model"]=Dict("buses"=>deepcopy(r.buses),"lines"=>deepcopy(r.lines),"transformers"=>deepcopy(r.transformers),"generators"=>deepcopy(r.generators),"sources"=>deepcopy(r.sources))
    end
    # Record unavailable leaves explicitly; NaNs retain BMOPFTools round-trip
    # conventions. Strict JSON null conversion is an explicit writer option.
    function inventory(x,path=String[])
        if x isa AbstractDict
            for (k,v) in x;k=="_formulationlab" && continue;inventory(v,[path;string(k)]);end
        elseif x isa AbstractVector
            for (k,v) in enumerate(x);inventory(v,[path;string(k)]);end
        elseif x isa Real && !isfinite(x)
            push!(missing,Dict("path"=>path,"reason"=>"unavailable_or_not_identifiable_from_retained_result"))
        end
    end
    inventory(out)
    for key in ("devices","native_powers","native_moments","native_model")
        haskey(extras,key) && inventory(extras[key],["_formulationlab",key])
    end
    _result_json_tree(out)
end
result_dict(b::Union{IVRNLPBuild,LinIVRBuild,SDPBuild,SOCBuild,BranchFlowSDPBuild,L3FBuild},r::AbstractSolveResult)=result_dict(_result_network(b),r)
result_dict(r::L3FResult)=result_dict(r.network,r)

"""Write a BMOPFTools-style result dictionary to a path or IO.

`nonfinite=:preserve` matches BMOPFTools' NaN/Inf convention. `:null` emits
strict JSON nulls; this is deliberately not an identical numeric round trip.
"""
function write_result(result::AbstractDict,io::IO;indent::Union{Int,Nothing}=2,nonfinite=:preserve)
    nonfinite in (:preserve,:null) || throw(ArgumentError("nonfinite must be :preserve or :null"))
    indent===nothing || 0<=indent<=typemax(UInt16) || throw(ArgumentError("invalid indentation"))
    convert(x::AbstractDict)=Dict(string(k)=>convert(v) for (k,v) in x)
    convert(x::AbstractVector)=map(convert,x)
    convert(x)=x isa Real && !isfinite(x) ? nothing : x
    value=nonfinite==:null ? convert(result) : result
    indent===nothing ? JSON3.write(io,value;allow_inf=nonfinite==:preserve) :
        JSON3.pretty(io,value,JSON3.AlignmentContext(;indent=UInt16(indent));allow_inf=nonfinite==:preserve)
    nothing
end
write_result(result::AbstractDict,path::AbstractString;kwargs...)=open(io->write_result(result,io;kwargs...),path,"w")
"""Read a result dictionary from IO, a file path, or JSON text (`from_string=true`)."""
read_result(io::IO)=JSON3.read(io,Dict{String,Any};allow_inf=true)
read_result(src::AbstractString;from_string=false)=from_string ? JSON3.read(src,Dict{String,Any};allow_inf=true) : open(read_result,src)
