module IVRTransferPreflightTests
using Test, FormulationLab, JSON3, JuMP
include("../examples/ivr_transfer_preflight.jl")
include("sdp_transformer_fixtures.jl")
const P=IVRTransferPreflight
json(x)=JSON3.read(JSON3.write(x),Dict{String,Any})
@testset "Activity distinguishes inactive and violated rows" begin
    m=Model();@variable(m,x)
    c=@build_constraint(x<=2)
    @test P.row_activity(c;atol=1e-7,value_of=f->2.).near_boundary
    @test !P.row_activity(c;atol=1e-7,value_of=f->1.).near_boundary
    violated=P.row_activity(c;atol=1e-7,value_of=f->3.)
    @test !violated.near_boundary && violated.normalized_slack<0
    @test_throws ArgumentError P.row_activity(c;atol=1e-7,value_of=f->NaN)
end
@testset "Typed solver controls and frozen finite orders" begin
    settings=P.solver_settings(json(P.SETTINGS))
    @test settings["bound_relax_factor"] isa Float64
    @test settings["max_cpu_time"] isa Float64
    @test settings["acceptable_iter"] isa Int
    @test settings==Dict(string(k)=>v for (k,v) in pairs(P.SETTINGS))
    for (kind,n,reps) in (("portfolio",9,18),("factorial",8,16),("pivot",2,16))
        a=P.orders(kind,"exploration");b=P.orders(kind,"confirmation")
        @test length(a)==reps && b==reverse(a)
        @test all(sort(o)==collect(1:n) for o in a)
        @test all(count(o->o[j]==i,a)==reps÷n for i in 1:n for j in 1:n)
    end
    @test_throws ArgumentError P.orders("portfolio","bad")
    @test_throws ArgumentError P.orders("bad","exploration")
end
function common()
    IVRNLPOptions(s_base=1e4,transformer_nameplate=:bmopftools,transformer_scaling=:nominal,
        ground_scaling=:voltage,row_scaling=:composed,lifting=:off,lifted_power_base=500.,
        load_power_lifting=true,observation_sharing=:signed)
end
@testset "Physical start and complete option interchange" begin
    p=ACPoint(voltage=Dict(("s","a")=>230+im,("s","n")=>0im),
        currents=Dict((:load,"d")=>[2+3im],(:transformer_coil_from,"t")=>[1+2im,3-4im]))
    d=json(P.point_record(p));q=P.read_point(d)
    @test isequal(p.voltage,q.voltage) && isequal(p.currents,q.currents)
    duplicate=deepcopy(d);push!(duplicate["voltage"],first(duplicate["voltage"]))
    @test_throws ArgumentError P.read_point(duplicate)
    bad=deepcopy(d);bad["units"]="pu";@test_throws ArgumentError P.read_point(bad)
    bad=deepcopy(d);bad["currents"][1]["re"]=[Inf];@test_throws ArgumentError P.read_point(bad)
    o=P.W.clone(common();objective=:power,power_terms=[IVRPowerTerm(channels=[(:voltage_source,"s",1)],quadratic=1e-6)],
        current_power_bases=Dict("s"=>1e5),generator_power_bases=Dict("g"=>1e3))
    @test json(P.record(P.read_options(json(P.record(o)))))==json(P.record(o))
    bad=json(P.record(o));delete!(bad,"s_base");@test_throws ArgumentError P.read_options(bad)
end

@testset "Generic frozen preparation and eighteen-arm correctness execution" begin
    mktempdir() do dir
        # Explicitly single-phase transformer: the old external driver rejected it.
        net=_sdp_tx_case("single_phase")
        _sdp_zload!(net,"d",["p","n"],.01-.002im)
        net["load"]["d"]["_merged_from"]=["declared_parent"]
        input=joinpath(dir,"input.json");P.save(input,net);source=P.hashfile(input)
        folder=joinpath(dir,"prepared")
        pre=P.prepare(input,folder;common=common(),exchange_target_W=100.)
        @test pre["ready"] && !pre["optimizer_invoked"] && pre["source_unchanged"]
        @test pre["detached_provenance_paths"]==["/load/d/_merged_from"]
        digest=P.hashfile(joinpath(folder,"PREPARATION.json"))
        @test P.load_prepared(folder,digest)["ready"]
        @test_throws ArgumentError P.load_prepared(folder,"stale")
        @test_throws ArgumentError P.prepare(input,folder;common=common(),exchange_target_W=100.)
        output=joinpath(dir,"correctness")
        report=P.run(folder,output;expected_preparation_sha256=digest)
        report["all_trials_accepted"] || @info "Preflight refusals" [(r["profile"],get(r,"error",get(r,"status",nothing))) for r in report["trials"] if !r["accepted"]]
        @test report["all_trials_accepted"] && report["objectives_comparable"]
        @test report["inputs_unchanged"] && !report["timing_eligible"] && report["ranking"]===nothing
        @test length(report["trials"])==18 && report["pending_trial"]===nothing
        @test length(Set((r["workload"],r["profile"]) for r in report["trials"]))==18
        @test all(r->r["physical_export_shape_equal"] && r["complete_declared_bound_coverage"],report["trials"])
        @test all(!occursin("wall",k) for r in report["trials"] for k in keys(r))
        @test P.hashfile(input)==source
        for r in report["trials"]
            stem=joinpath(output,r["workload"]*"__"*r["profile"])
            @test P.readjson(stem*".trial.json")==r
            @test isfile(stem*".result.json") && P.readjson(stem*".physical.json")["passed"]
            activity=P.readjson(stem*".activity.json")
            @test activity["normalized_tolerance"]==P.TOLERANCES.model_pu
        end
        @test_throws ArgumentError P.run(folder,output;expected_preparation_sha256=digest)
        startfile=joinpath(folder,"START.json");raw=read(startfile);write(startfile,[raw;0x20])
        @test_throws ArgumentError P.load_prepared(folder,digest)
        write(startfile,raw);write(input,"{}")
        @test_throws ArgumentError P.load_prepared(folder,digest)
    end
end

@testset "Unsupported originals remain explicit preparation outcomes" begin
    mktempdir() do dir
        n=_sdp_tx_case("single_phase");push!(n["bus"]["f"]["perfectly_grounded_terminals"],"undeclared")
        input=joinpath(dir,"bad.json");P.save(input,n)
        f=joinpath(dir,"prepared");r=P.prepare(input,f;common=common(),exchange_target_W=100.)
        @test !r["ready"] && haskey(r,"error") && !r["optimizer_invoked"]
        digest=P.hashfile(joinpath(f,"PREPARATION.json"))
        report=P.run(f,joinpath(dir,"not_run");expected_preparation_sha256=digest)
        @test report["planned_trials_not_run"]==18 && isempty(report["trials"])
        @test !report["all_trials_accepted"] && !report["objectives_comparable"]
        @test haskey(report,"preparation_refusal")
    end
end
end
