"""Preparation and correctness-only execution of declared transfer workloads.

Preparation records exact inputs, options and an unloaded linear-circuit start.
Execution requires the recorded preparation hash. A study must freeze its whole
protocol before using this executor on external cases. There is no timing runner.
"""
module IVRTransferPreflight
using FormulationLab, JuMP, Ipopt, JSON3, SHA, LinearAlgebra
include("census_ivr_compiler.jl")
include("ivr_transfer_specification.jl")
include("ivr_declared_bound_inventory.jl")
const W=IVRTransferSpecification
const D=IVRDeclaredBoundInventory
const SETTINGS=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,
    bound_relax_factor=0.,max_iter=500,max_cpu_time=30.,nlp_scaling_method="gradient-based",
    linear_solver="mumps",mumps_pivot_order=7,mumps_pivtol=1e-6)
const TOLERANCES=(start_pu=1e-10,model_pu=1e-7,objective_atol=1e-6,objective_rtol=1e-8,
    voltage_V=1e-5,current_A=1e-6,power_VA=1e-3)
hashfile(path)=bytes2hex(sha256(read(path)))
save(path,x)=open(io->JSON3.write(io,x),path,"w")
readjson(path)=JSON3.read(read(path,String),Dict{String,Any})
record(o::IVRNLPOptions)=(;(k=>getfield(o,k) for k in fieldnames(IVRNLPOptions))...)
require(ok,message)=ok || throw(ArgumentError("transfer preflight: "*message))
function newfolder(folder)
    require(!ispath(folder),"output must be a new directory")
    mkpath(folder)
end

# JSON does not carry Julia/Ipopt option types; integral-valued real options
# must be restored as Float64 (not sent to Ipopt's integer-option setter).
function solver_settings(d)
    require(Set(keys(d))==Set(string.(keys(SETTINGS))),"complete solver setting record required")
    Dict{String,Any}(string(k)=>begin
        v=d[string(k)]
        require(template isa String ? v isa String : W.finite_real(v),"invalid solver option $k")
        convert(typeof(template),v)
    end for (k,template) in pairs(SETTINGS))
end

"""Finite prospective orders; confirmation reverses the entire exploration order."""
function orders(kind,batch)
    require(batch in ("exploration","confirmation"),"unknown batch")
    result=if kind=="portfolio"
        block=[[mod1(i+k,9) for i in 1:9] for k in 0:8]
        vcat(block,reverse.(block))
    elseif kind=="factorial"
        block=[[mod1(i+k,8) for i in (1,2,8,3,7,4,6,5)] for k in 0:7]
        vcat(block,reverse.(block))
    elseif kind=="pivot"
        [isodd(k) ? [1,2] : [2,1] for k in 1:16]
    else
        throw(ArgumentError("unknown comparison kind"))
    end
    batch=="confirmation" ? reverse(result) : result
end

"""SI point interchange with explicit channel identities, including hidden currents."""
function point_record(p::ACPoint)
    require(all(isfinite,values(p.voltage)) && all(all(isfinite,v) for v in values(p.currents)),"nonfinite physical start")
    (;schema="FormulationLab.physical_start.v1",units="SI",
        voltage=[(;bus=b,terminal=t,re=real(v),im=imag(v)) for ((b,t),v) in sort!(collect(p.voltage);by=first)],
        currents=[(;family=string(f),id,re=real.(v),im=imag.(v)) for ((f,id),v) in sort!(collect(p.currents);by=x->string(first(x)))])
end
function read_point(d)
    require(get(d,"schema",nothing)=="FormulationLab.physical_start.v1" && get(d,"units",nothing)=="SI","start schema/units")
    voltage=Dict{Tuple{String,String},ComplexF64}();currents=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    for v in d["voltage"]
        require(v["bus"] isa String && v["terminal"] isa String && W.finite_real(v["re"]) && W.finite_real(v["im"]),"invalid voltage start")
        key=(v["bus"],v["terminal"]);require(!haskey(voltage,key),"duplicate voltage start")
        voltage[key]=complex(v["re"],v["im"])
    end
    for v in d["currents"]
        require(v["family"] isa String && v["id"] isa String && v["re"] isa AbstractVector &&
            v["im"] isa AbstractVector && length(v["re"])==length(v["im"]) &&
            all(W.finite_real,[v["re"];v["im"]]),"invalid current start")
        key=(Symbol(v["family"]),v["id"]);require(!haskey(currents,key),"duplicate current start")
        currents[key]=complex.(v["re"],v["im"])
    end
    p=ACPoint(;voltage,currents);point_record(p);p
