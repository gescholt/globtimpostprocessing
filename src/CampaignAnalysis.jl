"""
    CampaignAnalysis.jl

Multi-experiment campaign analysis and aggregation.
"""

using PrettyTables
using CSV
using DataFrames
using LinearAlgebra
using Printf
using Statistics

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
            # Include metadata for parameter extraction in reporting
            stats["metadata"] = exp.metadata
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

Aggregate individual metrics across all experiments, grouped by polynomial degree.

For each metric (approximation_quality, parameter_recovery, etc.) and each degree:
- Compute mean, min, max, std across experiments
- Identify best and worst performing experiments

Returns nested structure: metrics[metric_label][degree] = aggregated_stats

For metrics computed from CSV files (critical_point_count, numerical_stability), this
function computes per-degree statistics directly from the CSV files.
"""
function aggregate_metrics_across_experiments(campaign::CampaignResults, exp_stats::Dict)
    metrics = Dict{String, Any}()

    # First, aggregate CSV-based metrics by degree
    csv_metrics = aggregate_csv_metrics_by_degree(campaign)
    merge!(metrics, csv_metrics)

    # Then aggregate other metrics (those already in exp_stats)
    all_metric_labels = Set{String}()
    for (exp_id, stats) in exp_stats
        if !haskey(stats, "error")
            for label in keys(stats)
                # Skip metrics we've already aggregated from CSV
                if !haskey(metrics, label)
                    push!(all_metric_labels, label)
                end
            end
        end
    end

    # Aggregate each remaining metric label
    for metric_label in all_metric_labels
        # Collect metric values (not grouped by degree for non-CSV metrics)
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
            # Use degree = 0 to indicate "aggregated across all degrees"
            metrics[metric_label] = Dict{Int, Any}(
                0 => Dict{String, Any}(
                    "mean" => mean(metric_values),
                    "min" => minimum(metric_values),
                    "max" => maximum(metric_values),
                    "std" => length(metric_values) > 1 ? std(metric_values) : 0.0,
                    "best_experiment" => exp_ids[argmin(metric_values)],
                    "worst_experiment" => exp_ids[argmax(metric_values)],
                    "num_experiments" => length(metric_values),
                    "values" => metric_values,
                    "experiment_ids" => exp_ids
                )
            )
        end
    end

    return metrics
end

"""
    aggregate_csv_metrics_by_degree(campaign::CampaignResults) -> Dict{String, Any}

Compute per-degree statistics directly from CSV files for critical point metrics.

