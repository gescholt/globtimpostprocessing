push!(LOAD_PATH, "../src/")
using Documenter, GlobtimPostProcessing

makedocs(
    sitename = "GlobtimPostProcessing.jl Documentation",
    modules = [GlobtimPostProcessing],
    repo = "github.com/gescholt/GlobtimPostProcessing.jl",
    format = Documenter.HTML(
        repolink = "https://github.com/gescholt/GlobtimPostProcessing.jl",
        canonical = "https://gescholt.github.io/GlobtimPostProcessing.jl/stable/",
        edit_link = "main",
        assets = String[],
        analytics="G-22HWCKE0JK"
    ),
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting_started.md",
        "Guides" => [
            "Critical Point Refinement" => "refinement.md",
            "Quality Diagnostics" => "quality_diagnostics.md",
            "Parameter Recovery" => "parameter_recovery.md",
            "Landscape Fidelity" => "landscape_fidelity.md",
            "Campaign Analysis" => "campaign_analysis.md"
        ],
        "Examples" => "workflow_examples.md",
        "API Reference" => "api_reference.md"
    ],
    checkdocs = :none
)

deploydocs(repo = "github.com/gescholt/GlobtimPostProcessing.jl.git")
