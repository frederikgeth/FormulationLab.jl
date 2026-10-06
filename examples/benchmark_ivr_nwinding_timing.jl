"""Balanced lifted multiwinding comparison. Run without concurrent Julia work."""
module IVRNWindingTimingStudy
using FormulationLab, JuMP, Ipopt, JSON3, SHA, LinearAlgebra
include("benchmark_ivr_profiles.jl")
include("../test/ivr_nwinding_limit_fixtures.jl")
const P=IVRProfileStudy
const SOURCE_SHA=bytes2hex(sha256(read(@__FILE__)))
const SETTINGS=merge(P.STRICT,(nlp_scaling_method="gradient-based",linear_solver="mumps",mumps_pivot_order=7))
save(path,x)=open(io->JSON3.write(io,x),path,"w")

function profiles(sb)
    [(;name="$(mode)__$(lifting)",options=begin
        old=_nwinding_nonstar_options(sb,lifting)
        IVRNLPOptions(;(k=>(k==:device_elimination ? mode : getfield(old,k)) for k in fieldnames(IVRNLPOptions))...)
    end) for mode in (:transformer_currents,:all_transformer_currents) for lifting in (:powers,:bounded_observations)]
end

"""Two four-period Williams blocks balance positions and immediate predecessors.

Confirmation reverses the complete schedule; no timing-dependent ordering.
"""
function orders(batch)
    batch in ("exploration","confirmation") || throw(ArgumentError("unknown batch"))
    block=[[mod1(i+k,4) for i in (1,2,4,3)] for k in 0:3]
    result=vcat(block,reverse.(block))
    batch=="confirmation" ? reverse(result) : result
end

function start_point(net)
    e=build_opf(net,IVRNLP()).electrical
    z,_,_=FormulationLab._linivr_reference(e;fixed_coordinates=e.fixed_source_coordinates)
    ev(row)=FormulationLab._linivr_eval(row,z)
    ACPoint(voltage=Dict(k=>(i==0 ? 0im : z[i]*e.vb) for (k,i) in e.voltage),
        currents=Dict((f,id)=>ComplexF64[ev(row)*e.ib for row in rows] for (f,id,_,rows,_) in e.devices))
end

function trial(net,p,reference,anchor,point)
    row,endpoint=P.trial(net,p,reference,anchor;solver_options=SETTINGS,initial_point=point)
    if endpoint!==nothing
        eq=_nwinding_nonstar_equations(net,endpoint)
        row["independent_equations"]=(;eq.ampere_turn_A,eq.leakage_V,eq.loss_identity_VA)
        row["independent_equations_passed"]=eq.ampere_turn_A<1e-6 && eq.leakage_V<1e-6 && eq.loss_identity_VA<1e-3
        # All generators in this declared fixture are single-phase devices.
        cost=sum(net["generator"]) do (id,g)
            u=endpoint.voltage[(g["bus"],g["terminal_map"][1])]-endpoint.voltage[(g["bus"],g["terminal_map"][2])]
            only(g["cost"])*real(u*conj(endpoint.currents[(:generator,id)][1]))/1000
        end
        row["independent_cost"]=cost
        row["independent_cost_passed"]=row["objective"]!==nothing && isapprox(cost,row["objective"];atol=1e-7,rtol=1e-6)
        row["accepted"] &= row["independent_equations_passed"] && row["independent_cost_passed"]
    end
    row,endpoint
end