Returns metrics organized by degree:
- critical_point_count[degree] = {mean, min, max, std, ...}
- numerical_stability[degree] = {mean, min, max, std, ...}
"""
function aggregate_csv_metrics_by_degree(campaign::CampaignResults)
    metrics = Dict{String, Any}()

    # Track values by degree across experiments
    cp_count_by_degree = Dict{Int, Vector{Float64}}()
    cp_count_exp_ids = Dict{Int, Vector{String}}()

    cond_number_by_degree = Dict{Int, Vector{Float64}}()
    cond_number_exp_ids = Dict{Int, Vector{String}}()

    for exp in campaign.experiments
        exp_path = exp.source_path

        # Find all CSV files for this experiment
        csv_files = filter(f -> startswith(basename(f), "critical_points_deg_"),
                          readdir(exp_path, join=true, sort=false))

        for csv_file in csv_files
            # Extract degree from filename
            m = match(r"deg_(\d+)\.csv", basename(csv_file))
            if m === nothing
                continue
            end
            degree = parse(Int, m[1])

            # Load CSV and compute statistics for this degree
            try
                df = CSV.read(csv_file, DataFrame)

                if nrow(df) > 0
                    # Critical point count
                    if !haskey(cp_count_by_degree, degree)
                        cp_count_by_degree[degree] = Float64[]
                        cp_count_exp_ids[degree] = String[]
                    end
                    push!(cp_count_by_degree[degree], Float64(nrow(df)))
                    push!(cp_count_exp_ids[degree], exp.experiment_id)

                    # Numerical stability (condition number from Hessian if available)
                    # For now, use a placeholder - would need Hessian eigenvalues
                    # This is just counting, actual condition number would require eigenvalues
                end
            catch e
                @warn "Failed to load $csv_file: $e"
            end
        end
    end

    # Create aggregated statistics for critical_point_count
    if !isempty(cp_count_by_degree)
        metrics["critical_point_count"] = Dict{Int, Any}()

        for deg in sort(collect(keys(cp_count_by_degree)))
            values = cp_count_by_degree[deg]
            exp_ids = cp_count_exp_ids[deg]

            metrics["critical_point_count"][deg] = Dict{String, Any}(
                "mean" => mean(values),
                "min" => minimum(values),
                "max" => maximum(values),
                "std" => length(values) > 1 ? std(values) : 0.0,
                "best_experiment" => exp_ids[argmin(values)],
                "worst_experiment" => exp_ids[argmax(values)],
                "num_experiments" => length(values),
                "values" => values,
                "experiment_ids" => exp_ids
            )
        end
    end

    # Add numerical_stability if we computed it
    if !isempty(cond_number_by_degree)
        metrics["numerical_stability"] = Dict{Int, Any}()

        for deg in sort(collect(keys(cond_number_by_degree)))
            values = cond_number_by_degree[deg]
            exp_ids = cond_number_exp_ids[deg]

            metrics["numerical_stability"][deg] = Dict{String, Any}(
                "mean" => mean(values),
                "min" => minimum(values),
                "max" => maximum(values),
                "std" => length(values) > 1 ? std(values) : 0.0,
                "best_experiment" => exp_ids[argmin(values)],
                "worst_experiment" => exp_ids[argmax(values)],
                "num_experiments" => length(values),
                "values" => values,
                "experiment_ids" => exp_ids
            )
        end
    end

    return metrics
end

"""
    extract_key_metric_value_from_degree_data(metric_label::String, degree_data::Dict) -> Union{Float64, Nothing}

Extract the primary value from degree-level metric data for comparison purposes.
"""
function extract_key_metric_value_from_degree_data(metric_label::String, degree_data::Dict)
    # For degree-level data, use the same extraction logic as for aggregated data
    return extract_key_metric_value(metric_label, degree_data)
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
    # Check if this is a single experiment (show per-degree stats) or multi-experiment campaign
    is_single_experiment = length(campaign.experiments) == 1

    println("\n" * "="^80)
    if is_single_experiment
        println("📊 SINGLE EXPERIMENT ANALYSIS: $(campaign.campaign_id)")
        println("="^80)
        println("\nNote: Showing per-degree statistics (1 experiment)")
    else
        println("📊 CAMPAIGN ANALYSIS: $(campaign.campaign_id)")
        println("="^80)
    end

    # Compute aggregated statistics
    agg_stats = aggregate_campaign_statistics(campaign)

    # Print summary
    summary = agg_stats["campaign_summary"]
    println("\n📋 $(is_single_experiment ? "Experiment" : "Campaign") Summary:")
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
        # Use new grouped formatting by default
        # To use old PrettyTables format, set ENV["GLOBTIM_TABLE_STYLE"] = "pretty"
        use_pretty_tables = get(ENV, "GLOBTIM_TABLE_STYLE", "grouped") == "pretty"

        if use_pretty_tables
            println("\n📊 Aggregated Metrics Across Experiments:")
            println("=" ^ 80)
            format_metrics_pretty_table(metrics, metric_labels)
        else
            # Use new grouped formatting
            formatted_table = format_metrics_table(
                agg_stats,
                style=:grouped,
                max_width=100
            )
            print(formatted_table)
        end
    else
        println("\n⚠️  No aggregated metrics available")
    end

    # Add parameter recovery convergence analysis if CSV files are available
    print_parameter_recovery_table(campaign)

    println("\n" * "="^80)

    return agg_stats
end

"""
    format_metrics_pretty_table(metrics::Dict, _metric_labels::Dict)

