"""Manufactured network scaling, not external-feeder validation."""
module IVRNWindingNetworkStudy
using FormulationLab, JuMP, Ipopt, JSON3, LinearAlgebra, SHA
include("benchmark_ivr_nwinding_timing.jl")
const S=IVRNWindingTimingStudy
const P=S.P
const SETTINGS=S.SETTINGS

"""Live four-winding units behind a shared 2.3 kV/230 V boundary.

Per-unit demand, winding data and secondary feeder impedances stay fixed as
units increase. Common supply/trunk impedances scale by 1/units: this is a
declared family of manufactured networks, not a reduction of an external case.
Each secondary has two pi-line sections and all nine load branches remain live.
"""
function network(units)
    units isa Integer && !(units isa Bool) && units>0 || throw(ArgumentError("positive integer units required"))
    tm=["a","b","c","n"]
    net=Dict{String,Any}(k=>Dict{String,Any}() for k in ("bus","line","linecode","load","generator","ibr","voltage_source"))
    net["transformer"]=Dict("single_phase"=>Dict{String,Any}(),"n_winding"=>Dict{String,Any}())
    for b in ("grid","lv","hub")
        net["bus"][b]=Dict("terminal_names"=>copy(tm),"perfectly_grounded_terminals"=>["n"])
    end
    net["voltage_source"]["grid"]=Dict("bus"=>"grid","terminal_map"=>copy(tm),
        "v_magnitude"=>[2300.,2300.,2300.,0.],"v_angle"=>[0.,-2pi/3,2pi/3,0.])
    for t in tm[1:3]
        net["transformer"]["single_phase"][t]=Dict("bus_from"=>"grid","bus_to"=>"lv",
            "terminal_map_from"=>[t,"n"],"terminal_map_to"=>[t,"n"],
            "v_nom_from"=>2300.,"v_nom_to"=>230.,"tap"=>1.,
            "r_series_from"=>.2/units,"x_series_from"=>.1/units,
            "r_series_to"=>.002/units,"x_series_to"=>.001/units)
    end
    function code(id,m,scale;charged=false)
        c=Dict{String,Any}("i_max"=>fill(100units,m))
        for i in 1:m,j in i:m
            c["R_series_$(i)_$j"]=scale*(i==j ? .04 : .002)
            c["X_series_$(i)_$j"]=scale*(i==j ? .02 : .001)
            if charged
                c["B_from_$(i)_$j"]=i==j ? 1e-5/scale : 0.
                c["B_to_$(i)_$j"]=i==j ? 2e-5/scale : 0.
            end
        end
        net["linecode"][id]=c
    end
    function line(id,f,t,terminals,c)
        net["line"][id]=Dict("bus_from"=>f,"bus_to"=>t,"terminal_map_from"=>copy(terminals),
            "terminal_map_to"=>copy(terminals),"linecode"=>c,"length"=>.5,
            "s_max"=>fill(1e5units,3))
    end
    code("common",4,1/units);line("trunk","lv","hub",tm,"common")
    templates=Dict{String,Any}()
    for u in 1:units
        connection=(:YYYY,:YDYY,:YYYD,:DYYY)[mod1(u,4)];roll=isodd(u÷4) ? -1 : 1
        base=S._nwinding_nonstar_case(;connection,roll,bounded=true,excitation=true)
        prefix="u$(u)_";txid=prefix*"tx";templates[txid]=deepcopy(base)
        for (id,b) in base["bus"];net["bus"][prefix*id]=Dict{String,Any}(deepcopy(b));end
        tx=deepcopy(base["transformer"]["n_winding"]["tx"])
        for w in tx["windings"];w["bus"]=prefix*w["bus"];end
        net["transformer"]["n_winding"][txid]=tx
        code(prefix*"primary",4,.1);line(prefix*"primary","hub",prefix*"b1",tm,prefix*"primary")
        for k in 2:4
            w=tx["windings"][k];ts=w["terminal_map"];m=length(ts);vn=w["v_nom"]
            field=w["configuration"]=="DELTA" ? "vpp" : "vpn"
            # Positive engineering bands certify all fractional load-law domains.
            for suffix in ("", "_mid", "_end")
                b=prefix*"b$k"*suffix
                isempty(suffix) || (net["bus"][b]=Dict{String,Any}("terminal_names"=>copy(ts)))
                net["bus"][b][field*"_min"]=fill(.8vn,3)
                net["bus"][b][field*"_max"]=fill(1.2vn,3)
            end
            id=prefix*"secondary$k";code(id,m,(vn/57.5)^2;charged=k==3)
            line(id*"a",w["bus"],w["bus"]*"_mid",ts,id)
            line(id*"b",w["bus"]*"_mid",w["bus"]*"_end",ts,id)
        end
        for (id,d) in base["load"]
            x=deepcopy(d);k=parse(Int,string(id[2]));c=parse(Int,string(id[4]));vn=tx["windings"][k]["v_nom"]
            x["bus"]=prefix*x["bus"]*"_end";x["v_nom"]=[vn]
            x["model"]=("constant_current","zip","exponential")[c]
            if c==2
                for (pre,vals) in (("alpha",(.2,.3,.5)),("beta",(.4,.5,.1))),(s,v) in zip(("z","i","p"),vals)
                    x[pre*"_"*s]=[v]
                end
            elseif c==3
                x["gamma_p"]=[.4];x["gamma_q"]=[-.5]
            end
            net["load"][prefix*id]=x
        end
        for (id,d) in base["generator"]
            x=deepcopy(d);x["bus"]=prefix*x["bus"]*"_end"
            if endswith(id,"2")
                k=parse(Int,string(id[2]));scale=(tx["windings"][k]["v_nom"]/57.5)^2
                delete!(x,"configuration");delete!(x,"cost")
                merge!(x,Dict("topology"=>"SINGLE_PHASE","prime_mover"=>"BATTERY",
                    "q_min"=>[-150.],"q_max"=>[150.],"r_filter"=>[.02scale],"x_filter"=>[.008scale],
                    "b_filter_shunt"=>.0001/scale,"dc_link_coupled"=>true,"p_dc_min"=>0.,"p_dc_max"=>240.,"p_avail"=>270.))
                net["ibr"][prefix*id]=x
            else
                net["generator"][prefix*id]=x
            end
        end
    end
    net,templates
