# Follow-up to the controlled study: fixed Kim projections in sparse coordinates.
include("benchmark_soc_controlled.jl")
empty!(CONTROLLED_PROFILES)
append!(CONTROLLED_PROFILES,[
    (name="sparse_kim32_8",strength=:kim,size=32,basis=:sparse,refinement=30),
    (name="sparse_kim12_8",strength=:kim,size=12,basis=:sparse,refinement=30),
])
controlled_study(ARGS[1],length(ARGS)>1 ? parse(Int,ARGS[2]) : 3)
