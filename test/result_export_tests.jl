using Test, FormulationLab, JuMP, Ipopt, Clarabel, JSON3, LinearAlgebra
isdefined(@__MODULE__,:ivr_compiler_case) || include("../examples/ivr_compiler_cases.jl")
isdefined(@__MODULE__,:_sdp_tx_case) || include("sdp_transformer_fixtures.jl")
isdefined(@__MODULE__,:_audit_transformer_state) || include("ac_validation_fixtures.jl")
isdefined(@__MODULE__,:_l3f_case) || include("lindist3flow_fixtures.jl")
const _EXPORT_SETTINGS=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,acceptable_iter=0,bound_relax_factor=0.)
function _export_paths(x,path=String[])
    x isa AbstractDict && return reduce(vcat,[_export_paths(x[k],[path;string(k)]) for k in sort!(collect(keys(x));by=string) if k!="_formulationlab"];init=Vector{String}[])
    x isa AbstractVector && return reduce(vcat,[_export_paths(v,[path;string(k)]) for (k,v) in enumerate(x)];init=Vector{String}[])
    [path]
end
_export_at(d,path)=foldl((x,k)->x isa AbstractVector ? x[parse(Int,k)] : x[k],path;init=d)

@testset "BMOPFTools layout, exact recovery and JSON round trip" begin
    for m in (2,3,4)
        net=ivr_compiler_case(conductors=m,segments=3)
        delete!(net["load"],"d1");delete!(net["load"],"d2")
        full=nothing
        for specialization in (:off,:conductor_difference,:conductor_regions),elimination in (:off,:passive,:passive_chains)
            b=build_opf(net,IVRNLP(;specialization,linear_elimination=elimination);optimizer=Ipopt.Optimizer)
            r=solve_ivr_nlp_opf(b;solver_options=_EXPORT_SETTINGS);@test r.solve.optimal
            d=result_dict(net,r);@test isequal(d,result_dict(b,r))
            @test d["result_count"]==1 && d["solve_time"]>=0 && d["feasible"]
            @test d["_formulationlab"]["state_kind"]=="exact_coordinate_recovery"
            @test d["_formulationlab"]["initialisation_available"]
            @test d["bus"]["b1"]["a"]["vm"] ≈ abs(r.voltage_candidate[("b1","a")])
            @test d["line"]["l1"]["a"]["cr_fr"] ≈ real(r.current_candidate[(:line_from,"l1")][1])
            @test d["load"]["d3"]["a"]["pd"] ≈ net["load"]["d3"]["p_nom"][1] atol=1e-5
            @test d["losses"]["p_loss"] ≈ sum(real(sum(r.powers[(:line_from,id)])+sum(r.powers[(:line_to,id)])) for id in keys(net["line"])) atol=1e-8
            if m!=3
                @test isnan(d["ground"]["b0"]["n"]["cgm"])
                @test isnan(d["_formulationlab"]["devices"]["voltage_source"]["source"]["terminal_current"][end]["cm"])
                @test d["bus"]["b0"]["n"]["vm"]==0
            end
            if full===nothing;full=d;else
                @test _export_paths(d)==_export_paths(full)
                for path in _export_paths(full)
                    first(path) in ("solve_time","initialisation") && continue
                    a=_export_at(d,path);c=_export_at(full,path)
                    @test a isa Real && c isa Real ? (isnan(a)&&isnan(c) || isapprox(a,c;atol=1e-5,rtol=1e-7)) : a==c
                end
            end
            io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
            io=IOBuffer();write_result(d,io;indent=nothing,nonfinite=:null)
            text=String(take!(io));@test !occursin("NaN",text)
            @test JSON3.read(text)["bus"]["b1"]["a"]["vm"] ≈ d["bus"]["b1"]["a"]["vm"]
        end
    end
end

