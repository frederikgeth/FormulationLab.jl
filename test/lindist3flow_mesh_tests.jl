using Test, FormulationLab, JuMP, Clarabel, LinearAlgebra
include("lindist3flow_fixtures.jl")

function _mesh_fixture(;reverse=false)
    phases=["a","b","c"];v=230 .* cis.([0.,-2pi/3,2pi/3])
    net=Dict{String,Any}("bus"=>Dict(b=>Dict("terminal_names"=>phases) for b in ("s","u","v")),
        "voltage_source"=>Dict("s"=>Dict("bus"=>"s","terminal_map"=>phases,"configuration"=>"WYE","v_magnitude"=>abs.(v),"v_angle"=>angle.(v))),
        "load"=>Dict("d"=>Dict("bus"=>"v","terminal_map"=>phases,"configuration"=>"WYE","model"=>"constant_power","p_nom"=>[1000.,1700.,600.],"q_nom"=>[400.,-200.,300.])),
        "line"=>Dict{String,Any}())
    Z=ComplexF64[.2+.3im .02+.04im .01+.03im;.02+.04im .3+.2im .03+.02im;.01+.03im .03+.02im .25+.35im]
    for (id,a,b,factor) in (("a","s","u",1.),("b","u","v",1.5),("c","s","v",2.))
        reverse && id=="c" && ((a,b)=(b,a))
        d=Dict{String,Any}("bus_from"=>a,"bus_to"=>b,"terminal_map_from"=>phases,"terminal_map_to"=>phases)
        for i in 1:3,j in 1:3;d["R_series_$(i)_$(j)"]=factor*real(Z[i,j]);d["X_series_$(i)_$(j)"]=factor*imag(Z[i,j]);end
        net["line"][id]=d
    end
    net,Z,v
end

@testset "Meshed line model and independent complex linear circuit" begin
    net,Z,vref=_mesh_fixture()
    @test !is_l3f_applicable(check_l3f_applicability(net))
    # Independent constant-current linear circuit, with source increments zero.
    Y1=inv(Z);Y2=inv(1.5Z);Y3=inv(2Z)
    iload=conj.(complex.([1000.,1700.,600.],[400.,-200.,300.])./vref)
    dv=[Y1+Y2 -Y2;-Y2 Y2+Y3] \ [zeros(ComplexF64,3);-iload]
    expected=Dict("s"=>vref,"u"=>vref+dv[1:3],"v"=>vref+dv[4:6])
    for pu in (false,true),rev in (false,true)
        n,_,_=_mesh_fixture(reverse=rev)
        opts=L3FOptions(topology=:meshed_linear,per_unit=pu)
        b=build_l3f_opf(n,Clarabel.Optimizer;options=opts)
        set_silent(b.model);optimize!(b.model)
        @test termination_status(b.model)==MOI.OPTIMAL
        @test l3f_model_class(b)==:LP
        @test length(b.topology)==3
        @test length(b.constraints[:line_angle_drop])==9
        @test any(f->f.code=="A.L3F.MESH_LINEARIZED",b.applicability.findings)
        for e in b.topology
            z=Z*(e.id=="a" ? 1 : e.id=="b" ? 1.5 : 2)
            current=z \ (expected[e.parent]-expected[e.child])
            power=vref.*conj.(current)
            for k in 1:3
                scale=pu ? opts.s_base : 1.
                @test value(b.variables[:p_line][(:line,e.id,k)])*scale ≈ real(power[k]) atol=1e-3
                @test value(b.variables[:q_line][(:line,e.id,k)])*scale ≈ imag(power[k]) atol=1e-3
            end
        end
        for (bus,delta) in (("u",dv[1:3]),("v",dv[4:6])),k in 1:3
            scale=pu ? b.bases.v_base[bus]^2 : 1.
            @test value(b.variables[:w][(bus,["a","b","c"][k])])*scale ≈ abs2(vref[k])+2real(conj(vref[k])*delta[k]) atol=1e-3
        end
    end
    # Closing a loop through a transformer requires a different angle contract.
    bad=_l3f_case();bad["transformer"]=Dict("single_phase"=>Dict("t"=>Dict("bus_from"=>"source","bus_to"=>"load","terminal_map_from"=>["a"],"terminal_map_to"=>["a"],"v_nom_from"=>230.,"v_nom_to"=>230.)))
    r=check_l3f_applicability(bad;options=L3FOptions(topology=:meshed_linear))
    @test any(f->f.code=="E.L3F.MESH_TRANSFORMER_CYCLE",r.findings)
