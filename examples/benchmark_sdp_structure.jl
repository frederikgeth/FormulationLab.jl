# Optional integration environment is used only to reuse the established input
# preparation/parser contract. No NLP solves or new runtime dependencies here.
# julia --project=test/integration examples/benchmark_sdp_structure.jl MANIFEST OUTPUT [REPEATS] [--chordal|--conservative]
include("benchmark_nlp_soc.jl")
using SparseArrays

const SDP_STRUCTURE_PROFILES=(
    (name="baseline",clique_merge=:size,state_scaling=:global),
    (name="cost",clique_merge=:cost,state_scaling=:global),
    (name="scaling",clique_merge=:size,state_scaling=:voltage_region),
    (name="combined",clique_merge=:cost,state_scaling=:voltage_region))
const SDP_CHORDAL_PROFILES=(
    (name="chordal_size_scaled",clique_merge=:size,state_scaling=:voltage_region,decomposition=:chordal,consistency=:local),
    (name="chordal_cost12_w1",clique_merge=:cost,state_scaling=:global,decomposition=:chordal,consistency=:local,clique_size=12,clique_overlap_weight=1.),
    (name="chordal_cost12_w8",clique_merge=:cost,state_scaling=:global,decomposition=:chordal,consistency=:local,clique_size=12,clique_overlap_weight=8.),
    (name="chordal_combined12_w1",clique_merge=:cost,state_scaling=:voltage_region,decomposition=:chordal,consistency=:local,clique_size=12,clique_overlap_weight=1.))
const SDP_CONSERVATIVE_PROFILES=Tuple(merge(p,(name=replace(p.name,"chordal_"=>"auto_"),
    decomposition=:auto,consistency=:auto)) for p in SDP_CHORDAL_PROFILES[2:end])

structure_options(v,sb)=SDPOptions(s_base=sb,objective=:source_import,
    clique_merge=v.clique_merge,state_scaling=v.state_scaling,
    decomposition=get(v,:decomposition,:auto),consistency=get(v,:consistency,:auto),
    clique_size=get(v,:clique_size,32),clique_overlap_weight=get(v,:clique_overlap_weight,8.))

function sdp_structure_run(b)
    local_cliques=get(b.numerical_diagnostics,:consistency,:shared)==:local &&
        b.numerical_diagnostics[:decomposition]==:chordal
    set_optimizer(b.model,FormulationLab.default_sdp_optimizer(Val(:clarabel),
        Val(local_cliques ? :chordal : :dense)))
    for (k,v) in ("verbose"=>false,"tol_feas"=>1e-7,"tol_gap_abs"=>1e-6,
        "tol_gap_rel"=>1e-7,"time_limit"=>60.)
        set_optimizer_attribute(b.model,k,v)
    end
    GC.gc()
    attach=@elapsed MOI.Utilities.attach_optimizer(backend(b.model))
    wall=@elapsed optimize!(b.model)
    s=unsafe_backend(b.model).solver;info=s.info
    # Status acceptance only; retain original-model residuals separately. An
    # OPTIMAL status is not an accuracy or physical-feasibility certificate.
    accepted=termination_status(b.model)==MOI.OPTIMAL && primal_status(b.model)==MOI.FEASIBLE_POINT
    Dict("status"=>string(termination_status(b.model)),"accepted"=>accepted,
        "attach_seconds"=>attach,"optimize_wall_seconds"=>wall,
        "native_solve_seconds"=>s.timers["solve!"].accumulated_data.time*1e-9,
        "reported_solve_seconds"=>info.solve_time,"iterations"=>Int(info.iterations),
        "res_primal"=>info.res_primal,"res_dual"=>info.res_dual,
        "objective_W"=>accepted ? objective_value(b.model)*b.objective_scale : nothing,
        "dual_W"=>accepted && has_duals(b.model) ? dual_objective_value(b.model)*b.objective_scale : nothing,
        "max_scaled_violation"=>has_values(b.model) ? maximum(values(primal_feasibility_report(b.model;atol=0.0));init=0.0) : nothing,
        "A_shape"=>collect(size(s.data.A)),"A_nnz"=>nnz(s.data.A),
        "linear_solver"=>Dict(string(k)=>getfield(info.linsolver,k) for k in fieldnames(typeof(info.linsolver))))
