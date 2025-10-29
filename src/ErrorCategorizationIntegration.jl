"""
ErrorCategorizationIntegration.jl - Phase 3 of Issue #20

Integrates globtimcore's ErrorCategorization module into post-processing pipeline.

Features:
- Campaign-wide error analysis and categorization
- Priority-based error reporting
- Error distribution statistics
- Actionable recommendations
- Integration with batch processing

Author: GlobTim Team
Created: October 2025 (Issue #20, Phase 3)
"""

using DataFrames
using Statistics
using Globtim.ErrorCategorization
import Globtim.ErrorCategorization: ErrorCategory, ErrorClassification,
    categorize_error, analyze_experiment_errors, generate_error_report,
    ERROR_TAXONOMY, SEVERITY_LEVELS

# Re-export for convenience
export categorize_campaign_errors, generate_error_summary
export get_error_categories, get_severity_levels
export categorize_error_message, extract_campaign_errors
export filter_errors_by_category, filter_errors_by_severity
export get_top_priority_errors, get_experiment_errors
export calculate_error_rate, get_most_common_error_category
export calculate_average_priority, analyze_errors_by_degree
export format_error_report, format_error_table
export get_error_dataframe, create_mock_campaign

# ============================================================================
# HELPER FUNCTIONS FOR ACCESSING ERROR CATEGORIES
# ============================================================================

"""
    get_error_categories() -> Vector{String}

Get list of available error categories.
"""
function get_error_categories()::Vector{String}
    return ["INTERFACE_BUG", "MATHEMATICAL_FAILURE", "INFRASTRUCTURE_ISSUE",
            "CONFIGURATION_ERROR", "UNKNOWN_ERROR"]
end

"""
    get_severity_levels() -> Vector{String}

Get list of available severity levels.
"""
function get_severity_levels()::Vector{String}
    return ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]
end

# ============================================================================
# SINGLE ERROR CATEGORIZATION
# ============================================================================

"""
    categorize_error_message(error_msg::String; context::Dict=Dict()) -> Dict

Categorize a single error message.

# Returns
Dictionary with keys: category, severity, confidence, priority_score, suggested_fixes
"""
function categorize_error_message(error_msg::String;
                                   context::Dict{String,Any}=Dict{String,Any}())::Dict{String,Any}
    classification = categorize_error(error_msg; context=context)

    return Dict{String,Any}(
        "category" => string(classification.category),
        "severity" => string(classification.severity),
        "confidence" => classification.confidence,
        "priority_score" => classification.priority_score,
        "suggested_fixes" => classification.suggested_fixes,
        "patterns_matched" => classification.patterns_matched
    )
end

# ============================================================================
# CAMPAIGN ERROR EXTRACTION
# ============================================================================

"""
    extract_campaign_errors(campaign::CampaignResults) -> DataFrame

Extract all errors from campaign experiments into a DataFrame.
"""
function extract_campaign_errors(campaign::CampaignResults)::DataFrame
    errors = []

    for experiment in campaign.experiments
        # Check if experiment has error information in metadata
        success = get(experiment.metadata, "success", true)
        error_msg = get(experiment.metadata, "error", "")

        if !success && !isempty(error_msg)
            push!(errors, Dict(
                "experiment_id" => experiment.experiment_id,
                "error_message" => error_msg,
                "success" => success,
                "degree" => get(experiment.metadata, "degree", 0),
                "domain_range" => get(experiment.metadata, "domain_range", 0.0)
            ))
        end
    end

    if isempty(errors)
        return DataFrame(
            experiment_id = String[],
            error_message = String[],
            success = Bool[],
            degree = Int[],
            domain_range = Float64[]
        )
    end

    return DataFrame(errors)
end

# ============================================================================
# CAMPAIGN ERROR ANALYSIS
# ============================================================================

