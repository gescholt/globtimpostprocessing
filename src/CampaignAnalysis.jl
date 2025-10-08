"""
    CampaignAnalysis.jl

Multi-experiment campaign analysis and aggregation.
"""

"""
    aggregate_campaign_statistics(campaign::CampaignResults) -> Dict{String, Any}

Compute and aggregate statistics across all experiments in a campaign.

Aggregates:
- Per-metric statistics (mean, min, max, std across experiments)
- Best/worst performing experiments for each metric
- Campaign-wide summaries (total time, total critical points, etc.)
- Parameter variation analysis

# Arguments
- `campaign::CampaignResults`: Campaign containing multiple experiments

# Returns
- `Dict{String, Any}`: Aggregated statistics with the following structure:
  - `"experiments"`: Dict mapping experiment_id -> individual statistics
  - `"aggregated_metrics"`: Dict of metric_name -> {mean, min, max, std, best_exp, worst_exp}
  - `"campaign_summary"`: Overall campaign statistics
  - `"parameter_variations"`: Parameters that vary across experiments
"""
function aggregate_campaign_statistics(
    campaign::CampaignResults;
    progress_callback::Union{Function, Nothing}=nothing
)
    agg_stats = Dict{String, Any}()

    # Store individual experiment statistics
    exp_stats = Dict{String, Any}()

    println("📊 Aggregating statistics across $(length(campaign.experiments)) experiments...")

    total_experiments = length(campaign.experiments)

    # Compute statistics for each experiment
    for (idx, exp) in enumerate(campaign.experiments)
        try
            stats = compute_statistics(exp)
            exp_stats[exp.experiment_id] = stats

            # Call progress callback if provided
            if !isnothing(progress_callback)
                progress_callback(idx, total_experiments, exp.experiment_id)
            end
        catch e
            @warn "Failed to compute statistics for $(exp.experiment_id): $e"
            exp_stats[exp.experiment_id] = Dict("error" => string(e))

            # Still report progress on error
            if !isnothing(progress_callback)
                progress_callback(idx, total_experiments, exp.experiment_id)
            end
        end
    end

    agg_stats["experiments"] = exp_stats

    # Aggregate metrics across experiments
    agg_stats["aggregated_metrics"] = aggregate_metrics_across_experiments(campaign, exp_stats)

    # Create campaign-wide summary
    agg_stats["campaign_summary"] = create_campaign_summary(campaign, exp_stats)

    # Analyze parameter variations
    agg_stats["parameter_variations"] = analyze_parameter_variations(campaign)

    println("✓ Campaign statistics aggregation complete")

    return agg_stats
end

"""
    aggregate_metrics_across_experiments(campaign::CampaignResults, exp_stats::Dict) -> Dict{String, Any}

Aggregate individual metrics across all experiments.

For each metric (approximation_quality, parameter_recovery, etc.):
- Compute mean, min, max, std across experiments
- Identify best and worst performing experiments
"""
function aggregate_metrics_across_experiments(campaign::CampaignResults, exp_stats::Dict)
    metrics = Dict{String, Any}()

    # Discover all metric labels present across experiments
    all_metric_labels = Set{String}()
    for (exp_id, stats) in exp_stats
        if !haskey(stats, "error")
            for label in keys(stats)
                push!(all_metric_labels, label)
            end
        end
    end

    # Aggregate each metric label
    for metric_label in all_metric_labels
        # Collect metric values across experiments
        metric_values = []
        exp_ids = []

        for (exp_id, stats) in exp_stats
            if haskey(stats, metric_label) && get(stats[metric_label], "available", false)
                metric_data = stats[metric_label]

                # Extract key value based on metric type
                key_value = extract_key_metric_value(metric_label, metric_data)

                if key_value !== nothing && !isnan(key_value)
                    push!(metric_values, key_value)
                    push!(exp_ids, exp_id)
                end
            end
        end

        if !isempty(metric_values)
            metrics[metric_label] = Dict{String, Any}(
                "mean" => mean(metric_values),
                "min" => minimum(metric_values),
                "max" => maximum(metric_values),
                "std" => length(metric_values) > 1 ? std(metric_values) : 0.0,
                "best_experiment" => exp_ids[argmin(metric_values)],  # Lower is better for errors
                "worst_experiment" => exp_ids[argmax(metric_values)],
                "num_experiments" => length(metric_values),
                "values" => metric_values,
                "experiment_ids" => exp_ids
            )
        end
    end

    return metrics
end

