"""
    test_cp_verification.jl

Level 0 tests for the CP verification oracle.

Tests verify_critical_point (0a), classify_by_hessian (0b),
verify_local_minimum (0c), verify_and_classify (0d), and
find_all_critical_points (0e).

These oracle utilities are the foundation for all higher-level
verification tests (L1-L9). They must be rock-solid.

Run with:
    julia --project=pkg/globtimpostprocessing/test pkg/globtimpostprocessing/test/test_cp_verification.jl
"""

using Test
using LinearAlgebra
using ForwardDiff

# Include the module under test (guarded for runtests.jl which pre-includes it)
if !@isdefined(CPVerification)
    include(joinpath(@__DIR__, "test_utils", "cp_verification.jl"))
end
using .CPVerification

# ============================================================================
# Test functions with analytically known critical points
# ============================================================================

# Simple quadratic: f(x) = x₁² + x₂² — single minimum at origin
quadratic(x) = x[1]^2 + x[2]^2

# Shifted quadratic: f(x) = (x₁ - 1)² + (x₂ - 2)² — minimum at [1, 2]
shifted_quadratic(x) = (x[1] - 1)^2 + (x[2] - 2)^2

# Negative definite: f(x) = -(x₁² + x₂²) — maximum at origin
neg_quadratic(x) = -(x[1]^2 + x[2]^2)

# Saddle: f(x) = x₁² - x₂² — saddle at origin
saddle_func(x) = x[1]^2 - x[2]^2

# Rosenbrock 2D: f(x) = (1-x₁)² + 100(x₂-x₁²)²
# Single minimum at [1, 1], saddle-like behavior elsewhere
rosenbrock(x) = (1 - x[1])^2 + 100 * (x[2] - x[1]^2)^2

# Six-hump camel: well-known test function with 6 critical points in [-3,3]×[-2,2]
# 2 global minima, 2 local minima, 2 local maxima (saddle points of the landscape)
sixhump_camel(x) = (4 - 2.1*x[1]^2 + x[1]^4/3)*x[1]^2 + x[1]*x[2] + (-4 + 4*x[2]^2)*x[2]^2

# Himmelblau: f(x) = (x₁² + x₂ - 11)² + (x₁ + x₂² - 7)²
# 4 identical minima, 1 local maximum, 4 saddle points
himmelblau(x) = (x[1]^2 + x[2] - 11)^2 + (x[1] + x[2]^2 - 7)^2

# Degenerate: f(x) = x₁⁴ + x₂² — degenerate critical point at origin
# (Hessian has a zero eigenvalue in x₁ direction at origin)
degenerate_func(x) = x[1]^4 + x[2]^2

# 1D quadratic for dimension edge case
quadratic_1d(x) = x[1]^2

# ============================================================================
# 0a: verify_critical_point tests
# ============================================================================
@testset "0a: verify_critical_point" begin
    @testset "True critical points" begin
        # Origin is critical for quadratic
        @test verify_critical_point(quadratic, [0.0, 0.0]) == true

        # [1, 2] is critical for shifted quadratic
        @test verify_critical_point(shifted_quadratic, [1.0, 2.0]) == true

        # Origin is critical for negative quadratic
        @test verify_critical_point(neg_quadratic, [0.0, 0.0]) == true

        # Origin is critical for saddle
        @test verify_critical_point(saddle_func, [0.0, 0.0]) == true

        # [1, 1] is critical for Rosenbrock
        @test verify_critical_point(rosenbrock, [1.0, 1.0]) == true

        # Origin is critical for degenerate function
        @test verify_critical_point(degenerate_func, [0.0, 0.0]) == true

        # 1D case
        @test verify_critical_point(quadratic_1d, [0.0]) == true
    end

    @testset "Non-critical points" begin
        # [1, 1] is NOT critical for quadratic
        @test verify_critical_point(quadratic, [1.0, 1.0]) == false

        # Origin is NOT critical for shifted quadratic
        @test verify_critical_point(shifted_quadratic, [0.0, 0.0]) == false

        # Far from minimum of Rosenbrock
        @test verify_critical_point(rosenbrock, [0.0, 0.0]) == false
    end

    @testset "Tolerance sensitivity" begin
        # Near-critical: gradient norm is small but nonzero
        near_critical = [1e-5, 1e-5]
        # grad of quadratic at [ε,ε] is [2ε, 2ε], norm ≈ 2√2 × 1e-5 ≈ 2.83e-5

        # With tight tolerance, should fail
        @test verify_critical_point(quadratic, near_critical; grad_tol = 1e-6) == false

        # With loose tolerance, should pass
        @test verify_critical_point(quadratic, near_critical; grad_tol = 1e-4) == true
    end

    @testset "Returns gradient norm" begin
        # verify_critical_point returns Bool; grad_norm available via verify_and_classify
        # Just verify it works with exact zeros
        @test verify_critical_point(quadratic, [0.0, 0.0]; grad_tol = 1e-15) == true
    end