"""
    categorize_campaign_errors(campaign::CampaignResults) -> Dict{String,Any}

Analyze and categorize all errors in a campaign.

# Returns
Dictionary with comprehensive error analysis including:
- total_errors: Total number of errors
- total_experiments: Total number of experiments
- error_rate: Fraction of experiments that failed
- category_distribution: Breakdown by error category
- severity_distribution: Breakdown by severity
- high_priority_errors: Errors with priority > 75
- recommendations: Actionable recommendations
"""
function categorize_campaign_errors(campaign::CampaignResults)::Dict{String,Any}
    total_experiments = length(campaign.experiments)

    # Extract errors
    error_df = extract_campaign_errors(campaign)
    total_errors = nrow(error_df)

    if total_errors == 0
        return Dict{String,Any}(
            "total_errors" => 0,
            "total_experiments" => total_experiments,
            "error_rate" => 0.0,
            "category_distribution" => [],
            "severity_distribution" => [],
            "high_priority_errors" => [],
            "recommendations" => String[],
            "success_rate" => 1.0
        )
    end

    # Categorize each error
    categorized = []
    for row in eachrow(error_df)
        context = Dict{String,Any}(
            "experiment_id" => row.experiment_id,
            "degree" => row.degree,
            "domain_range" => row.domain_range
        )

        classification = categorize_error_message(row.error_message; context=context)

        push!(categorized, merge(Dict(
            "experiment_id" => row.experiment_id,
            "error_message" => row.error_message
        ), classification))
    end

    categorized_df = DataFrame(categorized)

    # Category distribution
    category_counts = combine(groupby(categorized_df, :category), nrow => :count)
    sort!(category_counts, :count, rev=true)

    category_dist = [
        Dict("category" => row.category,
             "count" => row.count,
             "percentage" => round(100 * row.count / total_errors, digits=1))
        for row in eachrow(category_counts)
    ]

    # Severity distribution
    severity_counts = combine(groupby(categorized_df, :severity), nrow => :count)
    sort!(severity_counts, :count, rev=true)

    severity_dist = [
        Dict("severity" => row.severity,
             "count" => row.count,
             "percentage" => round(100 * row.count / total_errors, digits=1))
        for row in eachrow(severity_counts)
    ]

    # High priority errors
    high_priority = filter(row -> row.priority_score > 75, categorized_df)
    high_priority_list = [
        Dict("experiment_id" => row.experiment_id,
             "category" => row.category,
             "severity" => row.severity,
             "priority_score" => row.priority_score,
             "confidence" => row.confidence)
        for row in eachrow(high_priority)
    ]

    # Generate recommendations
    recommendations = generate_recommendations_from_analysis(categorized_df, category_counts, total_errors)

    return Dict{String,Any}(
        "total_errors" => total_errors,
        "total_experiments" => total_experiments,
        "error_rate" => round(total_errors / total_experiments, digits=3),
        "success_rate" => round(1.0 - total_errors / total_experiments, digits=3),
        "category_distribution" => category_dist,
        "severity_distribution" => severity_dist,
        "high_priority_errors" => high_priority_list,
        "recommendations" => recommendations,
        "average_confidence" => mean(categorized_df.confidence)
    )
end

# ============================================================================
# ERROR SUMMARY GENERATION
# ============================================================================

"""
    generate_error_summary(campaign::CampaignResults;
                          sort_by_priority::Bool=false,
                          include_details::Bool=false) -> Dict{String,Any}

Generate comprehensive error summary for a campaign.
"""
function generate_error_summary(campaign::CampaignResults;
                                sort_by_priority::Bool=false,
                                include_details::Bool=false)::Dict{String,Any}
    analysis = categorize_campaign_errors(campaign)

    if include_details
        error_df = extract_campaign_errors(campaign)

        detailed_errors = []
        for row in eachrow(error_df)
            context = Dict{String,Any}(
                "experiment_id" => row.experiment_id,
                "degree" => row.degree,
                "domain_range" => row.domain_range
            )

            classification = categorize_error_message(row.error_message; context=context)

            push!(detailed_errors, Dict(
                "experiment_id" => row.experiment_id,
                "category" => classification["category"],
                "severity" => classification["severity"],
                "priority_score" => classification["priority_score"],
                "confidence" => classification["confidence"],
                "suggested_fixes" => classification["suggested_fixes"],
                "error_message" => row.error_message
            ))
        end

        if sort_by_priority
            sort!(detailed_errors, by = x -> x["priority_score"], rev=true)
        end

        analysis["detailed_errors"] = detailed_errors
    end

    if sort_by_priority && haskey(analysis, "high_priority_errors")
        sort!(analysis["high_priority_errors"], by = x -> x["priority_score"], rev=true)
    end

    return analysis