"""
    extract_key_metric_value(metric_label::String, metric_data::Dict) -> Union{Float64, Nothing}

Extract the primary value for a metric for comparison purposes.
"""
function extract_key_metric_value(metric_label::String, metric_data::Dict)
    if metric_label == "approximation_quality"
        return get(metric_data, "mean_error", nothing)
    elseif metric_label == "parameter_recovery"
        return get(metric_data, "mean_error", nothing)
    elseif metric_label == "numerical_stability"
        return get(metric_data, "mean_condition_number", nothing)
    elseif metric_label == "critical_points"
        return Float64(get(metric_data, "total_refined", 0))
    elseif metric_label == "critical_point_count"
        return Float64(get(metric_data, "total_points", 0))
    elseif metric_label == "refined_critical_points"
        return Float64(get(metric_data, "total_points", 0))
    elseif metric_label == "refinement_quality"
        return get(metric_data, "success_rate", nothing)
    elseif metric_label == "optimization_quality"
        return get(metric_data, "best_objective", nothing)
    elseif metric_label in ["polynomial_timing", "solving_timing", "refinement_timing", "total_timing"]
        return get(metric_data, "mean_time", nothing)
    elseif metric_label == "timing"
        return get(metric_data, "total_time", nothing)
    end

    return nothing
end

"""
    create_campaign_summary(campaign::CampaignResults, exp_stats::Dict) -> Dict{String, Any}

Create overall campaign summary statistics.
"""
function create_campaign_summary(campaign::CampaignResults, exp_stats::Dict)
    summary = Dict{String, Any}()

    summary["campaign_id"] = campaign.campaign_id
    summary["num_experiments"] = length(campaign.experiments)
    summary["collection_timestamp"] = campaign.collection_timestamp

    # Aggregate timing information
    total_time = 0.0
    for exp in campaign.experiments
        exp_time = something(get(exp.metadata, "total_time", nothing), 0.0)
        total_time += exp_time
    end
    summary["total_computation_time"] = total_time
    summary["total_computation_hours"] = total_time / 3600.0

    # Aggregate critical points
    total_cp = 0
    for exp in campaign.experiments
        exp_cp = something(get(exp.metadata, "total_critical_points", nothing), 0)
        total_cp += exp_cp
    end
    summary["total_critical_points"] = total_cp

    # Count successful experiments
    success_count = 0
    for (exp_id, stats) in exp_stats
        if !haskey(stats, "error")
            success_count += 1
        end
    end
    summary["successful_experiments"] = success_count
    summary["success_rate"] = success_count / length(campaign.experiments)

    # Aggregate degrees processed
    all_degrees = Set{Int}()
    for exp in campaign.experiments
        degrees = get(exp.metadata, "degrees_processed", nothing)
        if degrees !== nothing
            if degrees isa Vector
                union!(all_degrees, degrees)
            elseif degrees isa Int
                push!(all_degrees, degrees)
            end
        end
    end
    summary["degrees_covered"] = sort(collect(all_degrees))

    return summary
end

"""
    analyze_parameter_variations(campaign::CampaignResults) -> Dict{String, Any}

Analyze which parameters vary across experiments in the campaign.
"""
function analyze_parameter_variations(campaign::CampaignResults)
    variations = Dict{String, Any}()

    if isempty(campaign.experiments)
        return variations
    end

    # Extract parameter dictionaries from all experiments
    param_dicts = [get(exp.metadata, "params_dict", Dict()) for exp in campaign.experiments]

    # Find all unique parameter keys
    all_keys = Set{String}()
    for pd in param_dicts
        union!(all_keys, keys(pd))
    end

    # Identify varying and constant parameters
    varying_params = Dict{String, Vector{Any}}()
    constant_params = Dict{String, Any}()

    excluded_params = Set(["experiment_id", "timestamp"])

    for key in all_keys
        if key in excluded_params
            continue
        end

        values = [get(pd, key, missing) for pd in param_dicts]
        unique_values = unique(skipmissing(values))

        if length(unique_values) > 1
            varying_params[key] = collect(values)
        elseif length(unique_values) == 1
            constant_params[key] = first(unique_values)
        end
    end

    variations["varying_parameters"] = varying_params
    variations["constant_parameters"] = constant_params
    variations["num_varying"] = length(varying_params)
    variations["num_constant"] = length(constant_params)

    return variations
end

