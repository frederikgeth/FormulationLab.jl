"""Transfer the frozen six power-base policies to coupled unbalanced circuits.

This manufactured panel has no independently proved global optimum. Admission
uses original SI physics, original bounds, bidirectional formulation maps and
objective agreement. A local Ipopt solution is not a global certificate.
"""
module IVRUnbalancedPowerBaseStudy
using FormulationLab, JuMP, JSON3, SHA
include("benchmark_ivr_power_bases.jl")
const G=IVRPowerBaseStudy
const P=G.H.S.P

function case(;limit=:capability,branches=2,segments=12)
    limit in (:capability,:current,:voltage) || throw(ArgumentError("unknown limit"))
    branches isa Integer && branches>=1 || throw(ArgumentError("positive integer branches required"))
    segments isa Integer && segments>=1 || throw(ArgumentError("positive integer segments required"))
    phases=["a","b","c"];terminals=[phases;"n"]
    buses=Dict{String,Any}(b=>Dict("terminal_names"=>copy(terminals),
        "perfectly_grounded_terminals"=>["n"]) for b in ("hv","mv"))
    upstream=Dict(p=>Dict("bus_from"=>"hv","bus_to"=>"mv",
        "terminal_map_from"=>[p,"n"],"terminal_map_to"=>[p,"n"],
        "v_nom_from"=>11000.,"v_nom_to"=>2300.,
        "r_series_from"=>2.,"x_series_from"=>4.,"r_series_to"=>.02,"x_series_to"=>.04,
        "i_max_from"=>[100.,100.],"i_max_to"=>[100.,100.]) for p in phases)
    txs=Dict{String,Any}();lines=Dict{String,Any}();loads=Dict{String,Any}()
    generators=Dict{String,Any}();shunts=Dict{String,Any}()
    for branch in 1:branches
        prefix="lv$(branch)_";last=prefix*"b$segments";weight=1+.1(branch-1)
        buses[prefix*"b0"]=Dict("terminal_names"=>copy(terminals),"perfectly_grounded_terminals"=>["n"])
        txs["downstream$branch"]=Dict("bus_from"=>"mv","bus_to"=>prefix*"b0",
            "terminal_map_from"=>phases,"terminal_map_to"=>terminals,
            "v_nom_from"=>2300.,"v_nom_to"=>230.,"tap"=>1.,
            "r_series_from"=>.5,"x_series_from"=>1.,"r_series_to"=>.015,"x_series_to"=>.03,
            "i_max_from"=>fill(100.,3),"i_max_to"=>fill(100.,4))
        for k in 1:segments
            buses[prefix*"b$k"]=Dict("terminal_names"=>copy(terminals),
                "vpn_min"=>fill(180.,3),"vpn_max"=>fill(limit==:voltage && k==segments ? 231. : 260.,3),"vn_max"=>[30.])
            line=Dict{String,Any}("bus_from"=>prefix*"b$(k-1)","bus_to"=>prefix*"b$k",
                "terminal_map_from"=>terminals,"terminal_map_to"=>terminals,
                "i_max"=>[limit==:current && k==segments ? 5. : 100.,100.,100.,100.])
            for i in 1:4,j in i:4
                line["R_series_$(i)_$j"]=(i==j ? (i==4 ? .3 : .2) : .02)/segments
                line["X_series_$(i)_$j"]=(i==j ? (i==4 ? .1 : .08) : .015)/segments
            end
            lines[prefix*"l$k"]=line
        end
        shunts[prefix*"ground"]=Dict("bus"=>last,"terminal_map"=>["n"],"G_1_1"=>.5)
        for (i,p) in enumerate(phases)
            loads[prefix*p]=Dict("bus"=>last,"terminal_map"=>[p,"n"],
                "configuration"=>"SINGLE_PHASE","model"=>"constant_power",
                "p_nom"=>[weight*[2000.,1400.,2600.][i]],"q_nom"=>[weight*[500.,200.,900.][i]])
            generators[prefix*p]=Dict("bus"=>last,"terminal_map"=>[p,"n"],"configuration"=>"SINGLE_PHASE",
                "p_min"=>[0.],"p_max"=>[[4000.,3200.,4800.][i]],"q_min"=>[0.],"q_max"=>[0.],
                "s_max"=>[limit==:capability ? [250.,350.,450.][i] : 6000.],"cost"=>[0.])
        end
    end
    Dict{String,Any}("terminal_conventions"=>Dict("phase"=>phases,"neutral"=>["n"]),
        "bus"=>buses,"line"=>lines,"load"=>loads,"generator"=>generators,"shunt"=>shunts,
        "transformer"=>Dict("single_phase"=>upstream,"delta_wye"=>txs),
        "voltage_source"=>Dict("grid"=>Dict("bus"=>"hv","terminal_map"=>terminals,
            "v_magnitude"=>[11000.,11000.,11000.,0.],"v_angle"=>[0.,-2pi/3,2pi/3,0.])))
end

function benchmark(output;limit=:capability,branches=2,segments=12,nlp_scaling_method="none",repetitions=12)
    repetitions>0 && repetitions%12==0 || throw(ArgumentError("twelve-sweep multiples required"))
    net=case(;limit,branches,segments);candidates=G.profiles(net;nlp_scaling_method)
    start=G.H.S.L.start_point(net)
    checks=map(candidates) do p
        b=build_opf(net,IVRNLP(p.options));r=ivr_nlp_point_report(b,start)
        isempty(r.missing_channels) && length(r.variable_values)==num_variables(b.model) &&
            all(isfinite,values(r.variable_values)) &&
            max(r.max_binding_residual_pu,r.max_reconstruction_residual_pu)<=1e-10 || error("unrepresentable start")
        (;name=p.name,variables=num_variables(b.model),options=P.option_record(p.options),
            transformer=b.numerical_diagnostics[:transformer_scaling_report])
    end
    open(io->JSON3.write(io,net),output*".input.json","w")
    open(io->JSON3.write(io,(;limit,branches,segments,checks,
        note="Manufactured unequal three-phase CP loads, coupled four-wire lines, shared upstream leakage, delta-wye leakage and finite neutral grounds. Frozen six power-base policies; same physical input and unloaded start. Fixed objective divisor 10k, full IVR, composed rows, ground voltage, MUMPS AMD. No analytical global-optimum certificate. Ipopt wall time only.")),output*".manifest.json","w")
    r=P.benchmark(net,output;repetitions,candidates,initial_point=start,
        source_sha256=bytes2hex(sha256(read(@__FILE__))))
    r["position_balanced"]=all(count(o->o[k]==p.name,r["orders"])==repetitions/6 for p in candidates for k in 1:6)
    r["position_balanced"] || error("unbalanced positions")
    r["global_optimum_certified"]=false
    open(io->JSON3.write(io,r),output,"w")
    r
end
end
