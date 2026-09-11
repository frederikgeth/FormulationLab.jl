# Optional environment: julia --project=test/integration examples/benchmark_nlp_soc.jl MANIFEST OUTPUT
using FormulationLab, BMOPFTools, JuMP, Ipopt, Clarabel, JSON3, LinearAlgebra, SHA
include("benchmark_soc.jl")
BLAS.set_num_threads(1)
finite(x)=x isa AbstractFloat && !isfinite(x) ? nothing : x isa AbstractDict ? Dict(string(k)=>finite(v) for (k,v) in x) : x isa AbstractVector ? finite.(x) : x
panel_clean(x::AbstractDict)=Dict{String,Any}(string(k)=>panel_clean(v) for (k,v) in x if !startswith(string(k),"_"))
panel_clean(x::AbstractVector)=map(panel_clean,x)
panel_clean(x)=x
function prepare_case(path)
    net=endswith(lowercase(path),".json") ? BMOPFTools.parse_bmopf(path) : BMOPFTools.from_dss(path)
    provenance=get(net,"_meta",Dict());net=panel_clean(net)
    changes=String[];sources=Set(s["bus"] for s in values(net["voltage_source"]))
    for (id,g) in collect(get(net,"generator",Dict()))
        if g["bus"] in sources;delete!(net["generator"],id);push!(changes,"remove source generator $id");end
    end
    for s in values(net["voltage_source"]);s["cost"]=ones(length(s["terminal_map"]));pop!(s,"energy_cost_rate",nothing);end
    for g in values(get(net,"generator",Dict()));g["cost"]=zeros(length(g["p_max"]));pop!(g,"energy_cost_rate",nothing);end
    for (family,table) in net
        table isa AbstractDict || continue
        for (id,d) in table
            d isa AbstractDict || continue
            if haskey(d,"control_profile");push!(changes,"omit control $family/$id");delete!(d,"control_profile");end
        end
    end
    pop!(net,"control_profile",nothing)
    for (kind,table) in get(net,"transformer",Dict()),(id,d) in table
        for w in (kind=="n_winding" ? d["windings"] : [d])
            for k in ("tap_min","tap_max","tap_ratio_min","tap_ratio_max")
                if haskey(w,k)
                    haskey(w,"tap") || haskey(w,"tap_ratio") || error("No fixed tap for $kind/$id")
                    delete!(w,k);push!(changes,"fixed tap: remove $kind/$id/$k")
                end
            end
        end
    end
    load=sum((sum(abs.(complex.(d["p_nom"],d["q_nom"]))) for d in values(get(net,"load",Dict())));init=0.)
    gen=sum((sum(abs.(d["p_max"])) for d in values(get(net,"generator",Dict())));init=0.)
    net,max(load,gen,3000.)/3,changes,provenance
end
function nlp_run(net,sb)
    bt=@elapsed begin
        ctx=BMOPFTools.build_opf_model(net;optimizer=Ipopt.Optimizer,per_unit=true,s_base=sb)
        BMOPFTools.enforce_kcl!(ctx)
    end
    m=BMOPFTools.opf_model(ctx)
    for (k,v) in ("print_level"=>0,"tol"=>1e-8,"constr_viol_tol"=>1e-8,"bound_relax_factor"=>0.,"max_iter"=>1500,"max_cpu_time"=>90.)
        set_optimizer_attribute(m,k,v)
    end
    st=@elapsed optimize!(m);et=@elapsed r=BMOPFTools.extract_result(ctx)
    findings=BMOPFTools.Finding[];check=BMOPFTools.solution_check(net,r,findings)
    accepted=termination_status(m) in (MOI.LOCALLY_SOLVED,MOI.OPTIMAL)
    imp=accepted ? sum(sum(t["ps"] for t in values(s)) for s in values(r["voltage_source"])) : nothing
    Dict("status"=>string(termination_status(m)),"primal_status"=>string(primal_status(m)),"build_seconds"=>bt,"solve_seconds"=>st,"extract_seconds"=>et,
        "source_W"=>imp,"variables"=>num_variables(m),"max_model_residual"=>has_values(m) ? maximum(values(primal_feasibility_report(m));init=0.) : nothing,
        "findings"=>[Dict("severity"=>string(f.severity),"code"=>f.code,"message"=>f.message) for f in findings],"solution_check"=>check)
end
function run_panel(manifest,output)
    cases=JSON3.read(read(manifest,String),Vector{Dict{String,Any}})
    data=Dict("julia"=>string(VERSION),"ipopt"=>string(pkgversion(Ipopt)),"clarabel"=>string(pkgversion(Clarabel)),
        "bmopftools_revision"=>readchomp(`git -C $(dirname(dirname(pathof(BMOPFTools)))) rev-parse HEAD`),
        "formulationlab_revision"=>readchomp(`git rev-parse HEAD`),"blas_threads"=>1,"time_limit_seconds"=>90,"cases"=>Any[])
    save()=open(io->JSON3.write(io,finite(data)),output,"w")
    # Warm up the actual build/solve paths on the smallest feeder.
    warm,sb,_,_=prepare_case(cases[1]["path"])
    nlp_run(warm,sb);benchmark_soc(warm;s_base=sb,variants=(:linear,:kim))
    for c in cases
        row=copy(c);push!(data["cases"],row);save()
        println("START ",c["name"]);flush(stdout)
        try
            row["sha256"]=bytes2hex(sha256(read(c["path"])))
            pt=@elapsed net,sb,changes,provenance=prepare_case(c["path"])
            row["parse_seconds"]=pt;row["changes"]=changes;row["parser_provenance"]=provenance;row["buses"]=length(net["bus"]);row["s_base_VA"]=sb
            row["normalized_sha256"]=bytes2hex(sha256(JSON3.write(net)))
            row["components"]=Dict(k=>length(get(net,k,Dict())) for k in ("bus","line","load","generator","transformer","switch","capacitor","ibr"))
            row["load_models"]=unique([get(d,"model","constant_power") for d in values(get(net,"load",Dict()))])
            save()
            try row["nlp"]=nlp_run(net,sb) catch e;row["nlp_error"]=sprint(showerror,e);end
            save();println("NLP ",get(get(row,"nlp",Dict()),"status",get(row,"nlp_error","?")));flush(stdout)
            row["soc"]=Any[]
            if length(net["bus"])>140
                row["soc_skipped"]="Use the externally bounded runner above 140 buses. This is an experiment budget, not a formulation applicability limit."
                save();continue
            end
            for variant in (:linear,:kim)
                try append!(row["soc"],benchmark_soc(net;s_base=sb,variants=(variant,)))
                catch e;push!(row["soc"],Dict("variant"=>string(variant),"error"=>sprint(showerror,e)));end
                save();println("SOC ",variant," ",get(last(row["soc"]),"termination",get(last(row["soc"]),"error","?")));flush(stdout)
            end
        catch e;row["input_error"]=sprint(showerror,e);save();println("INPUT ",row["input_error"]);end
        GC.gc();flush(stdout)
    end
end
abspath(PROGRAM_FILE)==(@__FILE__) && run_panel(ARGS[1],ARGS[2])
