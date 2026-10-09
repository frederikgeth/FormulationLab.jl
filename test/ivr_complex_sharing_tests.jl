module IVRComplexSharingTests
using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/benchmark_ivr_affine_sharing.jl")
const A=IVRAffineSharingStudy
const F=FormulationLab

function graph(expressions,model)
    policy=model.ext[:ivr_lifting]=F._ivrn_lifting_policy(IVRNLPOptions(
        lifting=:bounded_observations,observation_support_threshold=0,
        observation_sharing=:complex_proportional))
    lifted=[F._ivrn_bound_observation(model,Dict(k=>1.0+0im),expressions)
            for k in eachindex(expressions)]
    policy,lifted
end

@testset "Complex affine sharing certificates and graph recovery" begin
    model=Model();@variable(model,x[1:4],start=.25)
    u=3+x[1]+2x[2]+im*(-4+x[3]-2x[4])
    originals=[u,u,-u,2u,-.5u,im*u,(1+im)*u,(.5-2im)*u,
               conj(u),u+eps(3.),u+eps(1.)*x[1],2u+1]
    policy,lifted=graph(originals,model)
    @test length(policy.records)==5
    @test policy.shared_count[]==7==length(policy.sharing_report)
    @test any(!isreal(r.factor) for r in policy.sharing_report)
    @test all(isfinite(r.factor) && !iszero(r.factor) for r in policy.sharing_report)
    for step in 1:5
        values=Dict(v=>sin(step*k) for (k,v) in enumerate(x))
        for r in policy.records
            value=JuMP.value(v->values[v],r.expression)
            values[r.real]=real(value);values[r.imag]=imag(value)
        end
        for (a,b) in zip(originals,lifted)
            @test JuMP.value(v->values[v],a)≈JuMP.value(v->values[v],b) atol=1e-13
        end
        @test isempty(primal_feasibility_report(model,values;atol=1e-12))
        for r in policy.records,coordinate in (r.real,r.imag)
            bad=copy(values);bad[coordinate]+=.25
            @test !isempty(primal_feasibility_report(model,bad;atol=1e-12))
        end
    end
    before=(length(policy.records),policy.shared_count[])
    F._ivrn_bound_observation(model,Dict(6=>1.0+0im),originals)
    @test before==(length(policy.records),policy.shared_count[])
    # Diagnostic factors must remain serializable; canonical physical exports
    # are checked separately below and contain the original physical variables.
    @test !isempty(JSON3.write(policy.sharing_report))

    signature(z)=F._ivrn_observation_signature(z,:complex_proportional)
    @test signature(u).key==signature(im*u).key
    @test signature(x[1]+im*x[2]).key==signature(-x[2]+im*x[1]).key
    @test signature(u).key!=signature(conj(u)).key
    @test signature(u).key!=signature(im*u+1).key
    @test signature(u).key!=signature(im*u+eps(2.)*x[4]).key
    @test signature(x[1]+im*x[2]).key!=signature(x[3]+im*x[4]).key
    @test signature(0u)===nothing
    @test signature(u).key==signature(3+2x[2]+x[1]+im*(-4-2x[4]+x[3])).key
    # Existing real-only policy must continue to refuse a rotation.
    @test F._ivrn_observation_signature(u,:proportional).key!=
          F._ivrn_observation_signature(im*u,:proportional).key

    factor=F._ivrn_observation_factor
    @test factor(1.0+im,1.0-im)==im
    @test factor(5.0im,1.0+2im)==2+im
    @test factor(complex(1e308,1e308),complex(1e308,1e308))==1+0im
    for (a,b) in ((1.0+0im,3.0+0im),(1.0+0im,3.0+im),
                  (complex(1e308,0.),complex(1e-308,0.)),
                  (complex(1e-308,0.),complex(1e308,0.)),
                  (0.0+0im,1.0+im),(1.0+im,0.0+0im),(complex(NaN,0.),1.0+im))
        @test factor(a,b)===nothing
    end
    # Multiple representatives retain rows whose ratios are nonrepresentable.
    m=Model();@variable(m,y[1:2],start=0.)
    v=1+y[1]+im*y[2]
    p,z=graph([3v,v,2im*v,6im*v],m)
    @test length(p.records)==2 && p.shared_count[]==2
    @test [r.factor for r in p.sharing_report]==[2im,2im]
end

@testset "Complex sharing retains distinct voltage, current and power limits" begin
    model=Model();@variable(model,x[1:4],start=0.)
    v=x[1]+im*x[2];i=x[3]+im*x[4]
    policy,z=graph([v,im*v,i,(1+im)*i],model)
    @test length(policy.records)==2 && policy.shared_count[]==2
    # Each original rating remains a separate constraint after sharing.
    bounds=[@constraint(model,real(z[1])^2+imag(z[1])^2<=9.),
            @constraint(model,real(z[2])^2+imag(z[2])^2<=4.),
            @constraint(model,real(z[3])^2+imag(z[3])^2<=16.),
            @constraint(model,real(z[4])^2+imag(z[4])^2<=8.)]
    originals=[v,im*v,i,(1+im)*i]
    powers=[F._ivrn_bound_power(model,Dict(a=>1.0+0im),Dict(b=>1.0+0im),originals)
            for (a,b) in ((1,3),(2,4))]
    @test count(r->r.kind==:power,policy.records)==2
    for raw in ([2.5,0.,0.,0.],[0.,0.,2.5,0.],[1.,.5,.25,-.75])
        values=Dict(x[k]=>raw[k] for k in eachindex(x))
        for r in policy.records
            value=JuMP.value(v->values[v],r.expression)
            values[r.real]=real(value);values[r.imag]=imag(value)
        end
        violations=primal_feasibility_report(model,values;atol=1e-12)
        expected=raw[1]==2.5 ? [bounds[2]] : raw[3]==2.5 ? [bounds[4]] : []
        @test Set(keys(violations))==Set(expected)
        eval(expr)=JuMP.value(v->values[v],expr)
        @test eval(powers[1])≈eval(v)*conj(eval(i))
        @test eval(powers[2])≈(1+im)*eval(powers[1]) # alpha * conj(beta)
    end
