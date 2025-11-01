"""
Test suite for interactive analysis entry point functionality

Tests campaign discovery, experiment listing, and analysis features
using TDD approach.
"""

using Test
using GlobtimPostProcessing
using JSON3
using DataFrames
using Dates

# Include the module to test (without running main)
include("../analyze_experiments.jl")

@testset "Interactive Analysis Tests" begin

    @testset "Campaign Discovery" begin
        # Create temporary test structure
        test_root = mktempdir()

        try
            # Setup: Create mock campaign structure
            campaign1_path = mkpath(joinpath(test_root, "study1", "configs_20251001", "hpc_results"))
            campaign2_path = mkpath(joinpath(test_root, "study2", "configs_20251002", "hpc_results"))

            # Create mock experiment directories
            exp1_path = mkpath(joinpath(campaign1_path, "exp_1_test"))
            exp2_path = mkpath(joinpath(campaign1_path, "exp_2_test"))
            exp3_path = mkpath(joinpath(campaign2_path, "exp_1_other"))

            # Create minimal results files in proper format
            for exp_path in [exp1_path, exp2_path, exp3_path]
                results = Dict(
                    "experiment_id" => basename(exp_path),
                    "success" => true,
                    "results_summary" => Dict(
                        "2" => Dict(
                            "critical_points" => 5,
                            "best_objective" => 1.234,
                            "computation_time" => 10.5
                        )
                    )
                )
                open(joinpath(exp_path, "results_summary.json"), "w") do io
                    JSON3.write(io, results)
                end

                config = Dict(
                    "experiment_name" => basename(exp_path),
                    "timestamp" => "2025-10-01T10:00:00"
                )
                open(joinpath(exp_path, "experiment_config.json"), "w") do io
                    JSON3.write(io, config)
                end
            end

            # Test: discover_campaigns should find both campaigns
            campaigns = discover_campaigns(test_root)

            @test length(campaigns) == 2
            @test campaign1_path in campaigns
            @test campaign2_path in campaigns
            @test all(isdir, campaigns)

            # Test: campaigns should be sorted
            @test issorted(campaigns)

        finally
            rm(test_root, recursive=true, force=true)
        end
    end

    @testset "Campaign Discovery - Empty Directory" begin
        test_root = mktempdir()

        try
            # Test: empty directory should return empty list
            campaigns = discover_campaigns(test_root)
            @test isempty(campaigns)

        finally
            rm(test_root, recursive=true, force=true)
        end
    end

    @testset "Campaign Discovery - No Experiments" begin
        test_root = mktempdir()

        try
            # Setup: Create hpc_results but no experiments
            campaign_path = mkpath(joinpath(test_root, "study", "configs", "hpc_results"))

            # Test: should not include empty hpc_results
            campaigns = discover_campaigns(test_root)
            @test isempty(campaigns)

        finally
            rm(test_root, recursive=true, force=true)
        end
    end

    @testset "Experiment Listing" begin
        test_root = mktempdir()

        try
            # Setup: Create campaign with experiments
            campaign_path = mkpath(joinpath(test_root, "study", "hpc_results"))

            exp_names = ["exp_a", "exp_b", "exp_c"]
            for name in exp_names
                exp_path = mkpath(joinpath(campaign_path, name))

                results = Dict(
                    "experiment_id" => name,
                    "success" => true,
                    "results_summary" => Dict(
                        "2" => Dict(
                            "critical_points" => 10,
                            "best_objective" => 2.5
                        )
                    )
                )
                open(joinpath(exp_path, "results_summary.json"), "w") do io
                    JSON3.write(io, results)
                end

                config = Dict("experiment_name" => name)
                open(joinpath(exp_path, "experiment_config.json"), "w") do io
                    JSON3.write(io, config)
                end
            end

            # Test: display_experiment_list should return all experiments
            experiments = display_experiment_list(campaign_path)

            @test length(experiments) == 3
            @test all(isdir, experiments)
            @test all(name -> any(endswith(exp, name) for exp in experiments), exp_names)

            # Test: experiments should be sorted
            @test issorted(basename.(experiments))

        finally
            rm(test_root, recursive=true, force=true)
        end
    end

    @testset "Single Experiment Analysis - Valid Data" begin
        test_root = mktempdir()

        try
            # Setup: Create valid experiment
            exp_path = mkpath(joinpath(test_root, "test_exp"))

            results = Dict(
                "experiment_id" => "test_exp",
                "success" => true,
                "results_summary" => Dict(
                    "2" => Dict(
                        "critical_points" => 5,
                        "best_objective" => 1.234
                    )
                )
            )
            open(joinpath(exp_path, "results_summary.json"), "w") do io
                JSON3.write(io, results)
            end

            config = Dict(
                "experiment_name" => "test_exp",
                "timestamp" => "2025-10-01T10:00:00"
            )
            open(joinpath(exp_path, "experiment_config.json"), "w") do io
                JSON3.write(io, config)
            end

            # Test: Should load and analyze without error
            result = load_experiment_results(exp_path)
            @test result.experiment_id == "test_exp"
            @test "critical_point_count" in result.enabled_tracking

            stats = compute_statistics(result)
            @test !isempty(stats)

        finally
            rm(test_root, recursive=true, force=true)
        end
    end

    @testset "Campaign Analysis - Multiple Experiments" begin
        test_root = mktempdir()

        try
            # Setup: Create campaign with multiple experiments
            campaign_path = mkpath(joinpath(test_root, "hpc_results"))

            for i in 1:3
                exp_path = mkpath(joinpath(campaign_path, "exp_$i"))

                results = Dict(
                    "experiment_id" => "exp_$i",
                    "success" => true,
                    "results_summary" => Dict(
                        "2" => Dict(
                            "critical_points" => i * 10,
                            "best_objective" => Float64(i)
                        )
                    ),
                    "experiment_type" => "lotka_volterra",
                    "num_varying" => 2
                )
                open(joinpath(exp_path, "results_summary.json"), "w") do io
                    JSON3.write(io, results)
                end

                config = Dict("experiment_name" => "exp_$i")
                open(joinpath(exp_path, "experiment_config.json"), "w") do io
                    JSON3.write(io, config)
                end
            end

            # Test: Should load campaign and analyze all experiments
            campaign = load_campaign_results(campaign_path)
            @test length(campaign.experiments) == 3

            campaign_stats = GlobtimPostProcessing.analyze_campaign(campaign)
            @test haskey(campaign_stats, "campaign_summary")
            @test haskey(campaign_stats, "aggregated_metrics")
            @test campaign_stats["campaign_summary"]["num_experiments"] == 3

        finally
            rm(test_root, recursive=true, force=true)
        end
    end

    @testset "Error Handling - Missing Files" begin
        test_root = mktempdir()

        try
            # Setup: Create experiment without results file
            exp_path = mkpath(joinpath(test_root, "incomplete_exp"))

            config = Dict("experiment_name" => "incomplete")
            open(joinpath(exp_path, "experiment_config.json"), "w") do io
                JSON3.write(io, config)
            end

            # Test: Should throw error for missing results
            @test_throws Exception load_experiment_results(exp_path)

        finally
            rm(test_root, recursive=true, force=true)
        end
    end

    @testset "Error Handling - Invalid JSON" begin
        test_root = mktempdir()

        try
            # Setup: Create experiment with malformed JSON
            exp_path = mkpath(joinpath(test_root, "bad_exp"))

            open(joinpath(exp_path, "results_summary.json"), "w") do io
                write(io, "{invalid json")
            end

            # Test: Should throw error for invalid JSON
            @test_throws Exception load_experiment_results(exp_path)

        finally
            rm(test_root, recursive=true, force=true)
        end
    end

    @testset "Path Validation" begin
        # Test: Non-existent path should error
        @test_throws Exception discover_campaigns("/nonexistent/path/$(rand(Int))")
    end

end

println("\n✓ All interactive analysis tests defined")
println("Run with: julia test/test_interactive_analysis.jl")
