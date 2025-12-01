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
        @test haskey(config, "function_name")
        @test haskey(config, "dimension")
        @test haskey(config, "basis")

        # Check values (Deuflhard_4d fixture)
        @test config["function_name"] == "Deuflhard_4d"
        @test config["dimension"] == 4
        @test config["basis"] == "chebyshev"

        # Fixture includes p_true for parameter recovery testing
        @test haskey(config, "p_true")
        @test config["p_true"] == [0.2, 0.3, 0.5, 0.6]
    end

    @testset "Load experiment config - missing file" begin
        @test_throws ErrorException load_experiment_config("/nonexistent/path")
    end

    @testset "Load critical points for specific degree" begin
        # Test degree 4
        df4 = load_critical_points_for_degree(fixtures_dir, 4)

        @test df4 isa DataFrame
        @test nrow(df4) == 81  # Deuflhard_4d degree 4 has 81 points
        @test hasproperty(df4, :index)
        @test hasproperty(df4, :p1)
        @test hasproperty(df4, :p2)
        @test hasproperty(df4, :p3)
        @test hasproperty(df4, :p4)
        @test hasproperty(df4, :objective)

        # Check data types
        @test eltype(df4.p1) <: Real
        @test eltype(df4.objective) <: Real

        # Check that indices are sequential
        @test df4[1, :index] == 1
        @test df4[end, :index] == nrow(df4)

        # Test degree 6
        df6 = load_critical_points_for_degree(fixtures_dir, 6)

        @test df6 isa DataFrame
        @test nrow(df6) > nrow(df4)  # Should have more critical points
        @test hasproperty(df6, :p1)
        @test hasproperty(df6, :objective)
        @test nrow(df6) == 289  # Deuflhard_4d degree 6 has 289 points
    end

    @testset "Load critical points - missing file" begin
        @test_throws ErrorException load_critical_points_for_degree(fixtures_dir, 999)
    end

    @testset "Check for ground truth (p_true)" begin
        # Fixture has p_true for parameter recovery testing
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
        # This simulates analyzing function minimization (not parameter recovery)
        config = load_experiment_config(fixtures_dir)
        function_name = config["function_name"]
        degrees = [4, 6]

        minimization_data = []
        for degree in degrees
            df = load_critical_points_for_degree(fixtures_dir, degree)

            # Find minimum objective value
            min_obj = minimum(df.objective)
            min_idx = argmin(df.objective)
            min_point = [df[min_idx, Symbol("p$i")] for i in 1:4]

            push!(minimization_data, (
                degree = degree,
                num_points = nrow(df),
                min_objective = min_obj,
                min_point = min_point
            ))
        end

        @test length(minimization_data) == 2
        @test minimization_data[1].degree == 4
        @test minimization_data[2].degree == 6
        @test minimization_data[1].num_points < minimization_data[2].num_points

        # Higher degree polynomial typically finds more critical points
        # (The actual minimum value depends on the specific problem and may not always improve)
        # Just verify both have valid objective values
        @test minimization_data[1].min_objective > 0
        @test minimization_data[2].min_objective > 0
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
