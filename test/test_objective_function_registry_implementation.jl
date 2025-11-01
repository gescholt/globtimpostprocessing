"""
Test: ObjectiveFunctionRegistry Implementation Tests

These tests verify the actual implementation works correctly.
Run after implementing ObjectiveFunctionRegistry module.
"""

# Activate environment FIRST
using Pkg
Pkg.activate(dirname(@__DIR__))

using Test

println("Testing ObjectiveFunctionRegistry Implementation...")
println("=" ^ 70)

# Load the module
include(joinpath(dirname(@__DIR__), "src", "ObjectiveFunctionRegistry.jl"))
using .ObjectiveFunctionRegistry

# Create test config
test_config = Dict{String, Any}(
    "model_func" => "define_daisy_ex3_model_4D",
    "p_true" => [0.2, 0.3, 0.5, 0.6],
    "p_center" => [0.224, 0.273, 0.473, 0.578],
    "ic" => [1.0, 2.0, 1.0, 1.0],
    "time_interval" => [0.0, 10.0],
    "num_points" => 25,
    "dimension" => 4,
    "experiment_id" => 1
)

@testset "ObjectiveFunctionRegistry Implementation" begin

    @testset "1. Load DynamicalSystems Module" begin
        println("\n[Test 1] Loading DynamicalSystems module...")

        ds_module = load_dynamical_systems_module()

        @test !isnothing(ds_module)
        @test isdefined(ds_module, :define_daisy_ex3_model_4D)
        @test isdefined(ds_module, :make_error_distance)
        @test isdefined(ds_module, :L2_norm)

        println("✓ DynamicalSystems module loaded successfully")
    end

    @testset "2. Resolve Model Function" begin
        println("\n[Test 2] Resolving model function...")

        ds_module = load_dynamical_systems_module()
        model_func = resolve_model_function("define_daisy_ex3_model_4D", ds_module)

        @test !isnothing(model_func)
        @test model_func isa Function

        # Call the function
        model, params, states, outputs = model_func()
        @test !isnothing(model)
        @test length(params) == 4
        @test length(states) == 4
        @test length(outputs) == 2

        println("✓ Model function resolved and callable")
    end

    @testset "3. Resolve Model Function - Unknown Model" begin
        println("\n[Test 3] Testing error handling for unknown model...")

        ds_module = load_dynamical_systems_module()

        @test_throws ErrorException resolve_model_function("unknown_model_xyz", ds_module)

        try
            resolve_model_function("unknown_model_xyz", ds_module)
        catch e
            @test contains(e.msg, "not found")
            @test contains(e.msg, "unknown_model_xyz")
        end

        println("✓ Unknown model error handled correctly")
    end

    @testset "4. Validate Config - Valid" begin
        println("\n[Test 4] Validating correct config...")

        result = validate_config(test_config)
        @test result == true

        println("✓ Valid config accepted")
    end

    @testset "5. Validate Config - Missing Keys" begin
        println("\n[Test 5] Testing validation of incomplete config...")

        incomplete_config = Dict{String, Any}(
            "model_func" => "define_daisy_ex3_model_4D",
            "p_true" => [0.2, 0.3, 0.5, 0.6]
            # Missing: ic, time_interval, num_points
        )

        @test_throws ErrorException validate_config(incomplete_config)

        try
            validate_config(incomplete_config)
        catch e
            @test contains(e.msg, "Missing required keys")
            @test contains(e.msg, "ic")
            @test contains(e.msg, "time_interval")
            @test contains(e.msg, "num_points")
        end

        println("✓ Missing keys detected correctly")
    end

    @testset "6. Validate Config - Wrong Types" begin
        println("\n[Test 6] Testing validation of incorrect types...")

        bad_config = Dict{String, Any}(
            "model_func" => "define_daisy_ex3_model_4D",
            "p_true" => [0.2, 0.3, 0.5, 0.6],
            "ic" => [1.0, 2.0, 1.0, 1.0],
            "time_interval" => [0.0, 10.0],
            "num_points" => "not an integer"  # Wrong type!
        )

        @test_throws ErrorException validate_config(bad_config)

        try
            validate_config(bad_config)
        catch e
            @test contains(e.msg, "type errors")
            @test contains(e.msg, "num_points")
        end

        println("✓ Type errors detected correctly")
    end

    @testset "7. Reconstruct Error Function" begin
        println("\n[Test 7] Reconstructing error function from config...")

        error_func = reconstruct_error_function(test_config)

        @test !isnothing(error_func)
        @test error_func isa Function

        println("✓ Error function reconstructed successfully")
    end

    @testset "8. Evaluate Error Function at True Parameters" begin
        println("\n[Test 8] Evaluating error function at true parameters...")

        error_func = reconstruct_error_function(test_config)
        p_true = test_config["p_true"]

        error_at_true = error_func(p_true)

        @test error_at_true isa Real
        @test error_at_true >= 0
        @test error_at_true < 0.1  # Should be very small

        println("✓ Error at true params: $error_at_true (small as expected)")
    end

    @testset "9. Evaluate Error Function at Perturbed Parameters" begin
        println("\n[Test 9] Evaluating error function at perturbed parameters...")

        error_func = reconstruct_error_function(test_config)
        p_true = test_config["p_true"]

        # Perturb parameters
        p_perturbed = p_true .+ 0.2

        error_at_true = error_func(p_true)
        error_at_perturbed = error_func(p_perturbed)

        @test error_at_perturbed > error_at_true

        ratio = error_at_perturbed / (error_at_true + 1e-10)  # Avoid div by zero

        println("✓ Error at perturbed params: $error_at_perturbed")
        println("  Ratio: $(ratio)x larger than at true params")
    end

    @testset "10. Different Model Function" begin
        println("\n[Test 10] Testing with different model function...")

        # Test with Lotka-Volterra 3D model
        lv3d_config = Dict{String, Any}(
            "model_func" => "define_lotka_volterra_3D_model",
            "p_true" => [0.5, -0.05, -0.5],
            "ic" => [1.0, 2.0],
            "time_interval" => [0.0, 10.0],
            "num_points" => 25
        )

        @test validate_config(lv3d_config) == true

        error_func = reconstruct_error_function(lv3d_config)
        @test !isnothing(error_func)

        error_at_true = error_func(lv3d_config["p_true"])
        @test error_at_true >= 0
        @test error_at_true < 0.1

        println("✓ Different model function works correctly")
    end

end

println("\n" * "=" ^ 70)
println("✓ ALL IMPLEMENTATION TESTS PASSED!")
println("=" ^ 70)
println("\nObjectiveFunctionRegistry module is ready for use.")
println("Ready to proceed to Phase 3: TrajectoryEvaluator")
