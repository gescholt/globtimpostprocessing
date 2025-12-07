"""
    CSVFallbackLoader

Fallback data loader for experiments with truncated or missing results_summary.json files.

This module provides an alternative loading path that reconstructs experiment results
directly from CSV files and experiment_config.json when the primary JSON summary is corrupted.

Created: 2025-10-07
Related: globtimcore/docs/DATA_COLLECTION_TRUNCATION_ISSUE.md
"""
module CSVFallbackLoader

using CSV
using DataFrames
using JSON3
using Statistics

export load_experiment_from_csv_fallback, can_use_csv_fallback, compute_basic_statistics_from_csv

"""
    can_use_csv_fallback(dir_path::String) -> Bool

Check if an experiment directory has the minimum required files for CSV fallback loading.

Returns true if:
1. experiment_config.json exists and is valid JSON
2. At least one critical_points_raw_deg_*.csv file exists
"""
function can_use_csv_fallback(dir_path::String)
    # Check for experiment config
    config_path = joinpath(dir_path, "experiment_config.json")
    if !isfile(config_path)
        return false
    end

    # Try to parse config
    try
        JSON3.read(read(config_path, String))
    catch
        return false
    end

    # Check for at least one CSV file (new format only)
    csv_files = filter(f -> occursin(r"critical_points_raw_deg_\d+\.csv", f), readdir(dir_path))
    return !isempty(csv_files)
end

"""
    load_experiment_from_csv_fallback(dir_path::String) -> ExperimentResult

Load experiment results directly from CSV files and config, bypassing corrupted JSON.

# Data Sources
- `experiment_config.json`: Experiment parameters and metadata
- `critical_points_raw_deg_*.csv`: Critical point coordinates and objective values

# Reconstructed Fields
- experiment_id: From config or directory name
- metadata: From experiment_config.json
- critical_points: Combined from all degree CSV files
- enabled_tracking: Inferred from available data columns
- tracking_capabilities: Basic set based on CSV structure

# Limitations
- Performance metrics not available (requires valid JSON)
- Tolerance validation not available (requires valid JSON)
- Refinement statistics not available (requires valid JSON)
"""
function load_experiment_from_csv_fallback(dir_path::String)
    if !can_use_csv_fallback(dir_path)
        error("Cannot use CSV fallback for $dir_path - missing required files")
    end

    # Load experiment config
    config_path = joinpath(dir_path, "experiment_config.json")
    config = JSON3.read(read(config_path, String))

    # Extract experiment ID
    experiment_id = string(get(config, :experiment_id, basename(dir_path)))

    # Build metadata from config
    metadata = Dict{String, Any}(
        "experiment_id" => get(config, :experiment_id, nothing),
        "sample_range" => get(config, :sample_range, nothing),
        "domain_range" => get(config, :domain_range, nothing),
        "degree_range" => get(config, :degree_range, nothing),
        "dimension" => get(config, :dimension, nothing),
        "basis" => get(config, :basis, nothing),
        "GN" => get(config, :GN, nothing),
        "p_true" => get(config, :p_true, nothing),
        "p_center" => get(config, :p_center, nothing),
        "time_interval" => get(config, :time_interval, nothing),
        "ic" => get(config, :ic, nothing),
        "num_points" => get(config, :num_points, nothing),
        "model_func" => get(config, :model_func, nothing),
        "data_source" => "csv_fallback",  # Mark as fallback loaded
        "results_summary_status" => "truncated_or_missing"
    )

    # Load all critical points CSVs
    critical_points = load_all_critical_points_csvs(dir_path)

    # Infer tracking capabilities from available data
    enabled_tracking = String[]
    tracking_capabilities = String[]

    if critical_points !== nothing
        # We have critical points with coordinates and objective values
        push!(enabled_tracking, "critical_points")
        push!(enabled_tracking, "objective_values")
        push!(tracking_capabilities, "critical_points")
        push!(tracking_capabilities, "objective_values")

        # Check for additional columns that might be present
        if "in_domain" in names(critical_points)
            push!(enabled_tracking, "domain_filtering")
            push!(tracking_capabilities, "domain_filtering")
        end
    end

    # No performance metrics or tolerance validation available from CSV fallback
    performance_metrics = nothing
    tolerance_validation = nothing

    # Return ExperimentResult struct (assuming it's defined in parent module)
    # Note: This assumes ExperimentResult is available in the calling scope
    return (
        experiment_id = experiment_id,
        metadata = metadata,
        enabled_tracking = enabled_tracking,
        tracking_capabilities = tracking_capabilities,
        critical_points = critical_points,
        performance_metrics = performance_metrics,
        tolerance_validation = tolerance_validation,
        source_path = dir_path
    )
