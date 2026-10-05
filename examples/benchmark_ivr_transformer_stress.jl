# Analytical admission is additional to the common solver and physical audits.
module IVRTransformerStressStudy
using JSON3, SHA
include("ivr_transformer_stress_cases.jl")
include("benchmark_ivr_transformer_scaling.jl")
const C=IVRTransformerStressCases
const S=IVRTransformerScalingStudy

function benchmark(output;limit=:capability,segments=48,nlp_scaling_method="none",repetitions=8)
    net=C.case(;limit,segments);expected=C.expected(limit)
    open(io->JSON3.write(io,(;limit,segments,expected,
        provenance="Manufactured ideal-transformer cascade, resistive chain and finite neutral ground; not an external feeder.",
        admission="Every measured trial and excluded warmup must match the independent source-import optimum within 1e-4 W.")),output*".witness.json","w")
    result=S.benchmark(net,output;objective=:source_import,nlp_scaling_method,repetitions,
        source_sha256=bytes2hex(sha256(read(joinpath(@__DIR__,"ivr_transformer_stress_cases.jl")))))
    result["analytical_expected"]=expected
    # Retain failures in the raw record; never silently retry or discard them.
    result["analytical_admission"]=all(get(t,"accepted",false) &&
        isapprox(t["objective"],expected.source_W;atol=1e-4,rtol=0.)
        for p in result["profiles"] for t in [p["warmup"];p["trials"]])
    result["analytical_admission"] || (result["ranking"]["fastest_ipopt"]=nothing)
    open(io->JSON3.write(io,result),output,"w")
    result
end
end
