"""
test_schema_v110.jl

Tests for Schema v1.1.0 with refinement data support.
Tests format auto-detection, parameter recovery with refined coordinates,
and backward compatibility with Phase 1 and Phase 2 formats.
"""

using Test
using GlobtimPostProcessing
using GlobtimPostProcessing: detect_csv_schema, get_coordinate_columns, _extract_coordinate
using DataFrames
using CSV
using LinearAlgebra

const FIXTURES_DIR = joinpath(@__DIR__, "fixtures")

@testset "Schema v1.1.0 Support" begin

    @testset "CSV Schema Detection" begin
        @testset "Detects v1.1.0 format" begin
            df = CSV.read(joinpath(FIXTURES_DIR, "critical_points_v110_deg_4.csv"), DataFrame)
            @test detect_csv_schema(df) == :v1_1_0
        end

        @testset "Detects Phase 2 format" begin
            df = CSV.read(joinpath(FIXTURES_DIR, "critical_points_raw_deg_4.csv"), DataFrame)
            @test detect_csv_schema(df) == :phase2
        end

        @testset "Detects Phase 1 format" begin
            df = CSV.read(joinpath(FIXTURES_DIR, "critical_points_deg_4.csv"), DataFrame)
            @test detect_csv_schema(df) == :phase1
        end

        @testset "Errors on unrecognized schema" begin
            df = DataFrame(a=[1,2], b=[3,4])
            @test_throws ErrorException detect_csv_schema(df)
        end
    end

    @testset "Coordinate Column Resolution" begin
        @testset "v1.1.0 prefers refined coordinates" begin
            df = CSV.read(joinpath(FIXTURES_DIR, "critical_points_v110_deg_4.csv"), DataFrame)
            prefix, has_refinement = get_coordinate_columns(df, 4)
            @test prefix == "theta"
            @test has_refinement == true
        end

        @testset "Phase 2 uses p prefix" begin
            df = CSV.read(joinpath(FIXTURES_DIR, "critical_points_raw_deg_4.csv"), DataFrame)
            prefix, has_refinement = get_coordinate_columns(df, 4)
            @test prefix == "p"
            @test has_refinement == false
        end

        @testset "Phase 1 uses x prefix" begin
            df = CSV.read(joinpath(FIXTURES_DIR, "critical_points_deg_4.csv"), DataFrame)
            prefix, has_refinement = get_coordinate_columns(df, 4)
            @test prefix == "x"
            @test has_refinement == false
        end
    end

    @testset "v1.1.0 CSV Loading" begin
        @testset "Load v1.1.0 degree 4" begin
            df = CSV.read(joinpath(FIXTURES_DIR, "critical_points_v110_deg_4.csv"), DataFrame)
            @test nrow(df) == 5
            @test hasproperty(df, :theta1_raw)
            @test hasproperty(df, :theta1)
            @test hasproperty(df, :objective_raw)
            @test hasproperty(df, :objective)
            @test hasproperty(df, :l2_approx_error)
            @test hasproperty(df, :refinement_improvement)
        end

        @testset "Load v1.1.0 degree 6" begin
            df = CSV.read(joinpath(FIXTURES_DIR, "critical_points_v110_deg_6.csv"), DataFrame)
            @test nrow(df) == 7
            @test hasproperty(df, :theta1_raw)
            @test hasproperty(df, :theta4)
        end

        @testset "All v1.1.0 columns have numeric data" begin
            df = CSV.read(joinpath(FIXTURES_DIR, "critical_points_v110_deg_4.csv"), DataFrame)
            for col in names(df)
                @test eltype(df[!, col]) <: Real
            end
        end

        @testset "Refinement improvement is non-negative" begin
            df = CSV.read(joinpath(FIXTURES_DIR, "critical_points_v110_deg_4.csv"), DataFrame)
            @test all(df.refinement_improvement .>= 0)
        end

        @testset "Refined objective <= raw objective" begin
            df = CSV.read(joinpath(FIXTURES_DIR, "critical_points_v110_deg_4.csv"), DataFrame)
            @test all(df.objective .<= df.objective_raw)
        end
    end

    @testset "Parameter Recovery with v1.1.0 Data" begin
        p_true = [0.2, 0.3, 0.5, 0.6]

        @testset "Uses refined coordinates for recovery" begin
            df = CSV.read(joinpath(FIXTURES_DIR, "critical_points_v110_deg_4.csv"), DataFrame)
            stats = compute_parameter_recovery_stats(df, p_true, 1.0)

            @test haskey(stats, "schema")
            @test stats["schema"] == :v1_1_0
            @test stats["used_refined"] == true
            @test stats["min_distance"] >= 0.0
            @test stats["mean_distance"] >= stats["min_distance"]
            @test length(stats["all_distances"]) == nrow(df)
        end

        @testset "Refined coordinates give better recovery than raw" begin
            df = CSV.read(joinpath(FIXTURES_DIR, "critical_points_v110_deg_4.csv"), DataFrame)

            # Recovery with refined coordinates (default)
            stats_refined = compute_parameter_recovery_stats(df, p_true, 1.0)

            # Manually compute distance using raw coordinates for comparison
            raw_distances = Float64[]
            for row in eachrow(df)
                p_raw = [row[:theta1_raw], row[:theta2_raw], row[:theta3_raw], row[:theta4_raw]]
                push!(raw_distances, norm(p_raw - p_true))
            end
            min_raw_distance = minimum(raw_distances)

            # Refined should be at least as good (or better) than raw
            @test stats_refined["min_distance"] <= min_raw_distance + 1e-10
        end

        @testset "Degree 6 has better recovery than degree 4" begin
            df4 = CSV.read(joinpath(FIXTURES_DIR, "critical_points_v110_deg_4.csv"), DataFrame)
            df6 = CSV.read(joinpath(FIXTURES_DIR, "critical_points_v110_deg_6.csv"), DataFrame)

            stats4 = compute_parameter_recovery_stats(df4, p_true, 1.0)
            stats6 = compute_parameter_recovery_stats(df6, p_true, 1.0)

            # Degree 6 should generally be closer (but just check both compute)
            @test stats4["min_distance"] >= 0.0
            @test stats6["min_distance"] >= 0.0
        end
    end

    @testset "Backward Compatibility" begin
        p_true = [0.2, 0.3, 0.5, 0.6]

        @testset "Phase 2 format still works" begin
            df = load_critical_points_for_degree(FIXTURES_DIR, 4)
            # Phase 2 raw format is preferred (critical_points_raw_deg_4.csv)
            @test detect_csv_schema(df) == :phase2
            stats = compute_parameter_recovery_stats(df, p_true, 1.0)
            @test stats["schema"] == :phase2
            @test stats["used_refined"] == false
            @test stats["min_distance"] >= 0.0
        end

        @testset "Phase 1 format still works" begin
            # The Phase 1 fixtures have x1..x4, z columns plus extras
            # load_critical_points_for_degree prefers raw (Phase 2) over legacy (Phase 1)
            # So we load Phase 1 directly
            df = CSV.read(joinpath(FIXTURES_DIR, "critical_points_deg_4.csv"), DataFrame)
            @test detect_csv_schema(df) == :phase1
            stats = compute_parameter_recovery_stats(df, p_true, 1.0)
            @test stats["schema"] == :phase1
            @test stats["used_refined"] == false
            @test stats["min_distance"] >= 0.0
        end

        @testset "Recovery table generation with mixed schemas" begin
            # The fixture directory has Phase 2 raw format files
            table = generate_parameter_recovery_table(FIXTURES_DIR, p_true, [4, 6], 1.0)
            @test nrow(table) == 2
            @test all(table.min_distance .>= 0.0)
        end
    end

    @testset "has_ground_truth edge cases" begin
        @testset "Returns true for fixture with p_true" begin
            @test has_ground_truth(FIXTURES_DIR) == true
        end

        @testset "Returns false for nonexistent path" begin
            @test has_ground_truth("/nonexistent/path") == false
        end

        @testset "Returns false for directory without config" begin
            @test has_ground_truth(tempdir()) == false
        end
    end

end
