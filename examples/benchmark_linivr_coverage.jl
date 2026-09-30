# julia --project=test/integration examples/benchmark_linivr_coverage.jl [output.json]
# Transformer references are constructed independently from winding EMFs and
# currents, then checked in SI. They are not loaded expansion points for LinIVR.
include("benchmark_linivr.jl")
include("../test/sdp_transformer_fixtures.jl")
include("../test/ac_validation_fixtures.jl")

function linivr_transformer_sample(kind;tap=1.03,current_scale=1.0,reverse=false)
    net,point=kind=="n_winding" ? _audit_nwinding_state() :
        _audit_transformer_state(kind;tap,current_scale,reverse)
    # The independently constructed cases intentionally have binding ampacity.
    # Give this accuracy panel margin; dedicated tests enforce tight ratings.
    for table in values(net["transformer"]),tx in values(table)
        for key in ("i_max_from","i_max_to")
            haskey(tx,key) && (tx[key] = 2 .* tx[key])
        end
        for w in get(tx,"windings",[])
            haskey(w,"i_max") && (w["i_max"] = 2 .* w["i_max"])
        end
    end
    row=Dict{String,Any}("kind"=>kind,"tap"=>tap,"current_scale"=>current_scale,"reverse"=>reverse,
        "input_sha256"=>bytes2hex(sha256(JSON3.write(net))),"rating_margin_factor"=>2.)
    if kind=="n_winding"
        # This fixture defines its own winding-specific taps and currents.
        for key in ("tap","current_scale","reverse");delete!(row,key);end
        row["reference_parameters"]="fixed four-winding audit fixture"
    end
    reference=physical_residuals(net,point)
    row["reference_passed"]=reference.passed
    row["reference_maxima"]=reference.maxima
    reference.passed || error("constructed $kind reference is not physically valid")
    bt=@elapsed build=build_opf(net,LinIVR(objective=:losses))
    st=@elapsed r=solve_linivr_opf(build;solver_options=LINIVR_CLARABEL)
    merge!(row,Dict("status"=>r.solve.termination_status,"build_seconds"=>bt,"solve_seconds"=>st,
        "diagnostics"=>r.numerical_diagnostics))
    r.solve.optimal || return row
    audit=physical_residuals(net,ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate))
    row["max_conductor_phasor_error_V"]=maximum(abs(r.voltage_candidate[k]-v) for (k,v) in point.voltage)
    row["approximate_state_physical_maxima"]=audit.maxima
    row["approximate_state_physical_passed"]=audit.passed
    row["predicted_losses_W"]=r.objective
    row
end

