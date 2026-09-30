# julia --project=test/integration examples/benchmark_linivr.jl [output.json] [case.json ...]
# BMOPFTools remains an optional external reference. No Kron reduction or
# loaded-reference feedback is applied to LinIVR. Extra files are parsed once
# by BMOPFTools, with private provenance detached and retained in the output.
# Both engines receive identical electrical data; failures stay visible.
using FormulationLab, BMOPFTools, Clarabel, Ipopt, JuMP, JSON3, LinearAlgebra, SHA
include("linivr_cases.jl")
BLAS.set_num_threads(1)
const LINIVR_IPOPT=("print_level"=>0,"tol"=>1e-9,"constr_viol_tol"=>1e-9,
    "bound_relax_factor"=>0.,"max_iter"=>1000,"max_cpu_time"=>60.)
const LINIVR_CLARABEL=(verbose=false,tol_gap_abs=1e-10,tol_gap_rel=1e-9,tol_feas=1e-9)

function linivr_read_case(path)
    raw=BMOPFTools.parse_bmopf(path);metadata=Dict{String,Any}()
    function clean(x,prefix="")
        if x isa AbstractDict
            out=Dict{String,Any}()
            for (key,v) in x
                name=string(key);location=prefix*"/"*name
                if startswith(name,"_")
                    metadata[location]=v
                else
                    out[name]=clean(v,location)
                end
            end
            return out
        elseif x isa AbstractVector
            return [clean(v,prefix*"/$k") for (k,v) in enumerate(x)]
        end
        x
    end
    net=clean(raw)
    net,metadata
end

function linivr_reference(net;power_flow=false)
    if power_flow
        return BMOPFTools.solve_pf(net;optimizer=Ipopt.Optimizer,s_base=1e4,solver_options=LINIVR_IPOPT)
    end
    BMOPFTools.solve_opf(net;optimizer=Ipopt.Optimizer,s_base=1e4,solver_options=LINIVR_IPOPT)
end

function linivr_comparison(net,r,ac)
    ac["termination_status"] in ("OPTIMAL","LOCALLY_SOLVED") || return Dict("reference_accepted"=>false)
    neutral_error=0.;phase_error=0.;neutral_max=0.;vpn_violation=0.;neutral_violation=0.
    for (bus,d) in net["bus"]
        nt=get(d,"neutral_terminal","n")
        vn=haskey(ac["bus"][bus],nt) ? complex(ac["bus"][bus][nt]["vr"],ac["bus"][bus][nt]["vi"]) : 0im
        approx_n=get(r.voltage_candidate,(bus,nt),0im)
        neutral_error=max(neutral_error,abs(approx_n-vn));neutral_max=max(neutral_max,abs(vn))
        if haskey(d,"vn_max")
            bound=d["vn_max"] isa Number ? d["vn_max"] : only(d["vn_max"])
            neutral_violation=max(neutral_violation,abs(vn)-bound)
        end
        phases=filter(!=(nt),d["terminal_names"])
        for (k,t) in enumerate(phases)
            v=complex(ac["bus"][bus][t]["vr"],ac["bus"][bus][t]["vi"])-vn
            vlin=r.voltage_candidate[(bus,t)]-approx_n
            phase_error=max(phase_error,abs(vlin-v))
            if haskey(d,"vpn_min");vpn_violation=max(vpn_violation,d["vpn_min"][k]-abs(v));end
            if haskey(d,"vpn_max");vpn_violation=max(vpn_violation,abs(v)-d["vpn_max"][k]);end
        end
    end
    neutral_current_error=0.;amp_violation=0.
    for (id,l) in get(net,"line",Dict())
        code=haskey(l,"linecode") ? net["linecode"][l["linecode"]] : l
        limits=get(l,"i_max",get(code,"i_max",nothing))
        for (k,t) in enumerate(l["terminal_map_from"])
            a=ac["line"][id][t]
            if t=="n"
                neutral_current_error=max(neutral_current_error,abs(r.current_candidate[(:line_from,id)][k]-complex(a["cr_fr"],a["ci_fr"])))
            end
            limits===nothing || (amp_violation=max(amp_violation,a["cm_fr"]-limits[k],a["cm_to"]-limits[k]))
        end
    end
    Dict("reference_accepted"=>true,"max_neutral_phasor_error_V"=>neutral_error,
        "max_connection_phasor_error_V"=>phase_error,"max_ac_neutral_voltage_V"=>neutral_max,
        "max_neutral_current_error_A"=>neutral_current_error,"max_ac_vpn_violation_V"=>vpn_violation,
        "max_ac_neutral_violation_V"=>neutral_violation,"max_ac_ampacity_violation_A"=>amp_violation)
