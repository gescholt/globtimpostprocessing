"""
    QualityDiagnostics.jl

Configurable quality diagnostic functions for experiment analysis (Issue #7, Phase 3).

Provides dimension-aware, threshold-based quality assessments replacing
hardcoded "made up" values with explicit, documented criteria.
"""

using Statistics

"""
    load_quality_thresholds(config_path::String=joinpath(@__DIR__, "..", "quality_thresholds.toml")) -> Dict

Load quality thresholds from TOML configuration file.

# Arguments
- `config_path`: Path to quality_thresholds.toml (default: package root)

# Returns
Dictionary with threshold categories:
- `l2_norm_thresholds`: Dimension-dependent L2 norm quality thresholds
- `parameter_recovery`: Parameter recovery thresholds
- `convergence`: Convergence quality thresholds
- `objective_distribution`: Objective value distribution thresholds
"""
function load_quality_thresholds(config_path::String=joinpath(@__DIR__, "..", "quality_thresholds.toml"))
    if !isfile(config_path)
        error("Quality thresholds file not found: $config_path")
    end

    # Parse TOML manually (avoid TOML dependency if not needed)
    # For simplicity, return a Dict with expected structure
    thresholds = Dict{String, Any}()

    lines = readlines(config_path)
    current_section = nothing

    for line in lines
        line = strip(line)

        # Skip comments and empty lines
        if isempty(line) || startswith(line, '#')
            continue
        end

        # Section header
        if startswith(line, '[') && endswith(line, ']')
            section_name = strip(line[2:end-1])
            current_section = section_name
            thresholds[current_section] = Dict{String, Any}()
            continue
        end

        # Key-value pair
        if occursin('=', line) && !isnothing(current_section)
            key, value = split(line, '=', limit=2)
            key = strip(key)
            value = strip(value)

            # Remove comments from value
            if occursin('#', value)
                value = strip(split(value, '#')[1])
            end

            # Parse value
            parsed_value = try
                if occursin("e-", lowercase(value)) || occursin("e+", lowercase(value))
                    parse(Float64, value)
                elseif occursin('.', value)
                    parse(Float64, value)
                else
                    parse(Int, value)
                end
            catch
                value  # Keep as string if parsing fails
            end

            thresholds[current_section][key] = parsed_value
        end
    end

    return thresholds
end

"""
    check_l2_quality(l2_norm::Float64, dimension::Int, thresholds::Dict) -> Symbol

Check L2 norm quality using dimension-dependent thresholds.

Returns graded quality assessment:
- `:excellent` - L2 < 0.5 * threshold
- `:good` - L2 < 1.0 * threshold
- `:fair` - L2 < 2.0 * threshold
- `:poor` - L2 >= 2.0 * threshold

# Arguments
- `l2_norm`: L2 approximation error
- `dimension`: Problem dimension
- `thresholds`: Loaded threshold dictionary

# Example
```julia
thresholds = load_quality_thresholds()
quality = check_l2_quality(0.05, 4, thresholds)  # :excellent
```
"""
function check_l2_quality(l2_norm::Float64, dimension::Int, thresholds::Dict)
    l2_thresholds = thresholds["l2_norm_thresholds"]

    # Get dimension-specific threshold
    threshold_key = "dim_$dimension"
    threshold = if haskey(l2_thresholds, threshold_key)
        l2_thresholds[threshold_key]
    else
        l2_thresholds["default"]
    end

    # Graded assessment
    if l2_norm < 0.5 * threshold
        return :excellent
    elseif l2_norm < 1.0 * threshold
        return :good
    elseif l2_norm < 2.0 * threshold
        return :fair
    else
        return :poor
    end
end

"""
    StagnationResult

Result of convergence stagnation detection.

# Fields
- `is_stagnant::Bool`: Whether stagnation was detected
- `stagnation_start_degree::Union{Int, Nothing}`: Degree where stagnation started
- `stagnant_count::Int`: Number of consecutive stagnant degrees
- `improvement_factors::Vector{Float64}`: Improvement ratios between consecutive degrees
"""
struct StagnationResult
    is_stagnant::Bool
    stagnation_start_degree::Union{Int, Nothing}
    stagnant_count::Int
    improvement_factors::Vector{Float64}
end

