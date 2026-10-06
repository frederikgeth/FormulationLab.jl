using Test, FormulationLab, JuMP, JSON3
isdefined(@__MODULE__,:NLRT) || include("ivr_nonlinear_trace_tests.jl")
isdefined(@__MODULE__,:_bound_case) || include("ivr_bound_coverage_tests.jl")
isdefined(@__MODULE__,:_ibr_state) || include("ivr_ibr_tests.jl")

function _dispatch_check(b,p)
    c=NLRT.catalog(b);r=NLRT.trace(b,p)
    audit=physical_residuals(b.network,p;delta_dispatch=:coil,ibr_delta_dispatch=:conductor)
    @test c.covered_constraint_count+length(c.outside_scope_constraints)==num_constraints(b.model;count_variable_in_set_constraints=true)
    @test !r.complete_model_coverage
    @test JSON3.read(JSON3.write(r)).complete_model_coverage==false
    @test length(unique(q.label for q in r.dispatch))==length(r.dispatch)
    for label in unique(q.audit_label for q in r.dispatch)
        actual=maximum(q.violation_SI for q in r.dispatch if q.audit_label==label)
        expected=only(q.residual for q in audit.records if q.label==label)
        @test actual≈expected atol=1e-8
    end
    for q in r.dispatch
        d=b.network
        for key in q.source_path;d=d[key];end
        @test q.limit_SI==(q.source_channel===nothing ? d : d[q.source_channel])
        @test abs(q.power_auxiliary_gap_SI)<1e-8
        @test abs(q.reconciliation_error_SI)<1e-8
    end
    for q in r.definitions
        @test abs(q.native_residual_SI)<1e-8
        @test abs(q.reconciliation_error_SI)<1e-8
    end
    r
end

@testset "Original dispatch channels and independently violated bounds" begin
    for m in (2,3,4)
        base,p=_bound_case(m;shunts=true)
        ibr,ip,_,_=_ibr_state(m)
        for (family,net,point) in ((:generator,base,p),(:voltage_source,base,p),(:ibr,ibr,ip))
            id=family==:voltage_source ? "source" : "g"
            b=build_opf(net,IVRNLP());assignment=ivr_nlp_point_report(b,point).variable_values
            physical=b.electrical.sb.*[value(v->assignment[v],real(s))+im*value(v->assignment[v],imag(s)) for s in b.powers[(family,id)]]
            n=family==:voltage_source && m!=3 ? length(physical)-1 : length(physical)
            physical=physical[1:n]
            safe=deepcopy(net);d=safe[string(family)][id]
            for (field,x,lower) in (("p_min",real.(physical),true),("p_max",real.(physical),false),
                                    ("q_min",imag.(physical),true),("q_max",imag.(physical),false))
                d[field]=x.+(lower ? -100. : 100.)
            end
            for field in ("p_min","p_max","q_min","q_max"),k in 1:n,reduced in (false,true),sb in (1e3,1e5)
                bad=deepcopy(safe);lower=endswith(field,"min")
                x=startswith(field,"p") ? real(physical[k]) : imag(physical[k])
                bad[string(family)][id][field][k]=x+(lower ? 10. : -10.)
                b=build_opf(bad,IVRNLP(;s_base=sb,generator_power_bases=family==:generator ? Dict(id=>500.) : Dict{String,Float64}(),
                    lifting=:powers,power_sharing=:generators,
                    specialization=reduced ? :conductor_difference : :off,
                    linear_elimination=reduced ? :passive_blocks : :off))
                r=_dispatch_check(b,point)
                row=only(q for q in r.dispatch if q.family==family && q.id==id && q.field==field && q.channel==k)
                @test row.violation_SI≈10. atol=1e-8
                @test row.basis==(family==:voltage_source ? :terminal : family==:ibr && m==3 ? :conductor_pcc : :connection_coil)
                @test count(q->q.family==family && q.field==field,r.dispatch)==n
            end
        end
    end
end

