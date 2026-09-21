# Compare chordal-ordering choices in IVRSDP and dense/chordal voltage closure
# in BranchFlowSDP on a prepared ENWL feeder.
#
# julia --project=test/integration examples/benchmark_sdp_sparsity.jl \
#   ../BMOPFDraftData/benchmarks/ENWLbenchmark/reduced/network_18_Feeder_9.json \
#   output.json
include("benchmark_nlp_sdp_enwl.jl")

const SPARSITY_S_BASE = 1e4
const SPARSITY_TIME_LIMIT = 120.0
const SPARSITY_REPETITIONS = 3

function _sparsity_mesh(net)
    out=deepcopy(net)
    source_id=first(sort!(collect(keys(out["line"]))))
    id="sparsity_parallel_" * source_id
    haskey(out["line"],id) && error("synthetic parallel line id already exists")
    out["line"][id]=deepcopy(out["line"][source_id])
    out,id,source_id
end

function _sparsity_formulation(name)
    if name==:ivr_minimum_degree || name==:ivr_minimum_fill
        ordering=name==:ivr_minimum_degree ? :minimum_degree : :minimum_fill
        return IVRSDP(;profile=:clarabel,decomposition=:chordal,
            consistency=:local,cone=:real,objective=:source_import,
            scale_objective=true,s_base=SPARSITY_S_BASE,
            clique_size=12,chordal_ordering=ordering)
    elseif name==:bfm_dense
        return BranchFlowSDP(;cone=:real,objective=:source_import,
            scale_objective=true,s_base=SPARSITY_S_BASE,
            voltage_decomposition=:dense)
    elseif name==:bfm_auto
        return BranchFlowSDP(;cone=:real,objective=:source_import,
            scale_objective=true,s_base=SPARSITY_S_BASE)
    elseif name in (:bfm_minimum_degree,:bfm_minimum_fill)
        ordering=name==:bfm_minimum_degree ? :minimum_degree : :minimum_fill
        return BranchFlowSDP(;cone=:real,objective=:source_import,
            scale_objective=true,s_base=SPARSITY_S_BASE,
            voltage_decomposition=:chordal,chordal_ordering=ordering,
            voltage_clique_size=12)
    end
    error("unknown sparsity profile $name")
end

function _sparsity_run(net,name;time_limit=SPARSITY_TIME_LIMIT)
    formulation=_sparsity_formulation(name)
    build_seconds=@elapsed build=build_opf(net,formulation;
        optimizer=MosekTools.Optimizer)
    model=build.model
    set_silent(model);set_time_limit_sec(model,time_limit)
    set_optimizer_attribute(model,"MSK_IPAR_NUM_THREADS",1)
    set_optimizer_attribute(model,"MSK_DPAR_INTPNT_CO_TOL_PFEAS",1e-9)
    set_optimizer_attribute(model,"MSK_DPAR_INTPNT_CO_TOL_DFEAS",1e-9)
    set_optimizer_attribute(model,"MSK_DPAR_INTPNT_CO_TOL_REL_GAP",1e-9)
    solve_seconds=@elapsed result=formulation isa IVRSDP ?
        solve_sdp_opf(build) : solve_branch_flow_sdp(build)
    status=solve_status(result)
    violation=has_values(model) ? try
        maximum(values(primal_feasibility_report(model;atol=0.0));init=0.0)
    catch
        nothing
    end : nothing
    diagnostics=build.numerical_diagnostics
    orders=get(diagnostics,:clique_orders,Int[])
    Dict{String,Any}(
        "profile"=>string(name),
        "formulation"=>formulation isa IVRSDP ? "IVRSDP" : "BranchFlowSDP",
        "termination_status"=>status.termination_status,
        "raw_status"=>raw_status(model),
        "primal_status"=>status.primal_status,
        "optimal"=>status.optimal,
        "objective_W"=>isfinite(result.objective) ? result.objective : nothing,
        "solver_bound_W"=>isfinite(result.solver_objective_bound) ?
            result.solver_objective_bound : nothing,
        "max_scaled_violation"=>violation,
        "build_seconds"=>build_seconds,
        "solve_seconds"=>solve_seconds,
        "variables"=>num_variables(model),
        "constraints"=>num_constraints(model;count_variable_in_set_constraints=false),
        "decomposition"=>string(get(diagnostics,:decomposition,
            get(diagnostics,:voltage_decomposition,:not_required))),
        "chordal_ordering"=>string(get(diagnostics,:chordal_ordering,:not_used)),
        "aggregate_sparsity_edges"=>get(diagnostics,:aggregate_sparsity_edges,nothing),
        "chordal_fill_edges"=>get(diagnostics,:chordal_fill_edges,nothing),
        "cliques"=>get(diagnostics,:cliques,nothing),
        "max_clique_order"=>isempty(orders) ? nothing : maximum(orders),
        "separator_real_dimension"=>get(diagnostics,:separator_real_dimension,nothing),
    )
end

function _sparsity_median(values)
    ordered=sort!(Float64[values...]);n=length(ordered)
    isodd(n) ? ordered[(n+1)÷2] : (ordered[n÷2]+ordered[n÷2+1])/2
end

