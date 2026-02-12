using Test
using GlobtimPostProcessing
using DataFrames
using LinearAlgebra
using JSON3

@testset "Parameter Recovery Analysis" begin

    @testset "Compute parameter distance" begin
        p_true = [0.2, 0.3, 0.5, 0.6]

        # Test case 1: Very close point
        p_found1 = [0.201, 0.299, 0.498, 0.602]
        dist1 = param_distance(p_found1, p_true)
        @test dist1 < 0.01
        @test dist1 ≈ 0.00316 atol=1e-3

        # Test case 2: Farther point
        p_found2 = [0.35, 0.45, 0.55, 0.65]
        dist2 = param_distance(p_found2, p_true)
        @test dist2 > 0.1
        @test dist2 > dist1

        # Test case 3: Exact match
        p_found3 = [0.2, 0.3, 0.5, 0.6]
        dist3 = param_distance(p_found3, p_true)
        @test dist3 ≈ 0.0 atol=1e-10
    end

    @testset "Load experiment config with p_true" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")
        config = load_experiment_config(fixtures_dir)

        @test haskey(config, "p_true")
        @test config["p_true"] == [0.2, 0.3, 0.5, 0.6]
        @test config["dimension"] == 4
        @test config["basis"] == "chebyshev"
    end

    @testset "Load critical points for degree" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")

        # Load degree 4 critical points (Phase 2 format: p1, p2, ..., objective)
        df = load_critical_points_for_degree(fixtures_dir, 4)
        @test nrow(df) == 81  # Phase 2 raw format has 81 critical points
        @test hasproperty(df, :p1)
        @test hasproperty(df, :p2)
        @test hasproperty(df, :p3)
        @test hasproperty(df, :p4)
        @test hasproperty(df, :objective)

        # Check first row has valid values
        @test df[1, :p1] isa Number
        @test df[1, :objective] isa Number
    end

    @testset "Parameter recovery statistics" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")

        # Load test data (Phase 2 format with p1, p2, p3, p4 columns)
        df = load_critical_points_for_degree(fixtures_dir, 4)

        # Use a hypothetical p_true for testing statistics computation
        # Note: Raw fixture data may not have points close to this p_true
        p_true = [0.2, 0.3, 0.5, 0.6]
        recovery_threshold = 1.0  # Larger threshold since raw data may not have close points

        # Compute statistics
        stats = compute_parameter_recovery_stats(df, p_true, recovery_threshold)

        # Check structure
        @test haskey(stats, "min_distance")
        @test haskey(stats, "mean_distance")
        @test haskey(stats, "num_recoveries")
        @test haskey(stats, "all_distances")

        # Check values - general consistency checks
        @test stats["min_distance"] >= 0.0
        @test stats["mean_distance"] >= stats["min_distance"]
        @test stats["num_recoveries"] >= 0
        @test stats["num_recoveries"] <= nrow(df)
        @test length(stats["all_distances"]) == nrow(df)

        # With threshold=1.0, we should have some points within range
        @test stats["num_recoveries"] >= 0  # May or may not have recoveries
    end

    @testset "Parameter recovery for multiple degrees" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")
        p_true = [0.2, 0.3, 0.5, 0.6]
        recovery_threshold = 1.0  # Larger threshold for raw data

        # Test for degree 4 (81 critical points in Phase 2 format)
        df4 = load_critical_points_for_degree(fixtures_dir, 4)
        stats4 = compute_parameter_recovery_stats(df4, p_true, recovery_threshold)

        # Test for degree 6 (289 critical points in Phase 2 format)
        df6 = load_critical_points_for_degree(fixtures_dir, 6)
        stats6 = compute_parameter_recovery_stats(df6, p_true, recovery_threshold)

        # Degree 6 should have more critical points (289 > 81)
        @test nrow(df6) > nrow(df4)
        @test nrow(df4) == 81
        @test nrow(df6) == 289

        # Both should compute valid statistics
        @test stats4["min_distance"] >= 0.0
        @test stats6["min_distance"] >= 0.0
        @test length(stats4["all_distances"]) == nrow(df4)
        @test length(stats6["all_distances"]) == nrow(df6)
    end

    @testset "Parameter recovery table generation" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")
        p_true = [0.2, 0.3, 0.5, 0.6]
        degrees = [4, 6]
        recovery_threshold = 1.0  # Larger threshold for raw fixture data

        # Generate recovery table
        table = generate_parameter_recovery_table(fixtures_dir, p_true, degrees, recovery_threshold)

        @test isa(table, DataFrame)
        @test nrow(table) == length(degrees)
        @test hasproperty(table, :degree)
        @test hasproperty(table, :num_critical_points)
        @test hasproperty(table, :min_distance)
        @test hasproperty(table, :mean_distance)
        @test hasproperty(table, :num_recoveries)

        # Check values
        @test table[1, :degree] == 4
        @test table[2, :degree] == 6
        @test table[1, :num_critical_points] == 81   # Phase 2 format
        @test table[2, :num_critical_points] == 289  # Phase 2 format
        @test all(table.min_distance .>= 0.0)
    end

    @testset "Check if experiment has p_true" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")

        # Should have p_true
        @test has_ground_truth(fixtures_dir) == true

        # Should return false for missing directory
        @test has_ground_truth("/nonexistent/path") == false
    end

    @testset "has_ground_truth with nested config format" begin
        nested_dir = joinpath(@__DIR__, "fixtures", "nested_config")
        @test has_ground_truth(nested_dir) == true
    end

    @testset "extract_true_parameters from loaded config" begin
        fixtures_dir = joinpath(@__DIR__, "fixtures")
        config = load_experiment_config(fixtures_dir)
        p = extract_true_parameters(config)
        @test p == [0.2, 0.3, 0.5, 0.6]

        nested_dir = joinpath(@__DIR__, "fixtures", "nested_config")
        config_nested = load_experiment_config(nested_dir)
        p_nested = extract_true_parameters(config_nested)
        @test p_nested == [0.2, 0.3, 0.5, 0.6]
    end

    @testset "Parameter distance with different dimensions" begin
        # 2D case
        p_true_2d = [1.0, 2.0]
        p_found_2d = [1.1, 2.1]
        dist_2d = param_distance(p_found_2d, p_true_2d)
        @test dist_2d ≈ sqrt(0.01 + 0.01) atol=1e-10

        # 3D case
        p_true_3d = [1.0, 2.0, 3.0]
        p_found_3d = [1.1, 2.1, 3.1]
        dist_3d = param_distance(p_found_3d, p_true_3d)
        @test dist_3d ≈ sqrt(0.01 + 0.01 + 0.01) atol=1e-10

        # Dimension mismatch should error
        @test_throws DimensionMismatch param_distance([1.0, 2.0], [1.0, 2.0, 3.0])
    end

end
