"""
Query interface for experiment selection.

Provides flexible filtering of experiments by GN, degree, domain, and seed.
"""

# ============================================================================
# Filter Specification Types
# ============================================================================

"""
    FixedValue{T}

Filter specification for a fixed value match.

# Example
```julia
FixedValue(8)  # Match exactly 8
```
"""
struct FixedValue{T}
    value::T
end

"""
    SweepRange{T}

Filter specification for a range of values.

# Example
```julia
SweepRange(4, 12)  # Match values in [4, 12]
```
"""
struct SweepRange{T}
    min::T
    max::T
end

"""
    FilterSpec{T}

Union type for filter specifications: nothing (any), FixedValue, or SweepRange.
"""
const FilterSpec{T} = Union{Nothing, FixedValue{T}, SweepRange{T}}

# ============================================================================
# Convenience Constructors
# ============================================================================

"""
    fixed(value) -> FixedValue

Create a fixed value filter specification.

# Example
```julia
filter = ExperimentFilter(gn=fixed(8))  # Only GN=8
```
"""
fixed(value::T) where T = FixedValue{T}(value)

"""
    sweep(min, max) -> SweepRange

Create a range filter specification.

# Example
```julia
filter = ExperimentFilter(degree=sweep(4, 12))  # Degrees 4-12
```
"""
sweep(min::T, max::T) where T = SweepRange{T}(min, max)
sweep(r::AbstractRange) = SweepRange(first(r), last(r))

# ============================================================================
# Main Filter Struct
# ============================================================================

"""
    ExperimentFilter

Filter specification for querying experiments.

# Fields
- `gn::FilterSpec{Int}`: Filter by GN value (nothing = any)
- `degree::FilterSpec{Int}`: Filter by degree (nothing = any)
- `domain::FilterSpec{Float64}`: Filter by domain (nothing = any)
- `seed::FilterSpec{Int}`: Filter by seed (nothing = any)

# Examples
```julia
# All experiments with GN=8, any domain
filter = ExperimentFilter(gn=fixed(8))

# Domain sweep: GN=8, degrees 4-12, all domains
filter = ExperimentFilter(
    gn = fixed(8),
    degree = sweep(4, 12),
    domain = nothing
)

# Specific configuration
filter = ExperimentFilter(
    gn = fixed(16),
    degree = fixed(8),
    domain = sweep(0.001, 0.5)
)
```
"""
@kwdef struct ExperimentFilter
    gn::FilterSpec{Int} = nothing
    degree::FilterSpec{Int} = nothing
    domain::FilterSpec{Float64} = nothing
    seed::FilterSpec{Int} = nothing
end

# ============================================================================
# Filter Matching
# ============================================================================

"""
    matches_filter(value, spec::Nothing) -> Bool

Nothing spec matches any value.
"""
matches_filter(value, ::Nothing) = true

"""
    matches_filter(value, spec::FixedValue) -> Bool

Fixed value spec matches exact value.
"""
matches_filter(value, spec::FixedValue) = value == spec.value

"""
    matches_filter(value, spec::SweepRange) -> Bool

Range spec matches values in [min, max].
"""
matches_filter(value, spec::SweepRange) = spec.min <= value <= spec.max

"""
    matches_experiment(params::ExperimentParams, filter::ExperimentFilter) -> Bool

Check if an experiment matches the filter specification.
"""
function matches_experiment(params::ExperimentParams, filter::ExperimentFilter)::Bool
    return matches_filter(params.GN, filter.gn) &&
           matches_filter(params.domain, filter.domain) &&
           matches_filter(something(params.seed, 0), filter.seed) &&
           _matches_degree(params, filter.degree)
end

"""
    _matches_degree(params::ExperimentParams, spec) -> Bool

Check if experiment's degree range overlaps with filter spec.

For single-degree experiments (degree_min == degree_max), checks if that degree matches.
For multi-degree experiments, checks if any degree in range matches.
"""
function _matches_degree(params::ExperimentParams, ::Nothing)::Bool
    return true
end

function _matches_degree(params::ExperimentParams, spec::FixedValue{Int})::Bool
    return params.degree_min <= spec.value <= params.degree_max
end

function _matches_degree(params::ExperimentParams, spec::SweepRange{Int})::Bool
    # Check if experiment's degree range overlaps with filter range
    return !(params.degree_max < spec.min || params.degree_min > spec.max)
end

# ============================================================================
# Query Functions
# ============================================================================

"""
    query_experiments(results_root::String, filter::ExperimentFilter) -> Vector{String}

Find experiment directories matching the filter specification.

# Arguments
- `results_root::String`: Directory containing experiment subdirectories
- `filter::ExperimentFilter`: Filter specification

# Returns
Vector of paths to matching experiment directories.

# Example
```julia
filter = ExperimentFilter(gn=fixed(8), domain=sweep(0.01, 0.5))
exp_dirs = query_experiments(results_root, filter)
```
"""
function query_experiments(results_root::Union{String, Nothing}, filter::ExperimentFilter)::Vector{String}
    exp_dirs = find_experiments(results_root)
    matching = String[]

    for exp_dir in exp_dirs
        params = parse_experiment_name(basename(exp_dir))
        params === nothing && continue

        if matches_experiment(params, filter)
            push!(matching, exp_dir)
        end
    end

    return matching
