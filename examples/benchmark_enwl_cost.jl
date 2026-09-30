# julia --project=test/integration examples/benchmark_enwl_cost.jl DIRECTORY OUTPUT [COUNT]
# COUNT=0 (default) selects every JSON file, sorted by bus count and filename.
# Costs and dispatch are evaluated in the original input units, even though all
# solver prices receive the same positive numerical scaling within each case.
include("benchmark_linivr.jl")

const COST_IPOPT=("print_level"=>0,"tol"=>1e-9,"constr_viol_tol"=>1e-9,
    "bound_relax_factor"=>0.,"max_iter"=>1500,"max_cpu_time"=>60.)
const COST_CONIC=(verbose=false,tol_gap_abs=1e-10,tol_gap_rel=1e-9,tol_feas=1e-9)
cost_accepted(r)=get(r,"status","") in ("OPTIMAL","LOCALLY_SOLVED")
cost_finite(x::AbstractDict)=Dict(string(k)=>cost_finite(v) for (k,v) in x)
cost_finite(x::AbstractVector)=map(cost_finite,x)
cost_finite(x)=x isa AbstractFloat && !isfinite(x) ? nothing : x

function cost_prepare(net;as_supplied=false)
    out=deepcopy(net);changes=Any[]
    if !as_supplied
        grid=out["generator"]["grid"]
        sid=only([id for (id,s) in out["voltage_source"] if s["bus"]==grid["bus"]])
        s=out["voltage_source"][sid]
        @assert grid["configuration"]=="WYE"
        @assert grid["terminal_map"]==vcat(s["terminal_map"],["n"])
        @assert !haskey(s,"cost")
        @assert Set(keys(grid)) ⊆ Set(["bus","terminal_map","configuration","cost","p_min","p_max","q_min","q_max"])
        for key in ("cost","p_min","p_max","q_min","q_max")
            haskey(grid,key) && (s[key]=deepcopy(grid[key]))
        end
        delete!(out["generator"],"grid")
        push!(changes,Dict("action"=>"transfer grid generator tariff and box bounds to voltage source; remove duplicate grid generator",
            "source"=>sid,"original_grid"=>grid))
    end
    price=max(maximum((maximum(abs,d["cost"]) for family in ("generator","voltage_source")
        for d in values(get(out,family,Dict())) if haskey(d,"cost"));init=0.),1e-12)
    solvernet=deepcopy(out)
    for family in ("generator","voltage_source"),d in values(get(solvernet,family,Dict()))
        haskey(d,"cost") && (d["cost"]=d["cost"]./price)
    end
    out,solvernet,changes,price
end

function cost_value(net,dispatch)
    sum((sum(d["cost"].*dispatch[family][id]["p_W"])/1000
        for family in ("generator","voltage_source") for (id,d) in get(net,family,Dict())
        if haskey(d,"cost"));init=0.)
end

function cost_voltages(net,V)
    vpn=Dict{String,Float64}();vng=Dict{String,Float64}()
    vpncomplex=Dict{String,Any}();vngcomplex=Dict{String,Any}()
    for (b,d) in net["bus"]
        n="n" in d["terminal_names"] ? V(b,"n") : 0im
        if "n" in d["terminal_names"]
            vng[b]=abs(n);vngcomplex[b]=[real(n),imag(n)]
        end
        for t in d["terminal_names"]
            t=="n" && continue
            u=V(b,t)-n;key="$b/$t"
            vpn[key]=abs(u);vpncomplex[key]=[real(u),imag(u)]
        end
    end
    Dict("vpn_V"=>vpn,"vng_V"=>vng,"vpn_complex_V"=>vpncomplex,"vng_complex_V"=>vngcomplex)
end

function cost_errors(a,b)
    result=Dict{String,Any}()
    for label in ("vpn","vng")
        x=a[label*"_V"];y=b[label*"_V"]
        @assert Set(keys(x))==Set(keys(y))
        errors=[abs(v-y[k]) for (k,v) in x]
        result[label]=Dict("count"=>length(errors),"max_abs_V"=>maximum(errors;init=0.),
            "mean_abs_V"=>sum(errors)/max(length(errors),1),"rmse_V"=>sqrt(sum(abs2,errors)/max(length(errors),1)),
            "reference_max_V"=>maximum(values(y);init=0.))
        ck=label*"_complex_V"
        if haskey(a,ck) && haskey(b,ck)
            ce=[abs(complex(v...)-complex(b[ck][k]...)) for (k,v) in a[ck]]
            result[label]["max_phasor_error_V"]=maximum(ce;init=0.)
        end
    end
    result
end

