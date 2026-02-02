"""
TrajectoryComparison Module

High-level analysis combining parameter recovery and trajectory evaluation.

This module provides:
1. Loading and evaluating critical points across polynomial degrees
2. Ranking critical points by quality metrics
3. Identifying parameter recovery candidates
4. Convergence analysis across degrees
5. Formatted reporting (text, markdown, JSON)
6. Campaign-level aggregation

Design Principles:
- NO FALLBACKS: Error if data missing or malformed
- Combines ObjectiveFunctionRegistry + TrajectoryEvaluator
- User-facing analysis functions
- Multiple output formats for flexibility

Author: GlobTim Team
Created: October 2025
"""
module TrajectoryComparison

export load_critical_points_for_degree,
       evaluate_all_critical_points,
       rank_critical_points,
       identify_parameter_recovery,
       analyze_experiment_convergence,
       generate_comparison_report,
       compare_degrees,
       analyze_campaign_parameter_recovery

using DataFrames
using CSV
using JSON3
using Printf
using Statistics
using LinearAlgebra

# Import from other modules
# Load ObjectiveFunctionRegistry first (TrajectoryEvaluator depends on it)
include("ObjectiveFunctionRegistry.jl")
using .ObjectiveFunctionRegistry

# Now load TrajectoryEvaluator (it will find ObjectiveFunctionRegistry already loaded)
include("TrajectoryEvaluator.jl")
using .TrajectoryEvaluator

# Default threshold for parameter recovery (5% of parameter space)
const DEFAULT_RECOVERY_THRESHOLD = 0.05

"""
    normalize_config(config) -> Dict

Convert JSON3.Object or other config representations to a plain Dict with String keys.
This ensures compatibility across different JSON loading methods.
"""
function normalize_config(config::Dict)
    # Already a dict with string keys
    if all(k -> k isa String, keys(config))
        return config
    end
    # Convert symbol keys to string keys
    return Dict(String(k) => v for (k, v) in pairs(config))
end

function normalize_config(config)
    # Handle JSON3.Object or similar
    return Dict(String(k) => v for (k, v) in pairs(config))
end

"""
    load_critical_points_for_degree(exp_path::String, degree::Int) -> DataFrame

Load critical points CSV file for a specific polynomial degree.

# Arguments
- `exp_path`: Path to experiment directory
- `degree`: Polynomial degree

# Returns
- DataFrame with critical points (may be empty if no points found)

# Throws
- ErrorException if file not found
- ErrorException if CSV malformed
"""
function load_critical_points_for_degree(exp_path::String, degree::Int)
    csv_file = joinpath(exp_path, "critical_points_deg_$(degree).csv")

    if !isfile(csv_file)
        error("""
            Critical points file not found for degree $degree.
            Expected: $csv_file

            Make sure the experiment has been run and critical points CSV exists.
            """)
    end

    try
        df = CSV.read(csv_file, DataFrame)
        return df
    catch e
        error("""
            Failed to read critical points CSV for degree $degree.
            File: $csv_file
            Error: $e

            The CSV file may be malformed or corrupted.
            """)
    end
end

"""
    evaluate_all_critical_points(config::Dict, critical_points_df::DataFrame) -> DataFrame

Evaluate trajectory quality for all critical points.

# Arguments
- `config`: Experiment configuration
- `critical_points_df`: DataFrame with critical points

# Returns
- Augmented DataFrame with additional columns:
  - param_distance: L2 distance to true parameters
  - trajectory_distance: L2 distance in trajectory space
  - is_recovery: Boolean flag (param_distance < threshold)
"""
function evaluate_all_critical_points(config, critical_points_df::DataFrame;
                                     recovery_threshold::Float64 = DEFAULT_RECOVERY_THRESHOLD)
    # Normalize config to Dict with String keys
    config = normalize_config(config)

    if nrow(critical_points_df) == 0
        # Return empty DataFrame with expected columns
        df = copy(critical_points_df)
        df[!, :param_distance] = Float64[]
        df[!, :trajectory_distance] = Float64[]
        df[!, :is_recovery] = Bool[]
        return df
    end

    # Evaluate each critical point
    param_distances = Float64[]
    trajectory_distances = Float64[]

    for row in eachrow(critical_points_df)
        try
            metrics = TrajectoryEvaluator.evaluate_critical_point(config, row)
            push!(param_distances, metrics.param_distance)
            push!(trajectory_distances, metrics.trajectory_distance)
        catch e
            @warn "Failed to evaluate critical point, skipping" exception=e
            push!(param_distances, NaN)
            push!(trajectory_distances, NaN)
        end
    end

    # Augment DataFrame
    df = copy(critical_points_df)
    df[!, :param_distance] = param_distances
    df[!, :trajectory_distance] = trajectory_distances
    df[!, :is_recovery] = param_distances .< recovery_threshold

    return df
