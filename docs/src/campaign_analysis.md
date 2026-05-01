# Campaign Analysis

This guide covers analyzing multiple experiments together as a campaign.

## Overview

A **campaign** is a collection of related experiments, typically:
- Parameter sweeps (varying domain size, polynomial degree, etc.)
- Multiple runs with different random seeds
- Comparisons across different test functions

Campaign analysis aggregates results to identify trends and draw conclusions.

## Quick Start

```julia
using GlobtimPostProcessing

# Load campaign (directory containing experiment subdirectories)
campaign = load_campaign_results("path/to/campaign_dir")

println("Campaign: \$(campaign.campaign_id)")
println("Experiments: \$(length(campaign.experiments))")

# Analyze
campaign_stats = analyze_campaign(campaign)

# Generate report
generate_campaign_report(campaign, campaign_stats)
```

## Loading Campaigns

### Directory Structure

Expected structure:
```
campaign_dir/
├── experiment_001/
│   ├── critical_points_deg_*.csv
│   ├── experiment_config.json
│   └── l2_errors_*.csv
├── experiment_002/
│   ├── critical_points_deg_*.csv
│   ├── experiment_config.json
│   └── l2_errors_*.csv
└── experiment_003/
    └── ...
```

### Loading

```julia
# Load all experiments in directory
campaign = load_campaign_results("path/to/campaign_dir")

# Access individual experiments
for exp in campaign.experiments
    println("Experiment: \$(exp.experiment_id)")
    println("  Path: \$(exp.source_path)")
    println("  Critical points: \$(size(exp.critical_points))")
end
```

### With Progress

```julia
# Show progress bar for large campaigns
campaign = load_campaign_with_progress("path/to/campaign_dir")
```

## Computing Campaign Statistics

```julia
campaign_stats = analyze_campaign(campaign)

# Available statistics
println("Mean L2 error: \$(campaign_stats.mean_l2)")
println("Best L2 error: \$(campaign_stats.min_l2)")
println("Mean critical points: \$(campaign_stats.mean_n_critical)")
println("Total experiments: \$(campaign_stats.n_experiments)")
```

### Aggregation by Parameter

```julia
# Group by domain size
stats_by_domain = aggregate_campaign_statistics(
    campaign,
    group_by = :domain_range
)

for (domain, stats) in stats_by_domain
    println("Domain \$domain:")
    println("  Mean L2: \$(stats.mean_l2)")
    println("  Mean recovery: \$(stats.mean_recovery)")
end
```

## Batch Analysis

### Batch Processing

```julia
# Process all experiments with progress
results = batch_analyze_campaign(campaign) do exp
    # Custom analysis per experiment
    stats = compute_statistics(exp)
    l2 = check_l2_quality(exp.source_path)
    return (l2_grade = l2.grade, n_points = size(exp.critical_points, 1))
end

# Results is a vector of named tuples
for (exp, result) in zip(campaign.experiments, results)
    println("\$(exp.experiment_id): \$(result.l2_grade), \$(result.n_points) points")
end
```

### With Progress Bar

```julia
results = batch_analyze_campaign_with_progress(campaign) do exp
    refine_experiment_results(exp.source_path, objective)
end
```

## Campaign Reports

### Text Report

```julia
report = generate_campaign_report(campaign, campaign_stats)
save_campaign_report(report, "campaign_analysis.txt")
```

### Summary Table

```julia
using DataFrames

# Build summary DataFrame
summary = DataFrame(
    experiment_id = String[],
    domain_range = Float64[],
    degree = Int[],
    l2_error = Float64[],
    n_critical = Int[]
)

for exp in campaign.experiments
    config = load_experiment_config(exp.source_path)
    push!(summary, (
        experiment_id = exp.experiment_id,
        domain_range = config["domain_range"],
        degree = config["degree_max"],
        l2_error = exp.performance_metrics["l2_error"],
        n_critical = size(exp.critical_points, 1)
    ))
end

# Export
CSV.write("campaign_summary.csv", summary)
```

## Comparing Experiments

### Metrics Comparison

```julia
# Compare specific experiments
exp1 = campaign.experiments[1]
exp2 = campaign.experiments[5]

println("Comparison:")
println("  Experiment 1: \$(exp1.experiment_id)")
println("    L2 error: \$(exp1.performance_metrics["l2_error"])")
println("    Critical points: \$(size(exp1.critical_points, 1))")
println("  Experiment 2: \$(exp2.experiment_id)")
println("    L2 error: \$(exp2.performance_metrics["l2_error"])")
println("    Critical points: \$(size(exp2.critical_points, 1))")
```

### Trend Analysis

