using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
isdefined(@__MODULE__,:ivr_compiler_case) || include("../examples/ivr_compiler_cases.jl")
isdefined(@__MODULE__,:_l3f_case) || include("lindist3flow_fixtures.jl")

_elim_point(r)=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
_elim_solve(b)=solve_ivr_nlp_opf(b;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.))
function _elim_impedance!(d,law,vn)
    d["model"]=law;d["v_nom"]=fill(vn,length(d["p_nom"]))
    if law=="zip"
        for prefix in ("alpha","beta"),suffix in ("z","i","p")
            d["$(prefix)_$suffix"]=suffix=="z" ? 1. : 0.
        end
    elseif law=="exponential"
        d["gamma_p"]=2.;d["gamma_q"]=2.
    end
    d
end

@testset "Impedance-current elimination retains physical observations" begin
    for m in 1:4,law in ("constant_impedance","zip","exponential")
        net=m==1 ? _l3f_case() : ivr_compiler_case(conductors=m,segments=2)
        for d in values(net["load"]);_elim_impedance!(d,law,m==3 ? 230sqrt(3) : 230.);end
        full=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
        r=_elim_solve(full);@test r.solve.optimal
        r.solve.optimal || continue
        p=_elim_point(r);@test physical_residuals(net,r).passed
        channels=sum(length(d["p_nom"]) for d in values(net["load"]))
        for specialization in (:off,:conductor_difference,:conductor_regions)
            reference=build_opf(net,IVRNLP(;specialization))
            b=build_opf(net,IVRNLP(;specialization,linear_elimination=:impedance_loads,objective=:source_import);optimizer=Ipopt.Optimizer)
            @test num_variables(reference.model)-num_variables(b.model)==2channels
            @test b.numerical_diagnostics[:linear_elimination_report].eliminated_complex_coordinates==channels
            @test ivr_nlp_point_report(b,p).passed
            s=_elim_solve(b);@test s.solve.optimal
            s.solve.optimal || continue
            @test physical_residuals(net,s).passed
            @test ivr_nlp_point_report(full,_elim_point(s)).passed
            @test s.objective ≈ r.objective rtol=1e-8 atol=1e-5
            @test keys(s.powers)==keys(r.powers)
            id=first(keys(net["load"]));bad=deepcopy(p.currents);bad[(:load,id)][1]+=1
            @test !ivr_nlp_point_report(b,ACPoint(voltage=p.voltage,currents=bad)).passed
            @test_throws ArgumentError update_ivr_loads!(b,Dict(id=>(p=[0.],q=[0.])))
        end
    end
    for loading in (0.,-.5)
        net=ivr_compiler_case(conductors=2,segments=1,loading=loading)
        _elim_impedance!(net["load"]["d1"],"constant_impedance",230.)
        b=build_opf(net,IVRNLP(linear_elimination=:impedance_loads);optimizer=Ipopt.Optimizer)
        r=_elim_solve(b);@test r.solve.optimal
        @test physical_residuals(net,r).passed
        @test b.numerical_diagnostics[:linear_elimination_report].eliminated_complex_coordinates==1
    end
    @test_throws ArgumentError build_opf(ivr_compiler_case(),IVRNLP(linear_elimination=:unknown))
end

function _elim_series_case(m;reverse=false,permuted=false)
    net=ivr_compiler_case(conductors=m,segments=3)
    delete!(net["load"],"d1");delete!(net["load"],"d2")
    if permuted && m>=3
        for (id,key) in (("l1","terminal_map_to"),("l2","terminal_map_from"))
            tm=net["line"][id][key];tm[1],tm[2]=tm[2],tm[1]
        end
    end
    if reverse
        l=net["line"]["l1"]
        l["bus_from"],l["bus_to"]=l["bus_to"],l["bus_from"]
        l["terminal_map_from"],l["terminal_map_to"]=l["terminal_map_to"],l["terminal_map_from"]
    end
    net
end