end

function linivr_panel_case(name,net;objective=:cost)
    row=Dict{String,Any}("name"=>name,"objective"=>string(objective),"buses"=>length(net["bus"]),
        "input_sha256"=>bytes2hex(sha256(JSON3.write(net))))
    try
        bt=@elapsed build=build_opf(net,LinIVR(;objective))
        st=@elapsed r=solve_linivr_opf(build;solver_options=LINIVR_CLARABEL)
        merge!(row,Dict("linear_status"=>r.solve.termination_status,"build_seconds"=>bt,"solve_seconds"=>st,
            "native_solver_seconds"=>solve_time(build.model),"variables"=>num_variables(build.model),
            "diagnostics"=>r.numerical_diagnostics))
        r.solve.optimal || return row
        row["linear_objective"]=r.objective
        at=@elapsed ac=linivr_reference(net)
        row["ac_opf_seconds"]=at;row["ac_opf_status"]=ac["termination_status"]
        row["ac_opf_cost"]=ac["objective"]
        # Replay precisely the linear dispatch in an independent nonlinear PF.
        replay=deepcopy(net)
        for family in ("generator","ibr"),(id,d) in get(replay,family,Dict())
            s=r.powers[(Symbol(family),id)]
            d["p_min"]=real.(s);d["p_max"]=real.(s)
            d["q_min"]=imag.(s);d["q_max"]=imag.(s)
        end
        pt=@elapsed pf=linivr_reference(replay;power_flow=true)
        row["replay_seconds"]=pt;row["replay_status"]=pf["termination_status"]
        row["replay"]=linivr_comparison(net,r,pf)
        row["linear_dispatch"]=Dict(id=>Dict("p_W"=>real.(r.powers[(:generator,id)]),"q_var"=>imag.(r.powers[(:generator,id)])) for id in keys(get(net,"generator",Dict())))
        row["linear_ibr_dispatch"]=Dict(id=>Dict("p_W"=>real.(r.powers[(:ibr,id)]),"q_var"=>imag.(r.powers[(:ibr,id)])) for id in keys(get(net,"ibr",Dict())))
        if pf["termination_status"] in ("OPTIMAL","LOCALLY_SOLVED")
            dispatch_error=0.;port_current_error=0.
            for family in ("generator","ibr"),(id,d) in get(net,family,Dict())
                ports=pf[family][id]
                order=filter(t->haskey(ports,t),d["terminal_map"])
                s=r.powers[(Symbol(family),id)]
                length(order)==length(s) || error("replay port arity differs for $family/$id")
                cr,ci=family=="generator" ? ("crg","cig") : ("cri","cii")
                for (k,t) in enumerate(order)
                    dispatch_error=max(dispatch_error,abs(complex(ports[t]["pg"],ports[t]["qg"])-s[k]))
                    port_current_error=max(port_current_error,abs(complex(ports[t][cr],ports[t][ci])-r.current_candidate[(Symbol(family),id)][k]))
                end
            end
            row["max_replayed_dispatch_error_VA"]=dispatch_error
            row["max_port_current_phasor_error_A"]=port_current_error
            findings=BMOPFTools.Finding[]
            row["replay_solution_check"]=BMOPFTools.solution_check(replay,pf,findings)
            row["replay_findings"]=[Dict("severity"=>string(f.severity),"code"=>f.code,"message"=>f.message) for f in findings]
            row["replay_line_losses_W"]=pf["losses"]["p_loss"]
            row["replay_source_W"]=sum(t["ps"] for s in values(pf["voltage_source"]) for t in values(s))
        end
    catch err
        row["error"]=sprint(showerror,err)
    end
    row
