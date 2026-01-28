"""
    LV4DAnalysis

Unified analysis module for Lotka-Volterra 4D parameter estimation experiments.

Consolidates multiple analysis scripts into a single interface with subcommands:
- `quality`: Single experiment critical point diagnostics
- `sweep`: Aggregate domain × degree sweep analysis
- `convergence`: Log-log convergence rate computation
- `gradients`: Gradient validation threshold analysis
- `minima`: Local minima clustering from refinement results

# Usage

```julia
using GlobtimPostProcessing.LV4DAnalysis

# Launch interactive TUI (arrow-key menus)
lv4d()

# Load and analyze a single experiment
data = load_lv4d_experiment(experiment_dir)
analyze_quality(data; verbose=true)

# Analyze a sweep campaign
experiments = load_sweep_experiments(results_root)
analyze_sweep(experiments)
```

Part of the GlobtimPostProcessing package - January 2026
"""
module LV4DAnalysis

using DataFrames
using CSV
using JSON
using JSON3
using Statistics
using LinearAlgebra
using Printf
using Dates
using PrettyTables
using UnicodePlots

# Import unified pipeline module (must be included before this module)
using ..UnifiedPipeline

# Import parent module types (but NOT from REPL for terminal menus)
# We'll handle the interactive menu differently for CLI vs REPL usage

# Include submodules in dependency order
include("common.jl")
include("data_loading.jl")
include("query.jl")  # Query interface (depends on common.jl and data_loading.jl)
include("quality.jl")
include("sweep.jl")
include("convergence.jl")
include("gradients.jl")
include("minima.jl")
include("comparison.jl")
include("interactive.jl")
include("tui.jl")
include("coverage.jl")

# Re-export key types and functions
export ExperimentParams

# Re-export unified pipeline types (for convenience)
export BaseExperimentData, ExperimentType, LV4DType, LV4D
export get_base, experiment_id, experiment_type, experiment_path
export degree_results, critical_points, has_critical_points

# Data loading
export load_lv4d_experiment, load_sweep_experiments, load_sweep_experiments_with_report
export LV4DExperimentData, LV4DSweepData, LoadResult

# Analysis functions
export analyze_quality, analyze_sweep, get_quality_summary
export analyze_convergence, ConvergenceResult, analyze_gradient_thresholds
export analyze_local_minima

# Utilities
export parse_experiment_name, is_single_experiment
export find_results_root, find_experiments
export format_domain, format_scientific, format_percentage, format_age

# Query interface
export ExperimentFilter, FixedValue, SweepRange
export fixed, sweep
export query_experiments, query_and_load, query_to_dataframe
export summarize_query, matches_experiment, format_filter, format_spec

# Histogram utilities
export make_log_bins, print_log_histogram

# Method comparison
export ComparisonData, load_comparison_data, analyze_comparison
export find_comparison_experiments
export ANSI_GREEN, ANSI_RED, ANSI_BOLD, ANSI_RESET
export make_winner_highlighter, make_loser_highlighter

# Subdivision comparison
export compare_single_vs_subdivision
export find_matched_subdivision_pairs, prepare_subdivision_comparison_df
export print_subdivision_comparison

# Interactive mode
export run_interactive, select_experiment

# TUI (interactive arrow-key menus)
export lv4d, analyze_lv4d

# Coverage analysis
export ExperimentKey, CoverageReport
export analyze_coverage, print_coverage_report
export get_missing_combinations, generate_gap_filling_configs
export summarize_coverage

end # module LV4DAnalysis
