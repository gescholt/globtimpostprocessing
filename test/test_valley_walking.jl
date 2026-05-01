"""
    test_valley_walking.jl

Tests for valley walking algorithm: detection of positive-dimensional minima
and predictor-corrector tracing along valley manifolds.

Test functions:
- f_circle(x) = (x₁² + x₂² - 1)²          — unit circle is a 1D valley of zeros in 2D
- f_quadratic(x) = x₁² + x₂²               — isolated minimum at origin (0D, NOT a valley)
- f_saddle(x) = x₁² - x₂²                  — saddle at origin (not a valley)
- f_circle3d(x) = (x₁² + x₂² - 1)² + x₃²  — circle valley embedded in 3D (x₃=0 plane)
- f_offset_valley(x) = (x₁² + x₂² - 1)² + 0.01  — valley with f_min > 0 (tests projection fix)
- f_hyperbola(x) = (x₁·x₂ - 2)²           — hyperbola valley {(a,b): a·b=2}; models
                                               product-form non-identifiability (ODE x'=a·b·x).
                                               Transverse curvature varies: λ_⊥=10 at (1,2),
                                               λ_⊥=32.5 at (0.5,4) — stresses adaptive step sizing.
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

# Product-form non-identifiability valley: hyperbola x₁·x₂ = 2.
# Models the ODE x'(t) = a·b·x(t) where only the product a·b is identifiable —
# any (a, b) on the hyperbola a·b = 2 reproduces identical trajectories.
# At (1,2): transverse eigenvalue λ_⊥ = 10.  At (0.5,4): λ_⊥ = 32.5.
# The increasing curvature toward the axes stresses adaptive step-size control.
f_hyperbola(x) = (x[1] * x[2] - 2.0)^2

# ─── detect_valley tests ────────────────────────────────────────────────────

@testset "detect_valley" begin
    config = ValleyWalkConfig(gradient_tolerance = 1e-4, eigenvalue_threshold = 1e-2)

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
    config = ValleyWalkConfig(eigenvalue_threshold = 1e-2)

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
        gradient_tolerance = 1e-4,
        eigenvalue_threshold = 1e-2,
        initial_step_size = 0.05,
        max_steps = 100,
        max_projection_iter = 20,
        projection_tol = 1e-10,
        method = :newton_projection,
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

# ─── project_to_valley_tangent tests ─────────────────────────────────────────

@testset "project_to_valley_tangent" begin
    @testset "projects near-circle point back to circle" begin
        # Start slightly off the unit circle at (1,0), tangent direction is +y
        point = [1.05, 0.0]
        tangent = [0.0, 1.0]
        projected = project_to_valley_tangent(f_circle, point, tangent)
        # Should land on the critical manifold (∇f = 0)
        @test norm(ForwardDiff.gradient(f_circle, projected)) < 1e-8
        # Should be near the unit circle
        @test abs(norm(projected) - 1.0) < 1e-6
    end

    @testset "preserves tangent-direction component" begin
        # Start at a point on the circle + offset in both tangent and normal directions
        # At (1,0), tangent is y-axis, normal is x-axis
        tangent = [0.0, 1.0]
        # Offset in y (tangent) by 0.1 and in x (normal) by 0.05
        point = [1.05, 0.1]
        projected = project_to_valley_tangent(f_circle, point, tangent)
        # The y-component (tangent direction) should be preserved
        @test abs(projected[2] - point[2]) < 1e-6
        # But the x-component should change to land on the circle
        @test abs(norm(projected) - 1.0) < 1e-4
    end

    @testset "less longitudinal drift than full Newton" begin
        # Start at a point offset from the circle
        tangent = [0.0, 1.0]  # tangent at (1,0)
        point = [1.05, 0.1]   # offset in both directions

        proj_full = project_to_valley(f_circle, point)
        proj_tang = project_to_valley_tangent(f_circle, point, tangent)

        # Both should reach the critical manifold
        @test norm(ForwardDiff.gradient(f_circle, proj_full)) < 1e-8
        @test norm(ForwardDiff.gradient(f_circle, proj_tang)) < 1e-8

        # Tangent projection should have less drift in the tangent direction
        drift_full = abs(proj_full[2] - point[2])
        drift_tang = abs(proj_tang[2] - point[2])
        @test drift_tang <= drift_full + 1e-10  # tangent preserves y-component
    end

    @testset "projects from inside circle" begin
        point = [0.9, 0.0]
        tangent = [0.0, 1.0]
        projected = project_to_valley_tangent(f_circle, point, tangent)
        @test norm(ForwardDiff.gradient(f_circle, projected)) < 1e-8
        @test abs(norm(projected) - 1.0) < 1e-6
    end

    @testset "identity on exact valley point" begin
        point = [1.0, 0.0]
        tangent = [0.0, 1.0]
        projected = project_to_valley_tangent(f_circle, point, tangent)
        @test norm(projected - point) < 1e-8
    end

    @testset "handles offset valley (f_min > 0)" begin
        point = [1.1, 0.0]
        tangent = [0.0, 1.0]
        projected = project_to_valley_tangent(f_offset_valley, point, tangent)
        @test norm(ForwardDiff.gradient(f_offset_valley, projected)) < 1e-8
        @test abs(norm(projected) - 1.0) < 1e-6
    end

    @testset "projects in 3D" begin
        point = [1.05, 0.0, 0.02]
        tangent = [0.0, 1.0, 0.0]  # tangent along y-axis in 3D
        projected = project_to_valley_tangent(f_circle3d, point, tangent)
        @test norm(ForwardDiff.gradient(f_circle3d, projected)) < 1e-8
        @test abs(norm(projected[1:2]) - 1.0) < 1e-6
        @test abs(projected[3]) < 1e-6
    end

    @testset "non-unit tangent is normalized internally" begin
        point = [1.05, 0.0]
        tangent = [0.0, 3.7]  # not unit length
        projected = project_to_valley_tangent(f_circle, point, tangent)
        @test norm(ForwardDiff.gradient(f_circle, projected)) < 1e-8
        @test abs(norm(projected) - 1.0) < 1e-6
    end
end

# ─── walk_predictor_corrector tests ──────────────────────────────────────────

@testset "walk_predictor_corrector" begin
    config = ValleyWalkConfig(
        gradient_tolerance = 1e-4,
        eigenvalue_threshold = 1e-2,
        initial_step_size = 0.05,
        max_steps = 100,
        max_projection_iter = 20,
        projection_tol = 1e-10,
        method = :predictor_corrector,
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

# ─── walk_tangent_projection tests ───────────────────────────────────────────

@testset "walk_tangent_projection" begin
    config = ValleyWalkConfig(
        gradient_tolerance = 1e-4,
        eigenvalue_threshold = 1e-2,
        initial_step_size = 0.05,
        max_steps = 100,
        max_projection_iter = 20,
        projection_tol = 1e-10,
        method = :tangent_projection,
    )

    @testset "traces arc on unit circle" begin
        start = [1.0, 0.0]
        direction = [0.0, 1.0]  # walk counterclockwise
        path = walk_tangent_projection(f_circle, start, direction, config)

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
        path = walk_tangent_projection(f_circle, start, direction, config)

        for p in path
            g = ForwardDiff.gradient(f_circle, p)
            @test norm(g) < 1e-4
        end
    end

    @testset "more uniform spacing than newton_projection" begin
        config_np = ValleyWalkConfig(
            gradient_tolerance = 1e-4,
            eigenvalue_threshold = 1e-2,
            initial_step_size = 0.05,
            max_steps = 100,
            max_projection_iter = 20,
            projection_tol = 1e-10,
            method = :newton_projection,
        )
        config_tp = ValleyWalkConfig(
            gradient_tolerance = 1e-4,
            eigenvalue_threshold = 1e-2,
            initial_step_size = 0.05,
            max_steps = 100,
            max_projection_iter = 20,
            projection_tol = 1e-10,
            method = :tangent_projection,
        )

        start = [1.0, 0.0]
        direction = [0.0, 1.0]

        path_np = walk_newton_projection(f_circle, start, direction, config_np)
        path_tp = walk_tangent_projection(f_circle, start, direction, config_tp)

        # Both should produce valid paths
        @test length(path_np) > 3
        @test length(path_tp) > 3

        # Compute spacing variance for each (coefficient of variation)
        function spacing_cv(path)
            spacings = [norm(path[i+1] - path[i]) for i in 1:(length(path)-1)]
            isempty(spacings) && return Inf
            μ = sum(spacings) / length(spacings)
            μ < 1e-12 && return Inf
            σ = sqrt(sum((s - μ)^2 for s in spacings) / length(spacings))
            return σ / μ
        end

        cv_np = spacing_cv(path_np)
        cv_tp = spacing_cv(path_tp)

        # Tangent projection should have comparable or better spacing uniformity
        # (We test that it's not dramatically worse — exact comparison depends on geometry)
        @test cv_tp < cv_np * 2.0  # at worst 2x the variance ratio
    end

    @testset "traces in 3D" begin
        start = [1.0, 0.0, 0.0]
        direction = [0.0, 1.0, 0.0]
        path = walk_tangent_projection(f_circle3d, start, direction, config)

        @test length(path) > 3
        for p in path
            @test abs(norm(p[1:2]) - 1.0) < 1e-3
            @test abs(p[3]) < 1e-3
        end
    end
end

# ─── trace_valley tests ─────────────────────────────────────────────────────

@testset "trace_valley" begin
    config = ValleyWalkConfig(
        gradient_tolerance = 1e-4,
        eigenvalue_threshold = 1e-2,
        initial_step_size = 0.05,
        max_steps = 50,
        max_projection_iter = 20,
        projection_tol = 1e-10,
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
            gradient_tolerance = 1e-4,
            eigenvalue_threshold = 1e-2,
            initial_step_size = 0.05,
            max_steps = 50,
            max_projection_iter = 20,
            projection_tol = 1e-10,
            method = :predictor_corrector,
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

    @testset "tangent_projection method" begin
        config_tp = ValleyWalkConfig(
            gradient_tolerance = 1e-4,
            eigenvalue_threshold = 1e-2,
            initial_step_size = 0.05,
            max_steps = 50,
            max_projection_iter = 20,
            projection_tol = 1e-10,
            method = :tangent_projection,
        )
        start = [1.0, 0.0]
        result = trace_valley(f_circle, start, config_tp)

        @test result.converged == true
        @test result.method == :tangent_projection
        @test result.valley_dimension == 1
        @test result.arc_length > 0.1
    end

    @testset "unknown method raises error" begin
        config_bad = ValleyWalkConfig(
            gradient_tolerance = 1e-4,
            eigenvalue_threshold = 1e-2,
            method = :bogus_method,
        )
        start = [1.0, 0.0]
        @test_throws ErrorException trace_valley(f_circle, start, config_bad)
    end
end

# ─── trace_valleys_from_critical_points tests ────────────────────────────────

@testset "trace_valleys_from_critical_points" begin
    config = ValleyWalkConfig(
        gradient_tolerance = 1e-4,
        eigenvalue_threshold = 1e-2,
        initial_step_size = 0.05,
        max_steps = 20,
        max_projection_iter = 20,
        projection_tol = 1e-10,
    )

    @testset "traces from DataFrame with valley and non-valley points" begin
        df = DataFrame(
            x1 = [1.0, 0.0, 0.0],   # circle point, origin of quadratic, origin of saddle
            x2 = [0.0, 0.0, 0.0],
        )
        # Only the first point is on the circle valley — use f_circle for all
        # Origin of f_circle is NOT a valley point (gradient is zero but
        # eigenvalues are both 0 — actually it IS degenerate at origin for f_circle)
        # Let's use a mix: one point on circle, one far off
        df2 = DataFrame(x1 = [1.0, 0.5], x2 = [0.0, 0.0])
        results = trace_valleys_from_critical_points(f_circle, df2, config)
        # Only (1,0) is a valley point; (0.5, 0) is not critical
        @test length(results) >= 1
        @test results[1].converged == true
    end

    @testset "errors on missing coordinate columns" begin
        df = DataFrame(a = [1.0], b = [2.0])
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
            gradient_tolerance = 1e-6,
            eigenvalue_threshold = 1e-5,
            initial_step_size = 0.1,
            max_steps = 500,
            method = :predictor_corrector,
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
            true,
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
            point = [1.0, 0.0],
            gradient_norm = 0.0,
            objective_value = 0.0,
            converged = true,
            iterations = 5,
            cp_type = :degenerate,
            eigenvalues = [0.0, 8.0],
            initial_gradient_norm = 1.0,
        )
        min_cp = CriticalPointRefinementResult(
            point = [0.0, 0.0],
            gradient_norm = 0.0,
            objective_value = 0.0,
            converged = true,
            iterations = 3,
            cp_type = :min,
            eigenvalues = [2.0, 2.0],
            initial_gradient_norm = 0.5,
        )

        results = run_valley_analysis(f_circle, [min_cp, degenerate_cp])
        @test length(results) == 1  # only the degenerate CP produces a valley trace
        @test results[1].converged == true
        @test results[1].valley_dimension == 1
        @test results[1].arc_length > 0.0
    end

    @testset "handles no degenerate CPs" begin
        min_cp = CriticalPointRefinementResult(
            point = [0.0, 0.0],
            gradient_norm = 0.0,
            objective_value = 0.0,
            converged = true,
            iterations = 3,
            cp_type = :min,
            eigenvalues = [2.0, 2.0],
            initial_gradient_norm = 0.5,
        )
        saddle_cp = CriticalPointRefinementResult(
            point = [0.0, 0.0],
            gradient_norm = 0.0,
            objective_value = 0.0,
            converged = true,
            iterations = 3,
            cp_type = :saddle,
            eigenvalues = [2.0, -2.0],
            initial_gradient_norm = 0.5,
        )

        results = run_valley_analysis(f_circle, [min_cp, saddle_cp])
        @test isempty(results)
    end

    @testset "handles empty refinement results" begin
        results = run_valley_analysis(f_circle, CriticalPointRefinementResult[])
        @test isempty(results)
    end
end

# ─── Hyperbola valley tests ──────────────────────────────────────────────────

@testset "hyperbola valley (product-form symmetry)" begin
    # f_hyperbola = (x₁·x₂ - 2)²: valley is the hyperbola x₁·x₂ = 2.
    # Eigenvalue structure at (a,b) on the valley:
    #   λ_tangent = 0,  λ_transverse = 2(a²+b²)
    # So transverse curvature increases as the path moves away from (1,2).

    config = ValleyWalkConfig(
        gradient_tolerance = 1e-4,
        eigenvalue_threshold = 1e-3,
        initial_step_size = 0.05,
        max_steps = 100,
        max_projection_iter = 20,
        projection_tol = 1e-10,
    )

    @testset "detect_valley finds 1D valley on hyperbola" begin
        # Both points lie on x₁·x₂ = 2 and should be detected as valleys
        is_v1, dirs1, vdim1 = detect_valley(f_hyperbola, [1.0, 2.0], config)
        @test is_v1 == true
        @test vdim1 == 1
        @test size(dirs1, 2) == 1

        is_v2, dirs2, vdim2 = detect_valley(f_hyperbola, [0.5, 4.0], config)
        @test is_v2 == true
        @test vdim2 == 1

        is_v3, dirs3, vdim3 = detect_valley(f_hyperbola, [2.0, 1.0], config)
        @test is_v3 == true
        @test vdim3 == 1
    end

    @testset "detect_valley rejects off-hyperbola points" begin
        # Origin: isolated minimum at f=4, not critical
        is_v, _, _ = detect_valley(f_hyperbola, [0.0, 0.0], config)
        @test is_v == false

        # Point near but not on the hyperbola: gradient is nonzero
        is_v2, _, _ = detect_valley(f_hyperbola, [1.5, 2.0], config)
        @test is_v2 == false
    end

    @testset "tangent direction at (1,2) is along hyperbola" begin
        # The tangent to x₁·x₂ = 2 at (1,2) via implicit differentiation:
        # d/dx(x·y) = 0 => y + x·dy/dx = 0 => dy/dx = -y/x = -2.
        # So the tangent direction is (1, -2)/√5, which is also the Hessian
        # null eigenvector at this point.
        prev = [1.0, -2.0] / sqrt(5)  # aligned with the null eigenvector
        t = get_valley_tangent(f_hyperbola, [1.0, 2.0], prev, config)
        @test !isnothing(t)
        @test abs(norm(t) - 1.0) < 1e-10  # unit vector
        expected = [1.0, -2.0] / sqrt(5)
        @test abs(dot(t, expected)) > 0.99  # collinear (up to sign)
    end

    @testset "project_to_valley lands on hyperbola" begin
        # Perturb a hyperbola point and project back
        p_near = [1.1, 2.0]  # x₁·x₂ = 2.2, not on valley
        @test abs(p_near[1] * p_near[2] - 2.0) > 0.1

        p_proj = project_to_valley(f_hyperbola, p_near)
        @test abs(p_proj[1] * p_proj[2] - 2.0) < 1e-6
        g = ForwardDiff.gradient(f_hyperbola, p_proj)
        @test norm(g) < 1e-6
    end

    @testset "project_to_valley_tangent preserves tangent component" begin
        p_near = [1.1, 2.0]
        tangent = [-2.0, 1.0] / sqrt(5)

        p_full = project_to_valley(f_hyperbola, p_near)
        p_tang = project_to_valley_tangent(f_hyperbola, p_near, tangent)

        # Both land on the valley
        @test abs(p_full[1] * p_full[2] - 2.0) < 1e-6
        @test abs(p_tang[1] * p_tang[2] - 2.0) < 1e-6

        # Tangent projection moves less along the tangent direction
        drift_full = abs(dot(p_full - p_near, tangent))
        drift_tang = abs(dot(p_tang - p_near, tangent))
        @test drift_tang <= drift_full + 1e-10
    end

    @testset "all three walk methods trace the hyperbola" begin
        methods = [:newton_projection, :predictor_corrector, :tangent_projection]
        for m in methods
            cfg = ValleyWalkConfig(;
                gradient_tolerance = 1e-4,
                eigenvalue_threshold = 1e-3,
                initial_step_size = 0.05,
                max_steps = 50,
                max_projection_iter = 20,
                projection_tol = 1e-10,
                method = m,
            )
            result = trace_valley(f_hyperbola, [1.0, 2.0], cfg)
            @test result.converged == true
            @test result.valley_dimension == 1
            @test result.arc_length > 0.5

            all_pts = vcat(result.path_positive, result.path_negative)
            for p in all_pts
                @test abs(p[1] * p[2] - 2.0) < 1e-4   # stays on hyperbola
                g = ForwardDiff.gradient(f_hyperbola, p)
                @test norm(g) < 1e-4                   # stays critical
            end
        end
    end
end

# ─── Quantitative method benchmark ───────────────────────────────────────────

@testset "quantitative method benchmark" begin
    # Compare all three methods on two test functions with different geometry:
    #   f_circle   — constant curvature (unit circle)
    #   f_hyperbola — varying curvature (hyperbola x₁·x₂ = 2)
    #
    # Metrics measured per (method, function) pair:
    #   arc_length        — total valley coverage
    #   n_points          — step count
    #   max_grad_norm     — max ‖∇f(p)‖ over all path points (criticality accuracy)
    #   max_manifold_err  — max distance from the manifold
    #   spacing_cv        — std(step_sizes)/mean(step_sizes) per direction (uniformity)
    #
    # All bounds are derived from measured values with conservative margins.

    using Statistics

    methods = [:newton_projection, :predictor_corrector, :tangent_projection]

    circle_config_base = (
        gradient_tolerance = 1e-4,
        eigenvalue_threshold = 1e-2,
        initial_step_size = 0.05,
        max_steps = 100,
        max_projection_iter = 20,
        projection_tol = 1e-10,
    )
    hyperbola_config_base = (
        gradient_tolerance = 1e-4,
        eigenvalue_threshold = 1e-3,
        initial_step_size = 0.05,
        max_steps = 100,
        max_projection_iter = 20,
        projection_tol = 1e-10,
    )

    function spacing_cv(path)
        spacings = [norm(path[i+1] - path[i]) for i in 1:(length(path)-1)]
        length(spacings) < 2 && return Inf
        μ = mean(spacings)
        μ < 1e-12 && return Inf
        return std(spacings) / μ
    end

    # ── Unit circle benchmark ────────────────────────────────────────────────
    @testset "unit circle" begin
        circle_results = Dict{Symbol,ValleyTraceResult}()
        for m in methods
            cfg = ValleyWalkConfig(; circle_config_base..., method = m)
            circle_results[m] = trace_valley(f_circle, [1.0, 0.0], cfg)
        end

        @testset "convergence and valley dimension" begin
            for m in methods
                r = circle_results[m]
                @test r.converged == true
                @test r.valley_dimension == 1
                @test r.method == m
            end
        end

        @testset "arc coverage" begin
            for m in methods
                r = circle_results[m]
                @test r.arc_length > 1.0   # at least ~1/6 of the circumference 2π
                @test r.n_points > 20
            end
        end

        @testset "criticality accuracy: max ‖∇f‖ < 1e-6" begin
            for m in methods
                for p in
                    vcat(circle_results[m].path_positive, circle_results[m].path_negative)
                    @test norm(ForwardDiff.gradient(f_circle, p)) < 1e-6
                end
            end
        end

        @testset "on-manifold accuracy: max |‖p‖-1| < 1e-6" begin
            for m in methods
                for p in
                    vcat(circle_results[m].path_positive, circle_results[m].path_negative)
                    @test abs(norm(p) - 1.0) < 1e-6
                end
            end
        end

        @testset "spacing uniformity: CV < 0.5 for all methods" begin
            for m in methods
                r = circle_results[m]
                @test spacing_cv(r.path_positive) < 0.5
                @test spacing_cv(r.path_negative) < 0.5
            end
        end

        @testset "predictor_corrector covers most arc (aggressive step growth)" begin
            # predictor_corrector grows step by 1.2× vs 1.1× for the others
            arc_pc = circle_results[:predictor_corrector].arc_length
            arc_np = circle_results[:newton_projection].arc_length
            arc_tp = circle_results[:tangent_projection].arc_length
            @test arc_pc >= arc_np
            @test arc_pc >= arc_tp
        end

        @testset "tangent_projection spacing no worse than 1.5× newton" begin
            cv_np = max(
                spacing_cv(circle_results[:newton_projection].path_positive),
                spacing_cv(circle_results[:newton_projection].path_negative),
            )
            cv_tp = max(
                spacing_cv(circle_results[:tangent_projection].path_positive),
                spacing_cv(circle_results[:tangent_projection].path_negative),
            )
            @test cv_tp < cv_np * 1.5
        end
    end

    # ── Hyperbola benchmark ──────────────────────────────────────────────────
    @testset "hyperbola (varying curvature)" begin
        hyperbola_results = Dict{Symbol,ValleyTraceResult}()
        for m in methods
            cfg = ValleyWalkConfig(; hyperbola_config_base..., method = m)
            hyperbola_results[m] = trace_valley(f_hyperbola, [1.0, 2.0], cfg)
        end

        @testset "convergence and valley dimension" begin
            for m in methods
                r = hyperbola_results[m]
                @test r.converged == true
                @test r.valley_dimension == 1
                @test r.method == m
            end
        end

        @testset "arc coverage" begin
            for m in methods
                r = hyperbola_results[m]
                @test r.arc_length > 1.0
                @test r.n_points > 20
            end
        end

        @testset "criticality accuracy: max ‖∇f‖ < 1e-6" begin
            for m in methods
                for p in vcat(
                    hyperbola_results[m].path_positive,
                    hyperbola_results[m].path_negative,
                )
                    @test norm(ForwardDiff.gradient(f_hyperbola, p)) < 1e-6
                end
            end
        end

        @testset "on-manifold accuracy: max |p₁p₂ - 2| < 1e-6" begin
            for m in methods
                for p in vcat(
                    hyperbola_results[m].path_positive,
                    hyperbola_results[m].path_negative,
                )
                    @test abs(p[1] * p[2] - 2.0) < 1e-6
                end
            end
        end

        @testset "spacing uniformity: CV < 0.5 for all methods" begin
            for m in methods
                r = hyperbola_results[m]
                @test spacing_cv(r.path_positive) < 0.5
                @test spacing_cv(r.path_negative) < 0.5
            end
        end

        @testset "predictor_corrector covers most arc (aggressive step growth)" begin
            arc_pc = hyperbola_results[:predictor_corrector].arc_length
            arc_np = hyperbola_results[:newton_projection].arc_length
            arc_tp = hyperbola_results[:tangent_projection].arc_length
            @test arc_pc >= arc_np
            @test arc_pc >= arc_tp
        end

        @testset "tangent_projection spacing no worse than 1.5× newton" begin
            cv_np = max(
                spacing_cv(hyperbola_results[:newton_projection].path_positive),
                spacing_cv(hyperbola_results[:newton_projection].path_negative),
            )
            cv_tp = max(
                spacing_cv(hyperbola_results[:tangent_projection].path_positive),
                spacing_cv(hyperbola_results[:tangent_projection].path_negative),
            )
            @test cv_tp < cv_np * 1.5
        end
    end
end

# ─── FiniteDiff gradient_method tests ────────────────────────────────────────
# ValleyWalking now supports gradient_method=:finitediff for ODE-based objectives
# that are not ForwardDiff-compatible. Verify it produces equivalent results on
# algebraic test functions where both methods work.

@testset "gradient_method=:finitediff" begin
    config_fd = ValleyWalkConfig(
        gradient_tolerance = 1e-4,
        eigenvalue_threshold = 1e-2,
        gradient_method = :forwarddiff,
    )
    config_nd = ValleyWalkConfig(
        gradient_tolerance = 1e-3,  # relaxed: FiniteDiff gradients are less precise
        eigenvalue_threshold = 1e-2,
        gradient_method = :finitediff,
    )

    @testset "detect_valley with FiniteDiff" begin
        # Unit circle — should detect valley with both methods
        point = [1.0, 0.0]
        is_v_fd, dirs_fd, vdim_fd = detect_valley(f_circle, point, config_fd)
        is_v_nd, dirs_nd, vdim_nd = detect_valley(f_circle, point, config_nd)
        @test is_v_fd == true
        @test is_v_nd == true
        @test vdim_fd == vdim_nd == 1

        # Tangent directions should agree (up to sign)
        dot_val = abs(dot(dirs_fd[:, 1], dirs_nd[:, 1]))
        @test dot_val > 0.99
    end

    @testset "project_to_valley with FiniteDiff" begin
        point = [1.05, 0.0]
        proj_fd = project_to_valley(f_circle, point; gradient_method = :forwarddiff)
        proj_nd = project_to_valley(f_circle, point; gradient_method = :finitediff)
        # Both should land on the unit circle
        @test abs(norm(proj_fd) - 1.0) < 1e-6
        @test abs(norm(proj_nd) - 1.0) < 1e-4  # relaxed for FiniteDiff
    end

    @testset "project_to_valley_tangent with FiniteDiff" begin
        point = [1.05, 0.0]
        tangent = [0.0, 1.0]
        proj_fd = project_to_valley_tangent(
            f_circle,
            point,
            tangent;
            gradient_method = :forwarddiff,
        )
        proj_nd = project_to_valley_tangent(
            f_circle,
            point,
            tangent;
            gradient_method = :finitediff,
        )
        @test abs(norm(proj_fd) - 1.0) < 1e-6
        @test abs(norm(proj_nd) - 1.0) < 1e-4
    end

    @testset "trace_valley with FiniteDiff" begin
        config_trace = ValleyWalkConfig(
            gradient_tolerance = 1e-3,
            eigenvalue_threshold = 1e-2,
            initial_step_size = 0.05,
            max_steps = 50,
            gradient_method = :finitediff,
        )
        result = trace_valley(f_circle, [1.0, 0.0], config_trace)
        @test result.converged == true
        @test result.valley_dimension == 1
        @test result.n_points > 10  # should trace a meaningful path

        # All traced points should lie on (or very near) the unit circle
        for p in vcat(result.path_positive, result.path_negative)
            @test abs(norm(p) - 1.0) < 1e-3  # relaxed for FiniteDiff
        end
    end

    @testset "invalid gradient_method raises error" begin
        bad_config = ValleyWalkConfig(gradient_method = :bogus)
        @test_throws ErrorException detect_valley(f_circle, [1.0, 0.0], bad_config)
    end
end
