module IVRAffineSharingTests
using Test, FormulationLab, JuMP, Ipopt, JSON3, LinearAlgebra
include("../examples/benchmark_ivr_affine_sharing.jl")
const A=IVRAffineSharingStudy
const F=FormulationLab

@testset "Certified signed and proportional affine graphs" begin
    for sharing in (:off,:exact,:signed,:proportional)
        model=Model();@variable(model,x[1:4],start=.25)
        policy=model.ext[:ivr_lifting]=F._ivrn_lifting_policy(IVRNLPOptions(
            lifting=:bounded_observations,observation_sharing=sharing))
        u=3+x[1]+2x[2]+im*(-4+x[3]-2x[4])
        originals=[u,u,-u,2u,-.5u,conj(u),u+eps(3.),u+eps(1.)*x[1],2u+1]
        lifted=[F._ivrn_bound_observation(model,Dict(k=>1.0+0im),originals) for k in eachindex(originals)]
        expected=sharing==:off ? 9 : sharing==:exact ? 8 : sharing==:signed ? 7 : 5
        @test length(policy.records)==expected
        @test policy.shared_count[]==9-expected==length(policy.sharing_report)
        for step in 1:5
            values=Dict(v=>sin(step*k) for (k,v) in enumerate(x))
            for r in policy.records
                value=JuMP.value(v->values[v],r.expression)
                values[r.real]=real(value);values[r.imag]=imag(value)
            end
            for (a,b) in zip(originals,lifted)
                @test JuMP.value(v->values[v],a)≈JuMP.value(v->values[v],b) atol=1e-14
            end
            @test isempty(primal_feasibility_report(model,values;atol=1e-12))
            for r in policy.records
                bad=copy(values);bad[r.real]+=.25
                @test !isempty(primal_feasibility_report(model,bad;atol=1e-12))
            end
        end
        # Repeat visits neither allocate nor count as new shared observations.
        before=(length(policy.records),policy.shared_count[])
        F._ivrn_bound_observation(model,Dict(3=>1.0+0im),originals)
        @test before==(length(policy.records),policy.shared_count[])
        @test all(r->isfinite(r.factor)&&!iszero(r.factor),policy.sharing_report)
    end
    # No floating normalized-key collision, rounded factor, zero, overflow or
    # underflow is accepted as an exact real proportionality certificate.
    @test F._ivrn_observation_factor(1.,3.)===nothing
    @test F._ivrn_observation_factor(2.,3.)===nothing
    @test F._ivrn_observation_factor(2.,1.)==2.
    @test F._ivrn_observation_factor(1e308,1e-308)===nothing
    @test F._ivrn_observation_factor(1e-308,1e308)===nothing
    model=Model();@variable(model,x[1:2],start=0.)
    policy=model.ext[:ivr_lifting]=F._ivrn_lifting_policy(IVRNLPOptions(
        lifting=:bounded_observations,observation_support_threshold=0,observation_sharing=:proportional))
    u=1+x[1]+im*x[2];zs=[3u,u,2u,6u,2u+eps(2.)]
    for k in eachindex(zs);F._ivrn_bound_observation(model,Dict(k=>1.0+0im),zs);end
    @test length(policy.records)==3 && policy.shared_count[]==2
    @test [r.factor for r in policy.sharing_report]==[2.,2.]
    @test F._ivrn_observation_signature(u,:proportional).key!=F._ivrn_observation_signature(2u+eps(2.),:proportional).key
    @test F._ivrn_observation_signature(u,:proportional).key!=F._ivrn_observation_signature(im*u,:proportional).key
end

@testset "Shared affine rows retain physical powers, limits and updates" begin
    for m in (2,3,4),charged in (false,true)
        net=A.H.case(conductors=m,segments=4;charged,alternate=true)
        full=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
        rf=solve_ivr_nlp_opf(full;solver_options=A.P.STRICT)
        @test rf.solve.optimal && physical_residuals(net,rf).passed
        p=ACPoint(voltage=rf.voltage_candidate,currents=rf.current_candidate)
        for sharing in (:exact,:signed,:proportional,:complex_proportional)
            opts=(;objective=:source_import,lifting=:bounded_observations,observation_sharing=sharing,
                specialization=:conductor_regions,linear_elimination=:passive_blocks,observation_support_threshold=0,
                transformer_scaling=:nominal,row_scaling=:composed,lifted_power_base=1e3,power_sharing=:generators)
            b=build_opf(net,IVRNLP(;opts...);optimizer=Ipopt.Optimizer)
            @test ivr_nlp_point_report(b,p).passed
            r=solve_ivr_nlp_opf(b;solver_options=A.P.STRICT)
            @test r.solve.optimal && physical_residuals(net,r).passed
            @test r.objective≈rf.objective atol=1e-5 rtol=1e-8
            q=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(full,q).passed
            result=result_dict(b,r);io=IOBuffer();write_result(result,io);seekstart(io);@test isequal(read_result(io),result)
            @test Set(keys(r.powers))==Set(keys(rf.powers))
            # Native complex powers preserve orientation and channel definitions.
            for (key,s) in rf.powers;@test r.powers[key]≈s atol=1e-4 rtol=1e-7;end
            for (bus,d) in net["bus"],field in ("v_min","v_max","vpn_min","vpn_max","vn_max","vpp_min","vpp_max")
                haskey(d,field) || continue
                tight=deepcopy(net)
                tight["bus"][bus][field]=fill(endswith(field,"min") ? 1e6 : 0.,length(d[field]))
                audit=physical_residuals(tight,p;delta_dispatch=:coil)
                audit.passed && continue # An identically grounded channel has no nonzero ceiling witness.
                @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(;opts...)),p).passed
            end
            for (id,d) in net["line"],field in ("i_max","s_max")
                tight=deepcopy(net);tight["line"][id][field]=fill(1e-9,field=="i_max" ? m : m==2 ? 1 : 3)
                @test !physical_residuals(tight,p;delta_dispatch=:coil).passed
                @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(;opts...)),p).passed
            end
            vars=all_variables(b.model);n=m==2 ? 1 : 3
            update_ivr_loads!(b,Dict("d4"=>(p=fill(500.,n),q=fill(100.,n))))
            update_ivr_generators!(b,Dict("der"=>(p_min=fill(100.,n),p_max=fill(100.,n),q_min=zeros(n),q_max=zeros(n))))
            changed=solve_ivr_nlp_opf(b;solver_options=A.P.STRICT)
            @test changed.solve.optimal && physical_residuals(b.network,changed).passed
            @test all_variables(b.model)==vars
        end
    end
