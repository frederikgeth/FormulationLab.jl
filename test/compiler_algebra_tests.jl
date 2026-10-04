using Test, FormulationLab, LinearAlgebra

@testset "Conductor-difference algebra without a network eligibility claim" begin
    for (rule,m) in ((:two_wire,2),(:three_wire,3),(:four_wire,4))
        map=FormulationLab._conductor_difference(rule);P=map.voltage
        Z=ComplexF64[(a==b ? .2+.1im : .01*(a+b)+.005im*(a-b)) for a in 1:m,b in 1:m]
        v=ComplexF64[20k+im*(k^2-2) for k in 1:m]
        j=ComplexF64[3k-im*k^2 for k in 1:m-1]
        i=transpose(P)*j
        line=FormulationLab._difference_line(map,Z)
        @test rank(P)==m-1
        @test P*ones(m)==zeros(m-1)
        @test FormulationLab._difference_current(map,i) ≈ j atol=1e-13
        @test FormulationLab._difference_voltage(map,P*v,sum(v)) ≈ v atol=1e-13
        @test sum(v.*conj.(i)) ≈ sum((P*v).*conj.(j)) atol=1e-12
        @test dot(i,Z*i) ≈ dot(j,line.impedance*j) atol=1e-12
        vt=v-Z*i
        ut=P*v-line.impedance*j
        sigma=sum(v)-sum(line.common_drop.*j)
        @test FormulationLab._difference_voltage(map,ut,sigma) ≈ vt atol=1e-12
        # A scalar earth-return term cancels in differential impedance.
        @test FormulationLab._difference_line(map,Z.+(.3+.2im)).impedance ≈ line.impedance atol=1e-14
        @test_throws ArgumentError FormulationLab._difference_current(map,i.+.01)
        @test_throws ArgumentError FormulationLab._difference_current(map,fill(NaN,m))
        @test_throws DimensionMismatch FormulationLab._difference_line(map,zeros(m+1,m+1))
        # Equal row sums can hide a nonzero common current from voltage drop,
        # but do not justify discarding it from current or loss constraints.
        sym=FormulationLab._difference_line(map,Matrix{Float64}(I,m,m))
        @test iszero(norm(sym.differential_coupling))
        @test_throws ArgumentError FormulationLab._difference_current(map,ones(m))
    end
    map=FormulationLab._conductor_difference(:two_wire)
    Z=[.2+.1im .02+.01im;.02+.01im .1+.05im]
    @test only(FormulationLab._difference_line(map,Z).impedance) ≈ .26+.13im
    # A delta's leg-current circulation is invisible at its terminals.
    D=[1. -1. 0.;0. 1. -1.;-1. 0. 1.]
    legs=ComplexF64[1+2im,3-im,-2+4im]
    @test transpose(D)*legs ≈ transpose(D)*(legs.+5im)
    map=FormulationLab._conductor_difference(:three_wire)
    @test FormulationLab._difference_current(map,transpose(D)*legs) ≈ [legs[1]-legs[3],legs[2]-legs[3]]
    @test_throws ArgumentError FormulationLab._conductor_difference(:unknown)
end
