"""
    test_hessian_classification_correctness.jl

Level 3: Verify that the pipeline's classify_critical_point function
agrees with the oracle's classification for all ground truth CPs.

This tests the actual function used in the pipeline (GlobtimPostProcessing's
classify_critical_point) against the oracle (ForwardDiff Hessian + our
eigenvalue classification). Any disagreement reveals a bug in the
classification logic or a sensitivity to tolerance parameters.

Run with:
    julia --project=profiles/dev pkg/globtimpostprocessing/test/test_hessian_classification_correctness.jl
"""

using Test
using LinearAlgebra
using ForwardDiff
using CSV
using DataFrames
using GlobtimPostProcessing

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

# Symbol → String mapping (oracle uses Symbol, pipeline uses String)
const SYM_TO_STR = Dict(
    :minimum => "minimum",
    :maximum => "maximum",
    :saddle => "saddle",
    :degenerate => "degenerate",
)

"""
    load_ground_truth_df(name, dim) -> DataFrame

Load ground truth CSV for a benchmark function.
"""
function load_ground_truth_df(name::String, dim::Int)
    filepath = joinpath(GT_DIR, "$(name)_critical_points.csv")
    isfile(filepath) || return nothing
    return CSV.read(filepath, DataFrame)
end

# ============================================================================
# Classification agreement tests
# ============================================================================
@testset "Level 3: Hessian Classification Correctness" begin
    @testset "Pipeline classify agrees with oracle at default tolerance" begin
        for bf in BENCHMARK_FUNCTIONS
            @testset "$(bf.name)" begin
                df = load_ground_truth_df(bf.name, bf.dim)
                df === nothing && continue

                for row in eachrow(df)
                    # Extract eigenvalues from CSV
                    ev_cols = [Symbol("eigenvalue_$i") for i in 1:bf.dim]
                    eigenvalues = Float64[row[c] for c in ev_cols]

                    # Oracle classification (from CSV, already computed by oracle)
                    oracle_class = string(row[:classification])

                    # Pipeline classification
                    pipeline_class = classify_critical_point(eigenvalues)

                    @test pipeline_class == oracle_class
                end
            end
        end
    end

    @testset "Pipeline classify with recomputed Hessian eigenvalues" begin
        # Instead of using stored eigenvalues, recompute them via ForwardDiff
        # and verify the pipeline still classifies correctly
        for bf in BENCHMARK_FUNCTIONS
            bf.name == "rastrigin_2d" && continue  # too many CPs
            bf.name == "deuflhard_4d" && continue  # too many CPs

            @testset "$(bf.name) recomputed" begin
                df = load_ground_truth_df(bf.name, bf.dim)
                df === nothing && continue

                x_cols = [Symbol("x$i") for i in 1:bf.dim]

                for row in eachrow(df)
                    x = Float64[row[c] for c in x_cols]
                    oracle_class = string(row[:classification])

                    # Recompute Hessian via ForwardDiff
                    H = ForwardDiff.hessian(bf.f, x)
                    eigenvalues = sort(real.(eigvals(H)))

                    # Pipeline classification of recomputed eigenvalues
                    pipeline_class = classify_critical_point(eigenvalues)

                    @test pipeline_class == oracle_class
                end
            end
        end
    end

    @testset "Pipeline classify with FiniteDiff eigenvalues" begin
        # The real pipeline uses FiniteDiff, not ForwardDiff
        # Test that FiniteDiff eigenvalues still lead to correct classification
        using FiniteDiff

        for bf in BENCHMARK_FUNCTIONS
            bf.name == "rastrigin_2d" && continue
            bf.name == "deuflhard_4d" && continue

            @testset "$(bf.name) FiniteDiff" begin
                df = load_ground_truth_df(bf.name, bf.dim)
                df === nothing && continue

                x_cols = [Symbol("x$i") for i in 1:bf.dim]
                n_disagree = 0
                n_total = 0

                for row in eachrow(df)
                    x = Float64[row[c] for c in x_cols]
                    oracle_class = string(row[:classification])

                    # Compute Hessian via FiniteDiff (as the pipeline does)
                    H_fd = FiniteDiff.finite_difference_hessian(bf.f, x)
                    ev_fd = sort(real.(eigvals(H_fd)))

                    # Pipeline classification of FiniteDiff eigenvalues
                    fd_class = classify_critical_point(ev_fd)

                    n_total += 1
                    if fd_class != oracle_class
                        n_disagree += 1
                    end
                end

                # Allow some disagreements (FiniteDiff noise can flip
                # near-degenerate eigenvalues) but not more than 10%
                if n_total > 0
                    disagree_rate = n_disagree / n_total
                    @test disagree_rate < 0.10
                end
            end
        end
    end

    @testset "Tolerance sensitivity: default vs relative_tol" begin
        # Test that relative_tol doesn't change classification for well-separated eigenvalues
        # NOTE: Rosenbrock excluded — Hessian condition number ~400 at [1,1] causes
        # relative_tol=0.01 to make eigenvalue 2.0 "degenerate" relative to 802.0
        for bf in [GroundTruthFunctions.SPHERE_2D, GroundTruthFunctions.HIMMELBLAU]
            @testset "$(bf.name)" begin
                df = load_ground_truth_df(bf.name, bf.dim)
                df === nothing && continue

                ev_cols = [Symbol("eigenvalue_$i") for i in 1:bf.dim]

                for row in eachrow(df)
                    eigenvalues = Float64[row[c] for c in ev_cols]

                    class_default = classify_critical_point(eigenvalues)
                    class_relative =
                        classify_critical_point(eigenvalues; relative_tol = 0.01)

                    # For well-conditioned functions, both should agree
                    @test class_default == class_relative
                end
            end
        end
    end

    @testset "Sub-classify degenerate" begin
        # Test sub_classify_degenerate option
        # Create eigenvalues that are degenerate (one near-zero) but with
        # remaining eigenvalues all positive → should sub-classify as degenerate_min
        ev_degen_min = [1e-8, 2.0, 3.0]
        @test classify_critical_point(ev_degen_min) == "degenerate"
        @test classify_critical_point(ev_degen_min; sub_classify_degenerate = true) ==
              "degenerate_min"

        ev_degen_max = [1e-8, -2.0, -3.0]
        @test classify_critical_point(ev_degen_max; sub_classify_degenerate = true) ==
              "degenerate_max"

        ev_degen_saddle = [1e-8, 2.0, -3.0]
        @test classify_critical_point(ev_degen_saddle; sub_classify_degenerate = true) ==
              "degenerate_saddle"
    end

    @testset "Classification counts match ground truth" begin
        # Verify the number of each type in the CSVs
        expected_counts = Dict(
            "sphere_2d" => Dict("minimum" => 1),
            "himmelblau" => Dict("minimum" => 4, "maximum" => 1, "saddle" => 4),
            "rosenbrock_2d" => Dict("minimum" => 1),
            "styblinski_tang_2d" => Dict("minimum" => 4, "maximum" => 1, "saddle" => 4),
            "rastrigin_2d" => Dict("minimum" => 121, "maximum" => 100, "saddle" => 220),
        )

        for (name, counts) in expected_counts
            @testset "$name counts" begin
                bf = first(filter(b -> b.name == name, BENCHMARK_FUNCTIONS))
                df = load_ground_truth_df(name, bf.dim)
                df === nothing && continue

                for (class, expected_n) in counts
                    actual_n =
                        count(row -> string(row[:classification]) == class, eachrow(df))
                    @test actual_n == expected_n
                end
            end
        end
    end
end

println("\n✓ All Level 3 classification correctness tests completed")
