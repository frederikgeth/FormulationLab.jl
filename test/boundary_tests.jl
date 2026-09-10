using Test, FormulationLab, JSON3, PowerIO, Clarabel
include("lindist3flow_fixtures.jl")

@testset "PowerIO BMOPF boundary" begin
    net = _l3f_case()
    net["line"]["line"]["length"] = 1.0
    net["name"] = "FormulationLab boundary fixture"
    net["meta"] = Dict("schema_version" => "0.2.0", "frequency" => 50.0)
    net["extras"] = Dict("retained_test_metadata" => Dict("value" => 3))
    raw = JSON3.write(net)
    input = read_bmopf(raw)
    @test input.network == net
    @test input.schema_version == "0.2.0"
    @test length(input.source_sha256) == 64
    @test read_bmopf(IOBuffer(raw)).source_sha256 == input.source_sha256
    mktemp() do path, io
        write(io, raw); close(io)
        @test read_bmopf(path).network == input.network
    end
    module_value = PowerIO.parse(IOBuffer(raw); format="bmopf-json")
    @test read_bmopf(module_value).network == net
    for value in (input, module_value, raw)
        r = solve_l3f_opf(value; solver_options=(verbose=false,))
        @test r.solve.optimal
        @test r.formulation["model_kind"] == "approximation"
        @test !r.formulation["provides_ac_lower_bound"]
        @test r.network["extras"] == net["extras"]
    end
    @test_throws Exception read_bmopf("{broken json")
end

@testset "Replay requires an explicit callback" begin
    r = solve_l3f_opf(_l3f_case(); options=L3FOptions(validate_nonlinear=true),
                      solver_options=(verbose=false,))
    @test r.solve.optimal
    @test r.validation["status"] == "unavailable"
    @test_throws ArgumentError l3f_reference_from_powerflow(_l3f_case())
    calls = Ref(0)
    # A test double checks the callback contract, not nonlinear power-flow accuracy.
    function callback(net; kwargs...)
        calls[] += 1
        net["callback_mutation"] = true
        Dict("termination_status" => "LOCALLY_SOLVED", "bus" => Dict(
            b => Dict(t => Dict("vr" => 230.0, "vi" => 0.0)
                      for t in data["terminal_names"]) for (b,data) in net["bus"]))
    end
    reference = l3f_reference_from_powerflow(_l3f_case(); powerflow=callback)
    @test reference.provenance == :power_flow
    v = validate_l3f_solution(r; powerflow=callback)
    @test v["status"] == "replayed"
    @test calls[] == 2
    @test !haskey(r.network, "callback_mutation")
    @test v["physical_limits"] == "unassessed"
end

@testset "Scaling across independent islands and shared linecodes" begin
    first = _l3f_case()
    second = _l3f_case()
    # Two electrically separate feeders sharing an SI linecode, at different voltages.
    for data in values(second["bus"])
        for field in ("v_min", "v_max")
            haskey(data, field) && (data[field] .*= 2)
        end
    end
    second["voltage_source"]["source"]["v_magnitude"] .*= 2
    for family in ("bus", "line", "load", "voltage_source")
        for (id, data) in second[family]
            copy_data = deepcopy(data)
            for f in ("bus", "bus_from", "bus_to")
                haskey(copy_data, f) && (copy_data[f] *= "2")
            end
            first[family][id * "2"] = copy_data
        end
    end
    original = deepcopy(first)
    si = solve_l3f_opf(first; options=L3FOptions(per_unit=false), solver_options=(verbose=false,))
    pu = solve_l3f_opf(first; options=L3FOptions(s_base=20_000.0), solver_options=(verbose=false,))
    @test first == original
    @test si.solve.optimal && pu.solve.optimal
    for b in keys(first["bus"])
        @test pu.buses[b]["a"]["w"] ≈ si.buses[b]["a"]["w"] rtol=1e-7
    end
    @test pu.objective ≈ si.objective rtol=1e-7
end

@testset "BMOPF proposal fields do not silently disappear" begin
    for key in ("dc_branch", "dc_grounding", "time_series")
        net=_l3f_case();net[key]=Dict("component"=>Dict{String,Any}())
        @test !is_l3f_applicable(check_l3f_applicability(net))
    end
    net=_l3f_case();delete!(net,"line");delete!(net,"linecode")
    net["transformer"]=Dict("single_phase"=>Dict("t"=>Dict{String,Any}(
        "bus_from"=>"source","bus_to"=>"load","terminal_map_from"=>["a"],
        "terminal_map_to"=>["a"],"v_nom_from"=>230.0,"v_nom_to"=>230.0,"tap_ratio"=>1.05)))
    r=solve_l3f_opf(net;solver_options=(verbose=false,))
    @test r.buses["load"]["a"]["vm"] ≈ 230/1.05 rtol=1e-7
    @test !haskey(net["transformer"]["single_phase"]["t"],"tap")
    net["transformer"]["single_phase"]["t"]["tap"]=0.9
    @test_throws ArgumentError build_l3f_opf(net)
end

@testset "Problem/formulation/optimizer separation" begin
    @test formulation_kind(LinDist3Flow()) == :approximation
    @test formulation_kind(IVRSDP()) == :relaxation
    build=build_opf(_l3f_case(),LinDist3Flow();optimizer=nothing)
    @test build isa L3FBuild
    @test JuMP.termination_status(build.model) == JuMP.MOI.OPTIMIZE_NOT_CALLED
    @test solve_opf(_l3f_case(),LinDist3Flow();solver_options=(verbose=false,)).solve.optimal
    @test build_opf(_l3f_case(),IVRSDP();optimizer=nothing) isa SDPBuild
end
