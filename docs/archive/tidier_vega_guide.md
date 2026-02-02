# VegaLite + Tidier.jl Visualization Guide

## Overview

GlobtimPostProcessing now includes a comprehensive suite of interactive visualizations powered by **VegaLite.jl** and expressive data transformations using **Tidier.jl**.

### Key Features

- **Interactive dashboards** with linked selections and dynamic filtering
- **Tidier.jl pipelines** for elegant data transformation using dplyr-like syntax
- **Multi-view coordinated visualizations** for exploring complex relationships
- **Statistical analysis** built directly into the visualization pipeline
- **Publication-ready graphics** with customizable themes

## Architecture

### Data Flow

```
ExperimentResults → Tidier Transform → Tidy DataFrame → VegaLite Spec → Interactive Viz
```

1. **Campaign Data**: Raw experiment results from globtimcore
2. **Tidier Transformations**: Data cleaning, aggregation, derived metrics
3. **Tidy DataFrame**: Long-format data optimized for visualization
4. **VegaLite Specification**: Declarative visualization grammar
5. **Browser Rendering**: Interactive HTML visualization

### Module Structure

```
globtimpostprocessing/
├── src/
│   ├── TidierTransforms.jl    # Data transformation pipelines
│   └── VegaPlotting.jl         # VegaLite visualization functions
└── examples/
    ├── demo_vega_explorer.jl   # Basic interactive explorer
    └── demo_tidier_vega_suite.jl # Complete visualization suite
```

## Data Transformations with Tidier.jl

### Core Transformation Functions

#### `campaign_to_tidy_dataframe(campaign, campaign_stats)`

Converts nested campaign results to tidy (long-form) DataFrame with derived metrics.

**Output columns:**
- `experiment_id`: Experiment identifier
- `domain_size`, `GN`: Parameter metadata
- `degree`: Polynomial degree
- `l2_error`: Approximation error
- `param_recovery_error`: Parameter recovery error
- `convergence_rate`: Error reduction per degree
- `error_category`: Categorical quality classification
- `domain_category`: Size classification

**Example:**
```julia
df_tidy = campaign_to_tidy_dataframe(campaign, campaign_stats)

# Now in tidy format for easy analysis
println("Total rows: $(nrow(df_tidy))")
println("Columns: $(names(df_tidy))")
```

#### `compute_convergence_analysis(df)`

Analyzes convergence behavior across polynomial degrees.

**Computes:**
- Error reduction ratios
- Effective convergence rates
- Convergence quality classifications

**Example:**
```julia
df_convergence = @chain df_tidy begin
    compute_convergence_analysis()
    @filter(convergence_quality == "excellent")
end
```

#### `compute_parameter_sensitivity(df)`

Aggregates metrics by parameter values to identify sensitivities.

**Example:**
```julia
df_sensitivity = compute_parameter_sensitivity(df_tidy)

# Shows how L2 error varies with domain_size at each degree
```

#### `compute_efficiency_metrics(df)`

Computes computational efficiency: error reduction per computational cost.

**Example:**
```julia
df_efficiency = @chain df_tidy begin
    @filter(!ismissing(total_time))
    compute_efficiency_metrics()
end
```

### Advanced Transformations

#### `pivot_metrics_longer(df)`

Converts multiple metric columns to long format for faceted plots.

**Example:**
```julia
df_long = pivot_metrics_longer(df_tidy)
# Now can facet by metric_name and metric_category
```

#### `add_comparison_baseline(df, baseline_id)`

Adds columns comparing each experiment to a baseline.

**Example:**
```julia
df_compared = add_comparison_baseline(df_tidy, "exp_1")
# Shows l2_improvement_ratio for each experiment vs baseline
```

#### `annotate_outliers(df, metric; threshold=3.0)`

Identifies statistical outliers using z-score method.

**Example:**
```julia
df_outliers = annotate_outliers(df_tidy, :l2_error, threshold=2.5)
# Adds is_outlier and z_score columns
```

## VegaLite Visualizations

### 1. Interactive Campaign Explorer

**Function:** `create_interactive_campaign_explorer(campaign, campaign_stats)`

Multi-view dashboard with linked selection:
- Bar chart selector (critical points per experiment)
- L2 convergence plot (filtered by selection)
- Parameter recovery plot (filtered by selection)