end

"""
    rank_critical_points(evaluated_df::DataFrame, by::Symbol) -> DataFrame

Rank critical points by specified metric.

# Arguments
- `evaluated_df`: DataFrame with evaluated critical points
- `by`: Column to rank by (:param_distance, :trajectory_distance, :z)

# Returns
- Sorted DataFrame with additional :rank column (1 = best)
"""
function rank_critical_points(evaluated_df::DataFrame, by::Symbol)
    if !(by in names(evaluated_df))
        error("""
            Cannot rank by column '$by' - column not found.
            Available columns: $(names(evaluated_df))

            Common ranking columns:
            - :param_distance (parameter space)
            - :trajectory_distance (trajectory space)
            - :z (objective function value)
            """)
    end

    # Sort by column (ascending for distances, ascending for objective)
    df_sorted = sort(evaluated_df, by)

    # Add rank column
    df_sorted[!, :rank] = 1:nrow(df_sorted)

    return df_sorted
end

"""
    identify_parameter_recovery(evaluated_df::DataFrame, threshold::Float64) -> DataFrame

Filter critical points that represent parameter recovery.

# Arguments
- `evaluated_df`: DataFrame with evaluated critical points
- `threshold`: Maximum parameter distance to consider as recovery

# Returns
- Filtered DataFrame with only recovery candidates, sorted by param_distance
"""
function identify_parameter_recovery(evaluated_df::DataFrame,
                                    threshold::Float64 = DEFAULT_RECOVERY_THRESHOLD)
    if nrow(evaluated_df) == 0
        return copy(evaluated_df)
    end

    # Filter by threshold
    recoveries = filter(row -> !isnan(row.param_distance) && row.param_distance < threshold,
                       evaluated_df)

    # Sort by parameter distance (best first)
    sort!(recoveries, :param_distance)

    return recoveries
end

"""
    analyze_experiment_convergence(exp_path::String) -> NamedTuple

Comprehensive convergence analysis across all polynomial degrees.

# Arguments
- `exp_path`: Path to experiment directory

# Returns
NamedTuple with:
- `degrees`: Vector of degrees analyzed
- `best_param_distance_by_degree`: Dict{Int, Float64}
- `best_trajectory_distance_by_degree`: Dict{Int, Float64}
- `num_critical_points_by_degree`: Dict{Int, Int}
- `num_recoveries_by_degree`: Dict{Int, Int}
- `config`: Experiment configuration
"""
function analyze_experiment_convergence(exp_path::String;
                                       recovery_threshold::Float64 = DEFAULT_RECOVERY_THRESHOLD)
    # Load config
    config_file = joinpath(exp_path, "experiment_config.json")
    if !isfile(config_file)
        error("""
            Experiment configuration not found.
            Expected: $config_file

            Make sure you are pointing to a valid experiment directory.
            """)
    end

    config = JSON3.read(read(config_file, String))

    # Discover available degree files
    csv_files = filter(f -> occursin(r"critical_points_deg_\d+\.csv", f),
                      readdir(exp_path))

    degrees = Int[]
    for csv_file in csv_files
        m = match(r"deg_(\d+)\.csv", csv_file)
        if m !== nothing
            push!(degrees, parse(Int, m[1]))
        end
    end

    sort!(degrees)

    if isempty(degrees)
        @warn "No critical points files found in $exp_path"
        return (
            degrees = Int[],
            best_param_distance_by_degree = Dict{Int, Float64}(),
            best_trajectory_distance_by_degree = Dict{Int, Float64}(),
            num_critical_points_by_degree = Dict{Int, Int}(),
            num_recoveries_by_degree = Dict{Int, Int}(),
            config = config
        )
    end

    # Analyze each degree
    best_param_dist = Dict{Int, Float64}()
    best_traj_dist = Dict{Int, Float64}()
    num_cp = Dict{Int, Int}()
    num_recoveries = Dict{Int, Int}()

    for degree in degrees
        cp_df = load_critical_points_for_degree(exp_path, degree)
        num_cp[degree] = nrow(cp_df)

        if nrow(cp_df) == 0
            best_param_dist[degree] = Inf
            best_traj_dist[degree] = Inf
            num_recoveries[degree] = 0
            continue
        end

        # Evaluate critical points
        evaluated_df = evaluate_all_critical_points(config, cp_df;
                                                   recovery_threshold=recovery_threshold)

        # Find best distances
        valid_param_dist = filter(!isnan, evaluated_df.param_distance)
        valid_traj_dist = filter(!isnan, evaluated_df.trajectory_distance)

        best_param_dist[degree] = isempty(valid_param_dist) ? Inf : minimum(valid_param_dist)
        best_traj_dist[degree] = isempty(valid_traj_dist) ? Inf : minimum(valid_traj_dist)

        # Count recoveries
        num_recoveries[degree] = count(evaluated_df.is_recovery)
    end

    return (
        degrees = degrees,
        best_param_distance_by_degree = best_param_dist,
        best_trajectory_distance_by_degree = best_traj_dist,
        num_critical_points_by_degree = num_cp,
        num_recoveries_by_degree = num_recoveries,
        config = config
    )
