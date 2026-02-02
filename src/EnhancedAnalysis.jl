# Enhanced Analysis Integration for Critical Point Analysis
#
# This module provides comprehensive statistical table functionality for
# Hessian-based critical point analysis, including type-specific statistics,
# condition number quality assessment, and mathematical validation.
#
# Moved from globtim to globtimpostprocessing (January 2026)

using Statistics
using DataFrames
using LinearAlgebra
using Dates

# ============================================================================
# STATISTICAL TABLE DATA STRUCTURES
# ============================================================================

# Abstract base type for all statistical tables
abstract type StatisticalTable end

# Core statistical data structures
struct RobustStatistics
    count::Int
    mean::Float64
    std::Float64
    median::Float64
    min::Float64
    max::Float64
    q1::Float64
    q3::Float64
    iqr::Float64
    outlier_count::Int
    outlier_percentage::Float64
    range::Float64
end

struct ConditionNumberAnalysis
    total_count::Int
    excellent_count::Int      # < 1e3
    good_count::Int          # 1e3-1e6
    fair_count::Int          # 1e6-1e9
    poor_count::Int          # 1e9-1e12
    critical_count::Int      # >= 1e12
    well_conditioned_percentage::Float64
    overall_quality::String
    recommendations::Vector{String}
end

struct ValidationResults
    eigenvalue_signs_correct::Union{Bool, Missing}
    positive_eigenvalue_count::Union{Int, Missing}
    negative_eigenvalue_count::Union{Int, Missing}
    mixed_eigenvalue_signs::Union{Bool, Missing}
    determinant_positive::Union{Bool, Missing}
    determinant_sign_consistent::Union{Bool, Missing}
    additional_checks::Dict{String, Any}
end

# Main statistical table types
struct HessianNormTable <: StatisticalTable
    point_type::Symbol
    statistics::RobustStatistics
    display_format::Symbol
    validation_results::ValidationResults
end

struct ConditionNumberTable <: StatisticalTable
    point_type::Symbol
    analysis::ConditionNumberAnalysis
    display_format::Symbol
end

struct ComprehensiveStatsTable <: StatisticalTable
    point_type::Symbol
    hessian_stats::RobustStatistics
    condition_analysis::ConditionNumberAnalysis
    validation_results::ValidationResults
    eigenvalue_stats::Union{RobustStatistics, Missing}
    display_format::Symbol
end

# ============================================================================
# STATISTICAL COMPUTATION FUNCTIONS
# ============================================================================

"""
    compute_robust_statistics(values::Vector{Float64})

Compute comprehensive robust statistical measures including outlier detection.

# Returns
- `RobustStatistics`: Complete statistical summary with outlier analysis
"""
function compute_robust_statistics(values::Vector{Float64})
    if isempty(values)
        return RobustStatistics(0, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, 0, 0.0, NaN)
    end

    # Basic statistics
    n = length(values)
    mean_val = mean(values)
    std_val = n > 1 ? std(values) : 0.0
    median_val = median(values)
    min_val = minimum(values)
    max_val = maximum(values)

    # Robust statistics
    q1 = quantile(values, 0.25)
    q3 = quantile(values, 0.75)
    iqr = q3 - q1

    # Outlier detection (1.5 * IQR rule)
    if iqr > 0
        lower_fence = q1 - 1.5 * iqr
        upper_fence = q3 + 1.5 * iqr
        outliers = values[(values .< lower_fence) .| (values .> upper_fence)]
        outlier_count = length(outliers)
        outlier_percentage = round(100 * outlier_count / n, digits = 1)
    else
        outlier_count = 0
        outlier_percentage = 0.0
    end

    return RobustStatistics(
        n,
        mean_val,
        std_val,
        median_val,
        min_val,
        max_val,
        q1,
        q3,
        iqr,
        outlier_count,
        outlier_percentage,
        max_val - min_val
    )
end

