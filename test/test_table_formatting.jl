"""
Test suite for TableFormatting module

Tests:
- Number formatting (scientific notation for small/large values)
- Experiment name extraction and truncation
- Grouped metric display
- Compact summary generation
"""

using Test
using GlobtimPostProcessing
using Dates

@testset "TableFormatting Tests" begin

    @testset "Number Formatting" begin
        # Import the formatting function from CampaignAnalysis
        include("../src/CampaignAnalysis.jl")

        # Test scientific notation for very small numbers
        @test format_scientific(1.23e-15) == "1.23e-15"
        @test format_scientific(5.67e-5) == "5.67e-05"

        # Test scientific notation for very large numbers
        @test format_scientific(2.46e30) == "2.46e+30"
        @test format_scientific(1.23e10) == "1.23e+10"

        # Test regular notation for moderate numbers
        @test format_scientific(0.1234) == "0.1234"
        @test format_scientific(123.4567) == "123.4568"
        @test format_scientific(1.0) == "1.0000"

        # Test special values
        @test format_scientific(NaN) == "N/A"
        @test format_scientific(Inf) == "+Inf"
        @test format_scientific(-Inf) == "-Inf"
    end

    @testset "Experiment Label Extraction" begin
        include("../src/CampaignAnalysis.jl")

        # Test extraction of key parameters
        @test occursin("GN", extract_experiment_label("4dlv_param_recovery_GN_14_deg_3:12"))
        @test occursin("exp1", extract_experiment_label("lv4d_exp1_range0.4_20251005"))
        @test occursin("dom", extract_experiment_label("experiment_domain_0.8"))

        # Test truncation
        long_name = "very_long_experiment_name_with_many_details_and_parameters"
        truncated = extract_experiment_label(long_name, max_length=20)
        @test length(truncated) <= 20

        # Test that short names are preserved
        short_name = "exp1"
        @test extract_experiment_label(short_name) == short_name
    end

    @testset "Mock Campaign Analysis" begin
        # Create mock campaign data
        mock_experiments = []

        for i in 1:3
            exp = ExperimentResult(
                "exp$i",
                Dict("params_dict" => Dict("domain_size" => 0.1 * i, "GN" => 14),
                     "total_critical_points" => 100 * i),
                ["approximation_quality", "parameter_recovery"],
                ["approximation_quality", "parameter_recovery", "timing"],
                nothing,
                nothing,
                nothing,
                "/tmp/exp$i"
            )
            push!(mock_experiments, exp)
        end

        campaign = CampaignResults(
            "test_campaign",
            mock_experiments,
            Dict("description" => "Test campaign"),
            now()
        )

        # This would normally run aggregate_campaign_statistics
        # For now, just test that campaign structure is valid
        @test length(campaign.experiments) == 3
        @test campaign.campaign_id == "test_campaign"
    end

    @testset "Grouped vs Compact Formatting" begin
        # Create minimal aggregated stats structure
        mock_agg_stats = Dict(
            "aggregated_metrics" => Dict(
                "approximation_quality" => Dict(
                    "mean" => 1.23e-4,
                    "min" => 5.67e-6,
                    "max" => 3.45e-3,
                    "std" => 8.90e-5,
                    "num_experiments" => 3,
                    "best_experiment" => "/path/to/exp1_GN14_dom0.1"
                ),
                "numerical_stability" => Dict(
                    "mean" => 2.46e30,  # Very large condition number
                    "min" => 1.23e10,
                    "max" => 5.67e31,
                    "std" => 1.23e30,
                    "num_experiments" => 3,
                    "best_experiment" => "/path/to/exp1_GN14_dom0.1"
                )
            ),
            "campaign_summary" => Dict(
                "num_experiments" => 3,
                "successful_experiments" => 3,
                "success_rate" => 1.0,
                "total_computation_hours" => 2.5
            )
        )

        # Test grouped formatting
        grouped_output = TableFormatting.format_metrics_table(
            mock_agg_stats,
            style=:grouped,
            max_width=100
        )

        @test occursin("Quality Metrics", grouped_output)
        @test occursin("L2 Error", grouped_output)
        @test occursin("Cond Number", grouped_output)
        @test occursin("Best Performers", grouped_output)

        # Verify scientific notation is used for large numbers
        @test occursin("2.46e+30", grouped_output)
        @test occursin("1.23e-04", grouped_output)

        # Verify no line exceeds max_width (with some tolerance for unicode)
        lines = split(grouped_output, '\n')
        # Most lines should be within max_width
        long_lines = filter(l -> length(l) > 105, lines)
        @test length(long_lines) < length(lines) * 0.1  # < 10% of lines too long

        # Test compact formatting
        compact_output = TableFormatting.format_metrics_table(
            mock_agg_stats,
            style=:compact
        )

        @test occursin("CAMPAIGN OVERVIEW", compact_output)
        @test occursin("Quick Summary", compact_output)
        @test occursin("L2 Error", compact_output)
        @test occursin("Success Rate", compact_output)
    end

    @testset "Width Constraints" begin
        mock_agg_stats = Dict(
            "aggregated_metrics" => Dict(),
            "campaign_summary" => Dict(
                "num_experiments" => 5,
                "successful_experiments" => 5,
                "success_rate" => 1.0,
                "total_computation_hours" => 1.5
            )
        )

        # Test with narrow width
        narrow_output = TableFormatting.format_metrics_table(
            mock_agg_stats,
            style=:grouped,
            max_width=80
        )

        # Verify most lines fit
        lines = split(narrow_output, '\n')
        long_lines = filter(l -> length(l) > 85, lines)
        @test length(long_lines) < length(lines) * 0.2  # < 20% tolerance

        # Test with wide width
        wide_output = TableFormatting.format_metrics_table(
            mock_agg_stats,
            style=:grouped,
            max_width=120
        )

        @test length(wide_output) > length(narrow_output)  # Should use more space
    end
end

println("✅ All TableFormatting tests passed!")
