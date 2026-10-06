# Optional correctness/solver diagnostic, not an isolated timing campaign.
using FormulationLab,JuMP,Ipopt,JSON3,SHA
include("benchmark_ivr_joint_boundaries.jl")
const J=IVRJointBoundaryStudy

function voltage_equality_study(output)
    folder=joinpath(dirname(abspath(output)),"VOLTAGE_EXPORTS");mkpath(folder)
    rows=Any[]
    for n in (2,3),direction in (-1,1),sb in (1e3,1e5),scaling in ("none","gradient-based")
        net,m=J.scenario(;conductors=n,direction,treatment=:loose_current)
        family=n==2 ? "vpn" : "vpp";channels=n==2 ? 1 : 3
        for suffix in ("min","max");net["bus"]["b1"][family*"_"*suffix]=fill(m.nominal_voltage_V,channels);end
        original=deepcopy(net);profiles=J.profiles(net,m;nlp_scaling_method=scaling)
        full=build_opf(net,IVRNLP(objective=:power,power_terms=first(profiles).options.power_terms))
        stem=join((n,direction,sb,scaling),"__")
        open(io->JSON3.write(io,net),joinpath(folder,stem*".input.json"),"w")
        anchor=nothing;objective=nothing
        for policy in (:equality,:separate),p in profiles
            label=stem*"__$(policy)__$(p.name)"
            row=Dict{String,Any}("case"=>stem,"conductors"=>n,"direction"=>direction,"s_base"=>sb,
                "scaling"=>scaling,"policy"=>policy,"profile"=>p.name,"accepted"=>false)
            try
                opts=IVRNLPOptions(;(k=>(k==:coincident_voltage_bounds ? policy : k==:s_base ? sb : deepcopy(getfield(p.options,k))) for k in fieldnames(IVRNLPOptions))...)
                b=build_opf(net,IVRNLP(opts);optimizer=Ipopt.Optimizer)
                enc=ivr_nlp_point_report(b,J.L.M.E.S.U.G.H.S.L.start_point(net))
                @assert isempty(enc.missing_channels)
                for (v,x) in enc.variable_values;set_start_value(v,x);end
                r=solve_ivr_nlp_opf(b;solver_options=merge(J.L.P.STRICT,p.solver_options))
                row["status"]=string(r.solve.termination_status)
                row["objective"]=r.objective
                row["physical_passed"]=physical_residuals(net,r).passed
                point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
                row["own_full_passed"]=ivr_nlp_point_report(b,point).passed && ivr_nlp_point_report(full,point).passed
                # The first full equality model supplies a common point and
                # objective anchor. Preserve its validity separately.
                if anchor===nothing
                    @assert r.solve.optimal && row["physical_passed"] && row["own_full_passed"]
                    anchor=point;objective=r.objective
                end
                row["reverse_passed"]=ivr_nlp_point_report(b,anchor).passed
                row["objective_gap"]=r.objective-objective
                row["objective_agrees"]=isapprox(r.objective,objective;atol=1e-5,rtol=1e-8)
                row["voltage_error_V"]=maximum(abs(x.slack_V) for x in J.voltage_activity(net,point,m).records)
                row["max_abs_row_dual"]=maximum(abs(dual(c)) for c in all_constraints(b.model;include_variable_in_set_constraints=false))
                row["lower_shift_rejected"]=false;row["upper_shift_rejected"]=false
                for (key,factor) in (("lower_shift_rejected",.999),("upper_shift_rejected",1.001))
                    shifted=deepcopy(net)
                    for suffix in ("min","max");shifted["bus"]["b1"][family*"_"*suffix].*=factor;end
                    row[key]=!physical_residuals(shifted,r).passed && !ivr_nlp_point_report(build_opf(shifted,IVRNLP(opts)),point).passed
                end
                d=result_dict(b,r);io=IOBuffer();write_result(d,io);seekstart(io)
                row["reader_roundtrip"]=isequal(read_result(io),d)
                row["result_file"]=joinpath("VOLTAGE_EXPORTS",label*".result.json")
                open(io->write_result(d,io),joinpath(dirname(abspath(output)),row["result_file"]),"w")
                row["accepted"]=r.solve.optimal && all(row[k] for k in ("physical_passed","own_full_passed","reverse_passed",
                    "objective_agrees","lower_shift_rejected","upper_shift_rejected","reader_roundtrip"))
                @assert net==original
            catch err
                err isa InterruptException && rethrow()
                row["accepted"]=false;row["error"]=sprint(showerror,err)
            end
            push!(rows,row)
            report=(;source_sha256=bytes2hex(sha256(read(@__FILE__))),cases=rows,
                note="Exploratory exact voltage-bound representation comparison. No isolated timing. Strict objective gate retained; equality full model supplies anchor. All failed outcomes retained.")
            open(io->JSON3.write(io,report),output,"w")
            println(label," ",get(row,"status","ERROR")," accepted=",row["accepted"]," ",get(row,"error",""));flush(stdout)
        end
    end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("Supply a JSON report path")
    voltage_equality_study(only(ARGS))
end
