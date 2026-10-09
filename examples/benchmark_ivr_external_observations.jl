"""External-feeder preflight for observation lifting × ordinary current elimination.

Inputs and scenario manifests stay outside Git. This is a correctness screen,
not an isolated timing campaign or a change to the formulation defaults.
"""
module IVRExternalObservationStudy
using FormulationLab, JuMP, Ipopt, JSON3, SHA, LinearAlgebra
include("benchmark_ivr_threephase_transfer.jl")
include("ivr_declared_bound_inventory.jl")
const T=IVRThreePhaseTransferStudy
const M=T.M
const P=T.P
const D=IVRDeclaredBoundInventory
const I=D.I
const SETTINGS=merge(P.STRICT,(nlp_scaling_method="gradient-based",linear_solver="mumps",mumps_pivot_order=7))
save(path,x)=open(io->JSON3.write(io,x),path,"w")
start_point(net)=M.E.S.U.G.H.S.L.start_point(net)

"""Fixed units across arms; source regions use 100 kVA, LV regions 1 kVA.

This particular transfer protocol requires ordinary step-down delta–wye
transformers. Conflicting seeds in a connected region are rejected by the
compiler, rather than resolved by a data-dependent scaling heuristic.
"""
function profiles(net,workload;exchange_target_W)
    ts=M.terms(net,workload;exchange_target_W)
    tx=get(net,"transformer",Dict())
    all(k=="delta_wye" || isempty(v) for (k,v) in tx) ||
        throw(ArgumentError("this external transfer protocol requires delta_wye transformers only"))
    seeds=Dict(d["bus"]=>1e5 for d in values(net["voltage_source"]))
    for d in values(get(tx,"delta_wye",Dict()))
        d["v_nom_from"]>d["v_nom_to"] || throw(ArgumentError("step-down transformer required"))
        haskey(seeds,d["bus_to"]) && seeds[d["bus_to"]]!=1e3 &&
            throw(ArgumentError("conflicting source and LV seeds"))
        seeds[d["bus_to"]]=1e3
    end
    [(;name="$(mode)__$(lifting)",options=IVRNLPOptions(;objective=:power,power_terms=deepcopy(ts),
        objective_scale=1.,s_base=1e5,transformer_nameplate=:bmopftools,lifting,
        lifted_power_base=500.,generator_power_bases=Dict(id=>1e3 for id in keys(net["generator"])),
        current_power_bases=copy(seeds),observation_selection=:all,observation_sharing=:signed,
        specialization=:conductor_regions,linear_elimination=:passive_blocks,device_elimination=mode,
        transformer_scaling=:nominal,row_scaling=:composed,ground_scaling=:voltage,
        kcl_row_max_base=1000.,load_power_lifting=true))
     for mode in (:off,:transformer_currents) for lifting in (:powers,:bounded_observations)]
end

function physical_objective(terms,r)
    sum(terms) do t
        residual=sum(w*(t.quantity==:p ? real(r.powers[(f,id)][k]) : imag(r.powers[(f,id)][k]))
            for ((f,id,k),w) in zip(t.channels,t.weights))-t.target
        t.linear*residual+t.quadratic*residual^2
    end
end

