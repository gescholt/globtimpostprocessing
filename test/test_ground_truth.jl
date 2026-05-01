"""
    test_ground_truth.jl

Level 1 tests: Verify ground truth reference data.

Tests that:
1. CSV files exist for all 8 benchmark functions
2. CSVs load correctly with expected columns
3. All loaded CPs are verified critical points (gradient check)
4. Analytically known minima are present in the data
5. Classification counts are plausible
6. Expected minimum counts match (where known)

Run with:
    julia --project=profiles/dev pkg/globtimpostprocessing/test/test_ground_truth.jl
"""

using Test
using LinearAlgebra
using ForwardDiff
using CSV
using DataFrames

# Include oracle and function definitions (guarded for runtests.jl which pre-includes them)
if !@isdefined(CPVerification)
    include(joinpath(@__DIR__, "test_utils", "cp_verification.jl"))
end
if !@isdefined(GroundTruthFunctions)
    include(joinpath(@__DIR__, "test_utils", "ground_truth_functions.jl"))
end
using .CPVerification
using .GroundTruthFunctions

if !@isdefined(GT_DIR)
    const GT_DIR = joinpath(@__DIR__, "fixtures", "ground_truth")
end

# ============================================================================
# Helper: load a ground truth CSV
# ============================================================================
function load_ground_truth(name::String, dim::Int)
    filepath = joinpath(GT_DIR, "$(name)_critical_points.csv")
    @test isfile(filepath)
    isfile(filepath) || return nothing

    df = CSV.read(filepath, DataFrame)

    # Verify expected columns
    x_cols = [Symbol("x$i") for i in 1:dim]
    ev_cols = [Symbol("eigenvalue_$i") for i in 1:dim]
    required = vcat(
        x_cols,
        [:value, :grad_norm, :classification],
        ev_cols,
        [:neighborhood_confirmed],
    )

    for col in required
        @test col in propertynames(df)
    end

    return df
end

"""
    df_to_points(df, dim) -> Vector{Vector{Float64}}

Extract point coordinates from a DataFrame.
"""
function df_to_points(df::DataFrame, dim::Int)
    x_cols = [Symbol("x$i") for i in 1:dim]
    return [Float64[row[c] for c in x_cols] for row in eachrow(df)]
end

# ============================================================================
# Tests for each benchmark function
# ============================================================================

