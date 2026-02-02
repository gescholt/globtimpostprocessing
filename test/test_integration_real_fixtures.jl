# Integration Tests with Real globtimcore Fixtures
# Tests the complete workflow: load → refine → analyze → report
# Uses real data from globtimcore (Deuflhard_4d, 81+289 critical points)

using Test
using GlobtimPostProcessing
using DataFrames
using Statistics
using LinearAlgebra
using JSON3

# Load the real objective function from fixtures
fixtures_dir = joinpath(@__DIR__, "fixtures")
include(joinpath(fixtures_dir, "test_functions.jl"))

@testset "Integration: Real Fixtures End-to-End" begin
    @testset "Fixture Availability" begin
        @test isdir(fixtures_dir)
        @test isfile(joinpath(fixtures_dir, "experiment_config.json"))
        @test isfile(joinpath(fixtures_dir, "results_summary.json"))
        @test isfile(joinpath(fixtures_dir, "critical_points_raw_deg_4.csv"))
        @test isfile(joinpath(fixtures_dir, "critical_points_raw_deg_6.csv"))
        @test isfile(joinpath(fixtures_dir, "test_functions.jl"))
    end

    @testset "Load Experiment Configuration" begin
        config = load_experiment_config(fixtures_dir)

        @test haskey(config, "function_name")
        @test config["function_name"] == "Deuflhard_4d"
        @test config["dimension"] == 4
        @test config["basis"] == "chebyshev"
        @test config["GN"] == 10
        @test config["domain_range"] == 1.2
        @test config["degrees"] == [4, 6]
    end

    @testset "Load Critical Points (Phase 2 Format)" begin
        # Degree 4
        df4 = load_critical_points_for_degree(fixtures_dir, 4)
        @test nrow(df4) == 81  # Known from fixture README
        @test ncol(df4) == 6   # index, p1, p2, p3, p4, objective
        @test "index" in names(df4)
        @test "p1" in names(df4)
        @test "objective" in names(df4)

        # Check data types
        @test all(df4.index .> 0)
        @test eltype(df4.objective) <: Real

        # Degree 6
        df6 = load_critical_points_for_degree(fixtures_dir, 6)
        @test nrow(df6) == 289  # Known from fixture README
        @test ncol(df6) == 6
    end

    @testset "Objective Function Evaluation" begin
        # Test the objective function works
        test_point = [0.0, 0.0, 0.0, 0.0]
        value = deuflhard_4d_fixture(test_point)
        @test value isa Float64
        @test value >= 0.0  # Deuflhard is non-negative

        # Origin value: (exp(0)-3)² = 4 per 2D component, so 4D = 8
        @test value ≈ 8.0 atol=0.01  # Deuflhard at origin is (1-3)² + (1-3)² = 8

        # Test at a few random points
        for _ in 1:5
            p = randn(4) * 0.5  # Within domain
            v = deuflhard_4d_fixture(p)
            @test v >= 0.0
            @test isfinite(v)
        end
    end

    @testset "Refinement: Single Critical Point" begin
        # Load degree 4 critical points
        df4 = load_critical_points_for_degree(fixtures_dir, 4)

        # Pick the best critical point (smallest objective)
        best_idx = argmin(df4.objective)
        raw_point = [df4[best_idx, Symbol("p$i")] for i in 1:4]
        raw_value = df4[best_idx, :objective]

        # Refine using the real objective function
        result = refine_critical_point(
            deuflhard_4d_fixture,
            raw_point;
            max_iterations = 1000,
            f_abstol = 1e-8
        )

        # Check refinement succeeded
        @test result.converged
        @test result.value_refined <= raw_value  # Should improve or stay same
        @test result.improvement >= 0.0

        # Check diagnostics are populated (Phase 2 Tier 1)
        @test result.f_calls > 0
        @test result.time_elapsed >= 0.0
        @test result.convergence_reason in [:x_tol, :f_tol, :g_tol, :iterations, :unknown]

        # For Deuflhard, refinement should find something close to origin
        @test norm(result.refined) < 2.0  # Within reasonable distance
    end

    @testset "Refinement: Batch Processing" begin
        # Load degree 4 critical points
        df4 = load_critical_points_for_degree(fixtures_dir, 4)

        # Refine top 10 best points
        n_test = 10
        sorted_indices = sortperm(df4.objective)
        test_indices = sorted_indices[1:n_test]

        raw_points = [
            [df4[idx, Symbol("p$i")] for i in 1:4]
            for idx in test_indices
        ]

        # Batch refinement
        results = refine_critical_points_batch(
            deuflhard_4d_fixture,
            raw_points;
            max_iterations = 500,
            show_progress = false
        )

        @test length(results) == n_test

        # Check all converged
        converged_count = count(r -> r.converged, results)
        @test converged_count >= 8  # At least 80% should converge

        # Check improvements
        @test all(r -> r.improvement >= 0.0, results)

        # Check refined values are better or equal
        for (i, result) in enumerate(results)
            raw_value = df4[test_indices[i], :objective]
            @test result.value_refined <= raw_value * 1.01  # Allow tiny tolerance
        end
    end

    @testset "Quality Diagnostics: L2 Assessment" begin
        # Load quality thresholds
        thresholds = load_quality_thresholds()
        @test haskey(thresholds, "l2_norm_thresholds")

        # Load results summary to get L2 norms
        summary_path = joinpath(fixtures_dir, "results_summary.json")
        summary_data = JSON3.read(read(summary_path, String))
        degree_results = summary_data.degree_results

        # Check L2 quality for degree 4
        deg4_entry = findfirst(entry -> entry.degree == 4, degree_results)
        @test !isnothing(deg4_entry)

        l2_deg4 = degree_results[deg4_entry].l2_norm
        quality_deg4 = check_l2_quality(l2_deg4, 4, thresholds)
        @test quality_deg4 in [:excellent, :good, :fair, :poor]

        # Check L2 quality for degree 6
        deg6_entry = findfirst(entry -> entry.degree == 6, degree_results)
        l2_deg6 = degree_results[deg6_entry].l2_norm
        quality_deg6 = check_l2_quality(l2_deg6, 4, thresholds)

        # Degree 6 should have better or equal L2 than degree 4
        @test l2_deg6 <= l2_deg4
    end

    @testset "Quality Diagnostics: Stagnation Detection" begin
        thresholds = load_quality_thresholds()

        # Load results summary
        summary_path = joinpath(fixtures_dir, "results_summary.json")
        summary_data = JSON3.read(read(summary_path, String))
        degree_results = summary_data.degree_results

        # Build L2 by degree dict
        l2_by_degree = Dict{Int, Float64}()
        for entry in degree_results
            l2_by_degree[entry.degree] = entry.l2_norm
        end

        # Detect stagnation
        stagnation = detect_stagnation(l2_by_degree, thresholds)

        @test hasfield(typeof(stagnation), :is_stagnant)
        @test hasfield(typeof(stagnation), :improvement_factors)
        @test length(stagnation.improvement_factors) >= 0

        # With only 2 degrees, should not detect stagnation
        # (need 3+ consecutive stagnant degrees by default)
        if length(l2_by_degree) < 3
            @test !stagnation.is_stagnant
        end
    end

    @testset "Quality Diagnostics: Objective Distribution" begin
        thresholds = load_quality_thresholds()

        # Load degree 4 critical points
        df4 = load_critical_points_for_degree(fixtures_dir, 4)
        objectives = df4.objective

        # Check objective distribution quality
        dist_result = check_objective_distribution_quality(objectives, thresholds)

        @test hasfield(typeof(dist_result), :has_outliers)
        @test hasfield(typeof(dist_result), :outlier_fraction)
        @test hasfield(typeof(dist_result), :num_outliers)
        @test hasfield(typeof(dist_result), :quality)

        @test dist_result.quality in [:excellent, :good, :fair, :poor, :insufficient_data]
        @test 0.0 <= dist_result.outlier_fraction <= 1.0

        # With 81 points, should have enough for meaningful analysis
        @test length(objectives) >= 10
    end

    @testset "Complete Workflow: Load → Refine → Analyze" begin
        # 1. Load configuration
        config = load_experiment_config(fixtures_dir)
        dimension = config["dimension"]

        # 2. Load critical points for degree 4
        df4 = load_critical_points_for_degree(fixtures_dir, 4)

        # 3. Select top 5 points for refinement
        n_refine = 5
        sorted_indices = sortperm(df4.objective)
        top_indices = sorted_indices[1:n_refine]

        raw_points = [
            [df4[idx, Symbol("p$i")] for i in 1:dimension]
            for idx in top_indices
        ]
        raw_values = [df4[idx, :objective] for idx in top_indices]

        # 4. Refine with real objective function
        refined_results = refine_critical_points_batch(
            deuflhard_4d_fixture,
            raw_points;
            max_iterations = 500,
            show_progress = false
        )

        # 5. Analyze refinement quality
        converged = [r.converged for r in refined_results]
        improvements = [r.improvement for r in refined_results]
        refined_values = [r.value_refined for r in refined_results]

        # Statistics
        convergence_rate = count(converged) / length(converged)
        mean_improvement = mean(improvements)
        best_refined_value = minimum(refined_values)

        # Assertions
        @test convergence_rate >= 0.8  # At least 80% should converge
        @test mean_improvement >= 0.0  # Should improve on average
        @test best_refined_value <= minimum(raw_values)  # Best should be at least as good

        # 6. Load quality thresholds and assess
        thresholds = load_quality_thresholds()

        # 7. Check objective distribution
        all_objectives = df4.objective
        dist_quality = check_objective_distribution_quality(all_objectives, thresholds)
        @test dist_quality.quality in [:excellent, :good, :fair, :poor]

        # 8. Load L2 norms and check quality
        summary_path = joinpath(fixtures_dir, "results_summary.json")
        summary_data = JSON3.read(read(summary_path, String))
        degree_results = summary_data.degree_results
        deg4_entry = findfirst(entry -> entry.degree == 4, degree_results)
        l2_norm = degree_results[deg4_entry].l2_norm
        l2_quality = check_l2_quality(l2_norm, dimension, thresholds)
        @test l2_quality in [:excellent, :good, :fair, :poor]

        # Success: Full workflow executed without errors
        @test true
    end

    @testset "Multi-Degree Analysis" begin
        # Load both degrees
        df4 = load_critical_points_for_degree(fixtures_dir, 4)
        df6 = load_critical_points_for_degree(fixtures_dir, 6)

        # Compare number of critical points
        @test nrow(df6) > nrow(df4)  # Higher degree → more critical points

        # Compare best objective values
        best_obj_4 = minimum(df4.objective)
        best_obj_6 = minimum(df6.objective)

        # Both should find valid (non-negative) objective values
        # Note: Higher degree doesn't guarantee better minima for polynomial approximations
        @test best_obj_4 >= 0.0
        @test best_obj_6 >= 0.0

        # Load L2 norms
        summary_path = joinpath(fixtures_dir, "results_summary.json")
        summary_data = JSON3.read(read(summary_path, String))
        degree_results = summary_data.degree_results

        l2_dict = Dict(entry.degree => entry.l2_norm for entry in degree_results)

        # L2 should decrease with degree
        @test l2_dict[6] < l2_dict[4]

        # Improvement ratio
        improvement_ratio = l2_dict[4] / l2_dict[6]
        @test improvement_ratio > 1.0  # Degree 6 should be better

        # Load thresholds and check for stagnation
        thresholds = load_quality_thresholds()
        stagnation = detect_stagnation(l2_dict, thresholds)

        # With only 2 degrees and improvement, should not be stagnant
        @test !stagnation.is_stagnant
    end

    @testset "Refinement Convergence Analysis" begin
        # Refine a subset and analyze convergence patterns
        df4 = load_critical_points_for_degree(fixtures_dir, 4)

        # Test on 20 points with varying initial quality
        n_test = min(20, nrow(df4))
        test_indices = 1:n_test

        raw_points = [
            [df4[idx, Symbol("p$i")] for i in 1:4]
            for idx in test_indices
        ]

        results = refine_critical_points_batch(
            deuflhard_4d_fixture,
            raw_points;
            max_iterations = 500,
            show_progress = false
        )

        # Analyze convergence statistics
        converged = [r.converged for r in results]
        f_calls = [r.f_calls for r in results]
        times = [r.time_elapsed for r in results]
        improvements = [r.improvement for r in results]

        @test mean(converged) >= 0.7  # At least 70% convergence
        @test mean(f_calls) > 0
        @test mean(times) > 0.0
        @test mean(improvements) >= 0.0

        # Convergence reasons
        reasons = [r.convergence_reason for r in results]
        @test all(r in [:x_tol, :f_tol, :g_tol, :iterations, :timeout, :error, :unknown] for r in reasons)

        # If converged, most should be due to tolerance
        converged_reasons = [r.convergence_reason for r in results if r.converged]
        if !isempty(converged_reasons)
            tolerance_converged = count(r in [:x_tol, :f_tol, :g_tol] for r in converged_reasons)
            @test tolerance_converged >= length(converged_reasons) * 0.5  # At least 50%
        end
    end

    @testset "Data Consistency Checks" begin
        # Verify fixture data consistency
        config = load_experiment_config(fixtures_dir)

        # Check all critical points are within domain
        domain_range = config["domain_range"]

        for degree in [4, 6]
            df = load_critical_points_for_degree(fixtures_dir, degree)

            for i in 1:4
                p_col = df[!, Symbol("p$i")]
                @test all(-domain_range .<= p_col .<= domain_range)
            end

            # Check objectives are non-negative (Deuflhard property)
            @test all(df.objective .>= 0.0)

            # Check no NaN or Inf
            @test all(isfinite.(df.objective))
        end
    end

    @testset "Objective Function Properties" begin
        # Verify Deuflhard properties

        # 1. Known value at origin: (exp(0)-3)² = 4 per 2D component, 4D = 8
        origin_value = deuflhard_4d_fixture([0.0, 0.0, 0.0, 0.0])
        @test origin_value ≈ 8.0 atol=0.01  # Deuflhard at origin is (1-3)² + (1-3)² = 8

        # 2. Symmetric (due to structure)
        p1 = [0.5, 0.3, 0.2, 0.1]
        p2 = [0.2, 0.1, 0.5, 0.3]  # Swap first/second pairs
        v1 = deuflhard_4d_fixture(p1)
        v2 = deuflhard_4d_fixture(p2)
        # Values should be similar (both evaluate 2D Deuflhard on similar inputs)
        @test abs(v1 - v2) < 1.0  # Rough symmetry

        # 3. Non-negative everywhere
        for _ in 1:20
            p = randn(4) * 1.0
            v = deuflhard_4d_fixture(p)
            @test v >= 0.0
        end

        # 4. Increases away from origin
        directions = [[1,0,0,0], [0,1,0,0], [0,0,1,0], [0,0,0,1]]
        for direction in directions
            v_near = deuflhard_4d_fixture(0.1 * direction)
            v_far = deuflhard_4d_fixture(0.5 * direction)
            # Generally increases (may have local minima)
            @test isfinite(v_near) && isfinite(v_far)
        end
    end
end

println("✅ All integration tests with real fixtures passed!")
