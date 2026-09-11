# Static coefficient census only: no incumbent and no coefficient removal.
include("benchmark_soc_controlled.jl")
function census(b)
    a=Float64[]
    visit(x::JuMP.VariableRef)=push!(a,1.)
    visit(x::JuMP.GenericAffExpr)=append!(a,abs.(collect(values(x.terms))))
    visit(x::AbstractVector)=foreach(visit,x)
    visit(x::Number)=nothing
    for (F,S) in list_of_constraint_types(b.model), c in all_constraints(b.model,F,S)
        visit(constraint_object(c).func)
    end
    nonzero=filter(!iszero,a)
    Dict("stored_coefficients"=>length(a),"nonzero_coefficients"=>length(nonzero),
        "small_nonzero_counts"=>Dict(string(t)=>count(<(t),nonzero) for t in (1e-16,1e-14,1e-12,1e-10,1e-8,1e-6)),
        "largest"=>maximum(nonzero;init=0.))
end
manifest=JSON3.read(read(joinpath(@__DIR__,"results/reduction_manifest.json"),String),Vector{Dict{String,Any}})
rows=[]
for c in manifest[2:3]
    net,sb,_,_=prepare_case(c["path"]);p=prepare_network(net;warn=false)
    for basis in (:auto,:sparse)
        v=(name=string(basis),strength=:linear,size=32,basis=basis,refinement=30)
        b=controlled_model(p,sb,v)
        push!(rows,Dict("case"=>c["name"],"basis"=>basis,"census"=>census(b)))
    end
end
open(io->JSON3.write(io,rows),ARGS[1],"w")
