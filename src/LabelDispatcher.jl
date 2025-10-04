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

    return all_stats
end

"""
    compute_statistics_for_label(label::String, result::ExperimentResult) -> Dict{String, Any}

Dispatch statistics computation based on tracking label.

# Supported Labels
- `"polynomial_quality"`: Approximation quality metrics
- `"convergence_tracking"`: Convergence history analysis
- `"hessian_eigenvalues"`: Hessian eigenvalue statistics
- `"gradient_norms"`: Gradient norm distribution
- `"distance_to_solutions"`: Distance to known solutions
- `"sparsification_tracking"`: Sparsification metrics
- `"performance_metrics"`: Timing and resource usage
- `"critical_point_statistics"`: Critical point classification

# Arguments
- `label::String`: Tracking label to process
- `result::ExperimentResult`: Experiment data

# Returns
- `Dict{String, Any}`: Computed statistics specific to the label
"""
function compute_statistics_for_label(label::String, result::ExperimentResult)
    if label == "polynomial_quality"
        return compute_polynomial_quality_statistics(result)
    elseif label == "convergence_tracking"
        return compute_convergence_statistics(result)
    elseif label == "hessian_eigenvalues"
        return compute_hessian_statistics(result)
    elseif label == "gradient_norms"
        return compute_gradient_norm_statistics(result)
    elseif label == "distance_to_solutions"
        return compute_distance_statistics(result)
    elseif label == "sparsification_tracking"
        return compute_sparsification_statistics(result)
    elseif label == "performance_metrics"
        return compute_performance_statistics(result)
    elseif label == "critical_point_statistics"
        return compute_critical_point_statistics(result)
    else
        @warn "Unknown tracking label: $label"
        return Dict{String, Any}("label" => label, "available" => false, "error" => "unknown_label")
    end
end