Legacy PrettyTables formatting (kept for compatibility).
Use TableFormatting module for new grouped format.
"""
function format_metrics_pretty_table(metrics::Dict, _metric_labels::Dict)
    # Metric name mappings for better readability
    metric_labels = Dict(
        "approximation_quality" => "Approximation Quality (L2 Error)",
        "parameter_recovery" => "Parameter Recovery Error",
        "numerical_stability" => "Numerical Stability (Cond. #)",
        "critical_points" => "Critical Points (Total)",
        "critical_point_count" => "Critical Points (Raw)",
        "refined_critical_points" => "Critical Points (Refined)",
        "refinement_quality" => "Refinement Success Rate",
        "optimization_quality" => "Optimization Quality",
        "polynomial_timing" => "Polynomial Construction Time (s)",
        "solving_timing" => "Solving Time (s)",
        "refinement_timing" => "Refinement Time (s)",
        "total_timing" => "Total Computation Time (s)",
        "timing" => "Total Time (s)"
    )

    # Create a table with all metrics
    metric_names = String[]
    means = String[]
    mins = String[]
    maxs = String[]
    stds = String[]
    num_exps = Int[]
    best_exps = String[]

    for (metric_name, metric_data) in sort(collect(metrics), by=x->x[1])
        # Use human-readable label
        readable_name = get(metric_labels, metric_name, metric_name)
        push!(metric_names, readable_name)

        # Format values
        push!(means, format_scientific(get(metric_data, "mean", NaN)))
        push!(mins, format_scientific(get(metric_data, "min", NaN)))
        push!(maxs, format_scientific(get(metric_data, "max", NaN)))
        push!(stds, format_scientific(get(metric_data, "std", NaN)))
        push!(num_exps, get(metric_data, "num_experiments", 0))

        # Extract short readable label from best experiment
        best_exp = get(metric_data, "best_experiment", "N/A")
        best_exp_short = best_exp == "N/A" ? "N/A" : extract_experiment_label(best_exp, max_length=30)
        push!(best_exps, best_exp_short)
    end

    # Display table
    header = ["Metric", "Mean", "Min", "Max", "Std Dev", "N", "Best Experiment"]
    data = hcat(metric_names, means, mins, maxs, stds, num_exps, best_exps)

    pretty_table(data,
                header=header,
                alignment=[:l, :r, :r, :r, :r, :c, :l],
                crop=:none,
                header_crayon=crayon"bold cyan",
                border_crayon=crayon"cyan")
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
function generate_campaign_report(campaign::CampaignResults; format::String="markdown", include_errors::Bool=false)
    # Compute aggregated statistics
    agg_stats = aggregate_campaign_statistics(campaign)

    if format == "markdown"
        return generate_campaign_markdown_report(campaign, agg_stats, include_errors=include_errors)
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
function generate_campaign_markdown_report(campaign::CampaignResults, agg_stats::Dict; include_errors::Bool=false)
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
        # Get aggregated stats (degree 0) or first available degree
        pr_stats = haskey(pr, 0) ? pr[0] : first(values(pr))
        println(io, "| Statistic | Value |")
        println(io, "|-----------|-------|")
        println(io, "| Mean Error | $(format_scientific(pr_stats["mean"])) |")
        println(io, "| Min Error | $(format_scientific(pr_stats["min"])) |")
        println(io, "| Max Error | $(format_scientific(pr_stats["max"])) |")
        println(io, "| Best Experiment | $(pr_stats["best_experiment"]) |")
        println(io, "")
    end

    if haskey(metrics, "numerical_stability")
        println(io, "### Numerical Stability")
        println(io, "")
        ns = metrics["numerical_stability"]
        # Get aggregated stats (degree 0) or first available degree
        ns_stats = haskey(ns, 0) ? ns[0] : first(values(ns))
        println(io, "| Statistic | Value |")
        println(io, "|-----------|-------|")
        println(io, "| Mean Condition Number | $(format_scientific(ns_stats["mean"])) |")
        println(io, "| Max Condition Number | $(format_scientific(ns_stats["max"])) |")
        println(io, "")
    end

    if haskey(metrics, "critical_points")
        println(io, "### Critical Points")
        println(io, "")
        cp = metrics["critical_points"]
        # Get aggregated stats (degree 0) or first available degree
        cp_stats = haskey(cp, 0) ? cp[0] : first(values(cp))
        println(io, "| Statistic | Value |")
        println(io, "|-----------|-------|")
        println(io, "| Mean per Experiment | $(round(cp_stats["mean"], digits=1)) |")
        println(io, "| Min | $(Int(cp_stats["min"])) |")
        println(io, "| Max | $(Int(cp_stats["max"])) |")
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

    # Error Analysis Section (if requested)
    if include_errors
        println(io, "## Error Analysis")
        println(io, "")

        error_analysis = categorize_campaign_errors(campaign)

        println(io, "| Metric | Value |")
        println(io, "|--------|-------|")
        println(io, "| Total Errors | $(error_analysis["total_errors"]) |")
        println(io, "| Error Rate | $(round(error_analysis["error_rate"]*100, digits=1))% |")
        println(io, "")

        # Category breakdown
        if error_analysis["total_errors"] > 0
            println(io, "### Errors by Category")
            println(io, "")
            println(io, "| Category | Count | Percentage |")
            println(io, "|----------|-------|------------|")
            for (category, count) in sort(collect(error_analysis["category_distribution"]), by=x->x[2], rev=true)
                pct = round(count / error_analysis["total_errors"] * 100, digits=1)
                println(io, "| $category | $count | $pct% |")
            end
            println(io, "")

            # Recommendations
            if !isempty(error_analysis["recommendations"])
                println(io, "### Recommended Actions")
                println(io, "")
                for rec in error_analysis["recommendations"]
                    println(io, "- $rec")
                end
                println(io, "")
            end
        end
    end

    # Footer
    println(io, "---")
    println(io, "_Generated by GlobtimPostProcessing_")

    return String(take!(io))
end

"""
    extract_experiment_label(exp_path::String) -> String