function preflight_trial(net,profile,reference,anchor,start,stem)
    row=Dict{String,Any}("accepted"=>false,"timing_eligible"=>false,"profile"=>profile.name,
        "options"=>P.option_record(profile.options),"solver_options"=>SETTINGS)
    point=nothing
    try
        b=build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer)
        inventory=I.report(b);save(stem*".inventory.json",inventory)
        declarations=D.report(b);save(stem*".bounds.json",declarations)
        row["complete_declared_bound_coverage"]=declarations.complete_declared_bound_coverage
        row["complete_emitted_coverage"]=inventory.complete_emitted_coverage
        row["complete_input_coverage"]=inventory.complete_input_coverage
        row["variables"]=num_variables(b.model)
        encoded=ivr_nlp_point_report(b,start)
        row["start_representable"]=isempty(encoded.missing_channels) &&
            length(encoded.variable_values)==num_variables(b.model) &&
            all(isfinite,values(encoded.variable_values)) &&
            max(encoded.max_binding_residual_pu,encoded.max_reconstruction_residual_pu)<=1e-10
        row["start_representable"] || error("shared physical start is not representable")
        for (v,x) in encoded.variable_values;set_start_value(v,x);end
        r=solve_ivr_nlp_opf(b;solver_options=SETTINGS)
        row["status"]=r.solve.termination_status
        row["ipopt_wall_s_diagnostic_only"]=JuMP.solve_time(b.model)
        row["iterations"]=JuMP.MOI.get(JuMP.backend(b.model),JuMP.MOI.BarrierIterations())
        row["objective"]=isfinite(r.objective) ? r.objective : nothing
        if r.solve.optimal
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            audit=physical_residuals(net,r);own=ivr_nlp_point_report(b,point)
            full=ivr_nlp_point_report(reference,point)
            row["physical_passed"]=audit.passed;row["own_model_passed"]=own.passed
            row["full_model_passed"]=full.passed
            row["anchor_in_profile"]=anchor===nothing ? nothing : ivr_nlp_point_report(b,anchor).passed
            row["bad_physical_records"]=[(;q.label,q.residual,q.unit) for q in audit.records
                if q.residual>getproperty(audit.tolerances,q.unit)]
            si=physical_objective(profile.options.power_terms,r)
            row["physical_power_objective"]=si
            row["objective_reconciled"]=isfinite(r.objective) &&
                isapprox(own.objective,full.objective;atol=1e-6,rtol=1e-8) &&
                isapprox(r.objective,si;atol=1e-6,rtol=1e-8)
            exported=result_dict(b,r);write_result(exported,stem*".result.json")
            row["native_reader_equal"]=isequal(read_result(stem*".result.json"),exported)
            row["accepted"]=inventory.complete_emitted_coverage && declarations.complete_declared_bound_coverage &&
                audit.passed && own.passed && full.passed &&
                row["anchor_in_profile"]!==false && row["objective_reconciled"] && row["native_reader_equal"]
        end
    catch err
        err isa InterruptException && rethrow()
        row["error"]=sprint(showerror,err)
    end
    save(stem*".trial.json",row)
    row,point
end

function run(input,folder)
    isdir(folder) && !isempty(readdir(folder)) && throw(ArgumentError("use a new empty evidence folder"))
    mkpath(folder);BLAS.set_num_threads(1)
    original,detached=P.compiler_feeder_input(input;detach_legacy_provenance=true)
    source_hash=bytes2hex(sha256(read(input)))
    net,manifest=T.scenario(original;filter_level=:low,load_law=:voltage_dependent)
    # Check every original top-level record, including annotations and bounds.
    preserved=all(isequal(v,get(net,k,nothing)) || (k in ("load","generator","ibr") &&
        all(isequal(record,get(net[k],id,nothing)) for (id,record) in v)) for (k,v) in original)
    preserved || error("scenario changed an original record")
    digest=bytes2hex(sha256(JSON3.write(net)));save(joinpath(folder,"INPUT.json"),net)
    save(joinpath(folder,"SCENARIO.json"),manifest)
    target=.35sum(sum(d["p_nom"]) for d in values(net["load"]))
    report=Dict{String,Any}("source"=>abspath(input),"source_sha256"=>source_hash,
        "network_sha256"=>digest,"detached_provenance_paths"=>detached,"original_fields_preserved"=>preserved,
        "exchange_target_W"=>target,"timing_eligible"=>false,"ranking"=>nothing,"trials"=>Any[],
        "scope"=>"Declared DER and parallel-demand scenario on external ordinary-transformer feeders; no multiwinding transfer claim.")
    path=joinpath(folder,"REPORT.json");save(path,report);start=start_point(net)
    for workload in (:quadratic_cost,:exchange_tracking)
        candidates=profiles(net,workload;exchange_target_W=target)
        reference=build_opf(net,IVRNLP(;objective=:power,power_terms=first(candidates).options.power_terms,
            transformer_nameplate=:bmopftools))
        anchor=nothing
        for profile in candidates
            stem=joinpath(folder,"$(workload)__$(profile.name)")
            report["pending_trial"]=basename(stem);save(path,report)
            row,point=preflight_trial(net,profile,reference,anchor,start,stem)
            row["workload"]=string(workload)
            anchor===nothing && row["accepted"] && (anchor=point)
            push!(report["trials"],row);report["pending_trial"]=nothing;save(path,report)
            println(basename(stem)," accepted=",row["accepted"]," ",get(row,"error",get(row,"status","")));flush(stdout)
        end
    end
    report["network_unchanged"]=digest==bytes2hex(sha256(JSON3.write(net)))
    report["source_unchanged"]=source_hash==bytes2hex(sha256(read(input)))
    report["all_trials_accepted"]=all(r["accepted"] for r in report["trials"])
    report["objectives_comparable"]=all((:quadratic_cost,:exchange_tracking)) do workload
        rows=filter(r->r["workload"]==string(workload),report["trials"])
        all(r->r["accepted"] && isapprox(r["objective"],first(rows)["objective"];atol=1e-6,rtol=1e-8),rows)
    end
    save(path,report)
    report
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("usage: input.json output-folder")
    IVRExternalObservationStudy.run(ARGS...)
end
