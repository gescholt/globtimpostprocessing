"""
    test_valley_walking.jl

Tests for valley walking algorithm: detection of positive-dimensional minima
and predictor-corrector tracing along valley manifolds.

Test functions:
- f_circle(x) = (x₁² + x₂² - 1)²      — unit circle is a 1D valley of zeros in 2D
- f_quadratic(x) = x₁² + x₂²            — isolated minimum at origin (0D, NOT a valley)
- f_saddle(x) = x₁² - x₂²               — saddle at origin (not a valley)
- f_circle3d(x) = (x₁² + x₂² - 1)² + x₃²  — circle valley embedded in 3D (x₃=0 plane)
- f_offset_valley(x) = (x₁² + x₂² - 1)² + 0.01  — valley with f_min > 0 (tests projection fix)
"""

using Test
using LinearAlgebra
using ForwardDiff
using DataFrames

# Functions are already loaded via GlobtimPostProcessing in runtests.jl

# ─── Test functions ──────────────────────────────────────────────────────────

# 1D valley: unit circle in 2D. Every point on x₁²+x₂²=1 is a minimum with f=0.
f_circle(x) = (x[1]^2 + x[2]^2 - 1)^2

# Isolated minimum at origin. No valley — all Hessian eigenvalues are positive.
f_quadratic(x) = x[1]^2 + x[2]^2

# Saddle at origin. Not a valley.
f_saddle(x) = x[1]^2 - x[2]^2

# Circle valley in 3D. The valley is the unit circle in the x₁-x₂ plane at x₃=0.
f_circle3d(x) = (x[1]^2 + x[2]^2 - 1)^2 + x[3]^2

# Valley with nonzero minimum value. Tests that projection targets ∇f=0, not f=0.
f_offset_valley(x) = (x[1]^2 + x[2]^2 - 1)^2 + 0.01

# ─── detect_valley tests ────────────────────────────────────────────────────

@testset "detect_valley" begin
    config = ValleyWalkConfig(gradient_tolerance=1e-4, eigenvalue_threshold=1e-2)

    @testset "detects valley on unit circle" begin
        # Point on the unit circle: gradient is zero, one Hessian eigenvalue is zero
        point = [1.0, 0.0]
        is_valley, directions, vdim = detect_valley(f_circle, point, config)
        @test is_valley == true
        @test directions !== nothing
        @test vdim == 1               # 1D valley
        @test size(directions, 2) == 1
        # Valley tangent at (1,0) should be along y-axis: [0, ±1]
        tangent = directions[:, 1]
        @test abs(tangent[1]) < 0.1   # nearly zero x-component
        @test abs(tangent[2]) > 0.9   # nearly unit y-component
    end

    @testset "detects valley at other circle points" begin
        # Point (0, 1) on the circle
        point = [0.0, 1.0]
        is_valley, directions, vdim = detect_valley(f_circle, point, config)
        @test is_valley == true
        @test vdim == 1
        @test size(directions, 2) == 1
        # Tangent at (0,1) should be along x-axis
        tangent = directions[:, 1]
        @test abs(tangent[1]) > 0.9
        @test abs(tangent[2]) < 0.1
    end

    @testset "detects valley at 45-degree point" begin
        point = [1/sqrt(2), 1/sqrt(2)]
        is_valley, directions, vdim = detect_valley(f_circle, point, config)
        @test is_valley == true
        @test vdim == 1
        @test size(directions, 2) == 1
    end

    @testset "rejects isolated minimum" begin
        point = [0.0, 0.0]
        is_valley, directions, vdim = detect_valley(f_quadratic, point, config)
        @test is_valley == false
        @test directions === nothing
        @test vdim == 0
    end

    @testset "rejects saddle point" begin
        # Saddle has non-zero eigenvalues (one positive, one negative), not a valley
        point = [0.0, 0.0]
        is_valley, directions, vdim = detect_valley(f_saddle, point, config)
        @test is_valley == false
        @test directions === nothing
        @test vdim == 0
    end

    @testset "rejects non-critical point" begin
        # Off the circle: gradient is nonzero
        point = [0.5, 0.0]
        is_valley, directions, vdim = detect_valley(f_circle, point, config)
        @test is_valley == false
        @test directions === nothing
        @test vdim == 0
    end

    @testset "detects valley in 3D (circle in x₁-x₂ plane)" begin
        point = [1.0, 0.0, 0.0]
        is_valley, directions, vdim = detect_valley(f_circle3d, point, config)
        @test is_valley == true
        @test vdim == 1               # still a 1D valley
        @test size(directions, 2) == 1
        # Tangent should be in the x₁-x₂ plane (x₃ component ≈ 0)
        tangent = directions[:, 1]
        @test abs(tangent[3]) < 0.1
    end