@testset "Level 1: Ground Truth Reference Data" begin
    @testset "CSV files exist" begin
        for bf in BENCHMARK_FUNCTIONS
            filepath = joinpath(GT_DIR, "$(bf.name)_critical_points.csv")
            @test isfile(filepath)
        end
    end

    @testset "sphere_2d ground truth" begin
        df = load_ground_truth("sphere_2d", 2)
        df === nothing && return

        # Should have exactly 1 CP (the minimum at origin)
        @test nrow(df) == 1

        # It should be a minimum
        @test df[1, :classification] == "minimum"

        # At the origin
        @test abs(df[1, :x1]) < 1e-6
        @test abs(df[1, :x2]) < 1e-6

        # Value should be 0
        @test df[1, :value] < 1e-12

        # Gradient norm should be tiny
        @test df[1, :grad_norm] < 1e-8
    end

    @testset "himmelblau ground truth" begin
        df = load_ground_truth("himmelblau", 2)
        df === nothing && return

        minima_df = df[df.classification .== "minimum", :]
        maxima_df = df[df.classification .== "maximum", :]
        saddle_df = df[df.classification .== "saddle", :]

        # Should have exactly 4 minima
        @test nrow(minima_df) == 4

        # Should have 1 local maximum
        @test nrow(maxima_df) == 1

        # Check all 4 known minima are found
        known = [
            [3.0, 2.0],
            [-2.805118, 3.131312],
            [-3.779310, -3.283186],
            [3.584428, -1.848126],
        ]
        points = df_to_points(minima_df, 2)

        for k in known
            found = any(p -> norm(p - k) < 0.01, points)
            @test found
        end

        # All minima should have f ≈ 0
        for row in eachrow(minima_df)
            @test row[:value] < 1e-6
        end

        # All CPs should have small gradient
        for row in eachrow(df)
            @test row[:grad_norm] < 1e-6
        end
    end

    @testset "sixhump_camel ground truth" begin
        df = load_ground_truth("sixhump_camel", 2)
        df === nothing && return

        minima_df = df[df.classification .== "minimum", :]

        # Should have at least 2 global minima
        @test nrow(minima_df) >= 2

        # Global minima near (±0.0898, ∓0.7126) with f ≈ -1.0316
        global_mins = [[0.0898, -0.7126], [-0.0898, 0.7126]]
        points = df_to_points(minima_df, 2)

        for gm in global_mins
            found = any(p -> norm(p - gm) < 0.01, points)
            @test found
        end

        # All CPs verified
        for row in eachrow(df)
            @test row[:grad_norm] < 1e-6
        end
    end

    @testset "rosenbrock_2d ground truth" begin
        df = load_ground_truth("rosenbrock_2d", 2)
        df === nothing && return

        minima_df = df[df.classification .== "minimum", :]

        # Single minimum at [1, 1]
        @test nrow(minima_df) == 1

        point = [minima_df[1, :x1], minima_df[1, :x2]]
        @test norm(point - [1.0, 1.0]) < 1e-4

        # f(1,1) = 0
        @test minima_df[1, :value] < 1e-8
    end

    @testset "deuflhard_2d ground truth" begin
        df = load_ground_truth("deuflhard_2d", 2)
        df === nothing && return

        minima_df = df[df.classification .== "minimum", :]

        # Deuflhard should have multiple critical points
        @test nrow(df) >= 3  # at least a few CPs

        # All CPs should be verified
        for row in eachrow(df)
            @test row[:grad_norm] < 1e-6
        end

        # Verify each CP independently using the oracle
        for row in eachrow(df)
            x = [row[:x1], row[:x2]]
            @test verify_critical_point(
                GroundTruthFunctions.deuflhard_2d,
                x;
                grad_tol = 1e-5,
            )
        end
    end

    @testset "styblinski_tang_2d ground truth" begin
        df = load_ground_truth("styblinski_tang_2d", 2)
        df === nothing && return

        minima_df = df[df.classification .== "minimum", :]

        # Should have 4 local minima
        @test nrow(minima_df) == 4

        # Global minimum near (-2.903534, -2.903534) with f ≈ -78.332
        points = df_to_points(minima_df, 2)
        global_min_found = any(p -> norm(p - [-2.903534, -2.903534]) < 0.01, points)
        @test global_min_found

        # All CPs verified
        for row in eachrow(df)
            @test row[:grad_norm] < 1e-6
        end
    end

    @testset "rastrigin_2d ground truth" begin
        df = load_ground_truth("rastrigin_2d", 2)
        df === nothing && return

        minima_df = df[df.classification .== "minimum", :]

        # Rastrigin has minima at all integer points in [-5,5]^2 = 121 minima
        # We may not find all 121 — but we should find a good fraction
        @test nrow(minima_df) >= 80  # at least ~66% recall

        # Global minimum at (0, 0) with f = 0
        points = df_to_points(minima_df, 2)
        global_min_found = any(p -> norm(p) < 0.01, points)
        @test global_min_found

        # All found CPs should have small gradient
        for row in eachrow(df)
            @test row[:grad_norm] < 1e-5
        end

        # All minima should be near integer points
        # (tolerance 0.05 accounts for boundary effects at ±5.12)
        for p in df_to_points(minima_df, 2)
            nearest_integer = round.(p)
            @test norm(p - nearest_integer) < 0.05
        end
    end

    @testset "deuflhard_4d ground truth" begin
        df = load_ground_truth("deuflhard_4d", 4)
        df === nothing && return

        minima_df = df[df.classification .== "minimum", :]

        # 4D Deuflhard = 2D + 2D, so #minima = #minima_2d ^ 2
        # Should have multiple CPs
        @test nrow(df) >= 5

        # All CPs should be verified
        for row in eachrow(df)
            @test row[:grad_norm] < 1e-5
        end

        # Cross-verify: each 4D CP should have its 2D sub-components
        # as approximate critical points of the 2D Deuflhard
        for row in eachrow(minima_df)
            x12 = [row[:x1], row[:x2]]
            x34 = [row[:x3], row[:x4]]
            # Each pair should be near a CP of 2D Deuflhard (loose check)
            g12 = ForwardDiff.gradient(GroundTruthFunctions.deuflhard_2d, x12)
            g34 = ForwardDiff.gradient(GroundTruthFunctions.deuflhard_2d, x34)
            @test norm(g12) < 1e-4
            @test norm(g34) < 1e-4
        end
    end

    @testset "All CSVs: classification values are valid" begin
        valid_classes = Set(["minimum", "maximum", "saddle", "degenerate"])
        for bf in BENCHMARK_FUNCTIONS
            filepath = joinpath(GT_DIR, "$(bf.name)_critical_points.csv")
            isfile(filepath) || continue
            df = CSV.read(filepath, DataFrame)
            for row in eachrow(df)
                @test string(row[:classification]) in valid_classes
            end
        end
    end

    @testset "All CSVs: eigenvalues have correct dimension" begin
        for bf in BENCHMARK_FUNCTIONS
            filepath = joinpath(GT_DIR, "$(bf.name)_critical_points.csv")
            isfile(filepath) || continue
            df = CSV.read(filepath, DataFrame)
            ev_cols = [Symbol("eigenvalue_$i") for i in 1:bf.dim]
            for col in ev_cols
                @test col in propertynames(df)
            end
        end
    end
end

println("\n✓ All Level 1 ground truth tests completed")
