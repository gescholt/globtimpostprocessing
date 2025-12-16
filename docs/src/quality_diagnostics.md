# Quality Diagnostics

This guide covers the quality assessment tools in GlobtimPostProcessing.jl for evaluating experiment quality.

## Overview

Quality diagnostics help assess:
- **L2 approximation quality**: How well does the polynomial approximate the objective?
- **Convergence stagnation**: Has the approximation stopped improving with higher degrees?
- **Objective distribution**: Are there outliers or anomalies in critical point values?

## Quick Start

```julia
using GlobtimPostProcessing

experiment_dir = "path/to/experiment"

# L2 approximation quality
l2_result = check_l2_quality(experiment_dir)
println("L2 Grade: \$(l2_result.grade)")

# Stagnation detection
stagnation = detect_stagnation(experiment_dir)
if stagnation.is_stagnant
    println("Stagnation detected at degree \$(stagnation.stagnation_start_degree)")
end

# Objective distribution
dist_result = check_objective_distribution_quality(experiment_dir)
println("Outliers: \$(dist_result.num_outliers)")
```

## L2 Approximation Quality

The L2 norm measures how well the polynomial approximation fits the objective function.

### Usage

```julia
# Load experiment and check quality
l2_result = check_l2_quality(experiment_dir)

println("Grade: \$(l2_result.grade)")       # :excellent, :good, :fair, :poor
println("L2 norm: \$(l2_result.l2_norm)")
println("Dimension: \$(l2_result.dimension)")
```

### Quality Grades

Grades are **dimension-aware** - higher dimensions naturally have higher L2 norms:

| Grade | Meaning |
|-------|---------|
| `:excellent` | L2 < 0.5 * threshold |
| `:good` | L2 < 1.0 * threshold |
| `:fair` | L2 < 2.0 * threshold |
| `:poor` | L2 >= 2.0 * threshold |

### Dimension-Specific Thresholds

Default thresholds in `quality_thresholds.toml`:

```toml
[l2_norm_thresholds]
dim_2 = 0.01
dim_3 = 0.05
dim_4 = 0.10
dim_6 = 0.20
default = 0.15
```

### Custom Thresholds

```julia
# Load custom thresholds
thresholds = load_quality_thresholds("my_thresholds.toml")

# Use with quality check
quality = check_l2_quality(l2_norm, dimension, thresholds)
```

## Stagnation Detection

Detects when polynomial approximation stops improving with higher degrees.

### Usage

```julia
stagnation = detect_stagnation(experiment_dir)

if stagnation.is_stagnant
    println("Stagnation detected!")
    println("Started at degree: \$(stagnation.stagnation_start_degree)")
    println("Consecutive stagnant degrees: \$(stagnation.stagnant_count)")
else
    println("No stagnation - approximation still improving")
end

# View improvement factors between degrees
for (i, factor) in enumerate(stagnation.improvement_factors)
    println("Degree \$(i) -> \$(i+1): \$(round(factor, digits=3))")
end
```

### Detection Criteria

Stagnation is detected when:
1. L2 norm fails to improve by `min_improvement_factor` for consecutive degrees
2. L2 norm is not already below the converged threshold

### Configuration

Default parameters in `quality_thresholds.toml`:

```toml
[convergence]
min_improvement_factor = 0.9      # Must improve by at least 10%
stagnation_tolerance = 3          # Consecutive stagnant degrees
absolute_improvement_threshold = 1e-8  # Below this = converged
```

### StagnationResult Fields

```julia
struct StagnationResult
    is_stagnant::Bool
    stagnation_start_degree::Union{Int, Nothing}
    stagnant_count::Int
    improvement_factors::Vector{Float64}
end
```

## Objective Distribution Quality

Analyzes the distribution of objective values at critical points to detect outliers.

### Usage

```julia
dist_result = check_objective_distribution_quality(experiment_dir)

println("Has outliers: \$(dist_result.has_outliers)")
println("Outlier count: \$(dist_result.num_outliers)")
println("Outlier fraction: \$(round(100*dist_result.outlier_fraction, digits=1))%")
println("Quality: \$(dist_result.quality)")

# Distribution statistics
println("Q1: \$(dist_result.q1)")
println("Q3: \$(dist_result.q3)")
println("IQR: \$(dist_result.iqr)")
```

