using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
isdefined(@__MODULE__,:ivr_compiler_case) || include("../examples/ivr_compiler_cases.jl")

# Independently solved two-wire circuit: two 0.5-ohm loops, a finite
# source-neutral shunt and a 2000 W / 230 V constant-impedance load.
function _ground_scaling_case(y)
    net=ivr_compiler_case(conductors=2,segments=2)
    delete!(net["load"],"d1")
    net["bus"]["b0"]["perfectly_grounded_terminals"]=String[]
    source=net["voltage_source"]["source"]
    source["terminal_map"]=["a"];source["v_magnitude"]=[230.];source["v_angle"]=[0.]
    net["shunt"]=Dict("ground"=>Dict("bus"=>"b0","terminal_map"=>["n"],"G_1_1"=>real(y),"B_1_1"=>imag(y)))
    code=net["linecode"]["wire"]
    for k in keys(code)
        startswith(k,"R_series_") || startswith(k,"X_series_") || continue
        code[k]=k=="R_series_1_1" ? .2 : k=="R_series_2_2" ? .3 : 0.
    end
    d=net["load"]["d2"];d["model"]="constant_impedance";d["v_nom"]=[230.];d["p_nom"]=[2000.];d["q_nom"]=[0.]
    current=230/(1+230^2/2000+inv(y))
    volts=Dict(("b$k",t)=>(t=="a" ? 230-.2k*current : current/y+.3k*current) for k in 0:2 for t in ("a","n"))
    currents=Dict{Tuple{Symbol,String},Vector{ComplexF64}}((:load,"d2")=>[current],(:voltage_source,"source")=>[current])
    for id in ("l1","l2")
        currents[(:line_from,id)]=[current,-current];currents[(:line_to,id)]=[-current,current]
    end
    net,ACPoint(voltage=volts,currents=currents)
end
_ground_scaling_solve(b)=solve_ivr_nlp_opf(b;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.))

@testset "Finite-ground coordinate equivalence and analytical states" begin
    for y in (.5+1im,-1e4im,-1e10im,1e10+2e10im,-1e5+0im),s_base in (1e3,1e5)
        net,p=_ground_scaling_case(y);original=deepcopy(net)
        @test physical_residuals(net,p;delta_dispatch=:coil).passed
        for specialization in (:off,:conductor_difference,:conductor_regions),linear_elimination in (:off,:impedance_loads,:passive)
            a=build_opf(net,IVRNLP(;s_base,specialization,linear_elimination))
            b=build_opf(net,IVRNLP(;s_base,specialization,linear_elimination,ground_scaling=:voltage))
            @test num_variables(a.model)==num_variables(b.model)
            @test num_constraints(a.model;count_variable_in_set_constraints=true)==num_constraints(b.model;count_variable_in_set_constraints=true)
            @test ivr_nlp_point_report(a,p).passed
            q=ivr_nlp_point_report(b,p);@test q.passed
            @test ivr_nlp_point_report(a,q.reconstructed_point).passed
            @test physical_residuals(net,q.reconstructed_point;delta_dispatch=:coil).passed
            @test q.objective ≈ ivr_nlp_point_report(a,p).objective atol=1e-8
            @test b.electrical.kcl==a.electrical.kcl
            @test b.electrical.equations==a.electrical.equations
            report=b.numerical_diagnostics[:ground_scaling_report]
            expected=abs(y)*b.electrical.zb
            @test length(report.scaled_terminals)==(expected>1 ? 1 : 0)
            if expected>1
                @test only(report.scaled_terminals).scale==expected
                @test only(report.scaled_terminals).terminal=="n"
            else
                @test b.coordinates.projection==a.coordinates.projection
                @test b.coordinates.reconstruction==a.coordinates.reconstruction
            end
            @test net==original
        end
    end
end