end

@testset "Affine sharing study isolates candidate changes" begin
    net=A.H.case(conductors=3,segments=4,charged=true)
    for workload in (:quadratic_cost,:exchange_tracking),policy in ("none","gradient-based")
        ps=A.profiles(net,workload;exchange_target_W=1500.,nlp_scaling_method=policy)
        @test length(ps)==6 && allunique(p.name for p in ps)
        a=ps[3].options
        for p in ps[4:6]
            @test all(JSON3.write(getfield(a,k))==JSON3.write(getfield(p.options,k)) for k in fieldnames(IVRNLPOptions) if k!=:observation_sharing)
        end
        ref=build_opf(net,IVRNLP(objective=:power,power_terms=first(ps).options.power_terms));anchor=nothing
        for p in ps
            row,q=A.P.trial(net,p,ref,anchor;initial_point=A.E.S.U.G.H.S.L.start_point(net))
            @test row["accepted"]
            anchor===nothing && (anchor=q)
        end
    end
end

include("sdp_transformer_fixtures.jl")
include("ac_validation_fixtures.jl")
@testset "Affine sharing composes with transformer units and original winding bounds" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta"),reverse in (false,true)
        net,p=_audit_transformer_state(kind;reverse,rotation=.23)
        tx=net["transformer"][kind]["tx"]
        for side in ("from","to");tx["i_max_$side"]=max.(tx["i_max_$side"],1e-6);end
        @test physical_residuals(net,p;delta_dispatch=:coil).passed
        for sharing in (:signed,:proportional,:complex_proportional),sb in (1e3,1e5)
            opts=(;s_base=sb,objective=:source_import,lifting=:bounded_observations,
                observation_support_threshold=0,observation_sharing=sharing,
                device_elimination=:transformer_currents,transformer_scaling=:nominal,row_scaling=:composed)
            b=build_opf(net,IVRNLP(;opts...));r=ivr_nlp_point_report(b,p)
            @test r.passed && length(r.variable_values)==num_variables(b.model)
            @test ivr_nlp_point_report(build_opf(net,IVRNLP()),r.reconstructed_point).passed
            for side in ("from","to")
                bad=deepcopy(net);rating=bad["transformer"][kind]["tx"]["i_max_$side"]
                rating[findfirst(>(1e-6),rating)]*=.5
                @test !physical_residuals(bad,p;delta_dispatch=:coil).passed
                @test !ivr_nlp_point_report(build_opf(bad,IVRNLP(;opts...)),p).passed
            end
        end
    end
end

@testset "Affine sharing preserves each interior sequence and terminal voltage family" begin
    for m in (2,3,4),sharing in (:signed,:proportional,:complex_proportional)
        net=A.H.case(conductors=m,segments=4,charged=true)
        full=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
        result=solve_ivr_nlp_opf(full;solver_options=A.P.STRICT)
        @test result.solve.optimal
        p=ACPoint(voltage=result.voltage_candidate,currents=result.current_candidate)
        opts=(;linear_elimination=:passive_blocks,specialization=:conductor_regions,
            lifting=:bounded_observations,observation_support_threshold=0,observation_sharing=sharing)
        for bus in ("b1","b2","b3")
            phases=m==2 ? ["a"] : ["a","b","c"];v=[p.voltage[(bus,t)] for t in phases]
            vn=m==3 ? 0im : p.voltage[(bus,"n")];u=v.-vn;a=cis(2pi/3)
            bounds=Dict("v_min"=>abs.(v),"v_max"=>abs.(v))
            m!=3 && merge!(bounds,Dict("vpn_min"=>abs.(u),"vpn_max"=>abs.(u),"vn_max"=>[abs(vn)]))
            if m>=3
                merge!(bounds,Dict("vpp_min"=>abs.([v[1]-v[2],v[2]-v[3],v[3]-v[1]]),
                    "vpp_max"=>abs.([v[1]-v[2],v[2]-v[3],v[3]-v[1]]),
                    "vpos_min"=>[abs(sum([1,a,a^2].*u)/3)],"vpos_max"=>[abs(sum([1,a,a^2].*u)/3)],
                    "vneg_max"=>[abs(sum([1,a^2,a].*u)/3)],"vzero_max"=>[abs(sum(u)/3)]))
            end
            for (field,x) in bounds,k in eachindex(x)
                x[k]>1e-5 || continue
                bad=deepcopy(net);lower=endswith(field,"min")
                bad["bus"][bus][field]=lower ? .5x : 2x
                bad["bus"][bus][field][k]=lower ? 1.5x[k] : .5x[k]
                audit=physical_residuals(bad,p;delta_dispatch=:coil)
                @test any(r->r.label=="bus/$bus/$field" && r.residual>getproperty(audit.tolerances,r.unit),audit.records)
                @test !ivr_nlp_point_report(build_opf(bad,IVRNLP(;opts...)),p).passed
            end
        end
    end
end
end
