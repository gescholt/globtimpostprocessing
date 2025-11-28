# GlobtimPostProcessing.jl

Data analysis and reporting engine for GlobTim experiment results. This package loads, analyzes, refines, and summarizes experimental results from `globtimcore`.

> **Note**: For visualization/plotting, use the separate `globtimplots` package.

## Features

- **Critical Point Refinement**: Improve numerical accuracy of critical points using local optimization
- **Gradient Validation**: Verify critical points satisfy ||∇f(x*)|| ≈ 0
- **Quality Diagnostics**: L2 error assessment, stagnation detection, distribution analysis
- **Parameter Recovery**: Measure distance to ground truth parameters
- **Campaign Analysis**: Aggregate and compare results across multiple experiments
- **Label-Driven Processing**: Automatically discovers available data from experiment metadata

## Installation

GlobtimPostProcessing is **not registered in Julia General**. Set up the entire GlobalOptim ecosystem:

```bash
# Clone the setup repository
git clone git@git.mpi-cbg.de:globaloptim/setup.git GlobalOptim
cd GlobalOptim

# Run automated setup (develops all packages)
julia setup_globaloptim.jl
```

### Manual Development (Alternative)

```julia
using Pkg
Pkg.develop(path="/path/to/GlobalOptim/globtimpostprocessing")
```

## Quick Start

### Refine Critical Points

The primary workflow: load raw critical points from `globtimcore` and refine them.

```julia
using GlobtimPostProcessing

# Define your objective function
function my_objective(p::Vector{Float64})
    # Your cost function here
    return cost
end

# Refine critical points from experiment output
refined = refine_experiment_results(
    "path/to/experiment_dir",
    my_objective
)

# Access results
println("Converged: $(refined.n_converged)/$(refined.n_raw)")
println("Best value: $(refined.best_refined_value)")

# Best parameter estimate
best_params = refined.refined_points[refined.best_refined_idx]
```

### Use ODE-Specific Configuration

For stiff ODE problems, use the preset configuration:

```julia
# Longer timeouts, robust mode for ODE objectives
refined = refine_experiment_results(
    experiment_dir,
    ode_objective,
    ode_refinement_config()
)
```

### Validate Gradient Norms

Verify that found critical points actually have zero gradient:

```julia
# Automatic: gradient validation runs automatically in refine_experiment_results()
# Results are in the printed summary and saved to CSV/JSON

# Manual: validate points directly
result = validate_critical_points(points, objective_func; tolerance=1e-6)
println("Valid critical points: $(result.n_valid)/$(length(points))")
println("Mean gradient norm: $(result.mean_norm)")
```

### Quality Diagnostics

Assess experiment quality:

```julia
# L2 approximation quality (dimension-aware grading)
l2_result = check_l2_quality(experiment_dir)
println("L2 Grade: $(l2_result.grade)")  # :excellent, :good, :acceptable, :poor

# Detect convergence stagnation
stagnation = detect_stagnation(experiment_dir)
if stagnation.detected
    println("Stagnation at degree $(stagnation.stagnation_degree)")
end

# Objective distribution analysis
dist_result = check_objective_distribution_quality(experiment_dir)
println("Outliers: $(dist_result.n_outliers)")
```

### Parameter Recovery Analysis

If ground truth parameters are available:

```julia
if has_ground_truth(experiment_dir)
    stats = compute_parameter_recovery_stats(experiment_dir)
    println("Best recovery error: $(stats.min_distance)")

    # Pretty table output
    generate_parameter_recovery_table(experiment_dir)
end
```

### Load and Analyze Experiments

```julia
# Load single experiment
result = load_experiment_results("path/to/experiment_dir")
stats = compute_statistics(result)

# Load campaign (multiple experiments)
campaign = load_campaign_results("path/to/campaign_dir")
campaign_stats = analyze_campaign(campaign)
```

## Output Files

When running `refine_experiment_results()`, these files are created:

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
- `gradient_norm`, `gradient_valid` — Gradient validation

### JSON Summary

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

## Architecture

```
globtimcore                    globtimpostprocessing           globtimplots
(runs experiments)      →      (analyzes results)        →     (visualizes)

Exports CSV/JSON               Loads, refines, reports         Creates plots
```

This package is the **analysis layer** — it processes data but does not create visualizations. For plots, use `globtimplots`:

```julia
using GlobtimPostProcessing
using GlobtimPlots

# Analyze
result = load_experiment_results(exp_dir)
stats = compute_statistics(result)

# Visualize (in globtimplots)
fig = create_experiment_plots(result, stats)
save_plot(fig, "analysis.png")
```

## API Reference

### Refinement

| Function | Description |
|----------|-------------|
| `refine_experiment_results(dir, objective)` | Main refinement workflow |
| `refine_critical_points(raw_result, objective)` | Refine from result object |
| `refine_critical_point(objective, point)` | Single point refinement |
| `RefinementConfig()` | Configuration struct |
| `ode_refinement_config()` | ODE-optimized preset |

### Gradient Validation

| Function | Description |
|----------|-------------|
| `validate_critical_points(points, objective)` | Validate batch of points |
| `compute_gradient_norms(points, objective)` | Compute ||∇f|| for points |
| `add_gradient_validation!(df, objective)` | Add validation to DataFrame |

### Quality Diagnostics

| Function | Description |
|----------|-------------|
| `check_l2_quality(dir)` | L2 approximation assessment |
| `detect_stagnation(dir)` | Convergence stagnation detection |
| `check_objective_distribution_quality(dir)` | Outlier detection |

### Parameter Recovery

| Function | Description |
|----------|-------------|
| `has_ground_truth(dir)` | Check if p_true available |
| `compute_parameter_recovery_stats(dir)` | Recovery statistics |
| `generate_parameter_recovery_table(dir)` | Pretty-printed table |

### Data Loading

| Function | Description |
|----------|-------------|
| `load_experiment_results(dir)` | Load single experiment |
| `load_campaign_results(dir)` | Load experiment campaign |
| `load_raw_critical_points(dir)` | Load raw CSV points |

## Development

### Running Tests

```julia
using Pkg
Pkg.activate(".")
Pkg.test()
```

### Project Structure

```
src/
├── GlobtimPostProcessing.jl   # Main module
├── ResultsLoader.jl           # Data loading
├── StatisticsCompute.jl       # Statistics computation
├── QualityDiagnostics.jl      # Quality assessment
├── ParameterRecovery.jl       # Parameter recovery analysis
├── CriticalPointClassification.jl
├── LandscapeFidelity.jl
└── refinement/
    ├── api.jl                 # High-level refinement API
    ├── core_refinement.jl     # Optim.jl integration
    ├── gradient_validation.jl # Gradient norm validation
    ├── config.jl              # Configuration structs
    └── io.jl                  # CSV/JSON I/O
```

## License

GPL-3.0

## Authors

- Georgy Scholten
