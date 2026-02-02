"""
    ReportGenerator.jl

Generates human-readable analysis reports in various formats (Markdown, LaTeX, HTML).
"""

"""
    generate_report(result::ExperimentResult, stats::Dict{String, Any};
                    format::String="markdown") -> String

Generate analysis report for a single experiment.

# Arguments
- `result::ExperimentResult`: Experiment data
- `stats::Dict{String, Any}`: Computed statistics
- `format::String`: Output format ("markdown", "latex", "html")

# Returns
- `String`: Formatted report
"""
function generate_report(result::ExperimentResult, stats::Dict{String, Any};
                         format::String="markdown")
    if format == "markdown"
        return generate_markdown_report(result, stats)
    elseif format == "latex"
        return generate_latex_report(result, stats)
    else
        error("Unsupported format: $format")
    end
end

"""
    generate_markdown_report(result::ExperimentResult, stats::Dict{String, Any}) -> String

Generate Markdown report for single experiment.
"""
function generate_markdown_report(result::ExperimentResult, stats::Dict{String, Any})
    io = IOBuffer()

    # Header
    println(io, "# GlobTim Experiment Analysis Report")
    println(io, "**Experiment ID**: `$(result.experiment_id)`")
    println(io, "**Generated**: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
    println(io, "")

    # Metadata section
    println(io, "## Experiment Configuration")
    println(io, "")
    for (key, value) in result.metadata
        println(io, "- **$key**: $value")
    end
    println(io, "")

    # Tracking labels
    println(io, "## Enabled Tracking")
    println(io, "")
    if !isempty(result.enabled_tracking)
        for label in result.enabled_tracking
            println(io, "- ✓ `$label`")
        end
    else
        println(io, "_No tracking labels enabled_")
    end
    println(io, "")

    # Statistics sections
    println(io, "## Analysis Results")
    println(io, "")

    for (label, label_stats) in stats
        if get(label_stats, "available", false)
            println(io, "### $label")
            println(io, "")

            # Format statistics based on label type
            format_label_statistics!(io, label, label_stats)

            println(io, "")
        end
    end

    # Critical points summary
    if result.critical_points !== nothing && nrow(result.critical_points) > 0
        println(io, "## Critical Points Summary")
        println(io, "")
        println(io, "**Total points found**: $(nrow(result.critical_points))")
        println(io, "")
    end

    # Performance metrics
    if result.performance_metrics !== nothing
        println(io, "## Performance Metrics")
        println(io, "")
        for (key, value) in result.performance_metrics
            println(io, "- **$key**: $value")
        end
        println(io, "")
    end

    # Validation results
    if result.tolerance_validation !== nothing
        println(io, "## Numerical Validation")
        println(io, "")

        all_passed = get(result.tolerance_validation, "all_passed", false)
        status_emoji = all_passed ? "✅" : "⚠️"

        println(io, "$status_emoji **Overall status**: $(all_passed ? "PASSED" : "NEEDS REVIEW")")
        println(io, "")
    end

    return String(take!(io))
end

"""
    format_label_statistics!(io::IO, label::String, stats::Dict{String, Any})

Format statistics for a specific label into markdown.
"""
function format_label_statistics!(io::IO, label::String, stats::Dict{String, Any})
    if label == "polynomial_quality"
        if haskey(stats, "degree")
            println(io, "- **Polynomial Degree**: $(stats["degree"])")
        end
        if haskey(stats, "dimension")
            println(io, "- **Problem Dimension**: $(stats["dimension"])")
        end
        if haskey(stats, "l2_norm")
            println(io, "- **L2 Norm**: $(@sprintf("%.2e", stats["l2_norm"]))")
        end
        if haskey(stats, "quality_class")
            class = stats["quality_class"]
            emoji = class == "excellent" ? "🟢" : class == "good" ? "🟡" :
                    class == "acceptable" ? "🟠" : "🔴"
            println(io, "- **Quality**: $emoji $class")
        end

    elseif label == "gradient_norms"
        if haskey(stats, "mean")
            println(io, "- **Mean gradient norm**: $(@sprintf("%.2e", stats["mean"]))")
        end
        if haskey(stats, "convergence_rate")
            rate = stats["convergence_rate"] * 100
            println(io, "- **Convergence rate**: $(@sprintf("%.1f", rate))%")
        end
        if haskey(stats, "num_converged")
            println(io, "- **Converged points**: $(stats["num_converged"])/$(stats["num_points"])")
        end

    elseif label == "hessian_eigenvalues"
        if haskey(stats, "num_critical_points")
            println(io, "- **Critical points analyzed**: $(stats["num_critical_points"])")
        end
        if haskey(stats, "eigenvalue_sign_distribution")
            dist = stats["eigenvalue_sign_distribution"]
            println(io, "- **Eigenvalue signs**:")
            println(io, "  - Negative: $(dist["negative"])")
            println(io, "  - Positive: $(dist["positive"])")
            println(io, "  - Near zero: $(dist["near_zero"])")
        end

    elseif label == "performance_metrics"
        if haskey(stats, "execution_time")
            println(io, "- **Execution time**: $(@sprintf("%.2f", stats["execution_time"])) seconds")
        end
        if haskey(stats, "time_per_degree")
            println(io, "- **Time per degree**: $(@sprintf("%.2f", stats["time_per_degree"])) seconds")
        end

    elseif label == "critical_point_statistics"
        if haskey(stats, "total_points")
            println(io, "- **Total critical points**: $(stats["total_points"])")
        end
        if haskey(stats, "function_value_min")
            println(io, "- **Min function value**: $(@sprintf("%.4f", stats["function_value_min"]))")
        end
        if haskey(stats, "function_value_max")
            println(io, "- **Max function value**: $(@sprintf("%.4f", stats["function_value_max"]))")
        end
    end
end

"""
    generate_latex_report(result::ExperimentResult, stats::Dict{String, Any}) -> String

Generate LaTeX report for single experiment.
"""
function generate_latex_report(result::ExperimentResult, stats::Dict{String, Any})
    # Placeholder for LaTeX generation
    # Future implementation
    return "% LaTeX report generation not yet implemented"
end

"""
    save_report(report_content::String, output_path::String; format::String="markdown")

Save a report to a file.

# Arguments
- `report_content::String`: The report content to save
- `output_path::String`: Path where report should be saved
- `format::String`: Report format ("markdown", "latex", "html")

# Examples
```julia
report = generate_report(result, stats)
save_report(report, "experiment_report.md")
```
"""
function save_report(report_content::String, output_path::String; format::String="markdown")
    # Ensure directory exists
    output_dir = dirname(output_path)
    if !isempty(output_dir) && !isdir(output_dir)
        mkpath(output_dir)
    end

    # Write to file
    open(output_path, "w") do f
        write(f, report_content)
    end

    println("✓ Report saved to: $output_path")
end

"""
    generate_and_save_report(result::ExperimentResult, stats::Dict{String, Any}, output_path::String; format::String="markdown")

Generate and save a report in one step.

# Arguments
- `result::ExperimentResult`: Experiment data
- `stats::Dict{String, Any}`: Computed statistics
- `output_path::String`: Path where report should be saved
- `format::String`: Output format ("markdown", "latex")

# Returns
- `String`: The generated report content (also saved to file)
"""
function generate_and_save_report(result::ExperimentResult, stats::Dict{String, Any}, output_path::String; format::String="markdown")
    report = generate_report(result, stats, format=format)
    save_report(report, output_path, format=format)
    return report
end

"""
    save_campaign_report(campaign::CampaignResults, output_path::String; format::String="markdown")

Generate and save a campaign report.

# Arguments
- `campaign::CampaignResults`: Campaign to report on
- `output_path::String`: Path where report should be saved
- `format::String`: Output format ("markdown", "latex")

# Returns
- `String`: The generated report content (also saved to file)
"""
function save_campaign_report(campaign::CampaignResults, output_path::String; format::String="markdown")
    report = generate_campaign_report(campaign, format=format)
    save_report(report, output_path, format=format)
    return report
end