end

function terms(net,workload)
    sources=[(:voltage_source,"grid",k) for k in 1:4]
    dispatch=[(Symbol(f),id,1) for f in ("generator","ibr") for id in sort!(collect(keys(net[f])))]
    if workload==:cost
        [IVRPowerTerm(channels=sources,linear=.25/1000);
         [IVRPowerTerm(channels=[(f==:ibr ? :ibr_internal : f,id,k)],linear=.10/1000) for (f,id,k) in dispatch];
         [IVRPowerTerm(channels=[c],quadratic=.5/1e6) for c in dispatch]]
    elseif workload==:tracking
        target=.35sum(sum(d["p_nom"]) for d in values(net["load"]))
        [IVRPowerTerm(channels=sources,target=target,quadratic=1e-6/length(dispatch));
         IVRPowerTerm(channels=sources,quantity=:q,quadratic=1e-6/length(dispatch));
         [IVRPowerTerm(channels=[c],target=100.,quadratic=1e-8) for c in dispatch];
         [IVRPowerTerm(channels=[c],quantity=:q,quadratic=1e-8) for c in dispatch]]
    else
        throw(ArgumentError("unknown workload"))
    end
end

function profiles(net,workload,sb)
    ts=terms(net,workload)
    [(;name="$(mode)__$(lifting)",options=IVRNLPOptions(;objective=:power,power_terms=deepcopy(ts),
        objective_scale=1.,s_base=sb,transformer_nameplate=:bmopftools,lifting,
        lifted_power_base=500.,observation_sharing=:signed,specialization=:conductor_regions,
        linear_elimination=:passive_blocks,device_elimination=mode,transformer_scaling=:nominal,
        row_scaling=:composed,ground_scaling=:voltage,load_power_lifting=true))
     for mode in (:transformer_currents,:all_transformer_currents) for lifting in (:powers,:bounded_observations)]
end

