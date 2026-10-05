# Reproducible teaching cases. Run from the repository root:
# julia --project=test examples/tutorial_exact_ivr.jl
# The documentation executes these same functions; no external datasets are used.
module ExactIVRTutorial
using FormulationLab, Ipopt, JuMP, LinearAlgebra, Printf
include("ivr_compiler_cases.jl")

const SOLVER_OPTIONS = (print_level=0, tol=1e-10, constr_viol_tol=1e-10,
                        acceptable_iter=0, max_iter=600)

"""Two-wire resistive feeder: 230 V, 0.2/0.3 ohm conductors, 2 kW load."""
function two_wire_case()
    Dict{String,Any}(
        "terminal_conventions" => Dict("phase"=>["a"], "neutral"=>["n"]),
        "bus" => Dict(
            "source"=>Dict("terminal_names"=>["a","n"], "perfectly_grounded_terminals"=>["n"]),
            "demand"=>Dict("terminal_names"=>["a","n"], "vpn_min"=>[180.],
                           "vpn_max"=>[260.], "vn_max"=>[30.])),
        "voltage_source" => Dict("grid"=>Dict("bus"=>"source", "terminal_map"=>["a","n"],
            "v_magnitude"=>[230.,0.], "v_angle"=>[0.,0.], "cost"=>[0.2])),
        "line" => Dict("service"=>Dict("bus_from"=>"source", "bus_to"=>"demand",
            "terminal_map_from"=>["a","n"], "terminal_map_to"=>["a","n"],
            "R_series_1_1"=>0.2, "R_series_2_2"=>0.3,
            "X_series_1_1"=>0., "X_series_2_2"=>0., "i_max"=>[40.,40.])),
        "load" => Dict("house"=>Dict("bus"=>"demand", "terminal_map"=>["a","n"],
            "configuration"=>"SINGLE_PHASE", "model"=>"constant_power",
            "p_nom"=>[2000.], "q_nom"=>[0.])))
end

point(result) = ACPoint(voltage=result.voltage_candidate, currents=result.current_candidate)

"""Keep solver acceptance, independent physics and encoded-model checks separate."""
function check_result(build, result)
    @assert result.solve.optimal "Strict local solver acceptance failed: $(result.solve.termination_status)"
    physical = physical_residuals(build.network, result)
    encoded = ivr_nlp_point_report(build, point(result))
    @assert physical.passed "Independent SI assessment failed"
    @assert encoded.passed "Supplied-state evaluation failed"
    (; physical, encoded)
end

function solve_checked(network; specialization=:off, objective=:source_import,linear_elimination=:off)
    build = build_opf(network, IVRNLP(; specialization, objective,linear_elimination); optimizer=Ipopt.Optimizer)
    result = solve_ivr_nlp_opf(build; solver_options=SOLVER_OPTIONS)
    checks = check_result(build, result)
    (; build, result, checks)
end

function analytical_example()
    net = two_wire_case()
    full = solve_checked(net)
    u = (230 + sqrt(230^2 - 4*0.5*2000))/2
    current = 2000/u
    neutral = 0.3current
    losses = 0.5current^2
    v = full.result.voltage_candidate
    @assert isapprox(v[("demand","a")]-v[("demand","n")], u; atol=1e-6)
    @assert isapprox(v[("demand","n")], neutral; atol=1e-6)
    @assert isapprox(full.result.current_candidate[(:line_from,"service")], [current,-current]; atol=1e-6)
    @assert isapprox(full.result.objective, 2000+losses; atol=1e-5)
    @printf("U_an = %.6f V; U_n = %.6f V; I = %.6f A; loss = %.6f W\n", u, neutral, current, losses)
    @printf("source import = %.6f W; independent physical checks = %s\n", full.result.objective, full.checks.physical.passed)
    (; net, full, u, current, neutral, losses)
end

function reduction_examples()
    println("wires | full variables | reduced variables | source import (W)")
    rows = NamedTuple[]
    for m in (2,3,4)
        net = m==2 ? two_wire_case() : ivr_compiler_case(conductors=m, segments=3, shape=:tree)
        full = solve_checked(net)
        reduced = solve_checked(net; specialization=:conductor_difference)
        @assert reduced.build.numerical_diagnostics[:specialization]==:conductor_difference
        @assert ivr_nlp_point_report(reduced.build, point(full.result)).passed
        @assert ivr_nlp_point_report(full.build, point(reduced.result)).passed
        @assert isapprox(full.result.objective, reduced.result.objective; atol=1e-5, rtol=1e-7)
        nf, nr = num_variables(full.build.model), num_variables(reduced.build.model)
        @assert nf-nr==2length(net["line"])
        @printf("%5d | %14d | %17d | %.6f\n", m, nf, nr, reduced.result.objective)
        push!(rows, (; wires=m, full_variables=nf, reduced_variables=nr, objective=reduced.result.objective))
    end
    rows
