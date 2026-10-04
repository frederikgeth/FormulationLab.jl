using Test, FormulationLab, JuMP, Ipopt, LinearAlgebra
isdefined(@__MODULE__,:ivr_compiler_case) || include("../examples/ivr_compiler_cases.jl")
isdefined(@__MODULE__,:_sdp_tx_case) || include("sdp_transformer_fixtures.jl")
isdefined(@__MODULE__,:_audit_nwinding_state) || include("ac_validation_fixtures.jl")
_region_build(net;mode=:conductor_regions,sb=1e4)=build_opf(net,IVRNLP(specialization=mode,s_base=sb,objective=:source_import);optimizer=Ipopt.Optimizer)
_region_solve(b)=solve_ivr_nlp_opf(b;solver_options=(print_level=0,tol=1e-10,constr_viol_tol=1e-10,bound_relax_factor=0.,acceptable_iter=0,max_iter=600))
_region_point(r)=ACPoint(voltage=r.voltage_candidate,currents=r.current_candidate)

# A phase-earth shunt at the boundary gives the retained upstream line a
# nonzero conductor-current sum. The pendant subtree has independently chosen
# coil currents; KCL and KVL determine all phasors and nominal powers.
function _region_witness(m;direction=1.)
    net=ivr_compiler_case(conductors=m,segments=3)
    tm=net["bus"]["b0"]["terminal_names"]
    D=m==2 ? [1. -1.] : m==3 ? [1. -1. 0.;0. 1. -1.;-1. 0. 1.] : [Matrix{Float64}(I,3,3) -ones(3)]
    Z=[complex(a==b ? .08+.01a : .01+.001(a+b),a==b ? .04+.002a : .008+.0001(a+b)) for a in 1:m,b in 1:m]
    js=[direction.*[(1+.2k+.11j)*cis(-.3-2pi*(j-1)/3) for j in axes(D,1)] for k in 1:3]
    il3=transpose(D)*js[3];il2=transpose(D)*js[2]+il3
    src=net["voltage_source"]["source"];vs=src["v_magnitude"].*cis.(src["v_angle"])
    Y=zeros(ComplexF64,m,m);Y[1,1]=.002
    v1=(I+Z*Y)\(vs-Z*(transpose(D)*js[1]+il2))
    il1=transpose(D)*js[1]+il2+Y*v1;v2=v1-Z*il2;v3=v2-Z*il3
    net["shunt"]=Dict("earth"=>Dict("bus"=>"b1","terminal_map"=>["a"],"G_1_1"=>.002))
    vsall=[vs,v1,v2,v3];currents=Dict{Tuple{Symbol,String},Vector{ComplexF64}}()
    for (k,il) in enumerate((il1,il2,il3))
        s=(D*vsall[k+1]).*conj.(js[k]);d=net["load"]["d$k"];d["p_nom"]=real.(s);d["q_nom"]=imag.(s)
        currents[(:load,"d$k")]=js[k];currents[(:line_from,"l$k")]=il;currents[(:line_to,"l$k")]=-il
    end
    si=copy(il1);m==3 || (si[end]=0im);currents[(:voltage_source,"source")]=si
    point=ACPoint(voltage=Dict(("b$(k-1)",t)=>x for (k,v) in enumerate(vsall) for (t,x) in zip(tm,v)),currents=currents)
    net,point
end

function _region_pair(net;sb=1e4)
    f=_region_build(net;mode=:off,sb);b=_region_build(net;sb)
    rf=_region_solve(f);r=_region_solve(b)
    if !(rf.solve.optimal && r.solve.optimal);@show sb length(first(values(net["bus"]))["terminal_names"]) rf.solve r.solve;end
    @test rf.solve.optimal && r.solve.optimal
    @test physical_residuals(net,r).passed
    @test physical_residuals(net,rf).passed
    @test ivr_nlp_point_report(f,_region_point(r)).passed
    @test ivr_nlp_point_report(b,_region_point(rf)).passed
    @test r.objective ≈ rf.objective atol=1e-4 rtol=1e-7
    report=b.numerical_diagnostics[:specialization_report]
    @test num_variables(f.model)-num_variables(b.model)==2length(report.components)
    @test b.numerical_diagnostics[:discharged_complex_kcl]==length(report.components)
    b,r,f,rf
