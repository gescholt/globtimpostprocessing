"""
Test: TrajectoryComparison Module

TDD Phase 1: Write tests FIRST for the TrajectoryComparison module.

Purpose:
High-level analysis module that combines ObjectiveFunctionRegistry and
TrajectoryEvaluator to:
1. Load all critical points for an experiment
2. Evaluate each critical point's quality
3. Rank critical points by parameter/trajectory distance
4. Identify which critical points represent true parameter recovery
5. Generate comparative analysis across polynomial degrees

NO FALLBACKS: Errors if data missing, experiments invalid, etc.
"""

# Activate environment FIRST
using Pkg
Pkg.activate(dirname(@__DIR__))

using Test
using DataFrames
using JSON3

println("Testing TrajectoryComparison module...")
println("=" ^ 70)

# Test 1: Load module
println("\n[Test 1] Loading TrajectoryComparison module...")
try
    include(joinpath(dirname(@__DIR__), "src", "TrajectoryComparison.jl"))
    using .TrajectoryComparison
    println("✓ TrajectoryComparison module loaded")
catch e
    println("✗ Module not implemented yet (expected for TDD)")
    println("  This is normal - implement after tests are written")
    println("  Error: $e")
end

# Test suite begins (tests that will drive implementation)
println("\n" * "=" ^ 70)
println("TDD TEST SPECIFICATION")
println("=" ^ 70)

println("""

The following tests define the TrajectoryComparison API.
Implement the module to make these tests pass.

API Required:
1. load_critical_points_for_degree(exp_path, degree) -> DataFrame
2. evaluate_all_critical_points(config, critical_points_df) -> DataFrame
3. rank_critical_points(evaluated_df, by) -> DataFrame
4. identify_parameter_recovery(evaluated_df, threshold) -> DataFrame
5. analyze_experiment_convergence(exp_path) -> NamedTuple
6. generate_comparison_report(exp_path, output_format) -> String/Dict

""")

# Test Spec 1: Load critical points for a specific degree
println("\n[Spec 1] load_critical_points_for_degree(exp_path, degree) should:")
println("  - Read critical_points_deg_<N>.csv from experiment directory")
println("  - Return DataFrame with columns: x1, x2, ..., xN, z, gradient_norm, etc.")
println("  - ERROR if file not found")
println("  - ERROR if CSV malformed")
println("  - Return empty DataFrame if no critical points (not error)")

# Test Spec 2: Evaluate all critical points
println("\n[Spec 2] evaluate_all_critical_points(config, critical_points_df) should:")
println("  - Call TrajectoryEvaluator.evaluate_critical_point for each row")
println("  - Add columns to DataFrame:")
println("    - param_distance: L2 distance to true parameters")
println("    - trajectory_distance: L2 distance in trajectory space")
println("    - is_recovery: Boolean (param_distance < threshold)")
println("  - Return augmented DataFrame with same number of rows")
println("  - ERROR if config missing required fields")

# Test Spec 3: Rank critical points
println("\n[Spec 3] rank_critical_points(evaluated_df, by) should:")
println("  - Sort DataFrame by specified column")
println("  - Support by: :param_distance, :trajectory_distance, :objective_value")
println("  - Add rank column (1 = best)")
println("  - Return sorted DataFrame")
println("  - ERROR if 'by' column doesn't exist")

# Test Spec 4: Identify parameter recoveries
println("\n[Spec 4] identify_parameter_recovery(evaluated_df, threshold) should:")
println("  - Filter critical points where param_distance < threshold")
println("  - Return DataFrame with only recovery candidates")
println("  - Sort by param_distance (ascending)")
println("  - Return empty DataFrame if no recoveries found (not error)")

# Test Spec 5: Analyze convergence across degrees
println("\n[Spec 5] analyze_experiment_convergence(exp_path) should:")
println("  - Load config from experiment directory")
println("  - Load critical points for all available degrees")
println("  - Evaluate all critical points across all degrees")
println("  - Compute convergence metrics:")
println("    - best_param_distance_by_degree: Dict{Int, Float64}")
println("    - best_trajectory_distance_by_degree: Dict{Int, Float64}")
println("    - num_critical_points_by_degree: Dict{Int, Int}")
println("    - num_recoveries_by_degree: Dict{Int, Int}")
println("  - Return NamedTuple with all metrics")
println("  - ERROR if experiment_config.json not found")

# Test Spec 6: Generate comparison report
println("\n[Spec 6] generate_comparison_report(exp_path, output_format) should:")
println("  - Analyze experiment convergence")
println("  - Generate formatted report")
println("  - Support output_format: :text, :markdown, :json")
println("  - :text: Human-readable ASCII table")
println("  - :markdown: Markdown formatted tables")
println("  - :json: JSON structure with all data")
println("  - Return String (text/markdown) or Dict (json)")
println("  - ERROR if output_format unknown")