"""
    compute_condition_number_analysis(condition_numbers::Vector{Float64})

Classify condition numbers by quality and generate recommendations.

# Returns
- `ConditionNumberAnalysis`: Quality breakdown and assessment
"""
function compute_condition_number_analysis(condition_numbers::Vector{Float64})
    if isempty(condition_numbers)
        return ConditionNumberAnalysis(0, 0, 0, 0, 0, 0, 0.0, "NO_DATA", String[])
    end

    n = length(condition_numbers)

    # Quality classification thresholds
    excellent = sum(condition_numbers .< 1e3)      # Well-conditioned
    good = sum(1e3 .<= condition_numbers .< 1e6)   # Acceptable
    fair = sum(1e6 .<= condition_numbers .< 1e9)   # Marginal
    poor = sum(1e9 .<= condition_numbers .< 1e12)  # Poor
    critical = sum(condition_numbers .>= 1e12)     # Numerically unstable

    # Overall quality assessment
    well_conditioned_percentage = round(100 * (excellent + good) / n, digits = 1)
    overall_quality = if well_conditioned_percentage > 80
        "EXCELLENT"
    elseif well_conditioned_percentage > 60
        "GOOD"
    elseif well_conditioned_percentage > 40
        "FAIR"
    else
        "POOR"
    end

    # Generate recommendations
    recommendations = String[]
    if well_conditioned_percentage > 90
        push!(recommendations, "Numerical quality is excellent")
    elseif well_conditioned_percentage > 70
        push!(recommendations, "Good numerical stability overall")
    else
        push!(recommendations, "Consider higher precision for stability")
    end

    if critical > 0
        push!(recommendations, "$(critical) critical points may be unreliable")
    end

    if poor + critical > n ÷ 4  # More than 25% problematic
        push!(recommendations, "Problem may benefit from rescaling")
    end

    return ConditionNumberAnalysis(
        n,
        excellent,
        good,
        fair,
        poor,
        critical,
        well_conditioned_percentage,
        overall_quality,
        recommendations
    )
end

"""
    perform_mathematical_validation(type_data::DataFrame, point_type::Symbol)

Perform mathematical validation of critical point classifications.

# Returns
- `ValidationResults`: Comprehensive validation results
"""
function perform_mathematical_validation(type_data::DataFrame, point_type::Symbol)
    additional_checks = Dict{String, Any}()

    # Initialize validation results
    eigenvalue_signs_correct = missing
    positive_eigenvalue_count = missing
    negative_eigenvalue_count = missing
    mixed_eigenvalue_signs = missing
    determinant_positive = missing
    determinant_sign_consistent = missing

    if point_type == :minimum
        # For minima: all eigenvalues should be positive
        if hasproperty(type_data, :smallest_positive_eigenval)
            pos_eigenvals = filter(!isnan, type_data.smallest_positive_eigenval)
            if !isempty(pos_eigenvals)
                all_positive = all(λ -> λ > 1e-12, pos_eigenvals)
                eigenvalue_signs_correct = all_positive
                positive_eigenvalue_count = sum(pos_eigenvals .> 1e-12)
                negative_eigenvalue_count = sum(pos_eigenvals .<= 1e-12)
                additional_checks["smallest_positive_eigenval_mean"] = mean(pos_eigenvals)
            end
        end

    elseif point_type == :maximum
        # For maxima: all eigenvalues should be negative
        if hasproperty(type_data, :largest_negative_eigenval)
            neg_eigenvals = filter(!isnan, type_data.largest_negative_eigenval)
            if !isempty(neg_eigenvals)
                all_negative = all(λ -> λ < -1e-12, neg_eigenvals)
                eigenvalue_signs_correct = all_negative
                negative_eigenvalue_count = sum(neg_eigenvals .< -1e-12)
                positive_eigenvalue_count = sum(neg_eigenvals .>= -1e-12)
                additional_checks["largest_negative_eigenval_mean"] = mean(neg_eigenvals)
            end
        end

    elseif point_type == :saddle
        # For saddles: mixed eigenvalue signs expected
        if hasproperty(type_data, :hessian_eigenvalue_min) &&
           hasproperty(type_data, :hessian_eigenvalue_max)
            min_eigenvals = filter(!isnan, type_data.hessian_eigenvalue_min)
            max_eigenvals = filter(!isnan, type_data.hessian_eigenvalue_max)

            if !isempty(min_eigenvals) && !isempty(max_eigenvals)
                has_negative = any(λ -> λ < -1e-12, min_eigenvals)
                has_positive = any(λ -> λ > 1e-12, max_eigenvals)
                mixed_eigenvalue_signs = has_negative && has_positive
                additional_checks["negative_eigenval_count"] = sum(min_eigenvals .< -1e-12)
                additional_checks["positive_eigenval_count"] = sum(max_eigenvals .> 1e-12)
            end
        end
    end

    # Determinant consistency check
    if hasproperty(type_data, :hessian_determinant)
        determinants = filter(!isnan, type_data.hessian_determinant)
        if !isempty(determinants)
            if point_type == :minimum
                determinant_positive = all(det -> det > 1e-12, determinants)
                additional_checks["determinant_mean"] = mean(determinants)
            elseif point_type == :maximum
                # For maxima, determinant sign depends on dimension
                # Even dimensions: positive, odd dimensions: negative
                # We'll check if determinants are consistent in sign
                pos_dets = sum(determinants .> 1e-12)
                neg_dets = sum(determinants .< -1e-12)
                determinant_sign_consistent = (pos_dets == 0) || (neg_dets == 0)
                additional_checks["positive_determinants"] = pos_dets
                additional_checks["negative_determinants"] = neg_dets
            end
        end
    end

    return ValidationResults(
        eigenvalue_signs_correct,
        positive_eigenvalue_count,
        negative_eigenvalue_count,
        mixed_eigenvalue_signs,
        determinant_positive,
        determinant_sign_consistent,
        additional_checks
    )
