"""
Test: ObjectiveFunctionRegistry Module

TDD Phase 2: Write tests FIRST for the ObjectiveFunctionRegistry module.

This module should:
1. Load experiment config (JSON)
2. Resolve model_func string → actual Julia function
3. Reconstruct error function from config parameters
4. Evaluate error function at parameter values

NO FALLBACKS: Errors if model_func unknown, config incomplete, etc.
"""

# Activate environment FIRST
using Pkg
Pkg.activate(dirname(@__DIR__))

using Test
using JSON3

println("Testing ObjectiveFunctionRegistry module...")
println("=" ^ 70)

# Test 1: Load module
println("\n[Test 1] Loading ObjectiveFunctionRegistry module...")
try
    include(joinpath(dirname(@__DIR__), "src", "ObjectiveFunctionRegistry.jl"))
    using .ObjectiveFunctionRegistry
    println("✓ ObjectiveFunctionRegistry module loaded")
catch e
    println("✗ Module not implemented yet (expected for TDD)")
    println("  This is normal - implement after tests are written")
    println("  Error: $e")
end

# Create test config (simulating real experiment config)
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

println("\n[Test 2] Validating experiment config...")
println("Config keys: ", keys(test_config))
required_keys = ["model_func", "p_true", "ic", "time_interval", "num_points"]
for key in required_keys
    if haskey(test_config, key)
        println("  ✓ $key: ", test_config[key])
    else
        error("Missing required key: $key")
    end
end

# Test suite begins (tests that will drive implementation)
println("\n" * "=" ^ 70)
println("TDD TEST SPECIFICATION")
println("=" ^ 70)

println("""

The following tests define the ObjectiveFunctionRegistry API.
Implement the module to make these tests pass.

API Required:
1. load_dynamical_systems_module() -> DynamicalSystems module
2. resolve_model_function(model_func::String, ds_module) -> Function
3. reconstruct_error_function(config::Dict) -> Function
4. validate_config(config::Dict) -> Bool (throws if invalid)

""")

# Test Spec 1: Load DynamicalSystems module
println("\n[Spec 1] load_dynamical_systems_module() should:")
println("  - Return the DynamicalSystems module from Globtim/Examples")
println("  - ERROR if Globtim not available")
println("  - ERROR if DynamicalSystems.jl not found")

# Test Spec 2: Resolve model function string
println("\n[Spec 2] resolve_model_function(\"define_daisy_ex3_model_4D\", ds_module) should:")
println("  - Return the actual Julia function")
println("  - Be callable: model_func() returns (model, params, states, outputs)")
println("  - ERROR if model_func string not found in module")

# Test Spec 3: Validate config
println("\n[Spec 3] validate_config(config) should:")
println("  - Return true if all required keys present")
println("  - ERROR if missing: model_func, p_true, ic, time_interval, num_points")
println("  - ERROR if wrong types (e.g., p_true not numeric array)")
println("  - Validate dimension consistency: length(p_true) == length(ic)")

# Test Spec 4: Reconstruct error function
println("\n[Spec 4] reconstruct_error_function(config) should:")
println("  - Call load_dynamical_systems_module()")
println("  - Resolve model function from config[\"model_func\"]")
println("  - Create model: model, params, states, outputs = model_func()")
println("  - Extract: ic, p_true, time_interval, num_points from config")
println("  - Return: error_func = make_error_distance(...)")
println("  - ERROR if any step fails")

# Test Spec 5: Error function evaluation
println("\n[Spec 5] error_func(p) where error_func = reconstruct_error_function(config):")
println("  - Takes parameter vector p of correct dimension")
println("  - Returns scalar Real >= 0")
println("  - error_func(p_true) should be very small (< 0.1)")
println("  - error_func(p_perturbed) should be larger")

# Test Spec 6: Handle unknown model_func
println("\n[Spec 6] resolve_model_function(\"unknown_model\", ds_module) should:")
println("  - ERROR with clear message: \"Model function 'unknown_model' not found\"")
println("  - NO fallback, NO default")

# Test Spec 7: Handle incomplete config
println("\n[Spec 7] validate_config(incomplete_config) should:")
println("  - ERROR listing missing keys")
println("  - ERROR with clear message for each missing field")

println("\n" * "=" ^ 70)
println("END OF TEST SPECIFICATION")
println("=" ^ 70)

println("""

IMPLEMENTATION TASK:
Create src/ObjectiveFunctionRegistry.jl with the above API.
Then run this test again to verify implementation.

Expected file structure:
```julia
module ObjectiveFunctionRegistry

export load_dynamical_systems_module, resolve_model_function,
       validate_config, reconstruct_error_function

function load_dynamical_systems_module()
    # Implementation here
end

function resolve_model_function(model_func_name::String, ds_module)
    # Implementation here
end

function validate_config(config::Dict)
    # Implementation here
end

function reconstruct_error_function(config::Dict)
    # Validate first
    # Load module
    # Resolve function
    # Create error function
    # Return
end

end # module
```

""")

println("\nTo run actual tests, implement the module then uncomment test blocks below.")
println("=" ^ 70)