end

# ============================================================================
# 0b: classify_by_hessian tests
# ============================================================================
@testset "0b: classify_by_hessian" begin
    @testset "Minimum classification" begin
        # Quadratic at origin — Hessian is [[2,0],[0,2]], both eigenvalues = 2
        @test classify_by_hessian(quadratic, [0.0, 0.0]) == :minimum

        # Shifted quadratic at its minimum
        @test classify_by_hessian(shifted_quadratic, [1.0, 2.0]) == :minimum

        # Rosenbrock at [1,1]
        @test classify_by_hessian(rosenbrock, [1.0, 1.0]) == :minimum
    end

    @testset "Maximum classification" begin
        # Negative quadratic at origin — eigenvalues are [-2, -2]
        @test classify_by_hessian(neg_quadratic, [0.0, 0.0]) == :maximum
    end

    @testset "Saddle classification" begin
        # Saddle function at origin — eigenvalues are [2, -2]
        @test classify_by_hessian(saddle_func, [0.0, 0.0]) == :saddle
    end

    @testset "Degenerate classification" begin
        # f(x) = x₁⁴ + x₂² at origin: Hessian = [[0,0],[0,2]]
        # One eigenvalue is 0 → degenerate
        @test classify_by_hessian(degenerate_func, [0.0, 0.0]) == :degenerate
    end

    @testset "Returns eigenvalues info" begin
        # classify_by_hessian returns Symbol; eigenvalues available via verify_and_classify
        # Just confirm it doesn't error on 1D
        @test classify_by_hessian(quadratic_1d, [0.0]) == :minimum
    end

    @testset "Tolerance for degenerate" begin
        # With very tight tol, small eigenvalues should NOT be degenerate
        # f(x) = 0.001*x₁² + x₂² at origin: eigenvalues [0.002, 2]
        weak_quadratic(x) = 0.001*x[1]^2 + x[2]^2

        # Default tol=1e-6: eigenvalue 0.002 >> 1e-6, so minimum
        @test classify_by_hessian(weak_quadratic, [0.0, 0.0]) == :minimum

        # With tol=0.01: eigenvalue 0.002 < 0.01, so degenerate
        @test classify_by_hessian(weak_quadratic, [0.0, 0.0]; tol = 0.01) == :degenerate
    end
end

