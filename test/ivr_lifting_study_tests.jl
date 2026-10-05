using Test, FormulationLab, JuMP
isdefined(@__MODULE__,:IVRLiftingBlockStudy) || include("../examples/benchmark_ivr_lifting_blocks.jl")
@testset "Matched physical starts for exact structural profiles" begin
    L=IVRLiftingBlockStudy
    for m in (2,3),charged in (false,true),tight in (false,true)
        net=L.case(conductors=m,segments=4,charged=charged,tight=tight)
        @test sum(d["length"] for d in values(net["line"])) ≈ 1.
        point=L.start_point(net)
        for p in L.profiles(;charged)
            b=build_opf(net,IVRNLP(p.options));encoded=ivr_nlp_point_report(b,point)
            @test isempty(encoded.missing_channels)
            @test encoded.max_binding_residual_pu<=1e-10
            @test encoded.max_reconstruction_residual_pu<=1e-10
            @test length(encoded.variable_values)==num_variables(b.model)
            for ref in b.model.ext[:ivr_lifting].records
                value=JuMP.value(v->encoded.variable_values[v],ref.expression)
                @test complex(encoded.variable_values[ref.real],encoded.variable_values[ref.imag]) ≈ value
            end
        end
    end
    @test_throws ArgumentError L.benchmark("unused.json";repetitions=6)
    net=L.case(segments=4,charged=true,tight=true);point=L.start_point(net)
    reference=build_opf(net,IVRNLP(objective=:source_import))
    for profile in L.profiles(;charged=true)
        row,p=L.P.trial(net,profile,reference,nothing;initial_point=point)
        @test row["accepted"]
        @test row["shared_start"].encoded_variables==row["variables"]
        @test minimum(abs.(row["generator_s_max_slack_VA"]["g"]))<1e-3
    end
    for charged in (false,true)
        net=L.case(segments=4,charged=charged,interior=true);point=L.start_point(net)
        reference=build_opf(net,IVRNLP(objective=:source_import))
        for profile in L.profiles(;charged)
            row,p=L.P.trial(net,profile,reference,nothing;initial_point=point)
            @test row["accepted"]
            @test abs(only(row["vpn_max_slack_V"]["b2"]))<1e-5
            # Independent resistive closed form for the uncharged witness:
            # middle drop=0.25 I=1 V, source import=230*4=920 W.
            charged || @test row["objective"] ≈ 920. atol=1e-4
        end
    end
    net=L.case(segments=8,charged=true,transformers=true,tight=true);point=L.start_point(net)
    @test length(net["transformer"]["single_phase"])==2
    reference=build_opf(net,IVRNLP(objective=:source_import))
    for profile in L.profiles(;charged=true)
        row,p=L.P.trial(net,profile,reference,nothing;initial_point=point)
        @test row["accepted"]
    end
end
