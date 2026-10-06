# Optional mechanism experiment: fixed-Q pairs versus exact equality. A completed
# report may contain failed solves. No timing or default recommendation follows.
using FormulationLab,JuMP,Ipopt,JSON3,SHA
import BMOPFTools
include("../ivr_nwinding_limit_fixtures.jl")
include("ivr_fixed_q_hook.jl")
length(ARGS) in (1,2) || error("Supply a JSON report path and optional --excitation")
excitation=length(ARGS)==2
excitation && ARGS[2]!="--excitation" && error("Unknown panel")
output=abspath(first(ARGS));folder=joinpath(dirname(output),"EQUALITY_EXPORTS");mkpath(folder)
save(path,x)=open(io->JSON3.write(io,x),path,"w")
settings=(print_level=5,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,
    bound_relax_factor=0.,max_iter=500,nlp_scaling_method="gradient-based")
rows=Any[];native=Any[]
root=dirname(dirname(pathof(BMOPFTools)))
sources=("src/io/parse_bmopf.jl","ext/BMOPFOpfExt/core.jl","ext/BMOPFOpfExt/generator.jl")
report()=(;reference_revision=readchomp(`git -C $root rev-parse HEAD`),
    reference_dirty=!isempty(readchomp(`git -C $root status --porcelain`)),
    source_sha256=Dict(p=>bytes2hex(sha256(read(joinpath(root,p)))) for p in sources),
    settings,excitation,native,cases=rows,accepted=count(r->get(r,"accepted",false),rows),
    note="Exploratory exact fixed-Q equality intervention; original pairs retained. Per-unit throughout. Diagnostic multipliers are in model units. No isolated timing.")
for (connection,roll) in ((:YYY,1),(:YDY,1),(:YDY,-1),(:DYY,1),(:DYY,-1)),
    reverse in (false,true),bounded in (excitation ? (true,) : (false,true)),sb in (1e3,1e5),winding in (excitation ? (1,2,3) : (0,))
    net=excitation ? _nwinding_excitation_case(;connection,roll,reverse,bounded,winding) :
        _nwinding_connection_case(;connection,roll,reverse,bounded)
    original=deepcopy(net)
    stem=join((connection,roll,reverse,bounded,sb,winding),"__")
    save(joinpath(folder,stem*".input.json"),net)
    full=build_opf(net,IVRNLP(;s_base=sb,objective_scale=1.,transformer_nameplate=:bmopftools))
    candidates=Any[]
    for lifting in (:off,:powers,:bounded_observations)
        b=build_opf(net,IVRNLP(;s_base=sb,objective_scale=1.,transformer_nameplate=:bmopftools,
            lifting,lifted_power_base=500.,observation_sharing=:signed,
            specialization=:conductor_regions,linear_elimination=:passive_blocks,
            device_elimination=:transformer_currents,transformer_scaling=:nominal,row_scaling=:composed);optimizer=Ipopt.Optimizer)
        r=solve_ivr_nlp_opf(b;solver_options=merge(settings,(print_level=0,)))
        d=result_dict(b,r);point=_nwinding_connection_point(net,d)
        valid=r.solve.optimal && physical_residuals(net,r).passed &&
            physical_residuals(net,point;delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed &&
            ivr_nlp_point_report(full,point).passed && ivr_nlp_point_report(b,point).passed
        push!(native,(;case=stem,lifting,valid,status=string(r.solve.termination_status),objective=r.objective))
        push!(candidates,(;b,r,d,valid))
        open(io->write_result(d,io),joinpath(folder,stem*"__$(lifting).native.json"),"w")
    end
    for stopping in (:baseline,:absolute),representation in (:pairs,:equality)
        local_settings=stopping==:baseline ? settings : merge(settings,(dual_inf_tol=1e-10,compl_inf_tol=1e-10))
        label=stem*"__$(stopping)__$(representation)"
        row=Dict{String,Any}("case"=>stem,"stopping"=>stopping,"representation"=>representation,"accepted"=>false)
        println("BEGIN_DIAGNOSTIC ",label);flush(stdout)
        try
            hook=ctx->begin
                before=JuMP.num_constraints(ctx.model;count_variable_in_set_constraints=false)
                row["replaced_pairs"]=representation==:equality ? _fixed_q_equalities!(ctx) : 0
                after=JuMP.num_constraints(ctx.model;count_variable_in_set_constraints=false)
                @assert row["replaced_pairs"]==(representation==:equality ? 3 : 0)
                @assert before-after==row["replaced_pairs"]
                @assert all(!(x isa JuMP.ConstraintRef) || JuMP.is_valid(ctx.model,x) for x in values(ctx.objects))
                row["constraints_before_kcl"]=after
            end
            solution_hook=(ctx,result)->begin
                qs=[abs(JuMP.dual(BMOPFTools.opf_object(ctx,k))) for k in BMOPFTools.opf_object_keys(ctx;kind=:constraint)
                    if k.family in (:generator_q_lower,:generator_q_upper,:diagnostic_generator_q_fixed)]
                row["max_abs_q_dual"]=maximum(qs;init=0.)
                row["max_abs_row_dual"]=maximum((abs(JuMP.dual(c)) for c in JuMP.all_constraints(ctx.model;include_variable_in_set_constraints=false));init=0.)
            end
            ref=BMOPFTools.solve_opf(net;optimizer=Ipopt.Optimizer,per_unit=true,s_base=sb,
                solver_options=Tuple(string(k)=>v for (k,v) in pairs(local_settings)),
                model_hook! = hook,solution_hook! = solution_hook)
            save(joinpath(folder,label*".reference.json"),ref)
            point=_nwinding_connection_point(net,ref)
            row["status"]=ref["termination_status"];row["objective"]=ref["objective"]
            row["physical_passed"]=physical_residuals(net,point;delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed
            row["full_membership_passed"]=ivr_nlp_point_report(full,point).passed
            row["comparisons"]=[(;lifting=string(c.b.options.lifting),native_valid=c.valid,
                membership=ivr_nlp_point_report(c.b,point).passed,
                objective_gap=c.r.objective-ref["objective"],
                objective_agrees=isapprox(c.r.objective,ref["objective"];atol=1e-7,rtol=1e-6),
                currents_agree=all(isapprox(complex(x["cr"],x["ci"]),complex(ref["transformer"]["tx"][w][k]["cr"],ref["transformer"]["tx"][w][k]["ci"]);atol=2e-5,rtol=1e-6)
                    for w in ("w1","w2","w3") for (k,x) in c.d["transformer"]["tx"][w])) for c in candidates]
            row["accepted"]=row["status"] in ("LOCALLY_SOLVED","OPTIMAL") && row["physical_passed"] && row["full_membership_passed"] &&
                all(c.native_valid && c.membership && c.objective_agrees && c.currents_agree for c in row["comparisons"])
            @assert net==original
        catch err
            err isa InterruptException && rethrow()
            row["accepted"]=false;row["error"]=sprint(showerror,err)
        end
        push!(rows,row);save(output,report())
        println("END_DIAGNOSTIC ",label," accepted=",row["accepted"]," ",get(row,"error",""));flush(stdout)
    end
end
