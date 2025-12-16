# API Reference

Complete function reference for GlobtimPostProcessing.jl.

## Refinement API

Functions for improving critical point accuracy using local optimization.

```@docs
refine_experiment_results
refine_critical_points
refine_critical_point
RefinementConfig
ode_refinement_config
RefinedExperimentResult
RefinementResult
```

### Refinement Functions

| Function | Description |
|----------|-------------|
| `refine_experiment_results(dir, objective)` | Main refinement workflow |
| `refine_critical_points(raw_result, objective)` | Refine from result object |
| `refine_critical_point(objective, point)` | Single point refinement |
| `refine_critical_points_batch(objective, points)` | Batch refinement |

### Configuration

| Function/Type | Description |
|---------------|-------------|
| `RefinementConfig()` | Configuration struct with defaults |
| `ode_refinement_config()` | ODE-optimized preset (longer timeouts, finite differences) |

### Configuration Options

```julia
RefinementConfig(;
    method = NelderMead(),        # Optim.jl optimizer
    max_time_per_point = 30.0,    # Timeout per point (seconds)
    f_abstol = 1e-8,              # Function value tolerance
    x_abstol = 1e-8,              # Parameter tolerance
    max_iterations = 1000,        # Max iterations per point
    show_progress = true,         # Show progress bar
    gradient_tolerance = 1e-6,    # Gradient norm tolerance
    gradient_method = :forwarddiff  # :forwarddiff or :finitediff
)
```

## Gradient Validation API

Functions for verifying critical points satisfy ||∇f(x*)|| ≈ 0.

```@docs
validate_critical_points
compute_gradient_norms
compute_gradient_norm
add_gradient_validation!
GradientValidationResult
```

### Functions

| Function | Description |
|----------|-------------|
| `validate_critical_points(points, objective)` | Validate batch of points |
| `compute_gradient_norms(points, objective)` | Compute ||∇f|| for all points |
| `compute_gradient_norm(objective, point)` | Compute ||∇f|| for single point |
| `add_gradient_validation!(df, objective)` | Add validation columns to DataFrame |

### GradientValidationResult Fields

```julia
struct GradientValidationResult
    norms::Vector{Float64}      # ||∇f(x)|| for each point
    valid::Vector{Bool}         # Which points pass tolerance
    n_valid::Int                # Count of valid points
    mean_norm::Float64          # Mean gradient norm
    max_norm::Float64           # Maximum gradient norm
    tolerance::Float64          # Tolerance used
end
```

## Quality Diagnostics API

Functions for assessing experiment quality.

```@docs
load_quality_thresholds
check_l2_quality
detect_stagnation
check_objective_distribution_quality
StagnationResult
ObjectiveDistributionResult
```

### Functions

| Function | Description |
|----------|-------------|
| `check_l2_quality(dir)` | L2 approximation quality assessment |
| `detect_stagnation(dir)` | Convergence stagnation detection |
| `check_objective_distribution_quality(dir)` | Outlier detection in objective values |
| `load_quality_thresholds()` | Load threshold configuration |

### Quality Grades

L2 quality returns one of:
- `:excellent` - L2 < 0.5 * threshold
- `:good` - L2 < 1.0 * threshold
- `:fair` - L2 < 2.0 * threshold
- `:poor` - L2 >= 2.0 * threshold

## Parameter Recovery API

Functions for comparing found parameters to ground truth.

```@docs
has_ground_truth
compute_parameter_recovery_stats
generate_parameter_recovery_table
param_distance
load_experiment_config
load_critical_points_for_degree
```

### Functions

| Function | Description |
|----------|-------------|
| `has_ground_truth(dir)` | Check if p_true available in config |
| `compute_parameter_recovery_stats(dir)` | Compute recovery statistics |
| `generate_parameter_recovery_table(dir)` | Pretty-printed recovery table |
| `param_distance(p_found, p_true)` | Euclidean distance between parameters |

## Data Loading API

Functions for loading experiment and campaign results.

```@docs
load_experiment_results
load_campaign_results
load_raw_critical_points
ExperimentResult
CampaignResults
RawCriticalPointsData
```

### Functions

