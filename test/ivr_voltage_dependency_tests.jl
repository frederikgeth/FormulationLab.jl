module IVRVoltageDependencyTests
using Test,FormulationLab,JuMP,Ipopt
include("../examples/benchmark_ivr_voltage_dependencies.jl")
const D=IVRVoltageDependencyStudy
const F=FormulationLab

@testset "Structural fixedness and exact normalized voltage identity" begin
    equations=[Dict(1=>2.0+0im,2=>-1.0+0im),Dict(2=>1.0+0im,3=>3im),
        Dict(3=>1.0+0im,4=>1.0+0im,5=>1e-300+0im),Dict(4=>1.0+0im,5=>1.0+0im)]
    e=(;equations,fixed_source_coordinates=Dict(1=>1.0+0im))
    certificate=F._ivrn_circuit_fixed_coordinates(e)
    @test certificate.fixed==Set([1,2,3]) # no threshold erases the tiny term
    known=Set(keys(e.fixed_source_coordinates))
    for d in certificate.derivations
        support=Set(k for (k,a) in equations[d.equation] if !iszero(a))
        @test setdiff(support,known)==Set([d.coordinate])
        push!(known,d.coordinate)
    end
    @test known==certificate.fixed
    no_source=F._ivrn_circuit_fixed_coordinates((;equations,fixed_source_coordinates=Dict{Int,ComplexF64}()))
    @test isempty(no_source.fixed) && isempty(no_source.derivations)
    # An exact zero coefficient creates a provable chain; no operating values
    # or nominal magnitudes enter this fixedness certificate.
    eqzero=deepcopy(equations);eqzero[3][5]=0im
    @test F._ivrn_circuit_fixed_coordinates((;equations=eqzero,e.fixed_source_coordinates)).fixed==Set(1:5)
    model=Model();@variable(model,x[1:2]);u=(x[1]+3)+im*(2x[2]-4)
    key=F._ivrn_voltage_equality_key
    @test key(u,230.)==key(2u,460.)
    @test key(u,230.)!=key(2u,nextfloat(460.))
    @test key(u,230.)!=key(u+eps(3.),230.)
    @test key(u,230.)!=key(-u,230.) # phase/sign equivalences are outside scope
end

@testset "Guarded voltage declarations under power costs" begin
    for n in (2,4),treatment in (:single,:duplicate,:implied),objective in (:linear_cost,:quadratic_cost),sb in (1e3,1e5)
        net=D.scenario(;conductors=n,treatment);original=deepcopy(net);channels=n==2 ? 1 : 3
        full=build_opf(net,IVRNLP(objective=:power,power_terms=D.terms(net,objective),objective_scale=1.))
        anchor=nothing;anchor_objective=nothing
        for p in D.profiles(net,objective)
            opts=D.options(p,:guarded_equality,sb)
            b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
            r=solve_ivr_nlp_opf(b;solver_options=merge(D.M.P.STRICT,p.solver_options))
            @test r.solve.optimal && physical_residuals(net,r).passed
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(b,point).passed && ivr_nlp_point_report(full,point).passed
            # Includes plain-equality models whose optimizer fails in the
            # measurement panel: the guarded point is still feasible there.
            @test ivr_nlp_point_report(build_opf(net,IVRNLP(D.options(p,:equality,sb))),point).passed
            if anchor===nothing;anchor=point;anchor_objective=r.objective;end
            @test ivr_nlp_point_report(b,anchor).passed
            @test isapprox(r.objective,anchor_objective;atol=1e-7,rtol=1e-6)
            actions=[x.action for x in b.numerical_diagnostics[:coincident_voltage_bound_report]]
            @test count(==(:equality),actions)==(treatment==:implied ? 0 : channels)
            @test count(==(:shared_equality),actions)==(treatment==:duplicate ? channels : 0)
            @test count(==(:circuit_fixed_pair_retained),actions)==(treatment==:implied ? channels : 0)
            @test isempty(b.numerical_diagnostics[:voltage_fixed_dependencies])==(treatment!=:implied)
            for factor in (.999,1.001)
                shifted=deepcopy(net)
                for key in ("v_min","v_max","vpn_min","vpn_max")
                    haskey(shifted["bus"]["b1"],key) && (shifted["bus"]["b1"][key].*=factor)
                end
                @test !physical_residuals(shifted,r).passed
                @test !ivr_nlp_point_report(build_opf(shifted,IVRNLP(opts)),point).passed
            end
            exported=result_dict(b,r)["_formulationlab"]
            @test exported["coincident_voltage_bounds"]=="guarded_equality"
            @test length(exported["coincident_voltage_bound_report"])==length(actions)
            @test net==original
        end
    end
end
end