end

function sdp_structure_study(manifest,output,repeats;profiles=SDP_STRUCTURE_PROFILES)
    repeats>=1 || error("REPEATS must be positive")
    cases=JSON3.read(read(manifest,String),Vector{Dict{String,Any}})
    data=Dict{String,Any}("revision"=>readchomp(`git rev-parse HEAD`),
        "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "source_sha256"=>Dict(f=>bytes2hex(sha256(read(joinpath(@__DIR__,"..",f)))) for f in
            ("src/formulations/sdp.jl","src/formulations/sdp_numerics.jl","src/formulations/sdp_sparse.jl")),
        "julia"=>string(VERSION),"clarabel"=>string(pkgversion(Clarabel)),
        "blas_threads"=>BLAS.get_num_threads(),"julia_threads"=>Threads.nthreads(),
        "repeats"=>repeats,"profiles"=>collect(profiles),"cases"=>Any[],
        "settings"=>Dict("tol_feas"=>1e-7,"tol_gap_abs"=>1e-6,"tol_gap_rel"=>1e-7,
            "time_limit"=>60.,"chordal_static_regularization"=>1e-5),
        "note"=>"Fresh optimizer each repeat. Native times exclude JuMP attachment and result recovery. Identical BMOPFTools-style reduced input for all profiles.")
    save()=open(io->JSON3.write(io,finite(data)),output,"w")
    warm_path=first(JSON3.read(read(joinpath(@__DIR__,"results/reduction_manifest.json"),String),Vector{Dict{String,Any}}))["path"]
    warm,sb,_,_=prepare_case(warm_path)
    for v in profiles
        b=build_sdp_opf(warm;options=structure_options(v,sb))
        sdp_structure_run(b)
    end
    for c in cases
        row=copy(c);row["profiles"]=Any[];push!(data["cases"],row);save()
        println("CASE ",c["name"]);flush(stdout)
        try
            net,sb,changes,provenance=prepare_case(c["path"])
            p=prepare_network(net;warn=false)
            row["changes"]=changes;row["parser_provenance"]=provenance
            row["input_sha256"]=bytes2hex(sha256(read(c["path"])))
            row["s_base_VA"]=sb;row["original_buses"]=length(net["bus"])
            row["reduced_buses"]=length(p.network["bus"]);row["reduction"]=reduction_report(p)
            for v in profiles
                entry=Dict{String,Any}("profile"=>v.name,"runs"=>Any[]);push!(row["profiles"],entry);save()
                try
                    println("BUILD ",v.name);flush(stdout)
                    entry["build_seconds"]=@elapsed b=build_sdp_opf(p.network;options=structure_options(v,sb))
                    entry["numerics"]=Dict(k=>val for (k,val) in b.numerical_diagnostics if k!=:bound_report)
                    save()
                    for repeat in 1:repeats
                        r=sdp_structure_run(b);push!(entry["runs"],r);save()
                        println(v.name," ",repeat," ",r["status"]," native=",r["native_solve_seconds"]);flush(stdout)
                        if !r["accepted"] || r["native_solve_seconds"]>30
                            entry["repeat_stop"]="Stop repeating a failed or >30 s exploratory variant";save();break
                        end
                    end
                catch e
                    e isa InterruptException && rethrow()
                    entry["error"]=sprint(showerror,e);println(entry["error"]);flush(stdout)
                end
                save()
            end
        catch e
            e isa InterruptException && rethrow()
            row["error"]=sprint(showerror,e);println(row["error"]);flush(stdout)
        end
        save()
    end
end

if abspath(PROGRAM_FILE)==@__FILE__
    sdp_structure_study(ARGS[1],ARGS[2],length(ARGS)>=3 ? parse(Int,ARGS[3]) : 3;
        profiles="--conservative" in ARGS ? SDP_CONSERVATIVE_PROFILES :
            "--chordal" in ARGS ? SDP_CHORDAL_PROFILES : SDP_STRUCTURE_PROFILES)
end
