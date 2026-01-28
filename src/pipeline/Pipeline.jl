"""
    Pipeline.jl - Experiment pipeline orchestration module

Provides auto-discovery of completed experiments and orchestrated analysis workflows.

This module contains the **canonical experiment registry system** (PipelineRegistry),
which consolidates:
- Persistent registry with JSON serialization
- Proper ExperimentParams struct (not Dict{String, Any})
- Indexed lookups (by_hash, by_gn, by_domain) for O(1) queries
- Coverage matrix and missing params detection
- Objective-agnostic (supports LV4D, Deuflhard, FitzHugh-Nagumo, etc.)

# Features
- Automatic experiment discovery from results directories
- Pipeline state tracking via JSON registry
- Batch analysis of pending experiments
- Watch mode for continuous monitoring
- Parameter coverage analysis and gap detection

# Usage
```julia
using GlobtimPostProcessing.Pipeline

# Scan for new experiments
registry = load_pipeline_registry()
scan_for_experiments!(registry)
save_pipeline_registry(registry)

# Query experiments by parameters (O(1) via index)
exps = get_experiments_by_params(registry; GN=16, domain=0.08)

# Coverage analysis
coverage = get_parameter_coverage(registry)
print_coverage_matrix(coverage)

# Find missing parameter combinations
missing = get_missing_params(registry, [8, 16], [0.01, 0.1], [(4, 12)])

# Analyze pending experiments
analyze_pending!(registry)

# Watch mode (daemon)
watch_and_analyze(registry; interval=60)
```
"""
module Pipeline

using Dates
using JSON
using DataFrames
using PrettyTables

# Include submodules
include("PipelineRegistry.jl")
include("ExperimentDiscovery.jl")
include("PipelineOrchestrator.jl")

# Export registry types
export PipelineRegistry, ExperimentEntry, ExperimentStatus
export DISCOVERED, ANALYZING, ANALYZED, FAILED  # ExperimentStatus enum values
export ExperimentParams, ParameterCoverage

# Export registry I/O functions
export load_pipeline_registry, save_pipeline_registry
export default_registry_path, default_results_root

# Export registry operations
export add_experiment!, remove_experiment!, update_experiment_status!
export get_pending_experiments, get_analyzed_experiments
export experiment_exists, rebuild_indices!

# Export parameter extraction
export extract_params_from_name, compute_params_hash, params_hash

# Export indexed query functions
export get_experiments_by_params, has_experiment_with_params
export get_experiments_for_params, get_unique_params, list_unique_params

# Export coverage and missing params functions
export get_parameter_coverage, get_missing_params
export print_coverage_matrix, print_query_results, format_domain

# Export discovery functions
export scan_for_experiments!, find_completed_experiments
export is_experiment_complete, parse_completion_marker

# Export orchestrator functions
export analyze_pending!, analyze_experiment!
export watch_and_analyze, get_pipeline_status

end # module Pipeline
