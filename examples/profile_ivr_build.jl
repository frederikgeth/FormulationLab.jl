# Local preparation measurements. Profile is a Julia standard library; no
# profiler or external feeder dependency is added to the package itself.
using FormulationLab, JuMP, Ipopt, JSON3, LinearAlgebra, Profile, SHA
include("census_ivr_compiler.jl")

function profile_ivr_build(input,output;repetitions=5)
    BLAS.set_num_threads(1)
    net,detached=compiler_feeder_input(input;detach_legacy_provenance=true)
    report=Dict{String,Any}("input"=>abspath(input),"sha256"=>bytes2hex(sha256(read(input))),
        "buses"=>length(net["bus"]),"julia"=>string(VERSION),"jump"=>string(pkgversion(JuMP)),
        "cpu"=>Sys.CPU_NAME,"julia_threads"=>Threads.nthreads(),"blas_threads"=>BLAS.get_num_threads(),
        "base_revision"=>readchomp(`git -C $(dirname(@__DIR__)) rev-parse HEAD`),
        "detached_provenance_paths"=>detached,"trials"=>Any[],
        "note"=>"Working tree may be uncommitted. Warmed build-only measurements; no optimization, no supply-accounting changes. Known provenance relocated in memory, raw dictionary input without schema validation. Allocation counts are not peak resident/native memory.")
    for specialization in (:off,:conductor_difference)
        f=IVRNLP(;specialization)
        warmup=@elapsed build_opf(net,f;optimizer=Ipopt.Optimizer)
        rows=Any[]
        for _ in 1:repetitions
            t=@timed build_opf(net,f;optimizer=Ipopt.Optimizer)
            push!(rows,(;seconds=t.time,bytes=t.bytes,gc_seconds=t.gctime,variables=num_variables(t.value.model)))
        end
        Profile.clear();@profile build_opf(net,f;optimizer=Ipopt.Optimizer)
        profile_path=output*".$specialization.txt"
        open(profile_path,"w") do io
            Profile.print(io;format=:flat,sortedby=:count)
        end
        push!(report["trials"],(;specialization,warmup_s=warmup,measurements=rows,profile_path))
        open(io->JSON3.write(io,report),output,"w")
    end
    report
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("Supply one feeder JSON path and an output JSON path")
    profile_ivr_build(ARGS[1],ARGS[2])
end
