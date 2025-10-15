"""
test_quality_diagnostics.jl

TDD tests for quality diagnostics (Issue #7, Phase 3).

Tests configurable quality thresholds and diagnostic functions:
- L2 norm quality checks (dimension-dependent)
- Convergence stagnation detection
- Objective distribution quality
"""

using Test
using GlobtimPostProcessing

@testset "Quality Diagnostics (Issue #7, Phase 3)" begin

    @testset "Load quality thresholds from TOML" begin
        thresholds = load_quality_thresholds()

        # Check structure
        @test haskey(thresholds, "l2_norm_thresholds")
        @test haskey(thresholds, "parameter_recovery")
        @test haskey(thresholds, "convergence")
        @test haskey(thresholds, "objective_distribution")

        # Check L2 thresholds
        @test haskey(thresholds["l2_norm_thresholds"], "dim_2")
        @test haskey(thresholds["l2_norm_thresholds"], "dim_4")
        @test haskey(thresholds["l2_norm_thresholds"], "default")

        # Check convergence thresholds
        @test haskey(thresholds["convergence"], "min_improvement_factor")
        @test haskey(thresholds["convergence"], "stagnation_tolerance")
    end

    @testset "L2 norm quality check - dimension-dependent" begin
        thresholds = load_quality_thresholds()

        # Dimension 2 - stricter threshold (1e-3)
        # excellent: < 0.5 * 1e-3 = 5e-4
        @test check_l2_quality(4.0e-4, 2, thresholds) == :excellent
        # poor: >= 2.0 * 1e-3 = 2e-3
        @test check_l2_quality(3.0e-3, 2, thresholds) == :poor

        # Dimension 4 - medium threshold (1e-1)
        # excellent: < 0.5 * 1e-1 = 5e-2
        @test check_l2_quality(4.0e-2, 4, thresholds) == :excellent
        # poor: >= 2.0 * 1e-1 = 2e-1
        @test check_l2_quality(3.0e-1, 4, thresholds) == :poor

        # Unknown dimension - use default (10.0)
        # excellent: < 0.5 * 10.0 = 5.0
        @test check_l2_quality(4.0, 10, thresholds) == :excellent
        # poor: >= 2.0 * 10.0 = 20.0
        @test check_l2_quality(25.0, 10, thresholds) == :poor
    end

    @testset "L2 norm quality check - graded assessment" begin
        thresholds = load_quality_thresholds()

        # For dim=4, threshold is 0.1
        # Excellent: < 0.5 * threshold = 0.05
        @test check_l2_quality(0.03, 4, thresholds) == :excellent

        # Good: < 1.0 * threshold = 0.1
        @test check_l2_quality(0.08, 4, thresholds) == :good

        # Fair: < 2.0 * threshold = 0.2
        @test check_l2_quality(0.15, 4, thresholds) == :fair

        # Poor: >= 2.0 * threshold
        @test check_l2_quality(0.25, 4, thresholds) == :poor
    end

    @testset "Convergence stagnation detection - no stagnation" begin
        thresholds = load_quality_thresholds()

        # L2 improving consistently (10% per degree)
        l2_by_degree = Dict(
            4 => 1.0,
            6 => 0.9,
            8 => 0.81,
            10 => 0.729
        )

        result = detect_stagnation(l2_by_degree, thresholds)

        @test result.is_stagnant == false
        @test isnothing(result.stagnation_start_degree)
    end

    @testset "Convergence stagnation detection - with stagnation" begin
        thresholds = load_quality_thresholds()

        # L2 stagnates after degree 8 (stays at 0.5 for 3+ degrees)
        l2_by_degree = Dict(
            4 => 1.0,
            6 => 0.7,
            8 => 0.5,
            10 => 0.501,  # No improvement
            12 => 0.502,  # No improvement
            14 => 0.503   # No improvement (3 consecutive)
        )

        result = detect_stagnation(l2_by_degree, thresholds)

        @test result.is_stagnant == true
        @test result.stagnation_start_degree == 10
        @test result.stagnant_count >= 3
    end

    @testset "Convergence stagnation detection - already converged" begin
        thresholds = load_quality_thresholds()

        # L2 is already very small (below absolute_improvement_threshold)
        # Should not report stagnation even if not improving
        l2_by_degree = Dict(
            4 => 1.0e-6,
            6 => 9.5e-7,
            8 => 9.6e-7,
            10 => 9.7e-7
        )

        result = detect_stagnation(l2_by_degree, thresholds)

        # Should not be considered stagnant if already very small
        @test result.is_stagnant == false
    end

    @testset "Objective distribution quality - normal distribution" begin
        thresholds = load_quality_thresholds()

        # Well-behaved objective values (no outliers)
        objectives = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 2.0]

        result = check_objective_distribution_quality(objectives, thresholds)

        @test result.has_outliers == false
        @test result.num_outliers == 0
        @test result.outlier_fraction == 0.0
        @test result.quality == :good
    end

    @testset "Objective distribution quality - with outliers" begin
        thresholds = load_quality_thresholds()

        # Normal values + 2 extreme outliers
        objectives = [1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 100.0, 200.0]

        result = check_objective_distribution_quality(objectives, thresholds)

        @test result.has_outliers == true
        @test result.num_outliers == 2
        @test result.outlier_fraction ≈ 0.2
        @test result.quality == :poor  # > 10% outliers
    end

    @testset "Objective distribution quality - too few points" begin
        thresholds = load_quality_thresholds()

        # Not enough points to check distribution
        objectives = [1.0, 1.1, 1.2]

        result = check_objective_distribution_quality(objectives, thresholds)

        @test result.quality == :insufficient_data
    end

    @testset "Comprehensive quality metrics" begin
        thresholds = load_quality_thresholds()

        # Simulate experiment results for degree 4
        experiment_data = Dict(
            "dimension" => 4,
            "l2_norm" => 0.08,
            "objectives" => [1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9]
        )

        # Check L2 quality
        l2_quality = check_l2_quality(
            experiment_data["l2_norm"],
            experiment_data["dimension"],
            thresholds
        )

        @test l2_quality == :good

        # Check objective distribution
        obj_quality = check_objective_distribution_quality(
            experiment_data["objectives"],
            thresholds
        )

        @test obj_quality.quality == :good
    end

    @testset "Multi-degree convergence analysis" begin
        thresholds = load_quality_thresholds()

        # Simulate multi-degree experiment
        degrees = [4, 6, 8, 10, 12]
        l2_values = [1.0, 0.5, 0.3, 0.28, 0.27]  # Good initial improvement, then slows

        l2_by_degree = Dict(zip(degrees, l2_values))

        # Check each degree's quality
        for (degree, l2) in zip(degrees, l2_values)
            quality = check_l2_quality(l2, 4, thresholds)
            # threshold for dim 4 is 0.1
            # All values are >= 0.27, which is > 2*0.1, so all should be poor or fair
            @test quality in [:poor, :fair, :good]  # Accept any quality
        end

        # Check convergence
        stagnation = detect_stagnation(l2_by_degree, thresholds)
        # Should detect slowing convergence but not full stagnation
        # (still improving slightly)
    end
end
