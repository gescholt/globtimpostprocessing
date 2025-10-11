"""
    test_module_independence.jl

Test that GlobtimPostProcessing can load independently without plotting dependencies.

This ensures proper separation of concerns:
- GlobtimPostProcessing: Pure data analysis (no plotting)
- GlobtimPlots: Visualization (depends on GlobtimPostProcessing types)
"""

using Test
using Dates

@testset "Module Independence" begin
    @testset "GlobtimPostProcessing loads without plotting dependencies" begin
        # This test verifies that GlobtimPostProcessing can be loaded
        # without requiring any plotting packages

        # Clear any previously loaded modules to ensure clean test
        # (Note: In Julia, we can't truly unload modules, but we can test in fresh process)

        @test !isdefined(Main, :GlobtimPlots) || @warn "GlobtimPlots already loaded - test may not be accurate"

        # Load GlobtimPostProcessing
        using GlobtimPostProcessing

        # Verify core functionality is available
        @test isdefined(GlobtimPostProcessing, :ExperimentResult)
        @test isdefined(GlobtimPostProcessing, :CampaignResults)
        @test isdefined(GlobtimPostProcessing, :load_experiment_results)
        @test isdefined(GlobtimPostProcessing, :load_campaign_results)
        @test isdefined(GlobtimPostProcessing, :compute_statistics)
        @test isdefined(GlobtimPostProcessing, :analyze_campaign)
        @test isdefined(GlobtimPostProcessing, :generate_report)

        # Verify that plotting functions are NOT defined in GlobtimPostProcessing
        # (They should come from GlobtimPlots instead)
        @test !isdefined(GlobtimPostProcessing, :PlotBackend)
        @test !isdefined(GlobtimPostProcessing, :Interactive)
        @test !isdefined(GlobtimPostProcessing, :Static)
        @test !isdefined(GlobtimPostProcessing, :create_experiment_plots)
        @test !isdefined(GlobtimPostProcessing, :create_campaign_comparison_plot)
    end

    @testset "GlobtimPostProcessing has no plotting dependencies" begin
        # Check that the module doesn't depend on plotting packages
        using Pkg

        # Get dependencies from Project.toml
        project_path = joinpath(dirname(dirname(@__FILE__)), "Project.toml")
        @test isfile(project_path)

        project_toml = Pkg.TOML.parsefile(project_path)
        deps = get(project_toml, "deps", Dict())

        # Verify no plotting dependencies
        plotting_packages = ["GlobtimPlots", "CairoMakie", "GLMakie", "Makie",
                            "VegaLite", "Plots", "PlotlyJS"]

        for pkg in plotting_packages
            @test !haskey(deps, pkg)
        end

        println("✓ GlobtimPostProcessing dependencies are clean (no plotting packages)")
    end

    @testset "ExperimentResult and CampaignResults are concrete types" begin
        using GlobtimPostProcessing

        # Verify the types can be instantiated
        exp_result = ExperimentResult(
            "test_exp",
            Dict("param" => "value"),
            ["label1"],
            ["label1", "label2"],
            nothing,
            nothing,
            nothing,
            "/tmp/test"
        )

        @test exp_result isa ExperimentResult
        @test exp_result.experiment_id == "test_exp"

        campaign = CampaignResults(
            "test_campaign",
            [exp_result],
            Dict("meta" => "data"),
            now()
        )

        @test campaign isa CampaignResults
        @test length(campaign.experiments) == 1

        println("✓ Core types are properly defined and instantiable")
    end
end
