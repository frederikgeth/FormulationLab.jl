module IVRDERScenarioTests
using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/ivr_der_scenario.jl")
include("../examples/benchmark_ivr_external_objectives.jl")
const D=IVRDERScenario
const E=IVRExternalObjectiveStudy

function fixture()
    n=E.S.case(:quadratic_cost;segments=2);delete!(n,"generator")
    n["load"]["wye"]=Dict("bus"=>"lv1_b0","terminal_map"=>["a","b","c","n"],"configuration"=>"WYE","p_nom"=>[1000.,500.,0.],"q_nom"=>[100.,0.,0.])
    n["load"]["delta"]=Dict("bus"=>"lv2_b0","terminal_map"=>["a","b","c"],"configuration"=>"DELTA","p_nom"=>[1000.,500.,0.],"q_nom"=>[100.,0.,0.])
    n["load"]["zero"]=Dict("bus"=>"lv1_b0","terminal_map"=>["a","n"],"configuration"=>"SINGLE_PHASE","p_nom"=>[0.],"q_nom"=>[0.])
    n
end
@testset "Additive DER provenance, native connections and refusal" begin
    input=fixture();before=deepcopy(input);net,m=D.augment(input)
    @test input==before
    @test length(net["generator"])==8 && length(m.changes)==8
    @test !haskey(net["generator"],"study_der_zero")
    for (k,v) in input;@test net[k]==v;end
    @test m.total_load_W≈15600. && m.total_active_capacity_W≈23400.
    @test issorted([c.source_load for c in m.changes])
    for c in m.changes
        d=input["load"][c.source_load];g=net["generator"][c.generator_id]
        @test g==c.after && c.before===nothing
        @test g["configuration"]==d["configuration"] && g["terminal_map"]==d["terminal_map"] && g["bus"]==d["bus"]
        @test g["p_max"]==1.5d["p_nom"] && g["s_max"]==g["p_max"]
        @test g["q_min"]==-.5g["p_max"] && g["q_max"]==.5g["p_max"]
    end
    net["generator"]["study_der_wye"]["terminal_map"][1]="changed"
    @test input==before && m.changes[end].after!==net["generator"]["study_der_wye"]
    @test only(c.after for c in m.changes if c.source_load=="wye")["terminal_map"][1]=="a"
    for kw in ((capacity_ratio=0.,),(capacity_ratio=Inf,),(reactive_ratio=-1.,),(reactive_ratio=Inf,),(prefix="",),(capacity_ratio=1e308,))
        @test_throws ArgumentError D.augment(input;kw...)
    end
    for mode in (:generator,:ibr,:negative,:nan,:law,:channels,:terminal,:zero)
        bad=deepcopy(input)
        mode==:generator && (bad["generator"]=Dict("g"=>Dict()))
        mode==:ibr && (bad["ibr"]=Dict("g"=>Dict()))
        mode==:negative && (bad["load"]["wye"]["p_nom"][1]=-1.)
        mode==:nan && (bad["load"]["wye"]["p_nom"][1]=NaN)
        mode==:law && (bad["load"]["wye"]["model"]="constant_current")
        mode==:channels && pop!(bad["load"]["wye"]["p_nom"])
        mode==:terminal && (bad["load"]["wye"]["terminal_map"][1]="missing")
        mode==:zero && foreach(d->d["p_nom"].=0.,values(bad["load"]))
        @test_throws ArgumentError D.augment(bad)
    end
    mktempdir() do dir
        path=joinpath(dir,"source.json");output=joinpath(dir,"scenario.json")
        open(io->JSON3.write(io,input),path,"w");raw=read(path)
        n,report=D.write_scenario(path,output)
        @test read(path)==raw && n==first(D.augment(input))
        @test isfile(output*".manifest.json") && report.source_sha256==bytes2hex(D.sha256(raw))
        @test JSON3.read(read(output,String),Dict{String,Any})==n
        @test_throws ArgumentError D.write_scenario(path,path)
    end
end

@testset "Added DER independent optimum and capability rejection" begin
    original=Dict{String,Any}("bus"=>Dict("b"=>Dict("terminal_names"=>["a","n"],"perfectly_grounded_terminals"=>["n"])),
        "voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>["a","n"],"v_magnitude"=>[230.,0.],"v_angle"=>[0.,0.])),
        "load"=>Dict("d"=>Dict("bus"=>"b","terminal_map"=>["a","n"],"configuration"=>"SINGLE_PHASE","p_nom"=>[3000.],"q_nom"=>[200.])))
    net,_=D.augment(original);start=E.S.U.G.H.S.L.start_point(net)
    # With fixed voltage and unrestricted source exchange, stationarity gives
    # Pg=(0.25-0.10)/(2*0.02)=3.75 kW and Qg=0; both are inside the DER circle.
    ps=E.profiles(net,:quadratic_cost;regional_bases=Dict("b"=>1e3))
    for profile in ps
        b=build_opf(net,IVRNLP(profile.options);optimizer=Ipopt.Optimizer)
        enc=ivr_nlp_point_report(b,start);@test length(enc.variable_values)==num_variables(b.model)
        for (v,x) in enc.variable_values;set_start_value(v,x);end
        r=solve_ivr_nlp_opf(b;solver_options=merge(E.P.STRICT,profile.solver_options))
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test only(r.powers[(:generator,"study_der_d")])≈(3750. + 0im) atol=1e-3
        @test r.objective≈.25*(-.75)+.10*3.75+.02*3.75^2 atol=1e-8
        p=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        bad=deepcopy(net);bad["generator"]["study_der_d"]["s_max"]=[3000.]
        @test !physical_residuals(bad,p;delta_dispatch=:coil).passed
        bounded=build_opf(bad,IVRNLP(profile.options))
        @test !ivr_nlp_point_report(bounded,p).passed
        d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
        @test isequal(read_result(io),d)
    end
end

@testset "Mixed native DER channels including fixed-zero channels" begin
    net,_=D.augment(fixture())
    bases=Dict("hv"=>1e5,"mv"=>1e4,"lv1_b0"=>1e3,"lv2_b0"=>1e3)
    reference=build_opf(net,IVRNLP(objective=:power,power_terms=E.terms(net,:quadratic_cost)))
    start=E.S.U.G.H.S.L.start_point(net);anchor=nothing
    for profile in E.profiles(net,:quadratic_cost;regional_bases=bases)[[1,6]]
        row,p=E.P.trial(net,profile,reference,anchor;initial_point=start)
        @test row["accepted"]
        p===nothing && continue
        anchor===nothing && (anchor=p)
        @test ivr_nlp_point_report(reference,p).passed
        @test row["physical_power_objective"]≈row["objective"] atol=1e-7
    end
end
end
