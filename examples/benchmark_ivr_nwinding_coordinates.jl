"""Factorial multiwinding nominal coordinates and KCL row-unit cap.

All four arms are retained, including rejected endpoints. Timing interpretation
requires whole-campaign isolation; preflight rows are never speed evidence.
"""
module IVRNWindingCoordinateStudy
using FormulationLab, JuMP, Ipopt, JSON3, SHA, LinearAlgebra
include("benchmark_ivr_nwinding_regional.jl")
const U=IVRNWindingRegionalStudy
const N=U.N
const P=N.P
const S=N.S

function profiles(net,workload,representation)
    control=first(U.profiles(net,workload,representation)).options
    [(;name="$(mode)__cap_$(cap===nothing ? "none" : "1000A")",
        factors=(;nominal_policy=mode,kcl_row_max_base_A=cap),
        options=IVRNLPOptions(; (k=>(k==:transformer_scaling ? mode :
            k==:kcl_row_max_base ? cap : deepcopy(getfield(control,k)))
            for k in fieldnames(IVRNLPOptions))...))
        for mode in (:nominal,:nominal_multiwinding) for cap in (nothing,1000.)]
end

function run(folder,batch;preflight_only=false)
    batch in ("exploration","confirmation") || throw(ArgumentError("unknown batch"))
    mkpath(folder);BLAS.set_num_threads(1);index=Any[]
    representations=[p.name for p in N.profiles(first(N.network(2)),:cost,1e3)]
    cases=[(;units,workload,representation) for units in (2,8,24)
        for workload in (:cost,:tracking) for representation in representations]
    batch=="confirmation" && reverse!(cases)
    for spec in cases
        (;units,workload,representation)=spec
        stem="$(units)__$(workload)__$(representation)"
        net,templates=N.network(units);digest=bytes2hex(sha256(JSON3.write(net)))
        candidates=profiles(net,workload,representation);start=S.start_point(net)
        reference=build_opf(net,IVRNLP(;objective=:power,power_terms=N.terms(net,workload),transformer_nameplate=:bmopftools))
        S.save(joinpath(folder,stem*".input.json"),net)
        report=Dict{String,Any}("case"=>spec,"batch"=>batch,"network_sha256"=>digest,
            "runner_sha256"=>bytes2hex(sha256(read(@__FILE__))),"profiles"=>[],"orders"=>[],"repetitions"=>(preflight_only ? 0 : 8),
            "primary_metric"=>"ipopt_wall_s","solver_options"=>N.SETTINGS,
            "julia"=>string(VERSION),"jump"=>string(pkgversion(JuMP)),"ipopt"=>string(pkgversion(Ipopt)),
            "cpu"=>Sys.CPU_NAME,"blas_threads"=>BLAS.get_num_threads(),"julia_threads"=>Threads.nthreads(),
            "shared_physical_start"=>true,"buses"=>length(net["bus"]),"lines"=>length(net["line"]),
            "note"=>"Factorial nominal-voltage policy and KCL row cap. Fixed primary/secondary current-power seeds 1 kVA, grid 100 kVA, assembly 100 kVA, generators 1 kVA, objective divisor 1 and auxiliaries 500 VA. Composed row normalization responds to columns. Manufactured networks; strict gates; no compilation penalty. Isolation must be established externally before timing interpretation.")
        path=joinpath(folder,stem*".json");anchor=nothing
        for p in candidates
            row,point=N.trial(net,templates,p,reference,anchor,start)
            if anchor===nothing && row["accepted"];anchor=point;report["anchor_profile"]=p.name;end
            push!(report["profiles"],Dict("name"=>p.name,"factors"=>p.factors,
                "options"=>P.option_record(p.options),"warmup"=>row,"trials"=>Any[]))
            S.save(path,report)
        end
        for order in (preflight_only ? Vector{Int}[] : S.orders(batch))
            push!(report["orders"],[candidates[j].name for j in order])
            for j in order
                row,_=N.trial(net,templates,candidates[j],reference,anchor,start)
                anchor===nothing && (row["accepted"]=false)
                push!(report["profiles"][j]["trials"],row)
            end
            S.save(path,report)
        end
        report["ranking"]=preflight_only ? nothing : P.rank_profiles(report["profiles"],8;objective_atol=1e-7,objective_rtol=1e-6)
        report["position_balanced"]=preflight_only || all(count(o->o[k]==p.name,report["orders"])==2 for p in candidates for k in eachindex(candidates))
        report["network_unchanged"]=bytes2hex(sha256(JSON3.write(net)))==digest
        @assert report["position_balanced"] && report["network_unchanged"]
        S.save(path,report);push!(index,(;case=stem,report=basename(path)))
        S.save(joinpath(folder,"INDEX.json"),index)
        println(stem," complete; preflight=",preflight_only);flush(stdout)
    end
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("usage: output-folder exploration|confirmation")
    IVRNWindingCoordinateStudy.run(ARGS...)
end