@testset "Reusable generator bounds resolve live references and SI coordinates" begin
    for m in (2,3,4),reduced in (false,true),powerbase in (500.,1e5)
        net,p=_bound_case(m);n=m==2 ? 1 : 3
        b=build_opf(net,IVRNLP(;s_base=1e4,generator_power_bases=Dict("g"=>powerbase),
            lifting=:powers,power_sharing=:generators,
            specialization=reduced ? :conductor_difference : :off))
        variables=all_variables(b.model);defs=copy(NLRT.catalog(b).definitions)
        for (change,count_per_channel) in (
            ((p_min=fill(-500.,n),p_max=fill(500.,n),q_min=fill(-100.,n),q_max=fill(100.,n)),4),
            ((p_min=fill(100.,n),p_max=fill(100.,n),q_min=zeros(n),q_max=zeros(n)),4),
            ((p_min=nothing,q_max=nothing),2),
            ((p_max=nothing,q_min=nothing),0),
            ((p_min=fill(-100.,n),q_max=fill(25.,n)),2),
            ((p_max=fill(300.,n),q_min=fill(-25.,n)),4),
            ((cost=fill(.2,n),),4))
            old=filter(q->q.family==:generator,NLRT.catalog(b).dispatch)
            update_ivr_generators!(b,Dict("g"=>change))
            for q in old
                haskey(change,Symbol(q.field)) && getproperty(change,Symbol(q.field))===nothing || continue
                @test !is_valid(b.model,q.constraint)
            end
            r=_dispatch_check(b,p)
            @test count(q->q.family==:generator,r.dispatch)==count_per_channel*n
            @test all_variables(b.model)==variables
            @test [q.constraint for q in NLRT.catalog(b).definitions]==[q.constraint for q in defs]
            fresh=build_opf(b.network,IVRNLP(b.options));rf=_dispatch_check(fresh,p)
            @test [(q.label,q.limit_SI,q.form) for q in r.dispatch]==[(q.label,q.limit_SI,q.form) for q in rf.dispatch]
            @test Float64[q.violation_SI for q in r.dispatch]≈Float64[q.violation_SI for q in rf.dispatch] atol=1e-8
        end
        before=JSON3.write(NLRT.trace(b,p))
        @test_throws ArgumentError update_ivr_generators!(b,Dict("g"=>(p_min=fill(999.,n),)))
        @test JSON3.write(NLRT.trace(b,p))==before
        assignment=ivr_nlp_point_report(b,p).variable_values
        x=first(b.generator_variables["g"].p);assignment[x]+=.2
        shifted=NLRT.trace(b;variable_values=assignment);baseline=NLRT.trace(b,p)
        @test [q.electrical_power_SI for q in shifted.dispatch]==[q.electrical_power_SI for q in baseline.dispatch]
        q=only(q for q in shifted.definitions if q.id=="g" && q.quantity==:p && q.channel==1)
        @test q.power_auxiliary_gap_SI≈.2powerbase atol=1e-8
        @test q.native_residual_SI≈-.2powerbase atol=1e-8
        @test maximum(abs(q.reconciliation_error_SI) for q in [shifted.dispatch;shifted.definitions])<1e-8
    end
end

@testset "Source phase expansion, terminal order and shared equality declarations" begin
    net,p=_bound_case(4);d=net["voltage_source"]["source"];perm=[4,2,1,3]
    for field in ("terminal_map","v_magnitude","v_angle");d[field]=d[field][perm];end
    currents=deepcopy(p.currents);currents[(:voltage_source,"source")]=currents[(:voltage_source,"source")][perm]
    p=ACPoint(;voltage=p.voltage,currents)
    for full in (false,true)
        n=full ? 4 : 3
        d["p_min"]=fill(100.,n);d["p_max"]=fill(100.,n)
        d["q_min"]=fill(-100.,n);d["q_max"]=fill(100.,n)
        b=build_opf(net,IVRNLP());r=_dispatch_check(b,p)
        rows=filter(q->q.family==:voltage_source,NLRT.catalog(b).dispatch)
        @test length(rows)==4n
        @test sort!(unique(q.channel for q in rows))==(full ? [1,2,3,4] : [2,3,4])
        for k in (full ? (1:4) : (2:4))
            lo=only(q for q in rows if q.field=="p_min" && q.channel==k)
            hi=only(q for q in rows if q.field=="p_max" && q.channel==k)
            @test lo.constraint==hi.constraint && lo.form==hi.form==:shared_equality
            @test lo.source_channel==(full ? k : k-1)
        end
    end
    # Absent fields are not declarations. Nonfinite user bounds are refused;
    # only internal phase expansion uses infinity to denote an unbounded neutral.
    for family in (:generator,:voltage_source,:ibr)
        net,p=family==:ibr ? _ibr_state(2)[1:2] : _bound_case(2)
        id=family==:voltage_source ? "source" : "g"
        net[string(family)][id]["p_min"]=[-Inf]
        @test_throws IVRNLPInapplicableError build_opf(net,IVRNLP())
    end
    net,p=_bound_case(2)
    net["generator"]["g"]["p_min"]=100.
    r=_dispatch_check(build_opf(net,IVRNLP()),p)
    @test only(q for q in r.dispatch if q.family==:generator).source_channel===nothing
end
