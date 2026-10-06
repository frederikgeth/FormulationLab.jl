# Optional physical-correspondence study. Every status is retained; no timings.
using FormulationLab,JuMP,Ipopt,JSON3,SHA
import BMOPFTools
include("../ivr_nwinding_limit_fixtures.jl")
include("ivr_fixed_q_hook.jl")
length(ARGS)==1 || error("Supply a JSON report path")
output=abspath(only(ARGS));folder=joinpath(dirname(output),"EXPORTS");mkpath(folder)
save(path,x)=open(io->JSON3.write(io,x),path,"w")
settings=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,
    bound_relax_factor=0.,max_iter=500,nlp_scaling_method="gradient-based")
root=dirname(dirname(pathof(BMOPFTools)))
sources=("src/io/nwinding.jl","src/io/parse_bmopf.jl","ext/BMOPFOpfExt/nwinding.jl","ext/BMOPFOpfExt/per_unit.jl","ext/BMOPFOpfExt/generator.jl")
provenance=(;reference_revision=readchomp(`git -C $root rev-parse HEAD`),
    reference_dirty=!isempty(readchomp(`git -C $root status --porcelain`)),
    reference_source_sha256=Dict(p=>bytes2hex(sha256(read(joinpath(root,p)))) for p in sources),
    runner_sha256=bytes2hex(sha256(read(@__FILE__))))
native=Any[];references=Any[]
report()=(;provenance,settings,native,references,
    note="Four-winding non-star SI correspondence. Both packages per unit; reference paired-Q controls and exact fixed-Q hook kept separate. No isolated timings or global optimality claims. All failed rows retained.")
