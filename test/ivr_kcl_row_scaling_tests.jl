using Test, FormulationLab, JuMP, Ipopt
isdefined(@__MODULE__,:IVRNWindingRegionalStudy) || include("../examples/benchmark_ivr_nwinding_regional.jl")

@testset "Optional KCL row cap preserves maps, objectives and physical bounds" begin
    U=IVRNWindingRegionalStudy;N=U.N;net,templates=N.network(2);original=deepcopy(net)
    start=N.S.start_point(net)
    for workload in (:cost,:tracking),mode in (:legacy,:composed)
        full=build_opf(net,IVRNLP(;objective=:power,power_terms=N.terms(net,workload),transformer_nameplate=:bmopftools))
        anchor=nothing;objective=nothing
        for representation in [p.name for p in N.profiles(net,workload,1e5)]
            original_options=first(U.profiles(net,workload,representation)).options
            control=IVRNLPOptions(; (k=>(k==:row_scaling ? mode : deepcopy(getfield(original_options,k))) for k in fieldnames(IVRNLPOptions))...)
            base=build_opf(net,IVRNLP(control))
            for cap in (nothing,1000.)
                options=IVRNLPOptions(; (k=>(k==:kcl_row_max_base ? cap : deepcopy(getfield(control,k))) for k in fieldnames(IVRNLPOptions))...)
                b=build_opf(net,IVRNLP(options);optimizer=Ipopt.Optimizer)
                @test b.numerical_diagnostics[:kcl_row_max_base]===cap
                @test b.coordinates.projection==base.coordinates.projection && b.coordinates.reconstruction==base.coordinates.reconstruction
                @test num_variables(b.model)==num_variables(base.model)
                @test num_constraints(b.model;count_variable_in_set_constraints=true)==num_constraints(base.model;count_variable_in_set_constraints=true)
                @test b.electrical.equations==base.electrical.equations && b.electrical.kcl==base.electrical.kcl
                encoded=ivr_nlp_point_report(b,start)
                @test isempty(encoded.missing_channels) && length(encoded.variable_values)==num_variables(b.model)
                for (v,x) in encoded.variable_values;set_start_value(v,x);end
                r=solve_ivr_nlp_opf(b;solver_options=N.SETTINGS)
                @test r.solve.optimal && physical_residuals(net,r).passed
                point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
                @test ivr_nlp_point_report(b,point).passed && ivr_nlp_point_report(full,point).passed
                if anchor===nothing;anchor=point;objective=r.objective;end
                @test ivr_nlp_point_report(b,anchor).passed && ivr_nlp_point_report(base,point).passed
                @test r.objective≈objective atol=1e-7 rtol=1e-6
                @test all(q.ampere_turn_A<1e-6 && q.leakage_V<1e-6 && q.loss_identity_VA<1e-3 for q in N.equations(templates,point))
                # Numerical KCL row units never relax engineering ampere limits.
                current=abs(point.currents[(:line_from,"u1_secondary2b")][1]);@test current>1e-6
                tight=deepcopy(net);tight["line"]["u1_secondary2b"]["i_max"]=[.5current,1e6,1e6,1e6]
                @test !physical_residuals(tight,point;delta_dispatch=:coil).passed
                @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(options)),point).passed
            end
        end
    end
    for cap in (0.,-1.,NaN,Inf,nextfloat(0.))
        @test_throws ArgumentError build_opf(net,IVRNLP(s_base=1e5,kcl_row_max_base=cap))
    end
    @test net==original
    @test FormulationLab._ivrn_kcl_row_divisor(2.,10.,1000.)==2.
    @test FormulationLab._ivrn_kcl_row_divisor(1e6,10.,1000.)==100.
    @test FormulationLab._ivrn_kcl_row_divisor(1e6,10.,nothing)==1e6
end
