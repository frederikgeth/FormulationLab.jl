# External fixed-transformer coverage and physical checks, not a timing claim.
# Usage: julia --project=test examples/check_ivr_transformer_datasets.jl ROOT OUTPUT
include("benchmark_ivr_feeders.jl")

function check_ivr_transformer_datasets(root,output;files=[
    "output/LV/original/LV33_1bus.json",
    "output/LV/augmented/LV1_14bus_augmented.json",
    "output/DSuite/original/DSuite_SPD_Rural.json",
    "output/DSuite/original/DSuite_SPD_Suburban.json",
    "output/FrenchPowerGrids/original/75_MVFeeder0281.bmopf.json"])
    BLAS.set_num_threads(1)
    report=Dict{String,Any}("julia"=>string(VERSION),"ipopt"=>string(pkgversion(Ipopt)),
        "root"=>abspath(root),"cases"=>Any[],"accounting_scenario"=>"declared",
        "note"=>"Raw dictionary boundary. Only known provenance relocated in memory; bus latitude/longitude/v_declared and legacy generator _slack labels retained in place. No electrical edits or source-file changes. Three demand factors on one built model per requested specialization. Transformer cases always use full IVR. No warmup or repeated timing panel; timings include compilation and are not performance evidence. Local solver status is not a global certificate.")
    for file in files
        row=Dict{String,Any}("file"=>file,"trials"=>Any[]);push!(report["cases"],row)
        try
            path=joinpath(root,file);row["sha256"]=bytes2hex(sha256(read(path)))
            net,detached=compiler_feeder_input(path;detach_legacy_provenance=true)
            row["detached_provenance_paths"]=detached
            row["buses"]=length(net["bus"]);row["original_accounting"]=feeder_accounting(net)
            row["transformers"]=Dict(kind=>length(table) for (kind,table) in get(net,"transformer",Dict()))
            demands=[complex(p,q) for load in values(get(net,"load",Dict())) for (p,q) in zip(load["p_nom"],load["q_nom"])]
            row["nominal_load"]=Dict("p_W"=>sum(real,demands;init=0.),"q_var"=>sum(imag,demands;init=0.),
                "channels"=>length(demands),"nonzero_channels"=>count(!iszero,demands))
            counterparts=Dict(s=>build_opf(net,IVRNLP(specialization=s,objective=:cost)) for s in (:off,:conductor_difference))
            for s in (:off,:conductor_difference)
                trial,_,_=feeder_trial(net,s;factors=(1.,.9,1.1),opposite=counterparts[s==:off ? :conductor_difference : :off])
                push!(row["trials"],trial)
            end
        catch err
            err isa InterruptException && rethrow()
            row["error"]=sprint(showerror,err)
        end
        haskey(row,"sha256") && (row["input_unchanged"]=bytes2hex(sha256(read(joinpath(root,file))))==row["sha256"])
        open(io->JSON3.write(io,report),output,"w")
        println(file," : ",get(row,"error",[(t["specialization"],[(s["status"],s["physical_passed"]) for s in t["scenarios"]]) for t in row["trials"]]));flush(stdout)
    end
    report
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("Supply dataset root and output JSON path")
    check_ivr_transformer_datasets(ARGS[1],ARGS[2])
end
