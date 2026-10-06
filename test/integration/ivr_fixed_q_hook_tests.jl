using Test,JuMP,Ipopt
import BMOPFTools
include("../ivr_nwinding_limit_fixtures.jl")
include("ivr_fixed_q_hook.jl")
@testset "Exact fixed-Q diagnostic intervention" begin
    for sb in (1e3,1e5)
        net=_nwinding_connection_case()
        net["generator"]["g2"]["q_min"]=[7.]
        net["generator"]["g2"]["q_max"]=[7.]
        net["generator"]["g3"]["q_min"]=[-2.]
        net["generator"]["g3"]["q_max"]=[3.]
        original=deepcopy(net)
        ctx=BMOPFTools.build_opf_model(net;optimizer=Ipopt.Optimizer,per_unit=true,s_base=sb)
        key(f,id)=BMOPFTools.OpfModelKey(:constraint,f,(id,1))
        before=Dict(id=>JuMP.constraint_object(BMOPFTools.opf_object(ctx,key(:generator_q_lower,id))) for id in ("g1","g2"))
        ranged=[BMOPFTools.opf_object(ctx,key(f,"g3")) for f in (:generator_q_lower,:generator_q_upper)]
        n=JuMP.num_constraints(ctx.model;count_variable_in_set_constraints=false)
        @test _fixed_q_equalities!(ctx)==2
        @test JuMP.num_constraints(ctx.model;count_variable_in_set_constraints=false)==n-2
        @test _fixed_q_equalities!(ctx)==0 # idempotent, does not collapse intervals
        for id in ("g1","g2")
            c=JuMP.constraint_object(BMOPFTools.opf_object(ctx,key(:diagnostic_generator_q_fixed,id)))
            @test c.set isa JuMP.MOI.EqualTo
            @test c.set.value==before[id].set.lower
            @test JuMP.isequal_canonical(c.func,before[id].func)
            @test !haskey(ctx.objects,key(:generator_q_lower,id))
            @test !haskey(ctx.objects,key(:generator_q_upper,id))
        end
        @test all(c->JuMP.is_valid(ctx.model,c),ranged)
        @test all(!(c isa JuMP.ConstraintRef) || JuMP.is_valid(ctx.model,c) for c in values(ctx.objects))
        @test net==original
    end
end
