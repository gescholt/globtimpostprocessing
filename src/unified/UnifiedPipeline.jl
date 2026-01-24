"""
    UnifiedPipeline

Unified post-processing pipeline that supports multiple experiment types.

This module provides a single entry point for loading and analyzing experiments
of any type (LV4D, Deuflhard, FitzHugh-Nagumo, etc.) with automatic type detection
and dispatch to type-specific handlers.

# Architecture

```
UnifiedPipeline
├── experiment_types.jl   # Type hierarchy + detection
├── base_data.jl          # BaseExperimentData struct
├── loaders.jl            # Unified load_experiment()
├── tui_main.jl           # postprocess() entry point
└── tui_menus.jl          # Shared menu utilities
```

# Usage

```julia
using GlobtimPostProcessing

# Unified loading with auto-detection
data = load_experiment("path/to/experiment")

# Interactive TUI
postprocess()
```

Part of the GlobtimPostProcessing package - January 2026
"""
module UnifiedPipeline

using DataFrames
using CSV
using JSON
using Statistics
using LinearAlgebra
using Printf
using Dates
using REPL.TerminalMenus
using PrettyTables

# Include submodules in dependency order
include("experiment_types.jl")
include("base_data.jl")
include("loaders.jl")
include("tui_menus.jl")
include("tui_main.jl")

# ============================================================================
# Exports: Experiment Types
# ============================================================================

export ExperimentType
export LV4DType, DeuflhardType, FitzHughNagumoType, UnknownType
export LV4D, DEUFLHARD, FITZHUGH_NAGUMO, UNKNOWN
export detect_experiment_type
export type_name
export is_lv4d, is_deuflhard, is_fitzhugh_nagumo, is_unknown
export has_ground_truth, is_dynamical_system
export SUPPORTED_TYPES, list_experiment_types

# ============================================================================
# Exports: Base Data
# ============================================================================

export BaseExperimentData
export get_base
export experiment_id, experiment_path, experiment_type
export experiment_config, degree_results, critical_points
export has_critical_points, num_critical_points, available_degrees
export get_config_value
export empty_base_data

# ============================================================================
# Exports: Loaders
# ============================================================================

export load_experiment
export is_single_experiment
export load_experiments, find_and_load_experiments

# ============================================================================
# Exports: TUI
# ============================================================================

export postprocess

end # module UnifiedPipeline