end

# ============================================================================
# ERROR FILTERING AND QUERIES
# ============================================================================

"""
    filter_errors_by_category(campaign::CampaignResults, category::String) -> Vector{Dict}

Filter errors by specific category.
"""
function filter_errors_by_category(campaign::CampaignResults, category::String)::Vector{Dict{String,Any}}
    error_df = extract_campaign_errors(campaign)

    filtered = []
    for row in eachrow(error_df)
        classification = categorize_error_message(row.error_message)
        if classification["category"] == category
            push!(filtered, merge(Dict("experiment_id" => row.experiment_id), classification))
        end
    end

    return filtered
end

"""
    filter_errors_by_severity(campaign::CampaignResults, severity::String) -> Vector{Dict}

Filter errors by severity level.
"""
function filter_errors_by_severity(campaign::CampaignResults, severity::String)::Vector{Dict{String,Any}}
    error_df = extract_campaign_errors(campaign)

    filtered = []
    for row in eachrow(error_df)
        classification = categorize_error_message(row.error_message)
        if classification["severity"] == severity
            push!(filtered, merge(Dict("experiment_id" => row.experiment_id), classification))
        end
    end

    return filtered
end

"""
    get_top_priority_errors(campaign::CampaignResults; n::Int=5) -> Vector{Dict}

Get top N errors by priority score.
"""
function get_top_priority_errors(campaign::CampaignResults; n::Int=5)::Vector{Dict{String,Any}}
    error_df = extract_campaign_errors(campaign)

    errors_with_priority = []
    for row in eachrow(error_df)
        classification = categorize_error_message(row.error_message)
        push!(errors_with_priority, merge(
            Dict("experiment_id" => row.experiment_id),
            classification
        ))
    end

    sort!(errors_with_priority, by = x -> x["priority_score"], rev=true)

    return first(errors_with_priority, min(n, length(errors_with_priority)))
end

"""
    get_experiment_errors(campaign::CampaignResults, experiment_id::String) -> Vector{Dict}

Get all errors for a specific experiment.
"""
function get_experiment_errors(campaign::CampaignResults, experiment_id::String)::Vector{Dict{String,Any}}
    error_df = extract_campaign_errors(campaign)

    exp_errors = filter(row -> row.experiment_id == experiment_id, error_df)

    errors = []
    for row in eachrow(exp_errors)
        classification = categorize_error_message(row.error_message)
        push!(errors, merge(Dict("experiment_id" => row.experiment_id), classification))
    end

    return errors
end

# ============================================================================
# ERROR STATISTICS
# ============================================================================

"""
    calculate_error_rate(campaign::CampaignResults) -> Float64

Calculate the fraction of experiments that failed.
"""
function calculate_error_rate(campaign::CampaignResults)::Float64
    total = length(campaign.experiments)
    errors = nrow(extract_campaign_errors(campaign))
    return errors / total
end

"""
    get_most_common_error_category(campaign::CampaignResults) -> Union{String,Nothing}

Get the most frequent error category in the campaign.
"""
function get_most_common_error_category(campaign::CampaignResults)::Union{String,Nothing}
    error_df = extract_campaign_errors(campaign)

    if nrow(error_df) == 0
        return nothing
    end

    categories = []
    for row in eachrow(error_df)
        classification = categorize_error_message(row.error_message)
        push!(categories, classification["category"])
    end

    category_counts = sort(collect(StatsBase.countmap(categories)), by = x -> x[2], rev=true)

    return first(category_counts)[1]
end

