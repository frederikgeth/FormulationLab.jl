"""Finite secondary grounds and an independent multiwinding ground-unit policy.

This runner is a correctness preflight. Its single trials are not speed evidence.
"""
module IVRNWindingGroundStudy
using FormulationLab, JuMP, Ipopt, JSON3, LinearAlgebra, SHA
include("benchmark_ivr_nwinding_coordinates.jl")
const C=IVRNWindingCoordinateStudy
const N=C.N
const S=N.S
const MODES=(:off,:voltage,:regional_voltage,:regional_multiwinding_voltage)
clone(o;kwargs...)=IVRNLPOptions(;merge((; (k=>deepcopy(getfield(o,k)) for k in fieldnames(IVRNLPOptions))...), (;kwargs...))...)

"""Replace declared secondary references with explicit finite shunts.

This defines a new physical fixture; scaling never performs the replacement.
Delta's declared reference conductor is retained as a finite physical ground,
not inferred from a characteristic nominal voltage or a missing neutral.
"""
function network(units;admittance=.5+0im,earth_return_S=0.0)
    isfinite(admittance) && real(admittance)>=0 && !iszero(admittance) ||
        throw(ArgumentError("finite nonzero passive ground admittance required"))
    earth_return_S isa Real && isfinite(earth_return_S) && earth_return_S>=0 ||
        throw(ArgumentError("finite nonnegative phase-to-earth conductance required"))
    net,templates=N.network(units);net["shunt"]=Dict{String,Any}()
    for tx in values(net["transformer"]["n_winding"]),w in tx["windings"][2:end]
        bus=w["bus"];d=net["bus"][bus]
        for t in get(d,"perfectly_grounded_terminals",String[])
            net["shunt"]["finite_$(bus)_$t"]=Dict("bus"=>bus,"terminal_map"=>[t],
                "G_1_1"=>Float64(real(admittance)),"B_1_1"=>Float64(imag(admittance)))
        end
        d["perfectly_grounded_terminals"]=String[]
        if earth_return_S>0
            net["shunt"]["earth_return_$bus"]=Dict("bus"=>bus*"_end", "terminal_map"=>[first(w["terminal_map"])],
                "G_1_1"=>Float64(earth_return_S),"B_1_1"=>0.)
        end
    end
    net,templates
end

function profiles(net,workload,representation)
    control=last(C.profiles(net,workload,representation)).options
    [(;name=string(mode),options=clone(control;ground_scaling=mode)) for mode in MODES]
end

function run(folder;units=(2,8),admittances=(.5+0im,1e8+0im),earth_return_S=0.0)
    mkpath(folder);BLAS.set_num_threads(1);index=NamedTuple[]
    for n in units,y in admittances,workload in (:cost,:tracking)
        net,templates=network(n;admittance=y,earth_return_S);start=S.start_point(net)
        reference=build_opf(net,IVRNLP(objective=:power,power_terms=N.terms(net,workload),transformer_nameplate=:bmopftools))
        digest=bytes2hex(sha256(JSON3.write(net)))
        for representation in [p.name for p in N.profiles(net,workload,1e5)]
            stem="$(n)__$(real(y))_$(imag(y))__$(workload)__$(representation)"
            S.save(joinpath(folder,stem*".input.json"),net)
            rows=[];anchor=nothing
            for p in profiles(net,workload,representation)
                row,point=N.trial(net,templates,p,reference,anchor,start)
                anchor===nothing && row["accepted"] && (anchor=point)
                if point!==nothing
                    # A nonzero finite-ground voltage is physical, even if tiny.
                    row["finite_grounds"]=[let v=point.voltage[(g["bus"],only(g["terminal_map"]))], yg=complex(g["G_1_1"],g["B_1_1"])
                        (;id,bus=g["bus"],terminal=only(g["terminal_map"]),vr=real(v),vi=imag(v),
                            current_A=abs(yg*v),power_W=real(v*conj(yg*v)))
                        end for (id,g) in sort!(collect(net["shunt"]);by=first)]
                end
                push!(rows,(;name=p.name,options=N.P.option_record(p.options),trial=row))
                report=(;units=n,admittance=(;real=real(y),imag=imag(y)),earth_return_S,workload,representation,
                    network_sha256=digest,network_unchanged=bytes2hex(sha256(JSON3.write(net)))==digest,
                    solver_options=N.SETTINGS,shared_physical_start=true,profiles=rows,
                    timing_eligible=false,ranking=nothing,
                    note="Single-trial physical preflight; all errors and rejected endpoints retained. Only ground_scaling varies. No compilation penalty or speed ranking.")
                S.save(joinpath(folder,stem*".json"),report)
            end
            push!(index,(;case=stem,report=stem*".json"));S.save(joinpath(folder,"INDEX.json"),index)
            println(stem," accepted=",count(r->r.trial["accepted"],rows),"/4");flush(stdout)
        end
    end
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==1 || error("usage: output-folder")
    IVRNWindingGroundStudy.run(only(ARGS))
end