end
function read_options(d)
    require(Set(keys(d))==Set(string.(fieldnames(IVRNLPOptions))),"complete option record required")
    kw=Dict{Symbol,Any}()
    for key in fieldnames(IVRNLPOptions)
        v=d[string(key)];T=fieldtype(IVRNLPOptions,key)
        kw[key]=if key==:power_terms
            [IVRPowerTerm(channels=[(Symbol(c[1]),String(c[2]),Int(c[3])) for c in t["channels"]],
                quantity=Symbol(t["quantity"]),weights=Float64.(t["weights"]),target=t["target"],
                linear=t["linear"],quadratic=t["quadratic"]) for t in v]
        elseif T==Symbol
            Symbol(v)
        else
            convert(T,v)
        end
    end
    IVRNLPOptions(;kw...)
end
function linear_start(b)
    e=b.electrical
    z,_,_=FormulationLab._linivr_reference(e;fixed_coordinates=e.fixed_source_coordinates)
    ACPoint(voltage=Dict(k=>(i==0 ? 0im : z[i]*e.vb) for (k,i) in e.voltage),
        currents=Dict((f,id)=>ComplexF64[FormulationLab._linivr_eval(row,z)*e.ib for row in rows]
            for (f,id,_,rows,_) in e.devices))
end

"""Record a bounded two-objective experiment without an optimizer call.

The source remains byte-identical. Known legacy provenance is losslessly detached
by the existing input boundary and retained in the compiler-input metadata.
Preparation refusals are saved outcomes; never substitute another source for them.
"""
function prepare(input,folder;common::IVRNLPOptions,exchange_target_W)
    newfolder(folder)
    report=Dict{String,Any}("schema"=>"FormulationLab.transfer_preparation.v1","ready"=>false,
        "source"=>abspath(input),"source_sha256"=>hashfile(input),"optimizer_invoked"=>false,
        "start_method"=>"unloaded linear circuit with fixed source coordinates; not an OPF solution",
        "common_options"=>record(common),"solver_options"=>SETTINGS,"tolerances"=>TOLERANCES,
        "future_orders"=>Dict(kind=>Dict(batch=>orders(kind,batch) for batch in ("exploration","confirmation"))
            for kind in ("portfolio","factorial","pivot")),
        "exchange_target_W"=>exchange_target_W,"files"=>Dict{String,String}(),"timing_eligible"=>false)
    try
        net,detached=compiler_feeder_input(input;detach_legacy_provenance=true)
        save(joinpath(folder,"COMPILER_INPUT.json"),net);report["detached_provenance_paths"]=detached
        workloads=[W.profiles(net,kind;common,exchange_target_W) for kind in (:quadratic_cost,:exchange_tracking)]
        save(joinpath(folder,"WORKLOADS.json"),[(;kind=w.workload.kind,definition=w.workload,
            reference=record(w.reference),candidates=[(;name=p.name,options=record(p.options)) for p in w.candidates]) for w in workloads])
        reference=build_opf(net,IVRNLP(first(workloads).reference))
        start=linear_start(reference);save(joinpath(folder,"START.json"),point_record(start))
        report["ready"]=true
    catch err
        err isa InterruptException && rethrow()
        report["error"]=sprint(showerror,err)
    end
    report["source_unchanged"]=hashfile(input)==report["source_sha256"]
    report["ready"] &= report["source_unchanged"]
    for name in ("COMPILER_INPUT.json","WORKLOADS.json","START.json")
        path=joinpath(folder,name);isfile(path) && (report["files"][name]=hashfile(path))
    end
    save(joinpath(folder,"PREPARATION.json"),report);report
end

