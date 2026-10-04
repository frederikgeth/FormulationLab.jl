# Optional differential check; BMOPFTools is never a runtime dependency.
include("relaxation_reference.jl")
include("../lindist3flow_fixtures.jl")
include("../../examples/linivr_cases.jl")

function run_ivr_nlp_reference(output)
    two=_l3f_case(explicit_neutral=true)
    b=two["bus"]["load"];b["perfectly_grounded_terminals"]=String[]
    delete!(b,"v_min");delete!(b,"v_max")
    b["vpn_min"]=[180.];b["vpn_max"]=[250.]
    four=linivr_case(segments=2,loading=.4)
    delta=linivr_case(segments=2,loading=.4,delta=true)
    three=deepcopy(delta)
    for b in values(three["bus"])
        b["terminal_names"]=["a","b","c"]
        pop!(b,"perfectly_grounded_terminals",nothing);pop!(b,"vn_max",nothing)
    end
    for l in values(three["line"])
        l["terminal_map_from"]=["a","b","c"];l["terminal_map_to"]=["a","b","c"]
    end
    for key in collect(keys(three["linecode"]["wire"]))
        (endswith(key,"_4") || occursin("_4_",key)) && delete!(three["linecode"]["wire"],key)
    end
    three["linecode"]["wire"]["i_max"]=[250.,250.,250.]
    s=three["voltage_source"]["source"]
    for key in ("terminal_map","v_magnitude","v_angle");s[key]=s[key][1:3];end
    three["terminal_conventions"]["neutral"]=String[]
    cases=(("two_wire",two),("four_wire_wye",four),("four_wire_delta",delta),("three_wire_delta",three))
    report=Dict{String,Any}("julia"=>string(VERSION),"ipopt"=>string(pkgversion(Ipopt)),
        "formulationlab_revision"=>readchomp(`git -C $(dirname(dirname(pathof(FormulationLab)))) rev-parse HEAD`),
        "bmopftools_revision"=>readchomp(`git -C $(dirname(dirname(pathof(BMOPFTools)))) rev-parse HEAD`),
        "note"=>"Working tree may contain uncommitted implementation. No timing or speedup claim; grounded source-current allocation is unobserved.","cases"=>Any[])
    @testset "Native exact IVR versus BMOPFTools" begin
        for (name,net) in cases
            reference=BMOPFTools.solve_opf(net;optimizer=Ipopt.Optimizer,per_unit=true,s_base=1e4,
                solver_options=("print_level"=>0,"tol"=>1e-10,"constr_viol_tol"=>1e-10))
            native=FormulationLab.solve_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer,
                solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10))
            point=reference_point(net,reference)
            reduced_build=FormulationLab.build_opf(net,IVRNLP(objective=:source_import,
                specialization=:conductor_difference);optimizer=Ipopt.Optimizer)
            full_build=FormulationLab.build_opf(net,IVRNLP(objective=:source_import))
            mapped=ivr_nlp_point_report(reduced_build,point)
            reduced=solve_ivr_nlp_opf(reduced_build;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10))
            reduced_point=ACPoint(voltage=reduced.voltage_candidate,currents=reduced.current_candidate)
            reverse=ivr_nlp_point_report(full_build,reduced_point)
            refcheck=physical_residuals(net,point;delta_dispatch=:coil)
            check=physical_residuals(net,ACPoint(voltage=native.voltage_candidate,currents=native.current_candidate);delta_dispatch=:coil)
            import_W=sum(sum(t["ps"] for t in values(x)) for x in values(reference["voltage_source"]))
            dv=maximum(abs(native.voltage_candidate[k]-v) for (k,v) in point.voltage)
            row=Dict("case"=>name,"input_sha256"=>bytes2hex(sha256(JSON3.write(net))),
                "reference_status"=>reference["termination_status"],"native_status"=>native.solve.termination_status,
                "reference_physical_passed"=>refcheck.passed,"native_physical_passed"=>check.passed,
                "reference_unassessed"=>refcheck.unassessed,"native_unassessed"=>check.unassessed,
                "reference_import_W"=>import_W,"native_import_W"=>native.objective,"max_voltage_difference_V"=>dv,
                "reduced_status"=>reduced.solve.termination_status,"reference_to_reduced_passed"=>mapped.passed,
                "reduced_to_full_passed"=>reverse.passed,"reduced_import_W"=>reduced.objective)
            push!(report["cases"],row)
            open(io->JSON3.write(io,report),output,"w")
            @test reference["termination_status"] in ("LOCALLY_SOLVED","OPTIMAL")
            @test native.solve.optimal
            @test refcheck.passed && check.passed
            @test dv<1e-5
            @test native.objective ≈ import_W atol=1e-4
            @test reduced_build.numerical_diagnostics[:specialization]==:conductor_difference
            @test mapped.passed && reverse.passed
            @test reduced.solve.optimal && physical_residuals(net,reduced_point;delta_dispatch=:coil).passed
            @test reduced.objective ≈ import_W atol=1e-4
            println(name," voltage difference ",dv," V");flush(stdout)
        end
    end
    report
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("Supply the output JSON path")
    run_ivr_nlp_reference(only(ARGS))
end