# ============================================================================
# 0c: verify_local_minimum tests
# ============================================================================
@testset "0c: verify_local_minimum" begin
    @testset "Confirmed local minima" begin
        # Origin is local minimum of quadratic
        @test verify_local_minimum(quadratic, [0.0, 0.0]) == true

        # [1, 2] is local minimum of shifted quadratic
        @test verify_local_minimum(shifted_quadratic, [1.0, 2.0]) == true

        # [1, 1] is local minimum of Rosenbrock
        @test verify_local_minimum(rosenbrock, [1.0, 1.0]) == true
    end

    @testset "Non-minima rejected" begin
        # Origin is maximum of neg_quadratic — neighborhood has LOWER values
        @test verify_local_minimum(neg_quadratic, [0.0, 0.0]) == false

        # Origin is saddle — neighborhood has both lower and higher values
        @test verify_local_minimum(saddle_func, [0.0, 0.0]) == false
    end

    @testset "Radius parameter" begin
        # Very tight radius should still confirm quadratic minimum
        @test verify_local_minimum(quadratic, [0.0, 0.0]; radius = 1e-8, n_samples = 500) ==
              true

        # Larger radius should also work
        @test verify_local_minimum(quadratic, [0.0, 0.0]; radius = 1.0, n_samples = 1000) ==
              true
    end

    @testset "1D case" begin
        @test verify_local_minimum(quadratic_1d, [0.0]) == true
        neg_1d(x) = -x[1]^2
        @test verify_local_minimum(neg_1d, [0.0]) == false
    end

    @testset "Degenerate but still local minimum" begin
        # f(x) = x₁⁴ + x₂² at origin: Hessian degenerate but IS a local minimum
        @test verify_local_minimum(degenerate_func, [0.0, 0.0]) == true
    end
end

# ============================================================================
# 0d: verify_and_classify tests
# ============================================================================
@testset "0d: verify_and_classify" begin
    @testset "Complete minimum characterization" begin
        result = verify_and_classify(quadratic, [0.0, 0.0])

        @test result.is_critical == true
        @test result.classification == :minimum
        @test result.grad_norm < 1e-10
        @test all(result.eigenvalues .> 0)
        @test result.neighborhood_confirmed == true
        @test result.value ≈ 0.0 atol=1e-15
    end

    @testset "Complete maximum characterization" begin
        result = verify_and_classify(neg_quadratic, [0.0, 0.0])

        @test result.is_critical == true
        @test result.classification == :maximum
        @test result.grad_norm < 1e-10
        @test all(result.eigenvalues .< 0)
        @test result.neighborhood_confirmed == false  # not a minimum
    end

    @testset "Complete saddle characterization" begin
        result = verify_and_classify(saddle_func, [0.0, 0.0])

        @test result.is_critical == true
        @test result.classification == :saddle
        @test result.neighborhood_confirmed == false  # not a minimum
    end

    @testset "Non-critical point" begin
        result = verify_and_classify(quadratic, [1.0, 1.0])

        @test result.is_critical == false
        @test result.grad_norm > 1e-8
        # Classification still computed from Hessian at the point
        @test result.classification == :minimum  # Hessian is PD everywhere for quadratic
    end

    @testset "Rosenbrock minimum" begin
        result = verify_and_classify(rosenbrock, [1.0, 1.0])

        @test result.is_critical == true
        @test result.classification == :minimum
        @test result.neighborhood_confirmed == true
        @test result.value ≈ 0.0 atol=1e-10
    end

    @testset "Degenerate minimum" begin
        result = verify_and_classify(degenerate_func, [0.0, 0.0])

        @test result.is_critical == true
        @test result.classification == :degenerate
        @test result.neighborhood_confirmed == true  # IS a local minimum despite degenerate Hessian
    end

    @testset "NamedTuple structure" begin
        result = verify_and_classify(quadratic, [0.0, 0.0])

        # Verify all expected fields exist
        @test haskey(result, :is_critical)
        @test haskey(result, :classification)
        @test haskey(result, :grad_norm)
        @test haskey(result, :eigenvalues)
        @test haskey(result, :neighborhood_confirmed)
        @test haskey(result, :value)
    end
end

# ============================================================================
# VerifiedCP struct tests
# ============================================================================
@testset "VerifiedCP struct" begin
    cp = VerifiedCP(
        point = [0.0, 0.0],
        classification = :minimum,
        value = 0.0,
        grad_norm = 1e-12,
        eigenvalues = [2.0, 2.0],
        neighborhood_confirmed = true,
    )

    @test cp.point == [0.0, 0.0]
    @test cp.classification == :minimum
    @test cp.value == 0.0
    @test cp.grad_norm == 1e-12
    @test cp.eigenvalues == [2.0, 2.0]
    @test cp.neighborhood_confirmed == true
