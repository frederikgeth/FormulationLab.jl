using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
isdefined(@__MODULE__,:_sdp_tx_case) || include("sdp_transformer_fixtures.jl")
isdefined(@__MODULE__,:_audit_transformer_state) || include("ac_validation_fixtures.jl")
isdefined(@__MODULE__,:IVRLiftingBlockStudy) || include("../examples/benchmark_ivr_lifting_blocks.jl")
const _TS_SETTINGS=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.,max_iter=500)
_ts_solve(b)=solve_ivr_nlp_opf(b;solver_options=_TS_SETTINGS)
_ts_point(r)=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)

@testset "Nominal transformer bases preserve independent SI states and bounds" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta"),reverse in (false,true)
        net,p=_audit_transformer_state(kind;reverse,rotation=.23)
        # Avoid treating roundoff-sized manufactured neutral currents as ratings.
        tx=net["transformer"][kind]["tx"]
        for side in ("from","to");tx["i_max_$side"]=max.(tx["i_max_$side"],1e-6);end
        full=build_opf(net,IVRNLP(objective=:source_import))
        @test physical_residuals(net,p;delta_dispatch=:coil).passed
        for s_base in (1e3,1e5),device_elimination in (:off,:transformer_currents),
            row_scaling in (:legacy,:composed),lifting in (:off,:bounded_observations)
            opts=(;s_base,objective=:source_import,device_elimination,row_scaling,lifting,
                transformer_scaling=:nominal,specialization=:conductor_regions,linear_elimination=:passive_blocks)
            b=build_opf(net,IVRNLP(;opts...))
            rep=b.numerical_diagnostics[:transformer_scaling_report]
            @test rep.status==:applied && isempty(rep.retained_buses)
            @test rep.bases["f"]≈maximum(net["voltage_source"]["s"]["v_magnitude"])
            @test rep.bases["t"]≈rep.bases["f"]/2
            @test !isempty(rep.scaled_coordinates)
            supplied=ivr_nlp_point_report(b,p)
            @test supplied.passed && length(supplied.variable_values)==num_variables(b.model)
            @test ivr_nlp_point_report(full,supplied.reconstructed_point).passed
            @test physical_residuals(net,supplied.reconstructed_point;delta_dispatch=:coil).passed
            @test supplied.objective≈ivr_nlp_point_report(full,p).objective atol=1e-8
            ev(row,x)=FormulationLab._linivr_eval(row,x)
            y=ComplexF64[sin(k)+im*cos(2k) for k in eachindex(b.coordinates.projection)]
            z=[ev(row,y) for row in b.coordinates.reconstruction]
            @test [ev(row,z) for row in b.coordinates.projection]≈y atol=1e-11
            # Negative witnesses at both original winding/terminal current limits.
            for side in ("from","to")
                tight=deepcopy(net);limit=tight["transformer"][kind]["tx"]["i_max_$side"]
                k=findfirst(>(1e-6),limit);limit[k]*=.5
                @test !ivr_nlp_point_report(build_opf(tight,IVRNLP(;opts...)),p).passed
                @test !physical_residuals(tight,p;delta_dispatch=:coil).passed
            end
        end
    end
end