"""
    calculate_average_priority(campaign::CampaignResults) -> Float64

Calculate average priority score across all errors.
"""
function calculate_average_priority(campaign::CampaignResults)::Float64
    error_df = extract_campaign_errors(campaign)

    if nrow(error_df) == 0
        return 0.0
    end

    priorities = []
    for row in eachrow(error_df)
        classification = categorize_error_message(row.error_message)
        push!(priorities, classification["priority_score"])
    end

    return mean(priorities)
end

"""
    analyze_errors_by_degree(campaign::CampaignResults) -> Dict{Int,Int}

Analyze error distribution across polynomial degrees.
"""
function analyze_errors_by_degree(campaign::CampaignResults)::Dict{Int,Int}
    error_df = extract_campaign_errors(campaign)

    degree_errors = Dict{Int,Int}()

    for row in eachrow(error_df)
        degree = row.degree
        degree_errors[degree] = get(degree_errors, degree, 0) + 1
    end

    return degree_errors
end

# ============================================================================
# ERROR REPORT FORMATTING
# ============================================================================

"""
    format_error_report(campaign::CampaignResults; format::String="markdown") -> String

Format error analysis as markdown or JSON.
"""
function format_error_report(campaign::CampaignResults; format::String="markdown")::String
    analysis = categorize_campaign_errors(campaign)

    if format == "json"
        return JSON3.write(analysis, allow_inf=true)
    else
        return format_error_report_markdown(analysis)
    end
end

"""
    format_error_report_markdown(analysis::Dict) -> String

Format error analysis as markdown.
"""
function format_error_report_markdown(analysis::Dict{String,Any})::String
    io = IOBuffer()

    println(io, "# Error Analysis Report")
    println(io, "")
    println(io, "## Summary")
    println(io, "- Total Experiments: $(analysis["total_experiments"])")
    println(io, "- Total Errors: $(analysis["total_errors"])")
    println(io, "- Error Rate: $(round(100*analysis["error_rate"], digits=1))%")
    println(io, "- Success Rate: $(round(100*analysis["success_rate"], digits=1))%")
    println(io, "")

    if analysis["total_errors"] > 0
        println(io, "## Error Distribution by Category")
        for cat in analysis["category_distribution"]
            println(io, "- **$(cat["category"])**: $(cat["count"]) errors ($(cat["percentage"])%)")
        end
        println(io, "")

        println(io, "## Error Distribution by Severity")
        for sev in analysis["severity_distribution"]
            println(io, "- **$(sev["severity"])**: $(sev["count"]) errors ($(sev["percentage"])%)")
        end
        println(io, "")

        if !isempty(analysis["high_priority_errors"])
            println(io, "## High Priority Errors")
            println(io, "Errors with priority score > 75:")
            for err in analysis["high_priority_errors"]
                println(io, "- **$(err["experiment_id"])**: $(err["category"]) (Priority: $(err["priority_score"]))")
            end
            println(io, "")
        end

        if !isempty(analysis["recommendations"])
            println(io, "## Recommendations")
            for rec in analysis["recommendations"]
                println(io, "- $rec")
            end
        end
    else
        println(io, "**No errors found** - All experiments completed successfully! ✅")
    end

    return String(take!(io))
end

"""
    format_error_table(campaign::CampaignResults) -> String

Format errors as a terminal-friendly table.
"""
function format_error_table(campaign::CampaignResults)::String
    error_df = extract_campaign_errors(campaign)

    if nrow(error_df) == 0
        return "No errors found in campaign."
    end

    # Categorize errors
    categorized = []
    for row in eachrow(error_df)
        classification = categorize_error_message(row.error_message)
        push!(categorized, (
            row.experiment_id,
            classification["category"],
            classification["severity"],
            classification["priority_score"]
        ))
    end

    # Format as simple table
    io = IOBuffer()
    println(io, "Experiment ID | Category | Severity | Priority")
    println(io, "--------------|----------|----------|----------")
    for (exp_id, cat, sev, priority) in categorized
        println(io, "$exp_id | $cat | $sev | $priority")
    end

    return String(take!(io))
end

