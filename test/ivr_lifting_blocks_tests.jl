using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
isdefined(@__MODULE__,:ivr_compiler_case) || include("../examples/ivr_compiler_cases.jl")
const _LB_SETTINGS=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.,max_iter=500)
function _lb_case(m;charged=true,alternate=false)
    net=ivr_compiler_case(conductors=m,segments=3)
    delete!(net["load"],"d1");delete!(net["load"],"d2")
    for l in values(net["line"]);l["s_max"]=fill(1e4,m==2 ? 1 : 3);end
    if charged
        code=net["linecode"]["wire"]
        for j in 1:m
            code["B_from_$(j)_$(j)"]=1e-4*j
            code["B_to_$(j)_$(j)"]=2e-4*j
            code["G_from_$(j)_$(j)"]=1e-6*j
        end
    end
    if alternate
        net["line"]["a"]=pop!(net["line"],"l2")
        l=net["line"]["l1"]
        l["bus_from"],l["bus_to"]=l["bus_to"],l["bus_from"]
        l["terminal_map_from"],l["terminal_map_to"]=l["terminal_map_to"],l["terminal_map_from"]
        if m>=3
            for (id,key) in (("l1","terminal_map_from"),("a","terminal_map_from"))
                tm=net["line"][id][key];tm[1],tm[2]=tm[2],tm[1]
            end
        end
    end
    net
end
_lb_point(r)=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
_lb_solve(b)=solve_ivr_nlp_opf(b;solver_options=_LB_SETTINGS)

@testset "Exact lifting and charged blocks preserve physical observations" begin
    for m in (2,3,4),charged in (false,true),alternate in (false,true)
        net=_lb_case(m;charged,alternate);original=deepcopy(net)
        full=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
        rf=_lb_solve(full);@test rf.solve.optimal
        for specialization in (:off,:conductor_regions),lifting in (:off,:powers,:bounded_observations)
            b=build_opf(net,IVRNLP(;objective=:source_import,specialization,lifting,linear_elimination=:passive_blocks);optimizer=Ipopt.Optimizer)
            rep=b.numerical_diagnostics[:linear_elimination_report]
            @test rep.series_buses==["b1","b2"]
            @test all(x->x.condition<=1e8 && x.relative_residual<=1e-12,values(rep.block_diagnostics))
            y=ComplexF64[sin(k)+im*cos(2k) for k in eachindex(b.coordinates.projection)]
            ev(row,x)=FormulationLab._linivr_eval(row,x)
            z=[ev(row,y) for row in b.coordinates.reconstruction]
            @test [ev(row,z) for row in b.coordinates.projection] ≈ y atol=1e-11
            for bus in rep.series_buses,t in net["bus"][bus]["terminal_names"]
                @test abs(ev(b.electrical.kcl[(bus,t)],z))<1e-11
            end
            for l in b.electrical.lnc_lines
                l.id in values(rep.selected_series_lines) || continue
                @test all(k->abs(ev(b.electrical.equations[k],z))<1e-11,l.equation_indices)
            end
            supplied=ivr_nlp_point_report(b,_lb_point(rf));@test supplied.passed
            @test length(supplied.variable_values)==num_variables(b.model)
            if lifting!=:off
                @test b.numerical_diagnostics[:lifted_real_variables]>0
                ref=first(b.model.ext[:ivr_lifting].records)
                bad=copy(supplied.variable_values);bad[ref.real]+=.1
                @test maximum(values(primal_feasibility_report(b.model,bad;atol=0.)))>.09
            end
            r=_lb_solve(b);@test r.solve.optimal
            @test physical_residuals(net,r).passed
            @test ivr_nlp_point_report(full,_lb_point(r)).passed
            @test ivr_nlp_point_report(b,_lb_point(r)).passed
            @test r.objective ≈ rf.objective rtol=1e-8 atol=1e-5
            d=result_dict(b,r)
            for (bus,ts) in result_dict(full,rf)["bus"],(t,v) in ts
                @test d["bus"][bus][t]["vr"] ≈ v["vr"] atol=1e-5
                @test d["bus"][bus][t]["vi"] ≈ v["vi"] atol=1e-5
            end
        end
        @test net==original
    end
end

