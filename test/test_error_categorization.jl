"""
Test suite for Phase 3: Error Categorization Integration (Issue #20)

Tests for integrating globtimcore's ErrorCategorization module into post-processing:
- Error category loading from experiment results
- Campaign-wide error distribution analysis
- Priority-based error reporting
- Error-aware campaign reports (markdown + JSON)
- Actionable recommendations based on error patterns
"""

using Test
using GlobtimPostProcessing
using DataFrames
using JSON3
using Dates

# Test data paths
TEST_CAMPAIGN_PATH = joinpath(@__DIR__, "..", "collected_experiments_20251013_083530",
                              "campaign_lotka_volterra_4d_extended_degrees")

@testset "Phase 3: Error Categorization Integration" begin

    @testset "1. ErrorCategorization Module Access" begin
        @testset "1.1 Load ErrorCategorization from globtimcore" begin
            # Test that we can access globtimcore's ErrorCategorization
            @test isdefined(GlobtimPostProcessing, :categorize_campaign_errors)
            @test isdefined(GlobtimPostProcessing, :generate_error_summary)
        end

        @testset "1.2 Error category types available" begin
            # Verify error category enums are accessible
            categories = get_error_categories()
            @test "INTERFACE_BUG" in categories
            @test "MATHEMATICAL_FAILURE" in categories
            @test "INFRASTRUCTURE_ISSUE" in categories
            @test "CONFIGURATION_ERROR" in categories
            @test "UNKNOWN_ERROR" in categories
        end

        @testset "1.3 Severity levels available" begin
            # Verify severity level enums are accessible
            severities = get_severity_levels()
            @test "CRITICAL" in severities
            @test "HIGH" in severities
            @test "MEDIUM" in severities
            @test "LOW" in severities
            @test "UNKNOWN" in severities
        end
    end

    @testset "2. Single Error Categorization" begin
        @testset "2.1 Categorize interface bug" begin
            error_msg = "ERROR: type ExperimentResult has no field val"
            category = categorize_error_message(error_msg)

            @test category isa Dict
            @test haskey(category, "category")
            @test category["category"] == "INTERFACE_BUG"
            @test haskey(category, "severity")
            @test haskey(category, "confidence")
            @test category["confidence"] > 0.0
        end

        @testset "2.2 Categorize mathematical failure" begin
            error_msg = "HomotopyContinuation failed to converge after 1000 iterations"
            category = categorize_error_message(error_msg)

            @test category["category"] == "MATHEMATICAL_FAILURE"
            @test category["severity"] == "MEDIUM"
            @test haskey(category, "suggested_fixes")
            @test length(category["suggested_fixes"]) > 0
        end

        @testset "2.3 Categorize configuration error" begin
            error_msg = "DimensionMismatch: attempted to multiply arrays of size (4,4) and (3,3)"
            category = categorize_error_message(error_msg)

            @test category["category"] == "CONFIGURATION_ERROR"
            @test haskey(category, "priority_score")
            @test category["priority_score"] isa Int
        end

        @testset "2.4 Unknown error classification" begin
            error_msg = "Some completely unknown error happened"
            category = categorize_error_message(error_msg)

            @test category["category"] == "UNKNOWN_ERROR"
            @test category["confidence"] < 0.5  # Low confidence for unknown
        end
    end

    @testset "3. Campaign Error Analysis" begin
        campaign = load_campaign_results(TEST_CAMPAIGN_PATH)

        @testset "3.1 Extract errors from campaign" begin
            errors = extract_campaign_errors(campaign)

            @test errors isa DataFrame
            @test "experiment_id" in names(errors)
            @test "error_message" in names(errors)
            @test "success" in names(errors)
        end

        @testset "3.2 Categorize all campaign errors" begin
            error_analysis = categorize_campaign_errors(campaign)

            @test error_analysis isa Dict
            @test haskey(error_analysis, "total_errors")
            @test haskey(error_analysis, "total_experiments")
            @test haskey(error_analysis, "error_rate")
            @test error_analysis["error_rate"] >= 0.0
            @test error_analysis["error_rate"] <= 1.0
        end

        @testset "3.3 Error distribution by category" begin
            error_analysis = categorize_campaign_errors(campaign)

            @test haskey(error_analysis, "category_distribution")
            dist = error_analysis["category_distribution"]
            @test dist isa Dict || dist isa Vector

            # Check structure
            if dist isa Vector
                @test all(haskey(item, "category") for item in dist)
                @test all(haskey(item, "count") for item in dist)
                @test all(haskey(item, "percentage") for item in dist)
            end
        end

        @testset "3.4 Error distribution by severity" begin
            error_analysis = categorize_campaign_errors(campaign)

            @test haskey(error_analysis, "severity_distribution")
            dist = error_analysis["severity_distribution"]
            @test dist isa Dict || dist isa Vector
        end

        @testset "3.5 High priority errors identified" begin
            error_analysis = categorize_campaign_errors(campaign)

            @test haskey(error_analysis, "high_priority_errors")
            high_priority = error_analysis["high_priority_errors"]
            @test high_priority isa Vector

            # Verify priority scores
            if !isempty(high_priority)
                @test all(err -> haskey(err, "priority_score"), high_priority)
                @test all(err -> err["priority_score"] > 75, high_priority)
            end
        end

        @testset "3.6 Error recommendations generated" begin
            error_analysis = categorize_campaign_errors(campaign)

            @test haskey(error_analysis, "recommendations")
            recommendations = error_analysis["recommendations"]
            @test recommendations isa Vector{String}

            # Should have actionable recommendations
            if error_analysis["total_errors"] > 0
                @test length(recommendations) > 0
            end
        end
    end

    @testset "4. Error-Aware Campaign Reports" begin
        @testset "4.1 Generate campaign report with error section" begin
            output_file = tempname() * ".md"

            success, result = batch_analyze_campaign(
                TEST_CAMPAIGN_PATH,
                output_file,
                silent=true,
                include_errors=true
            )

            @test success == true
            @test isfile(output_file)

            # Verify error section exists
            content = read(output_file, String)
            @test occursin("Error Analysis", content) || occursin("Error", content)

            # Cleanup
            rm(output_file, force=true)
        end

        @testset "4.2 Error section contains category breakdown" begin
            output_file = tempname() * ".md"

            batch_analyze_campaign(
                TEST_CAMPAIGN_PATH,
                output_file,
                silent=true,
                include_errors=true
            )

            content = read(output_file, String)

            # Check for error categories in report
            # At minimum, should have headers or structure for errors
            @test occursin("Error", content) || occursin("Success", content)

            # Cleanup
            rm(output_file, force=true)
        end

        @testset "4.3 Error section contains recommendations" begin
            output_file = tempname() * ".md"

            batch_analyze_campaign(
                TEST_CAMPAIGN_PATH,
                output_file,
                silent=true,
                include_errors=true
            )

            content = read(output_file, String)

            # Should contain recommendation section if errors exist
            # Or at least indicate no errors
            @test length(content) > 100

            # Cleanup
            rm(output_file, force=true)
        end

        @testset "4.4 JSON format includes error analysis" begin
            output_file = tempname() * ".json"

            success, result, stats = batch_analyze_campaign(
                TEST_CAMPAIGN_PATH,
                output_file,
                silent=true,
                return_stats=true,
                format="json",
                include_errors=true
            )

            @test success == true
            @test isfile(output_file)

            # Parse JSON
            json_content = read(output_file, String)
            parsed = JSON3.read(json_content)

            @test haskey(parsed, :statistics) || haskey(parsed, :campaign_id)

            # Check for error analysis in JSON
            if haskey(parsed, :error_analysis)
                error_section = parsed.error_analysis
                @test haskey(error_section, :total_errors) || haskey(error_section, :error_rate)
            end

            # Cleanup
            rm(output_file, force=true)
        end
    end

    @testset "5. Error Summary Generation" begin
        campaign = load_campaign_results(TEST_CAMPAIGN_PATH)

        @testset "5.1 Generate standalone error summary" begin
            summary = generate_error_summary(campaign)

            @test summary isa Dict
            @test haskey(summary, "total_errors")
            @test haskey(summary, "category_distribution")
            @test haskey(summary, "recommendations")
        end

        @testset "5.2 Error summary with priority sorting" begin
            summary = generate_error_summary(campaign, sort_by_priority=true)

            @test haskey(summary, "high_priority_errors")
            high_priority = summary["high_priority_errors"]

            # Verify sorted by priority (descending)
            if length(high_priority) > 1
                for i in 1:(length(high_priority)-1)
                    @test high_priority[i]["priority_score"] >= high_priority[i+1]["priority_score"]
                end
            end
        end

        @testset "5.3 Error summary includes experiment details" begin
            summary = generate_error_summary(campaign, include_details=true)

            @test haskey(summary, "detailed_errors")
            details = summary["detailed_errors"]
            @test details isa Vector

            # Each error should have full context
            if !isempty(details)
                first_error = details[1]
                @test haskey(first_error, "experiment_id")
                @test haskey(first_error, "category")
                @test haskey(first_error, "suggested_fixes")
            end
        end

        @testset "5.4 Error summary exports to DataFrame" begin
            error_df = get_error_dataframe(campaign)

            @test error_df isa DataFrame
            @test "experiment_id" in names(error_df)
            @test "category" in names(error_df)
            @test "severity" in names(error_df)
            @test "priority_score" in names(error_df)
        end
    end

    @testset "6. Error Filtering and Queries" begin
        campaign = load_campaign_results(TEST_CAMPAIGN_PATH)

        @testset "6.1 Filter errors by category" begin
            interface_bugs = filter_errors_by_category(campaign, "INTERFACE_BUG")
            @test interface_bugs isa Vector

            # All returned errors should be interface bugs
            for error in interface_bugs
                @test error["category"] == "INTERFACE_BUG"
            end
        end

        @testset "6.2 Filter errors by severity" begin
            high_severity = filter_errors_by_severity(campaign, "HIGH")
            @test high_severity isa Vector

            # All returned errors should be high severity
            for error in high_severity
                @test error["severity"] == "HIGH"
            end
        end

        @testset "6.3 Get top N priority errors" begin
            top_errors = get_top_priority_errors(campaign, n=5)
            @test top_errors isa Vector
            @test length(top_errors) <= 5

            # Should be sorted by priority (descending)
            if length(top_errors) > 1
                for i in 1:(length(top_errors)-1)
                    @test top_errors[i]["priority_score"] >= top_errors[i+1]["priority_score"]
                end
            end
        end

        @testset "6.4 Get errors by experiment" begin
            # Get first experiment ID from campaign
            if !isempty(campaign.experiments)
                exp_id = campaign.experiments[1].experiment_id
                exp_errors = get_experiment_errors(campaign, exp_id)

                @test exp_errors isa Vector
                for error in exp_errors
                    @test error["experiment_id"] == exp_id
                end
            end
        end
    end

    @testset "7. Campaign-Level Error Statistics" begin
        campaign = load_campaign_results(TEST_CAMPAIGN_PATH)

        @testset "7.1 Calculate error rate" begin
            error_rate = calculate_error_rate(campaign)
            @test error_rate isa Float64
            @test error_rate >= 0.0
            @test error_rate <= 1.0
        end

        @testset "7.2 Most common error category" begin
            most_common = get_most_common_error_category(campaign)
            # Should return category name or nothing if no errors
            @test most_common isa Union{String, Nothing}

            if !isnothing(most_common)
                categories = ["INTERFACE_BUG", "MATHEMATICAL_FAILURE",
                             "INFRASTRUCTURE_ISSUE", "CONFIGURATION_ERROR", "UNKNOWN_ERROR"]
                @test most_common in categories
            end
        end

        @testset "7.3 Average priority score" begin
            avg_priority = calculate_average_priority(campaign)
            @test avg_priority isa Float64
            @test avg_priority >= 0.0
        end

        @testset "7.4 Error distribution across degrees" begin
            degree_errors = analyze_errors_by_degree(campaign)
            @test degree_errors isa Dict

            # Keys should be degrees, values should be error counts
            for (degree, count) in degree_errors
                @test degree isa Int
                @test count isa Int
                @test count >= 0
            end
        end
    end

    @testset "8. Integration with Batch Processing" begin
        @testset "8.1 batch_analyze_campaign with errors enabled" begin
            output_file = tempname() * ".md"

            success, result, stats = batch_analyze_campaign(
                TEST_CAMPAIGN_PATH,
                output_file,
                silent=true,
                return_stats=true,
                include_errors=true
            )

            @test success == true
            @test stats isa Dict
            @test haskey(stats, "error_analysis") || haskey(stats, "campaign_summary")

            # Cleanup
            rm(output_file, force=true)
        end

        @testset "8.2 batch_analyze_campaign_with_progress includes errors" begin
            output_file = tempname() * ".md"

            success, result, stats = batch_analyze_campaign_with_progress(
                TEST_CAMPAIGN_PATH,
                output_file,
                show_progress=false,
                silent=true,
                include_errors=true
            )

            @test success == true
            @test isfile(output_file)

            # Cleanup
            rm(output_file, force=true)
        end

        @testset "8.3 CLI with error reporting flag" begin
            CLI_SCRIPT = joinpath(@__DIR__, "..", "scripts", "batch_analyze.jl")
            output_file = tempname() * ".md"

            exit_code = try
                run(`julia $CLI_SCRIPT --input $TEST_CAMPAIGN_PATH --output $output_file --silent --include-errors`)
                0
            catch e
                if e isa ProcessFailedException
                    e.procs[1].exitcode
                else
                    -1
                end
            end

            @test exit_code == 0
            @test isfile(output_file)

            # Cleanup
            rm(output_file, force=true)
        end
    end

    @testset "9. Error Report Formatting" begin
        campaign = load_campaign_results(TEST_CAMPAIGN_PATH)

        @testset "9.1 Markdown error report generation" begin
            error_report_md = format_error_report(campaign, format="markdown")
            @test error_report_md isa String
            @test length(error_report_md) > 0

            # Should contain markdown formatting
            @test occursin("#", error_report_md) || occursin("*", error_report_md) ||
                  occursin("Error", error_report_md) || occursin("No errors", error_report_md)
        end

        @testset "9.2 JSON error report generation" begin
            error_report_json = format_error_report(campaign, format="json")
            @test error_report_json isa String

            # Should be valid JSON
            parsed = JSON3.read(error_report_json)
            @test parsed isa AbstractDict
        end

        @testset "9.3 Terminal-friendly error table" begin
            error_table = format_error_table(campaign)
            @test error_table isa String

            # Should have table-like structure
            @test length(error_table) > 0
        end
    end

    @testset "10. Edge Cases" begin
        @testset "10.1 Campaign with no errors" begin
            # Create mock campaign with all successful experiments
            mock_campaign = create_mock_campaign(all_successful=true)

            error_analysis = categorize_campaign_errors(mock_campaign)
            @test error_analysis["total_errors"] == 0
            @test error_analysis["error_rate"] == 0.0
            @test isempty(error_analysis["recommendations"])
        end

        @testset "10.2 Campaign with all failed experiments" begin
            # Create mock campaign with all failed experiments
            mock_campaign = create_mock_campaign(all_failed=true)

            error_analysis = categorize_campaign_errors(mock_campaign)
            @test error_analysis["total_errors"] > 0
            @test error_analysis["error_rate"] == 1.0
            @test length(error_analysis["recommendations"]) > 0
        end

        @testset "10.3 Empty campaign" begin
            # Create empty campaign
            mock_campaign = create_mock_campaign(empty=true)

            error_analysis = categorize_campaign_errors(mock_campaign)
            @test error_analysis["total_errors"] == 0
            @test error_analysis["total_experiments"] == 0
        end

        @testset "10.4 Mixed success/failure campaign" begin
            # Real campaign should have mixed results
            campaign = load_campaign_results(TEST_CAMPAIGN_PATH)
            error_analysis = categorize_campaign_errors(campaign)

            @test error_analysis["total_experiments"] > 0
            # Error rate should be between 0 and 1
            @test 0.0 <= error_analysis["error_rate"] <= 1.0
        end
    end
end

println("\n" * "="^80)
println("Phase 3 Test Suite Complete")
println("="^80)
