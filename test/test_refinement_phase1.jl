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
end

println("✅ Phase 1 and Phase 2 Tier 1 refinement tests passed!")
