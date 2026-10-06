module IVRCircuitTraceTests
using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
include("../examples/ivr_circuit_residual_trace.jl")
include("../examples/benchmark_ivr_nwinding_coordinates.jl")
const C=IVRCircuitResidualTrace
const B=IVRNWindingCoordinateStudy
const N=B.N

@testset "Physical row units follow provenance, never the non-KCL category" begin
    m=Model(Ipopt.Optimizer);set_silent(m)
    @variable(m,xr[1:1],start=1.);@variable(m,xi[1:1],start=0.)
    @objective(m,Min,(xr[1]-1)^2+xi[1]^2);optimize!(m)
    row=Dict(1=>1.0+0im);R=[Dict(1=>2.0+0im)];y=xr+im*xi
    function toy(;omitted=false)
        e=(;vb=230.,ib=10.,equations=[copy(row) for _ in 1:6],kcl=Dict(("b","a")=>row),
            lnc_lines=[(;id="l",equation_indices=[1])],
            transformer_current_balances=[(;id="single_phase/t",equation_indices=[2])],
            nwinding_current_blocks=[(;id="n_winding/t",current=[1,2],equation_indices=[3,4])],
            impedance_loads=[(;id="load",equation_indices=[5])])
        (;model=m,electrical=e,state=[FormulationLab._linivr_eval(r,y) for r in R],
          coordinates=(;reconstruction=R,real_variables=xr,imaginary_variables=xi),
          network=Dict("transformer"=>Dict("n_winding"=>Dict("t"=>Dict("windings"=>[1,2])))),
          numerical_diagnostics=Dict(:composed_row_normalization=>true,:kcl_row_max_base=>1.,
            :linear_elimination_report=>(;selected_series_lines=omitted ? Dict("b"=>"l") : Dict{String,String}(),impedance_loads=omitted ? ["load"] : String[],series_buses=omitted ? ["b"] : String[]),
            :device_elimination_report=>(;equation_indices=omitted ? [2,3,4] : Int[])))
    end
    for omitted in (false,true)
        b=toy(;omitted);before=precision(BigFloat);t=C.trace(b)
        @test precision(BigFloat)==before
        @test t.unclassified_equations==[6] && length(t.rows)==6
        @test [q.unit for q in t.rows]==[:V,:A,:A,:V,:A,:A]
        for q in t.rows
            @test q.float_nested_SI≈(q.unit==:V ? 460. : 20.)
            @test q.big_nested_SI≈q.float_nested_SI
            @test q.retained_constraint==!omitted
            if omitted
                @test q.gain_SI===nothing && q.divisor===nothing && q.normalized_complex_residual===nothing && q.sufficient_scalar_target===nothing
            else
                @test q.gain_SI≈(q.kind==:kcl ? 1. : q.unit==:V ? 460. : 20.)
                @test q.sufficient_scalar_target≈1e-6/(sqrt(2)*q.gain_SI)
            end
        end
    end
    for kwargs in ((;bits=true),(;bits=64),(;atol_V=0.),(;atol_A=Inf))
        @test_throws ArgumentError C.trace(toy();kwargs...)
    end
    bad=toy();bad.electrical.lnc_lines[1].equation_indices[1]=99
    @test_throws ArgumentError C.catalog(bad)
end

@testset "Retained and eliminated physical circuit residuals on a live network" begin
    net,templates=N.network(2);start=N.S.start_point(net)
    for representation in [p.name for p in N.profiles(net,:tracking,1e5)],p in B.profiles(net,:tracking,representation)
        b=build_opf(net,IVRNLP(p.options);optimizer=Ipopt.Optimizer)
        for (v,x) in ivr_nlp_point_report(b,start).variable_values;set_start_value(v,x);end
        r=solve_ivr_nlp_opf(b;solver_options=N.SETTINGS)
        @test r.solve.optimal && physical_residuals(net,r).passed
        variables=value.(all_variables(b.model));trace=C.trace(b);cat=C.catalog(b)
        @test value.(all_variables(b.model))==variables
        @test length(trace.rows)==length(cat.rows) && isempty(trace.unclassified_equations)
        @test any(q->q.unit==:V && q.retained_constraint,trace.rows)
        @test any(q->q.unit==:V && !q.retained_constraint,trace.rows)
        qmap=Dict(q.label=>q for q in trace.rows)
        # Original line drop reconstructed independently from SI endpoint values
        # and recovered series currents, including charged passive sections.
        for l in b.electrical.lnc_lines
            v=[r.voltage_candidate[(l.from,t)] for t in l.tmf]-[r.voltage_candidate[(l.to,t)] for t in l.tmt]
            jf=r.current_candidate[(:line_from,l.id)]-l.Yf*[r.voltage_candidate[(l.from,t)] for t in l.tmf]
            residual=v-l.Z*jf
            for k in eachindex(residual)
                q=qmap["line/$(l.id)/drop/$k"]
                @test q.float_nested_SI≈abs(residual[k]) atol=1e-8
                @test q.retained_constraint==!(l.id in values(b.numerical_diagnostics[:linear_elimination_report].selected_series_lines))
            end
        end
        point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        for eq in N.equations(templates,point)
            qs=[q for q in trace.rows if startswith(q.label,"transformer/n_winding/$(eq.id)/")]
            @test maximum(q.float_nested_SI for q in qs if q.unit==:A)≈eq.ampere_turn_A atol=1e-8
            @test maximum(q.float_nested_SI for q in qs if q.unit==:V)≈eq.leakage_V atol=1e-8
            @test all(q.retained_constraint==(p.options.device_elimination!=:all_transformer_currents) for q in qs)
        end
        old=Dict((q.bus,q.terminal)=>q for q in C.K.trace(b))
        for q in trace.rows
            @test abs(q.big_nested_SI-q.float_nested_SI)<=q.nested_roundoff_SI+1e-12
            if q.retained_constraint
                @test q.gain_SI>0 && isfinite(q.gain_SI)
                @test q.normalized_scalar_residual<=q.normalized_complex_residual+1e-20
            else
                @test q.divisor===nothing && q.gain_SI===nothing && q.normalized_complex_residual===nothing
            end
            if q.kind==:kcl
                @test q.float_nested_SI==old[q.key].float_nested_A
                @test q.retained_constraint==old[q.key].retained_constraint
                q.retained_constraint && (@test q.gain_SI==old[q.key].gain_A)
            end
        end
    end
end
end
