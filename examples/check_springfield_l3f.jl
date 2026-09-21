# Explicit convention sensitivity study; neither interpretation is inferred from
# ambiguous aliases. Input remains unchanged; no branch is opened.
using FormulationLab, JuMP, Clarabel, JSON3, SHA, LinearAlgebra
function springfield_check(path,output)
    t=@elapsed input=read_bmopf(path)
    out=Dict{String,Any}("input"=>abspath(path),"input_sha256"=>bytes2hex(sha256(read(path))),
        "revision"=>readchomp(`git rev-parse HEAD`),"implementation_branch"=>readchomp(`git branch --show-current`),"working_tree_dirty"=>!isempty(readchomp(`git status --porcelain`)),"julia"=>string(VERSION),"clarabel"=>string(pkgversion(Clarabel)),
        "read_seconds"=>t,"note"=>"Both alias interpretations are explicit hypothetical scenarios, not a determination of the input author's convention. Build times include compilation. No branches removed; one solve per scenario.","runs"=>Any[])
    save()=open(io->JSON3.write(io,out),output,"w")
    for convention in (:from_terminal,:from_coil)
        row=Dict{String,Any}("convention"=>String(convention));push!(out["runs"],row);save()
        println("BUILD ",convention);flush(stdout)
        try
            opts=L3FOptions(topology=:meshed_linear,unsupported=:lower,transformer_impedance=convention,s_base=1e6,objective=:source_import)
            t=@elapsed b=build_l3f_opf(input,Clarabel.Optimizer;options=opts)
            row["build_seconds"]=t;row["variables"]=num_variables(b.model)
            row["lines_after_lowering"]=length(b.network["line"])
            row["transformers"]=sum(length,values(b.network["transformer"]))
            row["problem_class"]=String(l3f_model_class(b))
            row["findings"]=[Dict("code"=>f.code,"severity"=>String(f.severity),"id"=>f.id,"message"=>f.message,"evidence"=>f.evidence) for f in b.applicability.findings]
            set_silent(b.model);set_optimizer_attribute(b.model,"time_limit",120.)
            println("SOLVE ",convention);flush(stdout)
            t=@elapsed optimize!(b.model)
            row["optimize_seconds"]=t;row["native_solve_seconds"]=solve_time(b.model)
            row["status"]=string(termination_status(b.model))
            if termination_status(b.model)==MOI.OPTIMAL
                row["source_W"]=sum(value,values(b.variables[:p_source]))*opts.s_base
                pu=[sqrt(max(0.,value(w)))/abs(b.working_reference.voltage[key]) for (key,w) in b.variables[:w]]
                row["min_voltage_relative_reference"]=minimum(pu);row["max_voltage_relative_reference"]=maximum(pu)
            end
            println(row["status"]);flush(stdout)
        catch e
            row["error"]=sprint(showerror,e,catch_backtrace());println(row["error"]);flush(stdout)
        end
        save()
    end
end
springfield_check(ARGS[1],ARGS[2])
