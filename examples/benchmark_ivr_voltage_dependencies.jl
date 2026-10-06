"""Power-cost and voltage-dependency diagnostics; no isolated timing claims."""
module IVRVoltageDependencyStudy
using FormulationLab,JuMP,Ipopt,JSON3,SHA
include("benchmark_ivr_mixed_devices.jl")
const M=IVRMixedDeviceStudy

function scenario(;conductors=2,treatment=:single)
    conductors in (2,4) || throw(ArgumentError("use two or four conductors"))
    treatment in (:single,:duplicate,:implied) || throw(ArgumentError("unknown declaration treatment"))
    net=M.P.ivr_compiler_case(;conductors,segments=1)
    n=conductors==2 ? 1 : 3;tm=net["bus"]["b1"]["terminal_names"]
    net["bus"]["b1"]["perfectly_grounded_terminals"]=["n"]
    net["bus"]["b1"]["vpn_min"]=fill(230.,n);net["bus"]["b1"]["vpn_max"]=fill(230.,n)
    if treatment==:duplicate
        net["bus"]["b1"]["v_min"]=fill(230.,n);net["bus"]["b1"]["v_max"]=fill(230.,n)
    end
    if treatment==:implied
        empty!(net["line"])
        net["switch"]=Dict("s"=>Dict("bus_from"=>"b0","bus_to"=>"b1",
            "terminal_map_from"=>copy(tm),"terminal_map_to"=>copy(tm),"open_switch"=>false))
    else
        net["generator"]=Dict("g"=>Dict("bus"=>"b1","terminal_map"=>copy(tm),
            "configuration"=>conductors==2 ? "SINGLE_PHASE" : "WYE",
            "p_min"=>zeros(n),"p_max"=>fill(5000.,n),"q_min"=>fill(-2000.,n),
            "q_max"=>fill(2000.,n),"s_max"=>fill(6000.,n)))
    end
    net
end

function terms(net,objective)
    objective in (:linear_cost,:quadratic_cost) || throw(ArgumentError("unknown power objective"))
    source=[(:voltage_source,id,k) for (id,d) in net["voltage_source"] for k in eachindex(d["terminal_map"]) if d["terminal_map"][k]!="n"]
    dispatch=[(:generator,id,k) for (id,d) in get(net,"generator",Dict()) for k in eachindex(d["p_min"])]
    ts=[IVRPowerTerm(channels=source,linear=.25/1000);
        [IVRPowerTerm(channels=[c],linear=.10/1000) for c in dispatch]]
    if objective==:quadratic_cost
        append!(ts,[IVRPowerTerm(channels=[c],quadratic=.02/1e6) for c in dispatch])
        append!(ts,[IVRPowerTerm(channels=[c],quantity=:q,quadratic=.002/1e6) for c in dispatch])
    end
    ts
end

function profiles(net,objective;scaling="none")
    filter(p->p.name in ("full_powers","reduced_powers","blocks_signed_reuse"),
        M.profiles_for_terms(net,terms(net,objective);nlp_scaling_method=scaling))
end
options(p,mode,sb)=IVRNLPOptions(;(k=>(k==:coincident_voltage_bounds ? mode : k==:s_base ? sb : deepcopy(getfield(p.options,k))) for k in fieldnames(IVRNLPOptions))...)

function run(output)
    folder=joinpath(dirname(abspath(output)),"EXPORTS");mkpath(folder);rows=Any[]
    for n in (2,4),treatment in (:single,:duplicate,:implied),objective in (:linear_cost,:quadratic_cost),
        sb in (1e3,1e5),scaling in ("none","gradient-based")
        net=scenario(;conductors=n,treatment);original=deepcopy(net);ps=profiles(net,objective;scaling)
        full=build_opf(net,IVRNLP(objective=:power,power_terms=terms(net,objective),objective_scale=1.))
        stem=join((n,treatment,objective,sb,scaling),"__")
        open(io->JSON3.write(io,net),joinpath(folder,stem*".input.json"),"w")
        anchor=nothing;anchor_objective=nothing
        for mode in (:guarded_equality,:equality,:separate),p in ps
            row=Dict{String,Any}("case"=>stem,"conductors"=>n,"treatment"=>treatment,"objective_kind"=>objective,
                "s_base"=>sb,"scaling"=>scaling,"mode"=>mode,"profile"=>p.name,"accepted"=>false)
            try
                opts=options(p,mode,sb);b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
                r=solve_ivr_nlp_opf(b;solver_options=merge(M.P.STRICT,p.solver_options))
                row["status"]=string(r.solve.termination_status)
                row["objective"]=isfinite(r.objective) ? r.objective : nothing
                row["actions"]=[string(x.action) for x in b.numerical_diagnostics[:coincident_voltage_bound_report]]
                row["circuit_fixed_derivations"]=length(b.numerical_diagnostics[:voltage_fixed_dependencies])
                if r.solve.optimal
                    point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
                    row["physical_passed"]=physical_residuals(net,r).passed
                    row["own_full_passed"]=ivr_nlp_point_report(b,point).passed && ivr_nlp_point_report(full,point).passed
                    if mode==:guarded_equality && p.name=="full_powers" && row["physical_passed"] && row["own_full_passed"]
                        anchor=point;anchor_objective=r.objective
                    end
                    row["reverse_passed"]=anchor!==nothing && ivr_nlp_point_report(b,anchor).passed
                    row["objective_gap"]=anchor===nothing ? nothing : r.objective-anchor_objective
                    row["objective_agrees"]=anchor!==nothing && isapprox(r.objective,anchor_objective;atol=1e-7,rtol=1e-6)
                    row["shift_rejections"]=Bool[]
                    for factor in (.999,1.001)
                        shifted=deepcopy(net)
                        for key in ("v_min","v_max","vpn_min","vpn_max")
                            haskey(shifted["bus"]["b1"],key) && (shifted["bus"]["b1"][key].*=factor)
                        end
                        push!(row["shift_rejections"],!physical_residuals(shifted,r).passed && !ivr_nlp_point_report(build_opf(shifted,IVRNLP(opts)),point).passed)
                    end
                    d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
                    row["reader_roundtrip"]=isequal(read_result(io),d)
                    row["result_file"]=joinpath("EXPORTS",stem*"__$(mode)__$(p.name).json")
                    open(io->write_result(d,io),joinpath(dirname(abspath(output)),row["result_file"]),"w")
                    row["accepted"]=all(row[k] for k in ("physical_passed","own_full_passed","reverse_passed","objective_agrees","reader_roundtrip")) && all(row["shift_rejections"])
                end
                @assert net==original
            catch err
                err isa InterruptException && rethrow()
                row["accepted"]=false;row["error"]=sprint(showerror,err)
            end
            push!(rows,row)
            open(io->JSON3.write(io,(;source_sha256=bytes2hex(sha256(read(@__FILE__))),cases=rows,
                note="No timing claims. Guarded full equality supplies each cell's anchor. All failed statuses retained; exports only for strict solves.")),output,"w")
            println(stem," ",mode," ",p.name," ",get(row,"status","ERROR")," accepted=",row["accepted"]," ",get(row,"error",""));flush(stdout)
        end
    end
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("Supply a JSON report path")
    IVRVoltageDependencyStudy.run(only(ARGS))
end