| Function | Description |
|----------|-------------|
| `load_experiment_results(dir)` | Load single experiment |
| `load_campaign_results(dir)` | Load campaign (multiple experiments) |
| `load_raw_critical_points(dir)` | Load raw CSV critical points |

### ExperimentResult Fields

```julia
struct ExperimentResult
    experiment_id::String
    metadata::Dict{String, Any}
    enabled_tracking::Vector{String}
    tracking_capabilities::Vector{String}
    critical_points::Union{DataFrame, Nothing}
    performance_metrics::Union{Dict, Nothing}
    tolerance_validation::Union{Dict, Nothing}
    source_path::String
end
```

### CampaignResults Fields

```julia
struct CampaignResults
    campaign_id::String
    experiments::Vector{ExperimentResult}
    campaign_metadata::Dict{String, Any}
    collection_timestamp::DateTime
end
```

## Campaign Analysis API

Functions for analyzing multiple experiments.

```@docs
analyze_campaign
aggregate_campaign_statistics
batch_analyze_campaign
load_campaign_with_progress
```

### Functions

| Function | Description |
|----------|-------------|
| `analyze_campaign(campaign)` | Compute campaign-level statistics |
| `aggregate_campaign_statistics(campaign)` | Aggregate across experiments |
| `batch_analyze_campaign(campaign)` | Batch analysis with progress |

## Statistics API

Functions for computing experiment statistics.

```@docs
compute_statistics
compute_statistics_for_label
```

### Functions

| Function | Description |
|----------|-------------|
| `compute_statistics(result)` | Compute statistics for experiment |
| `compute_statistics_for_label(result, label)` | Compute for specific tracking label |

## Report Generation API

Functions for generating text reports.

```@docs
generate_report
generate_campaign_report
save_report
generate_and_save_report
save_campaign_report
```

### Functions

| Function | Description |
|----------|-------------|
| `generate_report(result, stats)` | Generate text report |
| `generate_campaign_report(campaign, stats)` | Generate campaign report |
| `save_report(report, path)` | Save report to file |

## Table Formatting API

Functions for terminal-friendly table output.

```@docs
format_metrics_table
format_compact_summary
format_grouped_metrics
print_refinement_summary
print_comparison_table
```

### Functions

| Function | Description |
|----------|-------------|
| `format_metrics_table(data)` | Format data as table |
| `format_compact_summary(data)` | Compact summary format |
| `print_refinement_summary(result)` | Print refinement summary |
| `print_comparison_table(result)` | Print raw vs refined table |

## Critical Point Classification API

Functions for classifying critical points using Hessian eigenvalues.

```@docs
classify_critical_point
classify_all_critical_points!
count_classifications
find_distinct_local_minima
get_classification_summary
```

### Functions

| Function | Description |
|----------|-------------|
| `classify_critical_point(hessian)` | Classify single point |
| `classify_all_critical_points!(df)` | Add classification column to DataFrame |
| `count_classifications(df)` | Count each classification type |
| `find_distinct_local_minima(df)` | Find unique local minima |

### Classifications

Returns one of:
- `"minimum"` - All eigenvalues positive
- `"maximum"` - All eigenvalues negative
- `"saddle"` - Mixed signs
- `"degenerate"` - Has zero eigenvalues

## Landscape Fidelity API

Functions for assessing polynomial vs objective landscape correspondence.

```@docs
check_objective_proximity
estimate_basin_radius
check_hessian_basin
assess_landscape_fidelity
batch_assess_fidelity
ObjectiveProximityResult
HessianBasinResult
LandscapeFidelityResult
```

### Functions

| Function | Description |
|----------|-------------|
| `check_objective_proximity(x_star, x_min, objective)` | Check if f(x*) ≈ f(x_min) |
| `check_hessian_basin(x_star, x_min, objective, H)` | Check if x* in basin of x_min |
| `assess_landscape_fidelity(x_star, x_min, objective)` | Composite assessment |
| `batch_assess_fidelity(df, refined_points, objective)` | Batch assessment |

## I/O Functions

```@docs
save_refined_results
```

### Output Files

| File | Description |
|------|-------------|
| `critical_points_refined_deg_X.csv` | Refined coordinates |
| `refinement_comparison_deg_X.csv` | Raw vs refined comparison |
| `refinement_summary_deg_X.json` | Statistics and timing |
