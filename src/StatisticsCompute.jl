"""
    StatisticsCompute.jl

Implementations of statistics computation for each tracking label.
Each function extracts and analyzes specific aspects of experiment results.
"""

"""
    extract_per_degree_data(result::ExperimentResult) -> Dict{String, Any}

Extract data organized by polynomial degree from results_summary format.
Returns a dictionary mapping degree => data_dict.
"""
function extract_per_degree_data(result::ExperimentResult)
    per_degree = Dict{Int, Dict{String, Any}}()

    # Load original results_summary.json to get per-degree data
    results_file = joinpath(result.source_path, "results_summary.json")

    if !isfile(results_file)
        return per_degree
    end

    data = JSON.parsefile(results_file)
    results_summary = get(data, "results_summary", Dict())

    for (degree_key, degree_data) in results_summary
        degree_str = replace(string(degree_key), "degree_" => "")
        degree = parse(Int, degree_str)
        per_degree[degree] = degree_data
    end

    return per_degree
end

"""
    compute_statistics(result::ExperimentResult) -> Dict{String, Any}

Compute all available statistics based on enabled tracking labels.
"""
function compute_statistics(result::ExperimentResult)
    stats = Dict{String, Any}()
    stats["experiment_id"] = result.experiment_id
    stats["enabled_tracking"] = result.enabled_tracking

    # Extract per-degree data
    per_degree = extract_per_degree_data(result)
    stats["per_degree_data"] = per_degree

    # Compute aggregate statistics across all labels
    if "approximation_quality" in result.enabled_tracking
        stats["approximation_quality"] = compute_approximation_quality(result, per_degree)
    end

    if "numerical_stability" in result.enabled_tracking
        stats["numerical_stability"] = compute_numerical_stability(result, per_degree)
    end

    if "parameter_recovery" in result.enabled_tracking
        stats["parameter_recovery"] = compute_parameter_recovery(result, per_degree)
    end

    if "polynomial_timing" in result.enabled_tracking || "solving_timing" in result.enabled_tracking
        stats["performance"] = result.performance_metrics
    end

    if "refinement_quality" in result.enabled_tracking
        stats["refinement"] = result.tolerance_validation
    end

    if "critical_point_count" in result.enabled_tracking || "refined_critical_points" in result.enabled_tracking
        stats["critical_points"] = compute_critical_points_summary(result, per_degree)
    end

    return stats
end

"""
    compute_approximation_quality(result::ExperimentResult, per_degree::Dict) -> Dict{String, Any}

Analyze L2 approximation error across degrees.
"""
function compute_approximation_quality(result::ExperimentResult, per_degree::Dict)
    degrees = sort(collect(keys(per_degree)))
    l2_errors = Float64[]

    for deg in degrees
        push!(l2_errors, get(per_degree[deg], "l2_approx_error", NaN))
    end

    valid_errors = filter(!isnan, l2_errors)

    return Dict(
        "degrees" => degrees,
        "l2_errors" => l2_errors,
        "mean_error" => isempty(valid_errors) ? NaN : mean(valid_errors),
        "min_error" => isempty(valid_errors) ? NaN : minimum(valid_errors),
        "max_error" => isempty(valid_errors) ? NaN : maximum(valid_errors),
        "best_degree" => isempty(valid_errors) ? nothing : degrees[argmin(l2_errors)]
    )
end

"""
    compute_numerical_stability(result::ExperimentResult, per_degree::Dict) -> Dict{String, Any}

Analyze condition numbers across degrees.
"""
function compute_numerical_stability(result::ExperimentResult, per_degree::Dict)
    degrees = sort(collect(keys(per_degree)))
    cond_numbers = Float64[]

    for deg in degrees
        push!(cond_numbers, get(per_degree[deg], "condition_number", NaN))
    end

    valid_conds = filter(!isnan, cond_numbers)

    return Dict(
        "degrees" => degrees,
        "condition_numbers" => cond_numbers,
        "mean_condition" => isempty(valid_conds) ? NaN : mean(valid_conds),
        "max_condition" => isempty(valid_conds) ? NaN : maximum(valid_conds)
    )
end

