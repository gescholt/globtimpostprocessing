"""
    test_critical_point_classification.jl

Tests for critical point classification based on Hessian eigenvalues.
"""

using Test
using DataFrames
using GlobtimPostProcessing

@testset "Critical Point Classification" begin

    @testset "classify_critical_point - Basic Classifications" begin
        # Test minimum (all positive eigenvalues)
        @test classify_critical_point([2.5, 1.3, 0.8]) == "minimum"
        @test classify_critical_point([1.0, 2.0]) == "minimum"
        @test classify_critical_point([5.0]) == "minimum"

        # Test maximum (all negative eigenvalues)
        @test classify_critical_point([-2.5, -1.3, -0.8]) == "maximum"
        @test classify_critical_point([-1.0, -2.0]) == "maximum"
        @test classify_critical_point([-5.0]) == "maximum"

        # Test saddle (mixed signs)
        @test classify_critical_point([2.5, -1.3, 0.8]) == "saddle"
        @test classify_critical_point([1.0, -2.0]) == "saddle"
        @test classify_critical_point([-1.0, 2.0, 3.0]) == "saddle"
        @test classify_critical_point([5.0, -0.1]) == "saddle"

        # Test degenerate (contains near-zero eigenvalues)
        @test classify_critical_point([1.0, 0.0, 2.0]) == "degenerate"
        @test classify_critical_point([0.0, 0.0]) == "degenerate"
        @test classify_critical_point([1.0, 1e-8, 2.0]) == "degenerate"
        @test classify_critical_point([1e-10]) == "degenerate"
    end

    @testset "classify_critical_point - Tolerance Testing" begin
        # Default tolerance is 1e-6

        # Just above tolerance - should classify normally
        @test classify_critical_point([1e-5, 2e-5]) == "minimum"
        @test classify_critical_point([-1e-5, -2e-5]) == "maximum"

        # Just below tolerance - should be degenerate
        @test classify_critical_point([1e-7, 1e-6]) == "degenerate"

        # Custom tolerance
        @test classify_critical_point([1e-3], tol=1e-2) == "degenerate"
        @test classify_critical_point([1e-3], tol=1e-4) == "minimum"
    end

    @testset "extract_eigenvalues_from_row" begin
        # Create test DataFrame
        df = DataFrame(
            x1 = [0.1, 0.2],
            x2 = [0.3, 0.4],
            hessian_eigenvalue_1 = [2.5, -1.0],
            hessian_eigenvalue_2 = [1.3, -2.0],
            hessian_eigenvalue_3 = [0.8, -0.5]
        )

        # Test extraction from first row
        row1 = df[1, :]
        eigenvalues1 = GlobtimPostProcessing.extract_eigenvalues_from_row(row1)
        @test eigenvalues1 == [2.5, 1.3, 0.8]

        # Test extraction from second row
        row2 = df[2, :]
        eigenvalues2 = GlobtimPostProcessing.extract_eigenvalues_from_row(row2)
        @test eigenvalues2 == [-1.0, -2.0, -0.5]

        # Test DataFrame without eigenvalue columns
        df_no_eigenvalues = DataFrame(x1 = [0.1], x2 = [0.3])
        row_no_eigenvalues = df_no_eigenvalues[1, :]
        @test GlobtimPostProcessing.extract_eigenvalues_from_row(row_no_eigenvalues) === nothing
    end

    @testset "classify_all_critical_points! - Basic Functionality" begin
        # Create test DataFrame with critical points
        df = DataFrame(
            x1 = [0.1, 0.2, 0.3, 0.4, 0.5],
            x2 = [0.3, 0.4, 0.5, 0.6, 0.7],
            hessian_eigenvalue_1 = [2.5, -1.0, 1.5, 0.0, 2.0],
            hessian_eigenvalue_2 = [1.3, -2.0, -0.8, 1.0, -1.0]
        )

        # Classify
        classify_all_critical_points!(df)

        # Check that classification column was added
        @test :point_classification in propertynames(df)

        # Check individual classifications
        @test df[1, :point_classification] == "minimum"   # [2.5, 1.3]
        @test df[2, :point_classification] == "maximum"   # [-1.0, -2.0]
        @test df[3, :point_classification] == "saddle"    # [1.5, -0.8]
        @test df[4, :point_classification] == "degenerate"  # [0.0, 1.0]
        @test df[5, :point_classification] == "saddle"    # [2.0, -1.0]
    end

    @testset "classify_all_critical_points! - Empty DataFrame" begin
        df_empty = DataFrame(
            x1 = Float64[],
            hessian_eigenvalue_1 = Float64[]
        )

        classify_all_critical_points!(df_empty)

        @test :point_classification in propertynames(df_empty)
        @test nrow(df_empty) == 0
    end

    @testset "classify_all_critical_points! - No Eigenvalue Columns" begin
        df_no_eigenvalues = DataFrame(
            x1 = [0.1, 0.2],
            x2 = [0.3, 0.4]
        )

        # Should throw an error
        @test_throws ErrorException classify_all_critical_points!(df_no_eigenvalues)
    end

    @testset "classify_all_critical_points! - Custom Column Name" begin
        df = DataFrame(
            x1 = [0.1],
            hessian_eigenvalue_1 = [2.5],
            hessian_eigenvalue_2 = [1.3]
        )

        classify_all_critical_points!(df, classification_col=:my_classification)

        @test :my_classification in propertynames(df)
        @test df[1, :my_classification] == "minimum"
    end

    @testset "count_classifications" begin
        df = DataFrame(
            x1 = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6],
            hessian_eigenvalue_1 = [2.5, -1.0, 1.5, 0.0, 2.0, 3.0],
            hessian_eigenvalue_2 = [1.3, -2.0, -0.8, 1.0, -1.0, 1.5]
        )

        classify_all_critical_points!(df)
        counts = count_classifications(df)

        # Expected: 2 minima, 1 maximum, 2 saddles, 1 degenerate
        @test counts["minimum"] == 2
        @test counts["maximum"] == 1
        @test counts["saddle"] == 2
        @test counts["degenerate"] == 1
    end

    @testset "count_classifications - No Classification Column" begin
        df = DataFrame(x1 = [0.1, 0.2])

        @test_throws ErrorException count_classifications(df)
    end

    @testset "find_distinct_local_minima - Basic Functionality" begin
        # Create test DataFrame with some nearby minima
        df = DataFrame(
            x1 = [0.1, 0.1001, 0.5, 0.2],
            x2 = [0.3, 0.3001, 0.6, -0.3],
            hessian_eigenvalue_1 = [2.5, 2.6, 3.0, -1.0],
            hessian_eigenvalue_2 = [1.3, 1.4, 1.5, -2.0]
        )

        classify_all_critical_points!(df)

        # Find distinct minima (points 1, 2, and 3 are minima; 1 and 2 are very close)
        distinct_indices = find_distinct_local_minima(df, distance_threshold=1e-2)

        # Should return 2 distinct minima (one from cluster of 1&2, plus point 3)
        @test length(distinct_indices) == 2

        # Check that we got indices of minima only
        for idx in distinct_indices
            @test df[idx, :point_classification] == "minimum"
        end
    end

    @testset "find_distinct_local_minima - No Minima" begin
        df = DataFrame(
            x1 = [0.1, 0.2],
            hessian_eigenvalue_1 = [-1.0, 1.0],
            hessian_eigenvalue_2 = [-2.0, -1.0]
        )

        classify_all_critical_points!(df)
        distinct_indices = find_distinct_local_minima(df)

        @test isempty(distinct_indices)
    end

    @testset "find_distinct_local_minima - No Parameter Columns" begin
        df = DataFrame(
            hessian_eigenvalue_1 = [2.5, 2.6],
            hessian_eigenvalue_2 = [1.3, 1.4]
        )

        classify_all_critical_points!(df)

        # Should warn and return all minima without clustering
        distinct_indices = @test_logs (:warn, r"No parameter columns") find_distinct_local_minima(df)

        @test length(distinct_indices) == 2
    end

    @testset "get_classification_summary" begin
        df = DataFrame(
            x1 = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
            x2 = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
            hessian_eigenvalue_1 = [2.5, 2.6, -1.0, 1.5, 0.0, 2.0, 3.0, -2.0, 1.0, 2.5],
            hessian_eigenvalue_2 = [1.3, 1.4, -2.0, -0.8, 1.0, -1.0, 1.5, -1.5, 1.2, 1.6]
        )

        classify_all_critical_points!(df)
        summary = get_classification_summary(df)

        # Check structure
        @test haskey(summary, "total")
        @test haskey(summary, "counts")
        @test haskey(summary, "percentages")
        @test haskey(summary, "distinct_local_minima")

        # Check totals
        @test summary["total"] == 10

        # Check that all counts sum to total
        total_counted = sum(values(summary["counts"]))
        @test total_counted == 10

        # Check percentages sum to 100
        total_percentage = sum(values(summary["percentages"]))
        @test total_percentage ≈ 100.0 atol=0.1
    end

    @testset "get_classification_summary - Empty DataFrame" begin
        df_empty = DataFrame(
            x1 = Float64[],
            hessian_eigenvalue_1 = Float64[]
        )

        classify_all_critical_points!(df_empty)
        summary = get_classification_summary(df_empty)

        @test summary["total"] == 0
        @test isempty(summary["counts"])
        @test summary["distinct_local_minima"] == 0
    end

    @testset "Integration with StatisticsCompute" begin
        # Create a mock ExperimentResult with critical points
        df = DataFrame(
            x1 = [0.1, 0.2, 0.3, 0.4],
            x2 = [0.3, 0.4, 0.5, 0.6],
            z = [100.0, 200.0, 150.0, 300.0],
            hessian_eigenvalue_1 = [2.5, -1.0, 1.5, 2.0],
            hessian_eigenvalue_2 = [1.3, -2.0, -0.8, 1.8]
        )

        exp_result = ExperimentResult(
            "test_classification",
            Dict{String, Any}(),
            ["hessian_eigenvalues"],
            ["hessian_eigenvalues"],
            df,
            nothing,
            nothing,
            "/tmp/test"
        )

        # Compute Hessian statistics
        stats = GlobtimPostProcessing.compute_hessian_statistics(exp_result)

        # Check that classifications are present
        @test stats["available"] == true
        @test haskey(stats, "classifications")
        @test haskey(stats, "classification_percentages")
        @test haskey(stats, "distinct_local_minima")

        # Check classification counts
        @test stats["classifications"]["minimum"] == 2  # Points 1 and 4
        @test stats["classifications"]["maximum"] == 1  # Point 2
        @test stats["classifications"]["saddle"] == 1   # Point 3

        # Check distinct local minima
        @test stats["distinct_local_minima"] >= 1
    end

    @testset "Real-world Dimension Test - 4D Critical Point" begin
        # Test with a realistic 4D critical point
        df = DataFrame(
            x1 = [0.201],
            x2 = [0.299],
            x3 = [0.498],
            x4 = [0.602],
            z = [1250.5],
            hessian_eigenvalue_1 = [3.2],
            hessian_eigenvalue_2 = [2.1],
            hessian_eigenvalue_3 = [1.5],
            hessian_eigenvalue_4 = [0.8]
        )

        classify_all_critical_points!(df)

        @test df[1, :point_classification] == "minimum"
    end

    @testset "Edge Cases - High Dimensional" begin
        # Test with many eigenvalues (10D)
        eigenvalues_10d_min = fill(1.0, 10)
        @test classify_critical_point(eigenvalues_10d_min) == "minimum"

        eigenvalues_10d_max = fill(-1.0, 10)
        @test classify_critical_point(eigenvalues_10d_max) == "maximum"

        eigenvalues_10d_saddle = vcat([1.0, 1.0, 1.0], fill(-1.0, 7))
        @test classify_critical_point(eigenvalues_10d_saddle) == "saddle"
    end

end
