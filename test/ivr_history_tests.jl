using Test, FormulationLab, JuMP, JSON3
include("../examples/benchmark_ivr_histories.jl")
@testset "Distinct operation histories and reactive-box dual transfer" begin
    H=IVRHistoryStudy;R=H.R
    for n in (3,6,8)
        orders=R.workflow_orders(n,2n)
        @test all(count(o->o[k]==j,orders)==2 for j in 1:n for k in 1:n)
        @test all(sort(o)==collect(1:n) for o in orders)
    end
    @test !all(count(o->o[k]==j,R.workflow_orders(6,6))==1 for j in 1:6 for k in 1:6)
    @test_throws ArgumentError R.workflow_orders(0,6)
    @test_throws ArgumentError R.workflow_orders(6,0)
    @test_throws ArgumentError H.history_case(conductors=4)
    @test_throws ArgumentError H.history_case(segments=3)
    @test_throws ArgumentError H.history_case(history=:unknown)
    for m in (2,3)
        fixed,fs=H.history_case(conductors=m,segments=2)
        net,steps=H.history_case(conductors=m,segments=2,history=:changing_boxes)
        @test fixed==net && length(steps)==6
        @test all(a.loads==b.loads && a.generators["der"].cost==b.generators["der"].cost for (a,b) in zip(fs,steps))
        original=deepcopy(net);inputs=R.scenario_inputs(net,steps)
        @test net==original
        @test all(inputs[k]!=inputs[k-1] for k in 2:6)
        @test all(x["line"]==net["line"] && x["voltage_source"]==net["voltage_source"] for x in inputs)
        @test inputs[3]["generator"]["der"]["q_min"]==inputs[3]["generator"]["der"]["q_max"]==zeros(m==2 ? 1 : 3)
        @test !haskey(inputs[5]["generator"]["der"],"q_min")
        @test inputs[6]["generator"]["der"]["q_min"]==net["generator"]["der"]["q_min"]
        for history in (:fixed_boxes,:changing_boxes)
            hnet,hsteps=H.history_case(conductors=m,segments=2,history=history)
            states=R.scenario_inputs(hnet,hsteps)
            mktempdir() do dir
                file=joinpath(dir,"history.json")
                result=H.benchmark(file;conductors=m,segments=2,history,repetitions=1)
                @test result["ranking"]["objective_comparable"]
                @test length(result["ranking"]["eligible"])==6
                @test JSON3.read(read(file*".manifest.json",String)).history_source_sha256==H.SOURCE_SHA
                @test !JSON3.read(read(file*".manifest.json",String)).position_balanced
                @test JSON3.read(read(file,String)).history_input.history==string(history)
                for profile in result["profiles"],trial in [profile["warmup"];profile["trials"]]
                    @test trial["accepted"]
                    for (k,s) in enumerate(trial["scenarios"])
                        @test s["physical_passed"] && s["own_passed"] && s["full_passed"] && s["fresh_same_formulation_passed"]
                        dispatch=s["generator_dispatch"]["der"];g=states[k]["generator"]["der"]
                        @test all(isfinite,vcat(dispatch["p_W"],dispatch["q_var"]))
                        for (key,lo,hi) in (("p_W","p_min","p_max"),("q_var","q_min","q_max"))
                            @test !haskey(g,lo) || all(dispatch[key].>=g[lo].-1e-4)
                            @test !haskey(g,hi) || all(dispatch[key].<=g[hi].+1e-4)
                        end
                        if profile["start"]!=:previous_primal && k>1
                            d=s["dual_start"];n=m==2 ? 1 : 3
                            reset=history==:fixed_boxes ? 0 : (k==5 ? 3n : 4n)
                            @test d.reset_bounds==reset && d.matches_policy
                            @test d.added==(history==:changing_boxes && k==6 ? n : 0)
                            @test d.removed==(history==:changing_boxes && k==5 ? n : 0)
                            @test d.source_sha256==trial["scenarios"][k-1]["dual_solution_sha256"]
                        end
                    end
                end
            end
        end
    end
end
