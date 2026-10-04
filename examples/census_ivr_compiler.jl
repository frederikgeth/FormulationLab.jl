# Read-only applicability census. Inputs are not altered or bundled.
using FormulationLab, JSON3, SHA
# Relocate only known provenance fields on the owned copy. Neither canonical
# electrical fields nor the source file are modified.
function compiler_feeder_input(path;detach_legacy_provenance=false)
    net=FormulationLab._l3f_input(JSON3.read(read(path,String),Dict{String,Any}))
    detached=Dict{String,Any}()
    function detach!(x,prefix="")
        x isa AbstractDict || return
        for key in collect(keys(x))
            location=prefix*"/"*string(key)
            if key in ("_pmd","_simplification_log","_merged_from")
                detached[location]=pop!(x,key)
            else
                detach!(x[key],location)
            end
        end
    end
    if detach_legacy_provenance
        detach!(net)
        get!(net,"_meta",Dict{String,Any}())["detached_legacy_provenance"]=detached
    end
    net,sort!(collect(keys(detached)))
end

function census_ivr_compiler(directory,output;detach_legacy_provenance=false)
    rows=Any[];codes=Dict{String,Int}()
    for path in sort!(filter(p->endswith(p,".json"),readdir(directory;join=true)))
        row=Dict{String,Any}("file"=>basename(path),"sha256"=>bytes2hex(sha256(read(path))))
        try
            # Exercise the supported raw-dictionary boundary. This census is
            # about electrical applicability, not PowerIO schema validation.
            net,detached=compiler_feeder_input(path;detach_legacy_provenance)
            row["detached_provenance_paths"]=detached
            FormulationLab._ivrn_check(net)
            e=FormulationLab._ivr_electrical_data(net;s_base=1e4,line_records=true,delta_dispatch=:coil,source_mode=:affine)
            FormulationLab._ivrn_start(net,e)
            report,_=FormulationLab._ivrn_structure(net,e)
            row["buses"]=length(net["bus"]);row["lines"]=length(e.lnc_lines)
            row["status"]=string(report.status);row["code"]=string(report.code)
            row["components"]=report.components
        catch err
            row["status"]="unsupported_or_invalid";row["code"]="baseline_error"
            row["error"]=sprint(showerror,err)
        end
        code=row["code"];codes[code]=get(codes,code,0)+1;push!(rows,row)
    end
    report=Dict("directory"=>abspath(directory),"count"=>length(rows),"codes"=>codes,"cases"=>rows,
        "input_mode"=>"raw BMOPF dictionaries, no schema validation",
        "detach_legacy_provenance"=>detach_legacy_provenance,
        "note"=>"Applicability only, no optimization or new topology reduction. Any reduction already present in source files is inherited.")
    open(io->JSON3.write(io,report),output,"w")
    println(codes)
    report
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS) in (2,3) || error("Supply input directory, output JSON path, and optional --detach-provenance")
    length(ARGS)==3 && ARGS[3]!="--detach-provenance" && error("Unknown flag")
    census_ivr_compiler(ARGS[1],ARGS[2];detach_legacy_provenance=length(ARGS)==3)
end
