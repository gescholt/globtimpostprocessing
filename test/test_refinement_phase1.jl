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
end

println("✅ Phase 1 refinement tests passed!")