@testset "Owned export snapshot, failures and distinct model meanings" begin
    @test FormulationLab._result_digest(Dict("x"=>230.0,"y"=>-0.0))==FormulationLab._result_digest(Dict("y"=>0,"x"=>230))
    @test FormulationLab._result_digest(Dict("x"=>9007199254740993))!=FormulationLab._result_digest(Dict("x"=>9007199254740992.0))
    @test FormulationLab._result_digest(Dict("x"=>true))!=FormulationLab._result_digest(Dict("x"=>1))
    net=ivr_compiler_case(conductors=2,segments=1)
    b=build_opf(net,IVRNLP();optimizer=Ipopt.Optimizer)
    r=solve_ivr_nlp_opf(b;solver_options=_EXPORT_SETTINGS);before=result_dict(net,r)
    update_ivr_loads!(b,Dict("d1"=>(p=[1000.],q=[100.])))
    after=solve_ivr_nlp_opf(b;solver_options=_EXPORT_SETTINGS)
    @test isequal(result_dict(net,r),before)
    @test_throws ArgumentError result_dict(b,r)
    @test result_dict(b,after)["load"]["d1"]["a"]["pd"] ≈ 1000. atol=1e-5
    @test_throws ArgumentError write_result(before,IOBuffer();nonfinite=:unknown)
    @test_throws ArgumentError write_result(before,IOBuffer();indent=-1)
    mktemp() do path,io
        write_result(before,path);@test isequal(read_result(path),before)
    end
    # A diagnostic primal is kept for export without weakening solve acceptance.
    failed=solve_opf(net,IVRNLP();optimizer=Ipopt.Optimizer,solver_options=(print_level=0,max_iter=0))
    @test !failed.solve.optimal
    d=result_dict(net,failed)
    @test d["termination_status"]=="ITERATION_LIMIT"
    @test d["result_count"]==1 && isfinite(d["bus"]["b1"]["a"]["vr"])
    @test isempty(failed.voltage_candidate)
    lin=solve_opf(net,LinIVR();optimizer=Clarabel.Optimizer,solver_options=(verbose=false,))
    d=result_dict(net,lin)
    @test d["_formulationlab"]["state_kind"]=="approximate_state"
    @test !isempty(d["_formulationlab"]["native_powers"])
    @test _export_paths(d)==_export_paths(before)
    io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
    n=_l3f_case()
    r=solve_opf(n,LinDist3Flow();optimizer=Clarabel.Optimizer,solver_options=(verbose=false,))
    d=result_dict(r)
    @test isequal(result_dict(JSON3.write(n),r),d)
    @test isequal(result_dict(read_bmopf(JSON3.write(n)),r),d)
    @test d["_formulationlab"]["state_kind"]=="fixed_angle_estimate"
    @test haskey(d["_formulationlab"],"native_model")
    @test !d["_formulationlab"]["initialisation_available"]
    io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
    exact=solve_opf(n,IVRNLP();optimizer=Ipopt.Optimizer,solver_options=_EXPORT_SETTINGS)
    @test exact.solve.optimal
    @test _export_paths(d)==_export_paths(result_dict(n,exact))
    for formulation in (IVRSDP(),IVRSOC(),BranchFlowSDP())
        r=solve_opf(net,formulation;optimizer=Clarabel.Optimizer,solver_options=(verbose=false,))
        d=result_dict(net,r)
        @test d["_formulationlab"]["state_kind"]=="relaxation_candidate"
        @test _export_paths(d)==_export_paths(before)
        @test !isempty(d["_formulationlab"]["native_powers"])
        @test haskey(d["_formulationlab"],"native_moments")
        @test d["_formulationlab"]["native_power_kind"]=="relaxed_moment"
        io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
    end
end

