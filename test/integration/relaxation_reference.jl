# Optional, independent nonlinear oracle. No BMOPFTools dependency in src/.
using FormulationLab, BMOPFTools, Ipopt, JuMP, Clarabel, JSON3, LinearAlgebra, Test, SHA
include("../sdp_transformer_fixtures.jl")

function reference_point(net,result)
    voltage=Dict((b,t)=>complex(x["vr"],x["vi"]) for (b,ts) in result["bus"] for (t,x) in ts)
    currents=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    for (id,d) in get(net,"load",Dict())
        data=result["load"][id]
        tm=d["terminal_map"];keys_in_order=[t for t in tm if haskey(data,t)]
        currents[(:load,id)]=[complex(data[t]["crd"],data[t]["cid"]) for t in keys_in_order]
    end
    for (id,d) in get(net,"generator",Dict())
        d["configuration"]=="DELTA" && error("delta generator reference convention requires a dedicated adapter")
        data=result["generator"][id]
        currents[(:generator,id)]=[complex(data[t]["crg"],data[t]["cig"]) for t in d["terminal_map"] if haskey(data,t)]
    end
    for (id,d) in get(net,"voltage_source",Dict())
        data=result["voltage_source"][id]
        currents[(:voltage_source,id)]=[haskey(data,t) ? complex(data[t]["cr"],data[t]["ci"]) :
            t in get(net["bus"][d["bus"]],"perfectly_grounded_terminals",[]) ? 0im : error("missing source current") for t in d["terminal_map"]]
    end
    for (id,d) in get(net,"line",Dict()),side in ("from","to")
        data=result["line"][id];suffix=side=="from" ? "fr" : "to"
        currents[(Symbol("line_",side),id)]=[complex(data[t]["cr_$suffix"],data[t]["ci_$suffix"]) for t in d["terminal_map_from"]]
    end
    # Use explicitly documented series-coil currents where their meaning is clear.
    # Other hidden transformer currents are reconstructed and recorded as inferred.
    for (kind,table) in get(net,"transformer",Dict()),(id,d) in table
        data=result["transformer"][id];key="$kind/$id"
        val(side,k)=complex(data[side][string(k)]["cr"],data[side][string(k)]["ci"])
        if kind in ("single_phase","single_phase_autotransformer","open_delta_regulator")
            n=kind=="open_delta_regulator" ? 2 : 1
            currents[(:transformer_coil_from,key)]=[val("fr",k) for k in 1:n]
            currents[(:transformer_coil_to,key)]=[val("to",k) for k in 1:n]
        elseif kind=="center_tap"
            currents[(:transformer_coil_from,key)]=[val("fr",1)]
            currents[(:transformer_coil_to,key)]=[val("to",1),-val("to",3)]
        end
    end
    ACPoint(;voltage,currents)
end

function reference_case(kind,tap;reverse=false,excitation=false)
    net=_sdp_tx_case(kind;tap)
    d=net["transformer"][kind]["tx"]
    if kind in ("delta_wye","wye_delta")
        d["r_series"]=0.1;d["x_series"]=0.08
    else
        d["r_series_from"]=0.1;d["x_series_from"]=0.08
        d["r_series_to"]=0.025;d["x_series_to"]=0.02
    end
    excitation && (d["g_no_load"]=0.002;d["b_no_load"]=-0.001)
    tm=net["bus"]["t"]["terminal_names"]
    pairs=kind=="center_tap" ? [["x1","n"],["x2","n"]] :
        kind in ("single_phase","single_phase_autotransformer") ? [tm[1:2]] :
        kind=="delta_wye" ? [[p,"n"] for p in tm[1:3]] : [[tm[k],tm[mod1(k+1,3)]] for k in 1:3]
    net["load"]=Dict{String,Any}()
    for (k,pair) in enumerate(pairs)
        net["load"]["l$k"]=Dict("bus"=>"t","terminal_map"=>pair,"configuration"=>"SINGLE_PHASE",
            "model"=>"constant_power","p_nom"=>[250.0*k],"q_nom"=>[65.0*k])
    end
    if reverse
        pair=first(pairs)
        net["generator"]=Dict("pv"=>Dict("bus"=>"t","terminal_map"=>pair,"configuration"=>"SINGLE_PHASE",
            "p_min"=>[0.0],"p_max"=>[2500.0],"q_min"=>[0.0],"q_max"=>[0.0],"cost"=>[0.0]))
    end
    for d in values(net["voltage_source"]);d["cost"]=fill(1.,length(d["terminal_map"]));end
    net
end

