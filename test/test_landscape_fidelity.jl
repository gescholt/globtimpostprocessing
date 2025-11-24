"""
    test_landscape_fidelity.jl

Tests for landscape fidelity assessment functionality.
"""

using Test
using DataFrames
using LinearAlgebra
using GlobtimPostProcessing

@testset "Landscape Fidelity" begin

    @testset "check_objective_proximity - Basic Functionality" begin
        # Simple quadratic: f(x) = sum(x^2), minimum at origin
        f(x) = sum(x.^2)

        # Test 1: Points very close in objective space
        x_star = [0.01, 0.01]
        x_min = [0.0, 0.0]
        result = check_objective_proximity(x_star, x_min, f, tolerance=0.05)

        @test result.is_same_basin == true
        @test result.f_star ≈ 0.0002
        @test result.f_min ≈ 0.0
        @test result.metric < 0.05

        # Test 2: Points far apart in objective space
        x_star = [0.5, 0.5]
        x_min = [0.0, 0.0]
        result = check_objective_proximity(x_star, x_min, f, tolerance=0.05)

        @test result.is_same_basin == false
        # With asymmetric criterion: f_min ≈ 0, so returns absolute difference
        @test result.metric ≈ 0.5  # abs(f_star - f_min) = abs(0.5 - 0.0)
    end

    @testset "check_objective_proximity - Edge Cases" begin
        f(x) = sum(x.^2)

        # Test: Both points at minimum (f = 0)
        x_star = [0.0, 0.0]
        x_min = [0.0, 0.0]
        result = check_objective_proximity(x_star, x_min, f)

        @test result.is_same_basin == true
        @test result.f_star == 0.0
        @test result.f_min == 0.0

        # Test: Custom tolerance
        x_star = [0.1, 0.1]
        x_min = [0.0, 0.0]

        result_strict = check_objective_proximity(x_star, x_min, f, tolerance=0.01)
        @test result_strict.is_same_basin == false

        result_lenient = check_objective_proximity(x_star, x_min, f, tolerance=1.0)
        @test result_lenient.is_same_basin == true
    end

    @testset "check_objective_proximity - Global Minima Bug Fix (Issue #2)" begin
        # Regression test for bug discovered in testing
        # Bug: When f_min ≈ 0, relative difference calculation explodes
        # f_star = 0.001, f_min = 0.0 → rel_diff = 1e7 instead of accepting

        f(x) = sum((x .- 0.5).^2)  # Global minimum at [0.5, 0.5, ...]

        # Case 1: Both near global minimum (should be same basin)
        x_star = [0.48, 0.52, 0.49, 0.51]  # Very close to minimum
        x_min = [0.50, 0.50, 0.50, 0.50]   # Exact minimum

        result = check_objective_proximity(x_star, x_min, f, tolerance=0.05)

        # Verify the function values
        @test result.f_star ≈ 0.001 atol=1e-4  # Small value near global min
        @test result.f_min ≈ 0.0
        # Should recognize as same basin (both at global minimum)
        @test result.is_same_basin == true
        # Metric should be absolute difference (not exploded relative diff)
        @test result.metric ≈ 1e-3 atol=1e-6  # abs(f_star - f_min) ≈ 0.001 (allow floating-point error)

        # Case 2: One point far from global minimum (should be different basin)
        x_star_far = [0.9, 0.9, 0.9, 0.9]
        result_far = check_objective_proximity(x_star_far, x_min, f, tolerance=0.05)

        @test result_far.is_same_basin == false
        @test result_far.f_star > 1e-3  # Far from minimum
    end

    @testset "estimate_basin_radius - Basic Functionality" begin
        # Quadratic: f(x) = x^2, f''(x) = 2
        f(x) = sum(x.^2)
        x_min = [0.0, 0.0]
        H = [2.0 0.0; 0.0 2.0]  # Hessian of f at minimum

        r = estimate_basin_radius(x_min, f, H, threshold_factor=0.1)

        @test !isnan(r)
        @test r > 0.0
        # For f(x) = sum(x^2), minimum eigenvalue = 2
        # Basin radius where f increases by 10% of f(0) = 0
        # Using absolute threshold = 0.1: r = sqrt(2*0.1/2) = sqrt(0.1) ≈ 0.316
        @test r ≈ sqrt(0.1) atol=1e-10
    end

    @testset "estimate_basin_radius - Degenerate Cases" begin
        f(x) = sum(x.^2)
        x_min = [0.0, 0.0]

        # Degenerate Hessian (not a minimum)
        H_degenerate = [-1.0 0.0; 0.0 2.0]  # Saddle point
        r = estimate_basin_radius(x_min, f, H_degenerate)
        @test isnan(r)

        # Singular Hessian
        H_singular = [0.0 0.0; 0.0 0.0]
        r = estimate_basin_radius(x_min, f, H_singular)
        @test isnan(r)
    end

    @testset "estimate_basin_radius - Non-zero Minimum" begin
        # f(x) = (x-1)^2 + (y-1)^2, minimum at [1, 1] with f(x_min) = 0
        # Shifted to have non-zero minimum: f(x) = above + 10
        f(x) = sum((x .- 1.0).^2) + 10.0
        x_min = [1.0, 1.0]
        H = [2.0 0.0; 0.0 2.0]

        r = estimate_basin_radius(x_min, f, H, threshold_factor=0.1)

        @test !isnan(r)
        @test r > 0.0
        # f(x_min) = 10, threshold = 0.1 * 10 = 1.0
        # r = sqrt(2*1.0/2) = 1.0
        @test r ≈ 1.0 atol=1e-10
    end

    @testset "check_hessian_basin - Inside Basin" begin
        f(x) = sum((x .- 0.5).^2)
        x_min = [0.5, 0.5]
        x_star = [0.51, 0.49]  # Close to minimum
        H = [2.0 0.0; 0.0 2.0]

        result = check_hessian_basin(x_star, x_min, f, H)

        @test result.is_same_basin == true
        @test result.metric < 1.0  # Relative distance < 1
        @test result.distance ≈ sqrt(0.01^2 + 0.01^2)
        @test !isnan(result.basin_radius)
        @test result.min_eigenvalue == 2.0
    end

    @testset "check_hessian_basin - Outside Basin" begin
        f(x) = sum(x.^2)
        x_min = [0.0, 0.0]
        x_star = [1.0, 1.0]  # Far from minimum
        H = [2.0 0.0; 0.0 2.0]

        result = check_hessian_basin(x_star, x_min, f, H)

        @test result.is_same_basin == false
        @test result.metric > 1.0  # Relative distance > 1
        @test result.distance ≈ sqrt(2.0)
    end

    @testset "check_hessian_basin - Degenerate Hessian" begin
        f(x) = sum(x.^2)
        x_min = [0.0, 0.0]
        x_star = [0.1, 0.1]
        H_degenerate = [-1.0 0.0; 0.0 2.0]  # Saddle

        result = check_hessian_basin(x_star, x_min, f, H_degenerate)

        @test result.is_same_basin == false
        @test isnan(result.basin_radius)
    end

    @testset "assess_landscape_fidelity - Objective Only" begin
        f(x) = sum(x.^2)
        x_star = [0.01, 0.01]
        x_min = [0.0, 0.0]

        # Without Hessian
        result = assess_landscape_fidelity(x_star, x_min, f)

        @test result.is_same_basin == true
        @test result.confidence == 1.0  # Only one criterion, it passed
        @test length(result.criteria) == 1
        @test result.criteria[1].name == "objective_proximity"
        @test result.criteria[1].passed == true
        @test result.x_star == x_star
        @test result.x_min == x_min
    end

    @testset "assess_landscape_fidelity - With Hessian" begin
        f(x) = sum(x.^2)
        x_star = [0.01, 0.01]
        x_min = [0.0, 0.0]
        H = [2.0 0.0; 0.0 2.0]

        # With Hessian
        result = assess_landscape_fidelity(x_star, x_min, f, hessian_min=H)

        @test result.is_same_basin == true
        @test result.confidence == 1.0  # Both criteria passed
        @test length(result.criteria) == 2
        @test result.criteria[1].name == "objective_proximity"
        @test result.criteria[2].name == "hessian_basin"
        @test all([c.passed for c in result.criteria])
    end

    @testset "assess_landscape_fidelity - Mixed Results" begin
        # Construct scenario where objective passes but Hessian fails
        # (or vice versa) to test consensus

        # Objective with flat region: f(x) = 0 for |x| < 1, else (|x|-1)^2
        function f_flat(x)
            r = norm(x)
            return r < 1.0 ? 0.0 : (r - 1.0)^2
        end

        x_star = [0.5, 0.0]  # In flat region
        x_min = [0.0, 0.0]   # Also in flat region
        H = [2.0 0.0; 0.0 2.0]

        result = assess_landscape_fidelity(x_star, x_min, f_flat, hessian_min=H)

        # Objective proximity should pass (both give f=0)
        obj_criterion = result.criteria[findfirst(c -> c.name == "objective_proximity", result.criteria)]
        @test obj_criterion.passed == true

        # Majority vote determines result
        @test result.confidence >= 0.5
    end

    @testset "assess_landscape_fidelity - All Fail" begin
        f(x) = sum(x.^2)
        x_star = [10.0, 10.0]  # Far from minimum
        x_min = [0.0, 0.0]
        H = [2.0 0.0; 0.0 2.0]

        result = assess_landscape_fidelity(x_star, x_min, f, hessian_min=H)

        @test result.is_same_basin == false
        @test result.confidence == 0.0  # All criteria failed
        @test all([!c.passed for c in result.criteria])
    end

    @testset "batch_assess_fidelity - Basic Functionality" begin
        # Create synthetic critical points DataFrame
        df = DataFrame(
            x1 = [0.01, 0.02, 0.50],
            x2 = [0.02, -0.01, 0.60],
            hessian_eigenvalue_1 = [2.0, 2.0, 2.0],
            hessian_eigenvalue_2 = [2.0, 2.0, 2.0]
        )

        # Classify
        classify_all_critical_points!(df)

        # All should be minima (positive eigenvalues)
        @test all(df.point_classification .== "minimum")

        # Objective
        f(x) = sum(x.^2)

        # Refined points (all converge to origin)
        refined = [[0.0, 0.0], [0.0, 0.0], [0.0, 0.0]]

        # Batch assess
        result_df = batch_assess_fidelity(df, refined, f)

        @test nrow(result_df) == 3
        @test :is_same_basin in propertynames(result_df)
        @test :fidelity_confidence in propertynames(result_df)
        @test :objective_proximity_metric in propertynames(result_df)

        # First two should pass (close to origin)
        @test result_df[1, :is_same_basin] == true
        @test result_df[2, :is_same_basin] == true

        # Third might fail (started far away)
        # (depends on objective proximity tolerance)
    end

    @testset "batch_assess_fidelity - With Hessians" begin
        df = DataFrame(
            x1 = [0.01, 0.02],
            x2 = [0.02, -0.01],
            hessian_eigenvalue_1 = [2.0, 2.0],
            hessian_eigenvalue_2 = [2.0, 2.0]
        )

        classify_all_critical_points!(df)

        f(x) = sum(x.^2)
        refined = [[0.0, 0.0], [0.0, 0.0]]
        hessians = [[2.0 0.0; 0.0 2.0], [2.0 0.0; 0.0 2.0]]

        result_df = batch_assess_fidelity(df, refined, f, hessian_min_list=hessians)

        @test :hessian_basin_metric in propertynames(result_df)
        @test all(.!ismissing.(result_df.hessian_basin_metric))
    end

    @testset "batch_assess_fidelity - Error Handling" begin
        df = DataFrame(
            x1 = [0.01, 0.02],
            x2 = [0.02, -0.01],
            hessian_eigenvalue_1 = [2.0, 2.0],
            hessian_eigenvalue_2 = [2.0, 2.0]
        )

        classify_all_critical_points!(df)

        f(x) = sum(x.^2)

        # Wrong number of refined points
        refined_wrong = [[0.0, 0.0]]  # Only 1, should be 2

        @test_throws ErrorException batch_assess_fidelity(df, refined_wrong, f)
    end

    @testset "Integration Test - Full Workflow" begin
        # Simulate a complete workflow

        # 1. Load critical points (simulated)
        df = DataFrame(
            x1 = [0.48, 0.21, 0.79, 0.51],
            x2 = [0.52, 0.19, 0.81, 0.49],
            x3 = [0.49, 0.22, 0.78, 0.50],
            x4 = [0.51, 0.20, 0.80, 0.52],
            z = [0.01, 0.02, 0.02, 0.01],
            hessian_eigenvalue_1 = [2.0, 2.0, 2.0, 2.0],
            hessian_eigenvalue_2 = [2.0, 2.0, 2.0, 2.0],
            hessian_eigenvalue_3 = [2.0, 2.0, 2.0, 2.0],
            hessian_eigenvalue_4 = [2.0, 2.0, 2.0, 2.0]
        )

        # 2. Classify
        classify_all_critical_points!(df)
        @test all(df.point_classification .== "minimum")

        # 3. Define objective
        f(x) = sum((x .- 0.5).^2)

        # 4. Run local optimization (simulated - all converge to [0.5, 0.5, 0.5, 0.5])
        refined = fill([0.5, 0.5, 0.5, 0.5], 4)

        # 5. Assess fidelity
        result_df = batch_assess_fidelity(df, refined, f)

        # 6. Analyze results
        num_valid = sum(result_df.is_same_basin)
        @test num_valid >= 2  # At least half should be valid

        fidelity_rate = num_valid / nrow(result_df)
        @test fidelity_rate >= 0.5  # At least 50% fidelity
    end

end
