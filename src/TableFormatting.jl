"""
    TableFormatting.jl

Terminal-friendly table formatting for campaign analysis results.

Provides:
- Grouped metric displays (quality, timing, critical points)
- Compact summary views
- Consistent number formatting
- Adaptive column widths
- Readable experiment labels
"""

using Printf
using Statistics

# Export public API
export format_metrics_table, format_compact_summary, format_grouped_metrics

# ============================================================================
# Metric Categories and Labels
# ============================================================================

const QUALITY_METRICS = [
    "approximation_quality",
    "parameter_recovery",
    "numerical_stability",
    "refinement_quality",
    "optimization_quality"
]

const TIMING_METRICS = [
    "polynomial_timing",
    "solving_timing",
    "refinement_timing",
    "total_timing",
    "timing"
]

const COUNT_METRICS = [
    "critical_points",
    "critical_point_count",
    "refined_critical_points"
]

# Compact readable labels for metrics
const METRIC_LABELS = Dict(
    "approximation_quality" => "L2 Error",
    "parameter_recovery" => "Param Recovery",
    "numerical_stability" => "Cond Number",
    "refinement_quality" => "Refinement Rate",
    "optimization_quality" => "Opt Quality",
    "polynomial_timing" => "Polynomial (s)",
    "solving_timing" => "Solving (s)",
    "refinement_timing" => "Refinement (s)",
    "total_timing" => "Total (s)",
    "timing" => "Total Time (s)",
    "critical_points" => "Critical Pts",
    "critical_point_count" => "CP Count",
    "refined_critical_points" => "Refined CPs"
)

# ============================================================================
# Main Formatting Functions
# ============================================================================

"""
    format_metrics_table(agg_stats::Dict; style=:grouped, max_width=100) -> String

Format aggregated campaign statistics as a readable terminal table.

# Arguments
- `agg_stats::Dict`: Aggregated statistics from `aggregate_campaign_statistics`
- `style::Symbol`: Display style (`:grouped` or `:compact`)
- `max_width::Int`: Maximum table width in characters

# Returns
- `String`: Formatted table ready for printing

# Examples
```julia
agg_stats = aggregate_campaign_statistics(campaign)

# Grouped display with separate sections
table = format_metrics_table(agg_stats, style=:grouped, max_width=100)
println(table)

# Compact summary for quick overview
summary = format_metrics_table(agg_stats, style=:compact)
println(summary)
```
"""
function format_metrics_table(agg_stats::Dict;
                              style::Symbol=:grouped,
                              max_width::Int=100)
    if style == :grouped
        return format_grouped_metrics(agg_stats, max_width)
    elseif style == :compact
        return format_compact_summary(agg_stats)
    else
        error("Unknown style: $style. Use :grouped or :compact")
    end
end

"""
    format_compact_summary(agg_stats::Dict) -> String

Generate a concise summary suitable for quick terminal display.
"""
function format_compact_summary(agg_stats::Dict)
    io = IOBuffer()

    metrics = agg_stats["aggregated_metrics"]
    summary = agg_stats["campaign_summary"]

    println(io, "="^80)
    println(io, "📊 CAMPAIGN OVERVIEW: $(summary["num_experiments"]) experiments")
    println(io, "="^80)
    println(io)

    # Quick summary section
    println(io, "Quick Summary:")

    if haskey(metrics, "approximation_quality")
        aq_by_deg = metrics["approximation_quality"]
        # Find overall best/worst across all degrees
        all_mins = [d["min"] for d in values(aq_by_deg)]
        all_maxs = [d["max"] for d in values(aq_by_deg)]
        all_means = [d["mean"] for d in values(aq_by_deg)]
        @printf(io, "  L2 Error:       %10s (best) → %10s (worst)  [mean: %10s]\n",
                format_value(minimum(all_mins)),
                format_value(maximum(all_maxs)),
                format_value(mean(all_means)))
    end

    if haskey(metrics, "parameter_recovery")
        pr_by_deg = metrics["parameter_recovery"]
        all_mins = [d["min"] for d in values(pr_by_deg)]
        all_maxs = [d["max"] for d in values(pr_by_deg)]
        all_means = [d["mean"] for d in values(pr_by_deg)]
        @printf(io, "  Param Recovery: %10s (best) → %10s (worst)  [mean: %10s]\n",
                format_value(minimum(all_mins)),
                format_value(maximum(all_maxs)),
                format_value(mean(all_means)))
    end

    @printf(io, "  Success Rate:   %.0f%% (%d/%d experiments converged)\n",
            summary["success_rate"] * 100,
            summary["successful_experiments"],
            summary["num_experiments"])

    total_hours = summary["total_computation_hours"]
    if total_hours < 1.0
        @printf(io, "  Total Time:     %.1f minutes\n", total_hours * 60)
    else
        @printf(io, "  Total Time:     %.2f hours\n", total_hours)
    end

    println(io)
    println(io, "For detailed metrics, use: format_metrics_table(agg_stats, style=:grouped)")

    return String(take!(io))