@testset "Large-ratio scaling, starts, JSON and model updates" begin
    for ratio in (1.,10.,11000/415),row_scaling in (:legacy,:composed)
        net=_sdp_tx_case("single_phase");tx=net["transformer"]["single_phase"]["tx"]
        source=net["voltage_source"]["s"];source["v_magnitude"]=[230ratio,0.]
        tx["v_nom_from"]=230ratio;tx["v_nom_to"]=230.
        tx["r_series_from"]=.01ratio^2;tx["x_series_from"]=.005ratio^2
        tx["r_series_to"]=.01;tx["x_series_to"]=.005
        net["load"]=Dict("d"=>Dict("bus"=>"t","terminal_map"=>["p","n"],"configuration"=>"SINGLE_PHASE","model"=>"constant_power","p_nom"=>[1000.],"q_nom"=>[200.]))
        net["generator"]=Dict("g"=>Dict("bus"=>"t","terminal_map"=>["p","n"],"configuration"=>"SINGLE_PHASE","p_min"=>[0.],"p_max"=>[300.],"q_min"=>[0.],"q_max"=>[0.],"s_max"=>[250.],"cost"=>[0.]))
        full=build_opf(net,IVRNLP(objective=:source_import);optimizer=Ipopt.Optimizer)
        rf=_ts_solve(full);@test rf.solve.optimal
        for device_elimination in (:off,:transformer_currents),ground_scaling in (:off,:voltage)
            b=build_opf(net,IVRNLP(;objective=:source_import,transformer_scaling=:nominal,
                row_scaling,device_elimination,ground_scaling,lifting=:bounded_observations);optimizer=Ipopt.Optimizer)
            start=ivr_nlp_point_report(b,IVRLiftingBlockStudy.start_point(net))
            @test isempty(start.missing_channels) && length(start.variable_values)==num_variables(b.model)
            @test max(start.max_binding_residual_pu,start.max_reconstruction_residual_pu)<1e-10
            for (v,x) in start.variable_values;set_start_value(v,x);end
            r=_ts_solve(b);@test r.solve.optimal && physical_residuals(net,r).passed
            @test ivr_nlp_point_report(full,_ts_point(r)).passed
            @test ivr_nlp_point_report(b,_ts_point(rf)).passed
            @test r.objective≈rf.objective atol=1e-5
            for field in ("v_min","v_max","s_max")
                tight=deepcopy(net)
                if field=="s_max"
                    tight["generator"]["g"][field]=[100.]
                else
                    v=abs(rf.voltage_candidate[("t","p")])
                    tight["bus"]["t"][field]=field=="v_min" ? [1.2v,0.] : [.8v,1.]
                end
                bad=build_opf(tight,IVRNLP(;transformer_scaling=:nominal,row_scaling,device_elimination))
                @test !ivr_nlp_point_report(bad,_ts_point(rf)).passed
                @test !physical_residuals(tight,rf).passed
            end
            d=result_dict(b,r);f=result_dict(full,rf)
            for (bus,ts) in f["bus"],(t,v) in ts,field in ("vr","vi")
                @test d["bus"][bus][t][field]≈v[field] atol=1e-5
            end
            io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
            vars=all_variables(b.model);projection=deepcopy(b.coordinates.projection)
            update_ivr_loads!(b,Dict("d"=>(p=[900.],q=[100.])))
            update_ivr_generators!(b,Dict("g"=>(p_min=[100.],p_max=[100.],q_min=[0.],q_max=[0.])))
            rr=_ts_solve(b);@test rr.solve.optimal && physical_residuals(b.network,rr).passed
            @test all_variables(b.model)==vars && b.coordinates.projection==projection
        end
    end
end

@testset "Base assignment, source fixing and conservative fallback" begin
    F=FormulationLab
    net=_sdp_tx_case("single_phase");e=(;vb=230.)
    net["line"]=Dict("cycle"=>Dict("bus_from"=>"f","bus_to"=>"t"))
    report=F._ivrn_region_bases(net,e)
    @test all(==("inconsistent_nominal_cycle"),values(report.retained_buses))
    @test all(==(230.),values(report.bases))
    delete!(net,"line")
    net["voltage_source"]["second"]=Dict("bus"=>"t","v_magnitude"=>[110.])
    @test all(==("inconsistent_source_bases"),values(F._ivrn_region_bases(net,e).retained_buses))
    delete!(net["voltage_source"],"second")
    net["voltage_source"]["s"]["v_magnitude"]=[0.,0.]
    @test all(==("no_nonzero_source_base"),values(F._ivrn_region_bases(net,e).retained_buses))
    # Open switches leave independent source regions independent.
    net=_sdp_tx_case("single_phase");delete!(net,"transformer")
    net["voltage_source"]["second"]=Dict("bus"=>"t","terminal_map"=>["p","n"],"v_magnitude"=>[115.,0.],"v_angle"=>[.2,0.])
    net["switch"]=Dict("open"=>Dict("bus_from"=>"f","bus_to"=>"t","terminal_map_from"=>["p","n"],"terminal_map_to"=>["p","n"],"open_switch"=>true))
    b=build_opf(net,IVRNLP(transformer_scaling=:nominal);optimizer=Ipopt.Optimizer)
    @test b.numerical_diagnostics[:transformer_scaling_report].bases["t"]==115.
    r=_ts_solve(b);@test r.solve.optimal && physical_residuals(net,r).passed
    @test r.voltage_candidate[("t","p")]≈115cis(.2) atol=1e-9
    for (k,v) in b.electrical.fixed_source_coordinates
        j,a=only(b.coordinates.reconstruction[k])
        @test a*complex(fix_value(b.coordinates.real_variables[j]),fix_value(b.coordinates.imaginary_variables[j]))≈v
    end
    @test_throws ArgumentError build_opf(net,IVRNLP(transformer_scaling=:invalid))
    @test_throws ArgumentError build_opf(net,IVRNLP(row_scaling=:invalid))
    a=build_opf(net,IVRNLP());b=build_opf(net,IVRNLP(transformer_scaling=:off,row_scaling=:legacy))
    @test sprint(show,a.model)==sprint(show,b.model)
    # Mixed projection units retain a coordinate rather than guessing its type.
    net=_sdp_tx_case("single_phase");full=build_opf(net,IVRNLP());maps=deepcopy(full.coordinates)
    mixed=(;projection=[F._SDPRow(1=>1,2=>1)],reconstruction=[F._SDPRow(1=>1) for _ in 1:full.electrical.coordinate_count[]])
    _,report=F._ivrn_transformer_coordinates(net,full.electrical,mixed,:nominal)
    @test report.retained_coordinates[1]=="mixed_coordinate_bases"
