using Test
using OpenDSSDirect
@testset "FormulationLab" begin
    include("boundary_tests.jl")
    include("sdp_tests.jl")
    include("soc_tests.jl")
    include("ac_validation_tests.jl")
    include("sdp_transformer_opendss_tests.jl")
    include("sdp_nwinding_opendss_tests.jl")
    include("lindist3flow_tests.jl")
    include("lindist3flow_contract_tests.jl")
    include("lindist3flow_lowering_tests.jl")
    include("lindist3flow_delta_transformer_tests.jl")
    include("lindist3flow_controls_tests.jl")
    include("lindist3flow_permissive_tests.jl")
    include("lindist3flow_center_tap_tests.jl")
    include("lindist3flow_literature_tests.jl")
    include("lindist3flow_ieee13_tests.jl")
end
