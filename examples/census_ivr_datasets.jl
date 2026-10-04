# Inventory external network files and test a deterministic size sample per
# directory. This does not solve, simplify or modify any input network.
using FormulationLab, JSON3, SHA
include("census_ivr_compiler.jl")

function census_ivr_datasets(root,output;max_buses=nothing)
    max_buses===nothing || (max_buses isa Integer && !(max_buses isa Bool) && max_buses>0) ||
        throw(ArgumentError("max_buses must be a positive integer or nothing"))
    cases=Any[];parse_errors=Any[]
    for folder in ("output","benchmarks")
        base=joinpath(root,folder);isdir(base) || continue
        for (directory,_,files) in walkdir(base),name in sort!(files)
            endswith(name,".json") || continue
            path=joinpath(directory,name)
            raw=read(path)
            # Skip non-object reports without treating valid JSON arrays as
            # parse errors. Bus terminal declarations distinguish input
            # networks from solver-result objects with similar root keys.
            startswith(lstrip(String(copy(raw))),"{") || continue
            net=try JSON3.read(String(copy(raw)),Dict{String,Any}) catch err
                push!(parse_errors,(;file=relpath(path,root),error=sprint(showerror,err)));continue
            end
            get(net,"bus",nothing) isa AbstractDict && get(net,"voltage_source",nothing) isa AbstractDict || continue
            !isempty(net["bus"]) && all(b->b isa AbstractDict && haskey(b,"terminal_names"),values(net["bus"])) || continue
            push!(cases,Dict("file"=>relpath(path,root),"directory"=>relpath(directory,root),
                "sha256"=>bytes2hex(sha256(raw)),"buses"=>length(net["bus"]),"lines"=>length(get(net,"line",Dict())),
                "generators"=>length(get(net,"generator",Dict())),
                "components"=>Dict(k=>length(get(net,k,Dict())) for k in ("transformer","switch","capacitor","ibr"))))
        end
    end
    groups=sort!(unique(c["directory"] for c in cases));sample=Any[]
    report=Dict("root"=>abspath(root),"inventory"=>cases,"sample"=>sample,"parse_errors"=>parse_errors,
        "max_buses"=>max_buses,"complete"=>false,
        "note"=>"Smallest, median-ranked and largest file per directory, ties ordered by path. Network-shaped JSON only; raw dictionary boundary, no schema validation. Known provenance relocated in memory. Related/duplicate variants are not independent feeders. No solve or source-file changes. An explicit size limit skips assembly/initialization, not input checks; skipped cases are not assessed. Checkpoints retain completed samples if interrupted.")
    save()=open(io->JSON3.write(io,report),output,"w")
    save()
    for group in groups
        ordered=sort([c for c in cases if c["directory"]==group];by=c->(c["buses"],c["file"]))
        for k in unique([1,cld(length(ordered),2),length(ordered)])
            row=copy(ordered[k]);path=joinpath(root,row["file"])
            println("Checking ",row["file"]);flush(stdout)
            try
                net,detached=compiler_feeder_input(path;detach_legacy_provenance=true)
                row["detached_provenance_paths"]=detached
                FormulationLab._ivrn_check(net)
                if max_buses!==nothing && row["buses"]>max_buses
                    row["status"]="not_assessed";row["code"]="size_limit"
                else
                    assembly=@timed FormulationLab._ivr_electrical_data(net;s_base=1e4,line_records=true,delta_dispatch=:coil,source_mode=:affine)
                    e=assembly.value;row["assembly_s"]=assembly.time
                    row["initialization_s"]=@elapsed FormulationLab._ivrn_start(net,e)
                    structure,_=FormulationLab._ivrn_structure(net,e)
                    row["status"]=string(structure.status);row["code"]=string(structure.code)
                end
            catch err
                err isa InterruptException && rethrow()
                row["status"]="unsupported_or_invalid";row["code"]="baseline_error"
                row["error"]=sprint(showerror,err)
            end
            push!(sample,row)
            save()
        end
        println("Sampled ",group);flush(stdout)
    end
    report["complete"]=true;save()
    report
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS) in (2,3) || error("Supply dataset root, output JSON path, and optional maximum bus count")
    census_ivr_datasets(ARGS[1],ARGS[2];max_buses=length(ARGS)==3 ? parse(Int,ARGS[3]) : nothing)
end