**Features:**
- Click experiments to highlight
- Toggle selection on/off
- Hover for detailed tooltips
- Color encoding by domain size

**Usage:**
```julia
viz = create_interactive_campaign_explorer(campaign, campaign_stats)
display(viz)  # Opens in browser
```

### 2. Convergence Dashboard

**Function:** `create_convergence_dashboard(campaign, campaign_stats)`

Comprehensive convergence analysis:
- Quality distribution histogram
- Effective convergence scatter plot
- Initial vs final error trajectories

**Uses Tidier:** `compute_convergence_analysis()`

**Best for:**
- Comparing convergence behavior across parameters
- Identifying optimal configurations
- Understanding error reduction patterns

**Usage:**
```julia
viz = create_convergence_dashboard(campaign, campaign_stats)
display(viz)
```

### 3. Parameter Sensitivity Plot

**Function:** `create_parameter_sensitivity_plot(campaign, campaign_stats)`

Shows how varying parameters affect metrics:
- Line plot: L2 error vs domain size (by degree)
- Error bars showing variability

**Uses Tidier:** `compute_parameter_sensitivity()`

**Best for:**
- Understanding parameter effects
- Identifying sensitive parameters
- Planning future experiments

**Usage:**
```julia
viz = create_parameter_sensitivity_plot(campaign, campaign_stats)
display(viz)
```

### 4. Multi-Metric Comparison

**Function:** `create_multi_metric_comparison(campaign, campaign_stats)`

Faceted comparison of multiple metrics:
- L2 approximation error
- Parameter recovery error
- Numerical stability (condition numbers)

**Uses Tidier:** `pivot_metrics_longer()`

**Features:**
- Independent y-axis scales per facet
- Legend-based filtering (click to highlight)
- Unified x-axis (polynomial degree)

**Usage:**
```julia
viz = create_multi_metric_comparison(campaign, campaign_stats)
display(viz)
```

### 5. Efficiency Analysis

**Function:** `create_efficiency_analysis(campaign, campaign_stats)`

Computational efficiency visualization:
- Error-time efficiency vs degree
- Complexity scaling vs error

**Uses Tidier:** `compute_efficiency_metrics()`

**Requires:** Timing data in experiment metadata

**Best for:**
- Understanding computational tradeoffs
- Identifying most efficient configurations
- Planning resource allocation

**Usage:**
```julia
viz = create_efficiency_analysis(campaign, campaign_stats)
display(viz)
```

### 6. Outlier Detection

**Function:** `create_outlier_detection_plot(campaign, campaign_stats; metric=:l2_error)`

Statistical outlier identification:
- Scatter plot with outliers highlighted
- Z-score distribution histogram

**Uses Tidier:** `annotate_outliers()`

**Parameters:**
- `metric`: Which metric to analyze (`:l2_error`, `:param_recovery_error`, etc.)
- Default threshold: 2.5 standard deviations

**Usage:**
```julia
viz = create_outlier_detection_plot(campaign, campaign_stats, metric=:l2_error)
display(viz)
```

### 7. Baseline Comparison

**Function:** `create_baseline_comparison(campaign, campaign_stats, baseline_id)`

Relative performance vs baseline experiment:
- Heatmap: improvement ratio by degree
- Bar chart: mean improvement per experiment

**Uses Tidier:** `add_comparison_baseline()`

**Color scheme:**
- Green: Better than baseline (ratio > 1)
- Yellow: Equal to baseline (ratio ≈ 1)
- Red: Worse than baseline (ratio < 1)

**Usage:**
```julia
baseline_id = "exp_1"
viz = create_baseline_comparison(campaign, campaign_stats, baseline_id)
display(viz)
```

## Complete Workflow Example

```julia
using GlobtimPostProcessing

# 1. Load campaign
campaign = load_campaign_results("path/to/campaign")

# 2. Compute statistics
campaign_stats = Dict()
for exp in campaign.experiments
    campaign_stats[exp.experiment_id] = compute_statistics(exp)
end

# 3. Create tidy DataFrame for custom analysis
df_tidy = campaign_to_tidy_dataframe(campaign, campaign_stats)

# 4. Custom Tidier analysis
best_experiments = @chain df_tidy begin
    @group_by(experiment_id)
    @summarize(
        mean_error = mean(l2_error),
        convergence = mean(skipmissing(convergence_rate))
    )
    @filter(mean_error < 1e-3)
    @arrange(mean_error)
end

# 5. Create visualizations
viz1 = create_convergence_dashboard(campaign, campaign_stats)
viz2 = create_parameter_sensitivity_plot(campaign, campaign_stats)
viz3 = create_multi_metric_comparison(campaign, campaign_stats)

# 6. Display
display(viz1)
display(viz2)
display(viz3)

# 7. Save DataFrame for further analysis
using CSV
CSV.write("campaign_analysis.csv", df_tidy)
```