end

@testset "Transformer normalization and unused electrical fields" begin
    n=Dict{String,Any}("terminal_conventions"=>Dict("phase"=>["a","b","c"],"neutral"=>["n"]),
        "bus"=>Dict(b=>Dict("terminal_names"=>["a","b","c","n"]) for b in ("s","v")),
        "transformer"=>Dict("delta_wye"=>Dict("t"=>Dict{String,Any}("bus_from"=>"s","bus_to"=>"v","r_series"=>3.,"x_series"=>6.))))
    for convention in (:from_terminal,:from_coil)
        x=deepcopy(n);f=FormulationLab.L3FFinding[]
        FormulationLab._l3f_normalize_inputs!(f,x,L3FOptions(transformer_impedance=convention))
        t=x["transformer"]["delta_wye"]["t"]
        @test t["terminal_map_from"]==["a","b","c"]
        @test t["terminal_map_to"]==["a","b","c","n"]
        @test t["r_series_from"] ≈ (convention==:from_coil ? 1 : 3)
        @test !haskey(t,"r_series")
        @test length(f)==3 && all(z->z.severity!=:error,f)
    end
    @test haskey(n["transformer"]["delta_wye"]["t"],"r_series")
    for (change,code) in ((x->nothing,"E.L3F.IMPEDANCE_CONVENTION_REQUIRED"),
        (x->(x["transformer"]["delta_wye"]["t"]["r_series_from"]=1.),"E.L3F.IMPEDANCE_ALIAS_CONFLICT"),
        (x->empty!(x["terminal_conventions"]),"E.L3F.TERMINAL_MAP_AMBIGUOUS"),
        (x->(x["transformer"]["delta_wye"]["t"]["x_leakage_typo"]=1.),"E.L3F.UNCONSUMED_ELECTRICAL_FIELD"))
        x=deepcopy(n);change(x);f=FormulationLab.L3FFinding[]
        options=L3FOptions(transformer_impedance=code=="E.L3F.IMPEDANCE_CONVENTION_REQUIRED" ? :unspecified : :from_terminal)
        FormulationLab._l3f_normalize_inputs!(f,x,options)
        @test any(z->z.code==code,f)
    end
    n=_l3f_case();n["linecode"]["lc"]["B_from_1_1"]=0.
    @test is_l3f_applicable(check_l3f_applicability(n))
    n["linecode"]["lc"]["B_from_1_1"]=1e-8
    @test !is_l3f_applicable(check_l3f_applicability(n))
end

@testset "Normalized delta bank matches explicit canonical input" begin
    original=_l3f_dy_case("delta_wye";line=true)
    canonical=deepcopy(original)
    tid=only(keys(canonical["transformer"]["delta_wye"]))
    canonical["transformer"]["delta_wye"][tid]["r_series_from"]=1.
    canonical["transformer"]["delta_wye"][tid]["x_series_from"]=2.
    inferred=deepcopy(original)
    inferred["terminal_conventions"]=Dict("phase"=>["a","b","c"],"neutral"=>String[])
    d=inferred["transformer"]["delta_wye"][tid]
    delete!(d,"terminal_map_from");delete!(d,"terminal_map_to")
    d["r_series"]=3.;d["x_series"]=6.
    opts=L3FOptions(unsupported=:lower,transformer_impedance=:from_coil,topology=:meshed_linear)
    a=solve_l3f_opf(canonical,Clarabel.Optimizer;options=opts,solver_options=(verbose=false,))
    b=solve_l3f_opf(inferred,Clarabel.Optimizer;options=opts,solver_options=(verbose=false,))
    @test a.solve.optimal && b.solve.optimal
    @test a.buses==b.buses
    @test b.formulation["topology"]=="meshed_linear"
    @test !haskey(inferred["transformer"]["delta_wye"][tid],"r_series_from")
end

@testset "Meshed reference contract" begin
    n=_l3f_case()
    ref=Dict(("source","a")=>230+0im,("load","a")=>229+0im)
    r=check_l3f_applicability(n;reference=ref,options=L3FOptions(topology=:meshed_linear))
    @test any(f->f.code=="E.L3F.MESH_REFERENCE_INVALID",r.findings)
end
