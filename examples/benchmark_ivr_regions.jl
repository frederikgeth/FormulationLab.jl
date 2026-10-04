# Matched regional/full experiments. External input files are never edited.
# Run with --project=test; raw evidence belongs outside the repository.
using Statistics, Profile
include("benchmark_ivr_feeders.jl")

_region_stats(xs) = (;minimum=minimum(xs),q25=quantile(xs,.25),median=median(xs),
                     q75=quantile(xs,.75),maximum=maximum(xs))
_region_measurement(t) = (;seconds=t.time,bytes=t.bytes,gc_seconds=t.gctime)

function region_build_stages(net,mode)
    # Separate warmed diagnostic pass: these times are NOT components of the
    # measured public build, and must not be added to its wall time.
    stages=Dict{String,Any}()
    t=@timed FormulationLab._l3f_input(net);owned=t.value;stages["snapshot"]=_region_measurement(t)
    t=@timed FormulationLab._ivrn_check(owned);stages["preflight"]=_region_measurement(t)
    t=@timed FormulationLab._ivr_electrical_data(owned;s_base=1e4,line_records=true,
        delta_dispatch=:coil,ibr_delta_dispatch=:conductor,source_mode=:affine,record_transformer_bonds=true)
    e=t.value;stages["electrical_assembly"]=_region_measurement(t)
    t=@timed FormulationLab._ivrn_start(owned,e);stages["initialization"]=_region_measurement(t)
    t=@timed mode==:off ? (nothing,nothing) : FormulationLab._ivrn_regions(owned,e)
    plan=last(t.value);stages["certificate"]=_region_measurement(t)
    t=@timed FormulationLab._ivrn_coordinates(e,plan);stages["coordinate_maps"]=_region_measurement(t)
    stages
end

function region_benchmark_trial(net,mode;objective,solver_options)
    build_time=@timed build_opf(net,IVRNLP(specialization=mode,objective=objective);optimizer=Ipopt.Optimizer)
    build=build_time.value
    solve_time=@timed solve_ivr_nlp_opf(build;solver_options)
    result=solve_time.value
    # Everything below this line is outside both timers.
    structure=build.numerical_diagnostics[:specialization_report]
    row=Dict{String,Any}("build"=>_region_measurement(build_time),"solve_and_extract"=>_region_measurement(solve_time),
        "total_s"=>build_time.time+solve_time.time,"strict_accepted"=>result.solve.optimal,
        "termination"=>result.solve.termination_status,"objective"=>isfinite(result.objective) ? result.objective : nothing,
        "variables"=>num_variables(build.model),"constraints"=>num_constraints(build.model;count_variable_in_set_constraints=true),
        "specialization"=>build.numerical_diagnostics[:specialization],"certificate_code"=>structure.code,
        "selected_lines"=>mode==:off ? 0 : length(structure.components),
        "regions"=>mode==:off ? 0 : length(structure.regions),
        "iterations"=>try JuMP.MOI.get(JuMP.backend(build.model),JuMP.MOI.BarrierIterations()) catch; nothing end,
        "physical_passed"=>false,"model_passed"=>false)
    point=nothing
    if result.solve.optimal
        point=ACPoint(voltage=result.voltage_candidate,currents=result.current_candidate)
        audit=physical_residuals(net,result);check=ivr_nlp_point_report(build,point)
        row["physical_passed"]=audit.passed;row["physical_maxima"]=audit.maxima
        row["unassessed"]=audit.unassessed
        row["model_passed"]=check.passed;row["model_constraint_violation"]=check.max_constraint_violation
        row["source_p_W"]=Dict(id=>real.(s) for ((family,id),s) in result.powers if family==:voltage_source)
        row["derivatives"]=feeder_derivative_structure(build.model)
    end
    (;build,result,point,row)
end

function region_benchmark_pair(net,order;objective,solver_options)
    outcomes=Dict{Symbol,Any}();rows=Dict{String,Any}()
    for mode in order
        try
            outcome=region_benchmark_trial(net,mode;objective,solver_options)
            outcomes[mode]=outcome;rows[string(mode)]=outcome.row
        catch err
            err isa InterruptException && rethrow()
            rows[string(mode)]=Dict("error"=>sprint(showerror,err))
        end
    end
    pair=Dict{String,Any}("order"=>string.(order),"modes"=>rows,"accepted"=>false,
        "cross_full"=>false,"cross_regional"=>false,"objectives_match"=>false)
    if length(outcomes)==2 && all(x->x.point!==nothing,values(outcomes))
        f,r=outcomes[:off],outcomes[:conductor_regions]
        pair["cross_full"]=ivr_nlp_point_report(f.build,r.point).passed
        pair["cross_regional"]=ivr_nlp_point_report(r.build,f.point).passed
        pair["objectives_match"]=isapprox(f.result.objective,r.result.objective;atol=1e-3,rtol=1e-7)
        pair["accepted"]=all(x->x.row["physical_passed"] && x.row["model_passed"],values(outcomes)) &&
            pair["cross_full"] && pair["cross_regional"] && pair["objectives_match"]
    end
    pair
end