## Tidier.jl Syntax Guide

For users new to Tidier.jl, here's a quick reference:

### Common Operations

```julia
using Tidier

# Filter rows
@chain df begin
    @filter(l2_error < 1e-3)
    @filter(!ismissing(param_recovery_error))
end

# Select columns
@chain df begin
    @select(experiment_id, degree, l2_error)
end

# Create new columns
@chain df begin
    @mutate(
        log_error = log10(l2_error),
        normalized = l2_error / maximum(l2_error)
    )
end

# Group and summarize
@chain df begin
    @group_by(domain_size, degree)
    @summarize(
        mean_error = mean(l2_error),
        std_error = std(l2_error),
        count = n()
    )
    @ungroup()
end

# Sort
@chain df begin
    @arrange(domain_size, degree)
    @arrange(desc(l2_error))  # Descending
end

# Slice rows
@chain df begin
    @slice(1:10)  # First 10 rows
end
```

## Tips and Best Practices

### 1. Data Quality

Always check for missing values before visualization:

```julia
df_clean = @chain df_tidy begin
    @filter(!ismissing(l2_error))
    @filter(!ismissing(param_recovery_error))
end
```

### 2. Performance

For large campaigns, use progressive loading:

```julia
# Load with progress callback
campaign = load_campaign_with_progress("path/to/campaign")
```

### 3. Custom Color Schemes

VegaLite supports various color schemes:
- `viridis`, `plasma`, `inferno` (sequential)
- `redyellowgreen`, `blueorange` (diverging)
- `category10`, `category20` (categorical)

### 4. Saving Visualizations

```julia
using VegaLite

viz = create_convergence_dashboard(campaign, campaign_stats)

# Save as HTML (interactive)
save("analysis.html", viz)

# Save as PNG (static)
save("analysis.png", viz)

# Save as SVG (vector)
save("analysis.svg", viz)
```

### 5. Combining with Custom Plots

You can extract the tidy DataFrame and create custom VegaLite plots:

```julia
df_tidy = campaign_to_tidy_dataframe(campaign, campaign_stats)

# Custom VegaLite specification
custom_viz = @vlplot(
    data = df_tidy,
    mark = :point,
    encoding = {
        x = :degree,
        y = {:l2_error, scale = {type = :log}},
        color = :experiment_id
    }
)
```

## Troubleshooting

### Issue: "No data available to plot"

**Cause:** Campaign statistics may not contain required metrics.

**Solution:** Check which tracking labels are enabled:
```julia
for exp in campaign.experiments
    println("$(exp.experiment_id): $(exp.enabled_tracking)")
end
```

### Issue: "No timing data available"

**Cause:** Efficiency analysis requires timing metadata.

**Solution:** Ensure experiments track timing:
```julia
# Check if timing data exists
for exp in campaign.experiments
    has_timing = haskey(exp.metadata, "total_time")
    println("$(exp.experiment_id): timing=$has_timing")
end
```

### Issue: Visualizations not opening in browser

**Solution:** Set browser manually:
```julia
ENV["BROWSER"] = "firefox"  # or "chrome", "safari"
```

## Further Reading

- [VegaLite.jl Documentation](https://www.queryverse.org/VegaLite.jl/stable/)
- [Tidier.jl Documentation](https://tidierorg.github.io/Tidier.jl/latest/)
- [Vega-Lite Grammar](https://vega.github.io/vega-lite/)
- GlobtimCore tracking labels documentation

## Examples

See the `examples/` directory for complete working examples:
- `demo_vega_explorer.jl`: Basic interactive explorer
- `demo_tidier_vega_suite.jl`: Complete visualization suite with menu

Run with:
```bash
julia --project=. examples/demo_tidier_vega_suite.jl path/to/campaign
```
