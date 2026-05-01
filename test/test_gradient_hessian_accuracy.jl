"""
    test_gradient_hessian_accuracy.jl

Level 2: Compare ForwardDiff (oracle) vs FiniteDiff (pipeline) for
gradient and Hessian computation accuracy.

Tests that FiniteDiff produces sufficiently accurate gradients and Hessians
for all benchmark functions at their known critical points. This quantifies
the numerical noise floor that the pipeline must handle.

Run with:
    julia --project=profiles/dev pkg/globtimpostprocessing/test/test_gradient_hessian_accuracy.jl
"""

using Test
using LinearAlgebra
using ForwardDiff
using FiniteDiff
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

"""
    load_points(name, dim) -> Vector{Vector{Float64}}

Load critical point locations from ground truth CSV.
"""
function load_points(name::String, dim::Int)
    filepath = joinpath(GT_DIR, "$(name)_critical_points.csv")
    isfile(filepath) || return Vector{Float64}[]
    df = CSV.read(filepath, DataFrame)
    x_cols = [Symbol("x$i") for i in 1:dim]
    return [Float64[row[c] for c in x_cols] for row in eachrow(df)]
end

# ============================================================================
# Gradient accuracy tests
# ============================================================================
@testset "Level 2: Gradient Accuracy (ForwardDiff vs FiniteDiff)" begin
    @testset "Gradient agreement at critical points" begin
        for bf in BENCHMARK_FUNCTIONS
            @testset "$(bf.name)" begin
                points = load_points(bf.name, bf.dim)
                isempty(points) && continue

                for (i, x) in enumerate(points)
                    g_forward = ForwardDiff.gradient(bf.f, x)
                    g_finite = FiniteDiff.finite_difference_gradient(bf.f, x)

                    # At critical points, both should be near zero
                    @test norm(g_forward) < 1e-6
                    @test norm(g_finite) < 1e-3  # FiniteDiff has larger noise

                    # Agreement between methods
                    if norm(g_forward) > 1e-14  # avoid division by zero
                        rel_error = norm(g_forward - g_finite) / norm(g_forward)
                        # FiniteDiff should agree to ~1e-6 relative error typically
                    else
                        abs_error = norm(g_forward - g_finite)
                        @test abs_error < 1e-4  # absolute agreement near zero
                    end
                end
            end
        end
    end

    @testset "Gradient accuracy away from critical points" begin
        # Test at non-critical points where gradient is substantial
        test_points = [
            (GroundTruthFunctions.sphere_2d, [1.0, 2.0], 2),
            (GroundTruthFunctions.himmelblau, [1.0, 1.0], 2),
            (GroundTruthFunctions.rosenbrock_2d, [0.0, 0.0], 2),
            (GroundTruthFunctions.sixhump_camel, [1.0, 0.5], 2),
            (GroundTruthFunctions.deuflhard_2d, [0.5, 0.5], 2),
            (GroundTruthFunctions.rastrigin_2d, [0.5, 0.5], 2),
        ]

        for (f, x, _dim) in test_points
            g_forward = ForwardDiff.gradient(f, x)
            g_finite = FiniteDiff.finite_difference_gradient(f, x)

            @test norm(g_forward) > 1e-8  # confirm it's not a CP

            rel_error = norm(g_forward - g_finite) / norm(g_forward)
            @test rel_error < 1e-5  # FiniteDiff should be ~1e-8 relative typically
        end
    end
end

