# Parameter Recovery

This guide covers parameter recovery analysis - measuring how close found critical points are to known ground truth parameters.

## Overview

In parameter estimation problems, we often know the true parameters (`p_true`) that generated the data. Parameter recovery analysis measures:
- How close are found critical points to `p_true`?
- Which critical point is the best estimate?
- How does recovery accuracy vary with polynomial degree?

## Quick Start

```julia
using GlobtimPostProcessing

experiment_dir = "path/to/experiment"

# Check if ground truth is available
if has_ground_truth(experiment_dir)
    # Compute recovery statistics
    stats = compute_parameter_recovery_stats(experiment_dir)

    println("Best recovery error: \$(stats.min_distance)")
    println("Best point index: \$(stats.best_point_idx)")

    # Pretty-print table
    generate_parameter_recovery_table(experiment_dir)
else
    println("No ground truth parameters available")
end
```

## Checking for Ground Truth

The experiment config must contain `p_true` field:

```julia
# Check if available
if has_ground_truth(experiment_dir)
    # Ground truth available
    config = load_experiment_config(experiment_dir)
    p_true = config["p_true"]
    println("True parameters: \$p_true")
end
```

## Computing Recovery Statistics

```julia
stats = compute_parameter_recovery_stats(experiment_dir)

# Available fields
println("Minimum distance: \$(stats.min_distance)")      # Best recovery
println("Mean distance: \$(stats.mean_distance)")        # Average recovery
println("Max distance: \$(stats.max_distance)")          # Worst point
println("Best point index: \$(stats.best_point_idx)")    # Index of best estimate
println("Best point: \$(stats.best_point)")              # Coordinates
println("Number of points: \$(stats.n_points)")
```

## Distance Metrics

The default metric is Euclidean distance:

```julia
distance = param_distance(p_found, p_true)
```

This computes `||p_found - p_true||₂`.

### Alternative Metrics

```julia
# Component-wise relative error
function relative_error(p_found, p_true)
    return maximum(abs.(p_found .- p_true) ./ abs.(p_true))
end

# Normalized distance (scale-invariant)
function normalized_distance(p_found, p_true)
    return norm(p_found .- p_true) / norm(p_true)
end
```

## Pretty-Printed Tables

Generate a formatted table showing recovery for all critical points:

```julia
generate_parameter_recovery_table(experiment_dir)
```

Example output:
```
Parameter Recovery Analysis
═══════════════════════════════════════════════════════════
  Idx  │  Distance   │  p₁      │  p₂      │  p₃      │  p₄
═══════════════════════════════════════════════════════════
    1  │   1.23e-06  │  0.5001  │  0.6000  │  0.3999  │  0.8001
    2  │   4.56e-04  │  0.4998  │  0.6012  │  0.4005  │  0.7989
    3  │   2.34e-02  │  0.5234  │  0.5876  │  0.3823  │  0.8123
  ...  │     ...     │    ...   │    ...   │    ...   │    ...
═══════════════════════════════════════════════════════════
True:  │      -      │  0.5000  │  0.6000  │  0.4000  │  0.8000
Best:  │   1.23e-06  │  0.5001  │  0.6000  │  0.3999  │  0.8001
═══════════════════════════════════════════════════════════
```

## Recovery by Degree

Analyze how recovery improves with polynomial degree:

```julia
# Load critical points for each degree
config = load_experiment_config(experiment_dir)
p_true = config["p_true"]

for degree in config["degrees"]
    points_df = load_critical_points_for_degree(experiment_dir, degree)

    # Compute distances
    distances = [param_distance(row_to_point(row), p_true)
                 for row in eachrow(points_df)]

    min_dist = minimum(distances)
    println("Degree \$degree: min distance = \$(min_dist)")
end
```

## Quality Thresholds

Use thresholds to grade recovery quality:

```julia
thresholds = load_quality_thresholds()
recovery_thresholds = thresholds["parameter_recovery"]

distance = stats.min_distance

if distance < recovery_thresholds["excellent_threshold"]
    grade = :excellent
elseif distance < recovery_thresholds["good_threshold"]
    grade = :good
elseif distance < recovery_thresholds["acceptable_threshold"]
    grade = :acceptable
else
    grade = :poor
end

println("Recovery grade: \$grade")
```

Default thresholds:
```toml
[parameter_recovery]
excellent_threshold = 1e-6
good_threshold = 1e-4
acceptable_threshold = 1e-2
```

## Combined with Refinement

For best results, combine with critical point refinement:

```julia
# 1. Refine critical points
refined = refine_experiment_results(experiment_dir, objective)

# 2. Compute recovery for refined points
config = load_experiment_config(experiment_dir)
p_true = config["p_true"]

# Find best refined estimate
best_refined = refined.refined_points[refined.best_refined_idx]
recovery_distance = param_distance(best_refined, p_true)

println("Raw best distance: \$(stats.min_distance)")
println("Refined best distance: \$(recovery_distance)")
println("Improvement: \$(round(100 * (1 - recovery_distance/stats.min_distance)))%")
```

## Campaign Analysis

Compare recovery across experiments:

```julia
campaign = load_campaign_results(campaign_dir)

recovery_summary = DataFrame(
    experiment_id = String[],
    domain_size = Float64[],
    degree = Int[],
    min_distance = Float64[]
)

for exp in campaign.experiments
    if has_ground_truth(exp.source_path)
        stats = compute_parameter_recovery_stats(exp.source_path)
        config = load_experiment_config(exp.source_path)

        push!(recovery_summary, (
            experiment_id = exp.experiment_id,
            domain_size = config["domain_range"],
            degree = config["degree_max"],
            min_distance = stats.min_distance
        ))
    end
end

# Analyze trends
using Statistics
by_domain = groupby(recovery_summary, :domain_size)
for group in by_domain
    println("Domain \$(first(group.domain_size)): mean recovery = \$(mean(group.min_distance))")
end
```

## API Reference

### Functions

| Function | Description |
|----------|-------------|
| `has_ground_truth(dir)` | Check if p_true available |
| `compute_parameter_recovery_stats(dir)` | Compute recovery statistics |
| `generate_parameter_recovery_table(dir)` | Pretty-print recovery table |
| `param_distance(p_found, p_true)` | Euclidean distance |
| `load_experiment_config(dir)` | Load experiment config JSON |
| `load_critical_points_for_degree(dir, degree)` | Load points for specific degree |

### Recovery Statistics Fields

```julia
struct ParameterRecoveryStats
    min_distance::Float64
    mean_distance::Float64
    max_distance::Float64
    best_point_idx::Int
    best_point::Vector{Float64}
    n_points::Int
    p_true::Vector{Float64}
end
```

## Troubleshooting

### "No ground truth available"

The experiment config doesn't have `p_true`:

```julia
# Check config file
config = load_experiment_config(experiment_dir)
println(keys(config))

# p_true should be set in experiment setup:
# experiment_config = Dict("p_true" => [0.5, 0.6, 0.4, 0.8], ...)
```

### Large recovery error despite good L2

This can happen when:
1. Multiple minima exist (found a different one)
2. The objective is flat near the minimum
3. Polynomial approximation is good but critical points are inaccurate

**Solutions:**
- Use refinement to improve critical point accuracy
- Check landscape fidelity
- Reduce domain size to focus on true minimum

## See Also

- [Critical Point Refinement](refinement.md) - Improve critical point accuracy
- [Quality Diagnostics](quality_diagnostics.md) - L2 quality assessment
- [Campaign Analysis](campaign_analysis.md) - Multi-experiment analysis
- [API Reference](api_reference.md) - Full function documentation