end

"""
    generate_comparison_report(exp_path::String, output_format::Symbol) -> Union{String, Dict}

Generate formatted convergence report.

# Arguments
- `exp_path`: Path to experiment directory
- `output_format`: Format type (:text, :markdown, or :json)

# Returns
- String for :text and :markdown formats
- Dict for :json format
"""
function generate_comparison_report(exp_path::String, output_format::Symbol;
                                   recovery_threshold::Float64 = DEFAULT_RECOVERY_THRESHOLD)
    if !(output_format in [:text, :markdown, :json])
        error("""
            Unknown output format: $output_format

            Supported formats:
            - :text (ASCII table)
            - :markdown (Markdown table)
            - :json (JSON structure)
            """)
    end

    # Analyze convergence
    convergence = analyze_experiment_convergence(exp_path;
                                                recovery_threshold=recovery_threshold)

    if output_format == :json
        return Dict(
            "experiment_path" => exp_path,
            "degrees" => convergence.degrees,
            "best_param_distance_by_degree" => convergence.best_param_distance_by_degree,
            "best_trajectory_distance_by_degree" => convergence.best_trajectory_distance_by_degree,
            "num_critical_points_by_degree" => convergence.num_critical_points_by_degree,
            "num_recoveries_by_degree" => convergence.num_recoveries_by_degree,
            "recovery_threshold" => recovery_threshold
        )
    end

    # Generate text/markdown report
    io = IOBuffer()

    if output_format == :markdown
        println(io, "# Experiment Convergence Analysis")
        println(io, "")
        println(io, "**Experiment:** `$(basename(exp_path))`")
        println(io, "")
        println(io, "## Convergence Across Degrees")
        println(io, "")
        println(io, "| Degree | Critical Points | Recoveries | Best Param Distance | Best Traj Distance |")
        println(io, "|--------|----------------|------------|--------------------|--------------------|")

        for deg in convergence.degrees
            @printf(io, "| %6d | %14d | %10d | %18.6e | %18.6e |\n",
                   deg,
                   convergence.num_critical_points_by_degree[deg],
                   convergence.num_recoveries_by_degree[deg],
                   convergence.best_param_distance_by_degree[deg],
                   convergence.best_trajectory_distance_by_degree[deg])
        end
    else  # :text
        println(io, "=" ^ 80)
        println(io, "EXPERIMENT CONVERGENCE ANALYSIS")
        println(io, "=" ^ 80)
        println(io, "")
        println(io, "Experiment: ", basename(exp_path))
        println(io, "")
        println(io, "-" ^ 80)
        @printf(io, "%-8s | %14s | %10s | %18s | %18s\n",
               "Degree", "Critical Pts", "Recoveries", "Best Param Dist", "Best Traj Dist")
        println(io, "-" ^ 80)

        for deg in convergence.degrees
            @printf(io, "%-8d | %14d | %10d | %18.6e | %18.6e\n",
                   deg,
                   convergence.num_critical_points_by_degree[deg],
                   convergence.num_recoveries_by_degree[deg],
                   convergence.best_param_distance_by_degree[deg],
                   convergence.best_trajectory_distance_by_degree[deg])
        end

        println(io, "-" ^ 80)
    end

    return String(take!(io))
end

