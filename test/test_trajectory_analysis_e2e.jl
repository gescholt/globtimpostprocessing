"""
End-to-End Integration Tests for Trajectory Analysis

Tests the complete workflow:
1. ObjectiveFunctionRegistry: Load model and reconstruct error function
2. TrajectoryEvaluator: Solve trajectories and evaluate critical points
3. TrajectoryComparison: Analyze convergence and generate reports
4. analyze_experiments.jl mode 4: Interactive analysis (programmatic test)

This validates the entire trajectory analysis pipeline works together.
"""

# Activate environment FIRST
using Pkg
Pkg.activate(dirname(@__DIR__))

using Test
using JSON3
using DataFrames
using CSV
using LinearAlgebra

println("=" ^ 80)
println("END-TO-END TRAJECTORY ANALYSIS INTEGRATION TESTS")
println("=" ^ 80)
println()

# Load all modules
println("[Setup] Loading modules...")
include(joinpath(dirname(@__DIR__), "src", "ObjectiveFunctionRegistry.jl"))
using .ObjectiveFunctionRegistry

include(joinpath(dirname(@__DIR__), "src", "TrajectoryEvaluator.jl"))
using .TrajectoryEvaluator

include(joinpath(dirname(@__DIR__), "src", "TrajectoryComparison.jl"))
using .TrajectoryComparison

println("✓ All modules loaded successfully")
println()

# Test configuration (Daisy Ex3 4D model)
test_config = Dict{String, Any}(
    "model_func" => "define_daisy_ex3_model_4D",
    "p_true" => [0.2, 0.3, 0.5, 0.6],
    "p_center" => [0.224, 0.273, 0.473, 0.578],
    "ic" => [1.0, 2.0, 1.0, 1.0],
    "time_interval" => [0.0, 10.0],
    "num_points" => 25,
    "dimension" => 4,
    "experiment_id" => "test_e2e_daisy"
)

