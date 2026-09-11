# Optional environment; all optimization here is fixed SOC/power cones or Ipopt.
include("benchmark_nlp_soc.jl")

function reduction_nlp(net,sb)
    bt=@elapsed begin
        ctx=BMOPFTools.build_opf_model(net;optimizer=Ipopt.Optimizer,per_unit=true,s_base=sb)
        BMOPFTools.enforce_kcl!(ctx)
    end
    m=BMOPFTools.opf_model(ctx)
    for (k,v) in ("print_level"=>0,"tol"=>1e-8,"constr_viol_tol"=>1e-8,"bound_relax_factor"=>0.,"max_cpu_time"=>90.)
        set_optimizer_attribute(m,k,v)
    end
    st=@elapsed optimize!(m)
    result=BMOPFTools.extract_result(ctx)
    accepted=termination_status(m) in (MOI.LOCALLY_SOLVED,MOI.OPTIMAL)
    row=Dict{String,Any}("status"=>string(termination_status(m)),"build_seconds"=>bt,"solve_seconds"=>st)
    voltage=Dict{Tuple{String,String},ComplexF64}()
    if accepted
        row["source_W"]=sum(sum(t["ps"] for t in values(s)) for s in values(result["voltage_source"]))
        voltage=Dict((b,t)=>complex(x["vr"],x["vi"]) for (b,ts) in result["bus"] for (t,x) in ts)
        findings=BMOPFTools.Finding[]
        BMOPFTools.solution_check(net,result,findings)
        row["findings"]=[Dict("severity"=>string(f.severity),"code"=>f.code,"message"=>f.message) for f in findings]
    end
    row,voltage
end

