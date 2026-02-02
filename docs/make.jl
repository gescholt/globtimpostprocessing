push!(LOAD_PATH, "../src/")
using Documenter, GlobtimPostProcessing

makedocs(
    sitename = "GlobtimPostProcessing.jl Documentation",
    modules = [GlobtimPostProcessing],
    repo = "git.mpi-cbg.de/globaloptim/globtimpostprocessing",
    format = Documenter.HTML(
        repolink = "https://git.mpi-cbg.de/globaloptim/globtimpostprocessing",
        edit_link = "master",
        assets = String[],
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

# deploydocs not used - GitLab repo
# deploydocs(repo = "git.mpi-cbg.de/globaloptim/globtimpostprocessing.git")
