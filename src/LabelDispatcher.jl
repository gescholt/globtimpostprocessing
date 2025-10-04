"""
    LabelDispatcher.jl

Maps tracking labels to appropriate statistics computation functions.
This is the core of the label-aware adaptive processing system.
"""

"""
    compute_statistics(result::ExperimentResult) -> Dict{String, Any}

Compute all statistics for enabled tracking labels in an experiment.

This function reads the `enabled_tracking` field and dispatches to
appropriate statistic computation functions for each label.

# Arguments
- `result::ExperimentResult`: Experiment result with metadata and data

# Returns
- `Dict{String, Any}`: Map from label → computed statistics
"""
function compute_statistics(result::ExperimentResult)
    all_stats = Dict{String, Any}()

    if isempty(result.enabled_tracking)
        @warn "No enabled tracking labels found for experiment $(result.experiment_id)"
        return all_stats
    end

    println("📊 Computing statistics for $(length(result.enabled_tracking)) tracking labels...")

    for label in result.enabled_tracking
        try
            stats = compute_statistics_for_label(label, result)
            all_stats[label] = stats
            println("  ✓ $label")
        catch e
            @warn "Failed to compute statistics for label '$label': $e"
            all_stats[label] = Dict("error" => string(e), "available" => false)
        end
    end

    # Create aggregated statistics for plotting
    # Aggregate critical_point_count and refined_critical_points into "critical_points"
    if haskey(all_stats, "critical_point_count") || haskey(all_stats, "refined_critical_points")
        all_stats["critical_points"] = create_critical_points_aggregated_stats(all_stats, result)
    end

    # Aggregate timing labels into "timing"
    timing_labels = ["polynomial_timing", "solving_timing", "refinement_timing", "total_timing"]
    if any(haskey(all_stats, label) for label in timing_labels)
        all_stats["timing"] = create_timing_aggregated_stats(all_stats, result)
    end

    return all_stats
end

"""
    compute_statistics_for_label(label::String, result::ExperimentResult) -> Dict{String, Any}

Dispatch statistics computation based on tracking label.

# Supported Labels
- `"polynomial_quality"` / `"approximation_quality"`: Approximation quality metrics
- `"convergence_tracking"`: Convergence history analysis
- `"hessian_eigenvalues"`: Hessian eigenvalue statistics
- `"gradient_norms"`: Gradient norm distribution
- `"distance_to_solutions"` / `"distance_to_true_parameters"`: Distance to known solutions
- `"sparsification_tracking"`: Sparsification metrics
- `"performance_metrics"`: Timing and resource usage
- `"critical_point_statistics"` / `"critical_point_count"` / `"refined_critical_points"`: Critical point classification
- `"parameter_recovery"`: Parameter recovery error metrics
- `"numerical_stability"`: Condition number analysis
- `"polynomial_timing"` / `"solving_timing"` / `"refinement_timing"` / `"total_timing"`: Timing breakdowns
- `"refinement_quality"`: Refinement convergence statistics
- `"optimization_quality"`: Optimization objective values

# Arguments
- `label::String`: Tracking label to process
- `result::ExperimentResult`: Experiment data

# Returns
- `Dict{String, Any}`: Computed statistics specific to the label
"""
function compute_statistics_for_label(label::String, result::ExperimentResult)
    # Old label names (for backwards compatibility)
    if label == "polynomial_quality" || label == "approximation_quality"
        return compute_approximation_quality_statistics(result)
    elseif label == "convergence_tracking"
        return compute_convergence_statistics(result)
    elseif label == "hessian_eigenvalues"
        return compute_hessian_statistics(result)
    elseif label == "gradient_norms"
        return compute_gradient_norm_statistics(result)
    elseif label == "distance_to_solutions" || label == "distance_to_true_parameters"
        return compute_distance_statistics(result)
    elseif label == "sparsification_tracking"
        return compute_sparsification_statistics(result)
    elseif label == "performance_metrics"
        return compute_performance_statistics(result)
    elseif label == "critical_point_statistics" || label == "critical_point_count" || label == "refined_critical_points"
        return compute_critical_point_statistics(result)
    # New label names from results_summary format
    elseif label == "parameter_recovery"
        return compute_parameter_recovery_statistics(result)
    elseif label == "numerical_stability"
        return compute_numerical_stability_statistics(result)
    elseif label == "polynomial_timing" || label == "solving_timing" || label == "refinement_timing" || label == "total_timing"
        return compute_timing_statistics(result, label)
    elseif label == "refinement_quality"
        return compute_refinement_quality_statistics(result)
    elseif label == "optimization_quality"
        return compute_optimization_quality_statistics(result)
    else
        @warn "Unknown tracking label: $label"
        return Dict{String, Any}("label" => label, "available" => false, "error" => "unknown_label")
    end
end

"""
    create_critical_points_aggregated_stats(all_stats::Dict, result::ExperimentResult) -> Dict{String, Any}

Create aggregated critical points statistics for plotting from individual label stats.
"""
function create_critical_points_aggregated_stats(all_stats::Dict, result::ExperimentResult)
    stats = Dict{String, Any}("label" => "critical_points", "available" => false)

    results_summary = get(result.metadata, "results_summary", Dict())
    if isempty(results_summary)
        return stats
    end

    refined = Int[]
    raw = Int[]
    degrees = Int[]

    for (degree_key, degree_data) in results_summary
        deg = parse(Int, replace(degree_key, "degree_" => ""))
        push!(degrees, deg)
        push!(refined, get(degree_data, "critical_points_refined", 0))
        push!(raw, get(degree_data, "critical_points_raw", 0))
    end

    if isempty(degrees)
        return stats
    end

    stats["available"] = true
    stats["degrees"] = degrees
    stats["refined_critical_points"] = refined
    stats["raw_critical_points"] = raw
    stats["total_refined"] = sum(refined)
    stats["total_raw"] = sum(raw)

    return stats
end

"""
    create_timing_aggregated_stats(all_stats::Dict, result::ExperimentResult) -> Dict{String, Any}

Create aggregated timing statistics for plotting from individual timing labels.
"""
function create_timing_aggregated_stats(all_stats::Dict, result::ExperimentResult)
    stats = Dict{String, Any}("label" => "timing", "available" => false)

    results_summary = get(result.metadata, "results_summary", Dict())
    if isempty(results_summary)
        return stats
    end

    # Create per_degree_data dict expected by plotting
    per_degree_data = Dict{Int, Dict{String, Any}}()

    for (degree_key, degree_data) in results_summary
        deg = parse(Int, replace(degree_key, "degree_" => ""))
        per_degree_data[deg] = Dict{String, Any}(
            "polynomial_construction_time" => get(degree_data, "polynomial_construction_time", 0.0),
            "critical_point_solving_time" => get(degree_data, "critical_point_solving_time", 0.0),
            "refinement_time" => get(degree_data, "refinement_time", 0.0),
            "total_computation_time" => get(degree_data, "total_computation_time", 0.0)
        )
    end

    if isempty(per_degree_data)
        return stats
    end

    stats["available"] = true
    stats["per_degree_data"] = per_degree_data

    return stats
end
