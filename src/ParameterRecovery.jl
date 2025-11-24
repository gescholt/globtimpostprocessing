"""
    ParameterRecovery.jl

Functions for analyzing parameter recovery in optimization experiments.

This module provides tools to measure how well the optimization algorithm
recovers true parameter values (`p_true`) across different polynomial degrees.
"""

using LinearAlgebra
using DataFrames
using Statistics
using CSV
using JSON3

"""
    param_distance(p_found::AbstractVector, p_true::AbstractVector) -> Float64

Compute Euclidean distance between found parameters and true parameters.

# Arguments
- `p_found`: Found parameter vector (e.g., from critical point)
- `p_true`: True parameter vector

# Returns
- Euclidean distance ||p_found - p_true||

# Example
```julia
p_true = [0.2, 0.3, 0.5, 0.6]
p_found = [0.201, 0.299, 0.498, 0.602]
dist = param_distance(p_found, p_true)  # ≈ 0.00316
```
"""
function param_distance(p_found::AbstractVector, p_true::AbstractVector)
    if length(p_found) != length(p_true)
        throw(DimensionMismatch("p_found and p_true must have same dimension"))
    end
    return norm(p_found - p_true)
end

"""
    load_experiment_config(experiment_path::String) -> Dict

Load experiment configuration from experiment_config.json.

# Arguments
- `experiment_path`: Path to experiment directory

# Returns
- Dictionary containing experiment configuration

# Throws
- `SystemError` if config file doesn't exist
"""
function load_experiment_config(experiment_path::String)
    config_file = joinpath(experiment_path, "experiment_config.json")
    if !isfile(config_file)
        error("Config file not found: $config_file")
    end
    return JSON3.read(read(config_file, String), Dict)
end

"""
    load_critical_points_for_degree(experiment_path::String, degree::Int) -> DataFrame

Load critical points CSV for a specific polynomial degree.

Supports both Phase 1 and Phase 2 file formats:
- Phase 2: `critical_points_raw_deg_X.csv` with columns (index, p1, p2, ..., objective)
- Phase 1: `critical_points_deg_X.csv` with columns (x1, x2, ..., z)

# Arguments
- `experiment_path`: Path to experiment directory
- `degree`: Polynomial degree

# Returns
- DataFrame with columns from CSV file

# Throws
- `ErrorException` if CSV file doesn't exist (neither format)
"""
function load_critical_points_for_degree(experiment_path::String, degree::Int)
    # Try Phase 2 format first (preferred)
    csv_file_raw = joinpath(experiment_path, "critical_points_raw_deg_$(degree).csv")
    if isfile(csv_file_raw)
        return CSV.read(csv_file_raw, DataFrame)
    end

    # Fall back to Phase 1 format
    csv_file_legacy = joinpath(experiment_path, "critical_points_deg_$(degree).csv")
    if isfile(csv_file_legacy)
        return CSV.read(csv_file_legacy, DataFrame)
    end

    error("Critical points file not found for degree $degree. Tried:\n" *
          "  Phase 2: $csv_file_raw\n" *
          "  Phase 1: $csv_file_legacy")
end