end

function reuse_example()
    net = two_wire_case()
    initial = solve_checked(net; specialization=:conductor_difference)
    build = initial.build
    variables = all_variables(build.model)
    println("demand (W) | reused import (W) | fresh import (W)")
    rows = NamedTuple[]
    for demand in (1000., 2000., 3000.)
        update_ivr_loads!(build, Dict("house"=>(p=[demand], q=[0.])))
        result = solve_ivr_nlp_opf(build; solver_options=SOLVER_OPTIONS)
        check_result(build, result)
        fresh_net = deepcopy(net)
        fresh_net["load"]["house"]["p_nom"]=[demand]
        fresh = solve_checked(fresh_net; specialization=:conductor_difference)
        @assert isapprox(result.objective, fresh.result.objective; atol=1e-5, rtol=1e-7)
        @assert ivr_nlp_point_report(fresh.build, point(result)).passed
        @assert ivr_nlp_point_report(build, point(fresh.result)).passed
        @assert all_variables(build.model)==variables
        @printf("%10.0f | %17.6f | %16.6f\n", demand, result.objective, fresh.result.objective)
        push!(rows, (; demand, reused=result.objective, fresh=fresh.result.objective))
    end
    @assert build.numerical_diagnostics[:assembly_count]==1
    @assert build.numerical_diagnostics[:update_count]==3
    @assert net["load"]["house"]["p_nom"]==[2000.]
    (; rows, build)
end

function dispatch_example()
    net = two_wire_case()
    net["generator"] = Dict("der"=>Dict("bus"=>"demand", "terminal_map"=>["a","n"],
        "configuration"=>"SINGLE_PHASE", "p_min"=>[0.], "p_max"=>[600.],
        "q_min"=>[0.], "q_max"=>[0.], "s_max"=>[1000.], "i_max"=>[10.,10.], "cost"=>[0.1]))
    first = solve_checked(net; objective=:cost)
    @assert isapprox(real(only(first.result.powers[(:generator,"der")])), 600.; atol=1e-3)
    update_ivr_generators!(first.build, Dict("der"=>(cost=[0.5],)))
    expensive = solve_ivr_nlp_opf(first.build; solver_options=SOLVER_OPTIONS)
    check_result(first.build, expensive)
    @assert abs(real(only(expensive.powers[(:generator,"der")])))<1e-3
    for (label,r,price) in (("cheap DER",first.result,0.1),("expensive DER",expensive,0.5))
        pg = real(only(r.powers[(:generator,"der")]))
        ps = sum(real, r.powers[(:voltage_source,"grid")])
        @assert isapprox(r.objective, (0.2ps+price*pg)/1000; atol=1e-7)
        @printf("%s: P_der = %.6f W; cost rate = %.6f currency/h\n", label, pg, r.objective)
    end
    (; cheap=first.result, expensive)
end

function inverter_example()
    net = two_wire_case()
    net["ibr"] = Dict("converter"=>Dict("bus"=>"demand", "terminal_map"=>["a","n"],
        "topology"=>"SINGLE_PHASE", "prime_mover"=>"BATTERY", "s_max"=>[1000.],
        "i_max"=>[10.,10.], "p_min"=>[0.], "p_max"=>[1000.], "q_min"=>[0.], "q_max"=>[0.],
        "p_avail"=>600., "r_filter"=>[0.2], "x_filter"=>[0.1], "b_filter_shunt"=>0.,
        "dc_link_coupled"=>true, "p_dc_min"=>0., "p_dc_max"=>500.))
    solved = solve_checked(net; specialization=:conductor_difference)
    r = solved.result
    p = real(only(r.powers[(:ibr,"converter")]))
    internal = real(only(r.powers[(:ibr_internal,"converter")]))
    loss = 0.2abs2(only(r.current_candidate[(:ibr_internal,"converter")]))
    @assert isapprox(internal, 500.; atol=1e-3)
    @assert isapprox(internal-p, loss; atol=1e-5)
    @assert 0 < p < 500 < 600
    @printf("P_PCC = %.6f W; P_internal = %.6f W; filter loss = %.6f W\n", p, internal, loss)
    solved
end

