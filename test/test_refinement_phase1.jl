# Test Phase 1 Refinement API with simple functions
# No dependency on Globtim - tests refinement in isolation

using Test
using GlobtimPostProcessing
using Optim  # Need Optim for type checks

@testset "Phase 1 Refinement - Simple Functions" begin
    @testset "Exports" begin
        # Configuration
        @test isdefined(GlobtimPostProcessing, :RefinementConfig)
        @test isdefined(GlobtimPostProcessing, :ode_refinement_config)

        # High-level API
        @test isdefined(GlobtimPostProcessing, :refine_experiment_results)
        @test isdefined(GlobtimPostProcessing, :refine_critical_points)

        # Core functions
        @test isdefined(GlobtimPostProcessing, :refine_critical_point)
        @test isdefined(GlobtimPostProcessing, :refine_critical_points_batch)

        # Data structures
        @test isdefined(GlobtimPostProcessing, :RefinedExperimentResult)
        @test isdefined(GlobtimPostProcessing, :RefinementResult)
        @test isdefined(GlobtimPostProcessing, :RawCriticalPointsData)

        # I/O utilities
        @test isdefined(GlobtimPostProcessing, :load_raw_critical_points)
        @test isdefined(GlobtimPostProcessing, :save_refined_results)
    end

    @testset "RefinementConfig" begin
        # Default config
        config = RefinementConfig()
        @test config.method isa Optim.NelderMead
        @test config.f_abstol == 1e-6
        @test config.x_abstol == 1e-6
        @test config.max_iterations == 300  # Actual default
        @test config.max_time_per_point == 30.0  # Actual default
        @test config.robust_mode == true  # Actual default
        @test config.show_progress == true  # Actual field name
        @test config.parallel == false

        # Custom config
        custom = RefinementConfig(
            method = Optim.BFGS(),
            f_abstol = 1e-8,
            max_iterations = 500,
            robust_mode = false
        )
        @test custom.method isa Optim.BFGS
        @test custom.f_abstol == 1e-8
        @test custom.max_iterations == 500
        @test custom.robust_mode == false
    end

    @testset "ODE Config Preset" begin
        ode_config = ode_refinement_config()
        @test ode_config.method isa Optim.NelderMead
        @test ode_config.max_time_per_point == 60.0  # ODE preset uses 60s
        @test ode_config.robust_mode == true
        @test ode_config.f_abstol == 1e-6

        # Custom timeout
        custom_ode = ode_refinement_config(max_time_per_point = 30.0)
        @test custom_ode.max_time_per_point == 30.0
    end

    @testset "Simple Quadratic Refinement" begin
        # Simple quadratic: f(p) = sum(p.^2)
        # Minimum at [0, 0] with value 0
        function simple_quadratic(p::Vector{Float64})
            return sum(p.^2)
        end

        # Start from [1.0, 1.0] (value = 2.0)
        result = refine_critical_point(
            simple_quadratic,
            [1.0, 1.0];
            max_iterations = 100
        )

        @test result.converged
        @test result.value_refined < result.value_raw
        @test result.value_raw ≈ 2.0
        @test result.value_refined < 1e-6  # Should be very close to 0
        @test all(abs.(result.refined) .< 1e-3)  # Field is 'refined' not 'point_refined'
        @test result.iterations > 0  # Field is 'iterations' not 'n_iterations'
        @test result.improvement > 0  # Check improvement field exists
    end

    @testset "Rosenbrock Function Refinement" begin
        # Rosenbrock: f(x,y) = (a-x)^2 + b(y-x^2)^2
        # Minimum at [1, 1] with value 0
        function rosenbrock(p::Vector{Float64})
            a, b = 1.0, 100.0
            x, y = p[1], p[2]
            return (a - x)^2 + b * (y - x^2)^2
        end

        # Start near minimum
        result = refine_critical_point(
            rosenbrock,
            [0.9, 0.8];
            max_iterations = 1000
        )

        @test result.converged
        @test result.value_refined < result.value_raw
        @test result.refined[1] ≈ 1.0 atol=1e-3
        @test result.refined[2] ≈ 1.0 atol=1e-3
        @test result.value_refined < 1e-6
    end

    @testset "Batch Refinement" begin
        function sphere(p::Vector{Float64})
            return sum(p.^2)
        end

        # Multiple starting points
        raw_points = [
            [1.0, 0.0],
            [0.0, 1.0],
            [1.0, 1.0],
            [2.0, 2.0]
        ]

        results = refine_critical_points_batch(
            sphere,
            raw_points;
            max_iterations = 100,
            show_progress = false
        )

        @test length(results) == 4
        @test all(r.converged for r in results)
        @test all(r.value_refined < 1e-6 for r in results)
        @test all(all(abs.(r.refined) .< 1e-3) for r in results)
    end

    @testset "Timeout Handling" begin
        # Very slow function (sleep-based)
        function slow_function(p::Vector{Float64})
            sleep(0.1)  # 100ms per evaluation
            return sum(p.^2)
        end

        # Should timeout after 0.2 seconds
        # Note: keyword is 'max_time' not 'max_time_per_point'
        result = refine_critical_point(
            slow_function,
            [1.0, 1.0];
            max_time = 0.2,
            max_iterations = 1000
        )

        # Should timeout before reaching 1000 iterations
        @test result.timed_out || result.iterations < 100
    end

    @testset "RefinementResult Structure" begin
        function simple(p::Vector{Float64})
            return sum(p.^2)
        end

        result = refine_critical_point(simple, [1.0, 1.0])

        # Check all fields exist (actual field names)
        @test hasfield(typeof(result), :refined)
        @test hasfield(typeof(result), :value_raw)
        @test hasfield(typeof(result), :value_refined)
        @test hasfield(typeof(result), :converged)
        @test hasfield(typeof(result), :iterations)
        @test hasfield(typeof(result), :improvement)
        @test hasfield(typeof(result), :timed_out)
        @test hasfield(typeof(result), :error_message)

        # Check types
        @test result.refined isa Vector{Float64}
        @test result.value_raw isa Float64
        @test result.value_refined isa Float64
        @test result.converged isa Bool
        @test result.iterations isa Int
        @test result.improvement isa Float64
        @test result.timed_out isa Bool
        @test result.error_message === nothing || result.error_message isa String
    end

    @testset "Phase 2: Tier 1 Diagnostics" begin
        @testset "Diagnostic Fields Exist" begin
            function simple(p::Vector{Float64})
                return sum(p.^2)
            end

            result = refine_critical_point(simple, [1.0, 1.0])

            # Check Tier 1 diagnostic fields exist
            @test hasfield(typeof(result), :f_calls)
            @test hasfield(typeof(result), :g_calls)
            @test hasfield(typeof(result), :h_calls)
            @test hasfield(typeof(result), :time_elapsed)
            @test hasfield(typeof(result), :x_converged)
            @test hasfield(typeof(result), :f_converged)
            @test hasfield(typeof(result), :g_converged)
            @test hasfield(typeof(result), :iteration_limit_reached)
            @test hasfield(typeof(result), :convergence_reason)

            # Check types
            @test result.f_calls isa Int
            @test result.g_calls isa Int
            @test result.h_calls isa Int
            @test result.time_elapsed isa Float64
            @test result.x_converged isa Bool
            @test result.f_converged isa Bool
            @test result.g_converged isa Bool
            @test result.iteration_limit_reached isa Bool
            @test result.convergence_reason isa Symbol
        end

        @testset "Call Counts Populated" begin
            function sphere(p::Vector{Float64})
                return sum(p.^2)
            end

            result = refine_critical_point(sphere, [1.0, 1.0])

            @test result.f_calls > 0  # Should have evaluated function
            @test result.g_calls >= 0  # NelderMead doesn't use gradients
            @test result.h_calls >= 0  # Hessian typically not used
        end

        @testset "Timing Information" begin
            function simple(p::Vector{Float64})
                return sum(p.^2)
            end

            result = refine_critical_point(simple, [1.0, 1.0])

            @test result.time_elapsed >= 0.0
            @test result.time_elapsed < 10.0  # Should be fast for simple function
        end

        @testset "Fine-Grained Convergence Flags" begin
            function quadratic(p::Vector{Float64})
                return sum(p.^2)
            end

            result = refine_critical_point(quadratic, [1.0, 1.0])

            # At least one convergence criterion should be met if converged
            if result.converged
                @test result.x_converged || result.f_converged || result.g_converged
            end

            # Iteration limit should be false if converged normally
            if result.converged && !result.timed_out
                @test result.iteration_limit_reached == false
            end
        end

        @testset "Convergence Reason Logic" begin
            function simple(p::Vector{Float64})
                return sum(p.^2)
            end

            result = refine_critical_point(simple, [1.0, 1.0])

            # Convergence reason should be one of the valid symbols
            valid_reasons = [:x_tol, :f_tol, :g_tol, :iterations, :timeout, :error, :unknown]
            @test result.convergence_reason in valid_reasons

            # If converged, reason should not be :error or :iterations
            if result.converged
                @test result.convergence_reason in [:x_tol, :f_tol, :g_tol, :unknown]
            end

            # If timed out, reason should be :timeout
            if result.timed_out
                @test result.convergence_reason == :timeout
            end

            # If hit iteration limit, reason should be :iterations
            if result.iteration_limit_reached && !result.converged
                @test result.convergence_reason == :iterations
            end
        end

        @testset "Timeout Convergence Reason" begin
            function slow(p::Vector{Float64})
                sleep(0.05)
                return sum(p.^2)
            end

            result = refine_critical_point(
                slow,
                [1.0, 1.0];
                max_time = 0.1
            )

            # If timed out, convergence reason should be :timeout
            if result.timed_out
                @test result.convergence_reason == :timeout
            end
        end

        @testset "Error Case Diagnostics" begin
            # Non-finite initial value
            function bad_func(p::Vector{Float64})
                return NaN
            end

            result = refine_critical_point(bad_func, [1.0, 1.0])

            @test !result.converged
            @test result.convergence_reason == :error
            @test result.f_calls >= 1  # At least initial evaluation
            @test result.error_message !== nothing
        end

        @testset "Batch Refinement Diagnostics" begin
            function sphere(p::Vector{Float64})
                return sum(p.^2)
            end

            points = [[1.0, 0.0], [0.0, 1.0], [1.0, 1.0]]
            results = refine_critical_points_batch(
                sphere,
                points;
                show_progress = false
            )

            # All results should have diagnostics
            @test all(r -> r.f_calls > 0, results)
            @test all(r -> r.time_elapsed >= 0.0, results)
            @test all(r -> r.convergence_reason in [:x_tol, :f_tol, :g_tol, :iterations, :timeout, :error, :unknown], results)

            # All should converge for simple sphere
            @test all(r -> r.converged, results)
        end
    end

    @testset "Phase 3: Box-Constrained Optimization" begin
        @testset "RefinementConfig Bounds Fields" begin
            # Default config has no bounds
            config = RefinementConfig()
            @test config.bounds === nothing

            # Config with bounds
            b = [(-1.0, 1.0), (-1.0, 1.0)]
            bounded_config = RefinementConfig(bounds=b)
            @test bounded_config.bounds == b
        end

        @testset "Initial Point Clamping" begin
            # Objective with minimum at [0, 0]
            function sphere(p::Vector{Float64})
                return sum(p.^2)
            end

            # Start OUTSIDE bounds [-1, 1]^2
            initial_outside = [2.0, 3.0]
            b = [(-1.0, 1.0), (-1.0, 1.0)]

            result = refine_critical_point(
                sphere,
                initial_outside;
                bounds=b,
                max_iterations=100
            )

            # Initial should have been clamped: raw_value = sphere([1,1]) = 2.0
            @test result.value_raw ≈ 2.0 atol=1e-10  # clamp([2,3], -1, 1) = [1,1]
            @test result.converged
        end

        @testset "Refined Points Stay Within Bounds" begin
            function sphere(p::Vector{Float64})
                return sum(p.^2)
            end

            b = [(-1.0, 1.0), (-1.0, 1.0)]
            lb = lower_bounds(b)
            ub = upper_bounds(b)

            # Multiple starting points, some inside, some outside bounds
            test_cases = [
                [0.5, 0.5],    # Inside bounds
                [1.5, 1.5],    # Outside bounds (will be clamped)
                [-2.0, 0.0],   # Partially outside
                [0.0, 3.0],    # Partially outside
            ]

            for initial in test_cases
                result = refine_critical_point(
                    sphere,
                    initial;
                    bounds=b,
                    max_iterations=200
                )

                # Refined point must be within bounds
                @test all(result.refined .>= lb)
                @test all(result.refined .<= ub)
            end
        end

        @testset "Bounded vs Unbounded Behavior" begin
            # Objective with minimum OUTSIDE typical bounds at [2, 2]
            function offset_sphere(p::Vector{Float64})
                return (p[1] - 2.0)^2 + (p[2] - 2.0)^2
            end

            initial = [1.0, 1.0]
            b = [(-1.0, 1.0), (-1.0, 1.0)]
            ub = upper_bounds(b)

            # Unbounded: should find true minimum at [2, 2]
            result_unbounded = refine_critical_point(
                offset_sphere,
                initial;
                max_iterations=200
            )
            @test result_unbounded.refined[1] ≈ 2.0 atol=0.1
            @test result_unbounded.refined[2] ≈ 2.0 atol=0.1

            # Bounded: should stay near bound [1, 1]
            # Note: Fminbox moves boundary points inward, so we use looser tolerance
            result_bounded = refine_critical_point(
                offset_sphere,
                initial;
                bounds=b,
                max_iterations=200
            )
            @test all(result_bounded.refined .<= ub)
            @test result_bounded.refined[1] ≈ 1.0 atol=0.05
            @test result_bounded.refined[2] ≈ 1.0 atol=0.05
        end

        @testset "Batch Refinement With Bounds" begin
            function sphere(p::Vector{Float64})
                return sum(p.^2)
            end

            b = [(-0.5, 0.5), (-0.5, 0.5)]
            lb = lower_bounds(b)
            ub = upper_bounds(b)

            # Some points inside, some outside bounds
            points = [
                [0.3, 0.3],    # Inside
                [1.0, 1.0],    # Outside (will be clamped to [0.5, 0.5])
                [-0.2, 0.4],   # Inside
                [-1.0, 2.0],   # Outside (will be clamped to [-0.5, 0.5])
            ]

            results = refine_critical_points_batch(
                sphere,
                points;
                bounds=b,
                max_iterations=100,
                show_progress=false
            )

            @test length(results) == 4
            @test all(r -> all(r.refined .>= lb), results)
            @test all(r -> all(r.refined .<= ub), results)
            @test all(r -> r.converged, results)
        end

        @testset "Asymmetric Bounds" begin
            function sphere(p::Vector{Float64})
                return sum(p.^2)
            end

            # Asymmetric bounds: minimum at origin is within bounds
            b = [(-2.0, 0.5), (-0.5, 2.0)]
            lb = lower_bounds(b)
            ub = upper_bounds(b)

            result = refine_critical_point(
                sphere,
                [0.3, 0.3];
                bounds=b,
                max_iterations=100
            )

            @test result.converged
            @test all(result.refined .>= lb)
            @test all(result.refined .<= ub)
            @test result.value_refined < 1e-4  # Should reach near-zero
        end

        @testset "Higher Dimensions (4D)" begin
            function sphere_4d(p::Vector{Float64})
                return sum(p.^2)
            end

            b = [(-1.0, 1.0), (-1.0, 1.0), (-1.0, 1.0), (-1.0, 1.0)]
            lb = lower_bounds(b)
            ub = upper_bounds(b)

            # Start outside in some dimensions
            initial = [0.5, 1.5, -0.5, 2.0]

            result = refine_critical_point(
                sphere_4d,
                initial;
                bounds=b,
                max_iterations=200
            )

            @test length(result.refined) == 4
            @test all(result.refined .>= lb)
            @test all(result.refined .<= ub)
            @test result.converged
        end
    end
