module ResultSequenceTests
using Test, FormulationLab, JuMP
include("../examples/ivr_compiler_cases.jl")

# Independently prescribe all three nonzero sequence components. With no load,
# equal end voltages and zero currents satisfy every line and source equation.
# Nonzero neutral voltage makes the phase-to-neutral convention observable.
function witness(m,names,storage,declared)
    net=ivr_compiler_case(conductors=m,segments=1)
    empty!(net["load"])
    tm=m==4 ? [names;"N"] : names
    net["terminal_conventions"]=Dict("neutral"=>m==4 ? ["N"] : String[])
    declared===nothing || (net["terminal_conventions"]["phase"]=declared)
    a=cis(2pi/3);pos=223+5im;neg=7-3im;zero=2+1im
    u=pos.*[1,a^2,a]+neg.*[1,a,a^2].+zero
    vn=m==4 ? 5-2im : 0im
    volts=Dict(t=>ComplexF64(v+vn) for (t,v) in zip(names,u))
    m==4 && (volts["N"]=vn)
    for d in values(net["bus"])
        d["terminal_names"]=copy(storage)
        delete!(d,"perfectly_grounded_terminals")
    end
    source=net["voltage_source"]["source"]
    source["terminal_map"]=copy(tm)
    source["v_magnitude"]=abs.([volts[t] for t in tm])
    source["v_angle"]=angle.([volts[t] for t in tm])
    line=net["line"]["l1"]
    line["terminal_map_from"]=copy(tm);line["terminal_map_to"]=copy(tm)
    point=ACPoint(voltage=Dict((b,t)=>volts[t] for b in keys(net["bus"]) for t in tm),
        currents=Dict((f,id)=>zeros(ComplexF64,m) for (f,id) in
            ((:voltage_source,"source"),(:line_from,"l1"),(:line_to,"l1"))))
    net,point
end

@testset "Sequence recovery uses the operating-bound phase convention" begin
    solved=SolveStatus("LOCALLY_SOLVED","FEASIBLE_POINT",true,true,true,true)
    a=cis(2pi/3)
    cases=((names=["a","b","c"],declared=["a","b","c"],order=["a","b","c"]),
           (names=["a","b","c"],declared=["a","b","c","other"],order=["a","b","c"]),
           (names=["a","b","c"],declared=nothing,order=["a","b","c"]),
           (names=["a","b","c"],declared=["a","a","a"],order=["a","b","c"]),
           (names=["L1","L2","L3"],declared=["L2","L3","L1"],order=["L2","L3","L1"]),
           (names=["L1","L2","L3"],declared=["L1","L1","L1"],order=nothing),
           (names=["L1","L2","L3"],declared=["unused"],order=nothing))
    for m in (3,4),c in cases,perm in ([1,2,3],[3,2,1],[2,3,1])
        phases=c.names[perm]
        storage=m==4 ? [phases[1];"N";phases[2:3]] : phases
        net,p=witness(m,c.names,storage,c.declared)
        order=c.order===nothing ? phases : c.order
        u=[p.voltage[("b1",t)]-(m==4 ? p.voltage[("b1","N")] : 0im) for t in order]
        expected=(positive_sequence=sum([1,a,a^2].*u)/3,
                  negative_sequence=sum([1,a^2,a].*u)/3,zero_sequence=sum(u)/3)
        bus=net["bus"]["b1"]
        limits=(vpos_min=.9abs(expected.positive_sequence),
                vpos_max=1.1abs(expected.positive_sequence),
                vneg_max=abs(expected.negative_sequence)+1.,vzero_max=abs(expected.zero_sequence)+1.)
        for (field,limit) in pairs(limits);bus[string(field)]=[limit];end
        @test physical_residuals(net,p;delta_dispatch=:coil).passed
        for reduced in (false,true)
            options=IVRNLP(objective=:feasibility,s_base=reduced ? 1e3 : 1e5,
                specialization=reduced ? :conductor_difference : :off,
                lifting=reduced ? :bounded_observations : :off)
            build=build_opf(net,options)
            @test build.numerical_diagnostics[:specialization]==(reduced ? :conductor_difference : :off)
            @test ivr_nlp_point_report(build,p).passed
            result=IVRNLPResult(0.,p.voltage,p.currents,
                Dict{Tuple{Symbol,String},Vector{ComplexF64}}(),solved,Dict{Symbol,Any}())
            exported=result_dict(build,result)
            extra=exported["_formulationlab"]["devices"]["bus"]["b1"]
            for (name,value) in pairs(expected)
                actual=extra[string(name)]
                @test complex(actual["vr"],actual["vi"])≈value atol=1e-10
                @test actual["vm"]≈abs(value) atol=1e-10
            end
            # Phase-pair arrays retain local storage order; sequence ordering
            # must not silently reorder these independently indexed fields.
            for k in 1:3
                pair=extra["phase_to_phase"][k]
                @test complex(pair["vr"],pair["vi"])≈p.voltage[("b1",phases[k])]-p.voltage[("b1",phases[mod1(k+1,3)])] atol=1e-10
            end
            io=IOBuffer();write_result(exported,io);seekstart(io)
            @test isequal(read_result(io),exported)
            for (field,value) in (("vpos_min",abs(expected.positive_sequence)+1.),
                    ("vpos_max",.9abs(expected.positive_sequence)),
                    ("vneg_max",.9abs(expected.negative_sequence)),
                    ("vzero_max",.9abs(expected.zero_sequence)))
                tight=deepcopy(net);tight["bus"]["b1"][field]=[value]
                @test !physical_residuals(tight,p;delta_dispatch=:coil).passed
                @test !ivr_nlp_point_report(build_opf(tight,options),p).passed
            end
        end
    end
end
end