@testset "Finite-ground physical-current error is visible after scaling" begin
    net,p=_ground_scaling_case(-1e10im)
    bad=copy(p.voltage);bad[("b0","n")]+=1e-3/(-1e10im)
    badpoint=ACPoint(voltage=bad,currents=p.currents)
    physical=physical_residuals(net,badpoint;delta_dispatch=:coil)
    @test !physical.passed
    @test any(x->x.label=="kcl/b0/n" && x.residual>9e-4,physical.records)
    for specialization in (:off,:conductor_difference,:conductor_regions),linear_elimination in (:off,:passive)
        a=build_opf(net,IVRNLP(;specialization,linear_elimination))
        b=build_opf(net,IVRNLP(;specialization,linear_elimination,ground_scaling=:voltage);optimizer=Ipopt.Optimizer)
        @test ivr_nlp_point_report(a,badpoint).passed # Reproduce the normalized-residual gap.
        @test !ivr_nlp_point_report(b,badpoint).passed
        r=_ground_scaling_solve(b);@test r.solve.optimal
        @test physical_residuals(net,r).passed
        rp=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
        @test ivr_nlp_point_report(b,rp).passed
        @test ivr_nlp_point_report(a,rp).passed
        @test r.voltage_candidate[("b0","n")] ≈ p.voltage[("b0","n")] rtol=1e-7 atol=1e-17
        for field in (:neutral_voltage,:source_current)
            tight=deepcopy(net)
            if field==:neutral_voltage
                tight["bus"]["b1"]["vn_max"]=[.5*abs(p.voltage[("b1","n")])]
            else
                # Single-phase source/current bound remains expressed in SI.
                tight["voltage_source"]["source"]["i_max"]=[.5*abs(only(p.currents[(:voltage_source,"source")]))]
            end
            tb=build_opf(tight,IVRNLP(;specialization,linear_elimination,ground_scaling=:voltage))
            @test !ivr_nlp_point_report(tb,p).passed
            @test !physical_residuals(tight,p;delta_dispatch=:coil).passed
        end
    end
end

@testset "Conservative ground-scaling scope and reuse" begin
    for variant in (:zero,:weak,:fixed,:ideal,:matrix,:duplicate)
        net,_=_ground_scaling_case(-1e10im)
        ground=net["shunt"]["ground"]
        if variant in (:zero,:weak)
            ground["B_1_1"]=variant==:zero ? 0. : -1e-3
            # Keep the zero-ground circuit structurally referenced.
            variant==:zero && (net["voltage_source"]["source"]["terminal_map"]=["a","n"];net["voltage_source"]["source"]["v_magnitude"]=[230.,0.];net["voltage_source"]["source"]["v_angle"]=[0.,0.])
        elseif variant==:fixed
            source=net["voltage_source"]["source"];source["terminal_map"]=["a","n"];source["v_magnitude"]=[230.,0.];source["v_angle"]=[0.,0.]
        elseif variant==:ideal
            net["bus"]["b0"]["perfectly_grounded_terminals"]=["n"]
        elseif variant==:matrix
            ground["terminal_map"]=["n","a"];ground["B_2_2"]=0.
            net["voltage_source"]["neutral_reference"]=Dict("bus"=>"b2","terminal_map"=>["n"],"v_magnitude"=>[0.],"v_angle"=>[0.])
        else
            net["shunt"]["second"]=deepcopy(ground);net["shunt"]["second"]["B_1_1"]=-2e10
        end
        b=build_opf(net,IVRNLP(ground_scaling=:voltage))
        report=b.numerical_diagnostics[:ground_scaling_report]
        @test length(report.scaled_terminals)==(variant==:duplicate ? 1 : 0)
        variant==:duplicate && (@test only(report.scaled_terminals).scale==2e10*b.electrical.zb)
    end
    net,_=_ground_scaling_case(-1e10im)
    net["load"]["cp"]=deepcopy(net["load"]["d2"]);net["load"]["cp"]["model"]="constant_power"
    net["generator"]=Dict("g"=>Dict("bus"=>"b2","terminal_map"=>["a","n"],"configuration"=>"SINGLE_PHASE","p_min"=>[0.],"p_max"=>[0.],"q_min"=>[0.],"q_max"=>[0.],"cost"=>[1.]))
    b=build_opf(net,IVRNLP(ground_scaling=:voltage,linear_elimination=:passive,specialization=:conductor_regions);optimizer=Ipopt.Optimizer)
    vars=all_variables(b.model);maps=deepcopy(b.coordinates.reconstruction)
    update_ivr_loads!(b,Dict("cp"=>(p=[100.],q=[20.])))
    update_ivr_generators!(b,Dict("g"=>(p_min=[20.],p_max=[20.],cost=[.5])))
    r=_ground_scaling_solve(b);@test r.solve.optimal
    @test physical_residuals(b.network,r).passed
    @test all_variables(b.model)==vars
    @test b.coordinates.reconstruction==maps
    @test ivr_nlp_point_report(build_opf(b.network,IVRNLP()),ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)).passed
    @test_throws ArgumentError build_opf(net,IVRNLP(ground_scaling=:unknown))
end