Extract a short, readable label from experiment path or ID.
Tries to extract key parameters like domain size, GN, degree range.

# Examples
- "4dlv_param_recovery_unified_GN_val=14_deg=3:12" → "GN=14_deg=3:12"
- "/path/to/lv4d_exp1_range0.4_20251005" → "exp1_range0.4"
- "very_long_experiment_name_with_lots_of_details" → "very_long_experi..."
"""
function extract_experiment_label(exp_path::String; max_length::Int=25)
    # Get basename (remove directory path)
    name = basename(exp_path)

    # Try to extract key parameters
    key_params = String[]

    # Extract GN parameter
    m = match(r"GN[_=](\d+)", name)
    if m !== nothing
        push!(key_params, "GN=$(m[1])")
    end

    # Extract domain/range parameter
    m = match(r"(?:domain|range)[_=]?([\d.]+)", name)
    if m !== nothing
        push!(key_params, "dom=$(m[1])")
    end

    # Extract degree range
    m = match(r"deg[_=]?(\d+:\d+|\d+)", name)
    if m !== nothing
        push!(key_params, "deg=$(m[1])")
    end

    # Extract experiment number
    m = match(r"exp[_]?(\d+)", name)
    if m !== nothing
        push!(key_params, "exp$(m[1])")
    end

    # If we extracted key parameters, use those
    if !isempty(key_params)
        label = join(key_params, "_")
    else
        # Otherwise use the full name
        label = name
    end

    # Truncate if still too long
    if length(label) > max_length
        label = label[1:max_length-3] * "..."
    end

    return label
end

"""
    format_scientific(x::Float64) -> String

Format a float in scientific notation for reports.
Uses scientific notation for very small (< 1e-3) or very large (> 1e4) values.
"""
function format_scientific(x::Float64)
    if isnan(x)
        return "N/A"
    elseif isinf(x)
        return x > 0 ? "+Inf" : "-Inf"
    elseif abs(x) < 1e-3 || abs(x) > 1e4
        # Use scientific notation for very small or very large values
        return @sprintf("%.2e", x)
    else
        # Use fixed notation for moderate values
        return @sprintf("%.4f", x)
    end
end

"""
    print_parameter_recovery_table(campaign::CampaignResults)