end

"""
    compute_type_specific_statistics(df::DataFrame, point_type::Symbol)

Compute comprehensive statistics for a specific critical point type.

# Returns
- `ComprehensiveStatsTable`: Complete statistical analysis
"""
function compute_type_specific_statistics(df::DataFrame, point_type::Symbol)
    # Check if minimum required columns exist
    if !hasproperty(df, :critical_point_type)
        # Return empty statistics if we don't even have the type column
        empty_stats =
            RobustStatistics(0, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, 0, 0.0, NaN)
        empty_condition =
            ConditionNumberAnalysis(0, 0, 0, 0, 0, 0, 0.0, "NO_DATA", String[])
        empty_validation = ValidationResults(
            missing,
            missing,
            missing,
            missing,
            missing,
            missing,
            Dict{String, Any}()
        )

        return ComprehensiveStatsTable(
            point_type,
            empty_stats,
            empty_condition,
            empty_validation,
            missing,
            :console
        )
    end

    # Filter data by critical point type
    type_mask = df.critical_point_type .== point_type
    type_data = df[type_mask, :]

    if nrow(type_data) == 0
        # Return empty statistics
        empty_stats =
            RobustStatistics(0, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, 0, 0.0, NaN)
        empty_condition =
            ConditionNumberAnalysis(0, 0, 0, 0, 0, 0, 0.0, "NO_DATA", String[])
        empty_validation = ValidationResults(
            missing,
            missing,
            missing,
            missing,
            missing,
            missing,
            Dict{String, Any}()
        )

        return ComprehensiveStatsTable(
            point_type,
            empty_stats,
            empty_condition,
            empty_validation,
            missing,
            :console
        )
    end

    # Extract key numerical columns
    hessian_norms = if hasproperty(type_data, :hessian_norm)
        filter(!isnan, type_data.hessian_norm)
    else
        Float64[]
    end

    condition_numbers = if hasproperty(type_data, :hessian_condition_number)
        filter(x -> isfinite(x) && x > 0, type_data.hessian_condition_number)
    else
        Float64[]
    end

    # Compute comprehensive statistics
    hessian_stats = compute_robust_statistics(hessian_norms)
    condition_analysis = compute_condition_number_analysis(condition_numbers)
    validation_results = perform_mathematical_validation(type_data, point_type)

    # Eigenvalue statistics (if available)
    eigenvalue_stats = missing
    if hasproperty(type_data, :hessian_eigenvalue_min)
        eigenvals = filter(!isnan, type_data.hessian_eigenvalue_min)
        if !isempty(eigenvals)
            eigenvalue_stats = compute_robust_statistics(eigenvals)
        end
    end

    return ComprehensiveStatsTable(
        point_type,
        hessian_stats,
        condition_analysis,
        validation_results,
        eigenvalue_stats,
        :console
    )
