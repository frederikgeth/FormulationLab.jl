using Test,FormulationLab,JuMP,Ipopt
isdefined(@__MODULE__,:IVRLiftingBlockStudy) || include("../examples/benchmark_ivr_lifting_blocks.jl")
isdefined(@__MODULE__,:IVRConstraintInventory) || include("../examples/ivr_constraint_inventory.jl")
@testset "Fixed-input observation inlining" begin
    F=FormulationLab
    for sharing in (:off,:exact,:signed,:proportional,:complex_proportional)
        m=Model();@variable(m,x[1:4]);fix.(x,[1.,2.,3.,4.])
        m.ext[:ivr_lifting]=F._ivrn_lifting_policy(IVRNLPOptions(
            lifting=:bounded_observations,observation_sharing=sharing,fixed_observation_elimination=true))
        u=x[1]+x[2]+im*(x[3]-x[4]);row=Dict(1=>1.0+0im)
        v=F._ivrn_bound_observation(m,row,[u])
        @test F._ivrn_affine_key(v)==F._ivrn_affine_key(u)
        @test num_variables(m)==4
        @test isempty(m.ext[:ivr_lifting].records)
        @test length(m.ext[:ivr_lifting].fixed_records)==1
        @test F._ivrn_affine_key(F._ivrn_bound_observation(m,row,[u]))==F._ivrn_affine_key(u)
        @test length(m.ext[:ivr_lifting].fixed_records)==1
        c=@constraint(m,real(v)^2+imag(v)^2<=9.)
        vals=Dict(a=>fix_value(a) for a in x)
        @test JuMP.primal_feasibility_report(m,vals;atol=0.)[c]≈1.
        fix(x[1],0.;force=true);vals[x[1]]=0.
        @test isempty(JuMP.primal_feasibility_report(m,vals;atol=0.))
        @test JuMP.value(fix_value,v)==2-im # dependency remains live
        lower=@constraint(m,real(v)^2+imag(v)^2>=8.)
        @test JuMP.primal_feasibility_report(m,vals;atol=0.)[lower]≈3.
        zero=F._ivrn_upper!(m,v,0.)
        @test length(zero)==2
        @test all(c->haskey(JuMP.primal_feasibility_report(m,vals;atol=0.),c),zero)
        unfix(x[1]);@test F._ivrn_affine_key(v)==F._ivrn_affine_key(u) # exact even after eligibility changes
    end
    for mode in (:off,:powers,:bounded_observations),fixed in (false,true),threshold in (0,10)
        m=Model();@variable(m,x[1:4],start=1.)
        fixed && fix.(x,1.)
        m.ext[:ivr_lifting]=F._ivrn_lifting_policy(IVRNLPOptions(lifting=mode,
            fixed_observation_elimination=true,observation_support_threshold=threshold))
        u=x[1]+x[2]+im*(x[3]+x[4])
        F._ivrn_bound_observation(m,Dict(1=>1.0+0im),[u])
        @test length(m.ext[:ivr_lifting].fixed_records)==(mode==:bounded_observations && fixed && threshold==0)
        @test length(m.ext[:ivr_lifting].records)==(mode==:bounded_observations && !fixed && threshold==0)
    end
end
@testset "Fixed observation physical equivalence and updates" begin
    L=IVRLiftingBlockStudy
    for n in (2,3,4)
        net=L.C.P.ivr_compiler_case(conductors=n,segments=3)
        if n==2
            net["generator"]=Dict("g"=>Dict("bus"=>"b3","terminal_map"=>["a","n"],
                "configuration"=>"SINGLE_PHASE","p_min"=>[0.],"p_max"=>[100.],
                "q_min"=>[-25.],"q_max"=>[25.],"cost"=>[0.]))
        end
        source=first(values(net["voltage_source"]))["bus"]
        net["bus"][source]=Dict{String,Any}(net["bus"][source])
        net["bus"][source]["v_max"]=fill(260.,n)
        # Source phase-pair observations involve four fixed real coordinates.
        net["bus"][source]["vpp_min"]=fill(0.,n==2 ? 0 : 3)
        net["bus"][source]["vpp_max"]=fill(1000.,n==2 ? 0 : 3)
        common=(;objective=:source_import,lifting=:bounded_observations,observation_sharing=:signed,observation_support_threshold=0)
        a=build_opf(net,IVRNLP(;common...);optimizer=Ipopt.Optimizer)
        b=build_opf(net,IVRNLP(;common...,fixed_observation_elimination=true);optimizer=Ipopt.Optimizer)
        count=b.numerical_diagnostics[:fixed_observation_count]
        @test count>0
        @test num_variables(a.model)-num_variables(b.model)==2count
        @test num_constraints(a.model;count_variable_in_set_constraints=false)-num_constraints(b.model;count_variable_in_set_constraints=false)==2count
        @test IVRConstraintInventory.report(b).complete_emitted_coverage
        @test length(a.model.ext[:ivr_bus_limit_rows])==length(b.model.ext[:ivr_bus_limit_rows])
        for (aa,bb) in zip(a.model.ext[:ivr_bus_limit_rows],b.model.ext[:ivr_bus_limit_rows])
            @test (aa.b,aa.key,aa.channel,aa.form)==(bb.b,bb.key,bb.channel,bb.form)
            @test length(aa.constraints)==length(bb.constraints)
        end
        ra=solve_ivr_nlp_opf(a;solver_options=L.P.STRICT)
        rb=solve_ivr_nlp_opf(b;solver_options=L.P.STRICT)
        @test ra.solve.optimal && rb.solve.optimal
        @test ra.objective≈rb.objective atol=1e-5 rtol=1e-7
        @test physical_residuals(net,rb).passed
        for (build,result) in ((a,rb),(b,ra))
            point=ACPoint(voltage=result.voltage_candidate,currents=result.current_candidate)
            @test ivr_nlp_point_report(build,point).passed
        end
        id=first(keys(b.load_constraints));load=b.network["load"][id]
        update=(;p=0.99 .* load["p_nom"],q=0.99 .* load["q_nom"])
        update_ivr_loads!(a,Dict(id=>update));update_ivr_loads!(b,Dict(id=>update))
        if n==2
            update_ivr_generators!(a,Dict("g"=>(p_max=[90.],)))
            update_ivr_generators!(b,Dict("g"=>(p_max=[90.],)))
        end
        ra=solve_ivr_nlp_opf(a;solver_options=L.P.STRICT);rb=solve_ivr_nlp_opf(b;solver_options=L.P.STRICT)
        @test ra.solve.optimal && rb.solve.optimal
        @test ra.objective≈rb.objective atol=1e-5 rtol=1e-7
        @test physical_residuals(b.network,rb).passed
        @test IVRConstraintInventory.report(b).complete_emitted_coverage
        d=result_dict(b,rb);io=IOBuffer();write_result(d,io);seekstart(io)
        @test isequal(read_result(io),d)
    end
end
