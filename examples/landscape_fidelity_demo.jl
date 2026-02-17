"""
    landscape_fidelity_demo.jl

Interactive demonstration of landscape fidelity assessment.

# Quick Start

Run this entire file in Julia REPL:
```julia
julia> include("examples/landscape_fidelity_demo.jl")
```

Or run specific examples:
```julia
julia> include("examples/landscape_fidelity_demo.jl")
julia> demo_1_simple_quadratic()
julia> demo_2_multiple_minima()
julia> demo_3_real_experiment()  # Requires path to experiment
```

# Purpose

Test whether polynomial approximant minima correctly identify
basins of attraction of the objective function.

"""

using GlobtimPostProcessing
using LinearAlgebra
using Printf

# If ForwardDiff is available, use it for automatic Hessian computation
try
    using ForwardDiff
    global HAS_FORWARDDIFF = true
    println("✓ ForwardDiff available - can compute Hessians automatically")
catch e
    @debug "ForwardDiff not available" exception=(e, catch_backtrace())
    global HAS_FORWARDDIFF = false
    println("✗ ForwardDiff not available - install with: using Pkg; Pkg.add(\"ForwardDiff\")")
end

"""
    demo_1_simple_quadratic()

Simplest case: quadratic objective, polynomial minimum close to true minimum.

Expected: High fidelity (both checks pass)
"""
function demo_1_simple_quadratic()
    println("\n" * "="^70)
    println("DEMO 1: Simple Quadratic - Good Approximation")
    println("="^70)

    # Define objective: minimum at [0.5, 0.5, 0.5, 0.5]
    f(x) = sum((x .- 0.5).^2)

    # Polynomial found a minimum at (close to true minimum)
    x_star = [0.48, 0.52, 0.49, 0.51]
    println("\nPolynomial minimum: ", x_star)
    println("f(x*) = ", f(x_star))

    # Local optimization converged to (true minimum)
    x_min = [0.50, 0.50, 0.50, 0.50]
    println("Refined minimum:    ", x_min)
    println("f(x_min) = ", f(x_min))

    # Check 1: Objective proximity
    println("\n--- Check 1: Objective Proximity ---")
    result_obj = check_objective_proximity(x_star, x_min, f, tolerance=0.05)
    println("Same basin? ", result_obj.is_same_basin)
    println("Relative difference: ", @sprintf("%.6f", result_obj.metric))
    println("Interpretation: ", result_obj.metric < 0.01 ? "✓ Excellent match" :
                                result_obj.metric < 0.05 ? "✓ Good match" : "⚠ Poor match")

    # Check 2: Hessian basin (if ForwardDiff available)
    if HAS_FORWARDDIFF
        println("\n--- Check 2: Hessian Basin ---")
        H = ForwardDiff.hessian(f, x_min)
        result_hess = check_hessian_basin(x_star, x_min, f, H)
        println("Inside basin? ", result_hess.is_same_basin)
        println("Distance: ", @sprintf("%.6f", result_hess.distance))
        println("Basin radius: ", @sprintf("%.6f", result_hess.basin_radius))
        println("Relative distance: ", @sprintf("%.6f", result_hess.metric))
        println("Interpretation: ", result_hess.metric < 0.5 ? "✓ Well inside basin" :
                                    result_hess.metric < 1.0 ? "✓ Inside basin" : "⚠ Outside basin")

        # Composite assessment
        println("\n--- Composite Assessment ---")
        result = assess_landscape_fidelity(x_star, x_min, f, hessian_min=H)
        println("Overall: ", result.is_same_basin ? "✓ SAME BASIN" : "✗ DIFFERENT BASINS")
        println("Confidence: ", @sprintf("%.1f%%", 100 * result.confidence))
        println("\nCriteria breakdown:")
        for c in result.criteria
            status = c.passed ? "✓" : "✗"
            println("  $status $(c.name): ", @sprintf("%.6f", c.metric))
        end
    else
        println("\n(Skipping Hessian check - ForwardDiff not available)")
    end

    println("\n" * "="^70)
    println("RESULT: This is a GOOD approximation - polynomial correctly")
    println("        identified the basin of the objective minimum.")
    println("="^70)
end

