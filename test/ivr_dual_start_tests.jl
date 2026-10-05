using Test, FormulationLab, JuMP, Ipopt, JSON3
isdefined(@__MODULE__,:IVRReuseStudy) || include("../examples/benchmark_ivr_reuse.jl")
@testset "Reconstructed dual correspondence and changed-box resets" begin
    R=IVRReuseStudy;D=R.IVRDualStarts
    net=R.P.ivr_compiler_case(conductors=2,segments=2)
    net["generator"]=Dict("der"=>Dict("bus"=>"b2","terminal_map"=>["a","n"],
        "configuration"=>"SINGLE_PHASE","p_min"=>[0.],"p_max"=>[600.],
        "q_min"=>[0.],"q_max"=>[0.],"s_max"=>[1000.],"i_max"=>[200.,200.],"cost"=>[.2]))
    build()=build_opf(net,IVRNLP(objective=:cost);optimizer=Ipopt.Optimizer)
    b=build();settings=merge(R.SETTINGS,R.DUAL_CONTROLS,(obj_scaling_factor=1000.,))
    @test_throws ArgumentError D.capture(b)
    result=solve_ivr_nlp_opf(b;solver_options=settings)
    @test result.solve.optimal && physical_residuals(net,result).passed
    cache=D.capture(b);vars=all_variables(b.model);primal=value.(vars)
    @test length(cache.data)==num_constraints(b.model;count_variable_in_set_constraints=true)
    @test all(x->isfinite(x.value),values(cache.data))
    @test_throws ArgumentError D.apply!(build(),cache)
    update_ivr_loads!(b,Dict("d1"=>(p=[900.],q=[225.])))
    a=D.apply!(b,cache)
    @test a.matches_policy && a.carried==length(cache.data) && a.reset_bounds==0
    @test a.source_sha256==cache.sha256
    @test all(dual_start_value(c)==d.value for (c,d) in cache.data)
    pg=only(b.generator_variables["der"].p)
    for c in (LowerBoundRef(pg),UpperBoundRef(pg))
        cache.data[c]=merge(cache.data[c],(value=9.,))
    end
    update_ivr_generators!(b,Dict("der"=>(p_max=[0.],)))
    a=D.apply!(b,cache)
    @test a.changed_boxes==[name(pg)] && a.reset_bounds==2 && a.added==a.removed==0
    @test dual_start_value(LowerBoundRef(pg))==dual_start_value(UpperBoundRef(pg))==0.
    R.set_starts!(vars,primal)
    result=solve_ivr_nlp_opf(b;solver_options=merge(settings,(warm_start_init_point="yes",)))
    @test result.solve.optimal && physical_residuals(b.network,result).passed
    fixedcache=D.capture(b)
    update_ivr_generators!(b,Dict("der"=>(p_max=[600.],)))
    @test D.apply!(b,fixedcache).reset_bounds==2
    update_ivr_generators!(b,Dict("der"=>(p_min=nothing,)))
    a=D.apply!(b,fixedcache)
    @test a.reset_bounds==1 && a.removed==1
    result=solve_ivr_nlp_opf(b;solver_options=settings)
    @test result.solve.optimal
    removedcache=D.capture(b)
    update_ivr_generators!(b,Dict("der"=>(p_min=[0.],)))
    a=D.apply!(b,removedcache)
    @test a.reset_bounds==2 && a.added==1
    a=D.apply!(b,removedcache;mode=:zero)
    @test a.carried==0 && a.zeroed==length(D.rows(b.model))
    @test all(dual_start_value(c)==0. for c in D.rows(b.model))
    # A same-ID row with changed coefficients must be refused before writes.
    c=first(b.load_constraints["d1"].p);set_normalized_coefficient(c,pg,1.)
    before=Dict(c=>dual_start_value(c) for c in D.rows(b.model))
    @test_throws ArgumentError D.apply!(b,removedcache)
    @test all(dual_start_value(c)==x for (c,x) in before)
    @test_throws ArgumentError D.apply!(b,removedcache;mode=:unknown)
    set_normalized_coefficient(c,pg,0.)
    other=first(c for (c,d) in removedcache.data if !(d.func isa VariableRef) &&
        !(c in removedcache.rhs) && d.set isa JuMP.MOI.EqualTo && d.func isa AffExpr)
    oldrhs=normalized_rhs(other);set_normalized_rhs(other,oldrhs+1.)
    @test_throws ArgumentError D.apply!(b,removedcache)
    set_normalized_rhs(other,oldrhs)
    fixedvar=first(v for v in vars if is_fixed(v));oldfixed=fix_value(fixedvar)
    fix(fixedvar,oldfixed+.1;force=true)
    @test_throws ArgumentError D.apply!(b,removedcache)
    fix(fixedvar,oldfixed;force=true)
    extra=@constraint(b.model,pg<=10.)
    @test_throws ArgumentError D.apply!(b,removedcache)
    delete(b.model,extra)
    added=@variable(b.model)
    @test_throws ArgumentError D.apply!(b,removedcache)
    delete(b.model,added)
    oldobjective=objective_function(b.model)
    set_objective_function(b.model,oldobjective+vars[end])
    @test_throws ArgumentError D.apply!(b,removedcache)
    set_objective_function(b.model,oldobjective)
    @test D.apply!(b,removedcache).matches_policy

end

@testset "Controlled dual workflow admission and effective settings" begin
    R=IVRReuseStudy
    net=R.P.ivr_compiler_case(conductors=2,segments=2)
    schedule=[(label="base",loads=Dict{String,Any}(),generators=Dict{String,Any}()),
        (label="repeat",loads=Dict{String,Any}(),generators=Dict{String,Any}()),
        (label="lower",loads=Dict(id=>(p=.9d["p_nom"],q=.9d["q_nom"]) for (id,d) in net["load"]),generators=Dict{String,Any}())]
    candidates=R.dual_workflows(profiles=R.P.profiles()[[1]])
    mktempdir() do dir
        file=joinpath(dir,"dual.json")
        r=R.benchmark(net,schedule,file;candidates,repetitions=6)
        @test r["ranking"]["objective_comparable"] && length(r["ranking"]["eligible"])==3
        @test all(count(o->o[k]==w.name,r["orders"])==2 for w in candidates for k in 1:3)
        for p in r["profiles"],t in p["trials"]
            @test t["accepted"]
            for (k,s) in enumerate(t["scenarios"])
                active=k>1 && p["start"]!=:previous_primal
                @test s["effective_solver_options"]["warm_start_init_point"]==(active ? "yes" : "no")
                @test s["effective_solver_options"]["fixed_variable_treatment"]=="make_parameter"
                if active
                    @test s["dual_start"].matches_policy && s["dual_start"].source_sha256==t["scenarios"][k-1]["dual_solution_sha256"]
                    @test s["dual_start"].reset_bounds==0
                else
                    @test s["dual_start"]===nothing
                end
            end
        end
        @test_throws ArgumentError R.benchmark(net,schedule,file;candidates=[merge(candidates[2],(reuse=false,))])
        saved=JSON3.read(read(file,String))
        @test saved.dual_helper_sha256==R.IVRDualStarts.SOURCE_SHA
    end
end
