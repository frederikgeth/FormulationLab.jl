using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/benchmark_ivr_nwinding_regional.jl")
const _NWREG=IVRNWindingRegionalStudy

@testset "Regional current units respect multiwinding boundaries and physical bounds" begin
    N=_NWREG.N;net,templates=N.network(2);original=deepcopy(net);start=N.S.start_point(net)
    for workload in (:cost,:tracking)
        full=build_opf(net,IVRNLP(;objective=:power,power_terms=N.terms(net,workload),transformer_nameplate=:bmopftools))
        anchor=nothing;objective=nothing
        for representation in [p.name for p in N.profiles(net,workload,1e5)]
            ps=_NWREG.profiles(net,workload,representation)
            @test Set((p.factors.primary_base_VA,p.factors.secondary_base_VA) for p in ps)==Set(Iterators.product((1e3,1e5),(1e3,1e5)))
            for a in ps,b in ps
                changed=Set(k for k in fieldnames(IVRNLPOptions) if JSON3.write(getfield(a.options,k))!=JSON3.write(getfield(b.options,k)))
                @test changed==(a.name==b.name ? Set{Symbol}() : Set([:current_power_bases]))
            end
            # High/high reproduces the preceding fixed-assembly/generator control.
            control=build_opf(net,IVRNLP(IVRNLPOptions(; (k=>(k==:current_power_bases ? Dict{String,Float64}() : deepcopy(getfield(ps[4].options,k))) for k in fieldnames(IVRNLPOptions))...)))
            for p in ps
                b=build_opf(net,IVRNLP(p.options);optimizer=Ipopt.Optimizer);d=b.numerical_diagnostics
                q=d[:transformer_scaling_report]
                @test d[:per_unit_bases].power_VA==1e5 && d[:objective_scale]==1.
                @test all(==(1e3),values(d[:generator_power_bases])) && d[:lifted_power_base]==500.
                @test all(==(500.),values(d[:load_power_bases])) && isempty(d[:load_power_row_bases])
                @test q.power_bases["grid"]==1e5
                @test all(q.power_bases[x]==p.factors.primary_base_VA for x in ("lv","hub","u1_b1","u2_b1"))
                @test q.bases["grid"]==2300. && q.bases["hub"]==230.
                for u in 1:2,k in 2:4,suffix in ("","_mid","_end")
                    bus="u$(u)_b$k"*suffix
                    @test q.power_bases[bus]==p.factors.secondary_base_VA
                    @test q.bases[bus]==b.electrical.vb && q.retained_buses[bus]=="no_nonzero_source_base"
                end
                @test all(==("unsupported_nominal_base_contract"),values(q.skipped_transformers))
                @test q.bases==control.numerical_diagnostics[:transformer_scaling_report].bases
                # Coordinate supports and retained voltage columns stay unchanged. At least
                # one current coefficient must change for every noncontrol arm.
                @test all(Set(keys(a))==Set(keys(c)) for (a,c) in zip(b.coordinates.reconstruction,control.coordinates.reconstruction))
                voltage_indices=Set(values(b.electrical.voltage))
                for (j,row) in enumerate(b.coordinates.projection)
                    all(k->k in voltage_indices,keys(row)) || continue
                    @test row==control.coordinates.projection[j]
                end
                # Eliminated voltages contain current terms, so their composed
                # recovery coefficients legitimately change with current units.
                @test (b.coordinates.reconstruction==control.coordinates.reconstruction)==(p.name==ps[4].name)
                encoded=ivr_nlp_point_report(b,start)
                @test isempty(encoded.missing_channels) && length(encoded.variable_values)==num_variables(b.model) && all(isfinite,values(encoded.variable_values))
                @test max(encoded.max_binding_residual_pu,encoded.max_reconstruction_residual_pu)<=1e-10
                for (v,x) in encoded.variable_values;set_start_value(v,x);end
                r=solve_ivr_nlp_opf(b;solver_options=N.SETTINGS)
                @test r.solve.optimal && physical_residuals(net,r).passed
                point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
                @test ivr_nlp_point_report(b,point).passed && ivr_nlp_point_report(full,point).passed
                if anchor===nothing;anchor=point;objective=r.objective;end
                @test ivr_nlp_point_report(b,anchor).passed
                @test r.objective≈objective atol=1e-7 rtol=1e-6
                @test all(q.ampere_turn_A<1e-6 && q.leakage_V<1e-6 && q.loss_identity_VA<1e-3 for q in N.equations(templates,point))
                # Challenge both sides of a current-unit boundary independently.
                for id in ("trunk","u1_secondary2b")
                    current=abs(point.currents[(:line_from,id)][1]);@test current>1e-6
                    tight=deepcopy(net);tight["line"][id]["i_max"]=[.5current,1e6,1e6,1e6]
                    @test !physical_residuals(tight,point;delta_dispatch=:coil).passed
                    @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(p.options)),point).passed
                end
            end
            empty!(ps[1].options.current_power_bases)
            @test all(length(p.options.current_power_bases)==8 for p in ps[2:end])
        end
    end
    @test net==original
    bad=_NWREG.seeds(net,1e3,1e5);bad["lv"]=1e5
    @test_throws ArgumentError build_opf(net,IVRNLP(transformer_scaling=:nominal,current_power_bases=bad))
    @test_throws ArgumentError _NWREG.seeds(net,0.,1e3)
    @test_throws ArgumentError _NWREG.profiles(net,:cost,"unknown")
end