# Test Spec 7: Handle experiments with no recoveries
println("\n[Spec 7] analyze_experiment_convergence with no recoveries should:")
println("  - Return valid NamedTuple with empty recovery lists")
println("  - Still compute best distances (may be large)")
println("  - num_recoveries_by_degree should all be 0")
println("  - Should NOT error")

# Test Spec 8: Handle missing degrees
println("\n[Spec 8] analyze_experiment_convergence with sparse degrees should:")
println("  - Only analyze degrees that have CSV files")
println("  - Skip missing degrees (e.g., degree 4, 8, 12 but not 6)")
println("  - Return metrics only for available degrees")
println("  - Should NOT error or create fake data")

# Test Spec 9: Per-degree comparison
println("\n[Spec 9] Additional function: compare_degrees(exp_path, deg1, deg2) should:")
println("  - Load critical points for both degrees")
println("  - Evaluate both sets")
println("  - Compare:")
println("    - Number of critical points")
println("    - Number of recoveries")
println("    - Best parameter distance")
println("    - Best trajectory distance")
println("  - Return NamedTuple with comparison metrics")
println("  - ERROR if either degree not found")

# Test Spec 10: Integration with campaign analysis
println("\n[Spec 10] analyze_campaign_parameter_recovery(campaign_path) should:")
println("  - Discover all experiments in campaign")
println("  - Run analyze_experiment_convergence for each")
println("  - Aggregate results across experiments")
println("  - Return DataFrame with columns:")
println("    - experiment_id")
println("    - sample_range")
println("    - best_param_distance (across all degrees)")
println("    - best_trajectory_distance")
println("    - total_critical_points")
println("    - total_recoveries")
println("  - Support campaign-level convergence analysis")

println("\n" * "=" ^ 70)
println("END OF TEST SPECIFICATION")
println("=" ^ 70)

println("""

IMPLEMENTATION TASK:
Create src/TrajectoryComparison.jl with the above API.

Expected module structure:
```julia
module TrajectoryComparison

export load_critical_points_for_degree,
       evaluate_all_critical_points,
       rank_critical_points,
       identify_parameter_recovery,
       analyze_experiment_convergence,
       generate_comparison_report,
       compare_degrees,
       analyze_campaign_parameter_recovery

using DataFrames
using CSV
using JSON3
using Printf
using Statistics

# Import from other modules
include("ObjectiveFunctionRegistry.jl")
using .ObjectiveFunctionRegistry

include("TrajectoryEvaluator.jl")
using .TrajectoryEvaluator

function load_critical_points_for_degree(exp_path::String, degree::Int)
    # Read CSV file
    # Return DataFrame
end

function evaluate_all_critical_points(config::Dict, critical_points_df::DataFrame)
    # Iterate over rows
    # Call TrajectoryEvaluator.evaluate_critical_point
    # Augment DataFrame with new columns
    # Return augmented DataFrame
end

function rank_critical_points(evaluated_df::DataFrame, by::Symbol)
    # Sort by column
    # Add rank column
    # Return sorted DataFrame
end

function identify_parameter_recovery(evaluated_df::DataFrame, threshold::Float64)
    # Filter by param_distance < threshold
    # Sort by param_distance
    # Return filtered DataFrame
end

function analyze_experiment_convergence(exp_path::String)
    # Load config
    # Discover all degree files
    # Load and evaluate all critical points
    # Compute convergence metrics
    # Return comprehensive NamedTuple
end

function generate_comparison_report(exp_path::String, output_format::Symbol)
    # Analyze experiment
    # Format output based on output_format
    # Return formatted report
end

function compare_degrees(exp_path::String, deg1::Int, deg2::Int)
    # Load both degree files
    # Evaluate both
    # Compare metrics
    # Return comparison
end

function analyze_campaign_parameter_recovery(campaign_path::String)
    # Discover experiments
    # Analyze each
    # Aggregate results
    # Return DataFrame
end

end # module
```

Design Notes:
1. This is the highest-level analysis module
2. Combines ObjectiveFunctionRegistry + TrajectoryEvaluator
3. Provides user-facing analysis functions
4. Used by analyze_experiments.jl mode 4
5. Enables interactive critical point inspection

Key Features:
- Comprehensive convergence analysis across polynomial degrees
- Parameter recovery identification
- Multiple output formats (text, markdown, JSON)
- Campaign-level aggregation
- Degree-to-degree comparison

Integration:
- Called by analyze_experiments.jl mode 4
- Provides data for interactive critical point selection
- Generates reports for documentation

""")

println("\nTo run actual tests, implement the module then uncomment test blocks below.")
println("=" ^ 70)