@testset "Passive degree-two elimination and conductor composition" begin
    for m in (2,3,4),reverse in (false,true),permuted in (false,true)
        net=_elim_series_case(m;reverse,permuted);original=deepcopy(net)
        full=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
        r=_elim_solve(full);@test r.solve.optimal
        r.solve.optimal || continue
        p=_elim_point(r)
        for specialization in (:off,:conductor_difference,:conductor_regions)
            reference=build_opf(net,IVRNLP(;specialization))
            b=build_opf(net,IVRNLP(;specialization,linear_elimination=:passive,objective=:source_import);optimizer=Ipopt.Optimizer)
            report=b.numerical_diagnostics[:linear_elimination_report]
            @test report.series_buses==["b1"]
            @test report.retained_series_buses["b2"]=="adjacent_elimination"
            @test report.eliminated_complex_coordinates==(specialization==:off ? 2m : 2m-1)
            @test num_variables(reference.model)-num_variables(b.model)==2report.eliminated_complex_coordinates
            @test ivr_nlp_point_report(b,p).passed
            s=_elim_solve(b);@test s.solve.optimal
            s.solve.optimal || continue
            @test physical_residuals(net,s).passed
            @test ivr_nlp_point_report(full,_elim_point(s)).passed
            @test s.objective ≈ r.objective rtol=1e-8 atol=1e-5
            @test Set(keys(s.voltage_candidate))==Set(keys(r.voltage_candidate))
            @test Set(keys(s.current_candidate))==Set(keys(r.current_candidate))
            bad=copy(p.voltage);bad[("b1","a")]+=1
            @test !ivr_nlp_point_report(b,ACPoint(voltage=bad,currents=p.currents)).passed
            bad=deepcopy(p.currents);bad[(:line_from,"l1")][1]+=1
            @test !ivr_nlp_point_report(b,ACPoint(voltage=p.voltage,currents=bad)).passed
            @test net==original
        end
    end
end

@testset "Eliminated observations retain voltage and segment limits" begin
    for m in (2,3,4),specialization in (:off,:conductor_regions),s_base in (1e3,1e5)
        net=_elim_series_case(m)
        full=build_opf(net,IVRNLP(;s_base);optimizer=Ipopt.Optimizer)
        r=_elim_solve(full);@test r.solve.optimal
        r.solve.optimal || continue
        p=_elim_point(r);variants=Dict{String,Any}()
        vn=m==3 ? p.voltage[("b1","b")] : p.voltage[("b1","n")]
        field=m==3 ? "vpp_max" : "vpn_max"
        tight=deepcopy(net);delete!(tight["bus"]["b1"],replace(field,"max"=>"min"))
        tight["bus"]["b1"][field][1]=.5abs(p.voltage[("b1","a")]-vn);variants["voltage"]=tight
        phases=m==2 ? ["a"] : ["a","b","c"]
        for field in ("v_min","v_max")
            tight=deepcopy(net);ratings=abs.([p.voltage[("b1",t)] for t in phases])
            ratings[1]*=field=="v_min" ? 1.5 : .5
            tight["bus"]["b1"][field]=ratings;variants[field]=tight
        end
        if m!=3
            tight=deepcopy(net);tight["bus"]["b1"]["vn_max"]=[.5abs(p.voltage[("b1","n")])]
            variants["neutral"]=tight
        end
        if m>=3
            a=cis(2pi/3);u=[p.voltage[("b1",t)]-(m==4 ? p.voltage[("b1","n")] : 0im) for t in phases]
            for (field,c,factor) in (("vpos_min",[1,a,a^2],1.5),("vpos_max",[1,a,a^2],.5),
                                    ("vneg_max",[1,a^2,a],.5),("vzero_max",[1,1,1],.5))
                magnitude=abs(sum(c.*u)/3)
                magnitude>1e-6 || continue
                tight=deepcopy(net);tight["bus"]["b1"][field]=[factor*magnitude];variants[field]=tight
            end
        end
        for id in ("l1","l2"),field in ("i_max","s_max")
            tight=deepcopy(net)
            ratings=abs.(field=="i_max" ? p.currents[(:line_from,id)] : r.powers[(:line_from,id)][1:(m==2 ? 1 : 3)])
            ratings[1]*=.5;tight["line"][id][field]=ratings;variants["$id/$field"]=tight
        end
        for tight in values(variants)
            b=build_opf(tight,IVRNLP(;s_base,specialization,linear_elimination=:passive))
            @test "b1" in b.numerical_diagnostics[:linear_elimination_report].series_buses
            @test !ivr_nlp_point_report(b,p).passed
            @test !physical_residuals(tight,p;delta_dispatch=:coil).passed
        end
    end
