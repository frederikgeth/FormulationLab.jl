using Test, FormulationLab, Clarabel, LinearAlgebra, JuMP
isdefined(@__MODULE__,:_sdp_tx_case) || include("sdp_transformer_fixtures.jl")
isdefined(@__MODULE__,:_audit_nwinding_state) || include("ac_validation_fixtures.jl")
isdefined(@__MODULE__,:linivr_case) || include("../examples/linivr_cases.jl")

_linivr_cover_solve(net;kwargs...)=solve_opf(net,LinIVR(;kwargs...);
    solver_options=(verbose=false,tol_gap_abs=1e-10,tol_gap_rel=1e-9,tol_feas=1e-9))

function _linivr_impedance_at_point!(net,point)
    for d in values(net["load"])
        tm=d["terminal_map"];b=d["bus"]
        # These analytical audit fixtures use single-phase winding loads or
        # an explicit three-phase wye/delta device.
        v=[point.voltage[(b,t)] for t in tm]
        u=d["configuration"]=="SINGLE_PHASE" ? [v[1]-v[2]] :
            d["configuration"]=="DELTA" ? v-v[[2,3,1]] : v[1:3].-v[4]
        d["model"]="constant_impedance";d["v_nom"]=abs.(u)
    end
end

@testset "LinIVR all fixed transformer families: loaded circuits and losses" begin
    for kind in ("single_phase","center_tap","wye_delta","delta_wye",
                 "single_phase_autotransformer","open_delta_regulator"),
        tap in (.94,1.06),reverse in (false,true)
        net,point=_audit_transformer_state(kind;tap,reverse)
        # Leave ample current margin for the constant-power approximation;
        # binding current ratings are tested independently below.
        tx=net["transformer"][kind]["tx"]
        tx["i_max_from"] .*= 2;tx["i_max_to"] .*= 2
        r=_linivr_cover_solve(net;objective=:losses)
        @test r.solve.optimal
        audit=physical_residuals(net,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate))
        @test isempty(audit.unassessed)
        @test audit.maxima[:voltage]<1e-6
        @test audit.maxima[:current]<1e-6
        key="$kind/tx"
        terminal_loss=sum(real,r.physical_powers[(:transformer_from,key)])+sum(real,r.physical_powers[(:transformer_to,key)])
        @test r.objective ≈ terminal_loss atol=1e-6
        @test r.numerical_diagnostics[:transformer_losses_W] ≈ terminal_loss atol=1e-6
        # Turn the independently constructed AC point into an impedance-load
        # circuit; its exact solution is now also the passive reference.
        _linivr_impedance_at_point!(net,point)
        exact=_linivr_cover_solve(net;objective=:losses)
        @test exact.solve.optimal
        @test all(abs(exact.voltage_candidate[k]-v)<1e-6 for (k,v) in point.voltage)
        @test physical_residuals(net,ACPoint(voltage=exact.voltage_candidate,currents=exact.current_candidate)).passed
    end
end

