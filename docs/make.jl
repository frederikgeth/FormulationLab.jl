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
        "Architecture"=>"architecture.md",
        "Component coverage"=>"coverage.md",
        "Schema field inventory"=>"schema_fields.md",
        "SDP"=>["Current–voltage relaxation"=>"sdp.md",
                 "Static AC components"=>"sdp_static.md",
                 "Clarabel and numerical profiles"=>"sdp_numerics.md",
                 "Lifted nonlinear cuts"=>"lnc.md",
                 "Fixed transformers and regulators"=>"sdp_transformers.md"],
        "LinDist3Flow"=>["Formulation and usage"=>"lindist3flow.md",
                         "Component equations"=>"lindist3flow_components.md"],
        "API"=>"api.md",
        "Provenance"=>"migration.md",
        "Verification"=>"verification.md",
    ],
)
