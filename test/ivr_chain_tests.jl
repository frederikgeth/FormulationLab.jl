using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
isdefined(@__MODULE__,:_elim_series_case) || include("ivr_elimination_tests.jl")
isdefined(@__MODULE__,:_selection_unbound!) || include("ivr_series_selection_tests.jl")

@testset "Adjacent chains use surviving equations and invertible maps" begin
    for m in (2,3,4),specialization in (:off,:conductor_difference,:conductor_regions),alternate in (false,true)
        net=_elim_series_case(m;reverse=alternate,permuted=alternate)
        # b1 first consumes the b1--b2 line: b2 must choose its other line.
        alternate && (net["line"]["a"]=pop!(net["line"],"l2"))
        original=deepcopy(net)
        full=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
        b=build_opf(net,IVRNLP(;specialization,linear_elimination=:passive_chains,objective=:source_import);optimizer=Ipopt.Optimizer)
        report=b.numerical_diagnostics[:linear_elimination_report]
        @test report.series_buses==["b1","b2"]
        @test isempty(report.retained_series_buses)
        @test length(unique(values(report.selected_series_lines)))==2
        @test report.selected_series_lines["b2"]==(alternate ? "l3" : "l2")
        @test report.eliminated_complex_coordinates==2*(specialization==:off ? 2m : 2m-1)
        # Arbitrary solver coordinates, not an optimum: PR=I and every removed
        # circuit equation vanishes on the entire reconstructed linear subspace.
        y=ComplexF64[sin(k)+im*cos(2k) for k in eachindex(b.coordinates.projection)]
        ev(row,x)=FormulationLab._linivr_eval(row,x)
        z=[ev(row,y) for row in b.coordinates.reconstruction]
        @test [ev(row,z) for row in b.coordinates.projection] ≈ y atol=1e-12
        for bus in report.series_buses,t in net["bus"][bus]["terminal_names"]
            @test abs(ev(b.electrical.kcl[(bus,t)],z))<1e-12
        end
        for line in b.electrical.lnc_lines
            line.id in values(report.selected_series_lines) || continue
            @test all(i->abs(ev(b.electrical.equations[i],z))<1e-12,line.equation_indices)
        end
        rf=_elim_solve(full);r=_elim_solve(b)
        @test rf.solve.optimal && r.solve.optimal
        @test physical_residuals(net,r).passed
        @test ivr_nlp_point_report(full,_elim_point(r)).passed
        @test ivr_nlp_point_report(b,_elim_point(rf)).passed
        @test r.objective ≈ rf.objective rtol=1e-8 atol=1e-5
        for bus in report.series_buses
            bad=copy(r.voltage_candidate);bad[(bus,"a")]+=1
            @test !ivr_nlp_point_report(b,ACPoint(voltage=bad,currents=r.current_candidate)).passed
        end
        @test net==original
    end
end

