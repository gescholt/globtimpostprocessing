# Landscape Fidelity Assessment Guide

## Overview

**Landscape fidelity** measures how well polynomial approximant critical points correspond to objective function basins of attraction.

**Key Question**: When the polynomial has a minimum at x*, does local optimization from x* converge to a nearby objective minimum, or does it jump to a different basin?

## Quick Start

### 1. Load Your Experiment

```julia
using GlobtimPostProcessing

# Load experiment results
results = load_experiment_results("/path/to/experiment")

# Get critical points
df = results.critical_points
classify_all_critical_points!(df)
```

### 2. Define Your Objective Function

```julia
# Load your model (example for Lotka-Volterra)
using Globtim
include(joinpath(ENV["GLOBTIM_ROOT"], "Examples/systems/DynamicalSystems.jl"))

# Create objective function
model, params, states, outputs = DynamicalSystems.lotka_volterra_4d()
config = load_experiment_config(results.source_path)

function create_objective(config)
    function obj(p)
        # Solve ODE with parameters p
        trajectory = solve_trajectory(config, p)
        # Compute trajectory distance to reference
        ref_trajectory = solve_trajectory(config, config["p_true"])
        return compute_trajectory_distance(ref_trajectory, trajectory, :L2)
    end
    return obj
end

objective = create_objective(config)
```

### 3. Run Local Optimization from Polynomial Minima

```julia
using Optim

# Filter for minima
minima_df = filter(row -> row.point_classification == "minimum", df)

# Run optimization from each
refined_points = []
for row in eachrow(minima_df)
    # Extract starting point
    x_star = [row.x1, row.x2, row.x3, row.x4]

    # Run local optimizer
    result = optimize(objective, x_star, BFGS())

    # Store converged point
    x_min = Optim.minimizer(result)
    push!(refined_points, x_min)
end
```

### 4. Assess Landscape Fidelity

```julia
# Batch assessment
fidelity_df = batch_assess_fidelity(minima_df, refined_points, objective)

# Analyze results
num_valid = sum(fidelity_df.is_same_basin)
total = nrow(fidelity_df)
fidelity_rate = num_valid / total

println("Landscape Fidelity: $(round(100*fidelity_rate, digits=1))%")
println("Valid basins: $num_valid / $total")
```

## Assessment Methods

### Method 1: Objective Proximity (Fast)

Checks if f(x*) ≈ f(x_min):

```julia
result = check_objective_proximity(x_star, x_min, objective, tolerance=0.05)

if result.is_same_basin
    println("✓ Same basin (rel_diff = $(result.metric))")
else
    println("✗ Different basins")
end
```

**Pros**: Fast, no derivatives needed
**Cons**: Can give false positives in flat regions

### Method 2: Hessian Basin Estimation (Rigorous)

Estimates basin radius using local quadratic approximation:

```julia
using ForwardDiff

# Compute Hessian at refined minimum
H = ForwardDiff.hessian(objective, x_min)

# Check if x* is inside estimated basin
result = check_hessian_basin(x_star, x_min, objective, H)

if result.is_same_basin
    println("✓ Inside basin (distance/radius = $(result.metric))")
    println("  Distance: $(result.distance)")
    println("  Basin radius: $(result.basin_radius)")
else
    println("✗ Outside basin")
end
```

**Pros**: Geometrically rigorous, adapts to curvature
**Cons**: Requires Hessian computation (expensive for high-dimensional problems)

### Method 3: Composite Assessment (Recommended)

Combines multiple criteria:

```julia
result = assess_landscape_fidelity(x_star, x_min, objective, hessian_min=H)

println("Basin membership: ", result.is_same_basin ? "✓ SAME" : "✗ DIFFERENT")
println("Confidence: $(round(100*result.confidence, digits=1))%")

for c in result.criteria
    status = c.passed ? "✓" : "✗"
    println("  $status $(c.name): $(c.metric)")
end
```

## Interpretation Guide

### Confidence Scores

- **100%**: All criteria agree → high confidence
- **50-99%**: Mixed results → uncertain case, inspect manually
- **0%**: All criteria disagree → clearly different basins

### Typical Fidelity Rates

| Fidelity Rate | Interpretation |
|---------------|----------------|
| > 80% | Excellent approximation - polynomial captures objective landscape well |
| 60-80% | Good approximation - most polynomial minima are valid |
| 40-60% | Fair approximation - significant differences between polynomial and objective |
| < 40% | Poor approximation - polynomial landscape misleading |

## Interactive Testing (REPL)

For quick experimentation without writing scripts:

