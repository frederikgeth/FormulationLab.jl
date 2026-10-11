module IVRVoltageEqualityTests
using Test,FormulationLab,JuMP,Ipopt,JSON3
include("../examples/benchmark_ivr_joint_boundaries.jl")
const J=IVRJointBoundaryStudy
const F=FormulationLab
# mumps_pivtol=1e-3 avoids platform-dependent pivot retries that ended these
# strict solves at ALMOST_LOCALLY_SOLVED on x86-64 Linux (see ivr_findings.md).
const PIVOT=(mumps_pivtol=1e-3,)

@testset "Exact coincident voltage-row selection" begin
    for family in ("v","vpn","vpp","vpos"),lifting in (:off,:bounded_observations),
        treatment in (:coincident,:interval,:near,:zero,:fixed_source,:upper_only)
        n=family=="vpos" ? 1 : 3
        lo=treatment==:zero ? 0. : 1.
        hi=treatment==:interval ? 1.1 : treatment==:near ? nextfloat(lo) : lo
        bus=Dict{String,Any}("terminal_names"=>["a","b","c","n"],family*"_max"=>fill(hi,n))
        treatment==:upper_only || (bus[family*"_min"]=fill(lo,n))
        net=Dict("bus"=>Dict("b"=>bus));original=deepcopy(net)
        function stamp(policy)
            model=Model();@variable(model,vr[1:3],start=0.);@variable(model,vi[1:3],start=0.);z=vr+im*vi
            model.ext[:ivr_lifting]=F._ivrn_lifting_policy(IVRNLPOptions(;lifting))
            tr=(b,ts)->[t=="n" ? Dict{Int,ComplexF64}() : Dict(findfirst(==(t),["a","b","c"])=>1.0+0im) for t in ts]
            e=(;vb=1.,terminal_rows=tr,neutral_map=Dict("b"=>"n"),
                fixed_source_coordinates=treatment==:fixed_source ? Dict(k=>cis(-2pi*(k-1)/3) for k in 1:3) : Dict{Int,ComplexF64}())
            report=F._ivrn_bus_limits!(model,net,e,z;coincident=policy)
            (;model,report)
        end
        control=stamp(:separate);candidate=stamp(:equality)
        merged=treatment==:coincident ? n : 0
        @test count(x->x.action==:equality,candidate.report)==merged
        @test count(x->x.action==:fixed_source_pair_retained,candidate.report)==(treatment==:fixed_source ? n : 0)
        @test num_constraints(control.model;count_variable_in_set_constraints=false)-num_constraints(candidate.model;count_variable_in_set_constraints=false)==merged
        @test isempty(control.report)
        @test all(x.limit_V==1. && x.lower==family*"_min" && x.upper==family*"_max" for x in candidate.report)
        @test net==original
    end
end

@testset "Fixed voltage magnitude preserves dispatch and physical bounds" begin
    for n in (2,3),direction in (-1,1),sb in (1e3,1e5)
        net,m=J.scenario(;conductors=n,direction,treatment=:loose_current)
        family=n==2 ? "vpn" : "vpp";channels=n==2 ? 1 : 3
        net["bus"]["b1"][family*"_min"]=fill(m.nominal_voltage_V,channels)
        net["bus"]["b1"][family*"_max"]=fill(m.nominal_voltage_V,channels)
        original=deepcopy(net);profiles=J.profiles(net,m);anchor=nothing;objective=nothing
        full=build_opf(net,IVRNLP(objective=:power,power_terms=first(profiles).options.power_terms))
        for policy in (:equality,:separate),p in profiles
            opts=IVRNLPOptions(;(k=>(k==:coincident_voltage_bounds ? policy : k==:s_base ? sb : deepcopy(getfield(p.options,k))) for k in fieldnames(IVRNLPOptions))...)
            b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
            start=ivr_nlp_point_report(b,J.L.M.E.S.U.G.H.S.L.start_point(net))
            for (v,x) in start.variable_values;set_start_value(v,x);end
            r=solve_ivr_nlp_opf(b;solver_options=merge(J.L.P.STRICT,p.solver_options,PIVOT))
            @test r.solve.optimal && physical_residuals(net,r).passed
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(full,point).passed && ivr_nlp_point_report(b,point).passed
            if anchor===nothing;anchor=point;objective=r.objective;end
            @test ivr_nlp_point_report(b,anchor).passed
            # Exact feasible-set correspondence does not ensure identical
            # solver termination accuracy. The optional measurement runner
            # retains control objective discrepancies under the same threshold.
            if policy==:equality
                @test isapprox(r.objective,objective;atol=1e-5,rtol=1e-8)
            end
            @test all(abs(x.slack_V)<1e-5 for x in J.voltage_activity(net,point,m).records)
            @test count(x->x.action==:equality,b.numerical_diagnostics[:coincident_voltage_bound_report])==(policy==:equality ? channels : 0)
            d=result_dict(b,r)
            @test d["_formulationlab"]["coincident_voltage_bounds"]==string(policy)
            io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
            # Both sides remain meaningful: shifting the fixed magnitude either
            # way excludes this point, without changing any other physical field.
            for factor in (.999,1.001)
                shifted=deepcopy(net)
                for suffix in ("min","max");shifted["bus"]["b1"][family*"_"*suffix].*=factor;end
                @test !physical_residuals(shifted,r).passed
                @test !ivr_nlp_point_report(build_opf(shifted,IVRNLP(opts)),point).passed
            end
            @test net==original
        end
    end
    net,_=J.scenario()
    @test_throws ArgumentError build_opf(net,IVRNLP(coincident_voltage_bounds=:approximate))
    a=build_opf(net,IVRNLP());b=build_opf(net,IVRNLP(coincident_voltage_bounds=:separate))
    @test sprint(show,a.model)==sprint(show,b.model)
end
end