end

"""
    format_grouped_metrics(agg_stats::Dict, max_width::Int) -> String

Format metrics grouped by category (quality, timing, counts).
"""
function format_grouped_metrics(agg_stats::Dict, max_width::Int)
    io = IOBuffer()
    metrics = agg_stats["aggregated_metrics"]
    summary = agg_stats["campaign_summary"]

    # Header
    println(io)
    println(io, "="^max_width)
    println(io, "📊 AGGREGATED METRICS: $(summary["num_experiments"]) experiments")
    println(io, "="^max_width)
    println(io)

    # Quality metrics section
    if has_any_metric(metrics, QUALITY_METRICS)
        println(io, "🎯 Quality Metrics")
        println(io, "─"^max_width)
        format_metric_group(io, metrics, QUALITY_METRICS, max_width)
        println(io)
    end

    # Timing metrics section
    if has_any_metric(metrics, TIMING_METRICS)
        println(io, "⏱️  Timing Metrics")
        println(io, "─"^max_width)
        format_metric_group(io, metrics, TIMING_METRICS, max_width)
        println(io)
    end

    # Count metrics section
    if has_any_metric(metrics, COUNT_METRICS)
        println(io, "🔍 Critical Point Metrics")
        println(io, "─"^max_width)
        format_metric_group(io, metrics, COUNT_METRICS, max_width)
        println(io)
    end

    # Best performers section
    println(io, "🏆 Best Performers")
    println(io, "─"^max_width)
    format_best_performers(io, agg_stats, max_width)
    println(io)

    println(io, "="^max_width)

    return String(take!(io))
end

# ============================================================================
# Helper Functions
# ============================================================================

"""
    format_metric_group(io::IO, metrics::Dict, metric_list::Vector, max_width::Int)

Format a group of related metrics as a table, organized by polynomial degree.
"""
function format_metric_group(io::IO, metrics::Dict, metric_list::Vector, max_width::Int)
    # Column widths
    name_width = 25
    num_width = 12

    # Header
    @printf(io, "%-*s %*s %*s %*s %*s %*s\n",
            name_width, "Metric",
            num_width, "Mean",
            num_width, "Min",
            num_width, "Max",
            num_width, "Std Dev",
            3, "N")
    println(io, "─"^max_width)

    # Data rows - now organized by degree
    for metric_key in metric_list
        if haskey(metrics, metric_key)
            metric_by_degree = metrics[metric_key]
            label = get(METRIC_LABELS, metric_key, metric_key)

            # Get all degrees for this metric
            degrees = sort(collect(keys(metric_by_degree)))

            for (idx, deg) in enumerate(degrees)
                m = metric_by_degree[deg]

                # Format metric name: add "Deg X" suffix, or "Overall" for degree=0
                if deg == 0
                    display_label = label
                else
                    display_label = idx == 1 ? label * " (deg $deg)" : "  deg $deg"
                end

                @printf(io, "%-*s %*s %*s %*s %*s %*d\n",
                        name_width, truncate_string(display_label, name_width),
                        num_width, format_value(m["mean"]),
                        num_width, format_value(m["min"]),
                        num_width, format_value(m["max"]),
                        num_width, format_value(m["std"]),
                        3, m["num_experiments"])
            end
        end
    end
end

"""
    format_best_performers(io::IO, agg_stats::Dict, max_width::Int)

Display best performing experiments for each metric and degree, showing experiment parameters.
"""
function format_best_performers(io::IO, agg_stats::Dict, max_width::Int)
    metrics = agg_stats["aggregated_metrics"]
    exp_stats = get(agg_stats, "experiments", Dict())

    name_width = min(25, div(max_width, 3))
    exp_width = min(30, div(max_width, 3))
    val_width = 12

    for (metric_name, metric_by_degree) in sort(collect(metrics), by=x->x[1])
        label = get(METRIC_LABELS, metric_name, metric_name)

        # Get all degrees for this metric
        degrees = sort(collect(keys(metric_by_degree)))

        # For metrics with multiple degrees, show best overall (min across all degrees)
        if length(degrees) > 1 && all(deg != 0 for deg in degrees)
            # Find best performer across all degrees
            best_val = Inf
            best_exp_id = ""
            best_deg = 0

            for deg in degrees
                metric_data = metric_by_degree[deg]
                if haskey(metric_data, "min") && metric_data["min"] < best_val
                    best_val = metric_data["min"]
                    best_exp_id = metric_data["best_experiment"]
                    best_deg = deg
                end
            end

            if best_exp_id != ""
                best_exp_display = extract_experiment_params(best_exp_id, exp_stats, exp_width)
                @printf(io, "%-*s: %-*s → %*s (deg %d)\n",
                        name_width, truncate_string(label, name_width),
                        exp_width, truncate_string(best_exp_display, exp_width),
                        val_width, format_value(best_val),
                        best_deg)
            end
        else
            # Single degree or degree=0 (overall metric)
            deg = first(degrees)
            metric_data = metric_by_degree[deg]

            if haskey(metric_data, "best_experiment")
                best_exp_id = metric_data["best_experiment"]
                best_exp_display = extract_experiment_params(best_exp_id, exp_stats, exp_width)
                best_val = format_value(metric_data["min"])

                @printf(io, "%-*s: %-*s → %*s\n",
                        name_width, truncate_string(label, name_width),
                        exp_width, truncate_string(best_exp_display, exp_width),
                        val_width, best_val)
            end
        end
    end
