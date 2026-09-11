using Test,FormulationLab,JuMP,LinearAlgebra
include("ac_validation_fixtures.jl")

@testset "Independent transformer states survive every relaxation" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta","single_phase_autotransformer","open_delta_regulator"),reverse in (false,true)
        net,p=_audit_transformer_state(kind;tap=reverse ? .94 : 1.06,rotation=.37,reverse)
        physical=physical_residuals(net,p)
        @test physical.passed
        for sb in (1000.,100_000.)
            profiles=(IVRSDP(audit=true,s_base=sb,decomposition=:dense,cone=:hermitian),
                IVRSDP(audit=true,s_base=sb,decomposition=:chordal,consistency=:local,clique_size=4),
                IVRSDP(audit=true,s_base=sb,decomposition=:chordal,consistency=:shared,clique_size=4),
                IVRSOC(audit=true,s_base=sb,strengthening=:none),
                IVRSOC(audit=true,s_base=sb,strengthening=:linear),
                IVRSOC(audit=true,s_base=sb,strengthening=:kim,max_triplets=2))
            for f in profiles
                b=build_opf(net,f;optimizer=nothing)
                before=num_constraints(b.model;count_variable_in_set_constraints=true)
                r=containment_report(b,p)
                @test r.state_residual_pu<1e-7
                @test r.max_bound_violation_pu<1e-7
            @test r.binding_residual<1e-7
                @test r.max_constraint_violation<1e-7
                @test isempty(r.missing_voltage)
                @test before==num_constraints(b.model;count_variable_in_set_constraints=true)
                @test termination_status(b.model)==MOI.OPTIMIZE_NOT_CALLED
            end
        end
    end
end

@testset "Validation rejects perturbed observations and limits" begin
    net,p=_audit_transformer_state("single_phase")
    b=build_opf(net,IVRSOC(audit=true);optimizer=nothing)
    bad=deepcopy(p);bad.voltage[("t","p")]+=1.0
    @test !physical_residuals(net,bad).passed
    @test containment_report(b,bad).state_residual_pu>1e-5
    bad=deepcopy(p);bad.currents[(:load,"l1")][1]+=0.1im
    @test !physical_residuals(net,bad).passed
    @test containment_report(b,bad).state_residual_pu>1e-5
    tight=deepcopy(net);tight["transformer"]["single_phase"]["tx"]["i_max_to"] .*= .5
    @test !physical_residuals(tight,p).passed
    r=containment_report(build_opf(tight,IVRSOC(audit=true);optimizer=nothing),p)
    @test r.max_constraint_violation>1e-6
    missing=ACPoint(voltage=copy(p.voltage))
    @test !physical_residuals(net,missing).passed
    @test !isempty(physical_residuals(net,missing).unassessed)
    @test_throws ArgumentError containment_report(build_opf(net,IVRSOC();optimizer=nothing),p)
end

@testset "Exact load-law points survive power-cone envelopes" begin
    for law in ("constant_power","constant_current","constant_impedance","zip","exponential")
        net=_l3f_case();d=net["load"]["load"];d["model"]=law;d["v_nom"]=[230.]
        d["alpha_z"]=[.2];d["alpha_i"]=[.3];d["alpha_p"]=[.5]
        d["beta_z"]=[.4];d["beta_i"]=[.3];d["beta_p"]=[.3]
        d["gamma_p"]=[.7];d["gamma_q"]=[-1.2]
        law!="zip" && foreach(k->delete!(d,k),("alpha_z","alpha_i","alpha_p","beta_z","beta_i","beta_p"))
        law!="exponential" && foreach(k->delete!(d,k),("gamma_p","gamma_q"))
        vl=220cis(-.01);i=(230-vl)/(.2+.1im);S=vl*conj(i);ratio=abs(vl)/230
        fp=law=="constant_current" ? ratio : law=="constant_impedance" ? ratio^2 : law=="zip" ? .2ratio^2+.3ratio+.5 : law=="exponential" ? ratio^.7 : 1.
        fq=law=="zip" ? .4ratio^2+.3ratio+.3 : law=="exponential" ? ratio^-1.2 : fp
        d["p_nom"]=[real(S)/fp];d["q_nom"]=[imag(S)/fq]
        net["line"]["line"]["i_max"]=[abs(i)*(1+1e-8)]
        p=ACPoint(voltage=Dict(("source","a")=>230+0im,("load","a")=>vl),
            currents=Dict((:load,"load")=>[i],(:line_from,"line")=>[i],(:line_to,"line")=>[-i],(:voltage_source,"source")=>[i]))
        @test physical_residuals(net,p).passed
        for f in (IVRSOC(audit=true,lnc=:lines),IVRSDP(audit=true))
            b=build_opf(net,f;optimizer=nothing);r=containment_report(b,p)
            @test r.max_bound_violation_pu<1e-7
            @test r.binding_residual<1e-7
            @test r.max_constraint_violation<1e-7
        end
    end
end

@testset "Coupled four-winding delta network containment" begin
    net,p=_audit_nwinding_state()
    @test physical_residuals(net,p).passed
    for f in (IVRSDP(audit=true,decomposition=:dense),IVRSDP(audit=true,decomposition=:chordal,clique_size=4),
        IVRSOC(audit=true,strengthening=:linear),IVRSOC(audit=true,strengthening=:kim,max_triplets=2))
        b=build_opf(net,f;optimizer=nothing);r=containment_report(b,p)
        @test r.state_residual_pu<1e-7
        @test r.max_bound_violation_pu<1e-7
        @test r.binding_residual<1e-7
        @test r.max_constraint_violation<1e-7
    end
