"""
Base data structures for unified experiment loading.

Provides common data structures that all experiment types share.
"""

# ============================================================================
# Base Experiment Data
# ============================================================================

"""
    BaseExperimentData

Common base data structure for all experiment types.

Contains fields that are present across all experiment types. Type-specific
experiment data structures (e.g., LV4DExperimentData) should contain a
`base::BaseExperimentData` field.

# Fields
- `experiment_id::String`: Unique identifier (typically directory basename)
- `path::String`: Path to experiment directory
- `experiment_type::ExperimentType`: Detected experiment type
- `config::Dict{String, Any}`: Parsed experiment_config.json
- `degree_results::DataFrame`: Per-degree results from results_summary.json
- `critical_points::Union{DataFrame, Nothing}`: Combined critical points from all degrees

# Example
```julia
base = BaseExperimentData(
    experiment_id = "lv4d_GN8_deg4-12_domain0.1_seed1_20260115_120000",
    path = "/path/to/experiment",
    experiment_type = LV4D,
    config = Dict("p_true" => [0.2, 0.3, 0.5, 0.6], ...),
    degree_results = DataFrame(...),
    critical_points = DataFrame(...)
)
```
"""
struct BaseExperimentData
    experiment_id::String
    path::String
    experiment_type::ExperimentType
    config::Dict{String, Any}
    degree_results::DataFrame
    critical_points::Union{DataFrame, Nothing}
end

# ============================================================================
# Accessors
# ============================================================================

"""Get experiment ID from base data."""
experiment_id(data::BaseExperimentData) = data.experiment_id

"""Get path from base data."""
experiment_path(data::BaseExperimentData) = data.path

"""Get experiment type from base data."""
experiment_type(data::BaseExperimentData) = data.experiment_type

"""Get config from base data."""
experiment_config(data::BaseExperimentData) = data.config

"""Get degree results from base data."""
degree_results(data::BaseExperimentData) = data.degree_results

"""Get critical points from base data."""
critical_points(data::BaseExperimentData) = data.critical_points

"""Check if critical points are available."""
has_critical_points(data::BaseExperimentData) = data.critical_points !== nothing && nrow(data.critical_points) > 0

"""Get number of critical points."""
function num_critical_points(data::BaseExperimentData)
    data.critical_points === nothing && return 0
    return nrow(data.critical_points)
end

"""Get available degrees from degree_results."""
function available_degrees(data::BaseExperimentData)::Vector{Int}
    nrow(data.degree_results) == 0 && return Int[]
    hasproperty(data.degree_results, :degree) || return Int[]
    return sort(unique(data.degree_results.degree))
end

# ============================================================================
# Protocol: Implement these for type-specific data
# ============================================================================

"""
    get_base(data) -> BaseExperimentData

Extract base experiment data from type-specific data structure.

All type-specific experiment data structures should implement this method.
"""
function get_base end

# Default implementation for BaseExperimentData itself
get_base(data::BaseExperimentData) = data

# Accessor forwarding: allow accessing base fields from type-specific data
experiment_id(data) = experiment_id(get_base(data))
experiment_path(data) = experiment_path(get_base(data))
experiment_type(data) = experiment_type(get_base(data))
experiment_config(data) = experiment_config(get_base(data))
degree_results(data) = degree_results(get_base(data))
critical_points(data) = critical_points(get_base(data))
has_critical_points(data) = has_critical_points(get_base(data))
num_critical_points(data) = num_critical_points(get_base(data))
available_degrees(data) = available_degrees(get_base(data))

# ============================================================================
# Summary Printing
# ============================================================================

"""
    Base.show(io::IO, data::BaseExperimentData)

Pretty-print base experiment data.
"""
function Base.show(io::IO, data::BaseExperimentData)
    print(io, "BaseExperimentData(")
    print(io, "id=\"$(data.experiment_id)\", ")
    print(io, "type=$(type_name(data.experiment_type)), ")
    print(io, "degrees=$(length(available_degrees(data))), ")
    print(io, "critical_points=$(num_critical_points(data)))")
end

function Base.show(io::IO, ::MIME"text/plain", data::BaseExperimentData)
    println(io, "BaseExperimentData")
    println(io, "  ID:       $(data.experiment_id)")
    println(io, "  Type:     $(type_name(data.experiment_type))")
    println(io, "  Path:     $(data.path)")
    println(io, "  Degrees:  $(available_degrees(data))")
    n_cp = num_critical_points(data)
    println(io, "  Critical: $n_cp point$(n_cp == 1 ? "" : "s")")
end

# ============================================================================
# Config Utilities
# ============================================================================

"""
    get_config_value(data::BaseExperimentData, key::String, default=nothing)

Get a value from experiment config with fallback default.
"""
function get_config_value(data::BaseExperimentData, key::String, default=nothing)
    return get(data.config, key, default)
end

"""
    get_config_value(data, key::String, default=nothing)

Get a value from experiment config (for type-specific data).
"""
get_config_value(data, key::String, default=nothing) = get_config_value(get_base(data), key, default)

# ============================================================================
# Empty Constructors
# ============================================================================

"""
    empty_base_data(path::String, type::ExperimentType=UNKNOWN) -> BaseExperimentData

Create an empty BaseExperimentData for a path.

Useful when loading fails but you still want to track the experiment.
"""
function empty_base_data(path::String, type::ExperimentType=UNKNOWN)
    return BaseExperimentData(
        basename(path),
        path,
        type,
        Dict{String, Any}(),
        DataFrame(),
        nothing
    )
end