"""
    demo_2_multiple_minima()

More complex: objective with multiple minima.
Test if polynomial correctly identifies separate basins.

Expected: Some polynomial minima match objective basins, others don't.
"""
function demo_2_multiple_minima()
    println("\n" * "="^70)
    println("DEMO 2: Multiple Minima - Selective Basin Capture")
    println("="^70)

    # Objective with two minima
    # Minimum 1 at [0.2, 0.2]
    # Minimum 2 at [0.8, 0.8]
    function f(x)
        # Two quadratic wells
        d1 = sum((x .- [0.2, 0.2]).^2)
        d2 = sum((x .- [0.8, 0.8]).^2)
        return min(100*d1, 100*d2)  # Two wells of equal depth
    end

    # Test cases
    test_cases = [
        ("Good match - Basin 1", [0.21, 0.19], [0.20, 0.20]),
        ("Good match - Basin 2", [0.79, 0.81], [0.80, 0.80]),
        ("Bad match - Wrong basin", [0.21, 0.19], [0.80, 0.80]),
        ("Bad match - Spurious minimum", [0.50, 0.50], [0.20, 0.20])
    ]

    for (name, x_star, x_min) in test_cases
        println("\n--- $name ---")
        println("x* = $x_star, x_min = $x_min")

        result_obj = check_objective_proximity(x_star, x_min, f, tolerance=0.05)
        println("Objective proximity: ", result_obj.is_same_basin ? "✓ PASS" : "✗ FAIL",
                " (rel_diff = ", @sprintf("%.6f", result_obj.metric), ")")

        if HAS_FORWARDDIFF
            H = ForwardDiff.hessian(f, x_min)
            result_hess = check_hessian_basin(x_star, x_min, f, H)
            println("Hessian basin: ", result_hess.is_same_basin ? "✓ PASS" : "✗ FAIL",
                    " (rel_dist = ", @sprintf("%.6f", result_hess.metric), ")")

            result = assess_landscape_fidelity(x_star, x_min, f, hessian_min=H)
            println("Overall: ", result.is_same_basin ? "✓ SAME BASIN" : "✗ DIFFERENT BASINS",
                    " (confidence = ", @sprintf("%.0f%%", 100*result.confidence), ")")
        end
    end

    println("\n" * "="^70)
    println("RESULT: Fidelity checks correctly distinguish between")
    println("        valid basin captures and spurious minima.")
    println("="^70)
end

"""
    demo_3_real_experiment(experiment_path::String;
                          objective_function=nothing)

Test on real experiment data.

# Arguments
- `experiment_path`: Path to experiment directory (e.g., "path/to/lotka_volterra_exp")
- `objective_function`: Your objective function (if available)

# Example
```julia
# Define your objective
using Globtim
f = create_objective_from_model("lotka_volterra_4d")

# Run demo
demo_3_real_experiment("/path/to/experiment", objective_function=f)
```

# Without objective function
If you don't provide the objective, we'll use a mock function for demonstration:
```julia
demo_3_real_experiment("/path/to/experiment")
```
"""
function demo_3_real_experiment(experiment_path::String;
                                objective_function=nothing)
    println("\n" * "="^70)
    println("DEMO 3: Real Experiment Analysis")
    println("="^70)

    # Load experiment
    println("\nLoading experiment from: $experiment_path")
    try
        result = load_experiment_results(experiment_path)
        println("✓ Loaded experiment: ", result.experiment_id)

        # Check if we have critical points
        if result.critical_points === nothing || nrow(result.critical_points) == 0
            println("✗ No critical points found in experiment")
            return
        end

        println("✓ Found ", nrow(result.critical_points), " critical points")

        # Classify critical points
        df = result.critical_points
        classify_all_critical_points!(df)

        num_minima = count(==("minimum"), df.point_classification)
        num_saddles = count(==("saddle"), df.point_classification)
        num_maxima = count(==("maximum"), df.point_classification)

        println("\nClassification:")
        println("  Minima: $num_minima")
        println("  Saddles: $num_saddles")
        println("  Maxima: $num_maxima")

        if num_minima == 0
            println("\n⚠ No minima found - cannot assess fidelity")
            return
        end

        # Check if objective function provided
        if objective_function === nothing
            println("\n⚠ No objective function provided")
            println("  Using MOCK objective for demonstration")
            println("  For real analysis, provide: objective_function=your_function")

            # Mock objective based on z values
            f_mock(x) = sum(x.^2) * 1000.0  # Placeholder
            f = f_mock
        else
            f = objective_function
            println("\n✓ Using provided objective function")
        end

        # Analyze first minimum as example
        println("\n" * "-"^70)
        println("Example: Analyzing first polynomial minimum")
        println("-"^70)

        minima_df = filter(row -> row.point_classification == "minimum", df)
        first_minimum = first(eachrow(minima_df))

        # Extract coordinates
        param_cols = filter(n -> occursin(r"^x\d+$", string(n)), propertynames(first_minimum))
        sorted_cols = sort(param_cols, by=x -> parse(Int, match(r"\d+", string(x)).match))
        x_star = Float64[first_minimum[col] for col in sorted_cols]

        println("\nPolynomial minimum location: ", x_star)
        println("Objective value (z): ", first_minimum.z)

        # For real analysis, you would run local optimization here:
        println("\n--- Simulated Local Optimization ---")
        println("In practice, you would:")
        println("  1. Use Optim.jl or similar to optimize from x*")
        println("  2. Get converged point x_min")
        println("  3. Run fidelity checks")

        # Mock refinement (add small perturbation)
        x_min = x_star .+ randn(length(x_star)) * 0.01
        println("\n(Using mock refined minimum for demo)")
        println("Mock x_min: ", x_min)

        # Assess fidelity
        println("\n--- Fidelity Assessment ---")
        result_obj = check_objective_proximity(x_star, x_min, f)
        println("Objective proximity: ", result_obj.is_same_basin ? "✓" : "✗")
        println("  Relative difference: ", @sprintf("%.6f", result_obj.metric))

        if HAS_FORWARDDIFF
            try
                H = ForwardDiff.hessian(f, x_min)
                result_hess = check_hessian_basin(x_star, x_min, f, H)
                println("Hessian basin: ", result_hess.is_same_basin ? "✓" : "✗")
                println("  Relative distance: ", @sprintf("%.6f", result_hess.metric))

                result = assess_landscape_fidelity(x_star, x_min, f, hessian_min=H)
                println("\nOverall fidelity: ", result.is_same_basin ? "✓ SAME BASIN" : "✗ DIFFERENT")
                println("Confidence: ", @sprintf("%.0f%%", 100*result.confidence))
            catch e
                println("⚠ Could not compute Hessian: $e")
            end
        end

        println("\n" * "="^70)
        println("To run full analysis on real data:")
        println("  1. Implement your objective function")
        println("  2. Run local optimization from each polynomial minimum")
        println("  3. Use batch_assess_fidelity() for all points")
        println("="^70)

    catch e
        println("✗ Error loading experiment: $e")
        println("\nMake sure:")
        println("  - Path exists and contains experiment data")
        println("  - Experiment has critical_points_deg_N.csv files")
        println("  - CSV files have Hessian eigenvalue columns")
    end