end

# ─── project_to_valley tests ────────────────────────────────────────────────

@testset "project_to_valley" begin
    @testset "projects near-circle point back to circle" begin
        # Start slightly off the unit circle
        point = [1.05, 0.0]
        projected = project_to_valley(f_circle, point)
        # Should project to ∇f = 0, which for f_circle is the unit circle
        @test norm(ForwardDiff.gradient(f_circle, projected)) < 1e-8
        # Point should be near the unit circle
        @test abs(norm(projected) - 1.0) < 1e-6
    end

    @testset "projects from inside circle" begin
        point = [0.9, 0.0]
        projected = project_to_valley(f_circle, point)
        @test norm(ForwardDiff.gradient(f_circle, projected)) < 1e-8
        @test abs(norm(projected) - 1.0) < 1e-6
    end

    @testset "identity on exact valley point" begin
        point = [1.0, 0.0]
        projected = project_to_valley(f_circle, point)
        @test norm(projected - point) < 1e-8
    end

    @testset "handles offset valley (f_min > 0)" begin
        # This is the key test for the f(x)→0 vs ∇f(x)→0 fix.
        # f_offset_valley has minimum value 0.01 on the circle, never reaches 0.
        # Old code (project to f=0) would diverge or fail.
        # New code (project to ∇f=0) should find the circle.
        point = [1.1, 0.0]
        projected = project_to_valley(f_offset_valley, point)
        @test norm(ForwardDiff.gradient(f_offset_valley, projected)) < 1e-8
        @test abs(norm(projected) - 1.0) < 1e-6
    end

    @testset "projects in 3D" begin
        point = [1.05, 0.0, 0.02]
        projected = project_to_valley(f_circle3d, point)
        @test norm(ForwardDiff.gradient(f_circle3d, projected)) < 1e-8
        @test abs(norm(projected[1:2]) - 1.0) < 1e-6
        @test abs(projected[3]) < 1e-6
    end
end

# ─── get_valley_tangent tests ────────────────────────────────────────────────

@testset "get_valley_tangent" begin
    config = ValleyWalkConfig(eigenvalue_threshold=1e-2)

    @testset "tangent at (1,0) is along y-axis" begin
        point = [1.0, 0.0]
        prev_dir = [0.0, 1.0]
        tangent = get_valley_tangent(f_circle, point, prev_dir, config)
        @test tangent !== nothing
        @test norm(tangent) ≈ 1.0  # unit vector
        @test abs(tangent[1]) < 0.1
        @test tangent[2] > 0.9  # same sign as prev_dir
    end

    @testset "tangent maintains direction continuity" begin
        point = [1.0, 0.0]
        # Request positive y direction
        tangent_pos = get_valley_tangent(f_circle, point, [0.0, 1.0], config)
        # Request negative y direction
        tangent_neg = get_valley_tangent(f_circle, point, [0.0, -1.0], config)
        @test tangent_pos !== nothing
        @test tangent_neg !== nothing
        # Should flip sign to match prev_dir
        @test tangent_pos[2] > 0
        @test tangent_neg[2] < 0
    end

    @testset "returns nothing for non-valley point" begin
        point = [0.0, 0.0]  # origin of f_quadratic: no zero eigenvalues
        prev_dir = [1.0, 0.0]
        tangent = get_valley_tangent(f_quadratic, point, prev_dir, config)
        @test tangent === nothing
    end
end

# ─── walk_newton_projection tests ────────────────────────────────────────────