function run_reference_audit(output;smoke=false)
    BLAS.set_num_threads(1)
    cases=smoke ? [("single_phase",1.03,false,false)] :
        [(kind,tap,reverse,false) for kind in ("single_phase","center_tap","delta_wye","wye_delta","single_phase_autotransformer","open_delta_regulator") for tap in (0.94,1.06) for reverse in (false,true)]
    smoke || push!(cases,("single_phase",1.03,false,true))
    report=Dict("julia"=>string(VERSION),"bmopftools_path"=>pathof(BMOPFTools),
        "bmopftools_version"=>string(pkgversion(BMOPFTools)),
        "bmopftools_revision"=>try readchomp(`git -C $(dirname(dirname(pathof(BMOPFTools)))) rev-parse HEAD`) catch; "unknown" end,
        "ipopt"=>string(pkgversion(Ipopt)),"clarabel"=>string(pkgversion(Clarabel)),"cases"=>Any[])
    for (kind,tap,reverse,excitation) in cases
        net=reference_case(kind,tap;reverse,excitation);sb=1000.0
        row=Dict{String,Any}("kind"=>kind,"tap"=>tap,"reverse_dispatch"=>reverse,"legacy_excitation"=>excitation,"input_sha256"=>bytes2hex(sha256(JSON3.write(net))))
        try
            result=BMOPFTools.solve_opf(net;optimizer=Ipopt.Optimizer,per_unit=true,s_base=sb,
                solver_options=("print_level"=>0,"tol"=>1e-10,"constr_viol_tol"=>1e-10,"bound_relax_factor"=>0.0,"max_iter"=>1000))
            row["nlp_status"]=result["termination_status"]
            result["termination_status"] in ("LOCALLY_SOLVED","OPTIMAL") || error("reference solve failed")
            p=reference_point(net,result)
            b=build_sdp_opf(net,nothing;options=SDPOptions(audit=true,s_base=sb))
            completion=complete_ac_point(b,p);physical=physical_residuals(net,completion.point)
            row["state_residual_pu"]=completion.state_residual_pu
            row["physical_passed"]=physical.passed;row["physical_maxima"]=Dict(string(k)=>v for (k,v) in physical.maxima)
            row["unassessed"]=physical.unassessed;row["inferred_channels"]=string.(completion.inferred_channels)
            row["worst_physical"]=sort(physical.records;by=r->-r.residual)[1:min(5,length(physical.records))]
            row["reference_import_W"]=sum(sum(t["ps"] for t in values(x)) for x in values(result["voltage_source"]))
            profiles=[]
            if physical.passed && completion.state_residual_pu<1e-7
                for (name,f) in (("dense_sdp",IVRSDP(audit=true,s_base=sb,objective=:source_import,decomposition=:dense)),
                    ("local_sdp",IVRSDP(audit=true,s_base=sb,objective=:source_import,decomposition=:chordal,consistency=:local,clique_size=8)),
                    ("soc_linear",IVRSOC(audit=true,s_base=sb,objective=:source_import)),("soc_kim",IVRSOC(audit=true,s_base=sb,objective=:source_import,strengthening=:kim,max_triplets=2)))
                    build=build_opf(net,f;optimizer=Clarabel.Optimizer)
                    c=containment_report(build,completion.point)
                    r=build isa SOCBuild ? solve_soc_opf(build;solver_options=(verbose=false,)) : solve_sdp_opf(build;solver_options=(verbose=false,))
                    push!(profiles,Dict("profile"=>name,"state_residual_pu"=>c.state_residual_pu,"binding_residual"=>c.binding_residual,
                        "max_constraint_violation"=>c.max_constraint_violation,"max_bound_violation_pu"=>c.max_bound_violation_pu,"status"=>r.solve.termination_status,
                        "objective"=>isfinite(r.objective) ? r.objective : nothing))
                end
            end
            row["profiles"]=profiles
        catch e
            row["error"]=sprint(showerror,e)
        end
        push!(report["cases"],row)
        open(io->JSON3.write(io,report),output,"w")
        println(kind," ",tap," reverse=",reverse," ",get(row,"error",get(row,"physical_passed",false)));flush(stdout)
    end
    @testset "BMOPFTools reference containment" begin
        for row in report["cases"]
            expected=row["kind"] in ("single_phase","single_phase_autotransformer","open_delta_regulator") && !row["legacy_excitation"]
            expected && @test get(row,"physical_passed",false)
            if get(row,"physical_passed",false)
                @test !haskey(row,"error")
                @test length(row["profiles"])==4
                for p in row["profiles"]
                    @test max(p["state_residual_pu"],p["binding_residual"],p["max_constraint_violation"],p["max_bound_violation_pu"])<1e-7
                    @test p["status"]=="OPTIMAL"
                    # Numerical objective comparison, not a certified dual bound.
                    @test p["objective"]<=row["reference_import_W"]+1e-3
                end
            end
        end
    end
    report
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)>=1 || error("Supply output JSON path")
    run_reference_audit(first(ARGS);smoke="--smoke" in ARGS)
end