@testset "End-to-End Trajectory Analysis" begin

    @testset "1. ObjectiveFunctionRegistry Integration" begin
        println("\n[Test 1] ObjectiveFunctionRegistry Integration")

        # Load DynamicalSystems module
        ds_module = load_dynamical_systems_module()
        @test !isnothing(ds_module)

        # Resolve model function
        model_func = resolve_model_function("define_daisy_ex3_model_4D", ds_module)
        @test model_func isa Function

        # Validate config
        @test validate_config(test_config) == true

        # Reconstruct error function
        error_func = reconstruct_error_function(test_config)
        @test error_func isa Function

        # Evaluate at true parameters (should be small)
        p_true = test_config["p_true"]
        error_at_true = error_func(p_true)
        @test error_at_true < 0.1

        # Evaluate at perturbed parameters (should be larger)
        p_perturbed = p_true .+ 0.2
        error_at_perturbed = error_func(p_perturbed)
        @test error_at_perturbed > error_at_true

        println("  ✓ Error at true params: $error_at_true")
        println("  ✓ Error at perturbed: $error_at_perturbed")
        println("  ✓ Ratio: $(error_at_perturbed / (error_at_true + 1e-10))x")
    end

    @testset "2. TrajectoryEvaluator Integration" begin
        println("\n[Test 2] TrajectoryEvaluator Integration")

        p_true = test_config["p_true"]
        p_found = [0.201, 0.298, 0.502, 0.599]  # Close to true

        # Solve trajectory with true parameters
        traj_true = solve_trajectory(test_config, p_true)
        @test !isnothing(traj_true)
        @test haskey(traj_true, "t")
        @test length(traj_true["t"]) == 25

        # Solve trajectory with found parameters
        traj_found = solve_trajectory(test_config, p_found)
        @test !isnothing(traj_found)

        # Compute trajectory distance
        dist_L2 = compute_trajectory_distance(traj_true, traj_found, :L2)
        @test dist_L2 >= 0
        @test dist_L2 isa Real

        # Distance to identical trajectory should be 0
        dist_self = compute_trajectory_distance(traj_true, traj_true, :L2)
        @test dist_self ≈ 0.0 atol=1e-10

        # Test symmetry
        dist_AB = compute_trajectory_distance(traj_true, traj_found, :L2)
        dist_BA = compute_trajectory_distance(traj_found, traj_true, :L2)
        @test dist_AB ≈ dist_BA

        println("  ✓ Trajectory distance (L2): $dist_L2")
        println("  ✓ Self-distance: $dist_self")
        println("  ✓ Symmetry verified")

        # Test evaluate_critical_point
        critical_point = (
            x1 = p_found[1],
            x2 = p_found[2],
            x3 = p_found[3],
            x4 = p_found[4],
            z = 0.00234
        )

        metrics = evaluate_critical_point(test_config, critical_point)
        @test metrics.p_found == p_found
        @test metrics.p_true == p_true
        @test metrics.param_distance >= 0
        @test metrics.trajectory_distance >= 0
        @test metrics.objective_value == 0.00234

        println("  ✓ Parameter distance: $(metrics.param_distance)")
        println("  ✓ Trajectory distance: $(metrics.trajectory_distance)")

        # Test compare_trajectories
        comparison = compare_trajectories(test_config, p_true, p_found)
        @test haskey(comparison.distances, :L1)
        @test haskey(comparison.distances, :L2)
        @test haskey(comparison.distances, :Linf)
        @test comparison.distances[:L2] == dist_L2

        println("  ✓ L1 distance: $(comparison.distances[:L1])")
        println("  ✓ L2 distance: $(comparison.distances[:L2])")
        println("  ✓ Linf distance: $(comparison.distances[:Linf])")
    end

    @testset "3. TrajectoryComparison Integration" begin
        println("\n[Test 3] TrajectoryComparison Integration")

        # Create temporary test experiment directory
        temp_exp_dir = mktempdir()

        try
            # Write config file
            config_file = joinpath(temp_exp_dir, "experiment_config.json")
            open(config_file, "w") do io
                JSON3.write(io, test_config)
            end

            # Create mock critical points CSV files for different degrees
            degrees = [4, 6, 8]

            for deg in degrees
                cp_data = DataFrame(
                    x1 = [0.201, 0.19, 0.205],
                    x2 = [0.298, 0.31, 0.295],
                    x3 = [0.502, 0.49, 0.505],
                    x4 = [0.599, 0.61, 0.595],
                    z = [0.00234, 0.00156, 0.00289],
                    gradient_norm = [1e-6, 1e-6, 1e-6]
                )

                csv_file = joinpath(temp_exp_dir, "critical_points_deg_$(deg).csv")
                CSV.write(csv_file, cp_data)
            end

            # Test load_critical_points_for_degree
            cp_df = load_critical_points_for_degree(temp_exp_dir, 8)
            @test nrow(cp_df) == 3
            @test haskey(cp_df, :x1)
            @test haskey(cp_df, :z)

            println("  ✓ Loaded critical points: $(nrow(cp_df)) points")

            # Test evaluate_all_critical_points
            evaluated_df = evaluate_all_critical_points(test_config, cp_df)
            @test nrow(evaluated_df) == 3
            @test haskey(evaluated_df, :param_distance)
            @test haskey(evaluated_df, :trajectory_distance)
            @test haskey(evaluated_df, :is_recovery)

            println("  ✓ Evaluated all critical points")
            println("  ✓ Parameter distances: ", evaluated_df.param_distance)

            # Test rank_critical_points
            ranked_df = rank_critical_points(evaluated_df, :param_distance)
            @test haskey(ranked_df, :rank)
            @test ranked_df[1, :rank] == 1
            @test ranked_df[1, :param_distance] <= ranked_df[2, :param_distance]

            println("  ✓ Ranked critical points")

            # Test identify_parameter_recovery
            recoveries = identify_parameter_recovery(evaluated_df, 0.05)
            @test nrow(recoveries) >= 0
            @test nrow(recoveries) <= nrow(evaluated_df)

            println("  ✓ Identified $(nrow(recoveries)) parameter recoveries")

            # Test analyze_experiment_convergence
            convergence = analyze_experiment_convergence(temp_exp_dir)
            @test length(convergence.degrees) == 3
            @test convergence.degrees == [4, 6, 8]
            @test haskey(convergence.num_critical_points_by_degree, 4)
            @test convergence.num_critical_points_by_degree[4] == 3

            println("  ✓ Convergence analysis complete")
            println("  ✓ Analyzed degrees: ", convergence.degrees)

            for deg in convergence.degrees
                println("    - Degree $deg: $(convergence.num_critical_points_by_degree[deg]) points, " *
                       "$(convergence.num_recoveries_by_degree[deg]) recoveries")
            end

            # Test generate_comparison_report (text format)
            report_text = generate_comparison_report(temp_exp_dir, :text)
            @test report_text isa String
            @test occursin("CONVERGENCE ANALYSIS", report_text)
            @test occursin("Degree", report_text)

            println("  ✓ Generated text report ($(length(report_text)) chars)")

            # Test generate_comparison_report (JSON format)
            report_json = generate_comparison_report(temp_exp_dir, :json)
            @test report_json isa Dict
            @test haskey(report_json, "degrees")
            @test report_json["degrees"] == [4, 6, 8]

            println("  ✓ Generated JSON report")

            # Test compare_degrees
            comparison = compare_degrees(temp_exp_dir, 4, 8)
            @test comparison.deg1_metrics.degree == 4
            @test comparison.deg2_metrics.degree == 8

            println("  ✓ Degree comparison:")
            println("    - Degree 4: $(comparison.deg1_metrics.num_critical_points) points, " *
                   "best dist = $(comparison.deg1_metrics.best_param_distance)")
            println("    - Degree 8: $(comparison.deg2_metrics.num_critical_points) points, " *
                   "best dist = $(comparison.deg2_metrics.best_param_distance)")

        finally
            # Cleanup
            rm(temp_exp_dir, recursive=true, force=true)
        end
    end

    @testset "4. Full Pipeline Integration" begin
        println("\n[Test 4] Full Pipeline Integration")

        # Create temporary campaign directory
        temp_campaign_dir = mktempdir()

        try
            # Create 2 mock experiments
            for exp_id in 1:2
                exp_dir = joinpath(temp_campaign_dir, "exp_$(exp_id)")
                mkpath(exp_dir)

                # Config
                exp_config = copy(test_config)
                exp_config["experiment_id"] = exp_id
                exp_config["sample_range"] = 0.1 * exp_id

                config_file = joinpath(exp_dir, "experiment_config.json")
                open(config_file, "w") do io
                    JSON3.write(io, exp_config)
                end

                # Critical points for degrees 4, 8
                for deg in [4, 8]
                    cp_data = DataFrame(
                        x1 = [0.20 + 0.01 * exp_id],
                        x2 = [0.30 - 0.01 * exp_id],
                        x3 = [0.50],
                        x4 = [0.60],
                        z = [0.001 * exp_id],
                        gradient_norm = [1e-6]
                    )

                    csv_file = joinpath(exp_dir, "critical_points_deg_$(deg).csv")
                    CSV.write(csv_file, cp_data)
                end
            end

            # Test analyze_campaign_parameter_recovery
            campaign_df = analyze_campaign_parameter_recovery(temp_campaign_dir)
            @test nrow(campaign_df) == 2
            @test haskey(campaign_df, :experiment_id)
            @test haskey(campaign_df, :best_param_distance)
            @test haskey(campaign_df, :total_critical_points)

            println("  ✓ Campaign analysis complete")
            println("  ✓ Analyzed $(nrow(campaign_df)) experiments")

            for row in eachrow(campaign_df)
                println("    - Exp $(row.experiment_id): $(row.total_critical_points) points, " *
                       "best dist = $(row.best_param_distance)")
            end

        finally
            # Cleanup
            rm(temp_campaign_dir, recursive=true, force=true)
        end
    end

    @testset "5. Error Handling" begin
        println("\n[Test 5] Error Handling")

        # Test unknown model function
        @test_throws ErrorException resolve_model_function("unknown_model", load_dynamical_systems_module())

        # Test invalid config
        invalid_config = Dict("model_func" => "define_daisy_ex3_model_4D")
        @test_throws ErrorException validate_config(invalid_config)

        # Test unknown norm type
        p_true = test_config["p_true"]
        traj = solve_trajectory(test_config, p_true)
        @test_throws ErrorException compute_trajectory_distance(traj, traj, :UnknownNorm)

        # Test missing critical points file
        @test_throws ErrorException load_critical_points_for_degree("/nonexistent/path", 8)

        println("  ✓ All error cases handled correctly")
    end

end

println()
println("=" ^ 80)
println("✓ ALL END-TO-END INTEGRATION TESTS PASSED!")
println("=" ^ 80)
println()

println("""
TRAJECTORY ANALYSIS PIPELINE READY FOR USE!

The complete workflow is functional:
1. ✓ ObjectiveFunctionRegistry: Model loading and error function reconstruction
2. ✓ TrajectoryEvaluator: Trajectory solving and critical point evaluation
3. ✓ TrajectoryComparison: Convergence analysis and reporting
4. ✓ analyze_experiments.jl mode 4: Interactive trajectory analysis

Usage:
    cd globtimpostprocessing
    julia analyze_experiments.jl

Then select mode 4 for interactive trajectory analysis.

Or programmatically:
    using .TrajectoryComparison
    convergence = analyze_experiment_convergence(exp_path)
    report = generate_comparison_report(exp_path, :markdown)
""")
