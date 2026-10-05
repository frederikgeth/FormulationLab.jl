using Test, FormulationLab, JuMP, Ipopt
isdefined(@__MODULE__,:IVRLiftingBlockStudy) || include("../examples/benchmark_ivr_lifting_blocks.jl")

@testset "Exact composed affine observation identity" begin
    F=FormulationLab
    for sharing in (:off,:exact)
        model=Model();@variable(model,x[1:4],start=0.1)
        model.ext[:ivr_lifting]=F._ivrn_lifting_policy(IVRNLPOptions(
            lifting=:bounded_observations,observation_sharing=sharing))
        u=(x[1]+2x[2]+3)+(x[3]-2x[4]-4)*im
        # Different original rows, identical composed expression including offset.
        z=[u,u+0*x[4],-u,u+eps(3.),u+eps(3.)*x[1],conj(u)]
        row(k)=Dict(k=>1.0+0im)
        a=F._ivrn_bound_observation(model,row(1),z)
        b=F._ivrn_bound_observation(model,row(2),z)
        @test isequal(a,b)==(sharing==:exact)
        @test isequal(F._ivrn_bound_observation(model,row(2),z),b)
        for k in 3:6
            @test !isequal(F._ivrn_bound_observation(model,row(k),z),a)
        end
        @test length(model.ext[:ivr_lifting].records)==(sharing==:exact ? 5 : 6)
        @test model.ext[:ivr_lifting].shared_count[]==(sharing==:exact ? 1 : 0)
        # Canonical order, exact zero terms and signed-zero constants.
        @test F._ivrn_affine_key(u)==F._ivrn_affine_key(3+2x[2]+x[1]+im*(-4-2x[4]+x[3]))
        @test F._ivrn_affine_key(x[1]+im*x[2]+0.0)==F._ivrn_affine_key(x[1]+im*x[2]-0.0)
        # Power auxiliaries remain separate even when their observations share.
        p=F._ivrn_bound_power(model,row(1),row(1),z)
        q=F._ivrn_bound_power(model,row(2),row(2),z)
        @test !isequal(p,q)
    end
    for threshold in (0,2,4,100)
        model=Model();@variable(model,x[1:4],start=0.)
        model.ext[:ivr_lifting]=F._ivrn_lifting_policy(IVRNLPOptions(
            lifting=:bounded_observations,observation_support_threshold=threshold))
        u=x[1]+x[2]+im*(x[3]+x[4])
        F._ivrn_bound_observation(model,Dict(1=>1.0+0im),[u])
        @test length(model.ext[:ivr_lifting].records)==(threshold<4 ? 1 : 0)
    end
end

@testset "Observation policies preserve exact physical models" begin
    L=IVRLiftingBlockStudy;settings=L.P.STRICT
    for m in (2,3),charged in (false,true)
        net=L.case(;conductors=m,segments=4,charged,tight=true)
        full=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
        rf=solve_ivr_nlp_opf(full;solver_options=settings);@test rf.solve.optimal
        point=ACPoint(voltage=rf.voltage_candidate,currents=rf.current_candidate)
        common=(;objective=:source_import,specialization=:conductor_regions,
            linear_elimination=:passive_blocks,lifting=:bounded_observations)
        default=build_opf(net,IVRNLP(;common...))
        explicit=build_opf(net,IVRNLP(;common...,observation_support_threshold=2,observation_sharing=:off))
        @test sprint(show,default.model)==sprint(show,explicit.model)
        for threshold in (2,4,8),sharing in (:off,:exact)
            b=build_opf(net,IVRNLP(;common...,observation_support_threshold=threshold,observation_sharing=sharing);optimizer=Ipopt.Optimizer)
            start=ivr_nlp_point_report(b,L.start_point(net))
            @test length(start.variable_values)==num_variables(b.model)
            @test isempty(start.missing_channels)
            @test max(start.max_binding_residual_pu,start.max_reconstruction_residual_pu)<1e-10
            @test ivr_nlp_point_report(b,point).passed
            for (v,value) in start.variable_values;set_start_value(v,value);end
            r=solve_ivr_nlp_opf(b;solver_options=settings)
            @test r.solve.optimal && physical_residuals(net,r).passed
            @test ivr_nlp_point_report(full,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
            @test r.objective≈rf.objective atol=1e-5 rtol=1e-8
            d=result_dict(b,r);df=result_dict(full,rf)
            @test keys(d)==keys(df)
            for (bus,ts) in df["bus"],(t,v) in ts,field in ("vr","vi")
                @test d["bus"][bus][t][field]≈v[field] atol=1e-5
            end
            # Sequential graph encoding includes both shared observations and P/Q.
            supplied=ivr_nlp_point_report(b,point)
            for ref in b.model.ext[:ivr_lifting].records
                bad=copy(supplied.variable_values);bad[ref.real]+=.1
                @test maximum(values(primal_feasibility_report(b.model,bad;atol=0.)))>.09
            end
            # Updating CP demand and dispatch never invalidates expression identity.
            vars=all_variables(b.model);n=m==2 ? 1 : 3
            update_ivr_loads!(b,Dict("d4"=>(p=fill(500.,n),q=fill(100.,n))))
            update_ivr_generators!(b,Dict("g"=>(p_min=fill(100.,n),p_max=fill(100.,n),q_min=zeros(n),q_max=zeros(n))))
            updated=solve_ivr_nlp_opf(b;solver_options=settings)
            @test updated.solve.optimal && physical_residuals(b.network,updated).passed
            @test all_variables(b.model)==vars
            # A violated original line-current limit remains visible at every threshold.
            tight=deepcopy(net);tight["line"]["l1"]["i_max"]=fill(1e-6,m)
            bound=build_opf(tight,IVRNLP(;common...,observation_support_threshold=threshold,observation_sharing=sharing))
            @test !ivr_nlp_point_report(bound,point).passed
            @test !physical_residuals(tight,point;delta_dispatch=:coil).passed
        end
    end
    net=L.case(segments=4)
    @test_throws ArgumentError build_opf(net,IVRNLP(observation_support_threshold=-1))
    @test_throws ArgumentError build_opf(net,IVRNLP(observation_sharing=:approximate))
    for mode in (:off,:powers)
        a=build_opf(net,IVRNLP(lifting=mode))
        b=build_opf(net,IVRNLP(lifting=mode,observation_support_threshold=0,observation_sharing=:exact))
        @test sprint(show,a.model)==sprint(show,b.model)
    end
end