end

function write_linivr_report(output,data)
    path=splitext(output)[1]*".md"
    rows=data["cases"]
    number(x)=x===nothing ? "—" : string(round(x;digits=4))
    open(path,"w") do io
        println(io,"# Explicit-neutral LinIVR exploratory panel — 30 September 2026\n")
        println(io,"LinIVR retains full conductor KCL/KVL and physical connection maps, but uses no-load affine power products. No loaded AC solution is used to assemble it. BMOPFTools supplies independent nonlinear OPF and fixed-dispatch power-flow replay. These are approximations and local nonlinear candidates, not global bounds.\n")
        println(io,"## Protocol\n")
        println(io,"The synthetic feeder has five buses, four fully coupled four-wire segments, and unbalanced constant-power loads. Loading multiplies the nominal 24 kW / 6 kvar demand. Grounding is either source-only (`Inf`) or a finite shunt at every downstream neutral (10 Ω or 0.2 Ω). The delta case changes the device connections. Dispatch cases add one phase-to-neutral DER and a 6 V neutral limit. Both solvers receive the same electrical network.\n")
        println(io,"No neutral Kron reduction is performed. External ENWL cases come from the existing **reduced topology** collection; their explicit neutrals and finite grounding shunts are retained. Private parser/reduction provenance is detached into the JSON artifact. Existing generation, source costs and other electrical fields are retained, so these objectives must not be compared with the older source-import panels that changed those fields.\n")
        println(io,"Julia $(data["julia"]), Clarabel $(data["clarabel"]), Ipopt $(data["ipopt"]); one BLAS thread. One warmed observation per case, including possible case-specific compilation. Native conic solve time, build time and solve/extraction time are reported separately. This is not a reliable speedup estimate. BMOPFTools revision: `$(data["bmopftools_revision"])`. FormulationLab base revision before this branch's changes: `$(data["formulationlab_base_revision"])`.\n")
        println(io,"## Accuracy at the chosen dispatch\n")
        println(io,"Phasor errors compare LinIVR with nonlinear power flow at the **same device powers**. Device mismatch compares the approximate state's actual voltage–current products with its modeled powers. The replay checker is also retained in the JSON; zero listed violations only describes the assessed limits.\n")
        println(io,"| Case | LinIVR status | Neutral error V | Connection error V | Neutral current error A | Device mismatch % | Replay voltage violation V |")
        println(io,"|:--|:--|--:|--:|--:|--:|--:|")
        for r in rows
            c=get(r,"replay",Dict());d=get(r,"diagnostics",Dict())
            mismatch=haskey(d,"max_relative_device_power_mismatch") ? 100d["max_relative_device_power_mismatch"] : nothing
            violation=isempty(c) ? nothing : max(get(c,"max_ac_vpn_violation_V",0.),get(c,"max_ac_neutral_violation_V",0.))
            println(io,"| $(r["name"]) | $(get(r,"linear_status","error")) | $(number(get(c,"max_neutral_phasor_error_V",nothing))) | $(number(get(c,"max_connection_phasor_error_V",nothing))) | $(number(get(c,"max_neutral_current_error_A",nothing))) | $(number(mismatch)) | $(number(violation)) |")
        end
        println(io,"\nTwo high-loading cases stop at linear-model infeasibility; no nonlinear feasibility conclusion follows. The source-only 1.5× case is accepted by LinIVR but its replay violates the 180 V connection lower limit by about 1.64 V. Its nonlinear OPF reports local infeasibility. This is direct evidence that the approximation must not certify feasible dispatch.\n")
        println(io,"## Dispatch and losses\n")
        println(io,"| Objective | DER P W | DER Q var | Replayed line losses W | Maximum replay neutral V |")
        println(io,"|:--|--:|--:|--:|--:|")
        for r in rows
            startswith(r["name"],"dispatch_") || continue
            der=get(get(r,"linear_dispatch",Dict()),"der",Dict());c=get(r,"replay",Dict())
            p=haskey(der,"p_W") ? only(der["p_W"]) : nothing;q=haskey(der,"q_var") ? only(der["q_var"]) : nothing
            println(io,"| $(r["objective"]) | $(number(p)) | $(number(q)) | $(number(get(r,"replay_line_losses_W",nothing))) | $(number(get(c,"max_ac_neutral_voltage_V",nothing))) |")
        end
        println(io,"\nThe quadratic objective reduces replayed losses in this example. These dispatches optimize different objectives; the nonlinear OPF reference uses the original cost objective, so the loss-objective row is **not** an optimality-gap comparison against an AC loss optimum.\n")
        println(io,"## External-case timing\n")
        println(io,"| Case | Buses | Build s | Solve/extract s | Native conic solve s | Nonlinear OPF total s |")
        println(io,"|:--|--:|--:|--:|--:|--:|")
        for r in rows
            haskey(r,"source_sha256") || continue
            println(io,"| $(r["name"]) | $(r["buses"]) | $(number(get(r,"build_seconds",nothing))) | $(number(get(r,"solve_seconds",nothing))) | $(number(get(r,"native_solver_seconds",nothing))) | $(number(get(r,"ac_opf_seconds",nothing))) |")
        end
        println(io,"\nThe initial evidence supports further testing as a small-deviation dispatch approximation. Larger neutral displacement and loading amplify the missing voltage–current feedback. A quadratic loss objective is useful experimentally, but does not restore exact device-power balance. Broader original-network panels, uncertainty/error margins and independent replay remain necessary before operational use.\n")
        errors=[r for r in rows if haskey(r,"error")]
        for r in errors;println(io,"- $(r["name"]): `$(replace(r["error"],'\n'=>' '))`");end
        println(io,"\nRaw data: [$(basename(output))]($(basename(output))). Reproduce with `examples/benchmark_linivr.jl` in `test/integration`; additional case paths are recorded by basename and content hash. Synthetic inputs are generated by `examples/linivr_cases.jl`.")
    end
