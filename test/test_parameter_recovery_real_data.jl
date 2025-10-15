"""
test_parameter_recovery_real_data.jl

Integration test for parameter recovery on real experimental data.
Tests Phase 2 of Issue #7 with actual HPC results.

Dataset: daisy_ex3_4d_study/configs_20251006_160051/hpc_results
This dataset has:
- p_true in configs (tests parameter recovery)
- Degree sweeps 4-12 (tests convergence)
- Domain variations (0.4, 0.8, 1.2, 1.6)
- 4 experiments (tests campaign mode)
"""

using Test
using GlobtimPostProcessing
using DataFrames
using Statistics

# Path to real experimental data
const TEST_DATASET_ROOT = joinpath(
    dirname(@__DIR__),
    "..",
    "globtimcore",
    "experiments",
    "daisy_ex3_4d_study",
    "configs_20251006_160051",
    "hpc_results"
)

@testset "Parameter Recovery - Real Data Integration" begin
    # Skip if dataset doesn't exist
    if !isdir(TEST_DATASET_ROOT)
        @warn "Real dataset not found at $TEST_DATASET_ROOT - skipping integration tests"
        @test_skip "Real dataset not available"
    else
        println("\n📂 Testing with real dataset: $TEST_DATASET_ROOT")

        @testset "Discover experiments in real dataset" begin
            # Should find experiment directories
            entries = readdir(TEST_DATASET_ROOT)
            exp_dirs = filter(e -> isdir(joinpath(TEST_DATASET_ROOT, e)), entries)

            @test length(exp_dirs) >= 1
            println("  Found $(length(exp_dirs)) experiment directories")
        end

        @testset "Load config from real experiment" begin
            # Get first experiment directory
            entries = readdir(TEST_DATASET_ROOT)
            exp_dirs = filter(e -> isdir(joinpath(TEST_DATASET_ROOT, e)), entries)

            if !isempty(exp_dirs)
                exp_path = joinpath(TEST_DATASET_ROOT, exp_dirs[1])
                println("  Testing experiment: $(exp_dirs[1])")

                # Load config
                config = load_experiment_config(exp_path)

                @test haskey(config, "dimension")
                @test config["dimension"] == 4

                # Check for p_true (this dataset should have it)
                if haskey(config, "p_true")
                    @test length(config["p_true"]) == 4
                    println("    ✓ Has p_true: $(config["p_true"])")
                else
                    @warn "    Expected p_true in config but not found"
                end
            end
        end

        @testset "Load critical points from real experiment" begin
            entries = readdir(TEST_DATASET_ROOT)
            exp_dirs = filter(e -> isdir(joinpath(TEST_DATASET_ROOT, e)), entries)

            if !isempty(exp_dirs)
                exp_path = joinpath(TEST_DATASET_ROOT, exp_dirs[1])

                # Find available CSV files
                csv_files = filter(f -> occursin(r"critical_points_deg_\d+\.csv", f), readdir(exp_path))

                if !isempty(csv_files)
                    # Extract degree from first CSV
                    m = match(r"critical_points_deg_(\d+)\.csv", csv_files[1])
                    degree = parse(Int, m.captures[1])

                    # Load critical points
                    df = load_critical_points_for_degree(exp_path, degree)

                    @test df isa DataFrame
                    @test nrow(df) > 0
                    @test hasproperty(df, :x1)
                    @test hasproperty(df, :z)

                    println("    ✓ Loaded $(nrow(df)) critical points for degree $degree")
                else
                    @warn "    No CSV files found in experiment"
                end
            end
        end

        @testset "Compute parameter recovery on real data" begin
            entries = readdir(TEST_DATASET_ROOT)
            exp_dirs = filter(e -> isdir(joinpath(TEST_DATASET_ROOT, e)), entries)

            if !isempty(exp_dirs)
                exp_path = joinpath(TEST_DATASET_ROOT, exp_dirs[1])

                # Load config to get p_true
                config = load_experiment_config(exp_path)

                if haskey(config, "p_true")
                    p_true = collect(config["p_true"])

                    # Find available degrees
                    csv_files = filter(f -> occursin(r"critical_points_deg_(\d+)\.csv", f), readdir(exp_path))

                    if !isempty(csv_files)
                        # Test on first available degree
                        m = match(r"critical_points_deg_(\d+)\.csv", csv_files[1])
                        degree = parse(Int, m.captures[1])

                        df = load_critical_points_for_degree(exp_path, degree)
                        stats = compute_parameter_recovery_stats(df, p_true, 0.01)

                        # Verify stats structure
                        @test haskey(stats, "min_distance")
                        @test haskey(stats, "mean_distance")
                        @test haskey(stats, "num_recoveries")
                        @test haskey(stats, "all_distances")

                        # Verify reasonable values
                        @test stats["min_distance"] >= 0.0
                        @test stats["mean_distance"] >= stats["min_distance"]
                        @test stats["num_recoveries"] >= 0
                        @test length(stats["all_distances"]) == nrow(df)

                        println("    Degree $degree:")
                        println("      Min distance:  $(round(stats["min_distance"], digits=6))")
                        println("      Mean distance: $(round(stats["mean_distance"], digits=6))")
                        println("      Recoveries:    $(stats["num_recoveries"]) / $(nrow(df))")
                    end
                end
            end
        end

        @testset "Generate parameter recovery table from real data" begin
            entries = readdir(TEST_DATASET_ROOT)
            exp_dirs = filter(e -> isdir(joinpath(TEST_DATASET_ROOT, e)), entries)

            if !isempty(exp_dirs)
                exp_path = joinpath(TEST_DATASET_ROOT, exp_dirs[1])
                config = load_experiment_config(exp_path)

                if haskey(config, "p_true")
                    p_true = collect(config["p_true"])

                    # Find all available degrees
                    csv_files = filter(f -> occursin(r"critical_points_deg_(\d+)\.csv", f), readdir(exp_path))
                    degrees = Int[]
                    for csv_file in csv_files
                        m = match(r"critical_points_deg_(\d+)\.csv", csv_file)
                        if m !== nothing
                            push!(degrees, parse(Int, m.captures[1]))
                        end
                    end
                    sort!(degrees)

                    if length(degrees) >= 2
                        # Generate table for first 2 degrees
                        test_degrees = degrees[1:min(2, length(degrees))]
                        recovery_table = generate_parameter_recovery_table(
                            exp_path, p_true, test_degrees, 0.01
                        )

                        @test recovery_table isa DataFrame
                        @test nrow(recovery_table) == length(test_degrees)
                        @test hasproperty(recovery_table, :degree)
                        @test hasproperty(recovery_table, :num_critical_points)
                        @test hasproperty(recovery_table, :min_distance)
                        @test hasproperty(recovery_table, :mean_distance)
                        @test hasproperty(recovery_table, :num_recoveries)

                        println("\n    Parameter Recovery Table:")
                        println("    " * "="^60)
                        for row in eachrow(recovery_table)
                            println("    Degree $(row.degree): $(row.num_critical_points) CPs, " *
                                   "min_dist=$(round(row.min_distance, digits=4)), " *
                                   "recoveries=$(row.num_recoveries)")
                        end
                        println("    " * "="^60)
                    end
                end
            end
        end

        @testset "Has ground truth check on real data" begin
            entries = readdir(TEST_DATASET_ROOT)
            exp_dirs = filter(e -> isdir(joinpath(TEST_DATASET_ROOT, e)), entries)

            if !isempty(exp_dirs)
                exp_path = joinpath(TEST_DATASET_ROOT, exp_dirs[1])

                # This dataset should have p_true
                @test has_ground_truth(exp_path) == true
                println("    ✓ Ground truth detected in real experiment")
            end
        end
    end
end