end

@testset "Independent grounding and static inverter checks" begin
    for rg in (0.,2.)
        net=_sdp_tx_case("single_phase");net["bus"]["t"]["perfectly_grounded_terminals"]=String[]
        net["transformer"]["single_phase"]["tx"]["r_neutral_to"]=rg
        _sdp_zload!(net,"l",["p"],.1)
        vp=115/(1+.1rg);il=.1vp
        p=ACPoint(voltage=Dict(("f","p")=>230+0im,("f","n")=>0im,("t","p")=>complex(vp),("t","n")=>complex(vp-115)),
            currents=Dict((:load,"l")=>[complex(il)],(:voltage_source,"s")=>[complex(.5il),0im],
                (:transformer_coil_from,"single_phase/tx")=>[complex(.5il)],(:transformer_coil_to,"single_phase/tx")=>[-complex(il)],
                (:transformer_from,"single_phase/tx")=>complex.([.5il,-.5il]),(:transformer_to,"single_phase/tx")=>[-complex(il),0im]))
        @test physical_residuals(net,p).passed
        for f in (IVRSDP(audit=true),IVRSOC(audit=true))
            r=containment_report(build_opf(net,f;optimizer=nothing),p)
            @test max(r.state_residual_pu,r.binding_residual,r.max_constraint_violation)<1e-7
        end
    end
    for top in ("FOUR_LEG","THREE_LEG")
        tm=top=="FOUR_LEG" ? ["a","b","c","n"] : ["a","b","c"]
        v=230cis.([0.,-2pi/3,2pi/3]);top=="FOUR_LEG" && push!(v,0im)
        D=top=="FOUR_LEG" ? [Matrix{Float64}(I,3,3) -ones(3)] : [1. -1. 0.;0. 1. -1.;-1. 0. 1.]
        u=D*v;coil=.01u;jf=coil+.001im*u;terminal=transpose(D)*coil
        port=top=="THREE_LEG" ? terminal : coil;S=(top=="THREE_LEG" ? v : u).*conj.(port)
        e=u+(.1+.05im)*jf
        net=Dict{String,Any}("bus"=>Dict("b"=>Dict("terminal_names"=>tm,"perfectly_grounded_terminals"=>filter(==("n"),tm),"vneg_max"=>.01,"vzero_max"=>.01)),
            "voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>tm,"v_magnitude"=>abs.(v),"v_angle"=>angle.(v))),
            "ibr"=>Dict("g"=>Dict("bus"=>"b","terminal_map"=>tm,"topology"=>top,"s_max"=>fill(10000.,3),
                "p_min"=>real.(S),"p_max"=>real.(S),"q_min"=>imag.(S),"q_max"=>imag.(S),
                "r_filter"=>fill(.1,3),"x_filter"=>fill(.05,3),"b_filter_shunt"=>.001,
                "grid_forming"=>true,"v_ref_internal"=>abs(first(e)))))
        source=-terminal;top=="FOUR_LEG" && (source[4]=0)
        p=ACPoint(voltage=Dict(("b",t)=>x for (t,x) in zip(tm,v)),currents=Dict((:ibr,"g")=>port,(:ibr_internal,"g")=>jf,(:voltage_source,"s")=>source))
        @test physical_residuals(net,p).passed
        bad=deepcopy(p);bad.currents[(:ibr_internal,"g")][1]+=.1
        @test !physical_residuals(net,bad).passed
        for f in (IVRSDP(audit=true),IVRSOC(audit=true))
            r=containment_report(build_opf(net,f;optimizer=nothing),p)
            @test max(r.state_residual_pu,r.binding_residual,r.max_constraint_violation)<1e-7
        end
        net["unsupported_device"]=1
        @test !physical_residuals(net,p).passed
    end
end

@testset "Passive SI checks do not overlook missing observations" begin
    net=_l3f_case();delete!(net,"line");delete!(net,"load");delete!(net["bus"],"load")
    net["capacitor"]=Dict("c"=>Dict("bus"=>"source","terminal_map"=>["a"],"configuration"=>"SINGLE_PHASE","v_nom"=>230.,"q_rated"=>[529.]))
    net["shunt"]=Dict("y"=>Dict("bus"=>"source","terminal_map"=>["a"],"G_1_1"=>.01))
    p=ACPoint(voltage=Dict(("source","a")=>230+0im),currents=Dict((:voltage_source,"source")=>[2.3+2.3im],(:capacitor,"c")=>[2.3im]))
    @test physical_residuals(net,p).passed
    bad=deepcopy(p);bad.currents[(:capacitor,"c")][1]+=.1
    @test !physical_residuals(net,bad).passed
    bad=deepcopy(p);empty!(bad.voltage)
    @test !physical_residuals(net,bad).passed
    for f in (IVRSDP(audit=true),IVRSOC(audit=true))
        r=containment_report(build_opf(net,f;optimizer=nothing),p)
        @test max(r.state_residual_pu,r.binding_residual,r.max_constraint_violation)<1e-7
    end
end