end

@testset "Pendant subtree proof retains a nonzero-sum boundary port" begin
    for m in (2,3,4),direction in (-1.,0.,1.),sb in (1e3,1e5)
        net,p=_region_witness(m;direction);original=deepcopy(net)
        @test abs(sum(p.currents[(:line_from,"l1")]))>.1
        b=_region_build(net;sb);f=_region_build(net;mode=:off,sb)
        report=b.numerical_diagnostics[:specialization_report]
        @test report.components==["l2","l3"]
        @test JuMP.value(JuMP.start_value,b.state[b.electrical.voltage[("b3","a")]]) ≈ 230/b.electrical.vb
        @test report.retained_lines==["l1"]
        @test report.boundary_buses==["b1"]
        @test all(k->first(k)!="b1",report.omitted_kcl)
        @test num_variables(f.model)-num_variables(b.model)==4
        @test physical_residuals(net,p;delta_dispatch=:coil).passed
        for model in (b,f);@test ivr_nlp_point_report(model,p).passed;end
        q=ivr_nlp_point_report(b,p).reconstructed_point
        @test ivr_nlp_point_report(f,q).passed
        for (key,x) in p.voltage;@test q.voltage[key] ≈ x atol=1e-10;end
        for (key,x) in p.currents;@test q.currents[key] ≈ x atol=1e-10;end
        bad=deepcopy(p);bad.currents[(:line_from,"l2")][end]+=.1
        @test ivr_nlp_point_report(b,bad).max_reconstruction_residual_pu>1e-5
        b,r,f,rf=_region_pair(net;sb)
        @test net==original
    end
end

function _region_tail!(net,root,tm,prefix;segments=2)
    m=length(tm);neutral="n" in tm;n=m==2 ? 1 : m==4 ? 3 : m
    previous=root
    for k in 1:segments
        bus="$prefix$k";get!(net,"bus",Dict())[bus]=Dict("terminal_names"=>copy(tm))
        l=Dict{String,Any}("bus_from"=>previous,"bus_to"=>bus,"terminal_map_from"=>copy(tm),"terminal_map_to"=>copy(tm),"i_max"=>fill(100.,m))
        for j in 1:m;l["R_series_$(j)_$(j)"]=.15;l["X_series_$(j)_$(j)"]=.04;end
        get!(net,"line",Dict{String,Any}())[bus]=l
        get!(net,"load",Dict{String,Any}())[bus]=Dict("bus"=>bus,"terminal_map"=>copy(tm),
            "configuration"=>m==2 ? "SINGLE_PHASE" : neutral ? "WYE" : "DELTA",
            "p_nom"=>fill(50.,n),"q_nom"=>fill(10.,n),"model"=>"constant_power")
        previous=bus
    end
end

@testset "Mixed ports, mesh cores, parallel lines and multiple sources" begin
    net=ivr_compiler_case(conductors=4,segments=3)
    _region_tail!(net,"b1",["a","n"],"two")
    _region_tail!(net,"b1",["a","b","c"],"three")
    _region_tail!(net,"b1",["c","a"],"pair")
    for sb in (1e3,1e5)
        b,r,f,rf=_region_pair(net;sb);report=b.numerical_diagnostics[:specialization_report]
        @test report.retained_lines==["l1"]
        @test sort([x.rule for x in report.regions])==sort([:two_wire,:two_wire,:three_wire,:four_wire])
        @test all(x.root=="b1" for x in report.regions)
        @test _region_build(net;mode=:conductor_difference).numerical_diagnostics[:specialization]==:off
    end
    for parallel in (false,true)
        net=ivr_compiler_case(conductors=3,segments=3)
        extra=deepcopy(net["line"]["l1"])
        if parallel;extra["bus_from"]="b1";extra["bus_to"]="b2"
        else;extra["bus_to"]="b2";end
        net["line"]["loop"]=extra
        b,r,f,rf=_region_pair(net)
        @test b.numerical_diagnostics[:specialization_report].components==["l3"]
        @test b.numerical_diagnostics[:specialization_report].boundary_buses==["b2"]
    end
    net=ivr_compiler_case(conductors=4,segments=3)
    net["voltage_source"]["second"]=deepcopy(net["voltage_source"]["source"])
    net["voltage_source"]["second"]["bus"]="b1"
    b,r,f,rf=_region_pair(net)
    @test b.numerical_diagnostics[:specialization_report].components==["l2","l3"]
