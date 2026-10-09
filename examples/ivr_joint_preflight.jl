# Included inside IVRJointReductionStudy. This does not run an optimizer.
_json(x)=JSON3.read(JSON3.write(x),Dict{String,Any})
_require(ok,message)=ok || throw(ArgumentError("joint preflight: "*message))
_finite(x)=x isa Real && !(x isa Bool) && isfinite(x)

# Preserve physical leaf paths and availability, not formulation diagnostics.
function _physical_shape(x)
    x isa AbstractDict && return Dict(k=>_physical_shape(v) for (k,v) in x)
    x isa AbstractVector && return _physical_shape.(x)
    x isa Real && return isfinite(x) ? :finite : isnan(x) ? :unavailable : :infinite
    x===nothing && return :unavailable
    (typeof(x),x)
end

"""Validate a current sixteen-trial joint preflight and its saved artifacts.

Read-only: no solver, output creation, historical report migration or timing
admission. Missing/currently incompatible evidence is rejected. The returned
hashes identify the inspected bytes; campaign isolation and source freezing are
separate requirements. This checks recorded evidence, not arbitrary tampering
of all records together or an independent replay of the circuit equations.
"""
function validate_preflight(folder)
    hashes=Dict{String,String}()
    function readjson(path)
        _require(isfile(path),"missing artifact $(basename(path))")
        raw=read(path);hashes[abspath(path)]=bytes2hex(sha256(raw))
        JSON3.read(String(raw),Dict{String,Any})
    end
    pre=readjson(joinpath(folder,"REPORT.json"))
    for key in ("all_trials_accepted","objectives_comparable","network_unchanged","source_unchanged")
        _require(get(pre,key,false)===true,"failed or absent $key")
    end
    _require(haskey(pre,"pending_trial") && pre["pending_trial"]===nothing,"unfinished preflight")
    _require(get(pre,"timing_eligible",nothing)===false && haskey(pre,"ranking") && pre["ranking"]===nothing,
        "preflight must remain diagnostic")
    input=get(pre,"input","");net=readjson(input)
    _require(hashes[abspath(input)]==get(pre,"source_sha256",nothing),"input bytes changed")
    _require(bytes2hex(sha256(JSON3.write(net)))==get(pre,"network_sha256",nothing),"input network changed")
    target=get(pre,"exchange_target_W",nothing)
    _require(_finite(target),"invalid exchange target")
    physical_digest=FormulationLab._result_digest(FormulationLab._l3f_input(net))
    expected=[(string(work),p) for work in (:quadratic_cost,:exchange_tracking)
        for p in Z.profiles(net,work;exchange_target_W=target,include_broad=true)]
    rows=get(pre,"trials",nothing)
    _require(rows isa AbstractVector && length(rows)==length(expected)==16,"exactly sixteen trials required")
    identities=[(get(r,"workload",nothing),get(r,"profile",nothing)) for r in rows]
    _require(identities==[(work,p.name) for (work,p) in expected],"missing, duplicate or reordered trial identity")
    objectives=Dict{String,Float64}();shapes=Dict{String,Any}();starts=Dict{String,Any}()
    for (index,(row,(work,p))) in enumerate(zip(rows,expected))
        label="$work/$(p.name)"
        for key in ("accepted","start_representable","physical_passed","own_model_passed",
                    "full_model_passed","objective_reconciled","native_reader_equal",
                    "complete_emitted_coverage","complete_declared_bound_coverage")
            _require(get(row,key,false)===true,"$label failed or absent $key")
        end
        _require(get(row,"complete_input_coverage",nothing)===false,"$label overclaims input coverage")
        _require(get(row,"timing_eligible",nothing)===false,"$label is not a preflight trial")
        _require(get(row,"bad_physical_records",nothing)==[],"$label has physical violations")
        _require(get(row,"anchor_in_profile",false)==(index in (1,9) ? nothing : true),"$label reverse-anchor gate")
        _require(get(row,"options",nothing)==_json(P.option_record(p.options)),"$label current options differ")
        _require(get(row,"solver_options",nothing)==_json(E.SETTINGS),"$label solver controls differ")
        value=get(row,"objective",nothing);physical=get(row,"physical_power_objective",nothing)
        _require(_finite(value) && _finite(physical) && isapprox(value,physical;atol=1e-6,rtol=1e-8),"$label objective reconciliation")
        baseline=get!(objectives,work,Float64(value))
        _require(isapprox(value,baseline;atol=1e-6,rtol=1e-8),"$label unequal local objective")
        stem=joinpath(folder,"$(work)__$(p.name)")
        trial=readjson(stem*".trial.json")
        _require(trial==Dict(k=>v for (k,v) in row if k!="workload"),"$label trial artifact differs")
        inv=readjson(stem*".inventory.json")
        _require(get(inv,"schema",nothing)=="FormulationLab.constraint_inventory.v1" &&
            get(inv,"complete_emitted_coverage",false)===true &&
            get(inv,"complete_input_coverage",nothing)===false &&
            get(inv,"uncovered_constraint_ids",nothing)==[] &&
            get(inv,"emitted_constraint_count",-1)==get(inv,"covered_constraint_count",-2),"$label emitted inventory")
        bounds=readjson(stem*".bounds.json")
        _require(get(bounds,"schema",nothing)=="FormulationLab.declared_bound_inventory.v1" &&
            get(bounds,"complete_declared_bound_coverage",false)===true &&
            get(bounds,"complete_emitted_coverage",false)===true &&
            get(bounds,"complete_input_coverage",nothing)===false &&
            all(get(bounds,k,nothing)==[] for k in ("missing","mismatched","unexpected")) &&
            get(bounds,"expected_channel_count",-1)==length(get(bounds,"matched",[])) &&
            all(get(q,"satisfied",false)===true for q in get(bounds,"fixed_setting_checks",[])),"$label declared bounds")
        # Canonical reader accepts intentional unavailable values in source
        # ground currents; compare their locations instead of requiring finiteness.
        resultpath=stem*".result.json"
        _require(isfile(resultpath),"$label missing canonical result")
        hashes[abspath(resultpath)]=bytes2hex(sha256(read(resultpath)))
        result=read_result(resultpath)
        _require(get(result,"feasible",false)===true && get(result,"termination_status",nothing)==get(row,"status",nothing),"$label exported status")
        _require(_finite(get(result,"objective",nothing)) && isapprox(result["objective"],value;atol=1e-6,rtol=1e-8),"$label exported objective")
        ext=get(result,"_formulationlab",Dict())
        _require(get(ext,"units",nothing)=="SI" && get(ext,"native_power_kind",nothing)=="physical_product" &&
            get(ext,"network_sha256",nothing)==physical_digest &&
            get(ext,"objective_definition",nothing)==row["options"]["power_terms"] &&
            get(ext,"initialisation_available",false)===true,"$label physical export contract")
        _require(all(haskey(result,k) for k in FormulationLab._RESULT_TABLES),"$label missing physical table")
        shape=_physical_shape(Dict("tables"=>Dict(k=>result[k] for k in FormulationLab._RESULT_TABLES),
            "devices"=>get(ext,"devices",nothing),"native_powers"=>get(ext,"native_powers",nothing),
            "unavailable"=>get(ext,"unavailable",nothing)))
        _require(shape==get!(shapes,work,shape),"$label physical paths or availability differ")
        initial=get(result,"initialisation",nothing)
        _require(initial isa AbstractDict && !isempty(initial),"$label missing physical initialization")
        base=get!(starts,work,initial)
        _require(_same_start(initial,base),"$label physical voltage start differs")
    end
    # Detect an input/report replacement during inspection as well.
    _require(all(isfile(path) && bytes2hex(sha256(read(path)))==digest for (path,digest) in hashes),"artifact changed during inspection")
    (;passed=true,timing_eligible=false,complete_input_coverage=false,trial_count=length(rows),
        input=abspath(input),source_sha256=pre["source_sha256"],network_sha256=pre["network_sha256"],
        exchange_target_W=target,artifact_sha256=hashes)
end

function _same_start(a,b)
    if a isa AbstractDict && b isa AbstractDict
        return Set(keys(a))==Set(keys(b)) && all(_same_start(a[k],b[k]) for k in keys(a))
    elseif a isa AbstractVector && b isa AbstractVector
        return length(a)==length(b) && all(_same_start(x,y) for (x,y) in zip(a,b))
    end
    _finite(a) && _finite(b) && isapprox(a,b;atol=1e-8,rtol=1e-10)
end