@testset "Adjacent chains retain every interior bound and both line endpoints" begin
    for m in (2,3,4),specialization in (:off,:conductor_regions)
        net=_elim_series_case(m)
        r=_elim_solve(build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer))
        @test r.solve.optimal
        point=_elim_point(r)
        # Enumerate physical voltage expressions independently, then require
        # an independent SI audit to identify the violated bound. This includes
        # all phase/pair/neutral/sequence families on each eliminated bus.
        for bus in ("b1","b2")
            phases=m==2 ? ["a"] : ["a","b","c"]
            v=[point.voltage[(bus,t)] for t in phases];vn=m==3 ? 0im : point.voltage[(bus,"n")]
            a=cis(2pi/3);u=v.-vn
            values=Dict("v_min"=>abs.(v),"v_max"=>abs.(v),"vpn_min"=>abs.(u),"vpn_max"=>abs.(u))
            m==3 && (delete!(values,"vpn_min");delete!(values,"vpn_max"))
            m!=3 && (values["vn_max"]=[abs(vn)])
            if m>=3
                pp=abs.([v[1]-v[2],v[2]-v[3],v[3]-v[1]])
                merge!(values,Dict("vpp_min"=>pp,"vpp_max"=>pp,
                    "vpos_min"=>[abs(sum([1,a,a^2].*u)/3)],"vpos_max"=>[abs(sum([1,a,a^2].*u)/3)],
                    "vneg_max"=>[abs(sum([1,a^2,a].*u)/3)],"vzero_max"=>[abs(sum(u)/3)]))
            end
            for (field,x) in values,k in eachindex(x)
                lower=endswith(field,"min")
                !lower && x[k]<1e-5 && continue
                tight=deepcopy(net)
                for key in collect(keys(tight["bus"][bus]))
                    endswith(key,"_min") || endswith(key,"_max") || continue
                    delete!(tight["bus"][bus],key)
                end
                tight["bus"][bus][field]=lower ? .5x : 2x
                tight["bus"][bus][field][k]=lower ? 1.5x[k] : .5x[k]
                b=build_opf(tight,IVRNLP(;specialization,linear_elimination=:passive_chains))
                @test b.numerical_diagnostics[:linear_elimination_report].series_buses==["b1","b2"]
                q=ivr_nlp_point_report(b,point)
                @test !q.passed && q.max_reconstruction_residual_pu<1e-7
                audit=physical_residuals(tight,point;delta_dispatch=:coil)
                @test !audit.passed && isempty(audit.unassessed)
                @test any(x->x.label=="bus/$bus/$field" && x.residual>getproperty(audit.tolerances,x.unit),audit.records)
            end
        end
        for id in ("l1","l2","l3"),side in (:line_from,:line_to),field in ("i_max","s_max")
            x=abs.(field=="i_max" ? point.currents[(side,id)] : r.powers[(side,id)][1:(m==2 ? 1 : 3)])
            for k in eachindex(x)
                x[k]>1e-5 || continue
                tight=deepcopy(net);tight["line"][id][field]=fill(1e9,length(x))
                tight["line"][id][field][k]=.5x[k]
                b=build_opf(tight,IVRNLP(;specialization,linear_elimination=:passive_chains))
                @test !ivr_nlp_point_report(b,point).passed
                audit=physical_residuals(tight,point;delta_dispatch=:coil)
                @test !audit.passed && isempty(audit.unassessed)
                label="line/$id/$(side==:line_from ? "from" : "to")/$field"
                @test any(x->x.label==label && x.residual>getproperty(audit.tolerances,x.unit),audit.records)
            end
        end
    end
end

@testset "Chain support selection, boundaries and supported updates" begin
    for mode in (:passive,:passive_chains)
        for reason in (:line_shunt,:device,:ground)
            net=_elim_series_case(2)
            reason==:line_shunt && (net["linecode"]["wire"]["B_from_1_1"]=1e-6)
            reason==:device && (net["load"]["extra"]=merge(deepcopy(net["load"]["d3"]),Dict("bus"=>"b1")))
            reason==:ground && (net["bus"]["b1"]["perfectly_grounded_terminals"]=["n"])
            b=build_opf(net,IVRNLP(linear_elimination=mode))
            @test "b1" ∉ b.numerical_diagnostics[:linear_elimination_report].series_buses
        end
    end
    for specialization in (:off,:conductor_regions)
        net=_elim_series_case(4)
        b=build_opf(net,IVRNLP(;specialization,linear_elimination=:passive_chains,series_selection=:bound_support))
        @test isempty(b.numerical_diagnostics[:linear_elimination_report].series_buses)
        for bus in ("b1","b2");_selection_unbound!(net,bus);end
        b=build_opf(net,IVRNLP(;specialization,linear_elimination=:passive_chains,series_selection=:bound_support))
        @test b.numerical_diagnostics[:linear_elimination_report].series_buses==["b1","b2"]
        _elim_impedance!(net["load"]["d3"],"constant_impedance",230.)
        net["load"]["cp"]=deepcopy(ivr_compiler_case(conductors=4,segments=3)["load"]["d3"])
        net["generator"]=Dict("g"=>Dict("bus"=>"b3","terminal_map"=>["a","b","c","n"],"configuration"=>"WYE",
            "p_min"=>zeros(3),"p_max"=>zeros(3),"q_min"=>zeros(3),"q_max"=>zeros(3),"cost"=>ones(3)))
        b=build_opf(net,IVRNLP(;specialization,linear_elimination=:passive_chains);optimizer=Ipopt.Optimizer)
        vars=all_variables(b.model)
        update_ivr_loads!(b,Dict("cp"=>(p=[100.,200.,300.],q=[20.,30.,40.])))
        update_ivr_generators!(b,Dict("g"=>(p_min=[20.,30.,40.],p_max=[20.,30.,40.],q_min=[-10.,-20.,-30.],q_max=[-10.,-20.,-30.],cost=[.2,.3,.4])))
        r=_elim_solve(b);@test r.solve.optimal
        @test physical_residuals(b.network,r).passed
        @test all_variables(b.model)==vars
        @test ivr_nlp_point_report(build_opf(b.network,IVRNLP()),_elim_point(r)).passed
    end
