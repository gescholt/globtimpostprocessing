# Getting Started

This guide walks you through the basic workflow of using GlobtimPostProcessing.jl to analyze experiment results from [Globtim.jl](https://gescholt.github.io/Globtim.jl/stable/).

## Prerequisites

Before using this package, you need:

1. **Experiment output** from `globtimcore` containing:
   - `critical_points_deg_*.csv` - Critical point coordinates
   - `experiment_config.json` - Experiment configuration
   - `l2_errors_*.csv` (optional) - L2 approximation errors

2. **Your objective function** - The same function used to generate the experiment

## Installation

```julia
using Pkg
Pkg.add("GlobtimPostProcessing")
```

## Basic Workflow

The typical workflow consists of four steps:

### Step 1: Load Experiment Results

```julia
using GlobtimPostProcessing

# Load a single experiment
result = load_experiment_results("path/to/experiment_dir")

# View available data
println("Experiment ID: \$(result.experiment_id)")
println("Tracking labels: \$(result.enabled_tracking)")
println("Critical points: \$(size(result.critical_points))")
```

### Step 2: Refine Critical Points

Critical points from polynomial approximation can be refined using local optimization:

```julia
# Define your objective function
function my_objective(p::Vector{Float64})
    # Your cost function - must match what was used in globtimcore
    return compute_cost(p)
end

# Refine critical points
refined = refine_experiment_results(
    "path/to/experiment_dir",
    my_objective
)

# Check refinement results
println("Converged: \$(refined.n_converged)/\$(refined.n_raw)")
println("Best refined value: \$(refined.best_refined_value)")
```

### Step 3: Validate and Analyze

```julia
# Quality diagnostics
l2_result = check_l2_quality("path/to/experiment_dir")
println("L2 Grade: \$(l2_result.grade)")  # :excellent, :good, :acceptable, :poor

# Check for stagnation
stagnation = detect_stagnation("path/to/experiment_dir")
if stagnation.detected
    println("Stagnation at degree \$(stagnation.stagnation_degree)")
end

# Parameter recovery (if ground truth available)
if has_ground_truth("path/to/experiment_dir")
    stats = compute_parameter_recovery_stats("path/to/experiment_dir")
    println("Best recovery error: \$(stats.min_distance)")
end
```

### Step 4: Generate Reports

```julia
# Compute statistics
stats = compute_statistics(result)

# Generate text report
report = generate_report(result, stats)
save_report(report, "analysis_report.txt")

# Pretty-print parameter recovery table
generate_parameter_recovery_table("path/to/experiment_dir")
```

## Output Files

When running `refine_experiment_results()`, these files are created in the experiment directory:

| File | Description |
|------|-------------|
| `critical_points_refined_deg_X.csv` | Refined critical point coordinates |
| `refinement_comparison_deg_X.csv` | Raw vs refined comparison with diagnostics |
| `refinement_summary_deg_X.json` | Statistics, timing, gradient validation |

### CSV Columns (refinement_comparison)

- `raw_dim1..N`, `refined_dim1..N` — Point coordinates
- `raw_value`, `refined_value` — Objective values
- `converged`, `iterations` — Convergence status
- `f_calls`, `g_calls`, `time_elapsed` — Performance metrics
- `convergence_reason` — Why optimization stopped
- `gradient_norm`, `gradient_valid` — Gradient validation results

### JSON Summary Structure

```json
{
  "n_converged": 15,
  "convergence_rate": 0.83,
  "best_refined_value": 1.23e-12,
  "convergence_breakdown": {"g_tol": 10, "f_tol": 3, "timeout": 2},
  "gradient_validation": {
    "n_valid": 14,
    "mean_norm": 2.34e-8,
    "validation_rate": 0.93
  }
}
```

## ODE-Specific Configuration

For stiff ODE parameter estimation problems, use the preset configuration:

```julia
# Longer timeouts, robust mode for ODE objectives
refined = refine_experiment_results(
    experiment_dir,
    ode_objective,
    ode_refinement_config()
)
```

This configuration uses:
- Extended timeout (60s per point)
- Finite differences for gradients (instead of ForwardDiff)
- Increased iteration limits
- Robust convergence criteria

## Campaign Analysis

For analyzing multiple experiments together:

```julia
# Load campaign (directory containing multiple experiment directories)
campaign = load_campaign_results("path/to/campaign_dir")

# Analyze campaign
campaign_stats = analyze_campaign(campaign)

# Generate campaign report
generate_campaign_report(campaign, campaign_stats)
```

## Next Steps

- [Critical Point Refinement](refinement.md) - Detailed refinement options
- [Quality Diagnostics](quality_diagnostics.md) - L2 quality assessment
- [Parameter Recovery](parameter_recovery.md) - Ground truth comparison
- [Examples](workflow_examples.md) - Complete workflow examples
- [API Reference](api_reference.md) - Full function reference

## Troubleshooting

### Common Issues

**"No critical points found"**
- Check that the experiment directory contains `critical_points_deg_*.csv` files
- Verify the path is correct

**"Objective function returns NaN"**
- Ensure your objective function handles all parameter values
- Check for division by zero or invalid ODE solutions

**"Low convergence rate"**
- Try `ode_refinement_config()` for ODE problems
- Increase `max_iterations` in `RefinementConfig`
- Check if critical points are far from true minima

For more help, see the [troubleshooting guide](https://git.mpi-cbg.de/globaloptim/globtimpostprocessing/-/issues) or open an issue.