function run(folder,batch;preflight_only=false)
    mkpath(folder);BLAS.set_num_threads(1);schedule=orders(batch);index=Any[]
    specs=[(;connection,roll,reverse,bounded,excitation,sb)
        for (connection,roll) in ((:YYYY,1),(:YDYY,1),(:YDYY,-1),(:YYYD,1),(:YYYD,-1),(:DYYY,1),(:DYYY,-1))
        for reverse in (false,true) for bounded in (false,true) for excitation in (false,true) for sb in (1e3,1e5)]
    batch=="confirmation" && reverse!(specs)
    for spec in specs
        (;connection,roll,reverse,bounded,excitation,sb)=spec
        stem=join((connection,roll,reverse,bounded,excitation,sb),"__")
        net=_nwinding_nonstar_case(;connection,roll,reverse,bounded,excitation)
        digest=bytes2hex(sha256(JSON3.write(net)));save(joinpath(folder,stem*".input.json"),net)
        candidates=profiles(sb);point=start_point(net)
        checks=map(candidates) do p
            b=build_opf(net,IVRNLP(p.options));r=ivr_nlp_point_report(b,point)
            passed=isempty(r.missing_channels) && length(r.variable_values)==num_variables(b.model) &&
                all(isfinite,values(r.variable_values)) && max(r.max_binding_residual_pu,r.max_reconstruction_residual_pu)<=1e-10
            (;name=p.name,passed,variables=num_variables(b.model),binding=r.max_binding_residual_pu,
                reconstruction=r.max_reconstruction_residual_pu,constraint_violation=r.max_constraint_violation)
        end
        report=Dict{String,Any}("case"=>spec,"batch"=>batch,"preflight"=>checks,"runner_sha256"=>SOURCE_SHA,
            "network_sha256"=>digest,"primary_metric"=>"ipopt_wall_s","solver_options"=>SETTINGS,
            "julia"=>string(VERSION),"jump"=>string(pkgversion(JuMP)),"ipopt"=>string(pkgversion(Ipopt)),
            "cpu"=>Sys.CPU_NAME,"blas_threads"=>BLAS.get_num_threads(),"julia_threads"=>Threads.nthreads(),
            "repetitions"=>length(schedule),"orders"=>[],"profiles"=>[],"shared_physical_start"=>true,
            "note"=>"Shared unloaded linear-circuit start, not a converged OPF. MOI.SolveTimeSec optimizer wall time only; compilation, build, cache transfer before backend call, extraction, audit and derivative queries excluded. All failures/outliers retained; no relaxed retries. Structure counts precede solver preprocessing and do not measure factor fill.")
        path=joinpath(folder,stem*".json");save(path,report)
        all(c.passed for c in checks) || error("unrepresentable shared start: $stem")
        if !preflight_only
            reference=build_opf(net,IVRNLP(;s_base=sb,objective_scale=1.,transformer_nameplate=:bmopftools))
            anchor=nothing
            for p in candidates
                row,endpoint=trial(net,p,reference,anchor,point)
                if anchor===nothing && row["accepted"];anchor=endpoint;report["anchor_profile"]=p.name;end
                push!(report["profiles"],Dict("name"=>p.name,"options"=>P.option_record(p.options),"warmup"=>row,"trials"=>Any[]))
                save(path,report)
            end
            for order in schedule
                push!(report["orders"],[candidates[j].name for j in order])
                for j in order
                    row,_=trial(net,candidates[j],reference,anchor,point)
                    anchor===nothing && (row["accepted"]=false)
                    push!(report["profiles"][j]["trials"],row)
                end
                save(path,report)
            end
            report["ranking"]=P.rank_profiles(report["profiles"],length(schedule);objective_atol=1e-7,objective_rtol=1e-6)
            report["position_balanced"]=all(count(o->o[k]==p.name,report["orders"])==length(schedule)/4
                for p in candidates for k in eachindex(candidates))
            @assert report["position_balanced"]
        end
        report["network_unchanged"]=bytes2hex(sha256(JSON3.write(net)))==digest
        @assert report["network_unchanged"]
        save(path,report);push!(index,(;case=stem,report=basename(path)))
        save(joinpath(folder,"INDEX.json"),index)
        println(stem," complete");flush(stdout)
    end
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS) in (2,3) || error("usage: output-folder exploration|confirmation [preflight]")
    IVRNWindingTimingStudy.run(ARGS[1],ARGS[2];preflight_only=length(ARGS)==3 && ARGS[3]=="preflight")
end