end

@testset "Chain composition sees old bounds, junctions and cycles" begin
    net=_elim_series_case(2)
    _selection_unbound!(net,"b2")
    net["linecode"]["zero"]=Dict(k=>startswith(k,"R_series_")||startswith(k,"X_series_") ? 0. : v for (k,v) in net["linecode"]["wire"])
    net["line"]["a"]=pop!(net["line"],"l2");net["line"]["a"]["linecode"]="zero"
    b=build_opf(net,IVRNLP(linear_elimination=:passive_chains,series_selection=:bound_support))
    report=b.numerical_diagnostics[:linear_elimination_report]
    @test report.series_buses==["b1"]
    @test report.selected_series_lines["b1"]=="a"
    @test report.retained_series_buses["b2"]=="operating_bound_support_expansion"
    @test any(x->startswith(x.label,"bus/b1/"),report.bound_support_rejections["b2"])
    @test all(x->!startswith(x.label,"bus/b2/"),report.bound_support_rejections["b2"])
    # No stale transaction survives rejection: exact same maps as the original
    # nonadjacent policy which accepts b1 and never attempts b2.
    passive=build_opf(net,IVRNLP(linear_elimination=:passive,series_selection=:bound_support))
    @test b.coordinates.projection==passive.coordinates.projection
    @test b.coordinates.reconstruction==passive.coordinates.reconstruction
    for shape in (:mesh,:junction),zero in (false,true)
        net=_elim_series_case(4)
        net["line"]["extra"]=deepcopy(net["line"]["l3"])
        net["line"]["extra"]["bus_from"]=shape==:mesh ? "b3" : "b2"
        net["line"]["extra"]["bus_to"]="b0"
        if zero
            net["linecode"]["zero"]=Dict(k=>startswith(k,"R_series_")||startswith(k,"X_series_") ? 0. : v for (k,v) in net["linecode"]["wire"])
            net["line"]["l1"]["linecode"]="zero"
        end
        full=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer)
        b=build_opf(net,IVRNLP(linear_elimination=:passive_chains,specialization=:conductor_regions);optimizer=Ipopt.Optimizer)
        @test b.numerical_diagnostics[:linear_elimination_report].series_buses==(shape==:mesh ? ["b1","b2"] : ["b1"])
        rf=_elim_solve(full);r=_elim_solve(b)
        @test rf.solve.optimal && r.solve.optimal
        @test physical_residuals(net,r).passed
        @test ivr_nlp_point_report(full,_elim_point(r)).passed
        @test ivr_nlp_point_report(b,_elim_point(rf)).passed
    end
end

@testset "Chain apparent-power limits isolate each endpoint by power direction" begin
    for m in (2,3),direction in (-1,1)
        net=_elim_series_case(m)
        net["load"]["d3"]["p_nom"] .*= direction
        net["load"]["d3"]["q_nom"] .*= direction
        r=_elim_solve(build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer));@test r.solve.optimal
        p=_elim_point(r)
        for id in ("l1","l2","l3")
            f=abs(r.powers[(:line_from,id)][1]);t=abs(r.powers[(:line_to,id)][1])
            @test abs(f-t)>1e-4
            endpoint=f>t ? "from" : "to"
            tight=deepcopy(net);tight["line"][id]["s_max"]=fill(1e9,m==2 ? 1 : 3)
            tight["line"][id]["s_max"][1]=(f+t)/2
            b=build_opf(tight,IVRNLP(specialization=:conductor_regions,linear_elimination=:passive_chains))
            q=ivr_nlp_point_report(b,p)
            @test !q.passed && q.max_reconstruction_residual_pu<1e-7
            audit=physical_residuals(tight,p;delta_dispatch=:coil)
            violations=[x.label for x in audit.records if x.residual>getproperty(audit.tolerances,x.unit)]
            @test violations==["line/$id/$endpoint/s_max"]
        end
    end
end
