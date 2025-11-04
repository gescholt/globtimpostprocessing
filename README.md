# GlobtimPostProcessing.jl

Label-aware post-processing and visualization framework for GlobTim experiment results.

## Features

- **Label-driven analysis**: Automatically discovers available tracking labels from experiment results
- **Adaptive plotting**: Generates appropriate visualizations based on enabled tracking labels
- **Campaign analysis**: Compare and aggregate results across multiple experiments
- **Interactive exploration**: Terminal-based UI for browsing and analyzing experiments
- **Flexible backends**: Support for both interactive (GLMakie) and static (CairoMakie) plotting

## Getting Started

### Installation

GlobtimPostProcessing is **not registered in Julia General**. To use it, set up the entire GlobalOptim ecosystem using the centralized setup repository:

```bash
# Clone the setup repository
git clone git@git.mpi-cbg.de:globaloptim/setup.git GlobalOptim
cd GlobalOptim

# Run automated setup (develops all packages)
julia setup_globaloptim.jl
```

This automatically develops all GlobalOptim packages including GlobtimPostProcessing.

**For detailed instructions**, see the [setup repository](https://git.mpi-cbg.de/globaloptim/setup).

### Manual Development (Alternative)

If you prefer manual setup:

```julia
using Pkg
Pkg.develop(path="/path/to/GlobalOptim/globtimpostprocessing")
```

## Quick Start

### Analyze a single experiment

```julia
using GlobtimPostProcessing

# Load experiment results
result = load_experiment_results("/path/to/experiment_dir")

# Compute statistics based on available labels
stats = compute_statistics(result)

# Create adaptive plots
fig = create_experiment_plots(result, stats, backend=Static)
save_plot(fig, "analysis.png")
```

### Analyze a campaign of experiments

```julia
# Load multiple experiments
campaign = load_campaign_results("/path/to/campaign_dir")

# Compute statistics for each experiment
campaign_stats = Dict()
for exp in campaign.experiments
    campaign_stats[exp.experiment_id] = compute_statistics(exp)
end

# Create comparison plot
fig = create_campaign_comparison_plot(campaign, campaign_stats, backend=Interactive)
display(fig)
```

### Interactive analysis

Run the interactive analysis script:

```bash
julia interactive_analyze.jl /path/to/campaign_directory
```

Or let it discover campaigns automatically:

```bash
julia interactive_analyze.jl
```

## Label-Aware Architecture

The package automatically discovers which data is available in experiment results through tracking labels:

### Supported Labels

- `approximation_quality`: L2 approximation error of polynomial
- `numerical_stability`: Condition numbers
- `parameter_recovery`: Distance to true parameters (if available)
- `critical_point_count`: Number of critical points found
- `refined_critical_points`: Number after refinement
- `polynomial_timing`: Polynomial construction time
- `solving_timing`: Critical point solving time
- `refinement_timing`: Refinement time
- `refinement_quality`: Convergence statistics

### How it works

1. **Discovery**: `load_experiment_results` scans `results_summary.json` to discover available fields
2. **Labeling**: Fields are mapped to semantic labels (e.g., `l2_approx_error` → `approximation_quality`)
3. **Statistics**: `compute_statistics` computes only relevant statistics based on enabled labels
4. **Plotting**: `create_experiment_plots` generates only plots for available data

## Data Format

Expects GlobTim experiment outputs with:

```
experiment_dir/
├── results_summary.json         # Main results file
├── critical_points_deg_3.csv   # Critical points for degree 3
├── critical_points_deg_4.csv   # Critical points for degree 4
└── ...
```

The `results_summary.json` should contain:

```json
{
    "experiment_id": "...",
    "results_summary": {
        "degree_3": {
            "l2_approx_error": 1.23e-8,
            "condition_number": 16.0,
            "critical_points_refined": 42,
            "recovery_error": 0.123,
            ...
        },
        ...
    },
    "system_info": {
        "true_parameters": [0.35, -0.3, ...],
        ...
    }
}
```

## Development

### Running tests

```julia
using Pkg
Pkg.activate(".")
Pkg.test()
```

### GitLab CI/CD

The repository includes automated CI/CD:

- Syntax checking
- Unit tests on Julia 1.10 and 1.11
- Code coverage analysis

See [`.gitlab-ci.yml`](.gitlab-ci.yml) for details.

## License

GPL-3.0

## Authors

- Georgy Scholten