@testset "walk_newton_projection" begin
    config = ValleyWalkConfig(
        gradient_tolerance=1e-4,
        eigenvalue_threshold=1e-2,
        initial_step_size=0.05,
        max_steps=100,
        max_projection_iter=20,
        projection_tol=1e-10,
        method=:newton_projection
    )

    @testset "traces arc on unit circle" begin
        start = [1.0, 0.0]
        direction = [0.0, 1.0]  # walk counterclockwise
        path = walk_newton_projection(f_circle, start, direction, config)

        @test length(path) > 5  # should take multiple steps
        # All points should lie on the unit circle
        for p in path
            @test abs(norm(p) - 1.0) < 1e-4
        end
        # Should have moved away from start
        @test norm(path[end] - start) > 0.1
    end

    @testset "all path points are critical" begin
        start = [1.0, 0.0]
        direction = [0.0, 1.0]
        path = walk_newton_projection(f_circle, start, direction, config)

        for p in path
            g = ForwardDiff.gradient(f_circle, p)
            @test norm(g) < 1e-4
        end
    end
end

# ─── walk_predictor_corrector tests ──────────────────────────────────────────

@testset "walk_predictor_corrector" begin
    config = ValleyWalkConfig(
        gradient_tolerance=1e-4,
        eigenvalue_threshold=1e-2,
        initial_step_size=0.05,
        max_steps=100,
        max_projection_iter=20,
        projection_tol=1e-10,
        method=:predictor_corrector
    )

    @testset "traces arc on unit circle" begin
        start = [1.0, 0.0]
        direction = [0.0, 1.0]
        path = walk_predictor_corrector(f_circle, start, direction, config)

        @test length(path) > 5
        for p in path
            @test abs(norm(p) - 1.0) < 1e-4
        end
        @test norm(path[end] - start) > 0.1
    end
end

# ─── trace_valley tests ─────────────────────────────────────────────────────

@testset "trace_valley" begin
    config = ValleyWalkConfig(
        gradient_tolerance=1e-4,
        eigenvalue_threshold=1e-2,
        initial_step_size=0.05,
        max_steps=50,
        max_projection_iter=20,
        projection_tol=1e-10
    )

    @testset "bidirectional trace on unit circle" begin
        start = [1.0, 0.0]
        result = trace_valley(f_circle, start, config)

        @test result isa ValleyTraceResult
        @test result.converged == true
        @test result.start_point ≈ start
        @test length(result.path_positive) > 3
        @test length(result.path_negative) > 3
        @test result.arc_length > 0.1
        @test result.n_points == length(result.path_positive) + length(result.path_negative)
        @test result.valley_dimension == 1

        # Both paths should stay on the circle
        for p in result.path_positive
            @test abs(norm(p) - 1.0) < 1e-4
        end
        for p in result.path_negative
            @test abs(norm(p) - 1.0) < 1e-4
        end
    end

    @testset "returns non-converged for isolated minimum" begin
        start = [0.0, 0.0]
        result = trace_valley(f_quadratic, start, config)

        @test result.converged == false
        @test result.arc_length == 0.0
        @test result.n_points == 1
        @test result.valley_dimension == 0
    end

    @testset "predictor_corrector method" begin
        config_pc = ValleyWalkConfig(
            gradient_tolerance=1e-4,
            eigenvalue_threshold=1e-2,
            initial_step_size=0.05,
            max_steps=50,
            max_projection_iter=20,
            projection_tol=1e-10,
            method=:predictor_corrector
        )
        start = [1.0, 0.0]
        result = trace_valley(f_circle, start, config_pc)

        @test result.converged == true
        @test result.method == :predictor_corrector
        @test result.valley_dimension == 1
        @test result.arc_length > 0.1
    end

    @testset "3D circle valley" begin
        start = [1.0, 0.0, 0.0]
        result = trace_valley(f_circle3d, start, config)

        @test result.converged == true
        @test result.valley_dimension == 1
        # All points should be on the circle in the x₁-x₂ plane
        for p in [result.path_positive; result.path_negative]
            @test abs(norm(p[1:2]) - 1.0) < 1e-3
            @test abs(p[3]) < 1e-3
        end
    end
end

# ─── trace_valleys_from_critical_points tests ────────────────────────────────

