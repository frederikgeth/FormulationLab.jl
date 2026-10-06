module IVRImpliedCertificateTests
using Test, FormulationLab, JuMP, LinearAlgebra
include("../examples/ivr_implied_residual_certificate.jl")
include("../examples/benchmark_ivr_nwinding_coordinates.jl")
const I=IVRImpliedResidualCertificate
const B=IVRNWindingCoordinateStudy
const N=B.N

function toy(;passive=false)
    m=Model();@variable(m,xr[1:2]);@variable(m,xi[1:2])
    R=[Dict(1=>1.0+0im),Dict(2=>1.0+0im),Dict(1=>1/3+0im)]
    e=(;vb=230.,ib=10.,equations=[Dict(1=>-1.0+0im,3=>3.0+0im)],
        equation_metadata=[(;index=1,label="voltage/substitution",unit=:V,assembly_multiplier=1.)],
        kcl=Dict(("b","a")=>Dict(1=>1.0+0im),("b","b")=>Dict(2=>1.0+0im),
            ("b","c")=>Dict(1=>-1.0+0im,2=>-1.0+0im)),lnc_lines=[],impedance_loads=[])
    (;electrical=e,coordinates=(;reconstruction=R,real_variables=xr,imaginary_variables=xi),
        numerical_diagnostics=Dict(:composed_row_normalization=>true,:kcl_row_max_base=>2.,
            :linear_elimination_report=>(;selected_series_lines=Dict(),impedance_loads=[],series_buses=passive ? ["b"] : String[]),
            :device_elimination_report=>(;equation_indices=[1]),
            :specialization_report=>(;omitted_kcl=[("b","c")])))
end

@testset "Exact inherited bounds and stored substitution defects" begin
    b=toy();certs=I.certificates(b);y=ComplexF64[2+3im,-4+5im]
    @test length(certs)==2
    voltage,kcl=certs
    # 3*Float64(1/3)-1 is nonzero in exact stored-coefficient arithmetic,
    # although ordinary Float64 multiplication rounds it to zero.
    @test 3*(1/3)-1==0
    @test voltage.defect==Dict(1=>complex(-big(1)//big(2)^54,0))
    @test isempty(voltage.dependencies) && isempty(kcl.defect)
    @test [d.label for d in kcl.dependencies]==["kcl/b/a","kcl/b/b"]
    @test all(d->d.coefficient==-I.Q(.2),kcl.dependencies)
    for c in certs
        r=I.evaluate(c,y)
        @test r.exact_identity_verified && r.exact_enclosure_verified
        @test r.conditional_components_bound_SI===nothing
        @test r.conditional_modulus_bound_SI===nothing
        @test r.retained_targets_satisfied===nothing
    end
    r=I.evaluate(kcl,y;retained_scalar_target=1e-10)
    @test r.physical_components_SI==(real=20.,imag=80.)
    @test r.observed_components_bound_SI==(real=60.,imag=80.)
    @test r.defect_components_bound_SI==(real=0.,imag=0.)
    @test r.conditional_components_bound_SI.real≈4e-10
    @test r.conditional_components_bound_SI.imag≈4e-10
    @test r.conditional_modulus_bound_SI≈8e-10
    # A conditional target is not an assertion that this deliberately bad
    # state meets it. Distinct observed and conditional fields prevent that.
    @test r.physical_components_SI.real>r.conditional_components_bound_SI.real
    @test !r.retained_targets_satisfied
    @test I.evaluate(kcl,y;retained_scalar_target=30.).retained_targets_satisfied
    targets=Dict("kcl/b/a"=>1e-10,"kcl/b/b"=>2e-10)
    @test I.evaluate(kcl,y;retained_scalar_target=targets).conditional_components_bound_SI.real≈6e-10
    vr=I.evaluate(voltage,y)
    @test I.Q(vr.defect_components_bound_SI.real)>=230*2//big(2)^54
    @test I.Q(vr.defect_components_bound_SI.imag)>=230*3//big(2)^54
    @test !vr.exact_zero_defect
    @test I.evaluate(voltage,y;retained_scalar_target=0.).retained_targets_satisfied
    # Complex coefficients require cross terms in the componentwise bound.
    complex_cert=merge(voltage,(;row=I.Row(1=>I.CQ(1//2,1//3)),defect=I.Row(1=>I.CQ(1//2,1//3))))
    complex_report=I.evaluate(complex_cert,y)
    @test complex_report.exact_identity_verified && complex_report.exact_enclosure_verified
    @test complex_report.observed_components_bound_SI.real==460.
    @test complex_report.observed_components_bound_SI.imag>=230*13/6
    # If same-bus rows were also removed by passive elimination, they are
    # never treated as retained constraints; their entire effect stays delta.
    passive=only(c for c in I.certificates(toy(;passive=true)) if c.reason==:specialization)
    @test isempty(passive.dependencies) && !isempty(passive.defect)
    @test I.evaluate(passive,y).defect_components_bound_SI==(real=60.,imag=80.)
    for target in (-1.,Inf,NaN,true,"tol",Dict("kcl/b/a"=>1e-10))
        @test_throws ArgumentError I.evaluate(kcl,y;retained_scalar_target=target)
    end
    @test_throws ArgumentError I.evaluate(kcl,[1im])
    @test_throws ArgumentError I.evaluate(kcl,[Inf+0im,0im])
    @test I._upper(big(1)//big(2)^2000)==nextfloat(0.)
    @test I._upper(big(2)^2000//1)==Inf
    @test I._upper(big(1)//10)>=.1
    @test I._upper(big(0)//1)==0.
end

@testset "Certificates cross reconstruction and scaling options" begin
    net,_=N.network(2)
    reasons=Set{Symbol}();methods=Set{Symbol}()
    for representation in [p.name for p in N.profiles(net,:tracking,1e5)],p in B.profiles(net,:tracking,representation)
        b=build_opf(net,IVRNLP(p.options));certs=I.certificates(b)
        @test length(certs)==count(q->!q.retained_constraint,I.C.catalog(b).rows)
        # Deliberately infeasible native values exercise inherited residuals,
        # not only cancellation at a converged or all-zero state.
        y=[complex(mod(k,7)/7,mod(k,11)/11) for k in eachindex(b.coordinates.real_variables)]
        before=precision(BigFloat)
        for c in certs
            r=I.evaluate(c,y;retained_scalar_target=1e-10)
            push!(reasons,c.reason);push!(methods,c.method)
            @test r.exact_identity_verified && r.exact_enclosure_verified
            @test r.physical_components_SI.real<=r.observed_components_bound_SI.real
            @test r.physical_components_SI.imag<=r.observed_components_bound_SI.imag
            @test all(d->startswith(d.label,"kcl/"),r.dependencies)
            # Independent BigFloat nested evaluation, avoiding the composed
            # row used by the exact evaluator.
            nested=setprecision(BigFloat,256) do
                yb=I.C.K._big.(y)
                z=[I.C.K._bigdot(row,yb) for row in b.coordinates.reconstruction]
                I.C.K._bigdot(I._original(b.electrical,c),z)*BigFloat(c.physical_scale)
            end
            @test abs(real(nested))<=BigFloat(r.observed_components_bound_SI.real)+big"1e-60"
            @test abs(imag(nested))<=BigFloat(r.observed_components_bound_SI.imag)+big"1e-60"
        end
        @test precision(BigFloat)==before
    end
    @test (:specialization in reasons) && (:passive_elimination in reasons) && (:device_elimination in reasons)
    @test methods==Set([:same_bus_kcl,:reconstruction])
end
end
