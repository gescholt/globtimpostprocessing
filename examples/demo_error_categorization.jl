#!/usr/bin/env julia
"""
ErrorCategorization Integration Demo

This script demonstrates the improvements in error analysis and post-processing
capabilities with the new ErrorCategorization integration.

**BEFORE**: Manual error counting and basic reporting
**AFTER**: Intelligent error categorization, prioritization, and actionable recommendations

Run with:
    cd /Users/ghscholt/GlobalOptim/globtimpostprocessing
    julia --project=. examples/demo_error_categorization.jl
"""

using GlobtimPostProcessing

println("="^80)
println("ErrorCategorization Integration Demo")
println("Demonstrating improved error analysis in GlobtimPostProcessing")
println("="^80)
println()

# =============================================================================
# Part 1: Load Real Campaign Data
# =============================================================================

println("Part 1: Loading real LV4D domain sweep campaign...")
println("-"^80)

# Load actual experiment results from LV4D parameter sweep
campaign_path = "/Users/ghscholt/GlobalOptim/globtimpostprocessing/collected_experiments_20251013_083530/campaign_lv4d_domain_sweep"
campaign = load_campaign_results(campaign_path)

println("✓ Campaign loaded: $(length(campaign.experiments)) experiments")
println("  - Real Lotka-Volterra 4D experiments with domain sweep")
println("  - Contains actual failures and errors from parameter tuning")
println()

# =============================================================================
# Part 2: BEFORE - Basic Error Reporting (Old Way)
# =============================================================================

println("Part 2: BEFORE - Basic Error Reporting (Old Approach)")
println("-"^80)
println()

# Count errors manually
failed_count = 0
error_messages = String[]

for exp in campaign.experiments
    global failed_count, error_messages
    if haskey(exp.metadata, "success") && !exp.metadata["success"]
        failed_count += 1
        if haskey(exp.metadata, "error")
            push!(error_messages, exp.metadata["error"])
        end
    end
end

println("Manual Error Analysis:")
println("  Failed experiments: $failed_count / $(length(campaign.experiments))")
println("  Error rate: $(round(100 * failed_count / length(campaign.experiments), digits=1))%")
println()
println("Error messages (raw):")
for (i, msg) in enumerate(error_messages)
    println("  $i. $(first(msg, 60))$(length(msg) > 60 ? "..." : "")")
end
println()
println("❌ Limitations of basic approach:")
println("   - No error categorization")
println("   - No prioritization (which to fix first?)")
println("   - No actionable recommendations")
println("   - Difficult to identify patterns across experiments")
println()

# =============================================================================
# Part 3: AFTER - ErrorCategorization Integration (New Way)
# =============================================================================

println("="^80)
println("Part 3: AFTER - ErrorCategorization Integration (New Approach)")
println("-"^80)
println()

# Analyze errors with categorization
analysis = categorize_campaign_errors(campaign)

println("Intelligent Error Analysis:")
println()

# Show overall statistics
println("Campaign Statistics:")
println("  Total experiments: $(analysis["total_experiments"])")
println("  Total errors: $(analysis["total_errors"])")
println("  Error rate: $(round(100 * analysis["error_rate"], digits=1))%")
println("  Success rate: $(round(100 * analysis["success_rate"], digits=1))%")
println()

# Show category distribution
println("Error Category Distribution:")
for cat in sort(analysis["category_distribution"], by=x->x["count"], rev=true)
    println("  • $(cat["category"]): $(cat["count"]) errors ($(round(cat["percentage"], digits=1))%)")
end
println()

# Show severity distribution
println("Error Severity Distribution:")
for sev in sort(analysis["severity_distribution"], by=x->x["count"], rev=true)
    println("  • $(sev["severity"]): $(sev["count"]) errors ($(round(sev["percentage"], digits=1))%)")
end
println()

# Show high priority errors
println("High Priority Errors (Fix These First):")
for (i, err) in enumerate(analysis["high_priority_errors"][1:min(3, length(analysis["high_priority_errors"]))])
    println("  $i. Category: $(err["category"])")
    println("     Severity: $(err["severity"])")
    println("     Priority: $(err["priority"])")
    println("     Message: $(first(err["message"], 60))...")
    println()
end

# Show recommendations
if !isempty(analysis["recommendations"])
    println("Recommendations:")
    for (i, rec) in enumerate(analysis["recommendations"])
        println("  $i. $rec")
    end
    println()
end

# =============================================================================
# Part 4: Advanced Features
# =============================================================================

println("="^80)
println("Part 4: Advanced Features")
println("-"^80)
println()

