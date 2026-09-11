# Run with: julia --project=test examples/benchmark_soc_enwl.jl REDUCED_DIRECTORY OUTPUT_JSON
include("benchmark_soc.jl")
using SHA

function benchmark_soc_enwl(directory,output;
        reference_path=joinpath(@__DIR__,"results","enwl_cached_nlp_reference_2026-09-11.json"))
    references=isfile(reference_path) ? JSON3.read(read(reference_path,String),Dict{String,Any})["cases"] : []
    files=["network_23_Feeder_3.json","network_11_Feeder_2.json",
           "network_9_Feeder_3.json","network_18_Feeder_5.json"]
    function input(file)
        raw=JSON3.read(read(joinpath(directory,file),String),Dict{String,Any})
        net=_sdp_benchmark_clean(raw)
        sources=Set(d["bus"] for d in values(net["voltage_source"]))
        loads=sum((sum(abs.(complex.(d["p_nom"],d["q_nom"]))) for d in values(net["load"]));init=0.)
        generation=sum((sum(abs.(d["p_max"])) for d in values(net["generator"]) if !(d["bus"] in sources));init=0.)
        raw,max(loads,generation)/3
    end
    BLAS.set_num_threads(1)
    raw,sb=input(first(files))
    benchmark_soc(raw;s_base=sb,remove_source_generators=true)
    data=Dict("julia"=>string(VERSION),"clarabel"=>string(pkgversion(Clarabel)),
              "blas_threads"=>1,"selection"=>"fixed, data only",
              "time_limit_seconds"=>90.,"soc_tol_gap_abs"=>1e-7,"soc_tol_feas"=>1e-8,"warmup"=>"all fixed variants on the 5-bus feeder",
              "cases"=>Any[])
    for file in files
        raw,sb=input(file)
        rows=benchmark_soc(raw;s_base=sb,remove_source_generators=true)
        hash=bytes2hex(sha256(read(joinpath(directory,file))))
        case=Dict("file"=>file,"sha256"=>hash,"buses"=>length(raw["bus"]),"results"=>rows)
        ref=findfirst(r->r["file"]==file && r["sha256"]==hash,references)
        if ref!==nothing
            value=references[ref]["source_W"];case["cached_nlp_source_W"]=value
            for row in rows
                row["nlp_minus_objective_W"]=row["objective_W"]===nothing ? nothing : value-row["objective_W"]
            end
        end
        push!(data["cases"],case)
        open(io->JSON3.write(io,data),output,"w")
        println("Completed ",file);flush(stdout)
    end
    data
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("Supply the ENWL reduced directory and output JSON path")
    benchmark_soc_enwl(ARGS[1],ARGS[2])
end
