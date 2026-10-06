"""Selective coil observations at fixed power lifting and electrical reduction."""
module IVRCoilObservationStudy
using FormulationLab, JuMP, Ipopt, JSON3, SHA, LinearAlgebra
include("benchmark_ivr_nwinding_coordinates.jl")
const C=IVRNWindingCoordinateStudy
const N=C.N
const S=N.S
clone(o;kwargs...)=IVRNLPOptions(;merge((; (k=>deepcopy(getfield(o,k)) for k in fieldnames(IVRNLPOptions))...), (;kwargs...))...)
function profiles(net,workload,device_elimination)
    device_elimination in (:transformer_currents,:all_transformer_currents) || throw(ArgumentError("unknown device elimination"))
    base=last(C.profiles(net,workload,"$(device_elimination)__bounded_observations")).options
    [(;name="powers",options=clone(base;lifting=:powers));
     [(;name=string(selection),options=clone(base;observation_selection=selection))
      for selection in (:coil_voltages,:coil_currents,:coils,:all)]]
end

"""Composed affine supports, before any observation auxiliaries are introduced.

Count distinct real native variables, using the same definition as the lifting
threshold. These are support counts, not nonlinear Jacobian or KKT fill counts.
"""
function supports(build)
    rows=NamedTuple[]
    for (family,id,v,i,_) in build.electrical.devices
        family in (:transformer_coil,:transformer_coil_from,:transformer_coil_to) || continue
        for (quantity,observations) in ((:voltage,v),(:current,i)),(k,row) in enumerate(observations)
            u=FormulationLab._linivr_eval(row,build.state)
            n=length(Set(var for x in (real(u),imag(u)) for (var,a) in x.terms if !iszero(a)))
            push!(rows,(;family,id,coil=k,quantity,real_support=n))
        end
    end
    rows
end

function run(folder;units=(2,8,24))
    mkpath(folder);BLAS.set_num_threads(1);index=NamedTuple[]
    for n in units,workload in (:cost,:tracking),elimination in (:transformer_currents,:all_transformer_currents)
        net,templates=N.network(n);start=S.start_point(net);candidates=profiles(net,workload,elimination)
        reference=build_opf(net,IVRNLP(objective=:power,power_terms=N.terms(net,workload),transformer_nameplate=:bmopftools))
        shape=build_opf(net,IVRNLP(first(candidates).options));support=supports(shape)
        stem="$(n)__$(workload)__$(elimination)";digest=bytes2hex(sha256(JSON3.write(net)))
        S.save(joinpath(folder,stem*".input.json"),net)
        rows=[];anchor=nothing
        for p in candidates
            row,point=N.trial(net,templates,p,reference,anchor,start)
            anchor===nothing && row["accepted"] && (anchor=point)
            push!(rows,(;name=p.name,options=N.P.option_record(p.options),trial=row))
            S.save(joinpath(folder,stem*".json"),(;units=n,workload,elimination,profiles=rows,support,
                network_sha256=digest,network_unchanged=bytes2hex(sha256(JSON3.write(net)))==digest,
                solver_options=N.SETTINGS,shared_physical_start=true,timing_eligible=false,ranking=nothing,
                note="Single-trial preflight. Fixed power lifting, SI objective, units, reductions and bounds; only observation selection varies among bounded-observation arms. Powers-only control retained. Backend derivative structures are not KKT fill. All failures retained; no speed ranking or compilation penalty."))
        end
        push!(index,(;case=stem,report=stem*".json"));S.save(joinpath(folder,"INDEX.json"),index)
        println(stem," accepted=",count(r->r.trial["accepted"],rows),"/5");flush(stdout)
    end
end

"""Odd-order Williams design: every position and within-sweep predecessor occurs twice.

The ten sweeps balance five arms. Between-sweep transitions are not balanced.
Confirmation reverses the sweep order, independently of observed outcomes.
"""
function orders(batch)
    batch in ("exploration","confirmation") || throw(ArgumentError("unknown batch"))
    block=[[mod1(i+k,5) for i in (1,2,5,3,4)] for k in 0:4]
    result=vcat(block,reverse.(block))
    batch=="confirmation" ? reverse(result) : result
end

function checkpoint(path,report)
    temporary=path*".pending"
    S.save(temporary,report)
    mv(temporary,path;force=true)
end

"""Persist intent before a solve and its returned result afterwards.

A surviving `started` entry means completion is unknown, not that no solve ran.
An exception leaves earlier results intact and propagates to the caller.
"""
function record_trial!(f,path,report,j,phase,sweep)
    phase in ("warmup","measured") || throw(ArgumentError("unknown phase"))
    p=report["profiles"][j]
    entry=Dict{String,Any}("profile"=>p["name"],"phase"=>phase,"sweep"=>sweep,"status"=>"started")
    push!(report["ledger"],entry);checkpoint(path,report)
    row,point=f()
    if phase=="warmup";p["warmup"]=row;else;push!(p["trials"],row);end
    entry["status"]="completed";entry["accepted"]=row["accepted"]
    checkpoint(path,report)
    row,point