"""
    get_error_dataframe(campaign::CampaignResults) -> DataFrame

Get errors as a DataFrame with all categorization information.
"""
function get_error_dataframe(campaign::CampaignResults)::DataFrame
    error_df = extract_campaign_errors(campaign)

    if nrow(error_df) == 0
        return DataFrame(
            experiment_id = String[],
            category = String[],
            severity = String[],
            priority_score = Int[],
            confidence = Float64[]
        )
    end

    categorized = []
    for row in eachrow(error_df)
        classification = categorize_error_message(row.error_message)
        push!(categorized, Dict(
            "experiment_id" => row.experiment_id,
            "category" => classification["category"],
            "severity" => classification["severity"],
            "priority_score" => classification["priority_score"],
            "confidence" => classification["confidence"]
        ))
    end

    return DataFrame(categorized)
end

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

"""
    generate_recommendations_from_analysis(df::DataFrame, category_counts::DataFrame, total::Int) -> Vector{String}

Generate actionable recommendations based on error analysis.
"""
function generate_recommendations_from_analysis(df::DataFrame, category_counts::DataFrame, total::Int)::Vector{String}
    recommendations = String[]

    if nrow(category_counts) == 0
        return recommendations
    end

    # Top category
    top_category = category_counts[1, :category]
    top_count = category_counts[1, :count]
    top_pct = round(100 * top_count / total, digits=1)

    if top_pct > 50
        push!(recommendations,
            "PRIMARY FOCUS: $top_category represents $top_pct% of errors. Addressing this category will have maximum impact.")
    end

    # Category-specific recommendations
    interface_bugs = nrow(filter(row -> row.category == "INTERFACE_BUG", df))
    if interface_bugs > 0
        pct = round(100 * interface_bugs / total, digits=1)
        push!(recommendations,
            "INTERFACE ISSUES: $interface_bugs errors ($pct%) are interface bugs. These are typically quick fixes - review API usage.")
    end

    math_failures = nrow(filter(row -> row.category == "MATHEMATICAL_FAILURE", df))
    if math_failures > 0
        pct = round(100 * math_failures / total, digits=1)
        push!(recommendations,
            "MATHEMATICAL TUNING: $math_failures errors ($pct%) are mathematical failures. Consider reducing polynomial degrees or adjusting parameters.")
    end

    # High priority
    high_priority = nrow(filter(row -> row.priority_score > 75, df))
    if high_priority > 0
        push!(recommendations,
            "URGENT ACTION: $high_priority errors have high priority scores (>75). Address these first for maximum stability improvement.")
    end

    return recommendations
end

"""
    create_mock_campaign(; all_successful::Bool=false, all_failed::Bool=false, empty::Bool=false) -> CampaignResults

Create a mock campaign for testing purposes.
"""
function create_mock_campaign(; all_successful::Bool=false, all_failed::Bool=false, empty::Bool=false)::CampaignResults
    experiments = ExperimentResult[]

    if empty
        return CampaignResults(
            "mock_empty_campaign",
            experiments,
            Dict{String,Any}(),
            now()
        )
    end

    if all_successful
        # Create 3 successful experiments
        for i in 1:3
            exp = ExperimentResult(
                "success_exp_$i",
                Dict{String,Any}("success" => true, "degree" => i+3),
                String[],
                String[],
                nothing,
                nothing,
                nothing,
                "/tmp/mock"
            )
            push!(experiments, exp)
        end
    elseif all_failed
        # Create 3 failed experiments
        errors = [
            "ERROR: type ExperimentResult has no field val",
            "HomotopyContinuation failed to converge",
            "DimensionMismatch in matrix multiplication"
        ]

        for (i, err_msg) in enumerate(errors)
            exp = ExperimentResult(
                "failed_exp_$i",
                Dict{String,Any}("success" => false, "error" => err_msg, "degree" => i+3),
                String[],
                String[],
                nothing,
                nothing,
                nothing,
                "/tmp/mock"
            )
            push!(experiments, exp)
        end
    end

    return CampaignResults(
        "mock_campaign",
        experiments,
        Dict{String,Any}(),
        now()
    )
end
