using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/benchmark_ivr_nwinding_scaling.jl")
const _NWUNITS=IVRNWindingScalingStudy

@testset "Multiwinding assembly/generator factorial: controlled SI correspondence" begin
    N=_NWUNITS.N
    net,templates=N.network(2);original=deepcopy(net);start=N.S.start_point(net)
    for workload in (:cost,:tracking)
        full=build_opf(net,IVRNLP(;objective=:power,power_terms=N.terms(net,workload),transformer_nameplate=:bmopftools))
        anchor=nothing;objective=nothing
        for representation in [p.name for p in N.profiles(net,workload,1e3)]
            ps=_NWUNITS.profiles(net,workload,representation)
            @test Set((p.factors.assembly_base_VA,p.factors.generator_base_VA) for p in ps)==Set(Iterators.product((1e3,1e5),(1e3,1e5)))
            for a in ps,b in ps
                changed=Set(k for k in fieldnames(IVRNLPOptions) if JSON3.write(getfield(a.options,k))!=JSON3.write(getfield(b.options,k)))
                expected=Set{Symbol}()
                a.factors.assembly_base_VA!=b.factors.assembly_base_VA && push!(expected,:s_base)
                a.factors.generator_base_VA!=b.factors.generator_base_VA && push!(expected,:generator_power_bases)
                @test changed==expected
            end
            for p in ps
                b=build_opf(net,IVRNLP(p.options);optimizer=Ipopt.Optimizer)
                d=b.numerical_diagnostics
                @test d[:generator_power_bases]==Dict(id=>p.factors.generator_base_VA for id in keys(net["generator"]))
                @test d[:lifted_power_base]==500. && all(==(500.),values(d[:load_power_bases])) && d[:objective_scale]==1.
                # The same physical dispatch must encode inversely with its own
                # column unit, even when the assembly base differs by 100x.
                encoded=ivr_nlp_point_report(b,start)
                @test isempty(encoded.missing_channels) && length(encoded.variable_values)==num_variables(b.model)
                @test max(encoded.max_binding_residual_pu,encoded.max_reconstruction_residual_pu)<=1e-10
                for (v,x) in encoded.variable_values;set_start_value(v,x);end
                r=solve_ivr_nlp_opf(b;solver_options=N.SETTINGS)
                @test r.solve.optimal && physical_residuals(net,r).passed
                point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
                @test ivr_nlp_point_report(full,point).passed && ivr_nlp_point_report(b,point).passed
                if anchor===nothing;anchor=point;objective=r.objective;end
                @test ivr_nlp_point_report(b,anchor).passed
                @test r.objective≈objective atol=1e-7 rtol=1e-6
                @test all(q.ampere_turn_A<1e-6 && q.leakage_V<1e-6 && q.loss_identity_VA<1e-3 for q in N.equations(templates,point))
                mapped=ivr_nlp_point_report(b,anchor)
                for (id,g) in b.generator_variables
                    power=anchor.currents[(:generator,id)][1]
                    gd=net["generator"][id];ts=gd["terminal_map"];bus=gd["bus"]
                    power=(anchor.voltage[(bus,ts[1])]-anchor.voltage[(bus,ts[2])])*conj(power)
                    @test mapped.variable_values[g.p[1]]*g.power_base≈real(power) atol=1e-8
                    @test mapped.variable_values[g.q[1]]*g.power_base≈imag(power) atol=1e-8
                end
                # Generator boxes must survive independent column rescaling.
                id=first(sort!(collect(keys(net["generator"]))));g=net["generator"][id]
                ts=g["terminal_map"];bus=g["bus"]
                pg=real((point.voltage[(bus,ts[1])]-point.voltage[(bus,ts[2])])*conj(point.currents[(:generator,id)][1]))
                tight=deepcopy(net);tight["generator"][id]["p_min"]=[pg+1.]
                tight["generator"][id]["p_max"]=[max(300.,pg+2.)]
                @test !physical_residuals(tight,point;delta_dispatch=:coil).passed
                @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(p.options)),point).passed
            end
            empty!(ps[1].options.generator_power_bases)
            @test all(length(p.options.generator_power_bases)==length(net["generator"]) for p in ps[2:end])
        end
    end
    @test net==original
    @test_throws ArgumentError _NWUNITS.profiles(net,:cost,"unknown")
end
