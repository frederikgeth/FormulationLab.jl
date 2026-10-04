using Test, FormulationLab, LinearAlgebra
isdefined(@__MODULE__,:_sdp_tx_case) || include("sdp_transformer_fixtures.jl")
isdefined(@__MODULE__,:_audit_nwinding_state) || include("ac_validation_fixtures.jl")

# Count the whole-network bus scan entry, not bus lookups during stamping.
struct _NeutralScanInput <: AbstractDict{String,Any}
    data::Dict{String,Any}
    scans::Base.RefValue{Int}
end
Base.getindex(d::_NeutralScanInput,k)=d.data[k]
Base.haskey(d::_NeutralScanInput,k)=haskey(d.data,k)
Base.length(d::_NeutralScanInput)=length(d.data)
Base.iterate(d::_NeutralScanInput,args...)=iterate(d.data,args...)
function Base.get(d::_NeutralScanInput,k,default)
    k=="bus" && (d.scans[]+=1)
    get(d.data,k,default)
end
_neutral_scan_input(net)=_NeutralScanInput(net,Ref(0))
_neutral_assembly(net)=FormulationLab._ivr_electrical_data(net;s_base=1e4,
    line_records=true,source_mode=:affine,delta_dispatch=:coil,record_transformer_bonds=true)

function _rename_neutral!(x)
    if x isa AbstractDict
        for (k,v) in x
            v=="n" ? (x[k]="return") : _rename_neutral!(v)
        end
    elseif x isa AbstractVector
        for k in eachindex(x)
            x[k]=="n" ? (x[k]="return") : _rename_neutral!(x[k])
        end
    end
    x
end

@testset "One assembly-local neutral index across winding and capacitor stamps" begin
    for kind in (FormulationLab._SDP_TRANSFORMERS...,"n_winding"),renamed in (false,true)
        net=kind=="n_winding" ? first(_audit_nwinding_state()) : _sdp_tx_case(kind)
        table=net["transformer"][kind];table["second"]=deepcopy(table["tx"])
        source=first(values(net["voltage_source"]));bus=source["bus"]
        tm=source["terminal_map"][1:2]
        net["capacitor"]=Dict(id=>Dict("bus"=>bus,"terminal_map"=>copy(tm),
            "configuration"=>"SINGLE_PHASE","q_rated"=>25.,"v_nom"=>230.) for id in ("c1","c2"))
        if renamed
            _rename_neutral!(net)
            net["terminal_conventions"]=Dict("neutral"=>["return"])
        end
        original=deepcopy(net);counted=_neutral_scan_input(net)
        e=_neutral_assembly(counted)
        @test counted.scans[]==1
        @test net==original
        @test e.neutral_map==FormulationLab._kr_neutral_map(net)
        @test count(d->d[1]==:capacitor,e.devices)==2
        # Every fresh assembly discovers roles again; there is no persistent
        # cache, even when the same input object is reused.
        again=_neutral_assembly(counted)
        @test counted.scans[]==2
        @test again.equations==e.equations && again.kcl==e.kcl && again.limits==e.limits
        for capacitor in values(net["capacitor"])
            direct=_neutral_scan_input(net)
            cached=FormulationLab._sdp_capacitor_plan(direct,capacitor,"capacitor";neutral_map=e.neutral_map)
            @test direct.scans[]==0
            @test cached==FormulationLab._sdp_capacitor_plan(direct,capacitor,"capacitor")
            @test direct.scans[]==1
        end
        if kind=="n_winding"
            direct=_neutral_scan_input(net)
            cached=FormulationLab._sdp_nwinding_plan(direct,"tx",table["tx"];neutral_map=e.neutral_map)
            @test direct.scans[]==0
            @test cached==FormulationLab._sdp_nwinding_plan(direct,"tx",table["tx"])
            @test direct.scans[]==1 # includes every winding's connection map
        end
        # A prior successful build cannot hide a newly ambiguous declaration.
        names=net["bus"][bus]["terminal_names"]
        net["terminal_conventions"]=Dict("neutral"=>names[1:2])
        @test_throws ArgumentError _neutral_assembly(counted)
    end
end

@testset "Standalone plans refresh authoritative neutral conventions" begin
    net=Dict{String,Any}("bus"=>Dict("b"=>Dict("terminal_names"=>["a","b","c","n"],"neutral_terminal"=>"a")),
        "terminal_conventions"=>Dict("neutral"=>["n"]))
    d=Dict("bus"=>"b","terminal_map"=>["a","b","c","n"],"configuration"=>"WYE",
        "q_rated"=>[10.,20.,30.],"v_nom"=>[230.,230.,230.])
    first_plan=FormulationLab._sdp_capacitor_plan(net,d,"c")
    @test first_plan.D==[1. 0. 0. -1.;0. 1. 0. -1.;0. 0. 1. -1.]
    net["terminal_conventions"]["neutral"]=["a"]
    @test FormulationLab._sdp_capacitor_plan(net,d,"c").D==[-1. 1. 0. 0.;-1. 0. 1. 0.;-1. 0. 0. 1.]
end