function reduction_study(manifest,output)
    cases=JSON3.read(read(manifest,String),Vector{Dict{String,Any}})
    data=Dict{String,Any}("julia"=>string(VERSION),"clarabel"=>string(pkgversion(Clarabel)),"ipopt"=>string(pkgversion(Ipopt)),
        "bmopftools_revision"=>readchomp(`git -C $(dirname(dirname(pathof(BMOPFTools)))) rev-parse HEAD`),
        "formulationlab_base_revision"=>readchomp(`git rev-parse HEAD`),"blas_threads"=>1,
        "solver_tolerances"=>Dict("tol_feas"=>1e-7,"tol_gap_abs"=>1e-6,"tol_gap_rel"=>1e-7),"cases"=>Any[])
    save()=open(io->JSON3.write(io,finite(data)),output,"w")
    warm,sb,_,_=prepare_case(first(cases)["path"])
    reduction_nlp(warm,sb)
    for (strength,size) in ((:linear,32),(:linear,12),(:none,12),(:kim,12),(:none,32),(:kim,32))
        b=build_opf(prepare_network(warm;warn=false),IVRSOC(s_base=sb,objective=:source_import,strengthening=strength,clique_size=size,max_triplets=8))
        r=solve_soc_opf(b;solver_options=(verbose=false,tol_feas=1e-7,tol_gap_abs=1e-6,tol_gap_rel=1e-7))
        r.solve.publishable && reconstruct_solution(prepare_network(warm;warn=false),r;warn=false)
    end
    for c in cases
        row=copy(c);push!(data["cases"],row);row["stage"]="prepare";save()
        println("CASE ",c["name"]);flush(stdout)
        try
            net,sb,changes,_=prepare_case(c["path"])
            # A labelled derived-input probe aligns the nameplate contract.
            if get(c,"no_nameplate_caps",false)
                for table in values(get(net,"transformer",Dict())),tx in values(table);pop!(tx,"s_rating",nothing);end
                push!(changes,"remove transformer s_rating fields (derived input; BMOPFTools otherwise enforces nameplate caps)")
            end
            row["changes"]=changes;row["s_base_VA"]=sb;row["input_sha256"]=bytes2hex(sha256(read(c["path"])))
            pt=@elapsed p=prepare_network(net;warn=false)
            row["prepare_seconds"]=pt;row["reduction"]=reduction_report(p)
            row["stage"]="nlp_original";save()
            row["nlp_original"],reference=reduction_nlp(net,sb);save()
            row["stage"]="nlp_reduced";save()
            if p.network==net
                row["nlp_reduced"]=copy(row["nlp_original"])
                row["nlp_reduced"]["reused_identical_input"]=true
            else
                row["nlp_reduced"],_=reduction_nlp(p.network,sb)
            end
            row["soc"]=Any[];save()
            for (name,strength,size) in (("linear32",:linear,32),("linear12",:linear,12),("physical12",:none,12),("kim12_8",:kim,12),("physical32",:none,32),("kim32_8",:kim,32))
                get(c,"profiles",nothing)===nothing || name in c["profiles"] || continue
                GC.gc();s=Dict{String,Any}("profile"=>name);push!(row["soc"],s)
                row["stage"]="build_$name";save();println(row["stage"]);flush(stdout)
                try
                    bt=@elapsed b=build_opf(p,IVRSOC(s_base=sb,objective=:source_import,strengthening=strength,clique_size=size,max_triplets=8,voltage_recovery=Symbol(get(c,"voltage_recovery","voltage_tree"))))
                    s["build_seconds"]=bt;s["variables"]=num_variables(b.model)
                    s["cone_types"]=[string(S) for (_,S) in list_of_constraint_types(b.model)]
                    @assert all(!occursin("Semidefinite",v) for v in s["cone_types"])
                    row["stage"]="solve_$name";save();set_time_limit_sec(b.model,90.)
                    st=@elapsed r=solve_soc_opf(b;solver_options=(verbose=false,tol_feas=1e-7,tol_gap_abs=1e-6,tol_gap_rel=1e-7))
                    s["recovery"]=get(r.metadata,:recovery,:unavailable);s["solve_seconds"]=st;s["status"]=r.solve.termination_status;s["objective_W"]=r.objective
                    s["solver_bound_W"]=r.solver_objective_bound;s["psd_residual"]=r.psd_residual
                    if has_values(b.model)
                        s["raw_primal_W"]=objective_value(b.model)*b.electrical.objective_scale
                    end
                    if r.solve.publishable
                        rt=@elapsed full=reconstruct_solution(p,r;warn=false)
                        s["reconstruction_seconds"]=rt;s["boundary_current_mismatch_A"]=full.diagnostics["boundary_current_mismatch_A"]
                        ph=full.diagnostics["physical"]
                        s["physical_maxima"]=ph.maxima;s["unassessed"]=ph.unassessed
                        s["max_kcl_A"]=maximum((x.residual for x in ph.records if startswith(x.label,"kcl/"));init=0.)
                        s["max_voltage_limit_violation_V"]=maximum((x.residual for x in ph.records if startswith(x.label,"bus/") && !endswith(x.label,"finite_voltage"));init=0.)
                        s["max_line_current_limit_violation_A"]=maximum((x.residual for x in ph.records if startswith(x.label,"line/") && endswith(x.label,"i_max"));init=0.)
                        s["line_losses_W"]=sum(real(l["loss"]) for l in values(full.lines))
                        if !isempty(reference)
                            s["max_voltage_magnitude_difference_V"]=maximum(abs(abs(v)-abs(reference[k])) for (k,v) in full.point.voltage)
                            s["max_phasor_difference_V"]=maximum(abs(v-reference[k]) for (k,v) in full.point.voltage)
                            s["nlp_minus_soc_W"]=row["nlp_original"]["source_W"]-r.objective
                            s["nlp_minus_soc_percent"]=100s["nlp_minus_soc_W"]/abs(row["nlp_original"]["source_W"])
                        end
                    end
                    println(name," ",s["status"]," build=",round(bt;digits=2)," solve=",round(st;digits=2));flush(stdout)
                catch e;s["error"]=sprint(showerror,e);println(s["error"]);flush(stdout);end
                save()
            end
            row["stage"]="complete"
        catch e;row["error"]=sprint(showerror,e);row["stage"]="error";end
        save()
    end
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    reduction_study(ARGS[1],ARGS[2])
end