```julia
# Analyze trend across domain sizes
using Statistics

domains = Float64[]
l2_errors = Float64[]

for exp in campaign.experiments
    config = load_experiment_config(exp.source_path)
    push!(domains, config["domain_range"])
    push!(l2_errors, exp.performance_metrics["l2_error"])
end

# Correlation
correlation = cor(domains, log10.(l2_errors))
println("Log-linear correlation (domain vs L2): \$correlation")
```

## Common Workflows

### Workflow 1: Parameter Sweep Analysis

```julia
# Analyze domain size sweep
function analyze_domain_sweep(campaign_dir)
    campaign = load_campaign_results(campaign_dir)

    results = DataFrame(
        domain = Float64[],
        mean_l2 = Float64[],
        best_recovery = Float64[]
    )

    # Group by domain
    by_domain = Dict{Float64, Vector}()
    for exp in campaign.experiments
        config = load_experiment_config(exp.source_path)
        domain = config["domain_range"]
        if !haskey(by_domain, domain)
            by_domain[domain] = []
        end
        push!(by_domain[domain], exp)
    end

    # Aggregate
    for (domain, exps) in sort(collect(by_domain))
        l2s = [e.performance_metrics["l2_error"] for e in exps]
        recoveries = Float64[]
        for e in exps
            if has_ground_truth(e.source_path)
                stats = compute_parameter_recovery_stats(e.source_path)
                push!(recoveries, stats.min_distance)
            end
        end

        push!(results, (
            domain = domain,
            mean_l2 = mean(l2s),
            best_recovery = isempty(recoveries) ? NaN : minimum(recoveries)
        ))
    end

    return results
end
```

### Workflow 2: Degree Comparison

```julia
# Compare different polynomial degrees
function compare_degrees(campaign_dir)
    campaign = load_campaign_results(campaign_dir)

    for exp in campaign.experiments
        config = load_experiment_config(exp.source_path)
        println("Degree \$(config["degree_max"]):")

        l2_result = check_l2_quality(exp.source_path)
        println("  L2 Grade: \$(l2_result.grade)")

        if has_ground_truth(exp.source_path)
            recovery = compute_parameter_recovery_stats(exp.source_path)
            println("  Recovery: \$(recovery.min_distance)")
        end
    end
end
```

### Workflow 3: Quality-Gated Analysis

```julia
# Only process high-quality experiments
function analyze_quality_gated(campaign_dir; min_grade=:good)
    campaign = load_campaign_results(campaign_dir)

    passed = ExperimentResult[]
    for exp in campaign.experiments
        l2_result = check_l2_quality(exp.source_path)
        if l2_result.grade in [:excellent, :good]
            push!(passed, exp)
        end
    end

    println("Quality gate: \$(length(passed))/\$(length(campaign.experiments)) passed")

    # Continue analysis with high-quality experiments only
    for exp in passed
        # ... further analysis
    end
end
```

## API Reference

### Types

```julia
struct CampaignResults
    campaign_id::String
    experiments::Vector{ExperimentResult}
    campaign_metadata::Dict{String, Any}
    collection_timestamp::DateTime
end
```

### Functions

| Function | Description |
|----------|-------------|
| `load_campaign_results(dir)` | Load all experiments in directory |
| `load_campaign_with_progress(dir)` | Load with progress bar |
| `analyze_campaign(campaign)` | Compute campaign statistics |
| `aggregate_campaign_statistics(campaign, group_by)` | Aggregate by parameter |
| `batch_analyze_campaign(f, campaign)` | Apply function to all experiments |
| `generate_campaign_report(campaign, stats)` | Generate text report |
| `save_campaign_report(report, path)` | Save report to file |

## Troubleshooting

### "No experiments found"

Check directory structure:
```julia
# List subdirectories
for entry in readdir(campaign_dir)
    path = joinpath(campaign_dir, entry)
    if isdir(path)
        println("Found: \$entry")
        # Check for required files
        has_config = isfile(joinpath(path, "experiment_config.json"))
        has_csv = !isempty(glob("critical_points_*.csv", path))
        println("  Config: \$has_config, CSV: \$has_csv")
    end
end
```

### Memory issues with large campaigns

```julia
# Process in batches
for batch in Iterators.partition(campaign.experiments, 10)
    for exp in batch
        # Process experiment
        # ...
    end
    GC.gc()  # Force garbage collection
end
```

## See Also

- [Getting Started](getting_started.md) - Basic workflow
- [Quality Diagnostics](quality_diagnostics.md) - Quality assessment
- [Parameter Recovery](parameter_recovery.md) - Ground truth comparison
- [API Reference](api_reference.md) - Full function documentation