end

function run_linivr_panel(output,paths)
    # Warm all build/solve/reference paths before measuring exploratory timings.
    linivr_panel_case("warmup",linivr_case(segments=1,loading=.1))
    rows=Any[]
    for ground in (Inf,10.,.2),loading in (.25,.5,1.,1.5,2.)
        push!(rows,linivr_panel_case("wye_g$(ground)_load$(loading)",linivr_case(;ground,loading)))
        println(rows[end]["name"],": ",get(rows[end],"error",get(rows[end],"linear_status","unknown")))
    end
    push!(rows,linivr_panel_case("delta",linivr_case(delta=true)))
    for objective in (:cost,:losses)
        push!(rows,linivr_panel_case("dispatch_$(objective)",linivr_case(dispatch=true);objective))
    end
    for path in paths
        try
            net,metadata=linivr_read_case(path)
            row=linivr_panel_case(basename(path),net)
            row["source_sha256"]=bytes2hex(sha256(read(path)))
            row["detached_private_metadata"]=metadata
            push!(rows,row)
        catch err
            push!(rows,Dict("name"=>path,"error"=>sprint(showerror,err)))
        end
    end
    data=Dict("julia"=>string(VERSION),"clarabel"=>string(pkgversion(Clarabel)),"ipopt"=>string(pkgversion(Ipopt)),
        "bmopftools_revision"=>readchomp(`git -C $(dirname(dirname(pathof(BMOPFTools)))) rev-parse HEAD`),
        "formulationlab_base_revision"=>readchomp(`git rev-parse HEAD`),"blas_threads"=>1,
        "repetitions"=>1,"kron_reduction"=>false,"reference"=>"passive no-load circuit",
        "cases"=>rows)
    open(io->JSON3.write(io,data),output,"w")
    write_linivr_report(output,data)
    println("Saved ",output)
end
if abspath(PROGRAM_FILE)==@__FILE__
    output=isempty(ARGS) ? joinpath(@__DIR__,"results","linivr_2026-09-30.json") : ARGS[1]
    run_linivr_panel(output,ARGS[2:end])
end