function _sparsity_repeated(net,name;
                            repetitions=SPARSITY_REPETITIONS,
                            time_limit=SPARSITY_TIME_LIMIT)
    repetitions>=1 || throw(ArgumentError("repetitions must be positive"))
    samples=Any[]
    for repetition in 1:repetitions
        println("  repetition ",repetition,"/",repetitions);flush(stdout)
        push!(samples,_sparsity_run(net,name;time_limit))
        GC.gc()
    end
    structural=("formulation","variables","constraints","decomposition",
        "chordal_ordering","aggregate_sparsity_edges","chordal_fill_edges",
        "cliques","max_clique_order","separator_real_dimension")
    for key in structural
        all(get(sample,key,nothing)==get(first(samples),key,nothing)
            for sample in samples) || error("profile $name changed $key across repetitions")
    end
    row=copy(first(samples))
    row["repetitions"]=repetitions
    row["build_seconds"]=_sparsity_median(sample["build_seconds"] for sample in samples)
    row["solve_seconds"]=_sparsity_median(sample["solve_seconds"] for sample in samples)
    objectives=Float64[sample["objective_W"] for sample in samples
        if sample["objective_W"] isa Real]
    row["objective_span_W"]=isempty(objectives) ? nothing :
        maximum(objectives)-minimum(objectives)
    isempty(objectives) || (row["objective_W"]=_sparsity_median(objectives))
    violations=Float64[sample["max_scaled_violation"] for sample in samples
        if sample["max_scaled_violation"] isa Real]
    row["max_scaled_violation"]=isempty(violations) ? nothing : maximum(violations)
    row["optimal"]=all(get(sample,"optimal",false) for sample in samples)
    statuses=unique(String(sample["termination_status"]) for sample in samples)
    row["termination_status"]=length(statuses)==1 ? only(statuses) : join(statuses,", ")
    row["samples"]=samples
    row
end

_sparsity_fmt(x)=x isa Real ? string(round(x;sigdigits=7)) : "—"

function _sparsity_markdown(data,output)
    path=splitext(output)[1] * ".md"
    open(path,"w") do io
        println(io,"# SDP sparsity experiment")
        println(io)
        println(io,"The IVR rows use the prepared radial feeder. The BranchFlow rows use ",
            "the same feeder with one named line duplicated as a parallel circuit, which ",
            "forces the otherwise conditional global voltage closure. Inputs and outputs ",
            "are SI; model coordinates are per unit on a 10 kVA base. Mosek uses one thread. ",
            "Times are medians of ",data["repetitions"]," fresh build/solve repetitions.")
        println(io)
        println(io,"| Profile | Status | Objective (W) | Objective span (W) | Residual | Build median (s) | Solve median (s) | Variables | Constraints | Fill edges | Cliques | Max order |")
        println(io,"|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for row in data["runs"]
            println(io,"| ",row["profile"]," | ",row["termination_status"]," | ",
                _sparsity_fmt(row["objective_W"])," | ",
                _sparsity_fmt(row["objective_span_W"])," | ",
                _sparsity_fmt(row["max_scaled_violation"])," | ",
                _sparsity_fmt(row["build_seconds"])," | ",
                _sparsity_fmt(row["solve_seconds"])," | ",row["variables"]," | ",
                row["constraints"]," | ",_sparsity_fmt(row["chordal_fill_edges"])," | ",
                _sparsity_fmt(row["cliques"])," | ",
                _sparsity_fmt(row["max_clique_order"])," |")
        end
        println(io)
        println(io,"This is a small repeated structural and numerical experiment, not a ",
            "solver-independent timing claim. Repetitions run in a fixed profile order; ",
            "compare objectives only within one ",
            "formulation/network pair and inspect the residual and termination status.")
    end
    path
end

function run_sdp_sparsity_benchmark(input,output;
        repetitions=SPARSITY_REPETITIONS,time_limit=SPARSITY_TIME_LIMIT)
    net,_,changes,provenance,reduction=_prepare_enwl_case(input)
    mesh,parallel_id,duplicated_id=_sparsity_mesh(net)
    runs=Any[]
    for name in (:ivr_minimum_degree,:ivr_minimum_fill)
        println("RUN ",name);flush(stdout)
        push!(runs,_capture(() -> _sparsity_repeated(net,name;
            repetitions,time_limit)))
        GC.gc()
    end
    for name in (:bfm_dense,:bfm_auto,:bfm_minimum_degree,:bfm_minimum_fill)
        println("RUN ",name);flush(stdout)
        push!(runs,_capture(() -> _sparsity_repeated(mesh,name;
            repetitions,time_limit)))
        GC.gc()
    end
    data=Dict{String,Any}(
        "julia"=>string(VERSION),
        "mosek"=>string(pkgversion(MosekTools.Mosek)),
        "mosek_tools"=>string(pkgversion(MosekTools)),
        "formulationlab_revision"=>_git_revision(pwd()),
        "bmopftools_revision"=>_git_revision(dirname(dirname(pathof(BMOPFTools)))),
        "input"=>abspath(input),"input_sha256"=>bytes2hex(sha256(read(input))),
        "buses"=>length(net["bus"]),"s_base_VA"=>SPARSITY_S_BASE,
        "units"=>Dict("input"=>"SI","model"=>"per_unit","results"=>"SI"),
        "normalization_changes"=>changes,"parser_provenance"=>provenance,
        "kron_reduction"=>reduction,
        "bfm_mesh_modification"=>Dict("added_line"=>parallel_id,
            "duplicate_of"=>duplicated_id),
        "time_limit_seconds"=>time_limit,"threads"=>1,
        "repetitions"=>repetitions,"runs"=>runs)
    open(io->JSON3.write(io,finite(data)),output,"w")
    markdown=_sparsity_markdown(finite(data),output)
    println("WROTE ",output," and ",markdown)
    data
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS) in (2,3) || error("Usage: julia --project=test/integration " *
        "examples/benchmark_sdp_sparsity.jl INPUT.json OUTPUT.json [REPETITIONS]")
    repetitions=length(ARGS)==3 ? parse(Int,ARGS[3]) : SPARSITY_REPETITIONS
    run_sdp_sparsity_benchmark(ARGS[1],ARGS[2];repetitions)
end
