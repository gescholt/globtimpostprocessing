"""
Test: TrajectoryEvaluator Module

TDD Phase 1: Write tests FIRST for the TrajectoryEvaluator module.

Purpose:
Given a critical point (found parameter values), evaluate its quality by:
1. Solving the ODE with found parameters
2. Comparing against reference trajectory (true parameters)
3. Computing trajectory distance metrics
4. Evaluating objective function value

NO FALLBACKS: Errors if model cannot be solved, parameters invalid, etc.
"""

# Activate environment FIRST
using Pkg
Pkg.activate(dirname(@__DIR__))

using Test
using JSON3
using LinearAlgebra

println("Testing TrajectoryEvaluator module...")
println("=" ^ 70)

# Test 1: Load module
println("\n[Test 1] Loading TrajectoryEvaluator module...")
try
    include(joinpath(dirname(@__DIR__), "src", "TrajectoryEvaluator.jl"))
    using .TrajectoryEvaluator
    println("✓ TrajectoryEvaluator module loaded")
catch e
    println("✗ Module not implemented yet (expected for TDD)")
    println("  This is normal - implement after tests are written")
    println("  Error: $e")
end

# Create test data (from typical experiment results)
test_config = Dict{String, Any}(
    "model_func" => "define_daisy_ex3_model_4D",
    "p_true" => [0.2, 0.3, 0.5, 0.6],
    "p_center" => [0.224, 0.273, 0.473, 0.578],
    "ic" => [1.0, 2.0, 1.0, 1.0],
    "time_interval" => [0.0, 10.0],
    "num_points" => 25,
    "dimension" => 4
)

# A critical point found by the optimizer (should be close to p_true)
critical_point = Dict{String, Any}(
    "x1" => 0.201,
    "x2" => 0.298,
    "x3" => 0.502,
    "x4" => 0.599,
    "z" => 0.00234  # Objective function value at this point
)

# Test suite begins (tests that will drive implementation)
println("\n" * "=" ^ 70)
println("TDD TEST SPECIFICATION")
println("=" ^ 70)

println("""

The following tests define the TrajectoryEvaluator API.
Implement the module to make these tests pass.

API Required:
1. solve_trajectory(config, p_found) -> trajectory_data
2. compute_trajectory_distance(traj_true, traj_found, norm_type) -> Real
3. evaluate_critical_point(config, critical_point_row) -> NamedTuple
4. compare_trajectories(config, p_true, p_found) -> NamedTuple

""")

# Test Spec 1: Solve trajectory with given parameters
println("\n[Spec 1] solve_trajectory(config, p_found) should:")
println("  - Load DynamicalSystems module")
println("  - Resolve model function from config[\"model_func\"]")
println("  - Create model instance")
println("  - Solve ODE with parameters p_found and initial conditions from config")
println("  - Return OrderedDict with time series data for each output")
println("  - ERROR if ODE solver fails")
println("  - ERROR if parameters have wrong dimension")

# Test Spec 2: Compute trajectory distance
println("\n[Spec 2] compute_trajectory_distance(traj_true, traj_found, norm_type) should:")
println("  - Take two trajectory dictionaries (from solve_trajectory)")
println("  - Compute distance for each output variable")
println("  - Support norm_type: :L1, :L2, :Linf")
println("  - Return scalar distance (aggregated across all outputs)")
println("  - ERROR if trajectories have different keys/lengths")
println("  - ERROR if norm_type unknown")

# Test Spec 3: Evaluate critical point quality
println("\n[Spec 3] evaluate_critical_point(config, critical_point_row) should:")
println("  - Extract parameter values from critical_point_row (x1, x2, ..., xN)")
println("  - Solve trajectory with found parameters")
println("  - Solve trajectory with true parameters (from config)")
println("  - Compute trajectory distance (L2)")
println("  - Return NamedTuple with:")
println("    - p_found: parameter values")
println("    - p_true: true parameter values")
println("    - param_distance: L2 distance in parameter space")
println("    - trajectory_distance: L2 distance in trajectory space")
println("    - objective_value: z value from critical point")
println("  - ERROR if critical point invalid")

# Test Spec 4: Compare trajectories
println("\n[Spec 4] compare_trajectories(config, p_true, p_found) should:")
println("  - Solve trajectory with p_true")
println("  - Solve trajectory with p_found")
println("  - Compute multiple distance metrics (L1, L2, Linf)")
println("  - Return NamedTuple with:")
println("    - trajectory_true: reference trajectory data")
println("    - trajectory_found: found trajectory data")
println("    - distances: Dict with :L1, :L2, :Linf distances")
println("    - output_distances: Per-output breakdown")

# Test Spec 5: Handle ODE solver failures
println("\n[Spec 5] solve_trajectory with bad parameters should:")
println("  - ERROR with clear message if ODE solve fails")
println("  - ERROR if parameters cause numerical instability")
println("  - NO fallback, NO default trajectory")

# Test Spec 6: Handle dimension mismatches
println("\n[Spec 6] evaluate_critical_point with wrong dimensions should:")
println("  - ERROR if critical_point has wrong number of parameters")
println("  - ERROR listing expected vs actual dimensions")

# Test Spec 7: Trajectory distance properties
println("\n[Spec 7] compute_trajectory_distance properties:")
println("  - Distance between identical trajectories = 0")
println("  - Distance is symmetric: d(A,B) == d(B,A)")
println("  - Distance > 0 for different trajectories")
println("  - L2 norm <= L1 norm (triangle inequality)")

println("\n" * "=" ^ 70)
println("END OF TEST SPECIFICATION")
println("=" ^ 70)

println("""

IMPLEMENTATION TASK:
Create src/TrajectoryEvaluator.jl with the above API.

Expected module structure:
```julia
module TrajectoryEvaluator

export solve_trajectory, compute_trajectory_distance,
       evaluate_critical_point, compare_trajectories

function solve_trajectory(config::Dict, p_found::Vector)
    # Load DynamicalSystems module
    # Resolve model function
    # Create model
    # Solve ODE
    # Return trajectory data
end

function compute_trajectory_distance(traj_true, traj_found, norm_type::Symbol)
    # Validate trajectories have same structure
    # Compute distance for each output
    # Aggregate distances
    # Return scalar
end

function evaluate_critical_point(config::Dict, critical_point_row)
    # Extract parameters from row (x1, x2, ..., xN)
    # Solve trajectory with found parameters
    # Solve trajectory with true parameters
    # Compute distances
    # Return comprehensive metrics
end

function compare_trajectories(config::Dict, p_true::Vector, p_found::Vector)
    # Solve both trajectories
    # Compute multiple distance metrics
    # Return detailed comparison
end

end # module
```

Design Notes:
1. Reuse ObjectiveFunctionRegistry.load_dynamical_systems_module()
2. Use ObjectiveFunctionRegistry.resolve_model_function()
3. Leverage existing sample_data() from DynamicalSystems module
4. Support arbitrary number of outputs (not just 2)
5. Work with any model function from DynamicalSystems

Integration:
- TrajectoryEvaluator will be used by analyze_experiments.jl mode 4
- Allows interactive inspection of critical points
- Helps identify which critical points are true parameter recoveries vs spurious

""")

println("\nTo run actual tests, implement the module then uncomment test blocks below.")
println("=" ^ 70)
