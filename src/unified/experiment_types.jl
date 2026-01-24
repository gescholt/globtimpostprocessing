"""
Experiment type hierarchy for unified post-processing pipeline.

Provides trait-based dispatch for type-specific loading and analysis.
"""

# ============================================================================
# Type Hierarchy
# ============================================================================

"""
    ExperimentType

Abstract base type for experiment type traits.

Used for dispatch-based loading and analysis. Each concrete type represents
a different experiment configuration (e.g., LV4D, Deuflhard, FitzHugh-Nagumo).
"""
abstract type ExperimentType end

"""
    LV4DType <: ExperimentType

Lotka-Volterra 4D parameter estimation experiment type.

Experiments in this category have:
- Directory names starting with "lv4d_"
- experiment_config.json with p_true, p_center, sample_range
- 4-dimensional parameter space
"""
struct LV4DType <: ExperimentType end

"""
    DeuflhardType <: ExperimentType

Deuflhard test function experiment type.

Standard global optimization test function used for benchmarking.
"""
struct DeuflhardType <: ExperimentType end

"""
    FitzHughNagumoType <: ExperimentType

FitzHugh-Nagumo neural model parameter estimation experiment type.
"""
struct FitzHughNagumoType <: ExperimentType end

"""
    UnknownType <: ExperimentType

Fallback type for experiments that don't match known patterns.

Used when experiment type cannot be determined from path or config.
"""
struct UnknownType <: ExperimentType end

# ============================================================================
# Singleton Instances
# ============================================================================

"""Singleton instance for LV4D experiment type."""
const LV4D = LV4DType()

"""Singleton instance for Deuflhard experiment type."""
const DEUFLHARD = DeuflhardType()

"""Singleton instance for FitzHugh-Nagumo experiment type."""
const FITZHUGH_NAGUMO = FitzHughNagumoType()

"""Singleton instance for unknown experiment type."""
const UNKNOWN = UnknownType()

# ============================================================================
# Type Names (for display)
# ============================================================================

"""Get human-readable name for experiment type."""
type_name(::LV4DType) = "LV4D"
type_name(::DeuflhardType) = "Deuflhard"
type_name(::FitzHughNagumoType) = "FitzHugh-Nagumo"
type_name(::UnknownType) = "Unknown"
type_name(::ExperimentType) = "Unknown"

# ============================================================================
# Type Detection
# ============================================================================

"""
    detect_experiment_type(path::String) -> ExperimentType

Detect experiment type from path name or config.

Detection order:
1. Check directory/file basename for known prefixes
2. Check experiment_config.json if available
3. Return UNKNOWN as fallback

# Arguments
- `path::String`: Path to experiment directory or file

# Returns
- Appropriate `ExperimentType` singleton

# Examples
```julia
detect_experiment_type("lv4d_GN8_deg4-12_domain0.1_seed1_20260115_120000")
# => LV4D

detect_experiment_type("deuflhard_deg6_20260115_120000")
# => DEUFLHARD

detect_experiment_type("unknown_experiment")
# => UNKNOWN
```
"""
function detect_experiment_type(path::String)::ExperimentType
    name = basename(path)

    # Check directory name prefixes
    if startswith(name, "lv4d")
        return LV4D
    elseif startswith(name, "deuflhard")
        return DEUFLHARD
    elseif startswith(name, "fitzhugh") || startswith(name, "fhn")
        return FITZHUGH_NAGUMO
    end

    # Try to load config if path is a directory
    if isdir(path)
        config_type = _detect_from_config(path)
        config_type !== nothing && return config_type
    end

    return UNKNOWN
end

"""
    _detect_from_config(dir::String) -> Union{ExperimentType, Nothing}

Detect experiment type from experiment_config.json.
"""
function _detect_from_config(dir::String)::Union{ExperimentType, Nothing}
    config_path = joinpath(dir, "experiment_config.json")
    !isfile(config_path) && return nothing

    try
        config = JSON.parsefile(config_path)

        # Check for system_type field
        system_type = get(config, "system_type", nothing)
        if system_type !== nothing
            system_lower = lowercase(string(system_type))
            if occursin("lotka", system_lower) || occursin("volterra", system_lower) ||
               occursin("lv4d", system_lower)
                return LV4D
            elseif occursin("deuflhard", system_lower)
                return DEUFLHARD
            elseif occursin("fitzhugh", system_lower) || occursin("nagumo", system_lower)
                return FITZHUGH_NAGUMO
            end
        end

        # Check for function_name field (common in older configs)
        fn_name = get(config, "function_name", nothing)
        if fn_name !== nothing
            fn_lower = lowercase(string(fn_name))
            if occursin("lotka", fn_lower) || occursin("volterra", fn_lower)
                return LV4D
            elseif occursin("deuflhard", fn_lower)
                return DEUFLHARD
            elseif occursin("fitzhugh", fn_lower)
                return FITZHUGH_NAGUMO
            end
        end

        # Check for LV4D-specific fields
        if haskey(config, "p_true") && haskey(config, "p_center")
            # Likely a parameter estimation problem
            # Check dimension - LV4D typically has 4 parameters
            p_true = config["p_true"]
            if p_true isa AbstractVector && length(p_true) == 4
                return LV4D
            end
        end

        return nothing
    catch e
        @debug "Failed to parse config for type detection" exception=e
        return nothing
    end
end

# ============================================================================
# Type Predicates
# ============================================================================

"""Check if experiment type is LV4D."""
is_lv4d(::LV4DType) = true
is_lv4d(::ExperimentType) = false

"""Check if experiment type is Deuflhard."""
is_deuflhard(::DeuflhardType) = true
is_deuflhard(::ExperimentType) = false

"""Check if experiment type is FitzHugh-Nagumo."""
is_fitzhugh_nagumo(::FitzHughNagumoType) = true
is_fitzhugh_nagumo(::ExperimentType) = false

"""Check if experiment type is unknown."""
is_unknown(::UnknownType) = true
is_unknown(::ExperimentType) = false

"""Check if experiment type supports parameter recovery analysis."""
has_ground_truth(::LV4DType) = true
has_ground_truth(::FitzHughNagumoType) = true
has_ground_truth(::ExperimentType) = false

"""Check if experiment type is a dynamical system (ODE-based)."""
is_dynamical_system(::LV4DType) = true
is_dynamical_system(::FitzHughNagumoType) = true
is_dynamical_system(::ExperimentType) = false

# ============================================================================
# Supported Types Registry
# ============================================================================

"""
List of all supported experiment types.

Used for TUI menus and validation.
"""
const SUPPORTED_TYPES = [
    LV4D => "Lotka-Volterra 4D parameter estimation",
    DEUFLHARD => "Deuflhard global optimization test function",
    FITZHUGH_NAGUMO => "FitzHugh-Nagumo neural model",
]

"""
Get list of experiment type names for menu display.
"""
function list_experiment_types()::Vector{Tuple{ExperimentType, String}}
    return [(t, desc) for (t, desc) in SUPPORTED_TYPES]
end
