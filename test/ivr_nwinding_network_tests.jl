using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/benchmark_ivr_nwinding_network.jl")
const _NWNET=IVRNWindingNetworkStudy

@testset "Live non-star networks preserve power workloads, bounds and coupling" begin
    for workload in (:cost,:tracking)
        net,templates=_NWNET.network(2);original=deepcopy(net);start=_NWNET.S.start_point(net)
        full=build_opf(net,IVRNLP(;objective=:power,power_terms=_NWNET.terms(net,workload),transformer_nameplate=:bmopftools))
        anchor=nothing;objective=nothing
        for p in _NWNET.profiles(net,workload,1e4)
            b=build_opf(net,IVRNLP(p.options);optimizer=Ipopt.Optimizer)
            encoded=ivr_nlp_point_report(b,start)
            @test isempty(encoded.missing_channels) && length(encoded.variable_values)==num_variables(b.model)
            @test max(encoded.max_binding_residual_pu,encoded.max_reconstruction_residual_pu)<=1e-10
            for (v,x) in encoded.variable_values;set_start_value(v,x);end
            r=solve_ivr_nlp_opf(b;solver_options=_NWNET.SETTINGS)
            @test r.solve.optimal && physical_residuals(net,r).passed
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(full,point).passed && ivr_nlp_point_report(b,point).passed
            if anchor===nothing;anchor=point;objective=r.objective;end
            @test ivr_nlp_point_report(b,anchor).passed
            @test r.objective≈objective atol=1e-7 rtol=1e-6
            for q in _NWNET.equations(templates,point)
                @test q.ampere_turn_A<1e-6 && q.leakage_V<1e-6 && q.loss_identity_VA<1e-3
            end
            for id in keys(templates),k in 1:4
                @test maximum(abs,point.currents[(:transformer_coil,"n_winding/$id/$k")])>1e-6
            end
            # Each bounded winding must retain its own coil cap after both
            # line and device elimination, independently of whether it binds.
            for id in keys(templates),k in (2,4)
                tight=deepcopy(net);w=tight["transformer"]["n_winding"][id]["windings"][k]
                tm=w["terminal_map"];other=w["configuration"]=="DELTA" ? mod1(1+get(w,"delta_roll",1),3) : 4
                v=point.voltage[(w["bus"],tm[1])]-point.voltage[(w["bus"],tm[other])]
                s=abs(v*conj(point.currents[(:transformer_coil,"n_winding/$id/$k")][1]))
                @test s>1e-6
                w["s_max"]=[.5s,w["s_max"]/3,w["s_max"]/3]
                @test !physical_residuals(tight,point;delta_dispatch=:coil).passed
                @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(p.options)),point).passed
            end
            io=IOBuffer();d=result_dict(b,r);write_result(d,io);seekstart(io)
            @test isequal(read_result(io),d)
            # A load change in unit 1 changes unit 2's upstream voltage:
            # these units share an electrical supply, not a block-diagonal solve.
            if p.options.device_elimination==:all_transformer_currents && p.options.lifting==:powers
                before=point.voltage[("u2_b1","a")]
                load=net["load"]["u1_w3c1"]
                # The update API deliberately accepts constant-power loads only.
                @test_throws ArgumentError update_ivr_loads!(b,Dict("u1_w3c1"=>(p=1.1load["p_nom"],q=load["q_nom"])))
                @test b.network["load"]["u1_w3c1"]["p_nom"]==load["p_nom"]
                changed=deepcopy(net);changed["load"]["u1_w3c1"]["p_nom"]*=1.1
                rebuilt=build_opf(changed,IVRNLP(p.options);optimizer=Ipopt.Optimizer)
                updated=solve_ivr_nlp_opf(rebuilt;solver_options=_NWNET.SETTINGS)
                @test updated.solve.optimal && physical_residuals(changed,updated).passed
                @test abs(updated.voltage_candidate[("u2_b1","a")]-before)>1e-7
            end
        end
        @test net==original
    end
end