function assess(net,point,full)
    eq=_nwinding_nonstar_equations(net,point)
    Dict{String,Any}("physical_passed"=>physical_residuals(net,point;delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed,
        "full_membership_passed"=>ivr_nlp_point_report(full,point).passed,
        "ampere_turn_A"=>eq.ampere_turn_A,"leakage_V"=>eq.leakage_V,"loss_identity_VA"=>eq.loss_identity_VA,
        "independent_equations_passed"=>eq.ampere_turn_A<1e-6 && eq.leakage_V<1e-6 && eq.loss_identity_VA<1e-3)
end
for (connection,roll) in ((:YYYY,1),(:YDYY,1),(:YDYY,-1),(:YYYD,1),(:YYYD,-1),(:DYYY,1),(:DYYY,-1)),
    reverse in (false,true),bounded in (false,true),excitation in (false,true),sb in (1e3,1e5)
    net=_nwinding_nonstar_case(;connection,roll,reverse,bounded,excitation);original=deepcopy(net)
    stem=join((connection,roll,reverse,bounded,excitation,sb),"__")
    save(joinpath(folder,stem*".input.json"),net)
    full=build_opf(net,IVRNLP(;s_base=sb,objective_scale=1.,transformer_nameplate=:bmopftools))
    candidates=Any[];anchor=nothing;anchor_objective=nothing
    for lifting in (:off,:powers,:bounded_observations)
        row=Dict{String,Any}("case"=>stem,"lifting"=>lifting,"accepted"=>false)
        try
            opts=_nwinding_nonstar_options(sb,lifting);b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
            r=solve_ivr_nlp_opf(b;solver_options=settings);row["status"]=string(r.solve.termination_status)
            row["objective"]=isfinite(r.objective) ? r.objective : nothing
            if r.solve.optimal
                d=result_dict(b,r);point=_nwinding_connection_point(net,d);merge!(row,assess(net,point,full))
                row["own_membership_passed"]=ivr_nlp_point_report(b,point).passed
                if anchor===nothing;anchor=point;anchor_objective=r.objective;end
                row["reverse_passed"]=ivr_nlp_point_report(b,anchor).passed
                row["objective_agrees"]=isapprox(r.objective,anchor_objective;atol=1e-8,rtol=1e-7)
                row["bound_rejections"]=Bool[]
                if bounded
                    for k in (2,4)
                        tight=deepcopy(net);tight["transformer"]["n_winding"]["tx"]["windings"][k]["s_max"]*=.9
                        push!(row["bound_rejections"],!physical_residuals(tight,r).passed && !ivr_nlp_point_report(build_opf(tight,IVRNLP(opts)),point).passed)
                    end
                end
                changed=deepcopy(net);changed["transformer"]["n_winding"]["tx"]["x_sc"]["3_4"]-=.02
                row["pair_perturbation_rejected"]=!physical_residuals(changed,r).passed && !ivr_nlp_point_report(build_opf(changed,IVRNLP(opts)),point).passed
                io=IOBuffer();write_result(d,io);seekstart(io);row["reader_roundtrip"]=isequal(BMOPFTools.read_result(io),d)
                row["result_file"]=joinpath("EXPORTS",stem*"__$(lifting).native.json")
                open(io->write_result(d,io),joinpath(dirname(output),row["result_file"]),"w")
                row["accepted"]=all(row[k] for k in ("physical_passed","full_membership_passed","independent_equations_passed",
                    "own_membership_passed","reverse_passed","objective_agrees","pair_perturbation_rejected","reader_roundtrip")) && all(row["bound_rejections"])
                push!(candidates,(;b,r,d,valid=row["accepted"]))
            end
        catch err
            err isa InterruptException && rethrow();row["error"]=sprint(showerror,err)
        end
        push!(native,row);save(output,report())
        println(stem," native ",lifting," accepted=",row["accepted"]," ",get(row,"error",""));flush(stdout)
    end
    for representation in (:pairs,:equality)
        row=Dict{String,Any}("case"=>stem,"representation"=>representation,"accepted"=>false)
        try
            hook=ctx->begin
                row["replaced_pairs"]=representation==:equality ? _fixed_q_equalities!(ctx) : 0
                @assert row["replaced_pairs"]==(representation==:equality ? 6 : 0)
            end
            ref=BMOPFTools.solve_opf(net;optimizer=Ipopt.Optimizer,per_unit=true,s_base=sb,
                solver_options=Tuple(string(k)=>v for (k,v) in pairs(settings)),model_hook! = hook)
            row["result_file"]=joinpath("EXPORTS",stem*"__$(representation).reference.json")
            save(joinpath(dirname(output),row["result_file"]),ref)
            row["status"]=ref["termination_status"];row["objective"]=ref["objective"]
            point=_nwinding_connection_point(net,ref);merge!(row,assess(net,point,full))
            row["comparisons"]=[(;lifting=string(c.b.options.lifting),native_valid=c.valid,
                membership=ivr_nlp_point_report(c.b,point).passed,objective_gap=c.r.objective-ref["objective"],
                objective_agrees=isapprox(c.r.objective,ref["objective"];atol=1e-7,rtol=1e-6),
                currents_agree=all(isapprox(complex(x["cr"],x["ci"]),complex(ref["transformer"]["tx"][w][k]["cr"],ref["transformer"]["tx"][w][k]["ci"]);atol=2e-5,rtol=1e-6)
                    for w in ("w1","w2","w3","w4") for (k,x) in c.d["transformer"]["tx"][w])) for c in candidates]
            row["accepted"]=row["status"] in ("LOCALLY_SOLVED","OPTIMAL") && row["physical_passed"] && row["full_membership_passed"] &&
                row["independent_equations_passed"] && length(candidates)==3 && all(c.native_valid && c.membership && c.objective_agrees && c.currents_agree for c in row["comparisons"])
        catch err
            err isa InterruptException && rethrow();row["error"]=sprint(showerror,err)
        end
        push!(references,row);save(output,report())
        println(stem," reference ",representation," accepted=",row["accepted"]," ",get(row,"error",""));flush(stdout)
    end
    @assert net==original
end