@testset "Multiwinding and regulator physical observations" begin
    solved=SolveStatus("LOCALLY_SOLVED","FEASIBLE_POINT",true,true,true,true)
    for kind in ("single_phase_autotransformer","open_delta_regulator","n_winding")
        net,p=kind=="n_winding" ? _audit_nwinding_state() : _audit_transformer_state(kind)
        if kind=="n_winding"
            net["transformer"][kind]["tx"]["windings"][3]["s_max"]=2000.
            net["transformer"][kind]["tx"]["windings"][4]["s_max"]=[2000.,3000.,4000.]
        end
        r=IVRNLPResult(0.,p.voltage,p.currents,Dict{Tuple{Symbol,String},Vector{ComplexF64}}(),solved,Dict{Symbol,Any}())
        d=result_dict(net,r);record=d["transformer"]["tx"];extra=d["_formulationlab"]["devices"]["transformer"]["tx"]
        terminal_loss=0im
        for label in (kind=="n_winding" ? ["w$k" for k in 1:4] : ["fr","to"])
            e=extra[label]
            @test length(e["terminal_current"])==length(e["terminal_map"])
            terminal_loss+=sum(complex(s["p"],s["q"]) for s in e["terminal_power"])
            k=kind=="n_winding" ? parse(Int,label[2:end]) : 0
            channel=kind=="n_winding" ? (:transformer_coil,"n_winding/tx/$k") :
                (label=="fr" ? :transformer_coil_from : :transformer_coil_to,"$kind/tx")
            for (j,i) in enumerate(p.currents[channel])
                @test complex(record[label][string(j)]["cr"],record[label][string(j)]["ci"]) ≈ i
                if kind=="n_winding" && k in (3,4)
                    @test record[label][string(j)]["s_max"]==(k==3 ? 2000. : [2000.,3000.,4000.][j])
                    @test record[label][string(j)]["s"] ≈ e["coil_power"][j]["s"]
                end
                v=e["coil_voltage"][j];s=e["coil_power"][j]
                @test complex(s["p"],s["q"]) ≈ complex(v["vr"],v["vi"])*conj(i)
            end
        end
        @test complex(record["loss"]["p_loss"],record["loss"]["q_loss"]) ≈ terminal_loss
        io=IOBuffer();write_result(d,io);seekstart(io);@test isequal(read_result(io),d)
    end
end

@testset "Transformer series, terminal and loss exports" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta")
        net,p=_audit_transformer_state(kind)
        for side in ("from","to")
            d=net["transformer"][kind]["tx"];haskey(d,"i_max_$side") && (d["i_max_$side"]=max.(d["i_max_$side"],1e-6))
        end
        r=solve_opf(net,IVRNLP();optimizer=Ipopt.Optimizer,solver_options=_EXPORT_SETTINGS)
        @test r.solve.optimal
        d=result_dict(net,r);rec=d["transformer"]["tx"]
        @test haskey(rec,"fr") && haskey(rec,"to") && haskey(rec,"loss")
        @test d["losses"]["p_loss"] ≈ real(sum(r.powers[(:transformer_from,"$kind/tx")])+sum(r.powers[(:transformer_to,"$kind/tx")])) atol=1e-8
        @test haskey(d["_formulationlab"]["devices"]["transformer"]["tx"]["fr"],"coil_voltage")
    end
end