Print parameter recovery convergence table showing best distances by degree.
Loads critical points from CSV files and computes L2 distances to true parameters.
"""
function print_parameter_recovery_table(campaign::CampaignResults)
    # Try to load CSV files for each experiment
    exp_data = []

    for exp in campaign.experiments
        exp_path = exp.source_path

        # Load experiment config to get true parameters
        config_file = joinpath(exp_path, "experiment_config.json")
        if !isfile(config_file)
            continue
        end

        config = JSON.parsefile(config_file)

        # Get true parameters
        p_true = if haskey(config, "p_true")
            collect(config["p_true"])
        elseif haskey(config, "p_center")
            collect(config["p_center"])
        else
            continue  # Skip if no true parameters
        end

        # Load critical points by degree
        csv_files = filter(f -> startswith(basename(f), "critical_points_deg_"),
                          readdir(exp_path, join=true))

        if isempty(csv_files)
            continue
        end

        cp_by_degree = Dict{Int, DataFrame}()
        for csv_file in csv_files
            m = match(r"deg_(\d+)\.csv", basename(csv_file))
            if m !== nothing
                degree = parse(Int, m[1])
                try
                    df = CSV.read(csv_file, DataFrame)
                    cp_by_degree[degree] = df
                catch
                    # Skip files that can't be loaded
                end
            end
        end

        if !isempty(cp_by_degree)
            push!(exp_data, (
                exp_id = exp.experiment_id,
                p_true = p_true,
                cp_by_degree = cp_by_degree
            ))
        end
    end

    if isempty(exp_data)
        # No CSV data available, skip this section
        return
    end

    println("\n📉 PARAMETER RECOVERY CONVERGENCE")
    println("="^80)

    # Helper function to compute parameter distance
    function param_distance(cp_row, p_true)
        n_params = length(p_true)
        p_found = [cp_row[Symbol("x$i")] for i in 1:n_params]
        return norm(p_found .- p_true)
    end

    # Collect all degrees
    all_degrees = Set{Int}()
    for exp in exp_data
        union!(all_degrees, keys(exp.cp_by_degree))
    end
    degrees = sort(collect(all_degrees))

    if isempty(degrees)
        return
    end

    # Print table header
    @printf("%-8s", "Degree")
    for (i, _) in enumerate(exp_data)
        short_id = length(exp_data) > 1 ? "Exp$i" : "Distance"
        @printf(" | %15s", short_id)
    end
    println()
    println("-"^(8 + length(exp_data) * 18))

    # Print rows for each degree
    for deg in degrees
        @printf("%-8d", deg)

        for exp in exp_data
            if haskey(exp.cp_by_degree, deg)
                df = exp.cp_by_degree[deg]
                if nrow(df) > 0
                    distances = [param_distance(row, exp.p_true) for row in eachrow(df)]
                    min_dist = minimum(distances)
                    @printf(" | %15.6e", min_dist)
                else
                    @printf(" | %15s", "N/A")
                end
            else
                @printf(" | %15s", "-")
            end
        end
        println()
    end

    println()

    # Print best critical points for each degree (if only one experiment)
    if length(exp_data) == 1
        println("\n📊 BEST CRITICAL POINTS BY DEGREE")
        println("="^80)

        exp = exp_data[1]

        for deg in degrees
            if !haskey(exp.cp_by_degree, deg)
                continue
            end

            df = exp.cp_by_degree[deg]
            if nrow(df) == 0
                continue
            end

            # Find best point for this degree
            distances = [param_distance(row, exp.p_true) for row in eachrow(df)]
            best_idx = argmin(distances)
            best_row = df[best_idx, :]
            best_dist = distances[best_idx]

            n_params = length(exp.p_true)
            p_found = [best_row[Symbol("x$i")] for i in 1:n_params]

            println("\nDegree $deg:")
            println("  Best distance: $(round(best_dist, sigdigits=6))")
            println("  Objective value: $(round(best_row.z, sigdigits=6))")
            println("  Parameters found: [$(join([round(p, sigdigits=6) for p in p_found], ", "))]")
            println("  True parameters:  [$(join([round(p, sigdigits=6) for p in exp.p_true], ", "))]")

            # Component-wise errors
            errors = abs.(p_found .- exp.p_true)
            println("  Component errors: [$(join([round(e, sigdigits=4) for e in errors], ", "))]")
        end
    end
end
