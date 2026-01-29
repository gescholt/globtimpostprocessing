"""
Refinement I/O Utilities

Provides functions to load raw critical points from globtim output
and save refined results to CSV/JSON files.

Created: 2025-11-22 (Architecture cleanup)
"""

"""
    RawCriticalPointsData

Container for loaded raw critical points data.

# Fields
- `points::Vector{Vector{Float64}}`: Raw critical points
- `degree::Int`: Polynomial degree used
- `n_points::Int`: Number of critical points
- `source_file::String`: Path to source CSV file
"""
struct RawCriticalPointsData
    points::Vector{Vector{Float64}}
    degree::Int
    n_points::Int
    source_file::String
end

"""
    load_raw_critical_points(experiment_dir::String; degree::Union{Int,Nothing}=nothing)

Load raw critical points from globtim experiment output directory.

Searches for `critical_points_raw_deg_X.csv` (new format) or falls back to
`critical_points_deg_X.csv` (old format for backward compatibility).

# Arguments
- `experiment_dir::String`: Path to globtim output directory
- `degree::Union{Int,Nothing}`: Specific degree to load (default: highest degree found)

# Returns
`RawCriticalPointsData` containing points and metadata

# Examples
```julia
# Load highest degree
raw_data = load_raw_critical_points("../globtim_results/lv4d_exp_20251122")

# Load specific degree
raw_data = load_raw_critical_points("../globtim_results/lv4d_exp_20251122", degree=12)

println("Loaded ", raw_data.n_points, " points at degree ", raw_data.degree)
```

# Errors
Throws error if no critical points files found in directory.
"""
function load_raw_critical_points(
    experiment_dir::String;
    degree::Union{Int,Nothing} = nothing
)
    # Search for critical points CSV files
    raw_pattern = r"critical_points_raw_deg_(\d+)\.csv"
    legacy_pattern = r"critical_points_deg_(\d+)\.csv"

    # Get all CSV files in directory
    csv_files = filter(f -> endswith(f, ".csv"), readdir(experiment_dir))

    # Find raw critical points files (new format)
    raw_files = filter(f -> occursin(raw_pattern, f), csv_files)

    # Fall back to legacy format if no raw files found
    if isempty(raw_files)
        raw_files = filter(f -> occursin(legacy_pattern, f), csv_files)
        pattern = legacy_pattern
        is_legacy = true
    else
        pattern = raw_pattern
        is_legacy = false
    end

    # Error if no files found
    if isempty(raw_files)
        error("No critical points CSV files found in $experiment_dir")
    end

    # Parse degrees from filenames
    available_degrees = Int[]
    degree_to_file = Dict{Int, String}()

    for file in raw_files
        m = match(pattern, file)
        if m !== nothing
            deg = parse(Int, m.captures[1])
            push!(available_degrees, deg)
            degree_to_file[deg] = joinpath(experiment_dir, file)
        end
    end

    # Select degree to load
    if degree === nothing
        # Load highest degree available
        selected_degree = maximum(available_degrees)
    else
        # Load specified degree
        if !(degree in available_degrees)
            error("Degree $degree not found. Available degrees: $available_degrees")
        end
        selected_degree = degree
    end

    csv_path = degree_to_file[selected_degree]

    # Load CSV
    df = CSV.read(csv_path, DataFrame)

    # Extract critical points (assuming columns are dimensions)
    # Find dimension columns (starts with dim, x, or p)
    dim_cols = filter(c -> occursin(r"^(dim|x|p)\d+$", String(c)), names(df))

    if isempty(dim_cols)
        # Fall back to all numeric columns
        dim_cols = names(df, Real)
    end

    # Convert to Vector{Vector{Float64}}
    points = [Vector{Float64}(row[dim_cols]) for row in eachrow(df)]

    return RawCriticalPointsData(
        points,
        selected_degree,
        length(points),
        csv_path
    )
end

"""
    RefinedExperimentResult

Results from refining critical points of an experiment.

# Fields
- `raw_points::Vector{Vector{Float64}}`: Original critical points from HomotopyContinuation
- `refined_points::Vector{Vector{Float64}}`: Successfully refined critical points
- `raw_values::Vector{Float64}`: Objective values at raw points
- `refined_values::Vector{Float64}`: Objective values at refined points
- `improvements::Vector{Float64}`: |f(refined) - f(raw)| for each point
- `convergence_status::Vector{Bool}`: Convergence status for each raw point
- `iterations::Vector{Int}`: Iterations per point
- `n_raw::Int`: Total number of raw critical points
- `n_converged::Int`: Number of successful refinements
- `n_failed::Int`: Number of failed refinements
- `n_timeout::Int`: Number of timeouts
- `mean_improvement::Float64`: Mean improvement for converged points
- `max_improvement::Float64`: Maximum improvement
- `best_raw_idx::Int`: Index of best raw point
- `best_refined_idx::Int`: Index of best refined point (among converged)
- `best_raw_value::Float64`: Best objective value among raw points
- `best_refined_value::Float64`: Best objective value among refined points
- `output_dir::String`: Directory where results are saved
- `degree::Int`: Polynomial degree used
- `total_time::Float64`: Total refinement time (seconds)
- `refinement_config::RefinementConfig`: Configuration used
"""
struct RefinedExperimentResult
    raw_points::Vector{Vector{Float64}}
    refined_points::Vector{Vector{Float64}}
    raw_values::Vector{Float64}
    refined_values::Vector{Float64}
    improvements::Vector{Float64}
    convergence_status::Vector{Bool}
    iterations::Vector{Int}
    n_raw::Int
    n_converged::Int
    n_failed::Int
    n_timeout::Int
    mean_improvement::Float64
    max_improvement::Float64
    best_raw_idx::Int
    best_refined_idx::Int
    best_raw_value::Float64
    best_refined_value::Float64
    output_dir::String
    degree::Int
    total_time::Float64
    refinement_config::RefinementConfig
