# Loading audit only. The wye-side alias adapter is specific to PowerIO's DSS
# emitter, not an inference about arbitrary BMOPF files. No controls are run.
using FormulationLab, PowerIO, JSON3, SHA
function audit_large_ieee(path,output)
    out=Dict{String,Any}("path"=>abspath(path),"master_sha256"=>bytes2hex(sha256(read(path))),
        "revision"=>readchomp(`git rev-parse HEAD`),"julia"=>string(VERSION),"powerio"=>string(pkgversion(PowerIO)),
        "stage"=>"parse", "note"=>"Applicability is not a claim of faithful conversion or a successful solve. No branch removal or controller simulation.")
    save()=open(io->JSON3.write(io,out),output,"w")
    diag(d)=Dict("code"=>d.code,"severity"=>String(d.severity),"message"=>d.message)
    save()
    try
        println("PARSE ",path);flush(stdout)
        t=@elapsed module_value=PowerIO.parse(path;format="dss")
        out["parse_seconds"]=t;out["read_diagnostics"]=diag.(module_value.diagnostics)
        out["stage"]="emit_bmopf";save()
        t=@elapsed input=read_bmopf(module_value)
        out["emit_seconds"]=t;out["parser_diagnostics"]=diag.(input.diagnostics)
        net=input.network
        out["component_counts"]=Dict(k=>length(v) for (k,v) in net if v isa AbstractDict && k ∉ ("meta","_meta","terminal_conventions"))
        out["transformer_counts"]=Dict(k=>length(v) for (k,v) in get(net,"transformer",Dict()))
        models=Dict{String,Int}()
        for d in values(get(net,"load",Dict()));k=string(get(d,"model","absent"));models[k]=get(models,k,0)+1;end
        out["load_models"]=models
        aliases=Any[]
        for (kind,table) in get(net,"transformer",Dict()),(id,d) in table
            kind in ("delta_wye","wye_delta") || continue
            side=kind=="delta_wye" ? "to" : "from"
            for k in ("r_series","x_series")
                haskey(d,k) || continue
                any(haskey(d,k*"_"*s) for s in ("from","to")) && error("ambiguous mixed transformer impedance fields")
                v=pop!(d,k);d[k*"_"*side]=v
                push!(aliases,Dict("transformer"=>id,"field"=>k,"target"=>k*"_"*side,"value"=>v))
            end
        end
        out["diagnostic_wye_alias_adapter"]=aliases
        out["applicability"]=Dict{String,Any}();save()
        for mode in (:lower,:approximate,:permissive)
            out["stage"]="check_$mode";save();println(out["stage"]);flush(stdout)
            row=Dict{String,Any}();out["applicability"][string(mode)]=row
            try
                t=@elapsed r=check_l3f_applicability(net;options=L3FOptions(unsupported=mode))
                row["seconds"]=t;row["status"]=String(r.status)
                counts=Dict{String,Int}();errors=Any[];samples=Dict{String,Any}()
                for f in r.findings
                    counts[f.code]=get(counts,f.code,0)+1
                    d=Dict("code"=>f.code,"severity"=>String(f.severity),"id"=>f.id,"message"=>f.message,"evidence"=>f.evidence)
                    f.severity==:error && push!(errors,d)
                    get!(samples,f.code,d)
                end
                row["finding_counts"]=counts;row["errors"]=errors;row["finding_samples"]=samples
                println(r.status," ",counts);flush(stdout)
            catch e;row["error"]=sprint(showerror,e,catch_backtrace());end
            save()
        end
        out["stage"]="complete"
    catch e
        out["error"]=sprint(showerror,e,catch_backtrace());out["failed_stage"]=out["stage"];out["stage"]="error"
    end
    save()
end
abspath(PROGRAM_FILE)==(@__FILE__) && audit_large_ieee(ARGS[1],ARGS[2])
