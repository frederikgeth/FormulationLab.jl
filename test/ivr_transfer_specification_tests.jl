module IVRTransferSpecificationTests
using Test, FormulationLab, JuMP, Ipopt, JSON3
include("../examples/ivr_transfer_specification.jl")
include("../examples/benchmark_ivr_lifting_blocks.jl")
const S=IVRTransferSpecification
const L=IVRLiftingBlockStudy

function fixture(;dispatch=true)
    n=Dict{String,Any}("bus"=>Dict("b"=>Dict("terminal_names"=>["a","n"],"perfectly_grounded_terminals"=>["n"])),
        "voltage_source"=>Dict("s"=>Dict("bus"=>"b","terminal_map"=>["a","n"],
            "v_magnitude"=>[230.,0.],"v_angle"=>[0.,0.])),
        "load"=>Dict("d"=>Dict("bus"=>"b","terminal_map"=>["a","n"],"configuration"=>"SINGLE_PHASE",
            "model"=>"constant_power","p_nom"=>[1000.],"q_nom"=>[200.])))
    dispatch && (n["generator"]=Dict("g"=>Dict("bus"=>"b","terminal_map"=>["a","n"],
        "configuration"=>"SINGLE_PHASE","p_min"=>[0.],"p_max"=>[600.],"q_min"=>[-300.],"q_max"=>[300.])))
    n
end
common()=IVRNLPOptions(s_base=1e4,transformer_nameplate=:bmopftools,transformer_scaling=:nominal,
    ground_scaling=:voltage,row_scaling=:composed,lifted_power_base=500.,observation_sharing=:signed,
    load_power_lifting=true)
shape(x::AbstractDict)=Dict(k=>shape(v) for (k,v) in x)
shape(x::AbstractVector)=shape.(x)
shape(x)=nothing

@testset "Prospective workload declarations do not require dispatch" begin
    for dispatch in (false,true)
        net=fixture(;dispatch);before=deepcopy(net)
        for kind in (:quadratic_cost,:exchange_tracking)
            w=S.workload(net,kind;exchange_target_W=350.)
            @test w.channels.active_dispatch_box_freedom==dispatch
            @test w.channels.reactive_dispatch_box_freedom==dispatch
            @test length(w.channels.sources)==2
            @test w.objective_scale==1 && !w.input_modified && !w.legacy_prices_used
            @test net==before
        end
    end
    n=fixture();n["generator"]["g"]["p_max"]=[0.]
    @test !S.channels(n).active_dispatch_box_freedom
    @test S.channels(n).reactive_dispatch_box_freedom
    for change in (d->delete!(d,"p_min"),d->(d["q_min"]=[NaN]),d->(d["p_max"]=[true]),
                   d->(d["p_max"]=[-1.]),d->(d["p_max"]=[1.,2.]),
                   d->(d["configuration"]="unknown"),d->(d["terminal_map"]=["a","a"]))
        n=fixture();change(n["generator"]["g"])
        @test_throws ArgumentError S.workload(n,:quadratic_cost)
    end
    for target in (nothing,NaN,Inf,true)
        @test_throws ArgumentError S.workload(fixture(),:exchange_tracking;exchange_target_W=target)
    end
    @test_throws ArgumentError S.workload(fixture(),:unknown)
    n=fixture();delete!(n,"voltage_source")
    @test_throws ArgumentError S.workload(n,:quadratic_cost)
    n=fixture();n["generator"]=[]
    @test_throws ArgumentError S.workload(n,:quadratic_cost)
end

@testset "Aggregate source power and converter internal cost semantics" begin
    n=fixture();n["voltage_source"]["second"]=deepcopy(n["voltage_source"]["s"])
    n["ibr"]=Dict("c"=>Dict("topology"=>"THREE_LEG","terminal_map"=>["a","b","c"],
        "p_min"=>zeros(3),"p_max"=>fill(600.,3),"q_min"=>fill(-300.,3),"q_max"=>fill(300.,3)))
    w=S.workload(n,:quadratic_cost)
    powers=Dict((:voltage_source,"s")=>[500+100im,0im],(:voltage_source,"second")=>[300+60im,0im],
        (:generator,"g")=>[200+40im],(:ibr,"c")=>[100+20im,200-10im,150+30im],
        (:ibr_internal,"c")=>[110+21im,220-8im,165+31im])
    evaluate(t)=begin
        z=sum(a*(t.quantity==:p ? real(powers[(f,id)][k]) : imag(powers[(f,id)][k]))
            for ((f,id,k),a) in zip(t.channels,t.weights))-t.target
        t.linear*z+t.quadratic*z^2
    end
    expected=.25*.8+.02*.8^2+.002*.16^2+.10*(.2+.110+.220+.165)+
        .02*(.2^2+.1^2+.2^2+.15^2)+.002*(.04^2+.02^2+.01^2+.03^2)
    @test sum(evaluate,w.terms)≈expected atol=1e-14
    @test length(w.terms[1].channels)==4 # square of aggregate, not sum of squares
    tracking=S.workload(n,:exchange_tracking;exchange_target_W=350.)
    @test all(c[1]!=:ibr_internal for t in tracking.terms for c in t.channels)
    for family in ("generator","ibr"),d in values(n[family]);d["cost"]=[-999.];end
    @test JSON3.write(S.workload(n,:quadratic_cost).terms)==JSON3.write(w.terms)
