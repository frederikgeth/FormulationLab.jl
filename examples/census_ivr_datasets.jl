# Inventory external network files and test a deterministic size sample per
# directory. This does not solve, simplify or modify any input network.
using FormulationLab, JSON3, SHA
include("census_ivr_compiler.jl")

function census_ivr_datasets(root,output)
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
    for group in groups
        ordered=sort([c for c in cases if c["directory"]==group];by=c->(c["buses"],c["file"]))
        for k in unique([1,cld(length(ordered),2),length(ordered)])
            row=copy(ordered[k]);path=joinpath(root,row["file"])
            try
                net,detached=compiler_feeder_input(path;detach_legacy_provenance=true)
                row["detached_provenance_paths"]=detached
                FormulationLab._ivrn_check(net)
                e=FormulationLab._ivr_electrical_data(net;s_base=1e4,line_records=true,delta_dispatch=:coil,source_mode=:affine)
                FormulationLab._ivrn_start(net,e)
                report,_=FormulationLab._ivrn_structure(net,e)
                row["status"]=string(report.status);row["code"]=string(report.code)
            catch err
                err isa InterruptException && rethrow()
                row["status"]="unsupported_or_invalid";row["code"]="baseline_error"
                row["error"]=sprint(showerror,err)
            end
            push!(sample,row)
        end
        println("Sampled ",group);flush(stdout)
    end
    report=Dict("root"=>abspath(root),"inventory"=>cases,"sample"=>sample,"parse_errors"=>parse_errors,
        "note"=>"Smallest, median-ranked and largest file per directory, ties ordered by path. Network-shaped JSON only; raw dictionary boundary, no schema validation. Known provenance relocated in memory. Related/duplicate variants are not independent feeders. No solve or source-file changes.")
    open(io->JSON3.write(io,report),output,"w")
    report
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("Supply dataset root and output JSON path")
    census_ivr_datasets(ARGS[1],ARGS[2])
end