function cost_limits(net,voltage)
    maxviolation=0.;nviol=0
    for (b,d) in net["bus"],(k,t) in enumerate(filter(!=("n"),d["terminal_names"]))
        v=voltage["vpn_V"]["$b/$t"]
        lo=get(d,"vpn_min",fill(0.,length(d["terminal_names"])))
        hi=get(d,"vpn_max",fill(Inf,length(d["terminal_names"])))
        violation=max(0.,lo[k]-v,v-hi[k]);maxviolation=max(maxviolation,violation)
        nviol+=violation>1e-4
    end
    Dict("max_vpn_violation_V"=>maxviolation,"vpn_violations_over_1e-4V"=>nviol)
end

function cost_nlp(net;pf=false)
    runtime=@elapsed r=pf ? BMOPFTools.solve_pf(net;optimizer=Ipopt.Optimizer,s_base=1e4,solver_options=COST_IPOPT) :
        BMOPFTools.solve_opf(net;optimizer=Ipopt.Optimizer,s_base=1e4,solver_options=COST_IPOPT)
    row=Dict{String,Any}("status"=>r["termination_status"],"seconds"=>runtime,"scaled_solver_objective"=>r["objective"])
    cost_accepted(row) || return row
    dispatch=Dict{String,Any}()
    for family in ("generator","voltage_source")
        ds=Dict{String,Any}()
        for (id,d) in get(net,family,Dict())
            ts=filter(t->haskey(r[family][id],t),d["terminal_map"])
            pk,qk=family=="generator" ? ("pg","qg") : ("ps","qs")
            ds[id]=Dict("p_W"=>[r[family][id][t][pk] for t in ts],"q_var"=>[r[family][id][t][qk] for t in ts])
        end
        dispatch[family]=ds
    end
    row["dispatch"]=dispatch
    row["voltage"]=cost_voltages(net,(b,t)->complex(r["bus"][b][t]["vr"],r["bus"][b][t]["vi"]))
    findings=BMOPFTools.Finding[]
    row["solution_check"]=BMOPFTools.solution_check(net,r,findings)
    row["findings"]=[Dict("severity"=>string(f.severity),"code"=>f.code,"message"=>f.message) for f in findings if string(f.severity)=="ERROR"]
    row["voltage_limits"]=cost_limits(net,row["voltage"])
    row
end

function cost_linear(net,which)
    if which=="linivr"
        runtime=@elapsed r=FormulationLab.solve_opf(net,LinIVR(objective=:cost);solver_options=COST_CONIC)
        row=Dict{String,Any}("status"=>r.solve.termination_status,"seconds"=>runtime,"diagnostics"=>r.numerical_diagnostics,"scaled_solver_objective"=>r.objective)
        cost_accepted(row) || return row
        row["dispatch"]=Dict(f=>Dict(id=>Dict("p_W"=>real.(r.powers[(Symbol(f),id)]),
            "q_var"=>imag.(r.powers[(Symbol(f),id)])) for id in keys(get(net,f,Dict()))) for f in ("generator","voltage_source"))
        row["voltage"]=cost_voltages(net,(b,t)->r.voltage_candidate[(b,t)])
    else
        runtime=@elapsed r=solve_l3f_opf(net,Clarabel.Optimizer;
            options=L3FOptions(objective=:cost,reference_policy=:source_propagated,unsupported=:permissive,s_base=1e4),
            solver_options=COST_CONIC)
        row=Dict{String,Any}("status"=>r.solve.termination_status,"seconds"=>runtime,
            "scaled_solver_objective"=>r.objective,
            "findings"=>[Dict("code"=>f.code,"message"=>f.message,"evidence"=>f.evidence) for f in r.applicability.findings])
        cost_accepted(row) || return row
        row["kron_provenance"]=FormulationLab._l3f_kron_provenance(r.network)
        row["dispatch"]=Dict(f=>Dict(id=>Dict("p_W"=>d["pg"],"q_var"=>d["qg"]) for (id,d) in ds)
            for (f,ds) in (("generator",r.generators),("voltage_source",r.sources)))
        # L3F has magnitudes, not solved phase angles or neutral phasors.
        row["voltage"]=Dict("vpn_V"=>Dict("$b/$t"=>r.buses[b][t]["vm"] for (b,d) in net["bus"] for t in d["terminal_names"] if t!="n"),
            "vng_V"=>Dict(b=>0. for (b,d) in net["bus"] if "n" in d["terminal_names"]))
        row["neutral_prediction"]="no neutral state; zero is the imposed ideal-ground assumption"
    end
    row["voltage_limits"]=cost_limits(net,row["voltage"])
    row
end

function cost_capture(f)
    try f() catch err;Dict{String,Any}("error"=>sprint(showerror,err));end
end

