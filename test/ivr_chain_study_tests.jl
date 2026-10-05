using Test, FormulationLab
include("../examples/benchmark_ivr_chains.jl")
@testset "Declared chain experiment and flat-start equivalence" begin
    C=IVRChainStudy
    @test length(C.profiles())==6
    for m in (2,3),n in (4,12),loads in (:terminal,:alternating)
        net=C.chain_case(conductors=m,segments=n,loads=loads)
        @test sum(d["length"] for d in values(net["line"])) ≈ 1.
        @test sum(sum(d["p_nom"]) for d in values(net["load"])) ≈ (m==2 ? 2000. : 3000.)
        @test all(haskey(d,"s_max") for d in values(net["line"]))
        @test C.start_check(net).max_physical_start_difference_pu<=1e-12
        models=[build_opf(net,IVRNLP(p.options)) for p in C.profiles()]
        for (a,b) in ((2,3),(5,6))
            ra=models[a].numerical_diagnostics[:linear_elimination_report]
            rb=models[b].numerical_diagnostics[:linear_elimination_report]
            @test length(rb.series_buses)==(loads==:terminal ? n-1 : n÷2)
            if loads==:alternating
                @test models[a].coordinates.projection==models[b].coordinates.projection
                @test models[a].coordinates.reconstruction==models[b].coordinates.reconstruction
            else
                @test length(rb.series_buses)>length(ra.series_buses)
            end
        end
    end
    @test_throws ArgumentError C.chain_case(conductors=4)
    @test_throws ArgumentError C.chain_case(segments=3)
    @test_throws ArgumentError C.chain_case(loads=:unknown)
    @test_throws ArgumentError C.benchmark("unused.json";repetitions=6)
end
