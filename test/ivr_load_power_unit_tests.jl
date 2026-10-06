# Independent SI witnesses are defined in ivr_load_law_tests.jl.
@testset "Independent load units preserve physical states, bounds and auxiliary inverses" begin
    for m in (2,3,4),law in ("constant_current","zip","exponential"),direction in (-1.,0.,1.),
        unit in (1e2,1e4),reduced in (false,true)
        net,point=_loadlaw_witness(m,law;direction)
        common=(;load_power_lifting=true,lifting=:bounded_observations,lifted_power_base=1e3,
            specialization=reduced ? :conductor_difference : :off,
            linear_elimination=reduced ? :passive_blocks : :off,objective=:source_import)
        a=build_opf(net,IVRNLP(;common...))
        b=build_opf(net,IVRNLP(;common...,load_power_base=unit);optimizer=Ipopt.Optimizer)
        ar=ivr_nlp_point_report(a,point);br=ivr_nlp_point_report(b,point)
        @test ar.passed && br.passed && length(br.variable_values)==num_variables(b.model)
        @test br.objective≈ar.objective atol=1e-9
        @test b.numerical_diagnostics[:load_power_bases]==Dict("d1"=>unit)
        @test num_variables(a.model)==num_variables(b.model)
        load_variables=Set(first(keys(real(u).terms)) for (k,u) in b.model.ext[:ivr_lifting].cache if first(k)==:load_law_power)
        @test length(load_variables)==(m==2 ? 1 : 3)
        for (x,y) in zip(a.model.ext[:ivr_lifting].records,b.model.ext[:ivr_lifting].records)
            factor=y.real in load_variables ? unit/1e3 : 1.
            @test y.scale≈x.scale*factor
            @test br.variable_values[y.real]*factor≈ar.variable_values[x.real] atol=1e-10
            @test br.variable_values[y.imag]*factor≈ar.variable_values[x.imag] atol=1e-10
        end
        r=_loadlaw_solve(b)
        @test r.solve.optimal && physical_residuals(net,r).passed
        @test ivr_nlp_point_report(a,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
        @test r.current_candidate[(:load,"d1")]≈point.currents[(:load,"d1")] atol=1e-5
        d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
        @test isequal(read_result(io),d)
        @test [complex(x["p"],x["q"]) for x in d["_formulationlab"]["native_powers"]["load"]["d1"]]≈r.powers[(:load,"d1")]
        tm=net["bus"]["b1"]["terminal_names"]
        u=point.voltage[("b1",tm[1])]-point.voltage[("b1",tm[m==3 ? 2 : m])]
        tight=deepcopy(net);tight["bus"]["b1"][m==3 ? "vpp_min" : "vpn_min"][1]=1.01abs(u)
        @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(;common...,load_power_base=unit)),point).passed
        @test !physical_residuals(tight,point;delta_dispatch=:coil).passed
    end
end

@testset "Per-load unit precedence, ownership and invalid declarations" begin
    net,point=_loadlaw_witness(4,"zip")
    net["load"]["d1"]["p_nom"]./=2;net["load"]["d1"]["q_nom"]./=2
    net["load"]["d2"]=deepcopy(net["load"]["d1"])
    currents=deepcopy(point.currents);currents[(:load,"d1")]./=2;currents[(:load,"d2")]=copy(currents[(:load,"d1")])
    p=ACPoint(;voltage=point.voltage,currents)
    units=Dict("d1"=>100.)
    opts=IVRNLPOptions(load_power_lifting=true,lifted_power_base=1e3,load_power_base=1e4,load_power_bases=units)
    b=build_opf(net,IVRNLP(opts));units["d1"]=1e6
    @test b.options.load_power_bases==Dict("d1"=>100.)
    @test b.numerical_diagnostics[:load_power_bases]==Dict("d1"=>100.,"d2"=>1e4)
    @test ivr_nlp_point_report(b,p).passed
    for (k,u) in b.model.ext[:ivr_lifting].cache
        first(k)==:load_law_power || continue
        v=first(keys(real(u).terms));unit=k[2]=="d1" ? 100. : 1e4
        @test coefficient(real(u),v)==unit/b.electrical.sb
    end
    for kwargs in ((;), (;lifted_power_base=2e3), (;load_power_base=3e3), (;load_power_bases=Dict("d1"=>4e3)))
        c=build_opf(net,IVRNLP(;load_power_lifting=true,kwargs...))
        expected=get(kwargs,:load_power_base,get(kwargs,:lifted_power_base,1e4))
        @test c.numerical_diagnostics[:load_power_bases]["d2"]==expected
    end
    for unit in (0.,-1.,NaN,Inf,nextfloat(0.)),perload in (false,true)
        kwargs=perload ? (;load_power_bases=Dict("d1"=>unit)) : (;load_power_base=unit)
        @test_throws ArgumentError build_opf(net,IVRNLP(;load_power_lifting=true,kwargs...))
    end
    @test_throws ArgumentError build_opf(net,IVRNLP(load_power_base=1e3))
    @test_throws ArgumentError build_opf(net,IVRNLP(load_power_bases=Dict("d1"=>1e3)))
    @test_throws ArgumentError build_opf(net,IVRNLP(load_power_lifting=true,load_power_bases=Dict("unknown"=>1e3)))
    for law in ("constant_power","constant_impedance")
        copy_net=deepcopy(net);copy_net["load"]["d1"]["model"]=law
        @test_throws ArgumentError build_opf(copy_net,IVRNLP(load_power_lifting=true,load_power_bases=Dict("d1"=>1e3)))
    end
    @test_throws ArgumentError build_opf(net,IVRNLP(s_base=1e-200,load_power_lifting=true,load_power_base=1e200))
end