end

@testset "Local series elimination in a mesh and with zero impedance" begin
    for mesh in (false,true),zero_impedance in (false,true)
        net=_elim_series_case(4)
        net["line"]["l1"]["length"]=2.;net["line"]["l2"]["length"]=.35
        if mesh
            net["line"]["closing"]=deepcopy(net["line"]["l3"])
            net["line"]["closing"]["bus_from"]="b3";net["line"]["closing"]["bus_to"]="b0"
        end
        if zero_impedance
            net["linecode"]["zero"]=Dict(k=>startswith(k,"R_series_")||startswith(k,"X_series_") ? 0. : v
                for (k,v) in net["linecode"]["wire"])
            net["line"]["l1"]["linecode"]="zero"
        end
        a=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer)
        b=build_opf(net,IVRNLP(linear_elimination=:passive,specialization=:conductor_regions);optimizer=Ipopt.Optimizer)
        @test b.numerical_diagnostics[:linear_elimination_report].series_buses==["b1"]
        ra=_elim_solve(a);rb=_elim_solve(b)
        @test ra.solve.optimal && rb.solve.optimal
        @test physical_residuals(net,rb).passed
        @test ivr_nlp_point_report(a,_elim_point(rb)).passed
        @test ivr_nlp_point_report(b,_elim_point(ra)).passed
    end
end

@testset "Conservative passive-section boundaries and mixed reuse" begin
    for reason in (:line_shunt,:device,:ground,:parallel)
        net=_elim_series_case(2)
        if reason==:line_shunt
            net["linecode"]["wire"]["B_from_1_1"]=1e-6
        elseif reason==:device
            net["load"]["extra"]=deepcopy(net["load"]["d3"]);net["load"]["extra"]["bus"]="b1"
            net["load"]["extra"]["p_nom"].=0.;net["load"]["extra"]["q_nom"].=0.
        elseif reason==:ground
            net["bus"]["b1"]["perfectly_grounded_terminals"]=["n"]
        else
            net["line"]["l2"]["bus_to"]="b0"
            # Keep the remaining load component referenced independently.
            net["voltage_source"]["other"]=deepcopy(net["voltage_source"]["source"])
            net["voltage_source"]["other"]["bus"]="b2"
        end
        b=build_opf(net,IVRNLP(linear_elimination=:passive))
        @test "b1" ∉ b.numerical_diagnostics[:linear_elimination_report].series_buses
    end
    net=_elim_series_case(4);_elim_impedance!(net["load"]["d3"],"zip",230.)
    net["load"]["cp"]=deepcopy(ivr_compiler_case(conductors=4,segments=3)["load"]["d3"])
    net["generator"]=Dict("g"=>Dict("bus"=>"b3","terminal_map"=>["a","b","c","n"],"configuration"=>"WYE",
        "p_min"=>zeros(3),"p_max"=>zeros(3),"q_min"=>zeros(3),"q_max"=>zeros(3),"cost"=>ones(3)))
    for specialization in (:off,:conductor_difference,:conductor_regions)
        b=build_opf(net,IVRNLP(;specialization,linear_elimination=:passive);optimizer=Ipopt.Optimizer)
        variables=all_variables(b.model);report=b.numerical_diagnostics[:linear_elimination_report]
        @test report.impedance_loads==["d3"] && report.series_buses==["b1"]
        update_ivr_loads!(b,Dict("cp"=>(p=[100.,200.,300.],q=[20.,30.,40.])))
        update_ivr_generators!(b,Dict("g"=>(p_min=[40.,50.,60.],p_max=[40.,50.,60.],cost=[.2,.3,.4])))
        r=_elim_solve(b);@test r.solve.optimal
        @test physical_residuals(b.network,r).passed
        @test all_variables(b.model)==variables
        fresh=build_opf(b.network,IVRNLP())
        @test ivr_nlp_point_report(fresh,_elim_point(r)).passed
    end
end
