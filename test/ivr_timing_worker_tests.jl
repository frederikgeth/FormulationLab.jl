module IVRTimingWorkerTests
using Test
include("../examples/ivr_timing_worker.jl")
@testset "Native permit binds explicit release to one job and process" begin
    permit=Dict{String,Any}("schema"=>"FormulationLab.native_launch_permit.v1","authorized"=>true,
        "job_sha256"=>"fixture","worker_pid"=>42,"launcher_pid"=>7,"nonce"=>"synthetic-unit-token")
    command=Dict("command"=>"run","nonce"=>"synthetic-unit-token")
    @test valid_permit(permit,command,"fixture",42,7)
    for (key,value) in (("schema","wrong"),("authorized",false),("authorized",1),
        ("job_sha256","other"),("worker_pid",43),("launcher_pid",8),("nonce","wrong"),("nonce",nothing))
        bad=copy(permit);bad[key]=value
        @test !valid_permit(bad,command,"fixture",42,7)
        delete!(bad,key);@test !valid_permit(bad,command,"fixture",42,7)
    end
    @test !valid_permit(permit,Dict("command"=>"abort","nonce"=>"synthetic-unit-token"),"fixture",42,7)
    @test !valid_permit(permit,Dict("command"=>"run"),"fixture",42,7)
end
end