"""Verify exact prepared bytes; this does not establish physical applicability."""
function load_prepared(folder,expected_sha256)
    require(hashfile(joinpath(folder,"PREPARATION.json"))==expected_sha256,"preparation hash changed")
    pre=readjson(joinpath(folder,"PREPARATION.json"))
    require(get(pre,"schema",nothing)=="FormulationLab.transfer_preparation.v1","preparation schema")
    require(get(pre,"optimizer_invoked",nothing)===false && get(pre,"timing_eligible",nothing)===false,"preparation contract")
    require(get(pre,"source_unchanged",false)===true && hashfile(pre["source"])==pre["source_sha256"],"source bytes changed")
    require(Set(keys(pre["files"])) ⊆ Set(["COMPILER_INPUT.json","WORKLOADS.json","START.json"]),"unexpected artifact path")
    for (name,digest) in pre["files"];require(hashfile(joinpath(folder,name))==digest,"changed $name");end
    pre
end
function physical_shape(x)
    x isa AbstractDict && return Dict(k=>physical_shape(v) for (k,v) in x)
    x isa AbstractVector && return physical_shape.(x)
    x isa Real && return isfinite(x) ? :finite : isnan(x) ? :unavailable : :infinite
    x===nothing ? :unavailable : (typeof(x),x)
end
physical_objective(terms,r)=sum(terms) do t
    x=sum(a*(t.quantity==:p ? real(r.powers[(f,id)][k]) : imag(r.powers[(f,id)][k]))
        for ((f,id,k),a) in zip(t.channels,t.weights))-t.target
    t.linear*x+t.quadratic*x^2
end

function trial(net,p,reference,start,anchor,stem,settings,tol)
    row=Dict{String,Any}("profile"=>p["name"],"accepted"=>false,"timing_eligible"=>false,
        "options"=>p["options"],"solver_options"=>settings)
    point=nothing;shape=nothing
    try
        o=read_options(p["options"]);b=build_opf(net,IVRNLP(o);optimizer=Ipopt.Optimizer)
        bounds=D.report(b);inventory=D.I.report(b)
        save(stem*".bounds.json",bounds);save(stem*".inventory.json",inventory)
        row["complete_declared_bound_coverage"]=bounds.complete_declared_bound_coverage
        row["complete_emitted_coverage"]=inventory.complete_emitted_coverage
        row["complete_input_coverage"]=inventory.complete_input_coverage
        encoded=ivr_nlp_point_report(b,start)
        row["start_representable"]=isempty(encoded.missing_channels) && length(encoded.variable_values)==num_variables(b.model) &&
            all(isfinite,values(encoded.variable_values)) &&
            max(encoded.max_binding_residual_pu,encoded.max_reconstruction_residual_pu)<=tol["start_pu"]
        require(row["start_representable"],"shared start is not representable")
        for (v,x) in encoded.variable_values;set_start_value(v,x);end
        r=solve_ivr_nlp_opf(b;solver_options=solver_settings(settings))
        row["status"]=r.solve.termination_status
        row["objective"]=isfinite(r.objective) ? r.objective : nothing
        if r.solve.optimal
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            audit=physical_residuals(net,r;atol=(voltage=tol["voltage_V"],current=tol["current_A"],power=tol["power_VA"]))
            own=ivr_nlp_point_report(b,point;atol=tol["model_pu"])
            full=ivr_nlp_point_report(reference,point;atol=tol["model_pu"])
            row["physical_passed"]=audit.passed;row["own_model_passed"]=own.passed;row["full_model_passed"]=full.passed
            row["anchor_in_profile"]=anchor===nothing ? nothing : ivr_nlp_point_report(b,anchor;atol=tol["model_pu"]).passed
            save(stem*".physical.json",audit)
            obj=physical_objective(o.power_terms,r);row["physical_power_objective"]=obj
            row["objective_reconciled"]=all(isapprox(a,obj;atol=tol["objective_atol"],rtol=tol["objective_rtol"])
                for a in (r.objective,own.objective,full.objective))
            exported=result_dict(b,r);write_result(exported,stem*".result.json")
            row["native_reader_equal"]=isequal(read_result(stem*".result.json"),exported)
            ext=exported["_formulationlab"]
            shape=physical_shape(Dict("tables"=>Dict(k=>exported[k] for k in FormulationLab._RESULT_TABLES),
                "devices"=>ext["devices"],"native_powers"=>ext["native_powers"],"unavailable"=>ext["unavailable"]))
            row["accepted"]=bounds.complete_declared_bound_coverage && inventory.complete_emitted_coverage &&
                audit.passed && own.passed && full.passed && row["anchor_in_profile"]!==false &&
                row["objective_reconciled"] && row["native_reader_equal"]
        end
    catch err
        err isa InterruptException && rethrow()
        row["error"]=sprint(showerror,err)
    end
    row,point,shape