"""Ideal fixed regulator: ratio orientation, terminal limits and full-IVR fallback."""
function regulator_example()
    net = two_wire_case()
    delete!(net, "line")
    net["transformer"] = Dict("single_phase_autotransformer"=>Dict("reg"=>Dict(
        "bus_from"=>"source", "bus_to"=>"demand",
        "terminal_map_from"=>["a","n"], "terminal_map_to"=>["a","n"],
        "regulator_type"=>"B", "tap_ratio"=>1.04,
        "i_max_from"=>[10.,10.], "i_max_to"=>[10.,10.])))
    solved = solve_checked(net; specialization=:conductor_difference)
    key = "single_phase_autotransformer/reg"
    u = solved.result.voltage_candidate[("demand","a")]-solved.result.voltage_candidate[("demand","n")]
    @assert isapprox(u, 230*1.04; atol=1e-6)
    @assert isapprox(solved.result.current_candidate[(:transformer_to,key)][1], -2000/u; atol=1e-6)
    @assert isapprox(solved.result.objective, 2000; atol=1e-5)
    @assert solved.build.numerical_diagnostics[:specialization_report].code==:transformer_boundary
    tight = deepcopy(net)
    tight["transformer"]["single_phase_autotransformer"]["reg"]["i_max_to"][1]=8.
    @assert !ivr_nlp_point_report(build_opf(tight, IVRNLP()), point(solved.result)).passed
    assessment = physical_residuals(tight, solved.result)
    @assert [r.label for r in assessment.records if r.residual>getproperty(assessment.tolerances,r.unit)]==["transformer/$key/i_max_to"]
    @printf("fixed type-B tap 1.04: %.6f V; output current %.6f A; source import %.6f W\n", real(u), abs(2000/u), solved.result.objective)
    println("Full-IVR fallback; tightening output phase rating to 8 A rejects the unchanged state.")
    (; net, solved, assessment)
end

"""Compare five load laws at the same 0.9 pu physical coil voltage."""
function load_law_example()
    rows=NamedTuple[]
    println("law                | active power (W) | reactive power (var)")
    for law in ("constant_power","constant_current","constant_impedance","zip","exponential")
        net=two_wire_case();delete!(net,"line");delete!(net["bus"],"demand")
        net["voltage_source"]["grid"]["v_magnitude"][1]=207.
        d=net["load"]["house"];d["bus"]="source";d["model"]=law;d["v_nom"]=[230.];d["q_nom"]=[300.]
        if law=="zip"
            for (prefix,values) in (("alpha",(.2,.3,.5)),("beta",(.4,.5,.1))), (suffix,x) in zip(("z","i","p"),values)
                d[prefix*"_"*suffix]=[x]
            end
        elseif law=="exponential"
            d["gamma_p"]=[.4];d["gamma_q"]=[2.7]
        end
        solved=solve_checked(net)
        r=.9
        fp,fq=law=="constant_power" ? (1.,1.) : law=="constant_current" ? (r,r) :
            law=="constant_impedance" ? (r^2,r^2) : law=="zip" ? (.2r^2+.3r+.5,.4r^2+.5r+.1) : (r^.4,r^2.7)
        power=only(solved.result.powers[(:load,"house")])
        @assert isapprox(power,2000fp+300fq*im;atol=1e-5)
        @assert isapprox(only(solved.result.current_candidate[(:load,"house")]),conj(power/207);atol=1e-6)
        @assert solved.build.numerical_diagnostics[:load_voltage_variable_count]==0
        @printf("%-18s | %16.6f | %.6f\n",law,real(power),imag(power))
        push!(rows,(;law,power))
    end
    rows
end

"""Reduce a pendant region while retaining a phase-earth boundary and its KCL."""
function region_example()
    net=ivr_compiler_case(conductors=4,segments=3)
    net["shunt"]=Dict("earth"=>Dict("bus"=>"b1","terminal_map"=>["a"],"G_1_1"=>.002))
    full=solve_checked(net)
    regional=solve_checked(net;specialization=:conductor_regions)
    legacy=build_opf(net,IVRNLP(specialization=:conductor_difference))
    @assert legacy.numerical_diagnostics[:specialization_report].code==:bus_shunt
    report=regional.build.numerical_diagnostics[:specialization_report]
    @assert report.components==["l2","l3"] && report.boundary_buses==["b1"]
    @assert ivr_nlp_point_report(full.build,point(regional.result)).passed
    @assert ivr_nlp_point_report(regional.build,point(full.result)).passed
    @assert isapprox(full.result.objective,regional.result.objective;atol=1e-5,rtol=1e-7)
    upstream=sum(regional.result.current_candidate[(:line_from,"l1")])
    @assert abs(upstream)>.1
    @assert abs(sum(regional.result.current_candidate[(:line_from,"l2")] ))<1e-7
    nf,nr=num_variables(full.build.model),num_variables(regional.build.model)
    @assert nf-nr==4
    println("Retained boundary: b1; reduced lines: l2, l3; retained line: l1")
    @printf("JuMP variables: %d full, %d regional; upstream current sum magnitude: %.6f A\n",nf,nr,abs(upstream))
    (;net,full,regional,report)
