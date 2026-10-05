module IVRPowerBaseStudy
using FormulationLab, JuMP, JSON3, SHA
include("benchmark_ivr_transformer_stress.jl")
const H=IVRTransformerStressStudy

"""Independent LV branches share an ideal MV supply; SI optimum is additive.

Each branch is the existing 2 kW analytical circuit. Thus MV aggregates several
LV power flows rather than carrying only one branch's power through a cascade.
"""
function case(;limit=:capability,branches=4,segments=12)
    branches isa Integer && branches>=1 || throw(ArgumentError("positive integer branches required"))
    template=H.C.case(;limit,segments)
    abs(branches*H.C.expected(limit).current_A/10)<100 ||
        throw(ArgumentError("analytical panel requires slack upstream current ratings"))
    net=deepcopy(template)
    net["bus"]=Dict{String,Any}(k=>deepcopy(template["bus"][k]) for k in ("hv","mv"))
    net["transformer"]["single_phase"]=Dict("upstream"=>deepcopy(template["transformer"]["single_phase"]["upstream"]))
    for family in ("line","load","generator","shunt");net[family]=Dict{String,Any}();end
    for branch in 1:branches
        rename(b)=b in ("hv","mv") ? b : "lv$(branch)_$b"
        for (b,d) in template["bus"]
            b in ("hv","mv") && continue
            net["bus"][rename(b)]=deepcopy(d)
        end
        tx=deepcopy(template["transformer"]["single_phase"]["downstream"])
        tx["bus_to"]=rename(tx["bus_to"])
        net["transformer"]["single_phase"]["downstream$branch"]=tx
        for family in ("line","load","generator","shunt"),(id,d) in template[family]
            copy=deepcopy(d)
            for key in ("bus","bus_from","bus_to");haskey(copy,key) && (copy[key]=rename(copy[key]));end
            net[family]["lv$(branch)_$id"]=copy
        end
    end
    net
end

function profiles(net;nlp_scaling_method="none")
    nlp_scaling_method in ("none","gradient-based") || throw(ArgumentError("unknown solver scaling policy"))
    seeds(lv)=merge(Dict("hv"=>1e6,"mv"=>1e5),Dict(b=>Float64(lv) for b in keys(net["bus"]) if endswith(b,"_b0")))
    specs=[("common_10k",1e4,Dict{String,Float64}()),("common_1k",1e3,Dict{String,Float64}()),
        ("common_100k",1e5,Dict{String,Float64}()),("common_1M",1e6,Dict{String,Float64}()),
        ("regional_LV_1k",1e4,seeds(1e3)),("regional_LV_10k",1e4,seeds(1e4))]
    [(;name,options=IVRNLPOptions(;s_base=sb,current_power_bases=bases,objective_scale=1e4,
        objective=:source_import,transformer_scaling=:nominal,row_scaling=:composed,ground_scaling=:voltage),
        solver_options=(linear_solver="mumps",mumps_pivot_order=0,nlp_scaling_method)) for (name,sb,bases) in specs]
end

function benchmark(output;limit=:capability,branches=4,segments=12,nlp_scaling_method="none",repetitions=12)
    repetitions>0 && repetitions%12==0 || throw(ArgumentError("twelve-sweep multiples required"))
    net=case(;limit,branches,segments);candidates=profiles(net;nlp_scaling_method);start=H.S.L.start_point(net)
    expected=branches*H.C.expected(limit).source_W
    checks=map(candidates) do p
        b=build_opf(net,IVRNLP(p.options));r=ivr_nlp_point_report(b,start)
        isempty(r.missing_channels) && length(r.variable_values)==num_variables(b.model) &&
            all(isfinite,values(r.variable_values)) &&
            max(r.max_binding_residual_pu,r.max_reconstruction_residual_pu)<=1e-10 || error("unrepresentable start")
        (;name=p.name,variables=num_variables(b.model),objective_scale=b.numerical_diagnostics[:objective_scale],
            ground=b.numerical_diagnostics[:ground_scaling_report],transformer=b.numerical_diagnostics[:transformer_scaling_report])
    end
    open(io->JSON3.write(io,net),output*".input.json","w")
    open(io->JSON3.write(io,(;limit,branches,segments,expected_source_W=expected,checks,
        note="Manufactured aggregate MV supply with independent LV branches. Four common power bases versus two current-coordinate-only regional power-base declarations. Numerical objective divisor fixed at 10k in every arm. Dispatch, lifted powers and ground policy remain on assembly units; regional current option does not rebase them. Same SI input/start, composed rows, MUMPS AMD, explicit solver scaling, twelve balanced sweeps. Ipopt wall time only.")),output*".manifest.json","w")
    r=H.S.P.benchmark(net,output;repetitions,candidates,initial_point=start,
        source_sha256=bytes2hex(sha256(read(@__FILE__))))
    r["position_balanced"]=all(count(o->o[k]==p.name,r["orders"])==repetitions/6 for p in candidates for k in 1:6)
    r["position_balanced"] || error("unbalanced positions")
    r["analytical_expected"]=(;source_W=expected)
    r["analytical_admission"]=all(get(t,"accepted",false) && isapprox(t["objective"],expected;atol=1e-4,rtol=0.)
        for p in r["profiles"] for t in [p["warmup"];p["trials"]])
    r["analytical_admission"] || (r["ranking"]["fastest_ipopt"]=nothing)
    open(io->JSON3.write(io,r),output,"w")
    r
end
end