"""
    compute_parameter_recovery(result::ExperimentResult, per_degree::Dict) -> Dict{String, Any}

Analyze parameter recovery performance (distance to true parameters).
"""
function compute_parameter_recovery(result::ExperimentResult, per_degree::Dict)
    degrees = sort(collect(keys(per_degree)))
    recovery_errors = Float64[]

    for deg in degrees
        push!(recovery_errors, get(per_degree[deg], "recovery_error", NaN))
    end

    valid_errors = filter(!isnan, recovery_errors)

    # Get true parameters if available
    system_info = get(result.metadata, "system_info", Dict())
    true_params = get(system_info, "true_parameters", nothing)

    return Dict(
        "degrees" => degrees,
        "recovery_errors" => recovery_errors,
        "mean_error" => isempty(valid_errors) ? NaN : mean(valid_errors),
        "min_error" => isempty(valid_errors) ? NaN : minimum(valid_errors),
        "best_degree" => isempty(valid_errors) ? nothing : degrees[argmin(recovery_errors)],
        "true_parameters" => true_params
    )
end

"""
    compute_critical_points_summary(result::ExperimentResult, per_degree::Dict) -> Dict{String, Any}

Summarize critical point counts and refinement statistics.
"""
function compute_critical_points_summary(result::ExperimentResult, per_degree::Dict)
    degrees = sort(collect(keys(per_degree)))
    raw_counts = Int[]
    refined_counts = Int[]

    for deg in degrees
        push!(raw_counts, get(per_degree[deg], "critical_points", 0))
        push!(refined_counts, get(per_degree[deg], "critical_points_refined", 0))
    end

    return Dict(
        "degrees" => degrees,
        "raw_critical_points" => raw_counts,
        "refined_critical_points" => refined_counts,
        "total_raw" => sum(raw_counts),
        "total_refined" => sum(refined_counts)
    )
end

"""
    compute_polynomial_quality_statistics(result::ExperimentResult) -> Dict{String, Any}

Compute polynomial approximation quality metrics.
(Legacy function - use compute_statistics instead)
"""
function compute_polynomial_quality_statistics(result::ExperimentResult)
    stats = Dict{String, Any}("label" => "polynomial_quality", "available" => false)

    # Extract from performance metrics or metadata
    if result.performance_metrics !== nothing
        perf = result.performance_metrics
        stats["degree"] = get(perf, "degree", nothing)
        stats["dimension"] = get(perf, "dimension", nothing)
        stats["available"] = true
    elseif haskey(result.metadata, "degree")
        stats["degree"] = result.metadata["degree"]
        stats["dimension"] = get(result.metadata, "dimension", nothing)
        stats["available"] = true
    end

    # L2 norm quality metrics
    if haskey(result.metadata, "L2_norm")
        l2_norm = result.metadata["L2_norm"]
        stats["l2_norm"] = l2_norm
        stats["log10_l2_norm"] = log10(l2_norm)

        # Quality classification
        if l2_norm < 1e-10
            stats["quality_class"] = "excellent"
        elseif l2_norm < 1e-6
            stats["quality_class"] = "good"
        elseif l2_norm < 1e-3
            stats["quality_class"] = "acceptable"
        else
            stats["quality_class"] = "poor"
        end

        stats["available"] = true
    end

    return stats
end

"""
    compute_convergence_statistics(result::ExperimentResult) -> Dict{String, Any}

Compute convergence tracking statistics.
"""
function compute_convergence_statistics(result::ExperimentResult)
    stats = Dict{String, Any}("label" => "convergence_tracking", "available" => false)

    # Placeholder for future convergence data extraction
    # Would parse convergence history if tracked

    return stats
end

"""
    compute_hessian_statistics(result::ExperimentResult) -> Dict{String, Any}

Compute Hessian eigenvalue statistics from critical points.
"""
function compute_hessian_statistics(result::ExperimentResult)
    stats = Dict{String, Any}("label" => "hessian_eigenvalues", "available" => false)

    if result.critical_points === nothing || nrow(result.critical_points) == 0
        return stats
    end

    df = result.critical_points

    # Find eigenvalue columns
    eigenvalue_cols = filter(n -> occursin(r"hessian_eigenvalue_\d+", string(n)), names(df))

    if isempty(eigenvalue_cols)
        return stats
    end

    stats["available"] = true
    stats["num_eigenvalues"] = length(eigenvalue_cols)
    stats["num_critical_points"] = nrow(df)

    # Compute statistics for each eigenvalue
    for col in eigenvalue_cols
        vals = df[!, col]
        col_name = string(col)

        stats["$(col_name)_mean"] = mean(vals)
        stats["$(col_name)_std"] = std(vals)
        stats["$(col_name)_min"] = minimum(vals)
        stats["$(col_name)_max"] = maximum(vals)
    end

    # Classification by eigenvalue signs
    if length(eigenvalue_cols) >= 1
        # Count saddle points, minima, maxima
        first_eigenval = df[!, eigenvalue_cols[1]]

        num_negative = count(x -> x < -1e-6, first_eigenval)
        num_positive = count(x -> x > 1e-6, first_eigenval)
        num_zero = nrow(df) - num_negative - num_positive

        stats["eigenvalue_sign_distribution"] = Dict(
            "negative" => num_negative,
            "positive" => num_positive,
            "near_zero" => num_zero
        )
    end

    return stats
