# Optional live measurement. Failed convergence/agreement rows are retained;
# successful execution means the report was written, not that all rows passed.
using FormulationLab,JuMP,Ipopt,JSON3,SHA
import BMOPFTools
include("../ivr_nwinding_limit_fixtures.jl")
length(ARGS)==1 || error("Supply a JSON report path; exports are saved beside it")
output=abspath(only(ARGS));folder=joinpath(dirname(output),"CONNECTION_EXPORTS");mkpath(folder)
save(path,x)=open(io->JSON3.write(io,x),path,"w")
base_settings=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,
    bound_relax_factor=0.,max_iter=500,nlp_scaling_method="gradient-based")
rows=Any[];references=Any[]
root=dirname(dirname(pathof(BMOPFTools)))
files=("src/io/nwinding.jl","ext/BMOPFOpfExt/nwinding.jl","ext/BMOPFOpfExt/per_unit.jl")
function report()
    (;reference_path=root,reference_revision=readchomp(`git -C $root rev-parse HEAD`),
      reference_dirty=!isempty(readchomp(`git -C $root status --porcelain`)),
      reference_source_sha256=Dict(p=>bytes2hex(sha256(read(joinpath(root,p)))) for p in files),
      references,cases=rows,accepted=count(r->get(r,"accepted",false),rows),
      note="Per-unit YYY/YDY/DYY, both delta rolls, finite leakage, zero excitation, unequal nominal turns, forward/reverse, absent/active scalar caps. Baseline and absolute stopping panels remain separate. Strict status, physical/model membership and objective agreement are separate gates; failed rows are not timed or discarded.")
end
for stopping in (:baseline,:absolute),
    (connection,roll) in ((:YYY,1),(:YDY,1),(:YDY,-1),(:DYY,1),(:DYY,-1)),
    reverse in (false,true),bounded in (false,true),sb in (1e3,1e5)
    settings=stopping==:baseline ? base_settings : merge(base_settings,(dual_inf_tol=1e-10,compl_inf_tol=1e-10))
    net=_nwinding_connection_case(;connection,roll,reverse,bounded);original=deepcopy(net)
    stem=join((stopping,connection,roll,reverse,bounded,sb),"__")
    save(joinpath(folder,stem*".input.json"),net)
    reference=Dict{String,Any}("case"=>stem,"stopping"=>stopping,"settings"=>settings)
    ref=nothing;refpoint=nothing
    full=build_opf(net,IVRNLP(;s_base=sb,objective_scale=1.,transformer_nameplate=:bmopftools))
    try
        ref=BMOPFTools.solve_opf(net;optimizer=Ipopt.Optimizer,per_unit=true,s_base=sb,
            solver_options=Tuple(string(k)=>v for (k,v) in pairs(settings)))
        save(joinpath(folder,stem*".reference.json"),ref)
        reference["status"]=ref["termination_status"];reference["objective"]=ref["objective"]
        reference["strict_status"]=ref["termination_status"] in ("LOCALLY_SOLVED","OPTIMAL")
        refpoint=_nwinding_connection_point(net,ref)
        reference["physical_passed"]=physical_residuals(net,refpoint;delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed
        reference["full_membership_passed"]=ivr_nlp_point_report(full,refpoint).passed
    catch err
        err isa InterruptException && rethrow()
        reference["error"]=sprint(showerror,err)
    end
    push!(references,reference)
    anchor=nothing
    for lifting in (:off,:powers,:bounded_observations)
        row=Dict{String,Any}("case"=>stem,"stopping"=>stopping,"connection"=>connection,"roll"=>roll,
            "reverse"=>reverse,"bounded"=>bounded,"s_base"=>sb,"lifting"=>lifting,"accepted"=>false)
        try
            opts=IVRNLPOptions(;s_base=sb,objective_scale=1.,transformer_nameplate=:bmopftools,
                lifting,lifted_power_base=500.,observation_sharing=:signed,
                specialization=:conductor_regions,linear_elimination=:passive_blocks,
                device_elimination=:transformer_currents,transformer_scaling=:nominal,row_scaling=:composed)
            b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
            r=solve_ivr_nlp_opf(b;solver_options=settings)
            row["native_status"]=string(r.solve.termination_status)
            if r.solve.optimal
                d=result_dict(b,r);point=_nwinding_connection_point(net,d)
                row["objective"]=r.objective
                row["physical_passed"]=physical_residuals(net,r).passed && physical_residuals(net,point;delta_dispatch=:coil,transformer_nameplate=:bmopftools).passed
                row["own_full_passed"]=ivr_nlp_point_report(b,point).passed && ivr_nlp_point_report(full,point).passed
                row["reverse_passed"]=anchor===nothing || ivr_nlp_point_report(b,anchor).passed
                row["reference_membership_passed"]=refpoint!==nothing && ivr_nlp_point_report(b,refpoint).passed
                row["objective_gap"]=ref===nothing ? nothing : r.objective-ref["objective"]
                row["objective_agrees"]=ref!==nothing && isapprox(r.objective,ref["objective"];atol=1e-7,rtol=1e-6)
                row["winding_currents_agree"]=ref!==nothing && all(isapprox(complex(x["cr"],x["ci"]),complex(ref["transformer"]["tx"][w][k]["cr"],ref["transformer"]["tx"][w][k]["ci"]);atol=2e-5,rtol=1e-6) for w in ("w1","w2","w3") for (k,x) in d["transformer"]["tx"][w])
                row["tightened_rejected"]=true
                if bounded
                    tight=deepcopy(net);tight["transformer"]["n_winding"]["tx"]["windings"][2]["s_max"]=270.
                    row["tightened_rejected"]=!physical_residuals(tight,r).passed && !ivr_nlp_point_report(build_opf(tight,IVRNLP(opts)),point).passed
                end
                io=IOBuffer();write_result(d,io);seekstart(io)
                row["reference_reader_roundtrip"]=isequal(BMOPFTools.read_result(io),d)
                row["result_file"]=joinpath("CONNECTION_EXPORTS",stem*"__"*string(lifting)*".result.json")
                open(io->write_result(d,io),joinpath(dirname(output),row["result_file"]),"w")
                row["accepted"]=get(reference,"strict_status",false) && get(reference,"physical_passed",false) &&
                    get(reference,"full_membership_passed",false) && all(row[k] for k in
                    ("physical_passed","own_full_passed","reverse_passed","reference_membership_passed",
                     "objective_agrees","winding_currents_agree","tightened_rejected","reference_reader_roundtrip"))
                anchor===nothing && (anchor=point)
            end
            @assert net==original
        catch err
            err isa InterruptException && rethrow()
            row["accepted"]=false
            row["error"]=sprint(showerror,err)
        end
        push!(rows,row);save(output,report())
        println(stem," ",lifting," accepted=",row["accepted"]," ",get(row,"error",""));flush(stdout)
    end
end
println("Accepted ",count(r->r["accepted"],rows),"/",length(rows)," comparisons; all outcomes retained.")