function region_benchmark_summary(pairs)
    accepted=filter(p->p["accepted"],pairs)
    result=Dict{String,Any}("attempted_pairs"=>length(pairs),"accepted_pairs"=>length(accepted),
        "all_pairs_accepted"=>length(accepted)==length(pairs),
        "note"=>"Distributions describe accepted pairs only. Inspect every failure; no statistical significance or population claim. Ratios are computed within pairs, not from separate medians.")
    isempty(accepted) && return result
    result["modes"]=Dict(mode=>Dict(
        "build_s"=>_region_stats([p["modes"][mode]["build"].seconds for p in accepted]),
        "build_bytes"=>_region_stats([p["modes"][mode]["build"].bytes for p in accepted]),
        "solve_s"=>_region_stats([p["modes"][mode]["solve_and_extract"].seconds for p in accepted]),
        "total_s"=>_region_stats([p["modes"][mode]["total_s"] for p in accepted])) for mode in ("off","conductor_regions"))
    result["paired_regional_over_full"]=Dict(
        "build"=>_region_stats([p["modes"]["conductor_regions"]["build"].seconds/p["modes"]["off"]["build"].seconds for p in accepted]),
        "solve"=>_region_stats([p["modes"]["conductor_regions"]["solve_and_extract"].seconds/p["modes"]["off"]["solve_and_extract"].seconds for p in accepted]),
        "total"=>_region_stats([p["modes"]["conductor_regions"]["total_s"]/p["modes"]["off"]["total_s"] for p in accepted]))
    result
end

"""Compare full and regional IVR on selected external inputs without changing their electrical data.

Use an explicit objective, balanced alternating order and an even repetition
count. Rejected warm-ups and trials remain in the output. Separate feasibility
experiments must use a separate output; they do not repair an optimization run.
"""
function benchmark_ivr_regions(directory,output,files;repetitions=6,objective=:source_import,profiles=false,
        max_cpu_time=30.,max_iter=1000)
    repetitions>=2 && iseven(repetitions) || throw(ArgumentError("use an even repetition count >= 2 to balance order"))
    objective in (:cost,:source_import,:feasibility) || throw(ArgumentError("unknown objective"))
    BLAS.set_num_threads(1)
    solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,bound_relax_factor=0.,acceptable_iter=0,max_iter=max_iter,max_cpu_time=max_cpu_time)
    revision=readchomp(`git -C $(dirname(@__DIR__)) rev-parse HEAD`)
    report=Dict{String,Any}("revision"=>revision,"working_tree_status"=>readchomp(`git -C $(dirname(@__DIR__)) status --short`),
        "runner_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "julia"=>string(VERSION),"jump"=>string(pkgversion(JuMP)),"ipopt"=>string(pkgversion(Ipopt)),
        "cpu"=>Sys.CPU_NAME,"julia_threads"=>Threads.nthreads(),"blas_threads"=>BLAS.get_num_threads(),
        "objective"=>objective,"solver_options"=>solver_options,"repetitions"=>repetitions,"cases"=>Any[],
        "note"=>"Original electrical inputs, explicit objective, provenance-only relocation, no new topology reduction. Each case has an excluded warm-up pair; rejected warm-ups are retained and not timed repeatedly. Fresh unloaded starts, alternating balanced order, no forced GC. Timers include Julia GC; allocated bytes exclude native solver/peak resident memory. Validation and derivative queries are outside timers. Profiles/stages are separate diagnostic runs. Objective equality does not establish global optimality or a meaningful economic scenario.")
    save()=open(io->JSON3.write(io,report),output,"w")
    for (index,file) in enumerate(files)
        path=joinpath(directory,file);case=Dict{String,Any}("file"=>file,"pairs"=>Any[])
        push!(report["cases"],case)
        try
            case["sha256"]=bytes2hex(sha256(read(path)))
            net,detached=compiler_feeder_input(path;detach_legacy_provenance=true)
            case["buses"]=length(net["bus"]);case["lines"]=length(get(net,"line",Dict()))
            case["detached_provenance_paths"]=detached
            case["source_accounting"]=merge(feeder_accounting(net),(;
                note="Original source/generator data retained; the experiment's objective is recorded separately. Colocated independently controlled injections can admit artificial exchanges, including unbounded directions. Objective parity alone does not establish a meaningful supply scenario."))
            case["warmup"]=region_benchmark_pair(net,(:off,:conductor_regions);objective,solver_options)
            save()
            if !case["warmup"]["accepted"]
                case["status"]="warmup_rejected"
            else
                for rep in 1:repetitions
                    order=isodd(rep) ? (:off,:conductor_regions) : (:conductor_regions,:off)
                    pair=region_benchmark_pair(net,order;objective,solver_options)
                    pair["repetition"]=rep;push!(case["pairs"],pair);save()
                    println(file," pair ",rep,": ",pair["accepted"]);flush(stdout)
                end
                case["summary"]=region_benchmark_summary(case["pairs"])
                case["status"]=case["summary"]["all_pairs_accepted"] ? "accepted" : "measured_failures"
                case["build_stages"]=Dict(string(mode)=>region_build_stages(net,mode) for mode in (:off,:conductor_regions))
                if profiles
                    for mode in (:off,:conductor_regions)
                        Profile.clear();@profile build_opf(net,IVRNLP(specialization=mode,objective=objective);optimizer=Ipopt.Optimizer)
                        profile_path=output*".case$index.$mode.profile.txt"
                        open(profile_path,"w") do io
                            Profile.print(IOContext(io,:displaysize=>(10000,240));format=:tree,C=true,mincount=2)
                        end
                        get!(case,"profiles",Dict{String,String}())[string(mode)]=profile_path
                    end
                end
            end
        catch err
            err isa InterruptException && rethrow()
            case["status"]="error";case["error"]=sprint(showerror,err)
        end
        println(file,": ",case["status"]);flush(stdout);save()
    end
    report
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)>=3 || error("Supply input directory, output JSON path and selected file names; optional --profiles")
    benchmark_ivr_regions(ARGS[1],ARGS[2],filter(!=("--profiles"),ARGS[3:end]);profiles="--profiles" in ARGS)
end
