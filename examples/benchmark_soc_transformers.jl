# Run with: julia --project=test examples/benchmark_soc_transformers.jl OUTPUT_JSON
include("benchmark_soc.jl")
include("../test/sdp_transformer_fixtures.jl")

function benchmark_soc_transformers(output)
    BLAS.set_num_threads(1)
    function fixture(kind)
        net=_sdp_tx_case(kind;tap=1.03)
        _sdp_zload!(net,"l",net["bus"]["t"]["terminal_names"][1:2],0.1-0.03im)
        net
    end
    benchmark_soc(fixture("single_phase"))
    data=Dict("julia"=>string(VERSION),"clarabel"=>string(pkgversion(Clarabel)),
        "blas_threads"=>1,"load"=>"constant impedance 0.1 - j0.03 S, fixed tap 1.03", "cases"=>Any[])
    for kind in ("single_phase","center_tap","delta_wye","wye_delta","single_phase_autotransformer","open_delta_regulator")
        push!(data["cases"],Dict("transformer"=>kind,"results"=>benchmark_soc(fixture(kind))))
        open(io->JSON3.write(io,data),output,"w")
    end
    data
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("Supply output JSON path")
    benchmark_soc_transformers(only(ARGS))
end