end

# ============================================================================
# TABLE RENDERING FUNCTIONS
# ============================================================================

"""
    center_text(prefix::String, text::String, width::Int, suffix::String="")

Center text within a given width with optional prefix and suffix.
"""
function center_text(prefix::String, text::String, width::Int, suffix::String = "")
    available_width = width - length(prefix) - length(suffix)
    if length(text) >= available_width
        # Truncate if too long
        truncated_text = text[1:min(length(text), available_width - 3)] * "..."
        return prefix * truncated_text * suffix
    end

    padding = available_width - length(text)
    left_pad = div(padding, 2)
    right_pad = padding - left_pad

    return prefix * " "^left_pad * text * " "^right_pad * suffix
end

"""
    format_table_row(label::String, value::String, width::Int;
                     label_width_ratio=0.6)

Format a single table row with proper alignment and padding.
"""
function format_table_row(label::String, value::String, width::Int; label_width_ratio = 0.6)
    # Calculate column widths
    available_width = width - 6  # Account for borders and separators "│ │ │"
    label_width = max(10, floor(Int, available_width * label_width_ratio))
    value_width = available_width - label_width

    # Truncate if necessary
    display_label = if length(label) > label_width
        label[1:(label_width - 3)] * "..."
    else
        label
    end

    display_value = if length(value) > value_width
        value[1:(value_width - 3)] * "..."
    else
        value
    end

    # Pad to alignment
    padded_label = rpad(display_label, label_width)
    padded_value = lpad(display_value, value_width)

    return "│ $padded_label │ $padded_value │"
end

"""
    create_table_border(width::Int, style::Symbol=:top)

Create table border lines.

# Arguments
- `width::Int`: Total table width
- `style::Symbol`: Border style (:top, :middle, :bottom, :section)
"""
function create_table_border(width::Int, style::Symbol = :top)
    if style == :top
        return "┌" * "─"^(width - 2) * "┐"
    elseif style == :middle
        return "├" * "─"^(width - 2) * "┤"
    elseif style == :bottom
        return "└" * "─"^(width - 2) * "┘"
    elseif style == :section
        return "├" * "─"^(width - 2) * "┤"
    else
        return "├" * "─"^(width - 2) * "┤"
    end
end

"""
    format_validation_key(key::String)

Format validation result keys for display.
"""
function format_validation_key(key::String)
    key_map = Dict(
        "eigenvalue_signs_correct" => "Eigenvalue signs correct",
        "positive_eigenvalue_count" => "Positive eigenvalues",
        "negative_eigenvalue_count" => "Negative eigenvalues",
        "mixed_eigenvalue_signs" => "Mixed eigenvalue signs",
        "determinant_positive" => "Determinant positive",
        "determinant_sign_consistent" => "Determinant sign consistent"
    )

    return get(key_map, key, titlecase(replace(key, "_" => " ")))
end

"""
    format_validation_value(value)

Format validation result values for display.
"""
function format_validation_value(value)
    if ismissing(value)
        return "N/A"
    elseif value === true
        return "✓ YES"
    elseif value === false
        return "✗ NO"
    else
        return string(value)
    end
end