@testset "trace_valleys_from_critical_points" begin
    config = ValleyWalkConfig(
        gradient_tolerance=1e-4,
        eigenvalue_threshold=1e-2,
        initial_step_size=0.05,
        max_steps=20,
        max_projection_iter=20,
        projection_tol=1e-10
    )

    @testset "traces from DataFrame with valley and non-valley points" begin
        df = DataFrame(
            x1 = [1.0, 0.0, 0.0],   # circle point, origin of quadratic, origin of saddle
            x2 = [0.0, 0.0, 0.0]
        )
        # Only the first point is on the circle valley — use f_circle for all
        # Origin of f_circle is NOT a valley point (gradient is zero but
        # eigenvalues are both 0 — actually it IS degenerate at origin for f_circle)
        # Let's use a mix: one point on circle, one far off
        df2 = DataFrame(
            x1 = [1.0,  0.5],
            x2 = [0.0,  0.0]
        )
        results = trace_valleys_from_critical_points(f_circle, df2, config)
        # Only (1,0) is a valley point; (0.5, 0) is not critical
        @test length(results) >= 1
        @test results[1].converged == true
    end

    @testset "errors on missing coordinate columns" begin
        df = DataFrame(a=[1.0], b=[2.0])
        @test_throws ErrorException trace_valleys_from_critical_points(f_circle, df, config)
    end
end

# ─── ValleyWalkConfig tests ─────────────────────────────────────────────────

@testset "ValleyWalkConfig" begin
    @testset "default values" begin
        config = ValleyWalkConfig()
        @test config.gradient_tolerance == 1e-4
        @test config.eigenvalue_threshold == 1e-3
        @test config.initial_step_size == 0.05
        @test config.max_steps == 200
        @test config.max_projection_iter == 10
        @test config.projection_tol == 1e-10
        @test config.method == :newton_projection
    end

    @testset "custom values" begin
        config = ValleyWalkConfig(
            gradient_tolerance=1e-6,
            eigenvalue_threshold=1e-5,
            initial_step_size=0.1,
            max_steps=500,
            method=:predictor_corrector
        )
        @test config.gradient_tolerance == 1e-6
        @test config.eigenvalue_threshold == 1e-5
        @test config.initial_step_size == 0.1
        @test config.max_steps == 500
        @test config.method == :predictor_corrector
    end
end

# ─── ValleyTraceResult tests ────────────────────────────────────────────────

@testset "ValleyTraceResult" begin
    @testset "construction" begin
        result = ValleyTraceResult(
            [1.0, 0.0],
            [[1.0, 0.0], [0.9, 0.1]],
            [[1.0, 0.0], [0.9, -0.1]],
            0.5,
            4,
            1,
            :newton_projection,
            true
        )
        @test result.start_point == [1.0, 0.0]
        @test result.converged == true
        @test result.valley_dimension == 1
        @test result.n_points == 4
        @test result.arc_length == 0.5
    end
end

# ─── run_valley_analysis integration tests ──────────────────────────────────

@testset "run_valley_analysis" begin
    @testset "traces valleys from degenerate CPs" begin
        # Create mock CriticalPointRefinementResult entries:
        # - CP at (1,0) on the unit circle of f_circle: degenerate (one zero eigenvalue)
        # - CP at (0,0) of f_quadratic: min (no zero eigenvalues)
        degenerate_cp = CriticalPointRefinementResult(
            [1.0, 0.0],     # point
            0.0,              # gradient_norm
            0.0,              # objective_value
            true,             # converged
            5,                # iterations
            :degenerate,      # cp_type
            [0.0, 8.0],       # eigenvalues (one near-zero)
            1.0               # initial_gradient_norm
        )
        min_cp = CriticalPointRefinementResult(
            [0.0, 0.0],     # point
            0.0,
            0.0,
            true,
            3,
            :min,
            [2.0, 2.0],
            0.5
        )

        results = run_valley_analysis(f_circle, [min_cp, degenerate_cp])
        @test length(results) == 1  # only the degenerate CP produces a valley trace
        @test results[1].converged == true
        @test results[1].valley_dimension == 1
        @test results[1].arc_length > 0.0
    end

    @testset "handles no degenerate CPs" begin
        min_cp = CriticalPointRefinementResult(
            [0.0, 0.0], 0.0, 0.0, true, 3, :min, [2.0, 2.0], 0.5
        )
        saddle_cp = CriticalPointRefinementResult(
            [0.0, 0.0], 0.0, 0.0, true, 3, :saddle, [2.0, -2.0], 0.5
        )

        results = run_valley_analysis(f_circle, [min_cp, saddle_cp])
        @test isempty(results)
    end

    @testset "handles empty refinement results" begin
        results = run_valley_analysis(f_circle, CriticalPointRefinementResult[])
        @test isempty(results)
    end
end
