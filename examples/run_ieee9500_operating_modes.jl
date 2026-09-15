# Compare the same explicit fixed DER point with hard and monitored branch limits.
# Scenario: preserve fixed bounds; otherwise choose upper active bounds and
# reactive power closest to zero. This is an explicit test scenario, not a
# reconstruction of the source deck's controller operating point.
using FormulationLab, JuMP, Clarabel, JSON3, SHA
net=JSON3.read(read(ARGS[1],String),Dict{String,Any})
opts=L3FOptions(unsupported=:approximate,transformer_impedance=:wye_terminal,objective=:feasibility)
hard=build_l3f_opf(net,Clarabel.Optimizer;options=opts)
dispatch=Dict{String,Any}()
for (id,g) in hard.network["generator"]
    p=Float64.(g["p_max"])
    q=clamp.(zeros(length(p)),Float64.(g["q_min"]),Float64.(g["q_max"]))
    all(isfinite,[p;q]) || error("Scenario requires finite explicit dispatch for $id")
    dispatch[id]=Dict("pg"=>p,"qg"=>q,"terminal_map"=>g["terminal_map"])
    for (field,values) in ((:p_generator,p),(:q_generator,q)),k in eachindex(values)
        @constraint(hard.model,hard.variables[field][(id,k)]==values[k]/opts.s_base)
    end
end
open(io->JSON3.write(io,dispatch),ARGS[2]*".dispatch.json","w")
out=Dict{String,Any}("input_sha256"=>bytes2hex(sha256(read(ARGS[1]))),"dispatch_scenario"=>"upper active bounds; nearest-to-zero reactive power within bounds", "generator_count"=>length(dispatch))
function record(label,b)
    set_silent(b.model);optimize!(b.model)
    report=l3f_limit_report(b)
    rows=filter(r->r["overloaded"],pop!(report,"entries"))
    sort!(rows;by=r->something(r["loading_ratio"],Inf),rev=true)
    out[label]=Dict("termination_status"=>string(termination_status(b.model)),"solve_seconds"=>solve_time(b.model),"limits"=>report,"overloads"=>rows,"model_class"=>string(l3f_model_class(b)))
    println(label," ",termination_status(b.model)," ",report["overload_count"]);flush(stdout)
    open(io->JSON3.write(io,out),ARGS[2],"w")
end
record("hard_limits_same_dispatch",hard)
pf=build_l3f_opf(net,Clarabel.Optimizer;options=FormulationLab._l3f_with_options(opts;operating_mode=:power_flow),dispatch)
record("power_flow",pf)
