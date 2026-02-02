"""
Test suite for Tidier + VegaLite integration
"""

using Test
using GlobtimPostProcessing
using DataFrames
using Tidier

@testset "TidierTransforms" begin
    @testset "campaign_to_tidy_dataframe" begin
        # Test that function exists and returns DataFrame
        @test isdefined(GlobtimPostProcessing, :campaign_to_tidy_dataframe)
        # Note: Full test requires actual campaign data
    end

    @testset "compute_convergence_analysis" begin
        # Test with sample data
        df = DataFrame(
            experiment_id = ["exp1", "exp1", "exp1"],
            degree = [2, 3, 4],
            l2_error = [1e-2, 1e-3, 1e-4],
            domain_size = [0.5, 0.5, 0.5],
            GN = [16, 16, 16]
        )

        df_conv = compute_convergence_analysis(df)

        @test nrow(df_conv) == 1
        @test "effective_convergence" in names(df_conv)
        @test "convergence_quality" in names(df_conv)
        @test df_conv.effective_convergence[1] > 0
    end

    @testset "compute_parameter_sensitivity" begin
        df = DataFrame(
            experiment_id = ["exp1", "exp2"],
            degree = [2, 2],
            l2_error = [1e-2, 2e-2],
            param_recovery_error = [1e-3, 2e-3],
            domain_size = [0.5, 0.5]
        )

        df_sens = compute_parameter_sensitivity(df)

        @test nrow(df_sens) >= 1
        @test "mean_l2" in names(df_sens)
        @test "std_l2" in names(df_sens)
    end

    @testset "pivot_metrics_longer" begin
        df = DataFrame(
            experiment_id = ["exp1", "exp1"],
            domain_size = [0.5, 0.5],
            GN = [16, 16],
            degree = [2, 3],
            l2_error = [1e-2, 1e-3],
            param_recovery_error = [1e-3, 1e-4]
        )

        df_long = pivot_metrics_longer(df)

        @test nrow(df_long) > nrow(df)  # Should have more rows (long format)
        @test "metric_name" in names(df_long)
        @test "metric_value" in names(df_long)
        @test "metric_category" in names(df_long)
    end

    @testset "annotate_outliers" begin
        df = DataFrame(
            experiment_id = ["exp$i" for i in 1:20],
            degree = fill(2, 20),
            l2_error = [fill(1e-3, 18); 1e-1; 1e-2]  # Two potential outliers
        )

        df_outliers = annotate_outliers(df, :l2_error, threshold=2.0)

        @test "is_outlier" in names(df_outliers)
        @test "z_score" in names(df_outliers)
        @test any(df_outliers.is_outlier)  # Should detect at least one outlier
    end

    @testset "add_comparison_baseline" begin
        df = DataFrame(
            experiment_id = ["exp1", "exp1", "exp2", "exp2"],
            degree = [2, 3, 2, 3],
            l2_error = [1e-2, 1e-3, 2e-2, 2e-3],
            param_recovery_error = [1e-3, 1e-4, 2e-3, 2e-4]
        )

        df_compared = add_comparison_baseline(df, "exp1")

        @test "baseline_l2" in names(df_compared)
        @test "l2_improvement_ratio" in names(df_compared)
        @test "better_than_baseline" in names(df_compared)

        # exp2 should have improvement ratios
        exp2_data = @chain df_compared begin
            @filter(experiment_id == "exp2")
        end
        @test all(!ismissing.(exp2_data.l2_improvement_ratio))
    end

    @testset "rolling_mean helper" begin
        x = [1.0, 2.0, 3.0, 4.0, 5.0]
        result = GlobtimPostProcessing.rolling_mean(x, 3)

        @test length(result) == length(x)
        @test result[1] ≈ 1.0  # First element
        @test result[3] ≈ 2.0  # (1+2+3)/3
        @test result[5] ≈ 4.0  # (3+4+5)/3
    end
end

@testset "VegaPlotting Functions" begin
    @testset "Function exports" begin
        # Test that all main functions are exported
        @test isdefined(GlobtimPostProcessing, :create_interactive_campaign_explorer)
        @test isdefined(GlobtimPostProcessing, :create_convergence_dashboard)
        @test isdefined(GlobtimPostProcessing, :create_parameter_sensitivity_plot)
        @test isdefined(GlobtimPostProcessing, :create_multi_metric_comparison)
        @test isdefined(GlobtimPostProcessing, :create_efficiency_analysis)
        @test isdefined(GlobtimPostProcessing, :create_outlier_detection_plot)
        @test isdefined(GlobtimPostProcessing, :create_baseline_comparison)
    end

    # Note: Full visualization tests require actual campaign data
    # and would create browser windows, so we only test function existence
end

@testset "Integration with existing module" begin
    @testset "Module exports" begin
        # Test that new exports don't break existing functionality
        @test isdefined(GlobtimPostProcessing, :load_experiment_results)
        @test isdefined(GlobtimPostProcessing, :load_campaign_results)
        @test isdefined(GlobtimPostProcessing, :compute_statistics)
        @test isdefined(GlobtimPostProcessing, :analyze_campaign)
    end
end

println("\n✓ All Tidier + VegaLite integration tests passed!")