```julia
# Load demos
include("examples/landscape_fidelity_demo.jl")

# Run demos
demo_1_simple_quadratic()      # Learn the basics
demo_2_multiple_minima()       # See how it handles multiple basins
demo_4_batch_processing()      # Batch workflow example

# Test with your experiment
demo_3_real_experiment("/path/to/your/experiment", objective_function=your_obj)
```

## Common Workflows

### Workflow A: Quick Check (No Hessian)

```julia
# Just use objective proximity
for (x_star, x_min) in zip(polynomial_minima, refined_minima)
    result = check_objective_proximity(x_star, x_min, objective)
    println(result.is_same_basin ? "✓" : "✗")
end
```

### Workflow B: Rigorous Analysis (With Hessian)

```julia
using ForwardDiff

fidelity_results = []
for (x_star, x_min) in zip(polynomial_minima, refined_minima)
    H = ForwardDiff.hessian(objective, x_min)
    result = assess_landscape_fidelity(x_star, x_min, objective, hessian_min=H)
    push!(fidelity_results, result)
end

# Summary statistics
confidences = [r.confidence for r in fidelity_results]
mean_confidence = mean(confidences)
```

### Workflow C: Batch Processing (Recommended for Many Points)

```julia
# Prepare data
refined_points = [optimize_from(x) for x in polynomial_minima]
hessians = [ForwardDiff.hessian(objective, x) for x in refined_points]

# Batch assess
results_df = batch_assess_fidelity(
    critical_points_df,
    refined_points,
    objective,
    hessian_min_list=hessians
)

# Export results
CSV.write("fidelity_assessment.csv", results_df)
```

## Troubleshooting

### Issue: "All points classified as different basins"

**Possible causes**:
1. Objective proximity tolerance too strict → Increase `tolerance` parameter
2. Polynomial approximation is poor → Check L2 approximation error
3. Hessian threshold too small → Increase `threshold_factor` parameter

**Solution**:
```julia
# More lenient parameters
result = assess_landscape_fidelity(
    x_star, x_min, objective,
    hessian_min=H,
    obj_tolerance=0.10,        # Default: 0.05
    threshold_factor=0.20      # Default: 0.10
)
```

### Issue: "Hessian computation fails or very slow"

**Possible causes**:
1. Objective function not differentiable
2. High-dimensional problem (computing Hessian is O(n²))

**Solution**:
```julia
# Use objective proximity only
result = assess_landscape_fidelity(x_star, x_min, objective)
# No hessian_min parameter → only uses objective proximity check
```

### Issue: "Different results for nearby points"

**This is expected!** The basin boundary can be sharp. Points very close in parameter space can lie in different basins.

**Diagnostic**:
```julia
# Visualize the sensitivity
for δ in [0.001, 0.01, 0.1]
    x_perturbed = x_star .+ δ * randn(length(x_star))
    x_min_perturbed = optimize_from(x_perturbed)
    result = check_objective_proximity(x_perturbed, x_min_perturbed, objective)
    println("Perturbation $δ: ", result.is_same_basin)
end
```

## Examples with Real Data

### Example 1: Lotka-Volterra 4D

```julia
# Load experiment
results = load_experiment_results("path/to/lotka_volterra_4d_exp")

# Define objective (trajectory matching)
config = load_experiment_config(results.source_path)
function lv_objective(p)
    traj = solve_trajectory(config, p)
    ref_traj = solve_trajectory(config, config["p_true"])
    return compute_trajectory_distance(ref_traj, traj, :L2)
end

# Classify critical points
df = results.critical_points
classify_all_critical_points!(df)

# Assess fidelity for degree 6
deg6_minima = filter(row -> row.point_classification == "minimum" && row.degree == 6, df)

# ... run optimization and assess ...
```

### Example 2: Campaign Analysis

Compare fidelity across multiple experiments:

```julia
campaign = load_campaign_results("path/to/campaign")

fidelity_summary = Dict()
for exp in campaign.experiments
    df = exp.critical_points
    classify_all_critical_points!(df)

    # ... run optimization ...
    # ... assess fidelity ...

    fidelity_summary[exp.experiment_id] = fidelity_rate
end

# Plot fidelity vs domain size, degree, etc.
```

## Best Practices

1. **Always classify critical points first** using `classify_all_critical_points!` before assessing fidelity
2. **Use composite assessment** when possible - provides confidence scores
3. **Compute Hessians only when needed** - expensive for high-dimensional problems
4. **Export results to CSV** for later analysis and visualization
5. **Test on synthetic examples first** to build intuition

## Further Reading

- Module documentation: `?assess_landscape_fidelity`
- Demo scripts: `examples/landscape_fidelity_demo.jl`
- Test suite: `test/test_landscape_fidelity.jl`
- Source code: `src/LandscapeFidelity.jl`
