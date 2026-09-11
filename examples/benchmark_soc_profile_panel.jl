# Wider ENWL panel. A supervising process may bound compilation/build separately.
include("benchmark_soc_controlled.jl")
function profile_panel(manifest,output)
    cases=JSON3.read(read(manifest,String),Vector{Dict{String,Any}})
    out=Dict{String,Any}("revision"=>readchomp(`git rev-parse HEAD`),"julia"=>string(VERSION),
        "clarabel"=>string(pkgversion(Clarabel)),"blas_threads"=>BLAS.get_num_threads(),
        "note"=>"one run per profile, screening only; native solve time excludes build and extraction", "cases"=>Any[])
    save()=open(io->JSON3.write(io,finite(out)),output,"w")
    # Same small warmup in every process, even when the manifest selects a large case.
    warm_manifest=JSON3.read(read(joinpath(@__DIR__,"results/reduction_manifest.json"),String),Vector{Dict{String,Any}})
    wn,sb,_,_=prepare_case(first(warm_manifest)["path"]);wp=prepare_network(wn;warn=false)
    for profile in (:clarabel,:fast,:balanced)
        b=build_opf(wp,IVRSOC(;profile,s_base=sb,objective=:source_import);optimizer=nothing)
        controlled_run(b,wp,(refinement=30,))
    end
    for c in cases
        row=Dict{String,Any}("name"=>c["name"],"path"=>c["path"],"runs"=>Any[],"stage"=>"prepare")
        push!(out["cases"],row);save();println("CASE ",c["name"]);flush(stdout)
        try
            net,sb,changes,_=prepare_case(c["path"]);p=prepare_network(net;warn=false)
            row["buses"]=length(net["bus"]);row["s_base_VA"]=sb;row["changes"]=changes
            row["input_sha256"]=bytes2hex(sha256(read(c["path"])))
            row["reduction"]=reduction_report(p)
            row["nlp"],_=reduction_nlp(p.network,sb);save()
            for profile in Symbol.(get(c,"profiles",["clarabel","fast","balanced"]))
                r=Dict{String,Any}("profile"=>profile);push!(row["runs"],r)
                row["stage"]="build_$profile";save();GC.gc()
                println(row["stage"]);flush(stdout)
                bt=@elapsed b=build_opf(p,IVRSOC(;profile,s_base=sb,objective=:source_import);optimizer=nothing)
                r["build_seconds"]=bt;r["variables"]=num_variables(b.model)
                r["basis"]=b.electrical.numerical_diagnostics[:basis]
                r["basis_fallback"]=get(b.electrical.numerical_diagnostics,:basis_fallback,false)
                row["stage"]="solve_$profile";save()
                merge!(r,controlled_run(b,p,(refinement=30,)))
                if r["publishable"];r["nlp_minus_soc_W"]=row["nlp"]["source_W"]-r["objective_W"];end
                println(profile," ",r["status"]," ",r["native_solve_seconds"]);flush(stdout);save()
            end
            row["stage"]="complete"
        catch e
            row["error"]=sprint(showerror,e,catch_backtrace());row["stage"]="error"
        end
        save()
    end
    out["complete"]=true;save()
end
abspath(PROGRAM_FILE)==(@__FILE__) && profile_panel(ARGS[1],ARGS[2])