end

@testset "Nine finite arms retain common units and isolate factors" begin
    n=fixture();o=common();before=deepcopy(n)
    panel=S.profiles(n,:quadratic_cost;common=o)
    @test n==before
    @test length(panel.candidates)==9 && allunique(p.name for p in panel.candidates)
    @test first(panel.candidates).name=="full_powers"
    @test panel.reference.lifting==:off && !panel.reference.load_power_lifting
    allowed=Set([:specialization,:linear_elimination,:device_elimination,:lifting,:zero_load_elimination])
    control=first(panel.candidates).options
    for p in panel.candidates
        @test Set(k for k in fieldnames(IVRNLPOptions) if
            JSON3.write(getfield(p.options,k))!=JSON3.write(getfield(control,k))) ⊆ allowed
    end
    empty!(control.power_terms[1].channels)
    @test all(!isempty(p.options.power_terms[1].channels) for p in panel.candidates[2:end])
    @test !isempty(panel.reference.power_terms[1].channels)
    @test !isempty(panel.workload.terms[1].channels)
    for bad in (S.clone(o;zero_load_elimination=true),S.clone(o;power_sharing=:generators),
                S.clone(o;fixed_observation_elimination=true),S.clone(o;transformer_nameplate=:ignore),
                S.clone(o;observation_selection=:coils))
        @test_throws ArgumentError S.profiles(n,:quadratic_cost;common=bad)
    end
    # Specification does not inspect transformer kinds or perform a hidden build.
    n["transformer"]=Dict("n_winding"=>Dict("pending_physical_validation"=>Dict()))
    @test length(S.profiles(n,:exchange_tracking;common=o,exchange_target_W=350.).candidates)==9
end

@testset "Closed-form power workloads with active bound and canonical recovery" begin
    for dispatch in (false,true),kind in (:quadratic_cost,:exchange_tracking)
        n=fixture(;dispatch);before=deepcopy(n);start=L.start_point(n)
        panel=S.profiles(n,kind;common=common(),exchange_target_W=350.)
        ref=build_opf(n,IVRNLP(panel.reference));anchor=nothing;export_shape=nothing
        pg=dispatch ? 600. : 0.
        qg=dispatch ? (kind==:quadratic_cost ? 100. : 200/1.01) : 0.
        ps=1000-pg;qs=200-qg
        expected=kind==:quadratic_cost ? .25ps/1000+.02ps^2/1e6+.002qs^2/1e6+
            .10pg/1000+.02pg^2/1e6+.002qg^2/1e6 :
            ((ps-350)^2+qs^2)/1e6+(dispatch ? ((pg-300)^2+qg^2)/1e8 : 0.)
        for p in panel.candidates
            b=build_opf(n,IVRNLP(p.options);optimizer=Ipopt.Optimizer)
            encoded=ivr_nlp_point_report(b,start)
            @test isempty(encoded.missing_channels) && length(encoded.variable_values)==num_variables(b.model)
            @test max(encoded.max_binding_residual_pu,encoded.max_reconstruction_residual_pu)<=1e-10
            for (v,x) in encoded.variable_values;set_start_value(v,x);end
            r=solve_ivr_nlp_opf(b;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,
                acceptable_iter=0,bound_relax_factor=0.,max_iter=100))
            @test r.solve.optimal && physical_residuals(n,r).passed
            @test sum(r.powers[(:voltage_source,"s")])≈ps+im*qs atol=1e-4
            dispatch && @test only(r.powers[(:generator,"g")])≈pg+im*qg atol=1e-4
            @test r.objective≈expected atol=1e-8
            point=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)
            @test ivr_nlp_point_report(b,point).passed && ivr_nlp_point_report(ref,point).passed
            anchor===nothing && (anchor=point)
            @test ivr_nlp_point_report(b,anchor).passed
            exported=result_dict(b,r);io=IOBuffer();write_result(exported,io);seekstart(io)
            @test isequal(read_result(io),exported)
            physical_shape=shape(Dict(k=>v for (k,v) in exported if !startswith(k,"_")))
            export_shape===nothing && (export_shape=physical_shape)
            @test physical_shape==export_shape
            @test n==before
        end
    end
end
end