end

"""
    query_and_load(results_root::String, filter::ExperimentFilter) -> Tuple{Vector{LV4DExperimentData}, Vector{String}}

Query experiments and load matching data.

# Returns
Tuple of:
- `loaded::Vector{LV4DExperimentData}`: Successfully loaded experiments
- `failed::Vector{String}`: Paths to experiments that failed to load

# Example
```julia
filter = ExperimentFilter(gn=fixed(8))
loaded, skipped = query_and_load(results_root, filter)
if !isempty(skipped)
    @warn "Skipped \$(length(skipped)) experiments"
end
```
"""
function query_and_load(results_root::Union{String, Nothing}, filter::ExperimentFilter)
    exp_dirs = query_experiments(results_root, filter)
    loaded = LV4DExperimentData[]
    failed = String[]

    for exp_dir in exp_dirs
        try
            data = load_lv4d_experiment(exp_dir)
            push!(loaded, data)
        catch e
            push!(failed, exp_dir)
            @debug "Failed to load $(basename(exp_dir)): $e"
        end
    end

    return (loaded, failed)
end

"""
    query_to_dataframe(results_root::String, filter::ExperimentFilter) -> DataFrame

Query experiments and return results as a DataFrame.

The DataFrame contains one row per experiment-degree combination with columns:
- `experiment_dir`: Experiment directory name
- `GN`, `domain`, `seed`: Experiment parameters
- `degree`: Polynomial degree
- `L2_norm`, `recovery_error`, `gradient_valid_rate`: Key metrics
- Other metrics from results_summary.json

# Example
```julia
filter = ExperimentFilter(gn=fixed(8), degree=sweep(4, 12))
df = query_to_dataframe(results_root, filter)
# Now filter/aggregate using DataFrames.jl
```
"""
function query_to_dataframe(results_root::String, filter::ExperimentFilter)::DataFrame
    loaded, failed = query_and_load(results_root, filter)

    if !isempty(failed)
        @debug "Skipped $(length(failed)) experiments that failed to load"
    end

    if isempty(loaded)
        return DataFrame()
    end

    # Combine degree_results from all experiments
    dfs = [exp.degree_results for exp in loaded if !isempty(exp.degree_results)]

    return isempty(dfs) ? DataFrame() : vcat(dfs...)
end

# ============================================================================
# Query Summary
# ============================================================================

"""
    summarize_query(results_root::String, filter::ExperimentFilter; verbose::Bool=false)

Print a summary of experiments matching the filter.

# Arguments
- `results_root::String`: Results directory
- `filter::ExperimentFilter`: Filter specification
- `verbose::Bool=false`: Show detailed listing

# Example
```julia
filter = ExperimentFilter(gn=fixed(8), domain=sweep(0.01, 0.5))
summarize_query(results_root, filter; verbose=true)
```
"""
function summarize_query(results_root::String, filter::ExperimentFilter; verbose::Bool=false)
    exp_dirs = query_experiments(results_root, filter)

    println("Query Results:")
    println("  Filter: $(format_filter(filter))")
    println("  Matching experiments: $(length(exp_dirs))")

    if isempty(exp_dirs)
        println("  No experiments match the filter")
        return
    end

    # Summarize by parameter
    params = [parse_experiment_name(basename(d)) for d in exp_dirs]
    params = filter(!isnothing, params)

    if !isempty(params)
        gn_values = sort(unique([p.GN for p in params]))
        domain_values = sort(unique([p.domain for p in params]))
        degree_ranges = unique([(p.degree_min, p.degree_max) for p in params])
        seed_values = sort(unique([something(p.seed, 0) for p in params]))

        println("  GN values: $gn_values")
        println("  Domains: $(length(domain_values)) unique values")
        if length(domain_values) <= 10
            println("    $domain_values")
        else
            println("    [$(minimum(domain_values)) ... $(maximum(domain_values))]")
        end
        println("  Degree ranges: $degree_ranges")
        println("  Seeds: $seed_values")
    end

    if verbose && length(exp_dirs) <= 20
        println()
        println("Matching experiments:")
        for exp_dir in exp_dirs
            println("  $(basename(exp_dir))")
        end
    elseif verbose
        println()
        println("First 20 matching experiments:")
        for exp_dir in exp_dirs[1:20]
            println("  $(basename(exp_dir))")
        end
        println("  ... and $(length(exp_dirs) - 20) more")
    end
end

"""
    format_filter(filter::ExperimentFilter) -> String

Format filter specification for display.
"""
function format_filter(filter::ExperimentFilter)::String
    parts = String[]

    if filter.gn !== nothing
        push!(parts, "GN=$(format_spec(filter.gn))")
    end
    if filter.degree !== nothing
        push!(parts, "degree=$(format_spec(filter.degree))")
    end
    if filter.domain !== nothing
        push!(parts, "domain=$(format_spec(filter.domain))")
    end
    if filter.seed !== nothing
        push!(parts, "seed=$(format_spec(filter.seed))")
    end

    isempty(parts) ? "(all)" : join(parts, ", ")
end

format_spec(::Nothing) = "any"
format_spec(spec::FixedValue) = string(spec.value)
format_spec(spec::SweepRange) = "[$(spec.min), $(spec.max)]"
