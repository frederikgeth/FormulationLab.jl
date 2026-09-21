using FormulationLab, JSON3, JuMP, Clarabel
net=JSON3.read(read(ARGS[1],String),Dict{String,Any})
# Input is an SI BMOPF snapshot exported with the patched PowerIO library.
opts=L3FOptions(topology=length(ARGS)>2 ? Symbol(ARGS[3]) : :radial,unsupported=:approximate,transformer_impedance=:wye_terminal)
println("CHECK");flush(stdout)
r=check_l3f_applicability(net;options=opts)
println(r.status);flush(stdout)
counts=Dict{String,Int}(); errors=[]
for f in r.findings
 counts[f.code]=get(counts,f.code,0)+1
 f.severity==:error && push!(errors,Dict("code"=>f.code,"id"=>f.id,"message"=>f.message))
end
out=Dict{String,Any}("status"=>r.status,"counts"=>counts,"errors"=>errors)
println(counts);flush(stdout)
open(io->JSON3.write(io,out),ARGS[2],"w")
if is_l3f_applicable(r)
 println("BUILD");flush(stdout)
 t=@elapsed b=build_l3f_opf(net,Clarabel.Optimizer;options=opts)
 out["build_seconds"]=t
 set_optimizer_attribute(b.model,"time_limit",120.0)
 println("SOLVE");flush(stdout)
 t=@elapsed optimize!(b.model)
 out["wall_solve_seconds"]=t;out["termination_status"]=string(termination_status(b.model))
 out["solve_seconds"]=solve_time(b.model);out["variables"]=num_variables(b.model)
 out["primal_status"]=string(primal_status(b.model));out["dual_status"]=string(dual_status(b.model))
 primal_status(b.model)==MOI.FEASIBLE_POINT && (out["objective"]=objective_value(b.model))
 open(io->JSON3.write(io,out),ARGS[2],"w")
end