@testset "Charged interior bounds remain binding expressions" begin
    for m in (2,3,4)
        net=_lb_case(m);r=_lb_solve(build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer));p=_lb_point(r)
        for bus in ("b1","b2")
            phases=m==2 ? ["a"] : ["a","b","c"];v=[p.voltage[(bus,t)] for t in phases]
            vn=m==3 ? 0im : p.voltage[(bus,"n")];u=v.-vn;a=cis(2pi/3)
            bounds=Dict("v_min"=>abs.(v),"v_max"=>abs.(v))
            m!=3 && merge!(bounds,Dict("vpn_min"=>abs.(u),"vpn_max"=>abs.(u),"vn_max"=>[abs(vn)]))
            if m>=3
                pp=abs.([v[1]-v[2],v[2]-v[3],v[3]-v[1]])
                merge!(bounds,Dict("vpp_min"=>pp,"vpp_max"=>pp,
                    "vpos_min"=>[abs(sum([1,a,a^2].*u)/3)],"vpos_max"=>[abs(sum([1,a,a^2].*u)/3)],
                    "vneg_max"=>[abs(sum([1,a^2,a].*u)/3)],"vzero_max"=>[abs(sum(u)/3)]))
            end
            for (field,x) in bounds,k in eachindex(x),lifting in (:powers,:bounded_observations)
                x[k]>1e-5 || continue
                tight=deepcopy(net);lower=endswith(field,"min")
                tight["bus"][bus][field]=lower ? .5x : 2x
                tight["bus"][bus][field][k]=lower ? 1.5x[k] : .5x[k]
                b=build_opf(tight,IVRNLP(;lifting,linear_elimination=:passive_blocks))
                @test !ivr_nlp_point_report(b,p).passed
                audit=physical_residuals(tight,p;delta_dispatch=:coil)
                @test any(x->x.label=="bus/$bus/$field" && x.residual>getproperty(audit.tolerances,x.unit),audit.records)
            end
        end
        for id in keys(net["line"]),side in (:line_from,:line_to),field in ("i_max","s_max"),lifting in (:off,:powers,:bounded_observations)
            x=abs.(field=="i_max" ? p.currents[(side,id)] : r.powers[(side,id)][1:(m==2 ? 1 : 3)])
            for k in eachindex(x)
                x[k]>1e-5 || continue
                tight=deepcopy(net);tight["line"][id][field]=fill(1e9,length(x));tight["line"][id][field][k]=.5x[k]
                b=build_opf(tight,IVRNLP(;lifting,linear_elimination=:passive_blocks))
                @test !ivr_nlp_point_report(b,p).passed
                audit=physical_residuals(tight,p;delta_dispatch=:coil)
                label="line/$id/$(side==:line_from ? "from" : "to")/$field"
                @test any(x->x.label==label && x.residual>getproperty(audit.tolerances,x.unit),audit.records)
            end
        end
    end
end

@testset "Block refusal, rollback and reuse" begin
    row(x)=Dict{Int,ComplexF64}(i=>v for (i,v) in enumerate(x) if !iszero(v))
    @test last(FormulationLab._ivrn_block_substitution([row([1,1]),row([1,1])],Set([1,2])))=="ill_conditioned_local_block"
    @test last(FormulationLab._ivrn_block_substitution([row([1,1,1]),row([1,1+1e-12,2])],Set([1,2])))=="ill_conditioned_local_block"
    @test last(FormulationLab._ivrn_block_substitution([row([1,1])],Set([1,2])))=="incomplete_local_block"
    net=_lb_case(2)
    selected=build_opf(net,IVRNLP(linear_elimination=:passive_blocks,series_selection=:bound_support))
    @test !isempty(selected.numerical_diagnostics[:linear_elimination_report].bound_support_rejections)
    r=_lb_solve(build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer))
    @test ivr_nlp_point_report(selected,_lb_point(r)).passed
    net["generator"]=Dict("g"=>Dict("bus"=>"b3","terminal_map"=>["a","n"],"configuration"=>"SINGLE_PHASE",
        "p_min"=>[0.],"p_max"=>[1000.],"q_min"=>[-100.],"q_max"=>[100.],"cost"=>[.2]))
    for lifting in (:powers,:bounded_observations)
        b=build_opf(net,IVRNLP(;lifting,linear_elimination=:passive_blocks);optimizer=Ipopt.Optimizer)
        vars=all_variables(b.model)
        update_ivr_loads!(b,Dict("d3"=>(p=[1500.],q=[300.])))
        update_ivr_generators!(b,Dict("g"=>(p_min=[100.],p_max=[100.],q_min=[-20.],q_max=[-20.],cost=[.5])))
        r=_lb_solve(b);@test r.solve.optimal
        @test all_variables(b.model)==vars
        @test physical_residuals(b.network,r).passed
        @test ivr_nlp_point_report(build_opf(b.network,IVRNLP()),_lb_point(r)).passed
    end
    @test_throws ArgumentError build_opf(net,IVRNLP(lifting=:invalid))
    # An LC resonance gives singular local blocks. Retain the circuit exactly;
    # do not regularize it or infer a current from a pseudoinverse.
    resonant=_lb_case(2);code=resonant["linecode"]["wire"]
    for key in collect(keys(code));key=="i_max" || delete!(code,key);end
    for j in 1:2
        code["R_series_$(j)_$(j)"]=0.;code["X_series_$(j)_$(j)"]=1.
        code["B_from_$(j)_$(j)"]=.5;code["B_to_$(j)_$(j)"]=.5
    end
    base=build_opf(resonant,IVRNLP());b=build_opf(resonant,IVRNLP(linear_elimination=:passive_blocks))
    @test isempty(b.numerical_diagnostics[:linear_elimination_report].series_buses)
    @test b.coordinates.reconstruction==base.coordinates.reconstruction
    @test all(bus->b.numerical_diagnostics[:linear_elimination_report].retained_series_buses[bus]=="ill_conditioned_local_block",["b1","b2"])
end
