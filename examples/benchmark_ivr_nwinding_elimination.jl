"""Diagnostic panel for exact multiwinding current elimination; no timing claims."""
module IVRNWindingEliminationStudy
using FormulationLab,JuMP,Ipopt,JSON3,SHA
include("../test/ivr_nwinding_limit_fixtures.jl")
const SETTINGS=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,
    bound_relax_factor=0.,max_iter=500,nlp_scaling_method="gradient-based")
function run(output)
    output=abspath(output);folder=joinpath(dirname(output),"EXPORTS");mkpath(folder);rows=Any[]
    save(path,x)=open(io->JSON3.write(io,x),path,"w")
    for (connection,roll) in ((:YYYY,1),(:YDYY,1),(:YDYY,-1),(:YYYD,1),(:YYYD,-1),(:DYYY,1),(:DYYY,-1)),
        reverse in (false,true),bounded in (false,true),excitation in (false,true),sb in (1e3,1e5)
        net=_nwinding_nonstar_case(;connection,roll,reverse,bounded,excitation);original=deepcopy(net)
        stem=join((connection,roll,reverse,bounded,excitation,sb),"__")
        save(joinpath(folder,stem*".input.json"),net)
        full=build_opf(net,IVRNLP(;s_base=sb,objective_scale=1.,transformer_nameplate=:bmopftools))
        anchor=nothing;anchor_objective=nothing
        for mode in (:transformer_currents,:all_transformer_currents),lifting in (:off,:powers,:bounded_observations)
            row=Dict{String,Any}("case"=>stem,"mode"=>mode,"lifting"=>lifting,"accepted"=>false)
            try
                old=_nwinding_nonstar_options(sb,lifting)
                opts=IVRNLPOptions(;(k=>(k==:device_elimination ? mode : getfield(old,k)) for k in fieldnames(IVRNLPOptions))...)
                b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
                row["device_report"]=b.numerical_diagnostics[:device_elimination_report]
                row["solver_state_dimension"]=b.numerical_diagnostics[:solver_state_dimension]
                row["model_variables"]=num_variables(b.model)
                row["anchor_membership"]=anchor===nothing ? nothing : ivr_nlp_point_report(b,anchor).passed
                r=solve_ivr_nlp_opf(b;solver_options=SETTINGS)
                row["status"]=string(r.solve.termination_status)
                row["objective"]=isfinite(r.objective) ? r.objective : nothing
                if r.solve.optimal
                    point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
                    row["physical_passed"]=physical_residuals(net,r).passed
                    row["own_full_passed"]=ivr_nlp_point_report(b,point).passed && ivr_nlp_point_report(full,point).passed
                    if anchor===nothing && row["physical_passed"] && row["own_full_passed"]
                        anchor=point;anchor_objective=r.objective;row["anchor_membership"]=true
                    end
                    row["objective_gap"]=anchor===nothing ? nothing : r.objective-anchor_objective
                    row["objective_agrees"]=anchor!==nothing && isapprox(r.objective,anchor_objective;atol=1e-7,rtol=1e-6)
                    eq=_nwinding_nonstar_equations(net,point)
                    row["independent_equations"]=(;eq.ampere_turn_A,eq.leakage_V,eq.loss_identity_VA)
                    row["equations_passed"]=eq.ampere_turn_A<1e-6 && eq.leakage_V<1e-6 && eq.loss_identity_VA<1e-3
                    row["bound_rejections"]=Bool[]
                    if bounded
                        for k in (2,4)
                            tight=deepcopy(net);tight["transformer"]["n_winding"]["tx"]["windings"][k]["s_max"]*=.9
                            push!(row["bound_rejections"],!physical_residuals(tight,r).passed && !ivr_nlp_point_report(build_opf(tight,IVRNLP(opts)),point).passed)
                        end
                    end
                    changed=deepcopy(net);changed["transformer"]["n_winding"]["tx"]["x_sc"]["3_4"]-=.02
                    row["pair_rejected"]=!physical_residuals(changed,r).passed && !ivr_nlp_point_report(build_opf(changed,IVRNLP(opts)),point).passed
                    d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
                    row["reader_roundtrip"]=isequal(read_result(io),d)
                    row["result_file"]=joinpath("EXPORTS",stem*"__$(mode)__$(lifting).json")
                    open(io->write_result(d,io),joinpath(dirname(output),row["result_file"]),"w")
                    row["accepted"]=all(row[k] for k in ("physical_passed","own_full_passed","anchor_membership","objective_agrees","equations_passed","pair_rejected","reader_roundtrip")) && all(row["bound_rejections"])
                end
            catch err
                err isa InterruptException && rethrow();row["error"]=sprint(showerror,err)
            end
            @assert net==original
            push!(rows,row)
            save(output,(;source_sha256=bytes2hex(sha256(read(@__FILE__))),settings=SETTINGS,cases=rows,
                note="No timing claims. All failed statuses retained; strict endpoints exported. Failed optimizer runs still receive baseline feasible-point membership tests."))
            println(stem," ",mode," ",lifting," ",get(row,"status","ERROR")," accepted=",row["accepted"]," ",get(row,"error",""));flush(stdout)
        end
    end
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("Supply a JSON report path")
    IVRNWindingEliminationStudy.run(only(ARGS))
end