end

using LinearAlgebra
using Statistics
using CSV
using DataFrames

# Load the Deuflhard 4D fixture objective
fixtures_dir = joinpath(@__DIR__, "fixtures")
include(joinpath(fixtures_dir, "test_functions.jl"))

@testset "Raw Critical Point Gradient Validation" begin
    @testset "compute_gradient_norms on simple functions" begin
        # Quadratic: f(x) = (x1-1)^2 + (x2-2)^2
        # True critical point: [1, 2], gradient = 0 there
        f_quad(x) = (x[1] - 1.0)^2 + (x[2] - 2.0)^2

        # Exact critical point should have ~zero gradient norm
        norms = compute_gradient_norms([[1.0, 2.0]], f_quad)
        @test length(norms) == 1
        @test norms[1] < 1e-12

        # Points away from critical point should have nonzero gradient
        norms = compute_gradient_norms([[1.0, 2.0], [1.1, 2.1], [0.0, 0.0]], f_quad)
        @test norms[1] < 1e-12
        @test norms[2] > 0.1
        @test norms[3] > 1.0
    end

    @testset "compute_gradient_norms with FiniteDiff" begin
        f_quad(x) = (x[1] - 1.0)^2 + (x[2] - 2.0)^2

        norms = compute_gradient_norms([[1.0, 2.0]], f_quad; gradient_method=:finitediff)
        @test length(norms) == 1
        @test norms[1] < 1e-6  # FiniteDiff less precise than ForwardDiff
    end

    @testset "Raw gradient norms on Deuflhard 4D fixture (degree 6)" begin
        # Load raw critical points from fixture CSV
        csv_path = joinpath(fixtures_dir, "critical_points_raw_deg_6.csv")
        df = CSV.read(csv_path, DataFrame)
        @test nrow(df) == 289

        # Extract points as Vector{Vector{Float64}}
        points = [Vector{Float64}([row.p1, row.p2, row.p3, row.p4]) for row in eachrow(df)]
        @test length(points) == 289

        # Compute gradient norms of the ORIGINAL objective at raw critical points
        norms = compute_gradient_norms(points, deuflhard_4d_fixture)

        # All gradient computations should succeed (Deuflhard is smooth)
        @test all(isfinite, norms)

        # Statistics should be computable
        @test minimum(norms) >= 0.0
        @test mean(norms) >= minimum(norms)
        @test maximum(norms) >= mean(norms)

        # At least some raw critical points should be near true critical points of f
        # (the polynomial approximation at degree 6 should produce some good approximations)
        n_small = count(n -> n < 1.0, norms)
        @test n_small > 0  # At least some points have gradient norm < 1

        # Print statistics for diagnostic visibility
        sorted_norms = sort(norms)
        println("Raw ||∇f|| stats (Deuflhard 4D, deg 6, $(length(norms)) points):")
        println("  min=$(round(sorted_norms[1], sigdigits=3)), " *
                "median=$(round(sorted_norms[div(length(sorted_norms)+1, 2)], sigdigits=3)), " *
                "mean=$(round(mean(sorted_norms), sigdigits=3)), " *
                "max=$(round(sorted_norms[end], sigdigits=3))")
        println("  < 0.1: $(count(n -> n < 0.1, norms)), " *
                "< 1.0: $(count(n -> n < 1.0, norms)), " *
                "< 10.0: $(count(n -> n < 10.0, norms))")
    end

    @testset "Raw gradient norms on Deuflhard 4D fixture (degree 4)" begin
        csv_path = joinpath(fixtures_dir, "critical_points_raw_deg_4.csv")
        df = CSV.read(csv_path, DataFrame)
        @test nrow(df) == 81

        points = [Vector{Float64}([row.p1, row.p2, row.p3, row.p4]) for row in eachrow(df)]

        norms = compute_gradient_norms(points, deuflhard_4d_fixture)
        @test all(isfinite, norms)

        # Degree 4 is a coarser approximation, but should still have some reasonable points
        n_small = count(n -> n < 10.0, norms)
        @test n_small > 0

        sorted_norms = sort(norms)
        println("Raw ||∇f|| stats (Deuflhard 4D, deg 4, $(length(norms)) points):")
        println("  min=$(round(sorted_norms[1], sigdigits=3)), " *
                "median=$(round(sorted_norms[div(length(sorted_norms)+1, 2)], sigdigits=3)), " *
                "mean=$(round(mean(sorted_norms), sigdigits=3)), " *
                "max=$(round(sorted_norms[end], sigdigits=3))")
        println("  < 0.1: $(count(n -> n < 0.1, norms)), " *
                "< 1.0: $(count(n -> n < 1.0, norms)), " *
                "< 10.0: $(count(n -> n < 10.0, norms))")
    end

    @testset "Degree 6 vs Degree 4: both find near-critical points" begin
        # Both polynomial degrees should find points near true critical points of f
        # (minimum gradient norms near machine epsilon)
        csv4 = CSV.read(joinpath(fixtures_dir, "critical_points_raw_deg_4.csv"), DataFrame)
        csv6 = CSV.read(joinpath(fixtures_dir, "critical_points_raw_deg_6.csv"), DataFrame)

        pts4 = [Vector{Float64}([r.p1, r.p2, r.p3, r.p4]) for r in eachrow(csv4)]
        pts6 = [Vector{Float64}([r.p1, r.p2, r.p3, r.p4]) for r in eachrow(csv6)]

        norms4 = compute_gradient_norms(pts4, deuflhard_4d_fixture)
        norms6 = compute_gradient_norms(pts6, deuflhard_4d_fixture)

        # Both degrees should find at least one point very close to a true critical point
        # (gradient norm near machine epsilon)
        @test minimum(norms4) < 1e-10
        @test minimum(norms6) < 1e-10

        # Degree 6 should have more raw points (higher degree → more critical points of p)
        @test length(norms6) > length(norms4)

        println("Best raw ||∇f||: deg 4 = $(round(minimum(norms4), sigdigits=3)), " *
                "deg 6 = $(round(minimum(norms6), sigdigits=3))")
    end

    @testset "print_refinement_summary with raw gradient norms" begin
        # Verify the updated print_refinement_summary accepts raw_gradient_norms
        # Create a minimal RefinedExperimentResult for testing
        f_quad(x) = sum(x.^2)
        raw_pts = [[0.1, 0.2], [0.3, 0.4]]
        config = RefinementConfig()

        result = RefinedExperimentResult(
            raw_pts,                    # raw_points
            [[0.01, 0.02]],             # refined_points
            [f_quad(p) for p in raw_pts], # raw_values
            [f_quad([0.01, 0.02])],     # refined_values
            [0.04],                     # improvements
            [true, false],              # convergence_status
            [10, 5],                    # iterations
            2,                          # n_raw
            1,                          # n_converged
            1,                          # n_failed
            0,                          # n_timeout
            0.04,                       # mean_improvement
            0.04,                       # max_improvement
            1,                          # best_raw_idx
            1,                          # best_refined_idx
            f_quad(raw_pts[1]),          # best_raw_value
            f_quad([0.01, 0.02]),        # best_refined_value
            tempdir(),                  # output_dir
            6,                          # degree
            0.1,                        # total_time
            config                      # refinement_config
        )

        raw_norms = compute_gradient_norms(raw_pts, f_quad)
        @test length(raw_norms) == 2
        @test all(isfinite, raw_norms)

        # Should print without errors
        pipe = Pipe()
        redirect_stdout(pipe) do
            print_refinement_summary(result, nothing, raw_norms)
        end
        close(pipe.in)
        output = read(pipe.out, String)
        @test occursin("Raw ||∇f||", output)

        # Also test with raw_gradient_norms=nothing (backward compatibility)
        pipe2 = Pipe()
        redirect_stdout(pipe2) do
            print_refinement_summary(result, nothing)
        end
        close(pipe2.in)
        output2 = read(pipe2.out, String)
        @test !occursin("Raw ||∇f||", output2)
    end
end

println("✅ Phase 1, Phase 2 Tier 1, Phase 3 Box-Constrained, and Raw Gradient Validation tests passed!")
