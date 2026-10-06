module IVREquationProvenanceTests
using Test, FormulationLab, LinearAlgebra
include("sdp_transformer_fixtures.jl")
include("ac_validation_fixtures.jl")
include("../examples/ivr_circuit_residual_trace.jl")
include("../examples/benchmark_ivr_nwinding_coordinates.jl")
const F=FormulationLab
const C=IVRCircuitResidualTrace
const N=IVRNWindingCoordinateStudy.N

function assemble(net;record=true,kwargs...)
    F._ivr_electrical_data(net;s_base=1e5,line_records=true,source_mode=:affine,
        record_transformer_bonds=true,record_transformer_currents=true,record_equations=record,kwargs...)
end
function correspondence(net;kwargs...)
    e=assemble(net;kwargs...);old=assemble(net;record=false,kwargs...)
    @test old.equation_metadata===nothing
    @test e.equations==old.equations && e.kcl==old.kcl && e.voltage==old.voltage
    @test e.devices==old.devices && e.limits==old.limits && e.fixed_source_coordinates==old.fixed_source_coordinates
    @test e.coordinate_count[]==old.coordinate_count[]
    @test [q.index for q in e.equation_metadata]==collect(eachindex(e.equations))
    @test all(q->q.unit in (:A,:V) && isfinite(q.assembly_multiplier) && q.assembly_multiplier>0,e.equation_metadata)
    e
end

@testset "Explicit ordinary transformer voltage units under perturbed SI points" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta","single_phase_autotransformer","open_delta_regulator"),reverse in (false,true)
        tap=1.03;net,p=_audit_transformer_state(kind;tap,reverse,rotation=.23)
        if kind in ("single_phase_autotransformer","open_delta_regulator")
            p=ACPoint(voltage=p.voltage,currents=merge(p.currents,Dict((:transformer_bond,"$kind/tx")=>ComplexF64[0.])))
        end
        b=build_opf(net,IVRNLP(s_base=1e5));e=correspondence(b.network)
        @test isempty(C.catalog(b).unclassified_equations)
        d=net["transformer"][kind]["tx"];mf=d["terminal_map_from"];mt=d["terminal_map_to"]
        if kind=="single_phase"
            pf,pt=[(1,2)],[(1,2)];gain=fill(.5/tap,1,1);zf=(.12+.05im)*tap^2;zt=.03+.015im
        elseif kind=="center_tap"
            pf,pt=[(1,2)],[(1,2),(2,3)];gain=fill(.5/tap,2,1);zf=(.12+.05im)*tap^2;zt=.03+.015im
        elseif kind=="delta_wye"
            pf,pt=[(1,3),(2,1),(3,2)],[(1,4),(2,4),(3,4)];gain=Matrix{Float64}(I,3,3)*(.5/(sqrt(3)*tap));zf=(.12+.05im)*3tap^2;zt=.03+.015im
        elseif kind=="wye_delta"
            pf,pt=[(1,4),(2,4),(3,4)],[(1,2),(2,3),(3,1)];gain=Matrix{Float64}(I,3,3)*(.5sqrt(3)/tap);zf=(.12+.05im)*tap^2;zt=3*(.03+.015im)
        else
            pf=pt=kind=="single_phase_autotransformer" ? [(1,2)] : [(1,2),(2,3)]
            gain=kind=="single_phase_autotransformer" ? fill(tap,1,1) : Matrix(Diagonal([tap,1/tap]));zf=.12+.05im;zt=.03+.015im
        end
        for perturb in (0im,2+3im)
            voltage=copy(p.voltage);voltage[("t",first(mt))]+=perturb
            point=ACPoint(voltage=voltage,currents=p.currents);encoded=ivr_nlp_point_report(b,point)
            @test isempty(encoded.missing_channels)
            y=[encoded.variable_values[x]+im*encoded.variable_values[y] for (x,y) in zip(b.coordinates.real_variables,b.coordinates.imaginary_variables)]
            z=[F._linivr_eval(row,y) for row in b.coordinates.reconstruction]
            uf=[voltage[("f",mf[a])]-voltage[("f",mf[c])] for (a,c) in pf]
            ut=[voltage[("t",mt[a])]-voltage[("t",mt[c])] for (a,c) in pt]
            jf=p.currents[(:transformer_coil_from,"$kind/tx")];jt=p.currents[(:transformer_coil_to,"$kind/tx")]
            residual=ut-zt*jt-gain*(uf-zf*jf)
            rows=filter(q->startswith(q.label,"transformer/$kind/tx/leakage/"),e.equation_metadata)
            @test length(rows)==length(pt)
            @test all(q->q.unit==:V && q.assembly_multiplier==1.,rows)
            for (k,q) in enumerate(rows)
                @test F._linivr_eval(e.equations[q.index],z)*e.vb≈residual[k] atol=1e-10
            end
            iszero(perturb) || (@test maximum(abs,residual)>1.)
        end
    end
end