"""
    render_console_table(stats_table::ComprehensiveStatsTable; width=80)

Render a comprehensive statistics table in ASCII format for console display.
"""
function render_console_table(stats_table::ComprehensiveStatsTable; width = 80)
    lines = String[]
    table_width = min(width, 120)  # Maximum reasonable width

    # Title
    title = "$(uppercase(string(stats_table.point_type))) STATISTICS"
    push!(lines, create_table_border(table_width, :top))
    push!(lines, center_text("│", title, table_width - 2, "│"))
    push!(lines, create_table_border(table_width, :middle))

    # Basic statistics section
    hs = stats_table.hessian_stats
    if hs.count > 0
        push!(lines, format_table_row("Count", string(hs.count), table_width))
        push!(
            lines,
            format_table_row(
                "Mean ± Std",
                "$(round(hs.mean, digits=3)) ± $(round(hs.std, digits=3))",
                table_width
            )
        )
        push!(
            lines,
            format_table_row(
                "Median (IQR)",
                "$(round(hs.median, digits=3)) ($(round(hs.q1, digits=3))-$(round(hs.q3, digits=3)))",
                table_width
            )
        )
        push!(
            lines,
            format_table_row(
                "Range",
                "[$(round(hs.min, digits=3)), $(round(hs.max, digits=3))]",
                table_width
            )
        )
        push!(
            lines,
            format_table_row(
                "Outliers",
                "$(hs.outlier_count) ($(hs.outlier_percentage)%)",
                table_width
            )
        )
    else
        push!(lines, format_table_row("Count", "0", table_width))
        push!(lines, format_table_row("Status", "No data available", table_width))
    end

    # Condition number quality section
    ca = stats_table.condition_analysis
    if ca.total_count > 0
        push!(lines, create_table_border(table_width, :section))
        push!(lines, center_text("│", "CONDITION NUMBER QUALITY", table_width - 2, "│"))
        push!(lines, create_table_border(table_width, :middle))

        total = ca.total_count
        push!(
            lines,
            format_table_row(
                "Excellent (< 1e3)",
                "$(ca.excellent_count) ($(round(100*ca.excellent_count/total, digits=1))%)",
                table_width
            )
        )
        push!(
            lines,
            format_table_row(
                "Good (1e3-1e6)",
                "$(ca.good_count) ($(round(100*ca.good_count/total, digits=1))%)",
                table_width
            )
        )
        push!(
            lines,
            format_table_row(
                "Fair (1e6-1e9)",
                "$(ca.fair_count) ($(round(100*ca.fair_count/total, digits=1))%)",
                table_width
            )
        )
        push!(
            lines,
            format_table_row(
                "Poor (1e9-1e12)",
                "$(ca.poor_count) ($(round(100*ca.poor_count/total, digits=1))%)",
                table_width
            )
        )
        push!(
            lines,
            format_table_row(
                "Critical (≥ 1e12)",
                "$(ca.critical_count) ($(round(100*ca.critical_count/total, digits=1))%)",
                table_width
            )
        )
        push!(lines, format_table_row("Overall Quality", ca.overall_quality, table_width))
    end

    # Mathematical validation section
    vr = stats_table.validation_results
    has_validation_data =
        !ismissing(vr.eigenvalue_signs_correct) ||
        !ismissing(vr.mixed_eigenvalue_signs) ||
        !ismissing(vr.determinant_positive)

    if has_validation_data
        push!(lines, create_table_border(table_width, :section))
        push!(lines, center_text("│", "MATHEMATICAL VALIDATION", table_width - 2, "│"))
        push!(lines, create_table_border(table_width, :middle))

        # Show relevant validation results based on point type
        if stats_table.point_type == :minimum
            if !ismissing(vr.eigenvalue_signs_correct)
                status = format_validation_value(vr.eigenvalue_signs_correct)
                push!(
                    lines,
                    format_table_row("All eigenvalues positive", status, table_width)
                )
            end
            if !ismissing(vr.positive_eigenvalue_count)
                push!(
                    lines,
                    format_table_row(
                        "Positive eigenvalue count",
                        string(vr.positive_eigenvalue_count),
                        table_width
                    )
                )
            end
            if !ismissing(vr.determinant_positive)
                status = format_validation_value(vr.determinant_positive)
                push!(lines, format_table_row("Determinant positive", status, table_width))
            end

        elseif stats_table.point_type == :maximum
            if !ismissing(vr.eigenvalue_signs_correct)
                status = format_validation_value(vr.eigenvalue_signs_correct)
                push!(
                    lines,
                    format_table_row("All eigenvalues negative", status, table_width)
                )
            end
            if !ismissing(vr.negative_eigenvalue_count)
                push!(
                    lines,
                    format_table_row(
                        "Negative eigenvalue count",
                        string(vr.negative_eigenvalue_count),
                        table_width
                    )
                )
            end
            if !ismissing(vr.determinant_sign_consistent)
                status = format_validation_value(vr.determinant_sign_consistent)
                push!(
                    lines,
                    format_table_row("Determinant sign consistent", status, table_width)
                )
            end

        elseif stats_table.point_type == :saddle
            if !ismissing(vr.mixed_eigenvalue_signs)
                status = format_validation_value(vr.mixed_eigenvalue_signs)
                push!(
                    lines,
                    format_table_row("Mixed eigenvalue signs", status, table_width)
                )
            end
        end

        # Show additional validation metrics if available
        for (key, value) in vr.additional_checks
            if isa(value, Number) && isfinite(value)
                display_key = format_validation_key(key)
                display_value =
                    isa(value, AbstractFloat) ? string(round(value, digits = 4)) :
                    string(value)
                push!(lines, format_table_row(display_key, display_value, table_width))
            end
        end
    end

    # Eigenvalue statistics section (if available)
    if !ismissing(stats_table.eigenvalue_stats)
        es = stats_table.eigenvalue_stats
        if es.count > 0
            push!(lines, create_table_border(table_width, :section))
            push!(lines, center_text("│", "EIGENVALUE STATISTICS", table_width - 2, "│"))
            push!(lines, create_table_border(table_width, :middle))

            push!(
                lines,
                format_table_row("Eigenvalue count", string(es.count), table_width)
            )
            push!(
                lines,
                format_table_row(
                    "Mean ± Std",
                    "$(round(es.mean, digits=6)) ± $(round(es.std, digits=6))",
                    table_width
                )
            )
            push!(
                lines,
                format_table_row(
                    "Range",
                    "[$(round(es.min, digits=6)), $(round(es.max, digits=6))]",
                    table_width
                )
            )
        end
    end

    # Recommendations section
    if !isempty(ca.recommendations)
        push!(lines, create_table_border(table_width, :section))
        push!(lines, center_text("│", "RECOMMENDATIONS", table_width - 2, "│"))
        push!(lines, create_table_border(table_width, :middle))

        for rec in ca.recommendations
            bullet = "• "
            # Word wrap long recommendations
            max_rec_width = table_width - 6  # Account for borders
            if length(rec) > max_rec_width - 2
                # Simple word wrap (could be enhanced)
                words = split(rec, " ")
                current_line = bullet
                for word in words
                    if length(current_line) + length(word) + 1 <= max_rec_width
                        current_line *= word * " "
                    else
                        push!(
                            lines,
                            format_table_row("", rstrip(current_line), table_width)
                        )
                        current_line = "  " * word * " "
                    end
                end
                if !isempty(rstrip(current_line))
                    push!(lines, format_table_row("", rstrip(current_line), table_width))
                end
            else
                push!(lines, format_table_row("", bullet * rec, table_width))
            end
        end
    end

    # Footer
    push!(lines, create_table_border(table_width, :bottom))

    return join(lines, "\n")