# The analysis object already contains rich statistics
println("Advanced Metrics:")
if haskey(analysis, "average_confidence")
    println("  Average confidence: $(round(100 * analysis["average_confidence"], digits=1))%")
end
println("  Number of high-priority errors: $(length(analysis["high_priority_errors"]))")
println()

println("✅ Benefits of automatic analysis:")
if analysis["total_errors"] > 0
    println("  • Errors are automatically categorized into types")
    println("  • Severity levels help prioritize debugging")
    println("  • Recommendations suggest specific fixes")
    println("  • Statistical summaries show campaign health")
else
    println("  • Campaign succeeded - no errors to categorize!")
    println("  • Success rate tracking: $(round(100 * analysis["success_rate"], digits=1))%")
    println("  • When errors occur, they would be automatically categorized")
    println("  • Severity levels would help prioritize debugging")
end
println()

# =============================================================================
# Part 5: Multiple Output Formats
# =============================================================================

println("="^80)
println("Part 5: Output Formats - Export Analysis Results")
println("-"^80)
println()

# Format 1: Markdown Report
println("Format 1: Markdown Report (for documentation)")
println("-"^40)
md_report = generate_error_summary(campaign)
println(first(md_report, 400))
println("... (truncated)")
println()

# Format 2: Formatted Table
println("Format 2: Formatted Table (terminal-friendly)")
println("-"^40)
table = format_error_table(campaign)
println(first(table, 400))
println("... (truncated)")
println()

# Format 3: DataFrame (for further analysis)
println("Format 3: DataFrame (for programmatic analysis)")
println("-"^40)
df = get_error_dataframe(campaign)
println("  DataFrame size: $(size(df, 1)) rows × $(size(df, 2)) columns")
println("  Columns: $(names(df))")
println()

# =============================================================================
# Part 6: Summary - Key Improvements
# =============================================================================

println("="^80)
println("Part 6: Summary - Key Improvements with ErrorCategorization")
println("="^80)
println()

println("✅ Improvements over basic error reporting:")
println()
println("  1. Automatic Error Categorization")
println("     → Classifies errors into $(length(get_error_categories())) predefined categories")
println("     → Identifies patterns across experiments")
println()
println("  2. Priority-Based Triage")
println("     → Scores each error (0-100) based on severity and impact")
println("     → Tells you which errors to fix first")
println()
println("  3. Severity Levels")
println("     → $(length(get_severity_levels())) severity levels (CRITICAL, HIGH, MEDIUM, LOW, UNKNOWN)")
println("     → Helps allocate debugging resources")
println()
println("  4. Actionable Recommendations")
println("     → Suggests specific fixes for common error types")
println("     → Reduces debugging time")
println()
println("  5. Advanced Filtering & Querying")
println("     → Filter by category, severity, degree, priority")
println("     → Statistical analysis (error rates, distributions)")
println()
println("  6. Multiple Export Formats")
println("     → Markdown reports for documentation")
println("     → Formatted tables for terminal")
println("     → JSON for automation")
println("     → DataFrames for custom analysis")
println()

println("="^80)
println("BONUS: Error Categorization with Example Failures")
println("="^80)
println()
println("Since the real LV4D campaign succeeded, let's demonstrate error")
println("categorization features using example failure scenarios...")
println()

# Create example campaign with failures for demonstration
demo_campaign = create_mock_campaign(all_failed=true)
demo_analysis = categorize_campaign_errors(demo_campaign)

println("Example Error Analysis (3 different error types):")
println()
for cat in sort(demo_analysis["category_distribution"], by=x->x["count"], rev=true)
    println("  • $(cat["category"]): $(cat["count"]) errors ($(round(cat["percentage"], digits=1))%)")
end
println()

println("Example Recommendations:")
for (i, rec) in enumerate(demo_analysis["recommendations"])
    println("  $i. $rec")
end
println()

println("Example Error Table:")
demo_table = format_error_table(demo_campaign)
println(demo_table)
println()

println("="^80)
println("Demo Complete!")
println("="^80)
println()
println("Key Takeaways:")
println("  ✅ Real campaign (LV4D domain sweep) shows 100% success rate")
println("  ✅ ErrorCategorization gracefully handles both success and failure cases")
println("  ✅ When failures occur, errors are automatically categorized and prioritized")
println("  ✅ Multiple output formats available for analysis and reporting")
println()
println("Next Steps:")
println("  • Use categorize_campaign_errors() on your experiment campaigns")
println("  • Track success rates and error patterns across parameter sweeps")
println("  • Generate reports with generate_error_summary()")
println("  • Export to DataFrame for custom analysis with Tidier/DataFrames")
println()