@testset "Ground, switch, source and normalized shunt provenance" begin
    for ground in (0.,2.)
        net=_sdp_tx_case("single_phase");net["transformer"]["single_phase"]["tx"]["r_neutral_to"]=ground
        e=correspondence(net)
        rows=filter(q->q.label=="transformer/single_phase/tx/ground/to",e.equation_metadata)
        @test length(rows)==(ground==0. ? 1 : 0)
        isempty(rows) || (@test only(rows).unit==:V)
    end
    for open in (false,true)
        net=_sdp_tx_case("single_phase")
        net["bus"]["sw"]=deepcopy(net["bus"]["t"])
        net["switch"]=Dict("s"=>Dict("bus_from"=>"t","bus_to"=>"sw","terminal_map_from"=>["p","n"],"terminal_map_to"=>["p","n"],"open_switch"=>open))
        e=correspondence(net)
        rows=filter(q->startswith(q.label,"switch/s/drop/"),e.equation_metadata)
        @test length(rows)==(open ? 0 : 2)
        @test all(q->q.unit==:V && q.assembly_multiplier==1.,rows)
    end
    net=_sdp_tx_case("single_phase");net["shunt"]=Dict{String,Any}()
    # Use the same shunt schema accepted by the assembly, then undo its internal
    # current-row normalization. This mode is a shared-assembly control, not a
    # new IVRNLP option (native IVRNLP uses substituted admittance shunts).
    net["shunt"]["g"]=Dict("bus"=>"t","terminal_map"=>["p"],"G_1_1"=>.02,"B_1_1"=>-.01)
    e=correspondence(net;shunt_coordinates=:current)
    row=only(filter(q->q.label=="shunt/g/current/1",e.equation_metadata))
    @test row.unit==:A && row.assembly_multiplier≈abs((.02-.01im)*e.zb)
    z=ComplexF64[sin(k)+im*cos(k) for k in 1:e.coordinate_count[]]
    j=only(k for k in keys(e.equations[row.index]) if k ∉ values(e.voltage))
    expected=z[j]*e.ib-(.02-.01im)*z[e.voltage[("t","p")]]*e.vb
    @test F._linivr_eval(e.equations[row.index],z)*e.ib*row.assembly_multiplier≈expected atol=1e-10
    net=_sdp_tx_case("single_phase");_sdp_zload!(net,"d",["p","n"],.02-.005im)
    e=correspondence(net);q=only(filter(q->q.label=="load/d/impedance/1",e.equation_metadata))
    @test q.unit==:A && q.assembly_multiplier==1.
    z=ComplexF64[sin(k)+im*cos(k) for k in 1:e.coordinate_count[]]
    j=only(only(e.impedance_loads).current)
    expected=F._linivr_eval(j,z)*e.ib-(.02-.005im)*z[e.voltage[("t","p")]]*e.vb
    @test F._linivr_eval(e.equations[q.index],z)*e.ib≈expected atol=1e-10
    for ground in (0.,2.)
        net,_=_audit_nwinding_state();net["transformer"]["n_winding"]["tx"]["windings"][2]["r_neutral"]=ground
        e=correspondence(net);rows=filter(q->q.label=="transformer/n_winding/tx/ground/2",e.equation_metadata)
        @test length(rows)==(ground==0. ? 1 : 0)
        isempty(rows) || (@test only(rows).unit==:V && isempty(e.equations[only(rows).index]))
    end
    hom=F._ivr_electrical_data(_sdp_tx_case("single_phase");s_base=1e5,record_equations=true)
    @test any(q->startswith(q.label,"source/s/phasor/") && q.unit==:V,hom.equation_metadata)
    @test length(hom.equation_metadata)==length(hom.equations)
end

@testset "Complete native network catalogue and corrupt-record refusal" begin
    net,_=N.network(4);e=correspondence(net)
    @test allunique(q.label for q in e.equation_metadata)
    for p in IVRNWindingCoordinateStudy.profiles(net,:tracking,"all_transformer_currents__powers")
        b=build_opf(net,IVRNLP(p.options));c=C.catalog(b)
        @test isempty(c.unclassified_equations)
        @test length(c.rows)==length(b.electrical.equations)+length(b.electrical.kcl)
        @test count(q->q.kind==:equation && q.unit==:V && startswith(q.label,"transformer/single_phase/"),c.rows)==3
        legacy=merge(b.electrical,(;equation_metadata=nothing))
        @test length(C.catalog((;electrical=legacy,numerical_diagnostics=b.numerical_diagnostics,network=b.network)).unclassified_equations)==3
        records=b.electrical.equation_metadata;original=copy(records)
        pop!(records);@test_throws ArgumentError C.catalog(b);empty!(records);append!(records,original)
        records[1]=merge(records[1],(;unit=:unknown));@test_throws ArgumentError C.catalog(b);records[1]=original[1]
        records[1]=merge(records[1],(;assembly_multiplier=0.));@test_throws ArgumentError C.catalog(b)
    end
end
end