end

"""Repeated five-arm comparison; external whole-campaign isolation is mandatory.

Each batch has twelve cells, five excluded warmups per cell and ten measured
sweeps. Use a fresh Julia process for confirmation. Rankings in individual cell
files are provisional until the external isolation and completeness audit passes.
"""
function run_timing(folder,batch;units=(2,8,24))
    schedule=orders(batch)
    isdir(folder) && !isempty(readdir(folder)) && throw(ArgumentError("output folder must be empty"))
    mkpath(folder);BLAS.set_num_threads(1);index=Any[]
    cases=[(;units=n,workload,elimination) for n in units for workload in (:cost,:tracking)
        for elimination in (:transformer_currents,:all_transformer_currents)]
    batch=="confirmation" && reverse!(cases)
    for spec in cases
        n=spec.units;(;workload,elimination)=spec
        net,templates=N.network(n);start=S.start_point(net);candidates=profiles(net,workload,elimination)
        reference=build_opf(net,IVRNLP(objective=:power,power_terms=N.terms(net,workload),transformer_nameplate=:bmopftools))
        stem="$(n)__$(workload)__$(elimination)";digest=bytes2hex(sha256(JSON3.write(net)))
        S.save(joinpath(folder,stem*".input.json"),net)
        report=Dict{String,Any}("case"=>spec,"batch"=>batch,"network_sha256"=>digest,
            "runner_sha256"=>bytes2hex(sha256(read(@__FILE__))),"profiles"=>[
                Dict{String,Any}("name"=>p.name,"options"=>N.P.option_record(p.options),"warmup"=>nothing,"trials"=>Any[])
                for p in candidates],"planned_orders"=>[[candidates[j].name for j in o] for o in schedule],
            "orders"=>Any[],"ledger"=>Any[],"repetitions"=>length(schedule),"complete"=>false,
            "ranking"=>nothing,"timing_eligible"=>false,"primary_metric"=>"ipopt_wall_s",
            "solver_options"=>N.SETTINGS,"julia"=>string(VERSION),"jump"=>string(pkgversion(JuMP)),
            "ipopt"=>string(pkgversion(Ipopt)),"cpu"=>Sys.CPU_NAME,"blas_threads"=>BLAS.get_num_threads(),
            "julia_threads"=>Threads.nthreads(),"shared_physical_start"=>true,
            "note"=>"Fixed SI objective, per-unit coordinates, reductions, bounds and shared unloaded physical start. One excluded warmup per arm; ten Williams sweeps. Confirmation reverses cells and sweeps in a fresh process. Only optimizer-call wall time is ranked; build/extraction/audit costs excluded. All failures and outliers retained. Cell ranking is provisional: external whole-campaign isolation and completeness audit required. Within-sweep predecessor balance does not cover sweep boundaries.")
        path=joinpath(folder,stem*".json");checkpoint(path,report);anchor=nothing
        for (j,p) in enumerate(candidates)
            row,point=record_trial!(path,report,j,"warmup",0) do
                N.trial(net,templates,p,reference,anchor,start)
            end
            if anchor===nothing && row["accepted"]
                anchor=point;report["anchor_profile"]=p.name;checkpoint(path,report)
            end
        end
        for (sweep,order) in enumerate(schedule)
            for j in order
                record_trial!(path,report,j,"measured",sweep) do
                    row,point=N.trial(net,templates,candidates[j],reference,anchor,start)
                    anchor===nothing && (row["accepted"]=false)
                    row,point
                end
            end
            push!(report["orders"],report["planned_orders"][sweep]);checkpoint(path,report)
        end
        report["ranking"]=N.P.rank_profiles(report["profiles"],length(schedule);objective_atol=1e-7,objective_rtol=1e-6)
        report["network_unchanged"]=bytes2hex(sha256(JSON3.write(net)))==digest
        @assert report["network_unchanged"]
        report["complete"]=true;checkpoint(path,report)
        push!(index,(;case=stem,report=basename(path)));checkpoint(joinpath(folder,"INDEX.json"),index)
        println(stem," complete; batch=",batch);flush(stdout)
    end
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS) in (1,2) || error("usage: output-folder [exploration|confirmation]")
    length(ARGS)==1 ? IVRCoilObservationStudy.run(only(ARGS)) : IVRCoilObservationStudy.run_timing(ARGS...)
end
