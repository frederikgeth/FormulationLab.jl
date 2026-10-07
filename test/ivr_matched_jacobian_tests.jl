module IVRMatchedJacobianTests
using Test, FormulationLab, JuMP, SparseArrays, LinearAlgebra
include("../examples/ivr_matched_jacobian.jl")
include("sdp_transformer_fixtures.jl")
include("ac_validation_fixtures.jl")
const M=IVRMatchedJacobian
@testset "Matched regional-current Jacobian coordinate contract" begin
    terms=[IVRPowerTerm(channels=[(:voltage_source,"s",1)],quadratic=1e-5)]
    @test M.same_option(terms,deepcopy(terms))
    @test !M.same_option(terms,[IVRPowerTerm(channels=[(:voltage_source,"s",1)],quadratic=2e-5)])
    rows=[(1,"f","s"),(2,"f","s")];names=["x","y"]
    a=(;J=sparse([1. 2.;3. 4.]),x=[2.,3.],rows,names,values=[4.,5.],objective=8.)
    map=(;column=[.1,10.],row=Dict(rows.=>[2.,.5]))
    b=(;a...,J=spdiagm(0=>[2.,.5])*a.J*spdiagm(0=>map.column),x=a.x./map.column,values=[8.,2.5])
    @test M.compare(a,b,map).passed
    @test !M.compare(a,(;b...,x=[1.,1.]),map).passed
    @test !M.compare(a,(;b...,values=[8.,3.]),map).passed
    @test !M.compare(a,(;b...,objective=9.),map).passed
    bad=copy(b.J);bad[1,1]+=.01
    @test !M.compare(a,(;b...,J=bad),map).passed
    @test_throws ArgumentError M.compare(a,(;b...,names=reverse(names)),map)
    @test_throws ArgumentError M.compare(a,b,(;map...,column=[0.,1.]))
    @test_throws ArgumentError M.compare(a,b,(;map...,row=Dict(first(rows)=>1.)))
    for kind in ("single_phase","delta_wye"),mode in (:off,:transformer_currents),lifting in (:powers,:bounded_observations)
        net,p=_audit_transformer_state(kind;rotation=.17)
        tx=net["transformer"][kind]["tx"]
        for side in ("from","to");tx["i_max_$side"]=max.(tx["i_max_$side"],1e-6);end
        opts=(;objective=:source_import,s_base=1e5,transformer_scaling=:nominal,row_scaling=:composed,device_elimination=mode,lifting)
        aa=build_opf(net,IVRNLP(;opts...,current_power_bases=Dict("t"=>1e3)))
        bb=build_opf(net,IVRNLP(;opts...,current_power_bases=Dict("t"=>1e4)))
        mapping=M.maps(aa,bb);pa=ivr_nlp_point_report(aa,p);pb=ivr_nlp_point_report(bb,p)
        @test pa.passed && pb.passed
        @test physical_residuals(net,p;delta_dispatch=:coil).passed
        @test pa.objective≈pb.objective atol=1e-8
        av=all_variables(aa.model);bv=all_variables(bb.model)
        @test [pa.variable_values[v] for v in av]≈mapping.column.*[pb.variable_values[v] for v in bv]
        refs=Dict(M.refkey(r)=>r for r in all_constraints(bb.model;include_variable_in_set_constraints=true))
        gaps=Float64[]
        for ref in all_constraints(aa.model;include_variable_in_set_constraints=true)
            key=M.refkey(ref)
            x=value(v->pa.variable_values[v],constraint_object(ref).func)
            y=value(v->pb.variable_values[v],constraint_object(refs[key]).func)
            push!(gaps,abs(y-mapping.row[key]*x)/max(1.,abs(y),abs(mapping.row[key]*x)))
        end
        @test maximum(gaps)<1e-10
        @test "transformer" in values(mapping.groups)
        @test any(!=(1.),mapping.column)
        changed=build_opf(net,IVRNLP(;opts...,s_base=2e5))
        @test_throws ArgumentError M.maps(aa,changed)
    end
end
end
