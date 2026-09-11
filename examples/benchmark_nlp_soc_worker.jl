include("benchmark_nlp_soc.jl")
function worker(path,output,mode)
    row=Dict{String,Any}("path"=>path,"mode"=>mode,"timing_note"=>"fresh process; warm-up excluded; new component compilation may remain")
    save()=open(io->JSON3.write(io,finite(row)),output,"w")
    row["stage"]="warmup";save()
    manifest=JSON3.read(read(joinpath(@__DIR__,"results","nlp_soc_panel_manifest.json"),String),Vector{Dict{String,Any}})
    net,sb,_,_=prepare_case(first(manifest)["path"])
    mode!="linear" && nlp_run(net,sb)
    mode!="nlp" && benchmark_soc(net;s_base=sb,variants=(:linear,))
    row["stage"]="parse";save()
    try
        pt=@elapsed net,sb,changes,provenance=prepare_case(path)
        merge!(row,Dict("buses"=>length(net["bus"]),"s_base_VA"=>sb,"changes"=>changes,"parse_seconds"=>pt,"parser_provenance"=>provenance,
            "load_models"=>unique([get(d,"model","constant_power") for d in values(get(net,"load",Dict()))]),
            "transformer_families"=>collect(keys(get(net,"transformer",Dict())))))
        if mode=="no_nameplate_caps"
            removed=Dict{String,Any}()
            for (kind,table) in get(net,"transformer",Dict()),(id,tx) in table
                haskey(tx,"s_rating") || continue
                removed["$kind/$id"]=pop!(tx,"s_rating")
            end
            row["removed_s_rating"]=removed
            row["repair"]="Separate diagnostic removing s_rating fields to disable BMOPFTools nameplate caps; not a solve of the unchanged input."
        end
        if mode=="repair_ieee13"
            # Original DSS explicitly gives r1=r0=1e-4, x1=x0=c1=c0=0, length defaults to 1.
            line=net["line"]["671692"];pop!(line,"linecode",nothing);pop!(line,"length",nothing)
            for i in 1:3,j in 1:3
                line["R_series_$(i)_$(j)"]=i==j ? 1e-4 : 0.
                line["X_series_$(i)_$(j)"]=0.
            end
            row["repair"]="Restore line 671692's explicitly stated OpenDSS sequence impedance as diag(1e-4 ohm). Separate derived-input experiment."
        end
        row["stage"]="nlp";save()
        if mode!="linear"
            try row["nlp"]=nlp_run(net,sb) catch e;row["nlp_error"]=sprint(showerror,e);end
        end
        row["stage"]="soc_linear";save()
        if mode!="nlp"
            try
                row["stage"]="soc_build";save()
                bt=@elapsed b=build_opf(net,IVRSOC(s_base=sb,objective=:source_import))
                row["stage"]="soc_solve";row["soc_build_seconds"]=bt;save()
                set_time_limit_sec(b.model,90.)
                st=@elapsed r=solve_soc_opf(b;solver_options=(verbose=false,))
                row["soc"]=[Dict("variant"=>"linear","termination"=>r.solve.termination_status,"primal_status"=>r.solve.primal_status,
                    "objective_W"=>finite(r.objective),"solver_bound_W"=>finite(r.solver_objective_bound),"build_seconds"=>bt,"solve_seconds"=>st,
                    "variables"=>num_variables(b.model))]
            catch e;row["soc_error"]=sprint(showerror,e);end
        end
        row["stage"]="complete"
    catch e;row["input_error"]=sprint(showerror,e);row["stage"]="input_error";end
    save()
end
if abspath(PROGRAM_FILE)==(@__FILE__)
    worker(ARGS[1],ARGS[2],ARGS[3])
end