end

@testset "Complex sharing power objectives, common starts and SI recovery" begin
    for conductors in (2,3,4),workload in (:quadratic_cost,:exchange_tracking)
        net=A.H.case(;conductors,segments=4,charged=true,alternate=true)
        original=JSON3.write(net)
        prior=A.profiles(net,workload;exchange_target_W=1000.)
        control=only(p for p in prior if p.name=="observations_proportional")
        opts=IVRNLPOptions(;(k=>(k==:observation_sharing ? :complex_proportional :
             deepcopy(getfield(control.options,k))) for k in fieldnames(IVRNLPOptions))...)
        candidate=(;name="observations_complex_proportional",options=opts,
                   solver_options=control.solver_options,
                   factors=merge(control.factors,(;observation_sharing=:complex_proportional)))
        @test all(JSON3.write(getfield(opts,k))==JSON3.write(getfield(control.options,k))
                  for k in fieldnames(IVRNLPOptions) if k!=:observation_sharing)
        full=build_opf(net,IVRNLP(;objective=:power,power_terms=opts.power_terms))
        start=A.E.S.U.G.H.S.L.start_point(net)
        reference,anchor=A.P.trial(net,control,full,nothing;initial_point=start)
        row,point=A.P.trial(net,candidate,full,anchor;initial_point=start)
        @test reference["accepted"] && row["accepted"]
        @test row["objective"]≈reference["objective"] atol=1e-6 rtol=1e-8
        @test JSON3.write(net)==original
        b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
        @test ivr_nlp_point_report(b,anchor).passed
        @test ivr_nlp_point_report(full,point).passed
        for (variable,value) in ivr_nlp_point_report(b,start).variable_values
            set_start_value(variable,value)
        end
        result=solve_ivr_nlp_opf(b;solver_options=A.P.STRICT)
        @test result.solve.optimal && physical_residuals(net,result).passed
        out=result_dict(b,result);io=IOBuffer();write_result(out,io);seekstart(io)
        @test isequal(read_result(io),out)
        @test Set(keys(result.powers))==Set(keys(b.powers))
        @test out["_formulationlab"]["units"]=="SI"
    end
end

include("../examples/tutorial_exact_ivr.jl")
@testset "Physical complex admittance supplies a nonreal sharing opportunity" begin
    for reactive in (-500.,500.)
        net=ExactIVRTutorial.two_wire_case()
        load=net["load"]["house"]
        load["model"]="constant_impedance";load["v_nom"]=[230.]
        load["p_nom"]=[1000.];load["q_nom"]=[reactive]
        terms=[IVRPowerTerm(channels=[(:load,"house",1)],linear=.2),
               IVRPowerTerm(channels=[(:load,"house",1)],quantity=:q,quadratic=1e-4)]
        common=(;objective=:power,power_terms=terms,objective_scale=1.,s_base=1e4,
                 lifting=:bounded_observations,observation_support_threshold=0,
                 linear_elimination=:impedance_loads)
        realbuild=build_opf(net,IVRNLP(;common...,observation_sharing=:proportional))
        b=build_opf(net,IVRNLP(;common...,observation_sharing=:complex_proportional);optimizer=Ipopt.Optimizer)
        report=b.numerical_diagnostics[:observation_sharing_report]
        @test any(!isreal(r.factor) for r in report)
        @test num_variables(b.model)<num_variables(realbuild.model)
        full=build_opf(net,IVRNLP(;objective=:power,power_terms=terms,objective_scale=1.);optimizer=Ipopt.Optimizer)
        reference=solve_ivr_nlp_opf(full;solver_options=A.P.STRICT)
        @test reference.solve.optimal && physical_residuals(net,reference).passed
        point=ACPoint(voltage=reference.voltage_candidate,currents=reference.current_candidate)
        encoded=ivr_nlp_point_report(b,point)
        @test encoded.passed && length(encoded.variable_values)==num_variables(b.model)
        for (variable,value) in encoded.variable_values;set_start_value(variable,value);end
        result=solve_ivr_nlp_opf(b;solver_options=A.P.STRICT)
        @test result.solve.optimal && physical_residuals(net,result).passed
        @test ivr_nlp_point_report(full,ACPoint(voltage=result.voltage_candidate,
                                             currents=result.current_candidate)).passed
        @test result.objective≈reference.objective atol=1e-6 rtol=1e-8
        @test result.powers[(:load,"house")]≈reference.powers[(:load,"house")] atol=1e-5
        out=result_dict(b,result);io=IOBuffer();write_result(out,io);seekstart(io)
        @test isequal(read_result(io),out)
        # A violated original voltage bound must survive a shared voltage/current
        # representative, including a lower bound when the representative and
        # original observation have different magnitudes.
        for field in ("vpn_min","vpn_max")
            bad=deepcopy(net)
            u=abs(point.voltage[("demand","a")]-point.voltage[("demand","n")])
            bad["bus"]["demand"][field]=[field=="vpn_min" ? 1.1u : .9u]
            @test !physical_residuals(bad,point).passed
            @test !ivr_nlp_point_report(build_opf(bad,IVRNLP(;common...,
                    observation_sharing=:complex_proportional)),point).passed
        end
    end
end
end
