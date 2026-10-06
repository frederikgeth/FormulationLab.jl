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
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("usage: output-folder")
    IVRCoilObservationStudy.run(only(ARGS))
end
