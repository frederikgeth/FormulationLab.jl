using Test, FormulationLab, JuMP, LinearAlgebra

@testset "Sparse IVR expression emission preserves coefficients and ownership" begin
    model=Model();@variable(model,x[1:3])
    # Independent dense coefficient/constant representation, including shared
    # variables, complex coefficients and repeated coordinate expressions.
    A=ComplexF64[1+2im -3 0; .5 1-im 4im; 0 0 0; 1+2im -3 0]
    d=ComplexF64[2-im,-1+3im,4,2-im]
    z=[sum(A[k,j]*x[j] for j in axes(A,2))+d[k] for k in axes(A,1)]
    z[4]=z[1] # Intentional input alias: accumulating a result must not change it.
    original=copy.(z)
    rows=[Dict{Int,ComplexF64}(),Dict(1=>1.0+0im),Dict(3=>2im),
          Dict(1=>1.0+0im,4=>-1.0+0im),Dict(1=>2im,2=>-.5+im,3=>3+0im,4=>1-im)]
    for coordinates in (z,view(z,:)),row in rows
        out=FormulationLab._linivr_eval(row,coordinates)
        weights=ComplexF64[get(row,k,0im) for k in axes(A,1)]
        coefficients=transpose(A)*weights;constant=sum(weights.*d)
        @test JuMP.constant(out)==constant
        for j in eachindex(x);@test JuMP.coefficient(out,x[j])==coefficients[j];end
        for values in ([0.,0.,0.],[1.,-2.,3.],[.125,8.,-.25])
            @test JuMP.value(v->values[JuMP.index(v).value],out) ≈ sum(coefficients.*values)+constant atol=1e-12
        end
        again=FormulationLab._linivr_eval(row,coordinates)
        JuMP.add_to_expression!(out,7.0-2im,x[1])
        @test JuMP.coefficient(again,x[1])==coefficients[1]
        for k in eachindex(z)
            @test JuMP.isequal_canonical(z[k],original[k])
        end
    end
    @test iszero(FormulationLab._linivr_eval(rows[4],z))
    @test iszero(FormulationLab._linivr_eval(rows[1],z[1:0]))
    # The numerical evaluator used by reference states and physical-point
    # reconstruction must retain its original complex scalar semantics.
    for values in (ComplexF64[1+im,2-im,3,4],Float64[1,2,3,4]),row in rows
        expected=sum(get(row,k,0im)*values[k] for k in eachindex(values))
        @test FormulationLab._linivr_eval(row,values) ≈ expected
    end
end
