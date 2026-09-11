# Profile implementation checks, fixed budgets, and an optional linear-solver comparison.
include("benchmark_soc_controlled.jl")
const IMPLEMENTED_VARIANTS=[
    (name="fast",options=(profile=:fast,),solver=(;)),
    (name="balanced",options=(profile=:balanced,),solver=(;)),
    (name="physical_sparse",options=(basis=:physical_sparse,),solver=(;)),
    (name="kim2",options=(profile=:balanced,max_triplets=2),solver=(;)),
    (name="kim4",options=(profile=:balanced,max_triplets=4),solver=(;)),
    (name="balanced_cholmod",options=(profile=:balanced,),solver=(direct_solve_method=:cholmod,)),
]
function implemented_study(output;repeats=3,indices=2:6)
    manifest=JSON3.read(read(joinpath(@__DIR__,"results/reduction_manifest.json"),String),Vector{Dict{String,Any}})
    out=Dict{String,Any}("base_revision"=>readchomp(`git rev-parse HEAD`),"julia"=>string(VERSION),
        "clarabel"=>string(pkgversion(Clarabel)),"blas_threads"=>BLAS.get_num_threads(),
        "repeats"=>repeats,"variants"=>IMPLEMENTED_VARIANTS,"cases"=>Any[])
    save()=open(io->JSON3.write(io,finite(out)),output,"w")
    wn,sb,_,_=prepare_case(manifest[1]["path"]);wp=prepare_network(wn;warn=false)
    for v in IMPLEMENTED_VARIANTS
        b=build_opf(wp,IVRSOC(;s_base=sb,objective=:source_import,v.options...);optimizer=nothing)
        controlled_run(b,wp,(refinement=30,);solver_options=v.solver)
    end
    for c in manifest[indices]
        println("CASE ",c["name"]);flush(stdout)
        net,sb,changes,_=prepare_case(c["path"]);p=prepare_network(net;warn=false)
        row=Dict{String,Any}("name"=>c["name"],"input_sha256"=>bytes2hex(sha256(read(c["path"]))),
            "s_base_VA"=>sb,"changes"=>changes,"reduction"=>reduction_report(p),"models"=>Dict(),"runs"=>Any[])
        push!(out["cases"],row);save()
        row["nlp"],_=reduction_nlp(p.network,sb)
        models=Dict()
        for v in IMPLEMENTED_VARIANTS
            bt=@elapsed b=build_opf(p,IVRSOC(;s_base=sb,objective=:source_import,v.options...);optimizer=nothing)
            models[v.name]=b
            d=b.electrical.numerical_diagnostics
            row["models"][v.name]=Dict("build_seconds"=>bt,"variables"=>num_variables(b.model),
                "blocks"=>size.(b.blocks,1),"numerics"=>Dict(string(k)=>val for (k,val) in d if startswith(string(k),"basis") || k in (:decomposition,:reduced_dimension,:soc_profile,:soc_options)))
            save()
        end
        for rep in 1:repeats,j in eachindex(IMPLEMENTED_VARIANTS)
            v=IMPLEMENTED_VARIANTS[mod1(j+rep-1,length(IMPLEMENTED_VARIANTS))]
            println("RUN ",v.name," repeat=",rep);flush(stdout)
            r=Dict{String,Any}("profile"=>v.name,"repeat"=>rep);push!(row["runs"],r);save()
            try
                merge!(r,controlled_run(models[v.name],p,(refinement=30,);recover=rep==1,solver_options=v.solver))
                if r["publishable"];r["nlp_minus_soc_W"]=row["nlp"]["source_W"]-r["objective_W"];end
                println(r["status"]," native=",round(r["native_solve_seconds"];digits=3)," gap=",get(r,"nlp_minus_soc_W",nothing))
            catch e
                r["error"]=sprint(showerror,e,catch_backtrace());println(r["error"])
            end
            save();flush(stdout)
        end
    end
    out["complete"]=true;save()
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    implemented_study(ARGS[1];repeats=length(ARGS)>1 ? parse(Int,ARGS[2]) : 3)
end