end

@testset "Winding and switch equations remain outside regional transformations" begin
    for kind in ("single_phase","center_tap","delta_wye","wye_delta","single_phase_autotransformer","open_delta_regulator","n_winding")
        net=kind=="n_winding" ? first(_audit_nwinding_state()) : _sdp_tx_case(kind)
        root=kind=="n_winding" ? "b2" : "t"
        # Finite winding leakage removes ideal circulating-current freedom
        # from this solve comparison; zero-leakage circuits have separate tests.
        if kind!="n_winding"
            merge!(net["transformer"][kind]["tx"],Dict("r_series_from"=>.05,"x_series_from"=>.02,"r_series_to"=>.03))
        end
        if kind=="n_winding"
            for w in net["transformer"][kind]["tx"]["windings"];w["i_max"]*=10;end
        end
        tm=kind=="center_tap" ? ["x1","n"] : copy(net["bus"][root]["terminal_names"])
        _region_tail!(net,root,tm,"tail")
        b,r,f,rf=_region_pair(net)
        report=b.numerical_diagnostics[:specialization_report]
        @test report.components==["tail1","tail2"]
        @test report.boundary_buses==[root]
        @test any(startswith(x,"transformer/") for x in report.barriers[root])
        # Bond/ideal-ground allocations may be nonunique. Both supplied-point
        # directions above validate the observations without equating choices.
    end
    for open in (false,true)
        net=ivr_compiler_case(conductors=2,segments=3)
        line=pop!(net["line"],"l1")
        net["switch"]=Dict("sw"=>Dict("bus_from"=>"b0","bus_to"=>"b1","terminal_map_from"=>["a","n"],"terminal_map_to"=>["a","n"],"open_switch"=>open))
        if open
            src=deepcopy(net["voltage_source"]["source"]);src["bus"]="b1";net["voltage_source"]["second"]=src
        end
        b,r,f,rf=_region_pair(net)
        @test b.numerical_diagnostics[:specialization_report].components==["l2","l3"]
        @test b.numerical_diagnostics[:specialization_report].boundary_buses==["b1"]
    end
end

@testset "Exact barriers, fully retained cases and deterministic plans" begin
    for (change,expected) in (
        (net->(net["bus"]["b2"]["perfectly_grounded_terminals"]=["n"]),["l3"]),
        (net->(net["shunt"]=Dict("tiny"=>Dict("bus"=>"b2","terminal_map"=>["n"],"G_1_1"=>1e-15))),["l3"]),
        (net->(net["shunt"]=Dict("zero"=>Dict("bus"=>"b2","terminal_map"=>["n"],"G_1_1"=>0.))),["l1","l2","l3"]),
        (net->(net["load"]["d2"]["terminal_map"]=["a"]),["l3"]))
        net=ivr_compiler_case(conductors=2,segments=3);change(net)
        b=_region_build(net)
        @test b.numerical_diagnostics[:specialization_report].components==expected
        @test b.numerical_diagnostics[:specialization_report]==_region_build(net).numerical_diagnostics[:specialization_report]
    end
    net=ivr_compiler_case(conductors=2,segments=3)
    # Only the affected edge and its endpoints stop peeling; no tolerance
    # turns tiny nonzero endpoint charging into a zero-sum line identity.
    code=deepcopy(net["linecode"]["wire"]);code["B_to_1_1"]=1e-15
    net["linecode"]["charged"]=code;net["line"]["l2"]["linecode"]="charged"
    @test _region_build(net).numerical_diagnostics[:specialization_report].components==["l3"]
    net=ivr_compiler_case(conductors=3,segments=2)
    extra=deepcopy(net["line"]["l1"]);extra["bus_to"]="b2";net["line"]["cycle"]=extra
    b=_region_build(net);f=_region_build(net;mode=:off)
    @test b.numerical_diagnostics[:specialization]==:off
    @test b.numerical_diagnostics[:specialization_report].code==:no_certified_regions
    @test num_variables(b.model)==num_variables(f.model)