end

# ============================================================================
# 0e: find_all_critical_points tests
# ============================================================================
@testset "0e: find_all_critical_points" begin
    @testset "Simple quadratic — finds single minimum" begin
        bounds = [(-2.0, 2.0), (-2.0, 2.0)]
        cps = find_all_critical_points(quadratic, bounds, 2; n_starts = 50, grad_tol = 1e-8)

        # Should find exactly 1 critical point (the minimum at origin)
        @test length(cps) >= 1

        # At least one should be near the origin
        origin_found = any(cp -> norm(cp.point) < 1e-4, cps)
        @test origin_found

        # All returned CPs should actually be critical
        for cp in cps
            @test cp.grad_norm < 1e-6
        end
    end

    @testset "Shifted quadratic — finds minimum at [1,2]" begin
        bounds = [(-3.0, 5.0), (-3.0, 5.0)]
        cps = find_all_critical_points(
            shifted_quadratic,
            bounds,
            2;
            n_starts = 50,
            grad_tol = 1e-8,
        )

        @test length(cps) >= 1

        target_found = any(cp -> norm(cp.point - [1.0, 2.0]) < 1e-4, cps)
        @test target_found
    end

    @testset "Himmelblau — finds 4 minima" begin
        # Himmelblau has 4 local minima at approximately:
        #   (3.0, 2.0), (-2.805, 3.131), (-3.779, -3.283), (3.584, -1.848)
        known_minima = [
            [3.0, 2.0],
            [-2.805118, 3.131312],
            [-3.779310, -3.283186],
            [3.584428, -1.848126],
        ]

        bounds = [(-5.0, 5.0), (-5.0, 5.0)]
        cps =
            find_all_critical_points(himmelblau, bounds, 2; n_starts = 200, grad_tol = 1e-8)

        # Filter to just the minima
        minima = filter(cp -> cp.classification == :minimum, cps)

        # Should find all 4 minima
        @test length(minima) >= 4

        # Each known minimum should be found
        for known in known_minima
            found = any(cp -> norm(cp.point - known) < 0.01, minima)
            @test found
        end
    end

    @testset "Saddle function — finds saddle at origin" begin
        bounds = [(-2.0, 2.0), (-2.0, 2.0)]
        cps =
            find_all_critical_points(saddle_func, bounds, 2; n_starts = 50, grad_tol = 1e-8)

        # Should find the saddle at origin
        saddle_found = any(cp -> norm(cp.point) < 1e-4 && cp.classification == :saddle, cps)
        @test saddle_found
    end

    @testset "Deduplication" begin
        # With many starts, quadratic should still give exactly 1 unique CP
        bounds = [(-2.0, 2.0), (-2.0, 2.0)]
        cps = find_all_critical_points(
            quadratic,
            bounds,
            2;
            n_starts = 100,
            grad_tol = 1e-8,
            dedup_tol = 1e-4,
        )

        @test length(cps) == 1
    end

    @testset "All returned CPs are verified" begin
        bounds = [(-5.0, 5.0), (-5.0, 5.0)]
        cps =
            find_all_critical_points(himmelblau, bounds, 2; n_starts = 100, grad_tol = 1e-6)

        for cp in cps
            @test cp.grad_norm < 1e-4  # all should be near-critical
            @test cp.classification in [:minimum, :maximum, :saddle, :degenerate]
            @test length(cp.eigenvalues) == 2
        end
    end

    @testset "1D case" begin
        bounds = [(-3.0, 3.0)]
        cps = find_all_critical_points(
            quadratic_1d,
            bounds,
            1;
            n_starts = 30,
            grad_tol = 1e-8,
        )

        @test length(cps) >= 1
        @test any(cp -> abs(cp.point[1]) < 1e-4, cps)
    end
end

println("\n✓ All Level 0 CP verification oracle tests completed")