end

@testset "Scaling composes with charged blocks and finite-ground coordinates" begin
    L=IVRLiftingBlockStudy
    for charged in (false,true)
        net=L.case(segments=8,charged=charged,transformers=true,tight=true)
        hv=deepcopy(net["bus"]["b0"])
        for key in keys(hv)
            startswith(key,"v") && hv[key] isa AbstractVector{<:Real} && (hv[key]=10 .* hv[key])
        end
        net["bus"]["hv"]=hv
        source=net["voltage_source"]["source"];source["bus"]="hv";source["v_magnitude"] .*=10
        net["transformer"]["single_phase"]["entry"]=Dict("bus_from"=>"hv","bus_to"=>"b0",
            "terminal_map_from"=>["a","n"],"terminal_map_to"=>["a","n"],
            "v_nom_from"=>2300.,"v_nom_to"=>230.,"r_series_from"=>1.,"x_series_from"=>.5,
            "r_series_to"=>.01,"x_series_to"=>.005)
        net["shunt"]=Dict("finite"=>Dict("bus"=>"b2","terminal_map"=>["n"],"G_1_1"=>1e4))
        full=build_opf(net,IVRNLP(objective=:source_import,ground_scaling=:voltage);optimizer=Ipopt.Optimizer)
        rf=_ts_solve(full);@test rf.solve.optimal && physical_residuals(net,rf).passed
        for device_elimination in (:off,:transformer_currents),row_scaling in (:legacy,:composed)
            b=build_opf(net,IVRNLP(;objective=:source_import,ground_scaling=:voltage,
                transformer_scaling=:nominal,row_scaling,device_elimination,specialization=:conductor_regions,
                linear_elimination=:passive_blocks,lifting=:bounded_observations,observation_sharing=:exact);optimizer=Ipopt.Optimizer)
            @test !isempty(b.numerical_diagnostics[:linear_elimination_report].series_buses)
            @test !isempty(b.numerical_diagnostics[:ground_scaling_report].scaled_terminals)
            @test b.numerical_diagnostics[:transformer_scaling_report].bases["b8"]≈230.
            @test ivr_nlp_point_report(b,_ts_point(rf)).passed
            start=ivr_nlp_point_report(b,L.start_point(net))
            @test isempty(start.missing_channels) && length(start.variable_values)==num_variables(b.model)
            @test max(start.max_binding_residual_pu,start.max_reconstruction_residual_pu)<1e-10
            r=_ts_solve(b);@test r.solve.optimal && physical_residuals(net,r).passed
            @test r.objective≈rf.objective atol=1e-5
            @test ivr_nlp_point_report(full,_ts_point(r)).passed
        end
    end
end

@testset "Declared nominal-base scope and overflow rollback" begin
    F=FormulationLab
    for kind in ("single_phase_autotransformer","open_delta_regulator")
        net=_sdp_tx_case(kind;tap=1.04)
        rep=F._ivrn_region_bases(net,(;vb=230.))
        @test rep.bases["f"]==rep.bases["t"]==230.
    end
    net,p=_audit_nwinding_state();b=build_opf(net,IVRNLP(transformer_scaling=:nominal))
    @test ivr_nlp_point_report(b,p).passed
    @test !isempty(b.numerical_diagnostics[:transformer_scaling_report].skipped_transformers)
    net=_sdp_tx_case("single_phase");full=build_opf(net,IVRNLP())
    maps=(;projection=[F._SDPRow(2=>floatmax(Float64))],reconstruction=[F._SDPRow(1=>1) for _ in 1:full.electrical.coordinate_count[]])
    returned,rep=F._ivrn_transformer_coordinates(net,full.electrical,maps,:nominal)
    @test returned==maps && rep.status==:retained_nonfinite_map
    @test_throws IVRNLPInapplicableError F._ivrn_scaled_row_norm(F._SDPRow(1=>floatmax(Float64)),(;reconstruction=[F._SDPRow(1=>2)]))
end