end

"""Substitute a load current using its exact impedance law."""
function impedance_elimination_example()
    net=two_wire_case();d=net["load"]["house"]
    d["model"]="constant_impedance";d["v_nom"]=[230.]
    full=solve_checked(net)
    reduced=solve_checked(net;linear_elimination=:impedance_loads)
    y=2000/230^2;u=230/(1+.5y);current=y*u
    @assert isapprox(only(reduced.result.current_candidate[(:load,"house")]),current;atol=1e-7)
    @assert ivr_nlp_point_report(full.build,point(reduced.result)).passed
    @assert ivr_nlp_point_report(reduced.build,point(full.result)).passed
    nf,nr=num_variables(full.build.model),num_variables(reduced.build.model)
    @assert nf-nr==2
    @printf("Impedance load: %.6f V, %.6f A; variables %d -> %d\n",u,current,nf,nr)
    (;net,full,reduced)
end

"""Eliminate an unloaded intermediate bus while retaining its voltage limit."""
function series_elimination_example()
    net=two_wire_case();net["bus"]["mid"]=Dict("terminal_names"=>["a","n"],"vn_max"=>[30.])
    original=pop!(net["line"],"service")
    for id in ("first","second")
        l=deepcopy(original);l["R_series_1_1"]*=.5;l["R_series_2_2"]*=.5
        l[id=="first" ? "bus_to" : "bus_from"]="mid";net["line"][id]=l
    end
    full=solve_checked(net)
    reduced=solve_checked(net;linear_elimination=:passive,specialization=:conductor_difference)
    @assert reduced.build.numerical_diagnostics[:linear_elimination_report].series_buses==["mid"]
    @assert ivr_nlp_point_report(full.build,point(reduced.result)).passed
    @assert ivr_nlp_point_report(reduced.build,point(full.result)).passed
    @assert isapprox(full.result.objective,reduced.result.objective;atol=1e-5)
    neutral=abs(reduced.result.voltage_candidate[("mid","n")])
    tight=deepcopy(net);tight["bus"]["mid"]["vn_max"]=[neutral/2]
    b=build_opf(tight,IVRNLP(linear_elimination=:passive,specialization=:conductor_difference))
    @assert !ivr_nlp_point_report(b,point(reduced.result)).passed
    @assert !physical_residuals(tight,reduced.result).passed
    @printf("Reconstructed mid-neutral: %.6f V; variables %d -> %d\n",neutral,num_variables(full.build.model),num_variables(reduced.build.model))
    println("The tightened mid-bus neutral bound rejects the unchanged physical state.")
    (;net,full,reduced)
end

function refusal_examples()
    baseline = analytical_example()
    tight = deepcopy(baseline.net)
    tight["bus"]["demand"]["vn_max"]=[1.]
    build = build_opf(tight, IVRNLP(specialization=:conductor_difference))
    encoded = ivr_nlp_point_report(build, point(baseline.full.result))
    physical = physical_residuals(tight, baseline.full.result)
    @assert !encoded.passed && !physical.passed
    violations = [r.label for r in physical.records if r.residual>getproperty(physical.tolerances,r.unit)]
    @assert violations==["bus/demand/vn_max"]
    println("Tightened neutral bound rejects the unchanged state: ", only(violations))
    # A real phase-earth path changes the problem and invalidates zero-sum KCL.
    earth = deepcopy(baseline.net)
    earth["shunt"] = Dict("earth"=>Dict("bus"=>"demand", "terminal_map"=>["a"], "G_1_1"=>0.001))
    fallback = solve_checked(earth; specialization=:conductor_difference)
    reason = fallback.build.numerical_diagnostics[:specialization_report].code
    @assert fallback.build.numerical_diagnostics[:specialization]==:off && reason==:bus_shunt
    println("Phase-earth shunt: full-IVR fallback, reason = ", reason)
    (; encoded, physical, fallback)
end

function run_all()
    analytical_example()
    reduction_examples()
    reuse_example()
    dispatch_example()
    inverter_example()
    regulator_example()
    load_law_example()
    region_example()
    impedance_elimination_example()
    series_elimination_example()
    refusal_examples()
    println("All tutorial checks passed.")
end
end # module

if abspath(PROGRAM_FILE)==@__FILE__
    ExactIVRTutorial.run_all()
end
