using Test, FormulationLab, Clarabel, JuMP, JSON3
include("lindist3flow_fixtures.jl")
function reduction_case(;pi=false)
    n=_l3f_case()
    n["bus"]["middle"]=Dict{String,Any}("terminal_names"=>["a"],"perfectly_grounded_terminals"=>String[])
    l=n["line"]["line"];l["bus_to"]="middle";l["length"]=0.4
    n["line"]["second"]=merge(deepcopy(l),Dict("bus_from"=>"middle","bus_to"=>"load","length"=>0.6))
    if pi;n["linecode"]["lc"]["B_from_1_1"]=1e-3;n["linecode"]["lc"]["B_to_1_1"]=1e-3;end
    n
end
@testset "Shared network reduction and reconstruction" begin
    for pi in (false,true)
        net=reduction_case(;pi);before=deepcopy(net)
        p=prepare_network(net;warn=false)
        @test net==before
        @test length(p.network["bus"])==2
        @test only(values(p.network["line"]))["length"]≈1
        @test reduction_report(p)["approximate"]==pi
        restored=restore_prepared_network(JSON3.read(JSON3.write(reconstruction_plan(p)),Dict{String,Any}))
        @test restored.network==p.network
        @test restored.plan.original==p.plan.original
        if pi
            exact=prepare_network(net;reduction=ReductionOptions(series_merge_policy=:exact),warn=false)
            @test length(exact.network["bus"])==3
        end
        for f in (IVRSOC(objective=:source_import),IVRSDP(objective=:source_import),LinDist3Flow(objective=:source_import))
            # L3F intentionally refuses π lines; reduction must not bypass that.
            if pi && f isa LinDist3Flow;continue;end
            b=build_opf(p,f)
            r=b isa SOCBuild ? solve_soc_opf(b;solver_options=(verbose=false,)) : b isa SDPBuild ? solve_sdp_opf(b;solver_options=(verbose=false,)) : solve_opf(p,f;solver_options=(verbose=false,))
            @test r.solve.optimal
            full=reconstruct_solution(p,r;build=b isa SOCBuild ? b.electrical : b isa SDPBuild ? b : nothing,warn=false)
            @test Set(keys(full.buses))==Set(keys(net["bus"]))
            @test Set(keys(full.lines))==Set(keys(net["line"]))
            @test full.diagnostics["linear_system_residual"]<1e-8
            v=full.point.voltage
            if !pi;@test v[("middle","a")]≈.6v[("source","a")]+.4v[("load","a")];end
            @test full.point.currents[(:line_to,"line")]+full.point.currents[(:line_from,"second")]≈[0im] atol=1e-8
            b isa SOCBuild && @test all(!occursin("Semidefinite",string(S)) for (_,S) in list_of_constraint_types(b.model))
        end
    end
    for blocker in (:ground,:bound,:device,:permutation,:rating)
        n=reduction_case()
        blocker==:ground && (n["bus"]["middle"]["perfectly_grounded_terminals"]=["a"])
        blocker==:bound && (n["bus"]["middle"]["v_min"]=[210.])
        blocker==:device && (n["load"]["load"]["bus"]="middle")
        blocker==:permutation && (n["line"]["second"]["terminal_map_from"]=["b"])
        blocker==:rating && (n["line"]["second"]["s_max"]=[20000.])
        p=prepare_network(n;reduction=ReductionOptions(dangling_lines=false),warn=false)
        @test haskey(p.network["bus"],"middle")
    end
    n=reduction_case();n["bus"]["middle"]["v_min"]=[235.]
    p=prepare_network(n;reduction=ReductionOptions(allow_drop_bus_constraints=true),warn=false)
    @test !haskey(p.network["bus"],"middle")
    @test reduction_report(p)["approximate"]
    @test_throws ArgumentError prepare_network(n;reduction=:typo)
end

@testset "Pruned π branches, switch identity, and orientation" begin
    n=reduction_case(pi=true)
    n["bus"]["stub"]=Dict{String,Any}("terminal_names"=>["a"],"v_max"=>[240.])
    n["line"]["stubline"]=merge(deepcopy(n["line"]["line"]),Dict("bus_from"=>"source","bus_to"=>"stub","length"=>.2))
    p=prepare_network(n;warn=false)
    full=reconstruct_solution(p,ACPoint(voltage=Dict(("source","a")=>230.0+0im,("load","a")=>220.0-3im));warn=false)
    @test !haskey(p.network["bus"],"stub")
    @test abs(only(full.point.currents[(:line_to,"stubline")]))<1e-8
    @test abs(full.point.voltage[("stub","a")]-230)>1e-6
    @test any(e["code"]=="BOUND_DROPPED" for e in p.plan.events)
    # Reversing a symmetric π section preserves the reconstructed circuit.
    nr=deepcopy(n);l=nr["line"]["second"];l["bus_from"],l["bus_to"]=l["bus_to"],l["bus_from"]
    pr=prepare_network(nr;warn=false)
    fr=reconstruct_solution(pr,ACPoint(voltage=Dict(("source","a")=>230.0+0im,("load","a")=>220.0-3im));warn=false)
    @test all(fr.point.voltage[k]≈v for (k,v) in full.point.voltage)
    @test fr.lines["second"]["power_to"]≈full.lines["second"]["power_from"]
    # Closed-switch bus identities and flow are recovered on original IDs.
    n=_l3f_case();n["bus"]["junction"]=deepcopy(n["bus"]["source"])
    n["line"]["line"]["bus_from"]="junction"
    n["switch"]=Dict("s"=>Dict("bus_from"=>"source","bus_to"=>"junction","terminal_map_from"=>["a"],"terminal_map_to"=>["a"],"open_switch"=>false,"i_max"=>[100.]))
    p=prepare_network(n;warn=false);r=solve_opf(p,IVRSOC(objective=:source_import);solver_options=(verbose=false,))
    f=reconstruct_solution(p,r;warn=false)
    @test f.point.voltage[("source","a")]≈f.point.voltage[("junction","a")]
    @test f.point.currents[(:switch_to,"s")]+f.point.currents[(:line_from,"line")]≈[0im] atol=1e-8
    @test isempty(f.diagnostics["physical"].unassessed)
    @test f.diagnostics["boundary_current_mismatch_A"]<1e-3
    # Round-tripped plans do not depend on integer matrix types or solver refs.
    q=restore_prepared_network(JSON3.read(JSON3.write(reconstruction_plan(p)),Dict{String,Any}))
    g=reconstruct_solution(q,r;warn=false)
    @test g.point.voltage==f.point.voltage