function run_linivr_coverage(output)
    linivr_transformer_sample("single_phase") # warm common compilation
    transformer_rows=Any[]
    for kind in ("single_phase","center_tap","wye_delta","delta_wye",
                 "single_phase_autotransformer","open_delta_regulator"),
        tap in (.94,1.06),scale in (1.,10.,30.),reverse in (false,true)
        try
            push!(transformer_rows,linivr_transformer_sample(kind;tap,current_scale=scale,reverse))
        catch err
            push!(transformer_rows,Dict("kind"=>kind,"tap"=>tap,"current_scale"=>scale,"reverse"=>reverse,"error"=>sprint(showerror,err)))
        end
    end
    push!(transformer_rows,linivr_transformer_sample("n_winding"))
    device_rows=Any[]
    for top in ("SINGLE_PHASE","FOUR_LEG","THREE_LEG")
        push!(device_rows,linivr_panel_case("ibr_$top",linivr_ibr_case(top);objective=:losses))
        feeder=linivr_case(segments=2,loading=.25)
        feeder["ibr"]=deepcopy(linivr_ibr_case(top)["ibr"])
        feeder["ibr"]["pv"]["bus"]="b2"
        push!(device_rows,linivr_panel_case("feeder_ibr_$top",feeder;objective=:losses))
    end
    net=linivr_case(segments=2,loading=.25)
    net["generator"]=Dict("delta"=>Dict("bus"=>"b2","terminal_map"=>["a","b","c"],
        "configuration"=>"DELTA","p_min"=>[300.,200.,100.],"p_max"=>[300.,200.,100.],
        "q_min"=>[50.,20.,-10.],"q_max"=>[50.,20.,-10.],"s_max"=>fill(500.,3)))
    push!(device_rows,linivr_panel_case("delta_generator",net))
    data=Dict("julia"=>string(VERSION),"clarabel"=>string(pkgversion(Clarabel)),"ipopt"=>string(pkgversion(Ipopt)),
        "bmopftools_revision"=>readchomp(`git -C $(dirname(dirname(pathof(BMOPFTools)))) rev-parse HEAD`),
        "transformer_reference"=>"independently constructed AC states with SI physical validation",
        "device_reference"=>"BMOPFTools nonlinear OPF and fixed-dispatch PF",
        "kron_reduction"=>false,"repetitions"=>1,"transformers"=>transformer_rows,"devices"=>device_rows)
    open(io->JSON3.write(io,data),output,"w")
    open(splitext(output)[1]*".md","w") do io
        println(io,"# LinIVR coverage expansion — 30 September 2026\n")
        println(io,"Transformer cases vary tap (0.94/1.06), current scale (1/10/30), and flow direction. References are independently constructed from winding EMFs and currents and must pass the SI physical checker. No loaded reference enters the LinIVR builder. Limits receive a recorded factor-two current margin for this accuracy panel. The multiwinding case has coupled non-star leakage, non-unity taps, delta excitation and four windings.\n")
        println(io,"| Transformer | Accepted / cases | Maximum conductor phasor error V | Maximum device power mismatch VA |")
        println(io,"|:--|--:|--:|--:|")
        for kind in unique(r["kind"] for r in transformer_rows)
            rows=filter(r->r["kind"]==kind,transformer_rows)
            accepted=filter(r->get(r,"status","")=="OPTIMAL",rows)
            error=maximum((r["max_conductor_phasor_error_V"] for r in accepted);init=0.)
            mismatch=maximum((r["diagnostics"][:max_device_power_mismatch_VA] for r in accepted);init=0.)
            println(io,"| $kind | $(length(accepted)) / $(length(rows)) | $(round(error;digits=5)) | $(round(mismatch;digits=5)) |")
        end
        println(io,"\nAll listed successful references pass independent physical validation; the approximate candidates still have nonzero device-power residuals. Construction/solution success is coverage evidence, not a claim of AC exactness or an optimality certificate. Timings are single warmed observations with possible additional compilation.\n")
        println(io,"| Device case | LinIVR | BMOPFTools OPF | Fixed-dispatch PF |")
        println(io,"|:--|:--|:--|:--|")
        for r in device_rows
            println(io,"| $(r["name"]) | $(get(r,"linear_status","error")) | $(get(r,"ac_opf_status","—")) | $(get(r,"replay_status","—")) |")
        end
        println(io,"\nDelta generators and three-leg inverters use coil P/Q and coil current limits, matching this BMOPFTools revision. Unequal coil powers distinguish this from the existing SDP conductor-power convention. Each inverter is tested at fixed PCC voltage and at the end of an unbalanced two-segment four-wire feeder. These comparisons verify PCC behavior only: this BMOPFTools implementation does not stamp the filter circuit used by FormulationLab. Filter losses and internal powers are checked separately in the SI regression suite. Internal-power budgets are affine, and actual internal powers can exceed them by omitted second-order filter losses.\n")
        for r in vcat(transformer_rows,device_rows)
            haskey(r,"error") && println(io,"- $(get(r,"kind",get(r,"name","case"))): $(replace(r["error"],'\n'=>' '))")
        end
        println(io,"\nRaw observations: [$(basename(output))]($(basename(output))). Run `examples/benchmark_linivr_coverage.jl` using the optional integration environment. Static controls, grid-forming internal-voltage regulation, general voltage-dependent loads, DC networks and time series remain unsupported.")
    end
    println("Saved ",output)
end
if abspath(PROGRAM_FILE)==@__FILE__
    run_linivr_coverage(isempty(ARGS) ? joinpath(@__DIR__,"results","linivr_coverage_2026-09-30.json") : ARGS[1])
end