### Outlier Detection

Uses IQR-based method:
- Lower bound: Q1 - k * IQR
- Upper bound: Q3 + k * IQR

Values outside these bounds are outliers.

### Quality Grades

| Grade | Meaning |
|-------|---------|
| `:good` | Few outliers (below threshold) |
| `:poor` | Many outliers (above threshold) |
| `:insufficient_data` | Not enough points to assess |

### Configuration

```toml
[objective_distribution]
min_points_for_distribution_check = 10
max_outlier_fraction = 0.10
outlier_iqr_multiplier = 1.5
```

### ObjectiveDistributionResult Fields

```julia
struct ObjectiveDistributionResult
    has_outliers::Bool
    num_outliers::Int
    outlier_fraction::Float64
    quality::Symbol
    q1::Float64
    q3::Float64
    iqr::Float64
end
```

## Quality Thresholds Configuration

All thresholds are configurable via `quality_thresholds.toml`.

### Default Location

```julia
# Package default
thresholds = load_quality_thresholds()

# Custom file
thresholds = load_quality_thresholds("/path/to/my_thresholds.toml")
```

### Full Configuration File

```toml
# quality_thresholds.toml

[l2_norm_thresholds]
# Dimension-specific L2 norm thresholds
dim_2 = 0.01
dim_3 = 0.05
dim_4 = 0.10
dim_6 = 0.20
default = 0.15

[parameter_recovery]
# Parameter recovery thresholds
excellent_threshold = 1e-6
good_threshold = 1e-4
acceptable_threshold = 1e-2

[convergence]
# Stagnation detection parameters
min_improvement_factor = 0.9
stagnation_tolerance = 3
absolute_improvement_threshold = 1e-8

[objective_distribution]
# Outlier detection parameters
min_points_for_distribution_check = 10
max_outlier_fraction = 0.10
outlier_iqr_multiplier = 1.5
```

## Combined Quality Assessment

### Example: Full Quality Report

```julia
using GlobtimPostProcessing

function assess_experiment_quality(experiment_dir)
    println("Quality Assessment for: \$experiment_dir")
    println("="^60)

    # L2 Quality
    l2_result = check_l2_quality(experiment_dir)
    println("\nL2 Approximation:")
    println("  Grade: \$(l2_result.grade)")
    println("  L2 norm: \$(l2_result.l2_norm)")

    # Stagnation
    stagnation = detect_stagnation(experiment_dir)
    println("\nConvergence:")
    if stagnation.is_stagnant
        println("  WARNING: Stagnation at degree \$(stagnation.stagnation_start_degree)")
    else
        println("  OK: Approximation still improving")
    end

    # Distribution
    dist = check_objective_distribution_quality(experiment_dir)
    println("\nObjective Distribution:")
    println("  Quality: \$(dist.quality)")
    println("  Outliers: \$(dist.num_outliers) (\$(round(100*dist.outlier_fraction))%)")

    # Summary
    println("\n" * "="^60)
    overall = if l2_result.grade in [:excellent, :good] &&
                 !stagnation.is_stagnant &&
                 dist.quality == :good
        "GOOD"
    else
        "NEEDS ATTENTION"
    end
    println("Overall Assessment: \$overall")
end
```

## Troubleshooting

### Poor L2 Quality

**Possible causes:**
- Polynomial degree too low
- Domain too large
- Objective has sharp features

**Solutions:**
```julia
# Increase polynomial degree in globtimcore experiment
# Or reduce domain size
# Or use adaptive refinement
```

### Stagnation Detected

**Possible causes:**
- Reached approximation limit for this domain size
- Objective has features polynomial can't capture

**Solutions:**
```julia
# Reduce domain size around region of interest
# Or accept current approximation as "good enough"
```

### Many Outliers

**Possible causes:**
- Some critical points are invalid (numerical issues)
- Multiple distinct basins with very different values

**Solutions:**
```julia
# Filter critical points by gradient validation
# Or investigate outlier points manually
```

## See Also

- [Getting Started](getting_started.md) - Basic workflow
- [Critical Point Refinement](refinement.md) - Post-processing critical points
- [Polynomial Approximation (Globtim.jl)](https://gescholt.github.io/Globtim.jl/stable/polynomial_approximation) - Core algorithm
- [API Reference](api_reference.md) - Full function documentation