end

"""
    render_comparative_table(stats_list::Vector{ComprehensiveStatsTable}; width=100)

Create a comparative analysis table showing statistics across multiple critical point types.
"""
function render_comparative_table(stats_list::Vector{ComprehensiveStatsTable}; width = 100)
    if isempty(stats_list)
        return "No data available for comparative analysis."
    end

    lines = String[]
    table_width = min(width, 120)

    # Header
    title = "COMPARATIVE ANALYSIS"
    push!(lines, create_table_border(table_width, :top))
    push!(lines, center_text("│", title, table_width - 2, "│"))

    # Column headers
    push!(lines, create_table_border(table_width, :middle))
    header_line = "│ Type        │ Count │ Hess.Mean │ Hess.Std  │ WellCond% │ Valid%   │"
    if length(header_line) > table_width
        # Simplified header for narrow tables
        header_line = "│ Type      │ Count │ Mean  │ Std   │ Qual% │ Valid │"
    end
    push!(lines, header_line)
    push!(lines, create_table_border(table_width, :middle))

    # Data rows
    total_points = 0
    well_conditioned_total = 0.0
    valid_total = 0.0

    for stats in stats_list
        point_type = titlecase(string(stats.point_type))
        count = stats.hessian_stats.count
        total_points += count

        if count > 0
            hess_mean = round(stats.hessian_stats.mean, digits = 2)
            hess_std = round(stats.hessian_stats.std, digits = 2)

            # Well-conditioned percentage
            ca = stats.condition_analysis
            well_cond_pct = ca.total_count > 0 ? ca.well_conditioned_percentage : 0.0
            well_conditioned_total += count * well_cond_pct / 100

            # Validation percentage (simplified)
            vr = stats.validation_results
            valid_pct =
                if stats.point_type == :minimum && !ismissing(vr.eigenvalue_signs_correct)
                    vr.eigenvalue_signs_correct ? 100.0 : 0.0
                elseif stats.point_type == :maximum &&
                       !ismissing(vr.eigenvalue_signs_correct)
                    vr.eigenvalue_signs_correct ? 100.0 : 0.0
                elseif stats.point_type == :saddle && !ismissing(vr.mixed_eigenvalue_signs)
                    vr.mixed_eigenvalue_signs ? 100.0 : 0.0
                else
                    0.0
                end
            valid_total += count * valid_pct / 100

            # Format row
            if table_width >= 80
                row = "│ $(rpad(point_type, 11)) │ $(lpad(count, 5)) │ $(lpad(hess_mean, 9)) │ $(lpad(hess_std, 9)) │ $(lpad(round(well_cond_pct, digits=1), 9)) │ $(lpad(round(valid_pct, digits=1), 8)) │"
            else
                # Compact format
                row = "│ $(rpad(point_type[1:min(8, length(point_type))], 8)) │ $(lpad(count, 5)) │ $(lpad(hess_mean, 5)) │ $(lpad(hess_std, 5)) │ $(lpad(round(well_cond_pct, digits=1), 5)) │ $(lpad(round(valid_pct, digits=1), 5)) │"
            end
            push!(lines, row)
        end
    end

    # Summary section
    push!(lines, create_table_border(table_width, :middle))
    if total_points > 0
        overall_well_cond = round(100 * well_conditioned_total / total_points, digits = 1)
        overall_valid = round(100 * valid_total / total_points, digits = 1)

        push!(lines, center_text("│", "SUMMARY", table_width - 2, "│"))
        push!(lines, create_table_border(table_width, :middle))
        push!(
            lines,
            format_table_row("Total critical points", string(total_points), table_width)
        )
        push!(
            lines,
            format_table_row(
                "Overall numerical quality",
                overall_well_cond > 80 ? "EXCELLENT" :
                overall_well_cond > 60 ? "GOOD" : "FAIR",
                table_width
            )
        )
        push!(
            lines,
            format_table_row(
                "Mathematical validation",
                "$(overall_valid)% pass rate",
                table_width
            )
        )
        push!(
            lines,
            format_table_row(
                "Production readiness",
                (overall_well_cond > 70 && overall_valid > 80) ? "READY" : "NEEDS REVIEW",
                table_width
            )
        )
    end

    push!(lines, create_table_border(table_width, :bottom))

    return join(lines, "\n")
