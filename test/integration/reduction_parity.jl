import BMOPFTools
using FormulationLab, Test
include("../network_reduction_tests.jl")
function clean_reduction(n)
    n=deepcopy(n);pop!(n,"_simplification_log",nothing)
    for l in values(get(n,"line",Dict()));pop!(l,"_merged_from",nothing);end
    n
end
@testset "BMOPFTools topology compatibility" begin
    for pi in (false,true),drop in (false,true),policy in (:off,:exact,:allow_approximate)
        n=reduction_case(;pi)
        n["bus"]["middle"]["v_min"]=[210.]
        p=prepare_network(n;reduction=ReductionOptions(allow_drop_bus_constraints=drop,series_merge_policy=policy),warn=false)
        ref=BMOPFTools.simplify_network(n;allow_drop_bus_constraints=drop,series_merge_policy=policy)
        @test p.network==clean_reduction(ref)
    end
    n=_l3f_case();n["bus"]["junction"]=deepcopy(n["bus"]["source"])
    n["line"]["line"]["bus_from"]="junction"
    n["switch"]=Dict("s"=>Dict("bus_from"=>"source","bus_to"=>"junction","terminal_map_from"=>["a"],"terminal_map_to"=>["a"],"open_switch"=>false,"i_max"=>[100.]))
    @test prepare_network(n;warn=false).network==clean_reduction(BMOPFTools.simplify_network(n))
end