end

"""
    save_refined_results(experiment_dir::String, result::RefinedExperimentResult, degree::Int, refinement_results::Vector{RefinementResult}; gradient_validation::Union{GradientValidationResult, Nothing}=nothing)

Save refined critical points and comparison data to experiment directory.

# Files Created
- `critical_points_refined_deg_X.csv`: Refined critical points
- `refinement_comparison_deg_X.csv`: Raw vs refined side-by-side (with Tier 1 diagnostics and gradient validation)
- `refinement_summary.json`: Statistics and metadata (with convergence breakdown and gradient validation)

# Arguments
- `experiment_dir::String`: Experiment output directory
- `result::RefinedExperimentResult`: Refinement results
- `degree::Int`: Polynomial degree
- `refinement_results::Vector{RefinementResult}`: Detailed per-point refinement results (for Tier 1 diagnostics)
- `gradient_validation::Union{GradientValidationResult, Nothing}=nothing`: Optional gradient validation results

# Examples
```julia
save_refined_results(experiment_dir, result, 12, refinement_results)

# With gradient validation
gradient_result = validate_critical_points(refined_points, objective_func)
save_refined_results(experiment_dir, result, 12, refinement_results; gradient_validation=gradient_result)
```
"""
function save_refined_results(
    experiment_dir::String,
    result::RefinedExperimentResult,
    degree::Int,
    refinement_results::Vector{RefinementResult};
    gradient_validation::Union{GradientValidationResult, Nothing} = nothing
)
    # 1. Save refined critical points CSV
    refined_csv_path = joinpath(experiment_dir, "critical_points_refined_deg_$degree.csv")

    if !isempty(result.refined_points)
        n_dim = length(result.refined_points[1])
        dim_cols = [Symbol("dim$i") for i in 1:n_dim]

        # Build DataFrame
        refined_df = DataFrame()
        for (i, col) in enumerate(dim_cols)
            refined_df[!, col] = [pt[i] for pt in result.refined_points]
        end

        # Add objective values and iterations
        refined_df[!, :objective_value] = result.refined_values
        refined_df[!, :improvement] = result.improvements
        refined_df[!, :iterations] = result.iterations[result.convergence_status]

        CSV.write(refined_csv_path, refined_df)
    end

    # 2. Save comparison CSV (raw vs refined)
    comparison_csv_path = joinpath(experiment_dir, "refinement_comparison_deg_$degree.csv")

    n_dim = length(result.raw_points[1])
    comparison_df = DataFrame()

    # Raw points
    for i in 1:n_dim
        comparison_df[!, Symbol("raw_dim$i")] = [pt[i] for pt in result.raw_points]
    end
    comparison_df[!, :raw_value] = result.raw_values

    # Refined points (or NaN for failed)
    for i in 1:n_dim
        refined_col = Vector{Float64}(undef, result.n_raw)
        for (j, converged) in enumerate(result.convergence_status)
            if converged
                # Find index in refined_points
                converged_idx = sum(result.convergence_status[1:j])
                refined_col[j] = result.refined_points[converged_idx][i]
            else
                refined_col[j] = NaN
            end
        end
        comparison_df[!, Symbol("refined_dim$i")] = refined_col
    end

    # Refined values (or NaN for failed)
    refined_value_col = Vector{Float64}(undef, result.n_raw)
    for (j, converged) in enumerate(result.convergence_status)
        if converged
            converged_idx = sum(result.convergence_status[1:j])
            refined_value_col[j] = result.refined_values[converged_idx]
        else
            refined_value_col[j] = NaN
        end
    end
    comparison_df[!, :refined_value] = refined_value_col

    # Status and improvement
    comparison_df[!, :converged] = result.convergence_status
    comparison_df[!, :iterations] = result.iterations

    # Tier 1 Diagnostics: Add call counts, timing, and convergence details
    comparison_df[!, :f_calls] = [r.f_calls for r in refinement_results]
    comparison_df[!, :g_calls] = [r.g_calls for r in refinement_results]
    comparison_df[!, :h_calls] = [r.h_calls for r in refinement_results]
    comparison_df[!, :time_elapsed] = [r.time_elapsed for r in refinement_results]
    comparison_df[!, :x_converged] = [r.x_converged for r in refinement_results]
    comparison_df[!, :f_converged] = [r.f_converged for r in refinement_results]
    comparison_df[!, :g_converged] = [r.g_converged for r in refinement_results]
    comparison_df[!, :iter_limit] = [r.iteration_limit_reached for r in refinement_results]
    comparison_df[!, :convergence_reason] = [String(r.convergence_reason) for r in refinement_results]

    # Add gradient validation columns if provided
    # Gradient validation only covers converged points, so expand to n_raw
    if gradient_validation !== nothing
        gradient_norms = fill(Inf, result.n_raw)
        gradient_valid_col = fill(false, result.n_raw)
        for (j, converged) in enumerate(result.convergence_status)
            if converged
                converged_idx = sum(result.convergence_status[1:j])
                gradient_norms[j] = gradient_validation.norms[converged_idx]
                gradient_valid_col[j] = gradient_validation.valid[converged_idx]
            end
        end
        comparison_df[!, :gradient_norm] = gradient_norms
        comparison_df[!, :gradient_valid] = gradient_valid_col
    end

    CSV.write(comparison_csv_path, comparison_df)

    # 3. Save summary JSON
    summary_json_path = joinpath(experiment_dir, "refinement_summary_deg_$degree.json")

    # Tier 1 Diagnostics: Compute convergence breakdown
    convergence_reasons = [r.convergence_reason for r in refinement_results]
    convergence_breakdown = Dict{String, Int}()
    for reason in unique(convergence_reasons)
        convergence_breakdown[String(reason)] = count(==(reason), convergence_reasons)
    end

    # Tier 1 Diagnostics: Call count statistics
    f_calls_all = [r.f_calls for r in refinement_results]
    g_calls_all = [r.g_calls for r in refinement_results]
    time_elapsed_all = [r.time_elapsed for r in refinement_results]

    call_counts = Dict(
        "mean_f_calls" => Statistics.mean(f_calls_all),
        "max_f_calls" => maximum(f_calls_all),
        "min_f_calls" => minimum(f_calls_all),
        "mean_g_calls" => Statistics.mean(g_calls_all),
        "max_g_calls" => maximum(g_calls_all)
    )

    # Tier 1 Diagnostics: Timing statistics
    timing = Dict(
        "mean_time_per_point" => Statistics.mean(time_elapsed_all),
        "max_time_per_point" => maximum(time_elapsed_all),
        "min_time_per_point" => minimum(time_elapsed_all),
        "points_timed_out" => result.n_timeout
    )

    # Gradient validation statistics (if provided)
    gradient_stats = if gradient_validation !== nothing
        Dict(
            "n_valid" => gradient_validation.n_valid,
            "n_invalid" => gradient_validation.n_invalid,
            "tolerance" => gradient_validation.tolerance,
            "mean_norm" => gradient_validation.mean_norm,
            "max_norm" => gradient_validation.max_norm,
            "min_norm" => gradient_validation.min_norm,
            "validation_rate" => gradient_validation.n_valid / length(gradient_validation.norms)
        )
    else
        nothing
    end

    summary = Dict(
        "degree" => degree,
        "n_raw_points" => result.n_raw,
        "n_converged" => result.n_converged,
        "n_failed" => result.n_failed,
        "n_timeout" => result.n_timeout,
        "convergence_rate" => result.n_converged / result.n_raw,
        "mean_improvement" => result.mean_improvement,
        "max_improvement" => result.max_improvement,
        "best_raw_value" => result.best_raw_value,
        "best_refined_value" => result.best_refined_value,
        "total_refinement_time" => result.total_time,
        # Tier 1 Diagnostics
        "convergence_breakdown" => convergence_breakdown,
        "call_counts" => call_counts,
        "timing" => timing,
        # Gradient validation
        "gradient_validation" => gradient_stats,
        "config" => Dict(
            "method" => string(typeof(result.refinement_config.method)),
            "max_time_per_point" => result.refinement_config.max_time_per_point,
            "f_abstol" => result.refinement_config.f_abstol,
            "x_abstol" => result.refinement_config.x_abstol,
            "max_iterations" => result.refinement_config.max_iterations
        ),
        "timestamp" => Dates.now()
    )

    # Replace NaN/Inf with null for JSON compatibility
    function sanitize_for_json(x)
        if x isa Float64 && (isnan(x) || isinf(x))
            return nothing
        elseif x isa Dict
            return Dict(k => sanitize_for_json(v) for (k, v) in x)
        elseif x isa Vector
            return [sanitize_for_json(v) for v in x]
        else
            return x
        end
    end

    sanitized_summary = sanitize_for_json(summary)

    open(summary_json_path, "w") do io
        # Use JSON.json() which handles Inf/NaN by default
        json_str = JSON.json(sanitized_summary)
        write(io, json_str)
    end

end