end

"""
    demo_4_batch_processing()

Demonstrate batch processing of multiple critical points.
"""
function demo_4_batch_processing()
    println("\n" * "="^70)
    println("DEMO 4: Batch Processing Multiple Critical Points")
    println("="^70)

    # Create synthetic data
    using DataFrames

    println("\nCreating synthetic critical points...")

    # Objective with minimum at origin
    f(x) = sum(x.^2)

    # Synthetic critical points (some good, some bad)
    df = DataFrame(
        x1 = [0.01, 0.02, 0.50, -0.01, 0.03],
        x2 = [0.02, -0.01, 0.60, 0.01, -0.02],
        hessian_eigenvalue_1 = [2.0, 2.0, 2.0, 2.0, 2.0],
        hessian_eigenvalue_2 = [2.0, 2.0, 2.0, 2.0, 2.0],
        z = [f([0.01, 0.02]), f([0.02, -0.01]), f([0.50, 0.60]), f([-0.01, 0.01]), f([0.03, -0.02])]
    )

    # Classify
    classify_all_critical_points!(df)
    println("✓ Created ", nrow(df), " critical points (all classified as minima)")

    # Mock refined points (first 2 good, rest bad)
    refined = [
        [0.00, 0.00],  # Good - near origin
        [0.00, 0.00],  # Good - near origin
        [0.00, 0.00],  # Bad - polynomial minimum was far away
        [0.00, 0.00],  # Good - near origin
        [0.00, 0.00]   # Good - near origin
    ]

    println("\nRunning batch assessment...")
    result_df = batch_assess_fidelity(df, refined, f)

    println("\n" * "-"^70)
    println("Results:")
    println("-"^70)
    for (i, row) in enumerate(eachrow(result_df))
        status = row.is_same_basin ? "✓" : "✗"
        println("Point $i: $status (confidence = ", @sprintf("%.0f%%", 100*row.fidelity_confidence), ")")
        println("  x* = [", @sprintf("%.3f", row.x1), ", ", @sprintf("%.3f", row.x2), "]")
        println("  Obj proximity: ", @sprintf("%.6f", row.objective_proximity_metric))
    end

    # Summary statistics
    num_valid = sum(result_df.is_same_basin)
    total = nrow(result_df)
    fidelity_rate = num_valid / total

    println("\n" * "="^70)
    println("SUMMARY: $num_valid / $total polynomial minima correctly identify basins")
    println("Landscape Fidelity: ", @sprintf("%.1f%%", 100*fidelity_rate))
    println("="^70)
end

# Print usage information when file is included
println("\n" * "="^70)
println("Landscape Fidelity Demo Loaded")
println("="^70)
println("\nAvailable demos:")
println("  demo_1_simple_quadratic()      - Basic quadratic example")
println("  demo_2_multiple_minima()       - Multiple basin example")
println("  demo_3_real_experiment(path)   - Real experiment analysis")
println("  demo_4_batch_processing()      - Batch assessment example")
println("\nRun all demos:")
println("  demo_1_simple_quadratic()")
println("  demo_2_multiple_minima()")
println("  demo_4_batch_processing()")
println("\nFor real experiments:")
println("  demo_3_real_experiment(\"/path/to/experiment\", objective_function=f)")
println("="^70)
