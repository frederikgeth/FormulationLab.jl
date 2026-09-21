using Documenter, FormulationLab

makedocs(;
    modules=[FormulationLab],
    sitename="FormulationLab.jl",
    authors="Frederik Geth",
    format=Documenter.HTML(prettyurls=get(ENV,"CI","false")=="true",
                           edit_link="main", size_threshold_warn=150*1024),
    checkdocs=:none, # The public API is growing; referenced docs and links stay strict.
    pages=[
        "Home"=>"index.md",
        "Start here"=>[
            "Choosing a formulation"=>"formulations.md",
            "Notation and conventions"=>"notation.md",
            "Architecture"=>"architecture.md",
            "Component coverage"=>"coverage.md",
            "Schema field inventory"=>"schema_fields.md",
        ],
        "Conic AC formulations"=>[
            "IVR semidefinite relaxation"=>"sdp.md",
            "Branch-flow semidefinite relaxation"=>"branch_flow_sdp.md",
            "SOC outer approximation"=>"soc.md",
            "Static AC components"=>"sdp_static.md",
            "Fixed transformers and regulators"=>"sdp_transformers.md",
            "Lifted nonlinear cuts"=>"lnc.md",
        ],
        "LinDist3Flow"=>["Formulation and usage"=>"lindist3flow.md",
                         "Component equations"=>"lindist3flow_components.md",
                         "OPF and power-flow modes"=>"lindist3flow_modes.md",
                         "Input normalization and meshed lines"=>"lindist3flow_mesh.md",
                         "PowerIO compatibility and IEEE roadmap"=>"powerio_compatibility.md"],
        "Numerics and evidence"=>[
            "SDP numerical profiles"=>"sdp_numerics.md",
            "SOC profiles and structural sparsity"=>"soc_profiles.md",
            "Network reduction and reconstruction"=>"reduction.md",
            "Formulation decisions"=>"formulation_choices.md",
            "Clarabel solve-time study and plan"=>"soc_performance_plan.md",
            "SDP solve-time study"=>"sdp_performance.md",
            "Verification"=>"verification.md",
            "AC containment audit"=>"ac_validation.md",
        ],
        "Reference"=>[
            "Literature and lineage"=>"literature.md",
            "Formulation and input API"=>"api.md",
            "Migration provenance"=>"migration.md",
        ],
    ],
)
