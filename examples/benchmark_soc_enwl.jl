# Run with: julia --project=test examples/benchmark_soc_enwl.jl REDUCED_DIRECTORY OUTPUT_JSON
include("benchmark_soc.jl")
using SHA

function benchmark_soc_enwl(directory,output)
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
    benchmark_soc(raw;s_base=sb,remove_source_generators=true,max_rounds=2)
    data=Dict("julia"=>string(VERSION),"clarabel"=>string(pkgversion(Clarabel)),
              "blas_threads"=>1,"separation_tolerance"=>1e-6,"max_rounds"=>30,
              "time_limit_seconds"=>90.,"warmup"=>"all variants on the 5-bus feeder, two cut rounds",
              "cases"=>Any[])
    for file in files
        raw,sb=input(file)
        rows=benchmark_soc(raw;s_base=sb,remove_source_generators=true)
        push!(data["cases"],Dict("file"=>file,"sha256"=>bytes2hex(sha256(read(joinpath(directory,file)))),
             "buses"=>length(raw["bus"]),"results"=>rows))
        open(io->JSON3.write(io,data),output,"w")
        println("Completed ",file);flush(stdout)
    end
    data
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("Supply the ENWL reduced directory and output JSON path")
    benchmark_soc_enwl(ARGS[1],ARGS[2])
end
