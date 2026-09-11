# Serial, cold-solver comparison; no changes to library defaults or adaptive cuts.
# julia --project=test/integration examples/benchmark_soc_controlled.jl OUTPUT [REPEATS]
include("benchmark_reduction.jl")
using SparseArrays

const CONTROLLED_PROFILES = [
    (name="linear32", strength=:linear, size=32, basis=:auto, refinement=30),
    (name="physical32", strength=:none, size=32, basis=:auto, refinement=30),
    (name="kim32_8", strength=:kim, size=32, basis=:auto, refinement=30),
    (name="kim12_8", strength=:kim, size=12, basis=:auto, refinement=30),
    (name="sparse_basis32", strength=:linear, size=32, basis=:sparse, refinement=30),
    (name="refine5", strength=:linear, size=32, basis=:auto, refinement=5),
]
function timer_record(t)
    Dict("seconds"=>t.accumulated_data.time*1e-9,
         "calls"=>t.accumulated_data.ncalls,
         "children"=>Dict(k=>timer_record(v) for (k,v) in t.inner_timers))
end
function controlled_model(p,sb,v)
    build_opf(p,IVRSOC(s_base=sb,objective=:source_import,strengthening=v.strength,
        clique_size=v.size,basis=v.basis,max_triplets=8,lnc=:off,
        voltage_recovery=:voltage_tree);optimizer=nothing)
end
function controlled_run(b,p,v;recover=false)
    # Reset optimizer every time: fresh setup and default start, no warm start reuse.
    set_optimizer(b.model,FormulationLab.default_soc_optimizer())
    for (key,value) in ("verbose"=>false,"tol_feas"=>1e-7,"tol_gap_abs"=>1e-6,
                        "tol_gap_rel"=>1e-7,"iterative_refinement_max_iter"=>v.refinement,
                        "time_limit"=>90.)
        set_optimizer_attribute(b.model,key,value)
    end
    GC.gc()
    attach=@elapsed MOI.Utilities.attach_optimizer(backend(b.model))
    optimizer_wall=Ref(0.)
    set_optimize_hook(b.model,(m;kwargs...)->begin
        optimizer_wall[]=@elapsed optimize!(m;ignore_optimize_hook=true,kwargs...)
        nothing
    end)
    wall=@elapsed result=solve_soc_opf(b)
    opt=unsafe_backend(b.model);s=opt.solver;info=s.info
    row=Dict{String,Any}("status"=>result.solve.termination_status,
        "publishable"=>result.solve.publishable,"attach_seconds"=>attach,
        "optimize_wall_seconds"=>optimizer_wall[],"extraction_seconds"=>wall-optimizer_wall[],
        "native_solve_seconds"=>s.timers["solve!"].accumulated_data.time*1e-9,
        "reported_solve_seconds"=>info.solve_time,"iterations"=>Int(info.iterations),
        "timers"=>timer_record(s.timers),"res_primal"=>info.res_primal,"res_dual"=>info.res_dual,
        "gap_abs_scaled"=>info.gap_abs,"gap_rel"=>info.gap_rel,
        "conic_gap_W"=>info.gap_abs*b.electrical.objective_scale,
        "objective_W"=>result.objective,"solver_bound_W"=>result.solver_objective_bound,
        "raw_primal_W"=>info.cost_primal*b.electrical.objective_scale,
        "objective_scale"=>b.electrical.objective_scale,
        "linear_solver"=>Dict(string(k)=>getfield(info.linsolver,k) for k in fieldnames(typeof(info.linsolver))),
        "A_shape"=>collect(size(s.data.A)),"A_nnz"=>nnz(s.data.A),
        "P_nnz"=>nnz(s.data.P),"psd_residual"=>result.psd_residual)
    cones=Dict{String,Any}()
    for c in s.data.cones
        key=string(typeof(c));d=cones[key]=get(cones,key,Dict("count"=>0,"dimensions"=>Int[]))
        d["count"]+=1;push!(d["dimensions"],Clarabel.nvars(c))
    end
    row["solver_cones"]=cones
    @assert all(!occursin("PSD",k) for k in keys(cones))
    if recover && result.solve.publishable
        rt=@elapsed full=reconstruct_solution(p,result;warn=false)
        row["reconstruction_seconds"]=rt
        ph=full.diagnostics["physical"]
        row["max_kcl_A"]=maximum((x.residual for x in ph.records if startswith(x.label,"kcl/"));init=0.)
        row["unassessed"]=ph.unassessed
    end
    row