end

"""
    load_all_critical_points_csvs(dir_path::String) -> DataFrame

Load and combine all critical_points_raw_deg_*.csv files from an experiment directory.

Returns a single DataFrame with:
- p1, p2, ..., pn: Critical point coordinates
- objective: Objective value at the critical point
- degree: Polynomial degree (added column)
"""
function load_all_critical_points_csvs(dir_path::String)
    csv_files = filter(f -> occursin(r"critical_points_raw_deg_\d+\.csv", f), readdir(dir_path))

    if isempty(csv_files)
        error("No critical_points_raw_deg_*.csv files found in $dir_path")
    end

    all_points = DataFrame[]

    for csv_file in csv_files
        # Extract degree from filename
        m = match(r"critical_points_raw_deg_(\d+)\.csv", csv_file)
        if m === nothing
            error("Unexpected CSV filename format: $csv_file")
        end

        degree = parse(Int, m.captures[1])
        csv_path = joinpath(dir_path, csv_file)

        df = CSV.read(csv_path, DataFrame)

        # Add degree column
        df[!, :degree] = fill(degree, nrow(df))

        push!(all_points, df)
    end

    return vcat(all_points...)
end

"""
    compute_basic_statistics_from_csv(critical_points::DataFrame) -> Dict

Compute basic statistics from critical points DataFrame.

This provides minimal statistics that can be computed without the full
results_summary.json data.

Expects new CSV format with columns: index, p1, p2, ..., pN, objective, degree

Returns:
- degrees: List of degrees with data
- points_per_degree: Count of critical points per degree
- best_by_degree: Best objective value per degree
- overall_best: Overall best objective value and point
"""
function compute_basic_statistics_from_csv(critical_points::DataFrame)
    if nrow(critical_points) == 0
        error("No critical points data available")
    end

    if !("objective" in names(critical_points))
        error("Missing 'objective' column in DataFrame. Found columns: $(names(critical_points))")
    end

    stats = Dict{String, Any}()

    # Group by degree
    grouped = groupby(critical_points, :degree)

    degrees = Int[]
    points_per_degree = Dict{Int, Int}()
    best_by_degree = Dict{Int, Float64}()

    for group in grouped
        degree = first(group.degree)
        push!(degrees, degree)
        points_per_degree[degree] = nrow(group)
        best_by_degree[degree] = minimum(group.objective)
    end

    stats["degrees"] = sort(degrees)
    stats["points_per_degree"] = points_per_degree
    stats["best_by_degree"] = best_by_degree

    # Overall best
    best_idx = argmin(critical_points.objective)
    stats["overall_best_value"] = critical_points[best_idx, :objective]

    # Extract coordinates (p1, p2, ..., pN)
    coord_cols = filter(c -> occursin(r"^p\d+$", string(c)), names(critical_points))
    sort!(coord_cols, by=c -> parse(Int, match(r"p(\d+)", string(c))[1]))
    best_point = [critical_points[best_idx, c] for c in coord_cols]
    stats["overall_best_point"] = best_point
    stats["overall_best_degree"] = critical_points[best_idx, :degree]

    return stats
end
end