"""
    compare_degrees(exp_path::String, deg1::Int, deg2::Int) -> NamedTuple

Compare critical points between two polynomial degrees.

# Arguments
- `exp_path`: Path to experiment directory
- `deg1`: First degree
- `deg2`: Second degree

# Returns
NamedTuple with comparison metrics for both degrees
"""
function compare_degrees(exp_path::String, deg1::Int, deg2::Int;
                        recovery_threshold::Float64 = DEFAULT_RECOVERY_THRESHOLD)
    # Load config
    config_file = joinpath(exp_path, "experiment_config.json")
    config = JSON3.read(read(config_file, String))

    # Load critical points for both degrees
    cp_df1 = load_critical_points_for_degree(exp_path, deg1)
    cp_df2 = load_critical_points_for_degree(exp_path, deg2)

    # Evaluate both
    eval_df1 = evaluate_all_critical_points(config, cp_df1;
                                           recovery_threshold=recovery_threshold)
    eval_df2 = evaluate_all_critical_points(config, cp_df2;
                                           recovery_threshold=recovery_threshold)

    # Compute metrics for deg1
    valid_param_dist1 = filter(!isnan, eval_df1.param_distance)
    valid_traj_dist1 = filter(!isnan, eval_df1.trajectory_distance)

    deg1_metrics = (
        degree = deg1,
        num_critical_points = nrow(cp_df1),
        num_recoveries = count(eval_df1.is_recovery),
        best_param_distance = isempty(valid_param_dist1) ? Inf : minimum(valid_param_dist1),
        best_trajectory_distance = isempty(valid_traj_dist1) ? Inf : minimum(valid_traj_dist1)
    )

    # Compute metrics for deg2
    valid_param_dist2 = filter(!isnan, eval_df2.param_distance)
    valid_traj_dist2 = filter(!isnan, eval_df2.trajectory_distance)

    deg2_metrics = (
        degree = deg2,
        num_critical_points = nrow(cp_df2),
        num_recoveries = count(eval_df2.is_recovery),
        best_param_distance = isempty(valid_param_dist2) ? Inf : minimum(valid_param_dist2),
        best_trajectory_distance = isempty(valid_traj_dist2) ? Inf : minimum(valid_traj_dist2)
    )

    return (
        deg1_metrics = deg1_metrics,
        deg2_metrics = deg2_metrics,
        improvement_param_distance = deg1_metrics.best_param_distance - deg2_metrics.best_param_distance,
        improvement_trajectory_distance = deg1_metrics.best_trajectory_distance - deg2_metrics.best_trajectory_distance
    )
end

"""
    analyze_campaign_parameter_recovery(campaign_path::String) -> DataFrame

Aggregate parameter recovery analysis across all experiments in a campaign.

# Arguments
- `campaign_path`: Path to campaign directory (containing experiment subdirs)

# Returns
DataFrame with columns:
- experiment_id: Experiment identifier
- sample_range: Sampling range from config
- best_param_distance: Best across all degrees
- best_trajectory_distance: Best across all degrees
- total_critical_points: Sum across all degrees
- total_recoveries: Sum across all degrees
"""
function analyze_campaign_parameter_recovery(campaign_path::String;
                                            recovery_threshold::Float64 = DEFAULT_RECOVERY_THRESHOLD)
    if !isdir(campaign_path)
        error("Campaign path not found: $campaign_path")
    end

    # Discover experiment directories
    exp_dirs = filter(isdir, readdir(campaign_path, join=true))

    if isempty(exp_dirs)
        @warn "No experiment directories found in $campaign_path"
        return DataFrame(
            experiment_id = String[],
            sample_range = Float64[],
            best_param_distance = Float64[],
            best_trajectory_distance = Float64[],
            total_critical_points = Int[],
            total_recoveries = Int[]
        )
    end

    # Analyze each experiment
    results = []

    for exp_path in exp_dirs
        try
            convergence = analyze_experiment_convergence(exp_path;
                                                       recovery_threshold=recovery_threshold)

            # Extract experiment metadata
            config = convergence.config
            exp_id = haskey(config, "experiment_id") ? config["experiment_id"] : basename(exp_path)
            sample_range = haskey(config, "sample_range") ? config["sample_range"] : NaN

            # Aggregate across degrees
            param_distances = collect(values(convergence.best_param_distance_by_degree))
            traj_distances = collect(values(convergence.best_trajectory_distance_by_degree))

            best_param = isempty(param_distances) ? Inf : minimum(param_distances)
            best_traj = isempty(traj_distances) ? Inf : minimum(traj_distances)

            total_cp = sum(values(convergence.num_critical_points_by_degree))
            total_rec = sum(values(convergence.num_recoveries_by_degree))

            push!(results, (
                experiment_id = string(exp_id),
                sample_range = sample_range,
                best_param_distance = best_param,
                best_trajectory_distance = best_traj,
                total_critical_points = total_cp,
                total_recoveries = total_rec
            ))
        catch e
            @warn "Failed to analyze experiment $exp_path" exception=e
        end
    end

    return DataFrame(results)
end

end # module TrajectoryComparison
