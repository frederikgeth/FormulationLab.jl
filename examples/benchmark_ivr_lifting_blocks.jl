# Exact structural experiment; run separately from tests/docs and other timings.
module IVRLiftingBlockStudy
using FormulationLab, JuMP, JSON3, SHA, LinearAlgebra
include("benchmark_ivr_chains.jl")
const C=IVRChainStudy
const P=C.P
const SOURCE_SHA=bytes2hex(sha256(read(@__FILE__)))

"""Fixed total length/demand, optional asymmetric endpoint charging in SI.

Ratings and intermediate voltage limits remain in every model. `tight=true`
adds cheap terminal generation with a 400 VA capability circle, which is
intended to bind under the source-import objective; observed activity is reported.
`interior=true` instead supplies a resistive single-phase witness with a 229 V
midpoint upper limit. Without charging its optimum is independently 920 W.
`transformers=true` replaces every fourth line by a fixed 1:1 transformer with
declared leakage and a grounded secondary neutral; this is a separate network,
not a total-impedance-preserving substitution of the chain experiment.
"""
function case(;conductors=2,segments=12,charged=false,tight=false,interior=false,transformers=false)
    interior && (conductors!=2 || tight) && throw(ArgumentError("interior witness requires single-phase and tight=false"))
    transformers && (conductors!=2 || interior) && throw(ArgumentError("transformer panel requires single-phase and interior=false"))
    net=C.chain_case(;conductors,segments)
    if charged
        code=net["linecode"]["wire"]
        for j in 1:conductors
            code["B_from_$(j)_$(j)"]=1e-4*j;code["B_to_$(j)_$(j)"]=2e-4*j
            code["G_from_$(j)_$(j)"]=1e-6*j
        end
    end
    if tight
        tm=net["bus"]["b$segments"]["terminal_names"];n=conductors==2 ? 1 : 3
        net["generator"]=Dict("g"=>Dict("bus"=>"b$segments","terminal_map"=>copy(tm),
            "configuration"=>conductors==2 ? "SINGLE_PHASE" : "DELTA",
            "p_min"=>zeros(n),"p_max"=>fill(1000.,n),"q_min"=>fill(-300.,n),"q_max"=>fill(300.,n),
            "s_max"=>fill(400.,n),"cost"=>zeros(n)))
    end
    if interior
        code=net["linecode"]["wire"]
        for j in 1:2,k in j:2
            code["R_series_$(j)_$(k)"]=j==k ? .25 : 0.
            code["X_series_$(j)_$(k)"]=0.
        end
        net["load"]["d$segments"]["q_nom"]=[0.]
        net["bus"]["b$(segments÷2)"]["vpn_max"]=[229.]
        net["generator"]=Dict("g"=>Dict("bus"=>"b$segments","terminal_map"=>["a","n"],"configuration"=>"SINGLE_PHASE",
            "p_min"=>[0.],"p_max"=>[2000.],"q_min"=>[0.],"q_max"=>[0.],"s_max"=>[1500.],"cost"=>[0.]))
    end
    if transformers
        table=Dict{String,Any}()
        for k in 4:4:segments
            l=pop!(net["line"],"l$k")
            net["bus"][l["bus_to"]]["perfectly_grounded_terminals"]=["n"]
            table["tx$k"]=Dict("bus_from"=>l["bus_from"],"bus_to"=>l["bus_to"],
                "terminal_map_from"=>["a","n"],"terminal_map_to"=>["a","n"],
                "v_nom_from"=>230.,"v_nom_to"=>230.,"tap"=>1.,
                "r_series_from"=>.01,"x_series_from"=>.005,"r_series_to"=>.01,"x_series_to"=>.005,
                "i_max_from"=>[200.,200.],"i_max_to"=>[200.,200.])
        end
        net["transformer"]=Dict("single_phase"=>table)
    end
    net
end

function profiles(;charged=false)
    baseline=charged ? :off : :passive_chains
    [ (;name="full",options=IVRNLPOptions(objective=:source_import),solver_options=(linear_solver="mumps",mumps_pivot_order=0)),
      (;name="regional_existing",options=IVRNLPOptions(objective=:source_import,specialization=:conductor_regions,linear_elimination=baseline),solver_options=(linear_solver="mumps",mumps_pivot_order=0)),
      [(;name="blocks_$(lifting)",options=IVRNLPOptions(objective=:source_import,specialization=:conductor_regions,
           linear_elimination=:passive_blocks,lifting=lifting),solver_options=(linear_solver="mumps",mumps_pivot_order=0))
       for lifting in (:off,:powers,:bounded_observations)]...,
      (;name="full_powers",options=IVRNLPOptions(objective=:source_import,lifting=:powers),solver_options=(linear_solver="mumps",mumps_pivot_order=0))]
end

"""One unloaded physical circuit point, shared by every representation.

Flat zero-current starts generally violate charged-section linear equations and
cannot be represented by their elimination. The linear circuit solve supplies
starts only; it does not fix operating currents or constrain the OPF.
"""
function start_point(net)
    e=build_opf(net,IVRNLP()).electrical
    z,_,_=FormulationLab._linivr_reference(e;fixed_coordinates=e.fixed_source_coordinates)
    ev(row)=FormulationLab._linivr_eval(row,z)
    ACPoint(voltage=Dict(k=>(i==0 ? 0im : z[i]*e.vb) for (k,i) in e.voltage),
        currents=Dict((f,id)=>ComplexF64[ev(row)*e.ib for row in rows] for (f,id,_,rows,_) in e.devices))
end

function benchmark(output;conductors=2,segments=12,charged=false,tight=false,interior=false,transformers=false,repetitions=12)
    repetitions>0 && repetitions%12==0 || throw(ArgumentError("twelve-sweep multiples balance six profiles"))
    net=case(;conductors,segments,charged,tight,interior,transformers);candidates=profiles(;charged);point=start_point(net)
    checks=map(candidates) do profile
        b=build_opf(net,IVRNLP(profile.options));r=ivr_nlp_point_report(b,point)
        isempty(r.missing_channels) && length(r.variable_values)==num_variables(b.model) &&
            max(r.max_binding_residual_pu,r.max_reconstruction_residual_pu)<=1e-10 || error("start mismatch")
        (;profile=profile.name,binding=r.max_binding_residual_pu,reconstruction=r.max_reconstruction_residual_pu)
    end
    open(io->JSON3.write(io,net),output*".input.json","w")
    metadata=(;conductors,segments,charged,tight,interior,transformers,repetitions,source_sha256=SOURCE_SHA,checks,
        initial_state="shared unloaded linear circuit, not a converged OPF",primary_metric="ipopt_wall_s",
        note="Identical original network for all six profiles. Chain cases keep total line length/demand fixed; transformer variants replace every fourth line with fixed leakage and grounded secondary. AMD, twelve balanced sweeps. Compilation/start assignment/export/audits excluded from primary score. All rejected and slow trials retained.")
    open(io->JSON3.write(io,metadata),output*".manifest.json","w")
    report=P.benchmark(net,output;repetitions,candidates,initial_point=point,source_sha256=SOURCE_SHA)
    report["position_balanced"]=all(count(o->o[k]==p.name,report["orders"])==repetitions/length(candidates) for p in candidates for k in eachindex(candidates))
    report["position_balanced"] || error("unbalanced profile position")
    open(io->JSON3.write(io,report),output,"w")
    report
end
end
