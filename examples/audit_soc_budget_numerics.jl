# Diagnostic only: compare a larger-budget primal point with the smaller model.
# It does not select or add cuts to a production model.
include("benchmark_soc_controlled.jl")
manifest=JSON3.read(read(joinpath(@__DIR__,"results/reduction_manifest.json"),String),Vector{Dict{String,Any}})
net,sb,_,_=prepare_case(manifest[2]["path"]);p=prepare_network(net;warn=false)
builds=Dict();runs=Dict()
for budget in (2,8)
    b=build_opf(p,IVRSOC(profile=:balanced,max_triplets=budget,s_base=sb,objective=:source_import);optimizer=nothing)
    builds[budget]=b;runs[string(budget)]=controlled_run(b,p,(refinement=30,))
end
small,large=builds[2],builds[8]
@assert small.electrical.nullspace==large.electrical.nullspace
@assert small.electrical.numerical_diagnostics[:fixed_strengthening].triplets==large.electrical.numerical_diagnostics[:fixed_strengthening].triplets[1:2]
# This case has constant-power loads and no auxiliary variables after strengthening.
@assert all(lowercase(get(d,"model","constant_power"))=="constant_power" for d in values(p.network["load"]))
a,b=all_variables(small.model),all_variables(large.model)
point=Dict(v=>value(b[i]) for (i,v) in enumerate(a))
violations=primal_feasibility_report(small.model,point)
worst=sort!(collect(violations);by=last,rev=true)
result=Dict("case"=>manifest[2]["name"],"runs"=>runs,
    "larger_point_objective_in_smaller_W"=>value(v->point[v],objective_function(small.model))*small.electrical.objective_scale,
    "max_smaller_constraint_violation"=>maximum(values(violations);init=0.),
    "worst_constraints"=>[Dict("violation"=>e,"constraint"=>first(string(c),min(length(string(c)),600))) for (c,e) in first(worst,min(5,length(worst)))])
open(io->JSON3.write(io,finite(result)),ARGS[1],"w")
