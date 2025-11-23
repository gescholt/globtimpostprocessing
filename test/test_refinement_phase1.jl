# Test Phase 1 Refinement API with simple functions
# No dependency on Globtim - tests refinement in isolation

using Test
using GlobtimPostProcessing

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
        @test config.f_reltol == 1e-6
        @test config.max_iterations == 1000
        @test config.max_time_per_point === nothing
        @test config.robust_mode == false
        @test config.show_trace == false

        # Custom config
        custom = RefinementConfig(
            method = Optim.BFGS(),
            f_abstol = 1e-8,
            max_iterations = 500,
            robust_mode = true
        )
        @test custom.method isa Optim.BFGS
        @test custom.f_abstol == 1e-8
        @test custom.max_iterations == 500
        @test custom.robust_mode == true
    end

    @testset "ODE Config Preset" begin
        ode_config = ode_refinement_config()
        @test ode_config.method isa Optim.NelderMead
        @test ode_config.max_time_per_point == 60.0
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
        @test all(abs.(result.point_refined) .< 1e-3)  # Should be close to [0, 0]
        @test result.n_iterations > 0
        @test result.runtime_seconds >= 0
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
        @test result.point_refined[1] ≈ 1.0 atol=1e-3
        @test result.point_refined[2] ≈ 1.0 atol=1e-3
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
        @test all(all(abs.(r.point_refined) .< 1e-3) for r in results)
    end

    @testset "Timeout Handling" begin
        # Very slow function (sleep-based)
        function slow_function(p::Vector{Float64})
            sleep(0.1)  # 100ms per evaluation
            return sum(p.^2)
        end

        # Should timeout after 0.2 seconds
        result = refine_critical_point(
            slow_function,
            [1.0, 1.0];
            max_time_per_point = 0.2,
            max_iterations = 1000
        )

        # Should timeout before reaching 1000 iterations
        @test result.runtime_seconds < 0.5  # Some margin for timing
        @test result.timed_out || result.n_iterations < 100
    end

    @testset "Robust Mode" begin
        # Function that can fail
        function sometimes_fail(p::Vector{Float64})
            if any(p .< -10.0)
                error("Domain error: p too negative")
            end
            return sum(p.^2)
        end

        # Non-robust mode: should propagate error
        @test_throws ErrorException refine_critical_point(
            sometimes_fail,
            [-20.0, 0.0];
            max_iterations = 10,
            robust_mode = false
        )

        # Robust mode: should return Inf
        result = refine_critical_point(
            sometimes_fail,
            [-20.0, 0.0];
            max_iterations = 10,
            robust_mode = true
        )
        @test result.value_refined == Inf
        @test !result.converged
    end

    @testset "RefinementResult Structure" begin
        function simple(p::Vector{Float64})
            return sum(p.^2)
        end

        result = refine_critical_point(simple, [1.0, 1.0])

        # Check all fields exist
        @test hasfield(typeof(result), :point_raw)
        @test hasfield(typeof(result), :point_refined)
        @test hasfield(typeof(result), :value_raw)
        @test hasfield(typeof(result), :value_refined)
        @test hasfield(typeof(result), :converged)
        @test hasfield(typeof(result), :n_iterations)
        @test hasfield(typeof(result), :runtime_seconds)
        @test hasfield(typeof(result), :timed_out)

        # Check types
        @test result.point_raw isa Vector{Float64}
        @test result.point_refined isa Vector{Float64}
        @test result.value_raw isa Float64
        @test result.value_refined isa Float64
        @test result.converged isa Bool
        @test result.n_iterations isa Int
        @test result.runtime_seconds isa Float64
        @test result.timed_out isa Bool
    end
end

println("✅ Phase 1 refinement tests passed!")