end

@testset "Transformer attachments survive preparation" begin
    n=reduction_case()
    # A winding-list attachment is just as meaningful as a two-port device.
    n["transformer"]=Dict("n_winding"=>Dict("t"=>Dict("windings"=>[Dict("bus"=>"middle"),Dict("bus"=>"load") ])))
    p=prepare_network(n;reduction=ReductionOptions(dangling_lines=false),warn=false)
    @test haskey(p.network["bus"],"middle")
    # Local ideal transformer current convention for a voltage-only seed.
    n=Dict{String,Any}("bus"=>Dict("s"=>Dict("terminal_names"=>["a"]),"l"=>Dict("terminal_names"=>["a"])),
        "transformer"=>Dict("single_phase"=>Dict("t"=>Dict("bus_from"=>"s","bus_to"=>"l","terminal_map_from"=>["a"],"terminal_map_to"=>["a"],"v_nom_from"=>230.,"v_nom_to"=>115.,"tap"=>1.))),
        "voltage_source"=>Dict("s"=>Dict("bus"=>"s","terminal_map"=>["a"],"v_magnitude"=>[230.],"v_angle"=>[0.])))
    p=prepare_network(n;warn=false)
    f=reconstruct_solution(p,ACPoint(voltage=Dict(("s","a")=>230.0+0im,("l","a")=>115.0+0im));warn=false)
    @test "single_phase/t" in f.diagnostics["inferred_transformers"]
    @test all(iszero,f.point.currents[(:transformer_coil_from,"single_phase/t")])
end

@testset "Cascaded switch currents include downstream subtrees" begin
    n=_l3f_case()
    for b in ("one","two");n["bus"][b]=deepcopy(n["bus"]["source"]);end
    n["line"]["line"]["bus_from"]="two"
    sw(f,t)=Dict("bus_from"=>f,"bus_to"=>t,"terminal_map_from"=>["a"],"terminal_map_to"=>["a"],"open_switch"=>false)
    n["switch"]=Dict("first"=>sw("source","one"),"second"=>sw("one","two"))
    p=prepare_network(n;warn=false)
    r=solve_opf(p,IVRSOC(objective=:source_import);solver_options=(verbose=false,))
    f=reconstruct_solution(p,r;warn=false)
    @test f.point.currents[(:switch_from,"first")]≈f.point.currents[(:switch_from,"second")]
    @test f.point.currents[(:switch_from,"first")]≈f.point.currents[(:line_from,"line")]
end

@testset "Static inverter filter state recovery" begin
    for topology in ("FOUR_LEG","THREE_LEG")
        tm=topology=="FOUR_LEG" ? ["a","b","c","n"] : ["a","b","c"]
        volts=230cis.([0.,-2pi/3,2pi/3]);topology=="FOUR_LEG" && push!(volts,0)
        n=Dict{String,Any}("bus"=>Dict("b"=>Dict("terminal_names"=>tm,"perfectly_grounded_terminals"=>filter(==("n"),tm))),
            "voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>tm,"v_magnitude"=>abs.(volts),"v_angle"=>angle.(volts))),
            "ibr"=>Dict("g"=>Dict("bus"=>"b","terminal_map"=>tm,"topology"=>topology,"s_max"=>fill(1000.,3),"p_min"=>fill(200.,3),"p_max"=>fill(200.,3),"q_min"=>zeros(3),"q_max"=>zeros(3))))
        p=prepare_network(n;warn=false)
        r=solve_opf(p,IVRSOC(objective=:source_import);solver_options=(verbose=false,))
        f=reconstruct_solution(p,r;warn=false)
        @test haskey(f.point.currents,(:ibr_internal,"g"))
        @test isempty(f.diagnostics["physical"].unassessed)
        @test maximum(x.residual for x in f.diagnostics["physical"].records if x.label=="ibr/g/filter_current")<1e-6
    end
end