end

"""
    render_table(table::StatisticalTable; output=:console, width=80, kwargs...)

Universal table rendering dispatch function.
"""
function render_table(table::StatisticalTable; output = :console, width = 80, kwargs...)
    if output == :console
        if isa(table, ComprehensiveStatsTable)
            return render_console_table(table; width = width)
        else
            error("Console rendering not implemented for $(typeof(table))")
        end
    else
        error("Output format $output not yet implemented")
    end
end

# ============================================================================
# HIGH-LEVEL ANALYSIS FUNCTIONS
# ============================================================================

"""
    display_statistical_table(stats_table::ComprehensiveStatsTable; width=80)

Display a single statistical table with proper formatting.
"""
function display_statistical_table(stats_table::ComprehensiveStatsTable; width = 80)
    table_string = render_console_table(stats_table; width = width)
    println("\n" * "="^width)
    println(table_string)
    println("="^width)
    return table_string
end

"""
    export_analysis_tables(rendered_tables::Dict{Symbol, String},
                          base_filename::String;
                          formats=[:console],
                          include_timestamp=true)

Export statistical tables in multiple formats for different use cases.

# Arguments
- `rendered_tables::Dict{Symbol, String}`: Tables to export
- `base_filename::String`: Base filename for exports
- `formats::Vector{Symbol}=[:console]`: Export formats
- `include_timestamp::Bool=true`: Include timestamp in filenames

# Examples
```julia
# Export tables from analysis
export_analysis_tables(tables, "critical_point_analysis",
                      formats=[:console, :markdown])
```
"""
function export_analysis_tables(
    rendered_tables::Dict{Symbol, String},
    base_filename::String;
    formats = [:console],
    include_timestamp = true
)

    timestamp_str = include_timestamp ? "_$(Dates.format(now(), "yyyymmdd_HHMMSS"))" : ""

    for (point_type, table_content) in rendered_tables
        for format in formats
            extension = format == :console ? "txt" : string(format)
            filename = "$(base_filename)_$(point_type)$(timestamp_str).$(extension)"

            try
                if format == :console
                    # Direct export of console content
                    write(filename, table_content)
                else
                    # Future: implement format conversion
                    @warn "Format conversion not yet implemented: $format"
                    continue
                end

                @info "Table exported: $filename"
            catch e
                @error "Failed to export table: $filename" exception = e
            end
        end
    end