@testset "Derived IBR, capacitor, shunt, ground and line observations" begin
    # These independent witness constructors are also used by the physics tests.
    isdefined(@__MODULE__,:_ibr_state) || include("ivr_ibr_tests.jl")
    isdefined(@__MODULE__,:_capacitor_state) || include("ivr_capacitor_tests.jl")
    solved=SolveStatus("LOCALLY_SOLVED","FEASIBLE_POINT",true,true,true,true)
    for m in (2,3,4)
        net,p,_,_=_ibr_state(m)
        r=IVRNLPResult(0.,p.voltage,p.currents,Dict{Tuple{Symbol,String},Vector{ComplexF64}}(),solved,Dict{Symbol,Any}())
        d=result_dict(net,r)
        tm=net["ibr"]["g"]["terminal_map"];u=m==2 ? [p.voltage[("b1","a")]-p.voltage[("b1","n")]] : m==3 ?
            [p.voltage[("b1",tm[k])]-p.voltage[("b1",tm[mod1(k+1,3)])] for k in 1:3] : [p.voltage[("b1",t)]-p.voltage[("b1","n")] for t in tm[1:3]]
        coil=p.currents[(:ibr_internal,"g")].-.001im.*u
        for (k,t) in enumerate(tm[1:length(coil)])
            @test complex(d["ibr"]["g"][t]["cri"],d["ibr"]["g"][t]["cii"]) ≈ coil[k]
            @test d["ibr"]["g"][t]["pg"] ≈ real(u[k]*conj(coil[k]))
            internal=d["_formulationlab"]["devices"]["ibr"]["g"]["internal_voltage"][k]
            @test complex(internal["vr"],internal["vi"]) ≈ u[k]+(.2+.08im)*p.currents[(:ibr_internal,"g")][k]
        end
        # Missing delta coil circulation cannot be guessed from terminal currents.
        if m==3
            c=deepcopy(p.currents);delete!(c,(:ibr_internal,"g"))
            missing=result_dict(net,IVRNLPResult(0.,p.voltage,c,r.powers,solved,r.numerical_diagnostics))
            @test isnan(missing["ibr"]["g"]["a"]["cri"])
            @test isfinite(missing["_formulationlab"]["devices"]["ibr"]["g"]["terminal_current"][1]["cr"])
        end
        net,p,D,b=_capacitor_state(m)
        r=IVRNLPResult(0.,p.voltage,p.currents,Dict{Tuple{Symbol,String},Vector{ComplexF64}}(),solved,Dict{Symbol,Any}())
        d=result_dict(net,r);tm=net["capacitor"]["c"]["terminal_map"]
        u=D*[p.voltage[("b1",t)] for t in tm];terminal=transpose(D)*(im.*b.*u)
        for (t,i) in zip(tm,terminal)
            rec=d["capacitor"]["c"]["terminals"][t]
            @test complex(rec["cr"],rec["ci"]) ≈ i
        end
        @test d["capacitor"]["c"]["q"] ≈ sum(b.*abs2.(u))
    end
    # A grounded load bus without a source has an identifiable aggregate reaction.
    net=ivr_compiler_case(conductors=2,segments=1)
    net["bus"]["b1"]["perfectly_grounded_terminals"]=["n"]
    net["shunt"]=Dict("s"=>Dict("bus"=>"b1","terminal_map"=>["a"],"G_1_1"=>.001,"B_1_1"=>-.002))
    net["linecode"]["wire"]["B_from_1_1"]=1e-4
    r=solve_opf(net,IVRNLP();optimizer=Ipopt.Optimizer,solver_options=_EXPORT_SETTINGS);@test r.solve.optimal
    d=result_dict(net,r)
    @test isfinite(d["ground"]["b1"]["n"]["cgm"])
    @test d["line"]["l1"]["a"]["cm_fr"] != d["line"]["l1"]["a"]["cm_to"]
    @test d["_formulationlab"]["devices"]["shunt"]["s"]["power"][1]["p"] ≈ .001abs2(r.voltage_candidate[("b1","a")])
    @test d["_formulationlab"]["devices"]["voltage_source"]["source"]["terminal_power"][end]["p"]==0
    @test !isempty(d["_formulationlab"]["unavailable"])
    # A flattening collision must never overwrite a transformer silently.
    collision=deepcopy(net);collision["transformer"]=Dict("single_phase"=>Dict("x"=>Dict()),"center_tap"=>Dict("x"=>Dict()))
    rr=IVRNLPResult(r.objective,r.voltage_candidate,r.current_candidate,r.powers,r.solve,Dict{Symbol,Any}())
    @test_throws ArgumentError result_dict(collision,rr)
end
