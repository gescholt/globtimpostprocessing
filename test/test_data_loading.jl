"""
test_data_loading.jl

Unit tests for unified data loading functions (Issue #7, Phase 1).

Tests all loader functions from src/ParameterRecovery.jl and relevant
parts of src/ResultsLoader.jl.
"""

using Test
using GlobtimPostProcessing
using DataFrames
using JSON3
using CSV

@testset "Data Loading (Issue #7, Phase 1)" begin
    fixtures_dir = joinpath(@__DIR__, "fixtures")

    @testset "Load experiment config" begin
        config = load_experiment_config(fixtures_dir)

        @test config isa Dict
        @test haskey(config, "p_true")
        @test haskey(config, "dimension")
        @test haskey(config, "basis")
        @test haskey(config, "experiment_id")

        # Check values
        @test config["p_true"] == [0.2, 0.3, 0.5, 0.6]
        @test config["dimension"] == 4
        @test config["basis"] == "chebyshev"
        @test config["experiment_id"] == "test_exp_1"
    end

    @testset "Load experiment config - missing file" begin
        @test_throws ErrorException load_experiment_config("/nonexistent/path")
    end

    @testset "Load critical points for specific degree" begin
        # Test degree 4
        df4 = load_critical_points_for_degree(fixtures_dir, 4)

        @test df4 isa DataFrame
        @test nrow(df4) == 3
        @test hasproperty(df4, :x1)
        @test hasproperty(df4, :x2)
        @test hasproperty(df4, :x3)
        @test hasproperty(df4, :x4)
        @test hasproperty(df4, :z)

        # Check data types
        @test eltype(df4.x1) <: Real
        @test eltype(df4.z) <: Real

        # Check values
        @test df4[1, :x1] ≈ 0.201
        @test df4[1, :z] ≈ 1250.5

        # Test degree 6
        df6 = load_critical_points_for_degree(fixtures_dir, 6)

        @test df6 isa DataFrame
        @test nrow(df6) > nrow(df4)  # Should have more critical points
        @test hasproperty(df6, :x1)
        @test hasproperty(df6, :z)
    end

    @testset "Load critical points - missing file" begin
        @test_throws ErrorException load_critical_points_for_degree(fixtures_dir, 999)
    end

    @testset "Check for ground truth (p_true)" begin
        # Should find p_true
        @test has_ground_truth(fixtures_dir) == true

        # Should not find p_true in nonexistent directory
        @test has_ground_truth("/nonexistent/path") == false
    end

    @testset "Load all critical points for multiple degrees" begin
        degrees = [4, 6]
        all_data = Dict{Int, DataFrame}()

        for degree in degrees
            df = load_critical_points_for_degree(fixtures_dir, degree)
            all_data[degree] = df
        end

        @test length(all_data) == 2
        @test haskey(all_data, 4)
        @test haskey(all_data, 6)
        @test nrow(all_data[6]) > nrow(all_data[4])
    end

    @testset "Integration: Load config and critical points together" begin
        # This simulates what analyze_experiments.jl would do
        config = load_experiment_config(fixtures_dir)
        p_true = config["p_true"]
        degrees = [4, 6]

        recovery_data = []
        for degree in degrees
            df = load_critical_points_for_degree(fixtures_dir, degree)
            stats = compute_parameter_recovery_stats(df, p_true, 0.01)

            push!(recovery_data, (
                degree = degree,
                num_points = nrow(df),
                min_dist = stats["min_distance"],
                recoveries = stats["num_recoveries"]
            ))
        end

        @test length(recovery_data) == 2
        @test recovery_data[1].degree == 4
        @test recovery_data[2].degree == 6
        @test recovery_data[1].num_points < recovery_data[2].num_points
    end

    @testset "Load experiment results from directory" begin
        # Test loading from fixtures directory
        exp_result = load_experiment_results(fixtures_dir)

        @test exp_result isa ExperimentResult
        @test !isnothing(exp_result.experiment_id)
        @test exp_result.source_path == fixtures_dir
        @test !isnothing(exp_result.critical_points)

        # Check critical points were loaded
        cp_df = exp_result.critical_points
        @test cp_df isa DataFrame
        @test nrow(cp_df) > 0
        @test hasproperty(cp_df, :degree)  # Should have degree column added
    end

    @testset "Load campaign results (single experiment)" begin
        # When given a single experiment directory, should load as 1-experiment campaign
        campaign = load_campaign_results(fixtures_dir)

        @test campaign isa CampaignResults
        @test length(campaign.experiments) >= 1
        @test campaign.experiments[1] isa ExperimentResult
    end
end
