# Controlled derived-input probes; original-input results remain separate.
include("benchmark_nlp_soc_worker.jl")
manifest=JSON3.read(read(joinpath(@__DIR__,"results","nlp_soc_panel_manifest.json"),String),Vector{Dict{String,Any}})
for (name,mode,output) in (("ieee13/ieee13_pmd.dss","repair_ieee13","ieee13_impedance_repair"),
    ("cigre/CIGRE_test_case.dss","no_nameplate_caps","cigre_no_nameplate_caps"),
    ("ieee34/ieee34_pmd.dss","no_nameplate_caps","ieee34_no_nameplate_caps"))
    c=only(filter(c->c["name"]==name,manifest))
    println("DIAGNOSTIC ",name," ",mode);flush(stdout)
    worker(c["path"],joinpath(@__DIR__,"results",output*"_2026-09-11.json"),mode)
end
