"""
Test suite for Landscape Fidelity features
Tests check_objective_proximity, check_hessian_basin, assess_landscape_fidelity, batch_assess_fidelity
"""

using Test
using LinearAlgebra
using Statistics
using DataFrames

# Functions are already loaded via GlobtimPostProcessing in runtests.jl

@testset "Objective Proximity Check" begin
    f(x) = sum((x .- 0.5).^2)
    x_star = [0.48, 0.52, 0.49, 0.51]
    x_min = [0.50, 0.50, 0.50, 0.50]

    result = check_objective_proximity(x_star, x_min, f, tolerance=0.05)

    @test result isa ObjectiveProximityResult
    @test result.is_same_basin == true
    @test result.metric < 0.05
    @test result.f_star ≈ f(x_star)
    @test result.f_min ≈ f(x_min)
end

@testset "Hessian Basin Check" begin
    f(x) = sum((x .- 0.5).^2)
    x_star = [0.48, 0.52, 0.49, 0.51]
    x_min = [0.50, 0.50, 0.50, 0.50]

    # Hessian of quadratic f(x) = Σ(x_i - 0.5)² is 2I
    H = 2.0 * I(4) |> Matrix

    result = check_hessian_basin(x_star, x_min, f, H)

    @test result isa HessianBasinResult
    @test result.is_same_basin == true
    @test result.distance ≈ norm(x_star - x_min)
    @test result.basin_radius > 0
    @test result.min_eigenvalue ≈ 2.0
end

@testset "Basin Radius Estimation" begin
    f(x) = sum((x .- 0.5).^2)
    x_min = [0.50, 0.50]
    H = [2.0 0.0; 0.0 2.0]

    r = estimate_basin_radius(x_min, f, H, threshold_factor=0.1)

    @test r > 0
    @test isfinite(r)
end

@testset "Composite Assessment" begin
    f(x) = sum((x .- 0.5).^2)
    x_star = [0.48, 0.52, 0.49, 0.51]
    x_min = [0.50, 0.50, 0.50, 0.50]
    H = 2.0 * I(4) |> Matrix

    result = assess_landscape_fidelity(x_star, x_min, f, hessian_min=H)

    @test result isa LandscapeFidelityResult
    @test result.is_same_basin == true
    @test result.confidence >= 0.5
    @test length(result.criteria) >= 1
    @test result.x_star == x_star
    @test result.x_min == x_min
end

@testset "Batch Assessment" begin
    f(x) = sum((x .- [0.5, 0.5]).^2)

    df = DataFrame(
        x1 = [0.48, 0.21, 0.79],
        x2 = [0.52, 0.19, 0.81],
        z = [f([0.48, 0.52]), f([0.21, 0.19]), f([0.79, 0.81])],
        point_classification = ["minimum", "minimum", "minimum"]
    )

    refined = [[0.50, 0.50], [0.20, 0.20], [0.80, 0.80]]
    hessians = [[2.0 0.0; 0.0 2.0], [2.0 0.0; 0.0 2.0], [2.0 0.0; 0.0 2.0]]

    result_df = batch_assess_fidelity(df, refined, f, hessian_min_list=hessians)

    @test nrow(result_df) == 3
    @test :is_same_basin in propertynames(result_df)
    @test :fidelity_confidence in propertynames(result_df)
    @test :objective_proximity_metric in propertynames(result_df)
    @test :hessian_basin_metric in propertynames(result_df)
end

@testset "Edge Cases" begin
    @testset "Saddle Point (Degenerate Hessian)" begin
        f_saddle(x) = x[1]^2 - x[2]^2
        H_saddle = [2.0 0.0; 0.0 -2.0]  # One negative eigenvalue
        x_s = [0.01, 0.01]
        x_m = [0.0, 0.0]

        result = check_hessian_basin(x_s, x_m, f_saddle, H_saddle)

        @test result.is_same_basin == false  # Saddle should not be classified as basin
    end

    @testset "Global Minimum (f ≈ 0)" begin
        f_global(x) = sum(x.^2)
        x_star = [0.01, 0.02]
        x_min = [0.0, 0.0]

        result = check_objective_proximity(x_star, x_min, f_global)

        @test result.is_same_basin == true  # Both near global minimum
    end

    @testset "Distant Points" begin
        f(x) = sum((x .- 0.5).^2)
        x_far = [0.9, 0.9, 0.9, 0.9]
        x_min = [0.5, 0.5, 0.5, 0.5]

        result = check_objective_proximity(x_far, x_min, f, tolerance=0.01)

        @test result.is_same_basin == false  # Far apart, different objective values
    end
end
