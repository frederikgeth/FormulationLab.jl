using Test, FormulationLab, JuMP, LinearAlgebra
isdefined(@__MODULE__,:_l3f_case) || include("lindist3flow_fixtures.jl")

function _passivity_network(Z,Yf,Yt)
    n=size(Z,1);tm=["p$k" for k in 1:n]
    code=Dict{String,Any}()
    for (M,r,x) in ((Z,"R_series_","X_series_"),(Yf,"G_from_","B_from_"),(Yt,"G_to_","B_to_"))
        for i in 1:n,j in 1:n
            code["$r$(i)_$j"]=real(M[i,j]);code["$x$(i)_$j"]=imag(M[i,j])
        end
    end
    Dict{String,Any}("bus"=>Dict(b=>Dict("terminal_names"=>copy(tm)) for b in ("s","t")),
        "terminal_conventions"=>Dict("phase"=>tm,"neutral"=>String[]),
        "voltage_source"=>Dict("s"=>Dict("bus"=>"s","terminal_map"=>tm,
            "v_magnitude"=>fill(230.,n),"v_angle"=>zeros(n))),
        "linecode"=>Dict("c"=>code),
        "line"=>Dict("l"=>Dict("bus_from"=>"s","bus_to"=>"t",
            "terminal_map_from"=>tm,"terminal_map_to"=>tm,"linecode"=>"c","length"=>0.7)))
end

@testset "Line passivity at zero and nonzero dissipative boundaries" begin
    for n in 1:4
        zero_matrix=zeros(ComplexF64,n,n)
        identity_matrix=Matrix{ComplexF64}(I,n,n)
        negative=copy(zero_matrix);negative[end,end]=-1e-14
        cases=[(zero_matrix,true),(fill(complex(-0.0,-0.0),n,n),true),
            (identity_matrix,true),(1e-14identity_matrix,true),
            (im*identity_matrix,true),(negative,false)]
        if n>=2
            singular=copy(identity_matrix);singular[end,end]=0
            indefinite=copy(identity_matrix);indefinite[1,2]=indefinite[2,1]=2
            # Nonreciprocal imaginary coupling has Hermitian eigenvalues ±1.
            asymmetric=copy(zero_matrix);asymmetric[1,2]=2im
            push!(cases,(singular,true),(indefinite,false),(asymmetric,false))
        end
        for (M,expected) in cases, channel in 1:3, sb in (1e3,1e5)
            matrices=[copy(zero_matrix) for _ in 1:3];matrices[channel]=M
            net=_passivity_network(matrices...);original=deepcopy(net)
            e=FormulationLab._ivr_electrical_data(net;s_base=sb,line_records=true)
            record=only(d for d in e.devices if d[1]==:line_from)
            @test record[5]["passive"]==expected
            @test net==original
            # Compare the previous numerical policy on the actual scaled
            # matrices, not a physical-linecode classification before scaling.
            line=only(e.lnc_lines)
            reference=all(A->minimum(eigvals(Hermitian((A+A')/2));init=0.)>=0,
                (line.Z/e.zb,line.Yf*e.zb,line.Yt*e.zb))
            @test record[5]["passive"]==reference
        end
    end
end

@testset "SOC retains the line-loss inequality only for passive lines" begin
    for conductance in (0.,1e-5,-1e-14), physical in (false,true)
        net=_l3f_case();net["linecode"]["lc"]["G_from_1_1"]=conductance
        b=build_opf(net,IVRSOC(physical_projections=physical);optimizer=nothing)
        powers=b.electrical.powers
        loss=sum(real,powers[(:line_from,"line")])+sum(real,powers[(:line_to,"line")])
        # Other PSD consequences cannot substitute for this precise constraint.
        found=any(all_constraints(b.model,AffExpr,MOI.GreaterThan{Float64})) do ref
            c=constraint_object(ref)
            c.set.lower==0. && JuMP.isequal_canonical(c.func,loss)
        end
        @test found==(physical && conductance>=0)
    end
end