@testset "LinIVR transformer excitation, grounding and multiwinding loss identity" begin
    for kind in ("single_phase","center_tap","delta_wye")
        net=_sdp_tx_case(kind;tap=1.04)
        tx=net["transformer"][kind]["tx"]
        tx["r_series_from"]=.12;tx["x_series_from"]=.07
        tx["r_series_to"]=.05;tx["x_series_to"]=.03
        tx["no_load_shunt"]=Dict("winding"=>2,"g"=>.001,"b"=>-.002)
        # A finite secondary earth connection and asymmetric impedance loads
        # make neutral-earth dissipation observable.
        net["bus"]["t"]["perfectly_grounded_terminals"]=String[]
        tx["r_neutral_to"]=2.;tx["x_neutral_to"]=.5
        net["load"]=Dict{String,Any}()
        mt=tx["terminal_map_to"]
        neutral=findfirst(==("n"),mt)
        for (k,t) in enumerate(mt)
            k==neutral && continue
            net["load"]["d$k"]=Dict("bus"=>"t","terminal_map"=>[t,"n"],
                "configuration"=>"SINGLE_PHASE","model"=>"constant_impedance",
                "v_nom"=>[115.],"p_nom"=>[200.0k],"q_nom"=>[40.0k])
        end
        r=_linivr_cover_solve(net;objective=:losses)
        @test r.solve.optimal
        terminal_loss=sum(real,r.physical_powers[(:transformer_from,"$kind/tx")])+sum(real,r.physical_powers[(:transformer_to,"$kind/tx")])
        @test r.objective ≈ terminal_loss atol=1e-5
        @test r.objective>0
        @test physical_residuals(net,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
    end
    net,point=_audit_nwinding_state()
    _linivr_impedance_at_point!(net,point)
    r=_linivr_cover_solve(net;objective=:losses)
    @test r.solve.optimal
    @test all(abs(r.voltage_candidate[k]-v)<1e-5 for (k,v) in point.voltage)
    @test physical_residuals(net,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
    total=sum(sum(real,s) for ((f,_),s) in r.physical_powers if f==:transformer_winding)
    @test r.objective ≈ total atol=1e-5
    @test r.numerical_diagnostics[:line_shunt_losses_W] ≈ 0 atol=1e-8
end

@testset "LinIVR reference current freedom does not fix operating currents" begin
    for kind in ("wye_delta","single_phase_autotransformer")
        net=_sdp_tx_case(kind;tap=1.03)
        b=build_opf(net,LinIVR(objective=:losses))
        @test b.numerical_diagnostics[:reference_current_nullity]>0
        @test b.numerical_diagnostics[:reference_current_choice]==:minimum_norm
        @test !isempty(b.numerical_diagnostics[:ambiguous_reference_currents])
        @test b.numerical_diagnostics[:reference_residual]<1e-10
    end
    net=_sdp_tx_case("single_phase_autotransformer")
    b=build_opf(net,LinIVR())
    device=only(filter(x->x[1]==:transformer_from,b.electrical.devices))
    row=device[4][2]
    current=sum(c*b.state[k] for (k,c) in row)*b.electrical.ib
    @constraint(b.model,real(current)==3.)
    @constraint(b.model,imag(current)==-2.)
    r=solve_linivr_opf(b;solver_options=(verbose=false,))
    @test r.solve.optimal
    @test r.current_candidate[(:transformer_from,"single_phase_autotransformer/tx")][2] ≈ 3-2im atol=1e-5
    # A floating delta common mode is still an actual voltage ambiguity.
    net=_sdp_tx_case("wye_delta")
    net["bus"]["t"]["perfectly_grounded_terminals"]=String[]
    @test_throws LinIVRInapplicableError build_opf(net,LinIVR();optimizer=nothing)
end

@testset "LinIVR delta generator coil powers and coil ratings" begin
    for permutation in (["a","b","c"],["c","a","b"]),sb in (1e3,1e5)
        net=linivr_case(segments=1,loading=.25)
        # Unequal coil powers distinguish the BMOPFTools contract from the
        # legacy SDP conductor-power convention.
        ps=[300.,200.,100.];qs=[50.,20.,-10.]
        net["generator"]=Dict("delta"=>Dict("bus"=>"b1","terminal_map"=>permutation,
            "configuration"=>"DELTA","p_min"=>ps,"p_max"=>ps,
            "q_min"=>qs,"q_max"=>qs,"i_max"=>fill(.8,3),"s_max"=>fill(500.,3)))
        r=_linivr_cover_solve(net;s_base=sb)
        @test r.solve.optimal
        @test r.powers[(:generator,"delta")] ≈ complex.(ps,qs) atol=1e-5
        @test r.numerical_diagnostics[:delta_dispatch]==:coil
        for (k,t) in enumerate(permutation)
            v0=230cis(t=="a" ? 0. : t=="b" ? -2pi/3 : 2pi/3)
            tnext=permutation[mod1(k+1,3)]
            w0=230cis(tnext=="a" ? 0. : tnext=="b" ? -2pi/3 : 2pi/3)
            @test r.current_candidate[(:generator,"delta")][k] ≈ conj(complex(ps[k],qs[k])/(v0-w0)) atol=1e-6
        end
        audit=physical_residuals(net,r)
        @test audit.maxima[:current]<1e-6
        net["generator"]["delta"]["i_max"]=fill(.1,3)
        @test !_linivr_cover_solve(net;s_base=sb).solve.optimal
    end
end

@testset "LinIVR exact impedance aliases" begin
    for delta in (false,true),law in ("zip","exponential")
        net=linivr_case(segments=1,loading=.25;delta)
        d=net["load"]["d1"];d["model"]=law;d["v_nom"]=fill(delta ? 230sqrt(3) : 230.,3)
        if law=="zip"
            for prefix in ("alpha","beta")
                d[prefix*"_z"]=ones(3);d[prefix*"_i"]=zeros(3);d[prefix*"_p"]=zeros(3)
            end
        else
            d["gamma_p"]=fill(2.,3);d["gamma_q"]=fill(2.,3)
        end
        r=_linivr_cover_solve(net)
        @test r.solve.optimal
        @test physical_residuals(net,r).passed
    end
end


@testset "LinIVR static inverter connections, filters and capability" begin
    for top in ("SINGLE_PHASE","FOUR_LEG","THREE_LEG")
        net=linivr_ibr_case(top)
        r=_linivr_cover_solve(net;objective=:losses)
        @test r.solve.optimal
        @test physical_residuals(net,r).passed
        @test r.objective ≈ .2sum(abs2,r.current_candidate[(:ibr_internal,"pv")]) atol=1e-6
        @test r.objective ≈ sum(real,r.physical_powers[(:ibr_internal,"pv")])-sum(real,r.physical_powers[(:ibr,"pv")]) atol=1e-6
        @test r.numerical_diagnostics[:ibr_filter_losses_W] ≈ r.objective atol=1e-6
        @test r.powers[(:ibr,"pv")] ≈ complex.(net["ibr"]["pv"]["p_min"],net["ibr"]["pv"]["q_min"]) atol=1e-6
        if top=="THREE_LEG"
            @test maximum(abs,r.current_candidate[(:ibr,"pv")])<1.
        elseif top=="FOUR_LEG"
            net["ibr"]["pv"]["i_max"][4]=0.
            @test !_linivr_cover_solve(net).solve.optimal
        end
    end
    net=linivr_ibr_case("SINGLE_PHASE");d=net["ibr"]["pv"]
    d["p_min"]=[0.];d["p_max"]=[1000.];d["q_min"]=[0.];d["q_max"]=[0.]
    d["p_avail"]=500.;d["b_filter_shunt"]=0.;d["r_filter"]=[1.]
    r=_linivr_cover_solve(net;objective=:source_import)
    @test r.solve.optimal
    @test real(only(r.powers[(:ibr,"pv")])) ≈ 500 atol=1e-4
    d["dc_link_coupled"]=true;d["p_dc_max"]=300.
    r=_linivr_cover_solve(net;objective=:source_import)
    @test r.solve.optimal
    @test real(only(r.powers[(:ibr_internal,"pv")])) ≈ 300 atol=1e-4
    # The internal power budget is affine: report, do not hide, omitted copper
    # loss when there was zero no-load filter current.
    @test real(only(r.physical_powers[(:ibr_internal,"pv")]))>301.
    @test r.numerical_diagnostics[:max_device_power_mismatch_VA]>1.
    delete!(d,"dc_link_coupled")
    @test_throws LinIVRInapplicableError build_opf(net,LinIVR();optimizer=nothing)
    delete!(d,"p_dc_max")
    d["grid_forming"]=true;d["v_ref_internal"]=230.
    @test_throws LinIVRInapplicableError build_opf(net,LinIVR();optimizer=nothing)
    delete!(d,"grid_forming");delete!(d,"v_ref_internal");d["control_profile"]="vv"
    @test_throws LinIVRInapplicableError build_opf(net,LinIVR();optimizer=nothing)
end