function cost_case(path;as_supplied=false)
    parsed,metadata=linivr_read_case(path)
    net,solvernet,changes,price=cost_prepare(parsed;as_supplied)
    row=Dict{String,Any}("name"=>basename(path),"buses"=>length(net["bus"]),"source_sha256"=>bytes2hex(sha256(read(path))),
        "normalized_sha256"=>bytes2hex(sha256(JSON3.write(net))),"changes"=>changes,
        "input_provenance"=>metadata,"solver_price_divisor"=>price,"as_supplied"=>as_supplied,
        "load_p_W"=>sum(sum(d["p_nom"]) for d in values(net["load"])),"generators"=>length(net["generator"]))
    for which in ("ivr","linivr","lindist3flow")
        r=cost_capture(()->which=="ivr" ? cost_nlp(solvernet) : cost_linear(solvernet,which))
        row[which]=r
        if cost_accepted(r)
            r["cost_per_hour"]=cost_value(net,r["dispatch"])
            r["objective_reconstruction_error"]=abs(r["scaled_solver_objective"]*price-r["cost_per_hour"])
        end
        println("  ",which," ",get(r,"status",get(r,"error","?")));flush(stdout)
    end
    for which in ("linivr","lindist3flow")
        r=row[which];cost_accepted(r) || continue
        if cost_accepted(row["ivr"])
            r["versus_ivr_optimum"]=cost_errors(r["voltage"],row["ivr"]["voltage"])
            r["cost_difference_per_hour"]=r["cost_per_hour"]-row["ivr"]["cost_per_hour"]
        end
        replay=deepcopy(solvernet)
        for (id,d) in get(replay,"generator",Dict())
            ds=r["dispatch"]["generator"][id]
            d["p_min"]=copy(ds["p_W"]);d["p_max"]=copy(ds["p_W"])
            d["q_min"]=copy(ds["q_var"]);d["q_max"]=copy(ds["q_var"])
        end
        # Grid/source dispatch must balance nonlinear losses in replay.
        # Leave its operational box in place; fix only non-slack generators.
        pf=cost_capture(()->cost_nlp(replay;pf=true));r["replay"]=pf
        if cost_accepted(pf)
            pf["cost_per_hour"]=cost_value(net,pf["dispatch"])
            r["versus_same_dispatch_replay"]=cost_errors(r["voltage"],pf["voltage"])
            # Audit against original capability, not artificially tight replay bounds.
            pf["max_generator_dispatch_error_VA"]=maximum((abs(complex(pf["dispatch"]["generator"][id]["p_W"][k],pf["dispatch"]["generator"][id]["q_var"][k])-
                complex(d["p_W"][k],d["q_var"][k])) for (id,d) in r["dispatch"]["generator"] for k in eachindex(d["p_W"]));init=0.)
        end
        println("  ",which," replay ",get(pf,"status",get(pf,"error","?")));flush(stdout)
    end
    row
end

function run_enwl_cost(directory,output,count=0)
    files=filter(p->endswith(lowercase(p),".json"),readdir(directory;join=true))
    sort!(files;by=p->(length(JSON3.read(read(p,String))["bus"]),basename(p)))
    count>0 && (files=files[1:min(count,length(files))])
    data=Dict{String,Any}("julia"=>string(VERSION),"ipopt"=>string(pkgversion(Ipopt)),"clarabel"=>string(pkgversion(Clarabel)),
        "bmopftools_revision"=>readchomp(Cmd(["git","-C",dirname(dirname(pathof(BMOPFTools))),"rev-parse","HEAD"])),
        "formulationlab_base_revision"=>readchomp(Cmd(["git","rev-parse","HEAD"])),"s_base_VA"=>1e4,
        "nonlinear_cpu_limit_seconds"=>60,"blas_threads"=>1,"selection"=>"all JSON files sorted by bus count and filename; optional first COUNT",
        "protocol"=>"Original DER prices and bounds. Main panel consolidates priced grid generator with ideal source. All solver prices divided by case maximum; reported costs recomputed using original prices. LinIVR uses full conductors; L3F applies guarded ideal-ground Kron projection. No loaded reference supplied to either approximation. Nonlinear IVR is a local reference, not a global certificate.",
        "cases"=>Any[],"as_supplied_audit"=>Any[])
    save()=open(io->JSON3.write(io,cost_finite(data)),output,"w")
    for (i,path) in enumerate(files)
        println("CASE ",i,"/",length(files)," ",basename(path));flush(stdout)
        push!(data["cases"],cost_capture(()->cost_case(path)));save();GC.gc()
    end
    for i in unique(round.(Int,range(1,length(files);length=min(5,length(files)))))
        println("AS_SUPPLIED ",basename(files[i]));flush(stdout)
        push!(data["as_supplied_audit"],cost_capture(()->cost_case(files[i];as_supplied=true)));save();GC.gc()
    end
    println("SAVED ",output)
end
abspath(PROGRAM_FILE)==(@__FILE__) && run_enwl_cost(ARGS[1],ARGS[2],length(ARGS)>2 ? parse(Int,ARGS[3]) : 0)
