# Diagnostic only: constraints are removed from one private optimization model.
# The input snapshot and production formulation remain unchanged.
# Usage: julia --project=test examples/diagnose_ieee9500_ratings.jl SNAPSHOT.json OUTPUT.json
using FormulationLab, JuMP, Clarabel, JSON3, LinearAlgebra, SHA
net=JSON3.read(read(ARGS[1],String),Dict{String,Any})
b=build_l3f_opf(net,Clarabel.Optimizer;options=L3FOptions(unsupported=:approximate,transformer_impedance=:wye_terminal))
m=b.model;set_silent(m);set_optimizer_attribute(m,"time_limit",90.)
out=Dict{String,Any}("input_sha256"=>bytes2hex(sha256(read(ARGS[1]))),"julia"=>string(VERSION),"clarabel"=>string(pkgversion(Clarabel)),"s_base_VA"=>b.options.s_base); save()=open(io->JSON3.write(io,out),ARGS[2],"w")
function solve(label)
 optimize!(m);r=Dict("status"=>string(termination_status(m)),"seconds"=>solve_time(m),"primal_status"=>string(primal_status(m)),"dual_status"=>string(dual_status(m)));out[label]=r
 println(label," ",r);flush(stdout);save()
end
solve("rated")
records=[]
for (family,table) in b.constraints
 startswith(string(family),"generator") && continue
 (occursin("current",string(family)) || occursin("apparent_power",string(family))) || continue
 for (key,ref) in table
  push!(records,(family=family,key=key,obj=constraint_object(ref)))
  delete(m,ref)
 end
end
solve("no_branch_ratings")
ratios=[]
if primal_status(m)==MOI.FEASIBLE_POINT
 for r in records
  v=value.(r.obj.func)
  ratio=r.obj.set isa MOI.SecondOrderCone ? norm(v[2:end])/v[1] : sqrt(sum(abs2,v[3:end])/max(2v[1]*v[2],1e-30))
  ratio>1.00001 && push!(ratios,Dict("family"=>string(r.family),"key"=>string(r.key),"ratio"=>ratio,"cone_value"=>v))
 end
end
out["unrated_violations"]=sort!(ratios;by=r->-r["ratio"]);save()
println("violated cones in unrated solution: ",length(ratios));flush(stdout)
for family in sort!(unique([r.family for r in records]);by=string)
 refs=[add_constraint(m,r.obj) for r in records if r.family==family]
 solve("only_"*string(family))
 foreach(r->delete(m,r),refs)
end
for (label,predicate) in [
 ("only_worst_triplex_to_leg1",r->r.family==:line_current && r.key==("Tpx338899C0","to",1)),
 ("only_ct5_T226192762B",r->r.family==:transformer_apparent_power && r.key==("center_tap","T226192762B","from",1))]
 refs=[add_constraint(m,r.obj) for r in records if predicate(r)]
 solve(label);foreach(r->delete(m,r),refs)
end
violated_keys=Set((row["family"],row["key"]) for row in ratios)
refs=[add_constraint(m,r.obj) for r in records if (string(r.family),string(r.key)) ∉ violated_keys]
solve("remove_only_unrated_violations")
foreach(r->delete(m,r),refs)
# Maximum receiving voltage with every branch rating removed. This checks
# whether controllable DER can possibly rescue the largest triplex overload.
w=b.variables[:w][("SX3122814C","1")]
@objective(m,Max,w)
solve("maximize_worst_triplex_voltage")
if primal_status(m)==MOI.FEASIBLE_POINT
 out["maximum_worst_triplex_voltage_V"]=sqrt(value(w))*b.bases.v_base["SX3122814C"]
 save()
end