"""
    analyze_campaign(campaign::CampaignResults) -> Dict{String, Any}

Perform comprehensive campaign analysis with statistical summaries.

This is a convenience function that computes aggregate statistics and
prints a human-readable summary to stdout.

# Arguments
- `campaign::CampaignResults`: Campaign to analyze

# Returns
- `Dict{String, Any}`: Aggregated campaign statistics
"""
function analyze_campaign(campaign::CampaignResults)
    println("\n" * "="^80)
    println("📊 CAMPAIGN ANALYSIS: $(campaign.campaign_id)")
    println("="^80)

    # Compute aggregated statistics
    agg_stats = aggregate_campaign_statistics(campaign)

    # Print summary
    summary = agg_stats["campaign_summary"]
    println("\n📋 Campaign Summary:")
    println("  Total experiments: $(summary["num_experiments"])")
    println("  Successful: $(summary["successful_experiments"]) ($(round(summary["success_rate"]*100, digits=1))%)")
    println("  Total computation time: $(round(summary["total_computation_hours"], digits=2)) hours")
    println("  Total critical points: $(summary["total_critical_points"])")
    println("  Degrees covered: $(summary["degrees_covered"])")

    # Print parameter variations
    param_vars = agg_stats["parameter_variations"]
    println("\n🔧 Parameter Analysis:")
    println("  Varying parameters: $(param_vars["num_varying"])")
    for (param, values) in param_vars["varying_parameters"]
        unique_vals = unique(skipmissing(values))
        println("    - $param: $(length(unique_vals)) unique values")
    end
    println("  Constant parameters: $(param_vars["num_constant"])")

    # Print metric aggregations
    metrics = agg_stats["aggregated_metrics"]

    if !isempty(metrics)
        println("\n📊 Aggregated Metrics Across Experiments:")
        println("-" ^ 80)

        for (metric_name, metric_data) in sort(collect(metrics), by=x->x[1])
            println("\n$(metric_name):")
            for (key, value) in metric_data
                if key in ["values", "experiment_ids"]
                    # Skip printing raw arrays
                    continue
                elseif value isa Number
                    println("  $key: $(format_scientific(Float64(value)))")
                else
                    println("  $key: $value")
                end
            end
        end
    else
        println("\n⚠️  No aggregated metrics available")
    end

    println("\n" * "="^80)

    return agg_stats
end

"""
    generate_campaign_report(campaign::CampaignResults; format::String="markdown") -> String

Generate comprehensive campaign analysis report.

# Arguments
- `campaign::CampaignResults`: Campaign to report on
- `format::String`: Output format ("markdown" or "latex")

# Returns
- `String`: Formatted report content
"""
function generate_campaign_report(campaign::CampaignResults; format::String="markdown")
    # Compute aggregated statistics
    agg_stats = aggregate_campaign_statistics(campaign)

    if format == "markdown"
        return generate_campaign_markdown_report(campaign, agg_stats)
    elseif format == "latex"
        return "% LaTeX campaign reports not yet implemented"
    else
        error("Unsupported format: $format")
    end
end