"""Evaluate each original non-star SI equation block with relabelled observations."""
function equations(templates,point)
    [let prefix=chop(id;tail=2)
        voltage=Dict((b,t)=>point.voltage[(prefix*b,t)] for (b,d) in net["bus"] for t in d["terminal_names"])
        currents=Dict((:transformer_coil,"n_winding/tx/$k")=>point.currents[(:transformer_coil,"n_winding/$id/$k")] for k in 1:4)
        q=S._nwinding_nonstar_equations(net,ACPoint(;voltage,currents))
        (;id,q.ampere_turn_A,q.leakage_V,q.loss_identity_VA)
    end for (id,net) in sort!(collect(templates);by=first)]
end

function trial(net,templates,p,reference,anchor,start)
    row,point=P.trial(net,p,reference,anchor;solver_options=SETTINGS,initial_point=start)
    if point!==nothing
        eq=equations(templates,point)
        row["independent_equations"]=eq
        row["independent_equations_passed"]=all(q.ampere_turn_A<1e-6 && q.leakage_V<1e-6 && q.loss_identity_VA<1e-3 for q in eq)
        row["accepted"] &= row["independent_equations_passed"]
    end
    row,point
end

function run(folder,batch)
    mkpath(folder);BLAS.set_num_threads(1);schedule=S.orders(batch);index=Any[]
    cases=[(;units,workload,sb) for units in (2,8,24) for workload in (:cost,:tracking) for sb in (1e3,1e5)]
    batch=="confirmation" && reverse!(cases)
    for spec in cases
        (;units,workload,sb)=spec;stem="$(units)__$(workload)__$(sb)"
        net,templates=network(units);digest=bytes2hex(sha256(JSON3.write(net)));candidates=profiles(net,workload,sb)
        S.save(joinpath(folder,stem*".input.json"),net);start=S.start_point(net)
        reference=build_opf(net,IVRNLP(;objective=:power,power_terms=terms(net,workload),transformer_nameplate=:bmopftools))
        report=Dict{String,Any}("case"=>spec,"batch"=>batch,"network_sha256"=>digest,
            "runner_sha256"=>bytes2hex(sha256(read(@__FILE__))),"profiles"=>[],"orders"=>[],"repetitions"=>8,
            "primary_metric"=>"ipopt_wall_s","solver_options"=>SETTINGS,
            "julia"=>string(VERSION),"jump"=>string(pkgversion(JuMP)),"ipopt"=>string(pkgversion(Ipopt)),
            "cpu"=>Sys.CPU_NAME,"blas_threads"=>BLAS.get_num_threads(),"julia_threads"=>Threads.nthreads(),
            "shared_physical_start"=>true,"buses"=>length(net["bus"]),"lines"=>length(net["line"]),
            "note"=>"Manufactured shared-supply network scaling, not external transfer. All ports live; no star fit. Same unloaded SI point, balanced eight sweeps, strict physics/objective gates. Primary metric MOI.SolveTimeSec excludes build, preceding cache transfer, start, extraction and audit. Warm-ups excluded; no relaxed retries, outlier deletion or compilation penalty.")
        path=joinpath(folder,stem*".json");anchor=nothing
        for p in candidates
            row,point=trial(net,templates,p,reference,anchor,start)
            if anchor===nothing && row["accepted"];anchor=point;report["anchor_profile"]=p.name;end
            push!(report["profiles"],Dict("name"=>p.name,"options"=>P.option_record(p.options),"warmup"=>row,"trials"=>Any[]))
            S.save(path,report)
        end
        for order in schedule
            push!(report["orders"],[candidates[j].name for j in order])
            for j in order
                row,_=trial(net,templates,candidates[j],reference,anchor,start)
                anchor===nothing && (row["accepted"]=false)
                push!(report["profiles"][j]["trials"],row)
            end
            S.save(path,report)
        end
        report["ranking"]=P.rank_profiles(report["profiles"],8;objective_atol=1e-7,objective_rtol=1e-6)
        report["position_balanced"]=all(count(o->o[k]==p.name,report["orders"])==2 for p in candidates for k in eachindex(candidates))
        report["network_unchanged"]=bytes2hex(sha256(JSON3.write(net)))==digest
        @assert report["position_balanced"] && report["network_unchanged"]
        S.save(path,report);push!(index,(;case=stem,report=basename(path)));S.save(joinpath(folder,"INDEX.json"),index)
        println(stem," complete; eligible=",length(report["ranking"]["eligible"]));flush(stdout)
    end
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("usage: output-folder exploration|confirmation")
    IVRNWindingNetworkStudy.run(ARGS...)
end
