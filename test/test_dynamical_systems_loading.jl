"""
Test: Can we load DynamicalSystems module from globtimcore?

This test validates Phase 1 of the trajectory evaluation system:
- Can we add globtimcore as a dependency?
- Can we access DynamicalSystems module?
- Can we call model definition functions?
- Can we call make_error_distance?

TDD Approach: Write test FIRST, then fix Project.toml if needed.
"""

using Test
using Pkg

# Activate globtimpostprocessing environment
Pkg.activate(dirname(@__DIR__))

println("Testing DynamicalSystems module loading from globtimcore...")
println("=" ^ 70)

# Test 1: Load Globtim package
println("\n[Test 1] Loading Globtim package...")
try
    @eval using Globtim
    println("✓ Globtim package loaded successfully")
catch e
    println("✗ Failed to load Globtim package")
    println("  Error: $e")
    println("\n  ACTION NEEDED: Add Globtim (globtimcore) to Project.toml dependencies")
    exit(1)
end

# Test 2: Access DynamicalSystems.jl file
println("\n[Test 2] Locating DynamicalSystems.jl...")
globtim_root = pkgdir(Main.Globtim)
ds_path = joinpath(globtim_root, "Examples", "systems", "DynamicalSystems.jl")

if !isfile(ds_path)
    println("✗ DynamicalSystems.jl not found at: $ds_path")
    exit(1)
else
    println("✓ Found DynamicalSystems.jl at: $ds_path")
end

# Test 3: Include and load DynamicalSystems module
println("\n[Test 3] Loading DynamicalSystems module...")
try
    include(ds_path)
    @eval using .DynamicalSystems
    println("✓ DynamicalSystems module loaded successfully")
catch e
    println("✗ Failed to load DynamicalSystems module")
    println("  Error: $e")
    exit(1)
end

# Test 4: Call model definition function
println("\n[Test 4] Calling define_daisy_ex3_model_4D()...")
try
    model, params, states, outputs = Main.DynamicalSystems.define_daisy_ex3_model_4D()

    @assert !isnothing(model) "Model is nothing"
    @assert length(params) == 4 "Expected 4 parameters, got $(length(params))"
    @assert length(states) == 4 "Expected 4 states, got $(length(states))"
    @assert length(outputs) == 2 "Expected 2 outputs, got $(length(outputs))"

    println("✓ Model created successfully")
    println("  - Parameters: $(length(params))")
    println("  - States: $(length(states))")
    println("  - Outputs: $(length(outputs))")
catch e
    println("✗ Failed to create model")
    println("  Error: $e")
    exit(1)
end

# Test 5: Create error function
println("\n[Test 5] Creating error function with make_error_distance()...")
try
    model, params, states, outputs = Main.DynamicalSystems.define_daisy_ex3_model_4D()

    IC = [1.0, 2.0, 1.0, 1.0]
    P_TRUE = [0.2, 0.3, 0.5, 0.6]
    TIME_INTERVAL = [0.0, 10.0]
    NUM_POINTS = 25

    error_func = Main.DynamicalSystems.make_error_distance(
        model,
        outputs,
        IC,
        P_TRUE,
        TIME_INTERVAL,
        NUM_POINTS,
        Main.DynamicalSystems.L2_norm
    )

    @assert !isnothing(error_func) "Error function is nothing"
    @assert error_func isa Function "Error function is not a Function"

    println("✓ Error function created successfully")
catch e
    println("✗ Failed to create error function")
    println("  Error: $e")
    Base.show_backtrace(stdout, catch_backtrace())
    exit(1)
end

# Test 6: Evaluate error function at true parameters
println("\n[Test 6] Evaluating error function at true parameters...")
try
    model, params, states, outputs = Main.DynamicalSystems.define_daisy_ex3_model_4D()

    IC = [1.0, 2.0, 1.0, 1.0]
    P_TRUE = [0.2, 0.3, 0.5, 0.6]
    TIME_INTERVAL = [0.0, 10.0]
    NUM_POINTS = 25

    error_func = Main.DynamicalSystems.make_error_distance(
        model,
        outputs,
        IC,
        P_TRUE,
        TIME_INTERVAL,
        NUM_POINTS,
        Main.DynamicalSystems.L2_norm
    )

    error_at_true = error_func(P_TRUE)

    @assert error_at_true isa Real "Error value is not Real"
    @assert error_at_true >= 0 "Error value is negative"
    @assert error_at_true < 0.1 "Error at true parameters too large: $error_at_true"

    println("✓ Error function evaluated successfully")
    println("  - Error at true params: $error_at_true")
catch e
    println("✗ Failed to evaluate error function")
    println("  Error: $e")
    Base.show_backtrace(stdout, catch_backtrace())
    exit(1)
end

# Test 7: Verify error increases with perturbation
println("\n[Test 7] Verifying error increases with parameter perturbation...")
try
    model, params, states, outputs = Main.DynamicalSystems.define_daisy_ex3_model_4D()

    IC = [1.0, 2.0, 1.0, 1.0]
    P_TRUE = [0.2, 0.3, 0.5, 0.6]
    TIME_INTERVAL = [0.0, 10.0]
    NUM_POINTS = 25

    error_func = Main.DynamicalSystems.make_error_distance(
        model,
        outputs,
        IC,
        P_TRUE,
        TIME_INTERVAL,
        NUM_POINTS,
        Main.DynamicalSystems.L2_norm
    )

    error_at_true = error_func(P_TRUE)
    P_PERTURBED = P_TRUE .+ 0.2
    error_at_perturbed = error_func(P_PERTURBED)

    @assert error_at_perturbed > error_at_true "Error did not increase with perturbation"

    println("✓ Error function behaves correctly")
    println("  - Error at true params: $error_at_true")
    println("  - Error at perturbed params: $error_at_perturbed")
    println("  - Ratio: $(error_at_perturbed / error_at_true)x")
catch e
    println("✗ Failed perturbation test")
    println("  Error: $e")
    exit(1)
end

println("\n" * "=" ^ 70)
println("✓ ALL TESTS PASSED - DynamicalSystems module is accessible!")
println("=" ^ 70)
println("\nReady to proceed to Phase 2: ObjectiveFunctionRegistry implementation")