"""
    compute_parameter_recovery_stats(
        df::DataFrame,
        p_true::AbstractVector,
        recovery_threshold::Float64
    ) -> Dict{String, Any}

Compute parameter recovery statistics for critical points in a DataFrame.

For each critical point (row in df), computes distance to p_true and aggregates:
- Minimum distance (best recovery)
- Mean distance (average recovery)
- Number of recoveries (points within threshold)
- All individual distances

# Arguments
- `df`: DataFrame with columns x1, x2, ..., x_dim, z
- `p_true`: True parameter vector
- `recovery_threshold`: Distance threshold for considering a point "recovered"

# Returns
Dictionary with keys:
- `"min_distance"`: Minimum distance to p_true
- `"mean_distance"`: Mean distance to p_true
- `"num_recoveries"`: Count of points within threshold
- `"all_distances"`: Vector of all distances

# Example
```julia
df = load_critical_points_for_degree("experiment/", 6)
p_true = [0.2, 0.3, 0.5, 0.6]
stats = compute_parameter_recovery_stats(df, p_true, 0.01)
println("Best recovery: ", stats["min_distance"])
println("Recoveries: ", stats["num_recoveries"])
```
"""
function compute_parameter_recovery_stats(
    df::DataFrame,
    p_true::AbstractVector,
    recovery_threshold::Float64
)
    # Determine dimension from DataFrame columns
    dim = length(p_true)

    # Check DataFrame has required columns
    for i in 1:dim
        col_name = Symbol("x$i")
        if !hasproperty(df, col_name)
            error("DataFrame missing column: $col_name")
        end
    end

    # Compute distances for all critical points
    distances = Float64[]
    for row in eachrow(df)
        p_found = [row[Symbol("x$i")] for i in 1:dim]
        dist = param_distance(p_found, p_true)
        push!(distances, dist)
    end

    # Aggregate statistics
    min_dist = minimum(distances)
    mean_dist = mean(distances)
    num_recoveries = count(d -> d < recovery_threshold, distances)

    return Dict{String, Any}(
        "min_distance" => min_dist,
        "mean_distance" => mean_dist,
        "num_recoveries" => num_recoveries,
        "all_distances" => distances
    )
end

"""
    generate_parameter_recovery_table(
        experiment_path::String,
        p_true::AbstractVector,
        degrees::AbstractVector{Int},
        recovery_threshold::Float64
    ) -> DataFrame

Generate a table of parameter recovery statistics across multiple degrees.

# Arguments
- `experiment_path`: Path to experiment directory
- `p_true`: True parameter vector
- `degrees`: Vector of polynomial degrees to analyze
- `recovery_threshold`: Distance threshold for recovery

# Returns
DataFrame with columns:
- `degree`: Polynomial degree
- `num_critical_points`: Number of critical points found
- `min_distance`: Best parameter recovery distance
- `mean_distance`: Average parameter recovery distance
- `num_recoveries`: Number of successful recoveries

# Example
```julia
p_true = [0.2, 0.3, 0.5, 0.6]
degrees = [4, 6, 8, 10]
table = generate_parameter_recovery_table("experiment/", p_true, degrees, 0.01)
```
"""
function generate_parameter_recovery_table(
    experiment_path::String,
    p_true::AbstractVector,
    degrees::AbstractVector{Int},
    recovery_threshold::Float64
)
    results = DataFrame(
        degree = Int[],
        num_critical_points = Int[],
        min_distance = Float64[],
        mean_distance = Float64[],
        num_recoveries = Int[]
    )

    for degree in degrees
        # Load critical points for this degree
        df = load_critical_points_for_degree(experiment_path, degree)

        # Compute recovery statistics
        stats = compute_parameter_recovery_stats(df, p_true, recovery_threshold)

        # Add row to results table
        push!(results, (
            degree = degree,
            num_critical_points = nrow(df),
            min_distance = stats["min_distance"],
            mean_distance = stats["mean_distance"],
            num_recoveries = stats["num_recoveries"]
        ))
    end

    return results
end

"""
    has_ground_truth(experiment_path::String) -> Bool

Check if experiment has ground truth parameters (p_true).

# Arguments
- `experiment_path`: Path to experiment directory

# Returns
- `true` if experiment_config.json exists and contains `p_true`
- `false` otherwise
"""
function has_ground_truth(experiment_path::String)
    try
        config = load_experiment_config(experiment_path)
        return haskey(config, "p_true") && !isnothing(config["p_true"])
    catch
        return false
    end
end

# Export functions
export param_distance
export load_experiment_config
export load_critical_points_for_degree
export compute_parameter_recovery_stats
export generate_parameter_recovery_table
export has_ground_truth
