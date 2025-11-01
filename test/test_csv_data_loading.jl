#!/usr/bin/env julia
"""
test_csv_data_loading.jl

TDD tests for loading experiment data directly from CSV files,
bypassing the truncated JSON results_summary.json files.

This is a workaround for the JSON truncation issue documented in:
globtimcore/docs/DATA_COLLECTION_TRUNCATION_ISSUE.md

Strategy:
1. Test basic CSV file discovery in experiment directories
2. Test CSV file parsing (headers, data types)
3. Test experiment config loading (separate from results_summary.json)
4. Test reconstruction of experiment metadata from CSV + config
5. Build up to full campaign loading

Usage:
    cd globtimpostprocessing
    julia --project=. test/test_csv_data_loading.jl
"""

using Test
using CSV
using DataFrames
using JSON3

# Test configuration
const TEST_CAMPAIGN = "../globtimcore/experiments/lotka_volterra_4d_study/configs_20251006_160051/hpc_results"
const TEST_EXPERIMENT = "lotka_volterra_4d_exp1_range0.4_20251006_160126"

@testset "CSV Data Loading Tests" begin

    @testset "1. Basic File Discovery" begin
        @testset "Can find hpc_results directory" begin
            @test isdir(TEST_CAMPAIGN)
        end

        @testset "Can find experiment directory" begin
            exp_dir = joinpath(TEST_CAMPAIGN, TEST_EXPERIMENT)
            @test isdir(exp_dir)
        end

        @testset "Can find CSV files" begin
            exp_dir = joinpath(TEST_CAMPAIGN, TEST_EXPERIMENT)
            csv_files = filter(f -> endswith(f, ".csv"), readdir(exp_dir))
            @test !isempty(csv_files)
            println("  Found $(length(csv_files)) CSV files")
        end

        @testset "CSV files follow naming pattern" begin
            exp_dir = joinpath(TEST_CAMPAIGN, TEST_EXPERIMENT)
            csv_files = filter(f -> endswith(f, ".csv"), readdir(exp_dir))
            pattern_files = filter(f -> occursin(r"critical_points_deg_\d+\.csv", f), csv_files)
            @test length(pattern_files) == length(csv_files)
            println("  All CSV files match naming pattern")
        end

        @testset "Can extract degree from filename" begin
            filename = "critical_points_deg_4.csv"
            m = match(r"critical_points_deg_(\d+)\.csv", filename)
            @test m !== nothing
            degree = parse(Int, m.captures[1])
            @test degree == 4
        end
    end

    @testset "2. CSV File Parsing" begin
        @testset "Can read CSV file" begin
            exp_dir = joinpath(TEST_CAMPAIGN, TEST_EXPERIMENT)
            csv_path = joinpath(exp_dir, "critical_points_deg_4.csv")
            @test isfile(csv_path)

            df = CSV.read(csv_path, DataFrame)
            @test df isa DataFrame
            @test nrow(df) >= 1
            println("  Loaded $(nrow(df)) rows from degree 4")
        end

        @testset "CSV has expected columns" begin
            exp_dir = joinpath(TEST_CAMPAIGN, TEST_EXPERIMENT)
            csv_path = joinpath(exp_dir, "critical_points_deg_4.csv")
            df = CSV.read(csv_path, DataFrame)

            # Should have x1, x2, x3, x4, z (objective value)
            expected_cols = ["x1", "x2", "x3", "x4", "z"]
            for col in expected_cols
                @test col in names(df)
            end
            println("  All expected columns present: $(names(df))")
        end

        @testset "CSV has numeric data" begin
            exp_dir = joinpath(TEST_CAMPAIGN, TEST_EXPERIMENT)
            csv_path = joinpath(exp_dir, "critical_points_deg_4.csv")
            df = CSV.read(csv_path, DataFrame)

            @test eltype(df.x1) <: Real
            @test eltype(df.z) <: Real
            @test all(isfinite, df.x1)
            @test all(isfinite, df.z)
            println("  Data types valid, all values finite")
        end

        @testset "Can find best point from CSV" begin
            exp_dir = joinpath(TEST_CAMPAIGN, TEST_EXPERIMENT)
            csv_path = joinpath(exp_dir, "critical_points_deg_4.csv")
            df = CSV.read(csv_path, DataFrame)

            best_idx = argmin(df.z)
            best_point = [df[best_idx, :x1], df[best_idx, :x2],
                         df[best_idx, :x3], df[best_idx, :x4]]
            best_value = df[best_idx, :z]

            @test length(best_point) == 4
            @test best_value == minimum(df.z)
            println("  Best point: $(round.(best_point, digits=4)), value: $(round(best_value, digits=2))")
        end
    end

    @testset "3. Experiment Config Loading" begin
        @testset "Can find experiment_config.json" begin
            exp_dir = joinpath(TEST_CAMPAIGN, TEST_EXPERIMENT)
            config_path = joinpath(exp_dir, "experiment_config.json")
            @test isfile(config_path)
        end

        @testset "Can parse experiment_config.json" begin
            exp_dir = joinpath(TEST_CAMPAIGN, TEST_EXPERIMENT)
            config_path = joinpath(exp_dir, "experiment_config.json")

            config = JSON3.read(read(config_path, String))
            @test haskey(config, "experiment_id")
            @test haskey(config, "degree_range")
            @test haskey(config, "sample_range")
            println("  Config keys: $(keys(config))")
        end

        @testset "Config contains expected metadata" begin
            exp_dir = joinpath(TEST_CAMPAIGN, TEST_EXPERIMENT)
            config_path = joinpath(exp_dir, "experiment_config.json")
            config = JSON3.read(read(config_path, String))

            @test config["experiment_id"] == 1
            @test config["degree_range"] isa AbstractArray
            @test length(config["degree_range"]) == 2
            @test config["sample_range"] isa Number
            println("  Experiment ID: $(config["experiment_id"])")
            println("  Degree range: $(config["degree_range"])")
            println("  Sample range: $(config["sample_range"])")
        end
    end

    @testset "4. Multi-Degree Data Loading" begin
        @testset "Can load all degrees for one experiment" begin
            exp_dir = joinpath(TEST_CAMPAIGN, TEST_EXPERIMENT)
            csv_files = filter(f -> occursin(r"critical_points_deg_\d+\.csv", f),
                             readdir(exp_dir))

            degree_data = Dict{Int, DataFrame}()
            for csv_file in csv_files
                m = match(r"critical_points_deg_(\d+)\.csv", csv_file)
                degree = parse(Int, m.captures[1])
                csv_path = joinpath(exp_dir, csv_file)
                df = CSV.read(csv_path, DataFrame)
                degree_data[degree] = df
            end

            @test length(degree_data) >= 4  # Should have multiple degrees
            degrees = sort(collect(keys(degree_data)))
            println("  Loaded degrees: $degrees")
        end

        @testset "Can compute L2 convergence from CSV" begin
            exp_dir = joinpath(TEST_CAMPAIGN, TEST_EXPERIMENT)
            config_path = joinpath(exp_dir, "experiment_config.json")
            config = JSON3.read(read(config_path, String))

            csv_files = filter(f -> occursin(r"critical_points_deg_\d+\.csv", f),
                             readdir(exp_dir))

            l2_data = []
            for csv_file in csv_files
                m = match(r"critical_points_deg_(\d+)\.csv", csv_file)
                degree = parse(Int, m.captures[1])
                csv_path = joinpath(exp_dir, csv_file)
                df = CSV.read(csv_path, DataFrame)

                best_value = minimum(df.z)
                push!(l2_data, (degree=degree, best_value=best_value))
            end

            @test length(l2_data) >= 4
            sort!(l2_data, by=x -> x.degree)

            println("  L2 convergence:")
            for d in l2_data
                println("    Degree $(d.degree): $(round(d.best_value, digits=2))")
            end
        end
    end

    @testset "5. Campaign-Level Loading" begin
        @testset "Can discover all experiments in campaign" begin
            @test isdir(TEST_CAMPAIGN)

            exp_dirs = filter(readdir(TEST_CAMPAIGN)) do d
                path = joinpath(TEST_CAMPAIGN, d)
                isdir(path) && !startswith(d, ".")
            end

            @test length(exp_dirs) >= 1
            println("  Found $(length(exp_dirs)) experiments in campaign")
            for d in exp_dirs
                println("    - $d")
            end
        end

        @testset "Can load config from all experiments" begin
            exp_dirs = filter(readdir(TEST_CAMPAIGN)) do d
                path = joinpath(TEST_CAMPAIGN, d)
                isdir(path) && !startswith(d, ".")
            end

            configs = Dict()
            for exp_dir_name in exp_dirs
                exp_dir = joinpath(TEST_CAMPAIGN, exp_dir_name)
                config_path = joinpath(exp_dir, "experiment_config.json")

                if isfile(config_path)
                    config = JSON3.read(read(config_path, String))
                    configs[exp_dir_name] = config
                end
            end

            @test length(configs) >= 1
            println("  Loaded configs for $(length(configs)) experiments")
        end
    end
end

println("\n" * "="^60)
println("✓ All TDD tests passed!")
println("CSV data loading strategy is viable.")
println("="^60)
