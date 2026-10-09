# Explicit source-root / B-or-C / instrumented-Ipopt arguments, as for the
# manufactured controller fixture. Captures runtime before and after four
# synthetic-clock correctness solves; never runs a timing campaign.
using Test,JSON3
include("../examples/ivr_timing_worker.jl")
length(ARGS)==3 || error("expected source root, B/C and instrumented Ipopt")
C.A.load_preflight(ARGS[1],ARGS[2])
LinearAlgebra.BLAS.set_num_threads(1)
before=IVRTimingRuntime.capture()
module PhysicalFixture
    include("ivr_timing_controller_integration.jl")
end
after=IVRTimingRuntime.capture()
if haskey(ENV,"FORMULATIONLAB_RUNTIME_EVIDENCE")
    folder=ENV["FORMULATIONLAB_RUNTIME_EVIDENCE"];ispath(folder) && error("new runtime evidence directory required")
    mkpath(folder);C.save(joinpath(folder,"BEFORE.json"),before);C.save(joinpath(folder,"AFTER.json"),after)
end
@testset "Physical execution does not introduce unrecorded runtime files" begin
    changed_keys=sort!([k for k in keys(before) if before[k]!=after[k]])
    @test isempty(changed_keys)
end