end

# Fixed-state probes distinguish a missing limit from a solver picking another
# feasible point. The independent audit must name only the tightened bound.
function _region_bound(net,p,select,field,x,labels;sb=1e4)
    for k in eachindex(x)
        abs(x[k])<1e-5 && continue
        bad=deepcopy(net);values=copy(Float64.(x));lower=endswith(field,"_min")
        values .+= lower ? -max.(.1abs.(values),.1) : max.(.1abs.(values),.1)
        values[k]=lower ? x[k]+max(.1abs(x[k]),.1) : max(0.,x[k]-max(.1abs(x[k]),.1))
        select(bad)[field]=values
        for mode in (:off,:conductor_regions)
            r=ivr_nlp_point_report(_region_build(bad;mode,sb),p)
            @test !r.passed
            @test r.max_reconstruction_residual_pu<1e-7
        end
        a=physical_residuals(bad,p;delta_dispatch=:coil)
        @test Set(r.label for r in a.records if r.residual>getproperty(a.tolerances,r.unit))==Set(labels)
    end
end

@testset "Regional reconstruction preserves boundary and interior operating bounds" begin
    for m in (2,3,4),sb in (1e3,1e5)
        net,p=_region_witness(m)
        tm=net["bus"]["b1"]["terminal_names"];n=m==2 ? 1 : 3
        for bus in ("b1","b2")
            v=[p.voltage[(bus,t)] for t in tm];vn=m==3 ? 0im : v[end];vp=v[1:n]
            for (field,x) in (("v_max",abs.(v)),("v_min",abs.(vp)),("vpn_max",abs.(vp.-vn)),("vpn_min",abs.(vp.-vn)))
                # Avoid a stricter probe conflicting with a pre-existing opposite bound.
                copy_net=deepcopy(net)
                for key in ("v_min","v_max","vpn_min","vpn_max");delete!(copy_net["bus"][bus],key);end
                _region_bound(copy_net,p,x->x["bus"][bus],field,x,["bus/$bus/$field"];sb)
            end
            m==3 || _region_bound(net,p,x->x["bus"][bus],"vn_max",[abs(vn)],["bus/$bus/vn_max"];sb)
            if n==3
                a=cis(2pi/3);vph=vp.-vn
                for (field,x) in (("vpos_max",abs((vph[1]+a*vph[2]+a^2*vph[3])/3)),
                    ("vneg_max",abs((vph[1]+a^2*vph[2]+a*vph[3])/3)),("vzero_max",abs(sum(vph)/3)))
                    _region_bound(net,p,x->x["bus"][bus],field,[x],["bus/$bus/$field"];sb)
                end
            end
        end
        for (id,bus) in (("l1","b0"),("l2","b1"),("l3","b2"))
            i=p.currents[(:line_from,id)];v=[p.voltage[(bus,t)] for t in tm]
            _region_bound(net,p,x->x["line"][id],"i_max",abs.(i),["line/$id/from/i_max","line/$id/to/i_max"];sb)
            # Side powers differ due to losses. Tighten below both endpoints
            # and keep every other conductor entry loose at both ends.
            tbus=net["line"][id]["bus_to"];vt=[p.voltage[(tbus,t)] for t in tm]
            s=max.(abs.(v[1:n].*conj.(i[1:n])),abs.(vt[1:n].*conj.(i[1:n])))
            _region_bound(net,p,x->x["line"][id],"s_max",s,["line/$id/from/s_max","line/$id/to/s_max"];sb)
        end
    end
