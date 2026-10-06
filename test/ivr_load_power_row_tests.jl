# Uses independently constructed SI states from ivr_load_law_tests.jl.
@testset "Independent load row units scale only selected equalities" begin
    for m in (2,3,4),law in ("constant_current","zip","exponential"),direction in (-1.,0.,1.),
        (column,row) in ((1e3,1e2),(2e3,1e5)),mode in (:definitions,:laws,:both),reduced in (false,true)
        net,point=_loadlaw_witness(m,law;direction);n=m==2 ? 1 : 3
        common=(;load_power_lifting=true,load_power_base=column,lifting=:bounded_observations,
            specialization=reduced ? :conductor_difference : :off,
            linear_elimination=reduced ? :passive_blocks : :off,objective=:source_import)
        a=build_opf(net,IVRNLP(;common...))
        options=IVRNLPOptions(;common...,load_power_row_scaling=mode,load_power_row_base=row)
        b=build_opf(net,IVRNLP(options);optimizer=Ipopt.Optimizer)
        ar=ivr_nlp_point_report(a,point);br=ivr_nlp_point_report(b,point)
        @test ar.passed && br.passed && length(br.variable_values)==num_variables(b.model)
        @test b.numerical_diagnostics[:load_power_row_bases]==Dict("d1"=>row)
        @test b.numerical_diagnostics[:load_power_bases]==Dict("d1"=>column)
        @test br.objective≈ar.objective atol=1e-9
        av=Dict(index(v)=>x for (v,x) in ar.variable_values);bv=Dict(index(v)=>x for (v,x) in br.variable_values)
        @test av==bv # Equality scaling must not alter any primal coordinate.
        factors=Dict{Any,Float64}();mu=a.electrical.sb/row
        for rec in a.model.ext[:ivr_lifting].records
            if first(rec.key)==:load_law_power && mode in (:definitions,:both)
                factors[index(rec.definition_real)]=mu;factors[index(rec.definition_imag)]=mu
            end
        end
        for rec in values(a.model.ext[:ivr_load_law_rows])
            if mode in (:laws,:both);factors[index(rec.p)]=mu;factors[index(rec.q)]=mu;end
        end
        @test length(factors)==(mode==:both ? 4n : 2n)
        ac=Dict(index(c)=>c for c in all_constraints(a.model;include_variable_in_set_constraints=true))
        bc=Dict(index(c)=>c for c in all_constraints(b.model;include_variable_in_set_constraints=true))
        @test keys(ac)==keys(bc)
        # An off-manifold point prevents zero residuals from hiding missing or
        # accidental row scaling. Unselected equalities and every bound stay put.
        perturb(v)=av[index(v)]+.00037*(mod(index(v).value,7)+1)
        for (idx,c) in ac
            x=constraint_object(c);y=constraint_object(bc[idx]);factor=get(factors,idx,1.)
            xv=value(perturb,x.func);yv=value(perturb,y.func)
            if x.set isa JuMP.MOI.EqualTo
                @test yv-y.set.value≈factor*(xv-x.set.value) atol=1e-10 rtol=1e-10
            else
                @test x.set==y.set && isapprox(xv,yv;atol=1e-10,rtol=1e-10)
            end
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
        @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(options)),point).passed
        @test !physical_residuals(tight,point;delta_dispatch=:coil).passed
    end
end

@testset "Load row-unit ownership, precedence, no-op and validation" begin
    net,point=_loadlaw_witness(4,"zip")
    units=Dict("d1"=>100.)
    b=build_opf(net,IVRNLP(load_power_lifting=true,load_power_row_scaling=:both,
        load_power_row_base=1e3,load_power_row_bases=units))
    units["d1"]=1e6
    @test b.options.load_power_row_bases==Dict("d1"=>100.)
    @test b.numerical_diagnostics[:load_power_row_bases]==Dict("d1"=>100.)
    @test ivr_nlp_point_report(b,point).passed
    for mode in (:off,:definitions,:laws,:both)
        c=build_opf(net,IVRNLP(load_power_lifting=true,load_power_base=500.,load_power_row_scaling=mode))
        @test all(r.row_multiplier==1. for r in c.model.ext[:ivr_lifting].records)
        @test all(r.row_multiplier==1. for r in values(c.model.ext[:ivr_load_law_rows]))
        @test c.numerical_diagnostics[:load_power_row_bases]==(mode==:off ? Dict() : Dict("d1"=>1e4))
    end
    for row in (0.,-1.,Inf,NaN,nextfloat(0.)),perload in (false,true)
        kwargs=perload ? (;load_power_row_bases=Dict("d1"=>row)) : (;load_power_row_base=row)
        @test_throws ArgumentError build_opf(net,IVRNLP(;load_power_lifting=true,load_power_row_scaling=:both,kwargs...))
    end
    @test_throws ArgumentError build_opf(net,IVRNLP(load_power_row_scaling=:both))
    @test_throws ArgumentError build_opf(net,IVRNLP(load_power_lifting=true,load_power_row_scaling=:unknown))
    @test_throws ArgumentError build_opf(net,IVRNLP(load_power_lifting=true,load_power_row_base=1e3))
    @test_throws ArgumentError build_opf(net,IVRNLP(load_power_lifting=true,load_power_row_bases=Dict("d1"=>1e3)))
    @test_throws ArgumentError build_opf(net,IVRNLP(load_power_lifting=true,load_power_row_scaling=:both,load_power_row_bases=Dict("unknown"=>1e3)))
    for law in ("constant_power","constant_impedance")
        copy_net=deepcopy(net);copy_net["load"]["d1"]["model"]=law
        @test_throws ArgumentError build_opf(copy_net,IVRNLP(load_power_lifting=true,load_power_row_scaling=:both,load_power_row_bases=Dict("d1"=>1e3)))
    end
    for (column,row) in ((1e200,1e-200),(1e-200,1e200))
        @test_throws ArgumentError build_opf(net,IVRNLP(load_power_lifting=true,load_power_base=column,load_power_row_scaling=:both,load_power_row_base=row))
    end
end