end

"""Run exactly eighteen correctness trials after the study's full protocol freeze.

The supplied digest binds prepared inputs, objectives, starts, units and settings.
Failures remain rows. No wall times are collected or ranked; unequal objectives
remain correctness outcomes and fail the separate comparison gate.
"""
function run(prepared,folder;expected_preparation_sha256)
    pre=load_prepared(prepared,expected_preparation_sha256);newfolder(folder);BLAS.set_num_threads(1)
    report=Dict{String,Any}("schema"=>"FormulationLab.transfer_preflight.v1","preparation_sha256"=>expected_preparation_sha256,
        "preparation"=>abspath(prepared),"trials"=>Any[],"timing_eligible"=>false,"ranking"=>nothing,
        "all_trials_accepted"=>false,"objectives_comparable"=>false,"pending_trial"=>nothing)
    path=joinpath(folder,"REPORT.json")
    if pre["ready"]!==true
        report["preparation_refusal"]=get(pre,"error","preparation not ready")
        report["planned_trials_not_run"]=18;save(path,report);return report
    end
    require(Set(keys(pre["files"]))==Set(["COMPILER_INPUT.json","WORKLOADS.json","START.json"]),"incomplete ready preparation")
    net=readjson(joinpath(prepared,"COMPILER_INPUT.json"));start=read_point(readjson(joinpath(prepared,"START.json")))
    ws=JSON3.read(read(joinpath(prepared,"WORKLOADS.json"),String),Vector{Dict{String,Any}})
    require([w["kind"] for w in ws]==["quadratic_cost","exchange_tracking"] && all(length(w["candidates"])==9 for w in ws),"two objectives and nine arms required")
    for w in ws
        anchor=nothing;baseline_shape=nothing;reference=nothing;reference_error=nothing
        try
            reference=build_opf(net,IVRNLP(read_options(w["reference"])))
        catch err
            err isa InterruptException && rethrow()
            reference_error=sprint(showerror,err)
        end
        for p in w["candidates"]
            stem="$(w["kind"])__$(p["name"])";report["pending_trial"]=stem;save(path,report)
            row,point,shape=reference_error===nothing ?
                trial(net,p,reference,start,anchor,joinpath(folder,stem),pre["solver_options"],pre["tolerances"]) :
                (Dict{String,Any}("profile"=>p["name"],"accepted"=>false,"timing_eligible"=>false,
                    "error"=>"reference model refused: "*reference_error),nothing,nothing)
            row["workload"]=w["kind"]
            if row["accepted"]
                anchor===nothing && (anchor=point;baseline_shape=shape)
                row["physical_export_shape_equal"]=isequal(shape,baseline_shape)
                row["accepted"] &= row["physical_export_shape_equal"]
            end
            save(joinpath(folder,stem*".trial.json"),row);push!(report["trials"],row)
            report["pending_trial"]=nothing;save(path,report)
        end
    end
    load_prepared(prepared,expected_preparation_sha256) # Detect changes during execution.
    report["inputs_unchanged"]=true
    report["all_trials_accepted"]=length(report["trials"])==18 && all(r["accepted"] for r in report["trials"])
    report["objectives_comparable"]=all(ws) do w
        rows=filter(r->r["workload"]==w["kind"],report["trials"])
        all(r->r["accepted"] && isapprox(r["objective"],first(rows)["objective"];
            atol=pre["tolerances"]["objective_atol"],rtol=pre["tolerances"]["objective_rtol"]),rows)
    end
    save(path,report);report
end
end
