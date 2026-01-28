"""
    ExperimentParameterIndex.jl - DEPRECATED

This module has been consolidated into Pipeline.PipelineRegistry.

All functionality is now available via:
```julia
using GlobtimPostProcessing.Pipeline

# Load registry (replaces build_parameter_index)
registry = load_pipeline_registry()
scan_for_experiments!(registry)

# Query experiments (same API)
exps = get_experiments_by_params(registry; GN=16, domain=0.08)

# Check if params exist (same API)
exists = has_experiment_with_params(registry; GN=16, domain=0.08, deg_min=4, deg_max=12)

# Coverage analysis (same API)
coverage = get_parameter_coverage(registry)
print_coverage_matrix(coverage)

# Missing params detection (same API)
missing = get_missing_params(registry, target_gns, target_domains, target_degrees)
```

See PipelineRegistry.jl for the canonical implementation.
"""

# Re-export types from Pipeline module for code that imports from here
using ..Pipeline: ExperimentParams, ExperimentEntry, ParameterCoverage
using ..Pipeline: PipelineRegistry as ExperimentParameterIndexStore
using ..Pipeline: extract_params_from_name as extract_params_from_path
using ..Pipeline: compute_params_hash as params_hash
using ..Pipeline: get_parameter_coverage, print_coverage_matrix
using ..Pipeline: get_experiments_by_params as query_experiments
using ..Pipeline: has_experiment_with_params, get_experiments_for_params
using ..Pipeline: get_unique_params as list_unique_params
using ..Pipeline: get_missing_params, print_query_results
using ..Pipeline: format_domain

# Note: ExperimentIndexEntry was replaced by ExperimentEntry in the consolidated system
const ExperimentIndexEntry = ExperimentEntry