"""
    detect_stagnation(l2_by_degree::Dict{Int, Float64}, thresholds::Dict) -> StagnationResult

Detect convergence stagnation across polynomial degrees.

Stagnation is detected when:
1. L2 norm fails to improve by `min_improvement_factor` for `stagnation_tolerance` consecutive degrees
2. L2 norm is not already below `absolute_improvement_threshold` (i.e., already converged)

# Arguments
- `l2_by_degree`: Dictionary mapping degree -> L2 norm
- `thresholds`: Loaded threshold dictionary

# Returns
`StagnationResult` with detection details
"""
function detect_stagnation(l2_by_degree::Dict{Int, Float64}, thresholds::Dict)
    convergence_params = thresholds["convergence"]
    min_improvement_factor = convergence_params["min_improvement_factor"]
    stagnation_tolerance = convergence_params["stagnation_tolerance"]
    absolute_threshold = convergence_params["absolute_improvement_threshold"]

    # Sort degrees
    degrees = sort(collect(keys(l2_by_degree)))

    if length(degrees) < 2
        return StagnationResult(false, nothing, 0, Float64[])
    end

    improvement_factors = Float64[]
    stagnant_count = 0
    stagnation_start = nothing

    for i in 2:length(degrees)
        prev_degree = degrees[i-1]
        curr_degree = degrees[i]

        prev_l2 = l2_by_degree[prev_degree]
        curr_l2 = l2_by_degree[curr_degree]

        # Skip if already converged (very small L2)
        if curr_l2 < absolute_threshold
            push!(improvement_factors, 0.0)
            stagnant_count = 0
            stagnation_start = nothing
            continue
        end

        # Calculate improvement factor
        improvement_factor = curr_l2 / prev_l2
        push!(improvement_factors, improvement_factor)

        # Check if stagnant (not improving enough)
        if improvement_factor >= min_improvement_factor
            stagnant_count += 1
            if stagnation_start === nothing
                stagnation_start = curr_degree
            end
        else
            # Reset counter if improvement detected
            stagnant_count = 0
            stagnation_start = nothing
        end
    end

    is_stagnant = stagnant_count >= stagnation_tolerance

    return StagnationResult(is_stagnant, stagnation_start, stagnant_count, improvement_factors)
end

"""
    ObjectiveDistributionResult

Result of objective value distribution quality check.

# Fields
- `has_outliers::Bool`: Whether outliers were detected
- `num_outliers::Int`: Number of outliers
- `outlier_fraction::Float64`: Fraction of values that are outliers
- `quality::Symbol`: Overall quality assessment
- `q1::Float64`: First quartile
- `q3::Float64`: Third quartile
- `iqr::Float64`: Interquartile range
"""
struct ObjectiveDistributionResult
    has_outliers::Bool
    num_outliers::Int
    outlier_fraction::Float64
    quality::Symbol
    q1::Float64
    q3::Float64
    iqr::Float64
end

"""
    check_objective_distribution_quality(objectives::Vector{Float64}, thresholds::Dict) -> ObjectiveDistributionResult

Check quality of objective value distribution using IQR-based outlier detection.

Outliers are values beyond Q1 - k*IQR or Q3 + k*IQR, where k is configurable.

Quality assessment:
- `:good` - Few or no outliers (< threshold)
- `:poor` - Many outliers (>= threshold)
- `:insufficient_data` - Not enough points to assess

# Arguments
- `objectives`: Vector of objective values
- `thresholds`: Loaded threshold dictionary
"""
function check_objective_distribution_quality(objectives::Vector{Float64}, thresholds::Dict)
    dist_params = thresholds["objective_distribution"]
    min_points = dist_params["min_points_for_distribution_check"]
    max_outlier_fraction = dist_params["max_outlier_fraction"]
    iqr_multiplier = dist_params["outlier_iqr_multiplier"]

    n = length(objectives)

    # Not enough data
    if n < min_points
        return ObjectiveDistributionResult(
            false, 0, 0.0, :insufficient_data, 0.0, 0.0, 0.0
        )
    end

    # Calculate quartiles and IQR
    sorted_objs = sort(objectives)
    q1 = quantile(sorted_objs, 0.25)
    q3 = quantile(sorted_objs, 0.75)
    iqr = q3 - q1

    # Detect outliers
    lower_bound = q1 - iqr_multiplier * iqr
    upper_bound = q3 + iqr_multiplier * iqr

    outliers = filter(x -> x < lower_bound || x > upper_bound, objectives)
    num_outliers = length(outliers)
    outlier_fraction = num_outliers / n

    has_outliers = num_outliers > 0
    quality = outlier_fraction <= max_outlier_fraction ? :good : :poor

    return ObjectiveDistributionResult(
        has_outliers, num_outliers, outlier_fraction, quality, q1, q3, iqr
    )
end

# Export functions
export load_quality_thresholds
export check_l2_quality
export detect_stagnation, StagnationResult
export check_objective_distribution_quality, ObjectiveDistributionResult
