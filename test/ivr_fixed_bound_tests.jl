module IVRFixedBoundTests
using Test, JuMP, FormulationLab, Ipopt
const F=FormulationLab
const M=JuMP.MOI
cert(f,s)=F._ivrn_fixed_bound_certificate(JuMP.ScalarConstraint(f,s))
@testset "Exact represented fixed-bound certificates (no optimizer)" begin
    m=Model(); @variable(m,x); @variable(m,y); @variable(m,z)
    fix(x,0.1);fix(y,-2.)
    q=Rational{BigInt}(0.1)
    @test F._ivrn_exact_scalar(0.1)==q
    @test q != 1//10
    for (s,expected) in ((M.LessThan(0.1),:implied),(M.GreaterThan(0.1),:implied),
                         (M.EqualTo(0.1),:implied),(M.Interval(0.0,0.1),:implied),
                         (M.LessThan(prevfloat(0.1)),:violated),
                         (M.GreaterThan(nextfloat(0.1)),:violated))
        r=cert(x,s); @test r.status==expected; @test r.dependencies[x]==q
    end
    @test cert(pi,M.LessThan(4.)).status==:uncertified
    @test cert(x,M.ZeroOne()).status==:uncertified
    @test cert(x^2,M.LessThan(0.01)).status==:violated
    @test cert(x^2,M.GreaterThan(0.01)).status==:implied
    # Real arithmetic of represented coefficients, not floating-point evaluation.
    f=1e16*x + 1.0*y + 1.0
    r=cert(f,M.EqualTo(0.0))
    @test r.value==big(10)^16*q-1
    @test r.status==:violated
    fix(x,1.0;force=true)
    cancellation=1e16*x - 1e16*y + 1.0
    fix(y,1.0;force=true)
    @test value(v->fix_value(v),cancellation)==0.0
    @test cert(cancellation,M.EqualTo(0.0)).value==1
    @test cert(cancellation,M.EqualTo(0.0)).status==:violated
    @test cert(cancellation,M.LessThan(1.0)).status==:implied
    set_start_value(z,0.0)
    @test cert(z,M.EqualTo(0.0)).status==:uncertified
    set_lower_bound(z,0.0);set_upper_bound(z,0.0)
    @test cert(z,M.EqualTo(0.0)).status==:uncertified
    @test cert(x+z,M.LessThan(10.0)).status==:uncertified
    @test cert(x*z,M.LessThan(10.0)).status==:uncertified
    @test cert(JuMP.NonlinearExpr(:sin,Any[x]),M.LessThan(10.)).status==:uncertified
    @test cert(1.0,M.LessThan(Inf)).status==:uncertified
    @test cert(NaN,M.LessThan(1.)).status==:uncertified
    @test cert(1.0,M.Interval(2.0,1.0)).status==:violated
    c=@constraint(m,x^2+y^2<=2.0)
    n=num_constraints(m;count_variable_in_set_constraints=true)
    @test F._ivrn_fixed_bound_certificate(c).status==:implied
    @test length(F._ivrn_fixed_bound_certificate(c).dependencies)==2
    @test num_constraints(m;count_variable_in_set_constraints=true)==n
    unfix(x)
    @test F._ivrn_fixed_bound_certificate(c).status==:uncertified
    # Separate oracle from exact dyadic inputs; both sides of every boundary.
    for i in -16:16, j in -8:8
        a=i/8; b=j/4
        fix(x,a;force=true);fix(y,b;force=true)
        f=0.5*x^2-0.25*x*y+2.0*y^2+0.125*x-0.5*y+1.0
        want=(1//2)*(i//8)^2-(1//4)*(i//8)*(j//4)+2*(j//4)^2+(1//8)*(i//8)-(1//2)*(j//4)+1
        bound=Float64(want)
        @test cert(f,M.EqualTo(bound)).status==:implied
        @test cert(f,M.EqualTo(bound)).value==want
        @test cert(f,M.LessThan(prevfloat(bound))).status==:violated
        @test cert(f,M.GreaterThan(nextfloat(bound))).status==:violated
    end
end

@testset "Immutable bound tables preserve shared and violated rows" begin
    m=Model();@variable(m,x);@variable(m,y);fix(x,2.)
    good=@constraint(m,x^2<=4.0)
    bad=@constraint(m,x^2<=prevfloat(4.0))
    free=@constraint(m,y^2<=4.0)
    for key in F._IVRN_FIXED_BOUND_TABLES
        m.ext[key]=Any[(;form=:magnitude_upper,constraints=[good,bad,free])]
    end
    count_before=num_constraints(m;count_variable_in_set_constraints=true)
    report=F._ivrn_remove_fixed_bounds!(m)
    @test length(report)==1
    @test count_before-num_constraints(m;count_variable_in_set_constraints=true)==1
    @test !is_valid(m,good) && is_valid(m,bad) && is_valid(m,free)
    @test F._ivrn_validate_fixed_bounds(m)===nothing
    for key in F._IVRN_FIXED_BOUND_TABLES
        q=only(m.ext[key]);@test q.form==:partially_certified_fixed
        @test q.constraints==[bad,free]
        original=F._ivrn_original_bound_constraints(q)
        @test length(original)==3 && original[2:3]==[bad,free]
        @test F._ivrn_fixed_bound_certificate(original[1]).status==:implied
    end
    # Losing all declaration ownership of a certificate must be detected.
    saved=[copy(m.ext[k]) for k in F._IVRN_FIXED_BOUND_TABLES]
    for k in F._IVRN_FIXED_BOUND_TABLES;empty!(m.ext[k]);end
    @test_throws ArgumentError F._ivrn_validate_fixed_bounds(m)
    for (k,rows) in zip(F._IVRN_FIXED_BOUND_TABLES,saved);m.ext[k]=rows;end
    unfix(x);@test_throws ArgumentError F._ivrn_validate_fixed_bounds(m)
end

include("../examples/ivr_compiler_cases.jl")
include("../examples/ivr_declared_bound_inventory.jl")
const D=IVRDeclaredBoundInventory
const STRICT=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.)
@testset "Certified bounds: physical equivalence, recovery and updates" begin
    for n in (2,3,4), lifting in (:powers,:bounded_observations)
        net=ivr_compiler_case(conductors=n,segments=2)
        source=net["voltage_source"]["source"]["bus"]
        net["bus"][source]=Dict{String,Any}(net["bus"][source])
        net["bus"][source]["v_max"]=fill(500.,n)
        if n==2
            net["generator"]=Dict("g"=>Dict("bus"=>"b2","terminal_map"=>["a","n"],
                "configuration"=>"SINGLE_PHASE","p_min"=>[0.],"p_max"=>[100.],
                "q_min"=>[-25.],"q_max"=>[25.],"cost"=>[0.]))
        end
        common=(;objective=:source_import,lifting,fixed_observation_elimination=true)
        a=build_opf(net,IVRNLP(;common...);optimizer=Ipopt.Optimizer)
        b=build_opf(net,IVRNLP(;common...,fixed_bound_elimination=true);optimizer=Ipopt.Optimizer)
        report=b.numerical_diagnostics[:fixed_bound_report]
        @test !isempty(report)
        @test num_variables(a.model)==num_variables(b.model)
        @test num_constraints(a.model;count_variable_in_set_constraints=true)-num_constraints(b.model;count_variable_in_set_constraints=true)==length(report)
        ca=D.catalog(a);cb=D.catalog(b)
        @test cb.complete_declared_bound_coverage && cb.complete_emitted_coverage
        @test ca.expected_channel_count==cb.expected_channel_count
        @test any(q->q.form==:certified_fixed && isempty(q.constraints),cb.matched)
        ra=solve_ivr_nlp_opf(a;solver_options=STRICT);rb=solve_ivr_nlp_opf(b;solver_options=STRICT)
        @test ra.solve.optimal && rb.solve.optimal
        @test ra.objective≈rb.objective atol=1e-5 rtol=1e-7
        @test physical_residuals(net,rb).passed
        for (build,result) in ((a,rb),(b,ra))
            point=ACPoint(voltage=result.voltage_candidate,currents=result.current_candidate)
            @test ivr_nlp_point_report(build,point).passed
        end
        # Exactly recoverable physical tables keep the same keys and values.
        ea=result_dict(a,ra);eb=result_dict(b,rb)
        function compare(x,y)
            if x isa AbstractDict
                @test Set(keys(x))==Set(keys(y))
                for k in keys(x);compare(x[k],y[k]);end
            elseif x isa Real
                @test isequal(x,y) || isapprox(x,y;atol=1e-4,rtol=1e-5)
            else
                @test isequal(x,y)
            end
        end
        for table in F._RESULT_TABLES;compare(ea[table],eb[table]);end
        io=IOBuffer();write_result(eb,io);seekstart(io);@test isequal(read_result(io),eb)
        id=first(keys(b.load_constraints));load=b.network["load"][id]
        up=Dict(id=>(p=.99 .* load["p_nom"],q=.99 .* load["q_nom"]))
        update_ivr_loads!(a,up);update_ivr_loads!(b,up)
        if n==2
            for build in (a,b);update_ivr_generators!(build,Dict("g"=>(p_max=[90.],)));end
        end
        ra=solve_ivr_nlp_opf(a;solver_options=STRICT);rb=solve_ivr_nlp_opf(b;solver_options=STRICT)
        @test ra.solve.optimal && rb.solve.optimal
        @test ra.objective≈rb.objective atol=1e-5 rtol=1e-7
        @test physical_residuals(b.network,rb).passed
        @test D.catalog(b).complete_declared_bound_coverage
        deps=first(values(b.model.ext[:ivr_fixed_bound_certificates])).proof.dependencies
        v=first(keys(deps));old=fix_value(v);fix(v,old+0.01;force=true)
        @test_throws ArgumentError solve_ivr_nlp_opf(b;solver_options=STRICT)
        @test_throws ArgumentError update_ivr_loads!(b,up)
        @test_throws ArgumentError D.catalog(b)
        @test_throws ArgumentError update_ivr_generators!(b,Dict())
        @test_throws ArgumentError ivr_nlp_point_report(b,ACPoint(voltage=rb.voltage_candidate,currents=rb.current_candidate))
        fix(v,old;force=true)
        @test D.catalog(b).complete_declared_bound_coverage
    end
end
end
