include(joinpath(@__DIR__,"benchmark_nlp_soc.jl"))
rows=Any[]
for c in JSON3.read(read(joinpath(@__DIR__,"results","nlp_soc_panel_manifest.json"),String),Vector{Dict{String,Any}})
    row=copy(c);push!(rows,row)
    try
        n,sb,_,_=prepare_case(c["path"])
        for drop in (false,true)
            t=@elapsed p=prepare_network(n;reduction=ReductionOptions(allow_drop_bus_constraints=drop),warn=false)
            rep=reduction_report(p)
            row[string(drop)]=Dict(k=>v for (k,v) in rep if k!="events")
            row[string(drop)]["prepare_seconds"]=t
        end
        println(c["name"]," ",row["false"]["buses_before"]," -> ",row["false"]["buses_after"]," / ",row["true"]["buses_after"]);flush(stdout)
    catch e; row["error"]=sprint(showerror,e);println(row["error"]);end
    open(io->JSON3.write(io,rows),joinpath(@__DIR__,"results","reduction_scan_2026-09-11.json"),"w")
end