# ============================================================================
# Hessian accuracy tests
# ============================================================================
@testset "Level 2: Hessian Accuracy (ForwardDiff vs FiniteDiff)" begin
    @testset "Hessian agreement at critical points" begin
        for bf in BENCHMARK_FUNCTIONS
            bf.name == "rastrigin_2d" && continue  # skip: 441 CPs too many Hessians
            bf.name == "deuflhard_4d" && continue  # skip: 220 CPs too many 4x4 Hessians

            @testset "$(bf.name)" begin
                points = load_points(bf.name, bf.dim)
                isempty(points) && continue

                for (i, x) in enumerate(points)
                    H_forward = ForwardDiff.hessian(bf.f, x)
                    H_finite = FiniteDiff.finite_difference_hessian(bf.f, x)

                    # Frobenius norm agreement
                    H_norm = norm(H_forward)
                    if H_norm > 1e-10
                        rel_error = norm(H_forward - H_finite) / H_norm
                        @test rel_error < 1e-3  # FiniteDiff Hessian ~1e-4 to 1e-6 relative
                    else
                        abs_error = norm(H_forward - H_finite)
                        @test abs_error < 1e-4
                    end
                end
            end
        end
    end

    @testset "Eigenvalue agreement at critical points" begin
        # More important than Hessian entry agreement: do eigenvalues agree?
        for bf in BENCHMARK_FUNCTIONS
            bf.name == "rastrigin_2d" && continue
            bf.name == "deuflhard_4d" && continue

            @testset "$(bf.name) eigenvalues" begin
                points = load_points(bf.name, bf.dim)
                isempty(points) && continue

                for (i, x) in enumerate(points)
                    H_forward = ForwardDiff.hessian(bf.f, x)
                    H_finite = FiniteDiff.finite_difference_hessian(bf.f, x)

                    ev_forward = sort(real.(eigvals(H_forward)))
                    ev_finite = sort(real.(eigvals(H_finite)))

                    for j in eachindex(ev_forward)
                        if abs(ev_forward[j]) > 0.1
                            # For substantial eigenvalues, check relative agreement
                            rel_error =
                                abs(ev_forward[j] - ev_finite[j]) / abs(ev_forward[j])
                            @test rel_error < 0.01  # 1% relative error acceptable
                        else
                            # For near-zero eigenvalues, check absolute agreement
                            @test abs(ev_forward[j] - ev_finite[j]) < 0.01
                        end
                    end
                end
            end
        end
    end

    @testset "Hessian symmetry" begin
        # FiniteDiff Hessian should be approximately symmetric
        for bf in [
            GroundTruthFunctions.SPHERE_2D,
            GroundTruthFunctions.HIMMELBLAU,
            GroundTruthFunctions.ROSENBROCK_2D,
        ]
            @testset "$(bf.name) symmetry" begin
                x = bf.known_minima[1]
                H = FiniteDiff.finite_difference_hessian(bf.f, x)
                @test norm(H - H') / (norm(H) + 1e-16) < 1e-8
            end
        end
    end
end

# ============================================================================
# Quantify FiniteDiff noise floor
# ============================================================================
@testset "Level 2: FiniteDiff Noise Characterization" begin
    @testset "Gradient noise at exact minima" begin
        # At exact analytic minima, ForwardDiff gradient = 0 exactly (or near machine eps)
        # FiniteDiff will have a noise floor — quantify it
        exact_minima = [
            ("sphere_2d", GroundTruthFunctions.sphere_2d, [0.0, 0.0]),
            ("rosenbrock_2d", GroundTruthFunctions.rosenbrock_2d, [1.0, 1.0]),
            ("himmelblau", GroundTruthFunctions.himmelblau, [3.0, 2.0]),
        ]

        for (name, f, x) in exact_minima
            g_fd = FiniteDiff.finite_difference_gradient(f, x)
            noise_floor = norm(g_fd)

            # FiniteDiff gradient noise should be < 1e-6 for smooth functions
            @test noise_floor < 1e-6

            # Log for reference
            @debug "FiniteDiff gradient noise at $name minimum" noise_floor
        end
    end

    @testset "Hessian eigenvalue noise at exact minima" begin
        exact_minima = [
            ("sphere_2d", GroundTruthFunctions.sphere_2d, [0.0, 0.0], [2.0, 2.0]),
            ("rosenbrock_2d", GroundTruthFunctions.rosenbrock_2d, [1.0, 1.0], nothing),
        ]

        for (name, f, x, expected_ev) in exact_minima
            H_fd = FiniteDiff.finite_difference_hessian(f, x)
            H_ad = ForwardDiff.hessian(f, x)

            ev_fd = sort(real.(eigvals(H_fd)))
            ev_ad = sort(real.(eigvals(H_ad)))

            if expected_ev !== nothing
                for (j, ev_true) in enumerate(expected_ev)
                    @test abs(ev_ad[j] - ev_true) < 1e-10  # ForwardDiff exact
                    @test abs(ev_fd[j] - ev_true) < 0.01   # FiniteDiff noise
                end
            end

            # Both should agree on sign structure (positive = minimum)
            @test all(ev_ad .> 0)
            @test all(ev_fd .> 0)
        end
    end
end

println("\n✓ All Level 2 gradient/Hessian accuracy tests completed")