"""
    generate_campaign_markdown_report(campaign::CampaignResults, agg_stats::Dict) -> String

Generate Markdown campaign report.
"""
function generate_campaign_markdown_report(campaign::CampaignResults, agg_stats::Dict)
    io = IOBuffer()

    # Header
    println(io, "# Campaign Analysis Report")
    println(io, "")
    println(io, "**Campaign ID**: `$(campaign.campaign_id)`")
    println(io, "**Generated**: $(Dates.format(now(), "yyyy-mm-dd HH:MM:SS"))")
    println(io, "**Collection Date**: $(Dates.format(campaign.collection_timestamp, "yyyy-mm-dd HH:MM:SS"))")
    println(io, "")

    # Campaign Summary
    summary = agg_stats["campaign_summary"]
    println(io, "## Campaign Summary")
    println(io, "")
    println(io, "| Metric | Value |")
    println(io, "|--------|-------|")
    println(io, "| Total Experiments | $(summary["num_experiments"]) |")
    println(io, "| Successful | $(summary["successful_experiments"]) ($(round(summary["success_rate"]*100, digits=1))%) |")
    println(io, "| Total Computation Time | $(round(summary["total_computation_hours"], digits=2)) hours |")
    println(io, "| Total Critical Points | $(summary["total_critical_points"]) |")
    println(io, "| Degrees Covered | $(join(summary["degrees_covered"], ", ")) |")
    println(io, "")

    # Parameter Variations
    param_vars = agg_stats["parameter_variations"]
    println(io, "## Parameter Analysis")
    println(io, "")

    if param_vars["num_varying"] > 0
        println(io, "### Varying Parameters")
        println(io, "")
        for (param, values) in param_vars["varying_parameters"]
            unique_vals = unique(skipmissing(values))
            println(io, "- **$param**: $(join(unique_vals, ", "))")
        end
        println(io, "")
    end

    if param_vars["num_constant"] > 0
        println(io, "### Constant Parameters")
        println(io, "")
        for (param, value) in param_vars["constant_parameters"]
            println(io, "- **$param**: $value")
        end
        println(io, "")
    end

    # Aggregated Metrics
    metrics = agg_stats["aggregated_metrics"]
    println(io, "## Aggregated Metrics Across Experiments")
    println(io, "")

    if haskey(metrics, "approximation_quality")
        println(io, "### Approximation Quality (L2 Error)")
        println(io, "")
        aq = metrics["approximation_quality"]
        println(io, "| Statistic | Value |")
        println(io, "|-----------|-------|")
        println(io, "| Mean | $(format_scientific(aq["mean"])) |")
        println(io, "| Min | $(format_scientific(aq["min"])) |")
        println(io, "| Max | $(format_scientific(aq["max"])) |")
        println(io, "| Std Dev | $(format_scientific(aq["std"])) |")
        println(io, "| Best Experiment | $(aq["best_experiment"]) |")
        println(io, "| Worst Experiment | $(aq["worst_experiment"]) |")
        println(io, "")
    end

    if haskey(metrics, "parameter_recovery")
        println(io, "### Parameter Recovery")
        println(io, "")
        pr = metrics["parameter_recovery"]
        println(io, "| Statistic | Value |")
        println(io, "|-----------|-------|")
        println(io, "| Mean Error | $(format_scientific(pr["mean"])) |")
        println(io, "| Min Error | $(format_scientific(pr["min"])) |")
        println(io, "| Max Error | $(format_scientific(pr["max"])) |")
        println(io, "| Best Experiment | $(pr["best_experiment"]) |")
        println(io, "")
    end

    if haskey(metrics, "numerical_stability")
        println(io, "### Numerical Stability")
        println(io, "")
        ns = metrics["numerical_stability"]
        println(io, "| Statistic | Value |")
        println(io, "|-----------|-------|")
        println(io, "| Mean Condition Number | $(format_scientific(ns["mean"])) |")
        println(io, "| Max Condition Number | $(format_scientific(ns["max"])) |")
        println(io, "")
    end

    if haskey(metrics, "critical_points")
        println(io, "### Critical Points")
        println(io, "")
        cp = metrics["critical_points"]
        println(io, "| Statistic | Value |")
        println(io, "|-----------|-------|")
        println(io, "| Mean per Experiment | $(round(cp["mean"], digits=1)) |")
        println(io, "| Min | $(Int(cp["min"])) |")
        println(io, "| Max | $(Int(cp["max"])) |")
        println(io, "")
    end

    # Individual Experiment Results Table
    println(io, "## Individual Experiment Results")
    println(io, "")
    println(io, "| Experiment | L2 Error | Param Recovery | Critical Points | Status |")
    println(io, "|------------|----------|----------------|-----------------|--------|")

    for exp in campaign.experiments
        exp_id = exp.experiment_id

        if haskey(agg_stats["experiments"], exp_id)
            stats = agg_stats["experiments"][exp_id]

            l2_err = "N/A"
            if haskey(stats, "approximation_quality") && get(stats["approximation_quality"], "available", false)
                l2_err = format_scientific(stats["approximation_quality"]["mean_error"])
            end

            param_rec = "N/A"
            if haskey(stats, "parameter_recovery") && get(stats["parameter_recovery"], "available", false)
                param_rec = format_scientific(stats["parameter_recovery"]["mean_error"])
            end

            cp_count = something(get(exp.metadata, "total_critical_points", nothing), "N/A")

            status = haskey(stats, "error") ? "⚠️ Error" : "✓ Success"

            println(io, "| $exp_id | $l2_err | $param_rec | $cp_count | $status |")
        end
    end
    println(io, "")

    # Footer
    println(io, "---")
    println(io, "_Generated by GlobtimPostProcessing_")

    return String(take!(io))
end

"""
    format_scientific(x::Float64) -> String

Format a float in scientific notation for reports.
"""
function format_scientific(x::Float64)
    if isnan(x)
        return "N/A"
    elseif abs(x) < 1e-10
        return @sprintf("%.2e", x)
    elseif abs(x) < 0.01
        return @sprintf("%.2e", x)
    else
        return @sprintf("%.4f", x)
    end
end