end

"""
    extract_experiment_params(exp_id::String, exp_stats::Dict, max_length::Int) -> String

Extract experiment parameters from experiment stats for display.
Tries to extract GN, domain_range, and degree_range from metadata.
Falls back to parsing experiment name if metadata is unavailable.
"""
function extract_experiment_params(exp_id::String, exp_stats::Dict, max_length::Int)
    # Try to get experiment stats
    if haskey(exp_stats, exp_id)
        exp_stat = exp_stats[exp_id]

        # Check if we have metadata in the stats
        if haskey(exp_stat, "metadata")
            metadata = exp_stat["metadata"]

            # Extract key parameters
            params = String[]

            # GN parameter
            if haskey(metadata, "GN")
                push!(params, "GN=$(metadata["GN"])")
            end

            # Domain range
            if haskey(metadata, "domain_range")
                dr = metadata["domain_range"]
                push!(params, "range=$(dr)")
            elseif haskey(metadata, "sample_range")
                dr = metadata["sample_range"]
                push!(params, "range=$(dr)")
            end

            # Degree range
            if haskey(metadata, "degree_min") && haskey(metadata, "degree_max")
                dmin = metadata["degree_min"]
                dmax = metadata["degree_max"]
                push!(params, "deg=$(dmin)-$(dmax)")
            end

            # If we found parameters, return them
            if !isempty(params)
                result = join(params, ", ")
                return truncate_string(result, max_length)
            end
        end
    end

    # Fallback: parse from experiment name
    exp_name = basename(exp_id)
    return extract_key_params(exp_name, max_length)
end

"""
    extract_key_params(name::String, max_length::Int) -> String

Extract key parameters from experiment name for compact display.
"""
function extract_key_params(name::String, max_length::Int)
    # Remove timestamp patterns
    name = replace(name, r"_\d{8}_\d{6}" => "")

    # Extract key parameters
    key_params = String[]

    # Extract experiment number
    m = match(r"exp[_]?(\d+)", name)
    if m !== nothing
        push!(key_params, "exp$(m[1])")
    end

    # Extract GN parameter
    m = match(r"GN[_=](\d+)", name)
    if m !== nothing
        push!(key_params, "GN$(m[1])")
    end

    # Extract domain/range parameter
    m = match(r"(?:domain|range)[_=]?([\d.]+)", name)
    if m !== nothing
        push!(key_params, "dom$(m[1])")
    end

    # If we found params, use those; otherwise use original name
    if !isempty(key_params)
        result = join(key_params, "_")
    else
        result = name
    end

    return truncate_string(result, max_length)
end

"""
    format_value(x) -> String

Format a numeric value for table display.
Uses scientific notation for very small or very large values.
"""
function format_value(x)
    if x isa Number
        if isnan(x)
            return "N/A"
        elseif isinf(x)
            return x > 0 ? "+Inf" : "-Inf"
        elseif abs(x) < 1e-3 || abs(x) > 1e4
            return @sprintf("%.2e", x)
        else
            return @sprintf("%.4f", x)
        end
    else
        return string(x)
    end
end

"""
    truncate_string(s::String, max_len::Int) -> String

Truncate string to maximum length, adding "..." if needed.
"""
function truncate_string(s::String, max_len::Int)
    if length(s) <= max_len
        return s
    else
        return s[1:max_len-3] * "..."
    end
end

"""
    has_any_metric(metrics::Dict, metric_list::Vector) -> Bool

Check if any metric from list exists in metrics dictionary.
"""
function has_any_metric(metrics::Dict, metric_list::Vector)
    return any(haskey(metrics, m) for m in metric_list)
end