end

"""
    create_statistical_summary(df_enhanced::DataFrame)

Create a quick statistical summary of all critical point types.

# Returns
- `String`: Formatted summary table
"""
function create_statistical_summary(df_enhanced::DataFrame)
    if !hasproperty(df_enhanced, :critical_point_type)
        return "No critical point type information available."
    end

    # Count by type
    type_counts = DataFrames.combine(
        DataFrames.groupby(df_enhanced, :critical_point_type),
        DataFrames.nrow => :count
    )
    total_points = nrow(df_enhanced)

    lines = String[]
    push!(lines, "┌─────────────────────────────────────────┐")
    push!(lines, "│           CRITICAL POINT SUMMARY        │")
    push!(lines, "├─────────────────┬───────────┬───────────┤")
    push!(lines, "│ Type            │ Count     │ Percent   │")
    push!(lines, "├─────────────────┼───────────┼───────────┤")

    for row in eachrow(type_counts)
        type_name = titlecase(string(row.critical_point_type))
        count = row.count
        percentage = round(100 * count / total_points, digits = 1)

        line = "│ $(rpad(type_name, 15)) │ $(lpad(count, 9)) │ $(lpad("$(percentage)%", 9)) │"
        push!(lines, line)
    end

    push!(lines, "├─────────────────┼───────────┼───────────┤")
    push!(
        lines,
        "│ $(rpad("TOTAL", 15)) │ $(lpad(total_points, 9)) │ $(lpad("100.0%", 9)) │"
    )
    push!(lines, "└─────────────────┴───────────┴───────────┘")

    return join(lines, "\n")
end

"""
    quick_table_preview(df::DataFrame; point_types=[:minimum, :maximum])

Generate a quick preview of statistical tables for a DataFrame that already
has critical point type and Hessian analysis columns.

Useful for rapid exploration of results.
"""
function quick_table_preview(df::DataFrame; point_types = [:minimum, :maximum])
    @info "Generating quick table preview..."

    # Check if Phase 2 analysis data is available
    if !hasproperty(df, :critical_point_type) || !hasproperty(df, :hessian_norm)
        @warn "DataFrame does not have required Phase 2 analysis columns (critical_point_type, hessian_norm)"
        return
    end

    df_enhanced = df

    # Show basic summary
    summary_table = create_statistical_summary(df_enhanced)
    println(summary_table)

    # Show simplified statistics for requested types
    for point_type in point_types
        stats_table = compute_type_specific_statistics(df_enhanced, point_type)
        if stats_table.hessian_stats.count > 0
            # Simplified display
            hs = stats_table.hessian_stats
            ca = stats_table.condition_analysis

            println("\n$(uppercase(string(point_type))) Quick Stats:")
            println("  Count: $(hs.count)")
            println(
                "  Hessian norm: $(round(hs.mean, digits=3)) ± $(round(hs.std, digits=3))"
            )
            if ca.total_count > 0
                println("  Well-conditioned: $(ca.well_conditioned_percentage)%")
                println("  Quality: $(ca.overall_quality)")
            end
        end
    end

    println("\nFor detailed analysis, use: compute_type_specific_statistics(df, :minimum)")
end