end

"""
    compute_gradient_norm_statistics(result::ExperimentResult) -> Dict{String, Any}

Compute gradient norm statistics at critical points.
"""
function compute_gradient_norm_statistics(result::ExperimentResult)
    stats = Dict{String, Any}("label" => "gradient_norms", "available" => false)

    if result.critical_points === nothing || nrow(result.critical_points) == 0
        return stats
    end

    df = result.critical_points

    if !("gradient_norm" in names(df))
        return stats
    end

    gradient_norms = df.gradient_norm
    stats["available"] = true
    stats["num_points"] = length(gradient_norms)

    # Statistical summary
    stats["mean"] = mean(gradient_norms)
    stats["median"] = median(gradient_norms)
    stats["std"] = std(gradient_norms)
    stats["min"] = minimum(gradient_norms)
    stats["max"] = maximum(gradient_norms)

    # Convergence quality
    tolerance = 1e-6
    num_converged = count(x -> x < tolerance, gradient_norms)
    stats["num_converged"] = num_converged
    stats["convergence_rate"] = num_converged / length(gradient_norms)
    stats["tolerance"] = tolerance

    return stats
end

"""
    compute_distance_statistics(result::ExperimentResult) -> Dict{String, Any}

Compute distance to known solutions (if available).
"""
function compute_distance_statistics(result::ExperimentResult)
    stats = Dict{String, Any}("label" => "distance_to_solutions", "available" => false)

    # Placeholder - would require known solutions in metadata
    # Future implementation

    return stats
end

"""
    compute_sparsification_statistics(result::ExperimentResult) -> Dict{String, Any}

Compute sparsification metrics.
"""
function compute_sparsification_statistics(result::ExperimentResult)
    stats = Dict{String, Any}("label" => "sparsification_tracking", "available" => false)

    # Placeholder for sparsification data
    # Future implementation

    return stats
end

"""
    compute_performance_statistics(result::ExperimentResult) -> Dict{String, Any}

Compute performance profiling statistics.
"""
function compute_performance_statistics(result::ExperimentResult)
    stats = Dict{String, Any}("label" => "performance_metrics", "available" => false)

    if result.performance_metrics === nothing
        return stats
    end

    perf = result.performance_metrics
    stats["available"] = true

    stats["execution_time"] = get(perf, "execution_time", nothing)
    stats["memory_used"] = get(perf, "memory_used", nothing)
    stats["degree"] = get(perf, "degree", nothing)
    stats["dimension"] = get(perf, "dimension", nothing)

    # Compute efficiency metrics if data available
    if haskey(perf, "execution_time") && haskey(perf, "degree")
        stats["time_per_degree"] = perf["execution_time"] / perf["degree"]
    end

    return stats
end

"""
    compute_critical_point_statistics(result::ExperimentResult) -> Dict{String, Any}

Compute critical point distribution and classification statistics.
"""
function compute_critical_point_statistics(result::ExperimentResult)
    stats = Dict{String, Any}("label" => "critical_point_statistics", "available" => false)

    if result.critical_points === nothing || nrow(result.critical_points) == 0
        return stats
    end

    df = result.critical_points
    stats["available"] = true
    stats["total_points"] = nrow(df)

    # Type distribution if available
    if "point_type" in names(df)
        type_counts = Dict{String, Int}()
        for pt_type in unique(df.point_type)
            type_counts[string(pt_type)] = count(==(pt_type), df.point_type)
        end
        stats["type_distribution"] = type_counts
    end

    # Function value statistics
    if "z" in names(df)
        function_values = df.z
        stats["function_value_min"] = minimum(function_values)
        stats["function_value_max"] = maximum(function_values)
        stats["function_value_mean"] = mean(function_values)
        stats["function_value_std"] = std(function_values)
    end

    return stats
end