end

@testset "Regional branch reversal, terminal ordering and family reuse" begin
    for m in (2,3,4)
        net,p=_region_witness(m)
        l=net["line"]["l2"];l["bus_from"],l["bus_to"]=l["bus_to"],l["bus_from"]
        for b in values(net["bus"]);reverse!(b["terminal_names"]);end
        b=_region_build(net);vars=all_variables(b.model);report=b.numerical_diagnostics[:specialization_report]
        original=deepcopy(net["load"])
        for scale in (1.,.5,-.5)
            update_ivr_loads!(b,Dict(id=>(p=scale*d["p_nom"],q=scale*d["q_nom"]) for (id,d) in original))
            r=_region_solve(b);f=_region_build(b.network;mode=:off);rf=_region_solve(f)
            @test r.solve.optimal && rf.solve.optimal
            @test physical_residuals(b.network,r).passed
            @test ivr_nlp_point_report(f,_region_point(r)).passed
            @test ivr_nlp_point_report(b,_region_point(rf)).passed
            @test r.objective ≈ rf.objective atol=1e-4 rtol=1e-7
            @test all_variables(b.model)==vars
            @test b.numerical_diagnostics[:specialization_report]==report
            @test b.numerical_diagnostics[:structure_analysis_count]==1
        end
    end
end

@testset "Regional device identities include voltage laws, capacitors, generators and IBRs" begin
    for law in ("constant_current","zip","exponential")
        net,p=_region_witness(4)
        for d in values(net["load"])
            d["model"]=law;d["v_nom"]=fill(230.,3)
            if law=="zip"
                for prefix in ("alpha","beta"), (suffix,x) in zip(("z","i","p"),(.2,.3,.5));d[prefix*"_"*suffix]=fill(x,3);end
            elseif law=="exponential"
                d["gamma_p"]=fill(.4,3);d["gamma_q"]=fill(-.5,3)
            end
        end
        net["capacitor"]=Dict("c"=>Dict("bus"=>"b2","terminal_map"=>["a","b","c","n"],"configuration"=>"WYE","q_rated"=>[20.,40.,60.],"v_nom"=>fill(230.,3)))
        net["generator"]=Dict("g"=>Dict("bus"=>"b3","terminal_map"=>["a","b","c"],"configuration"=>"DELTA",
            "p_min"=>[20.,30.,40.],"p_max"=>[20.,30.,40.],"q_min"=>zeros(3),"q_max"=>zeros(3),"s_max"=>fill(100.,3),"i_max"=>fill(10.,3)))
        net["ibr"]=Dict("i"=>Dict("bus"=>"b2","terminal_map"=>["a","b","c","n"],"topology"=>"FOUR_LEG",
            "p_min"=>[10.,20.,30.],"p_max"=>[10.,20.,30.],"q_min"=>zeros(3),"q_max"=>zeros(3),"s_max"=>fill(100.,3),"i_max"=>fill(10.,4),"r_filter"=>.05))
        b,r,f,rf=_region_pair(net)
        @test b.numerical_diagnostics[:specialization_report].components==["l2","l3"]
        @test b.numerical_diagnostics[:load_voltage_variable_count]==9
        point=_region_point(r)
        for field in ("i_max","s_max")
            x=field=="i_max" ? abs.(r.current_candidate[(:generator,"g")]) : abs.(r.powers[(:generator,"g")])
            _region_bound(net,point,x->x["generator"]["g"],field,x,["generator/g/$field"])
        end
        # Even a zero-rated phase-earth capacitor stops the identity proof.
        net["capacitor"]["c"]=Dict("bus"=>"b2","terminal_map"=>["a"],"configuration"=>"SINGLE_PHASE","q_rated"=>0.,"v_nom"=>230.)
        b,r,f,rf=_region_pair(net)
        @test b.numerical_diagnostics[:specialization_report].components==["l3"]
        @test "earth_return/capacitor/c" in b.numerical_diagnostics[:specialization_report].barriers["b2"]
    end
end