end
function controlled_study(output,repeats)
    @assert repeats>=1
    manifest=JSON3.read(read(joinpath(@__DIR__,"results/reduction_manifest.json"),String),Vector{Dict{String,Any}})
    cases=manifest[2:end]
    data=Dict{String,Any}("revision"=>readchomp(`git rev-parse HEAD`),
        "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "julia"=>string(VERSION),"clarabel"=>string(pkgversion(Clarabel)),
        "ipopt"=>string(pkgversion(Ipopt)),"blas_threads"=>BLAS.get_num_threads(),
        "julia_threads"=>Threads.nthreads(),"cpu"=>Sys.CPU_NAME,
        "profiles"=>CONTROLLED_PROFILES,"repeats"=>repeats,
        "settings"=>Dict("tol_feas"=>1e-7,"tol_gap_abs"=>1e-6,"tol_gap_rel"=>1e-7,
            "static_regularization_constant"=>1e-7,"time_limit"=>90.),"cases"=>Any[])
    save()=open(io->JSON3.write(io,finite(data)),output,"w")
    # Exercise timer extraction, both basis choices, all cuts, and recovery before measurements.
    warm,sb,_,_=prepare_case(manifest[1]["path"]);wp=prepare_network(warm;warn=false)
    reduction_nlp(warm,sb)
    for v in CONTROLLED_PROFILES
        controlled_run(controlled_model(wp,sb,v),wp,v;recover=true)
    end
    save()
    for c in cases
        println("PREPARE ",c["name"]);flush(stdout)
        net,sb,changes,_=prepare_case(c["path"])
        p=prepare_network(net;warn=false)
        row=Dict{String,Any}("name"=>c["name"],"path"=>c["path"],
            "input_sha256"=>bytes2hex(sha256(read(c["path"]))),
            "changes"=>changes,"s_base_VA"=>sb,"reduction"=>reduction_report(p),
            "original_buses"=>length(net["bus"]),"reduced_buses"=>length(p.network["bus"]),
            "models"=>Dict{String,Any}(),"runs"=>Any[])
        push!(data["cases"],row);save()
        row["nlp_original"],_=reduction_nlp(net,sb)
        row["nlp_reduced"],_=reduction_nlp(p.network,sb);save()
        models=Dict{String,Any}()
        for v in CONTROLLED_PROFILES
            bt=@elapsed b=controlled_model(p,sb,v);models[v.name]=b
            diag=b.electrical.numerical_diagnostics
            row["models"][v.name]=Dict("build_seconds"=>bt,"variables"=>num_variables(b.model),
                "block_orders"=>[size(H,1) for H in b.blocks],
                "numerics"=>Dict(string(k)=>diag[k] for k in (:basis,:decomposition,:state_dimension,:reduced_dimension,:consistency,:electrical_residual) if haskey(diag,k)))
            save()
        end
        # Cyclically rotate the serial order each repeat to reduce order bias.
        for rep in 1:repeats, j in eachindex(CONTROLLED_PROFILES)
            v=CONTROLLED_PROFILES[mod1(j+rep-1,length(CONTROLLED_PROFILES))]
            println("RUN ",c["name"]," ",v.name," repeat=",rep);flush(stdout)
            r=Dict{String,Any}("profile"=>v.name,"repeat"=>rep)
            push!(row["runs"],r);save()
            try
                merge!(r,controlled_run(models[v.name],p,v;recover=rep==1))
                if r["publishable"]
                    r["nlp_minus_soc_W"]=row["nlp_reduced"]["source_W"]-r["objective_W"]
                end
                println("DONE ",r["status"]," native=",round(r["native_solve_seconds"];digits=3)," iterations=",r["iterations"])
            catch e
                r["error"]=sprint(showerror,e,catch_backtrace());println(r["error"])
            end
            flush(stdout);save()
        end
        row["complete"]=true;save();empty!(models);GC.gc()
    end
    data["complete"]=true;save()
end
abspath(PROGRAM_FILE)==(@__FILE__) && controlled_study(ARGS[1],length(ARGS)>1 ? parse(Int,ARGS[2]) : 3)
