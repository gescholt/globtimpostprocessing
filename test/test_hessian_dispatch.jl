"""
    test_hessian_dispatch.jl

Fast tests for Hessian classification dispatch correctness:
1. classify_refined_points works with callable structs (not just ::Function)
2. classify_refined_points works with :finitediff gradient_method
3. ForwardDiff and FiniteDiff Hessians produce consistent classifications

These tests verify the fix for the type dispatch bug where ODE-model objectives
(TolerantObjective, a callable struct) silently fell back to Symbol[] because the
GlobtimExt override was constrained to ::Function.

Run with:
    julia --project=profiles/dev -e 'include("pkg/globtimpostprocessing/test/test_hessian_dispatch.jl")'
"""

using Test
using LinearAlgebra
using GlobtimPostProcessing
using Globtim  # Required to activate GlobtimExt

# ── Test fixtures ──────────────────────────────────────────────────────────

# Generic callable struct — accepts any numeric vector (ForwardDiff-compatible)
struct GenericQuadratic
    A::Matrix{Float64}
    b::Vector{Float64}
end
(obj::GenericQuadratic)(x) = 0.5 * dot(x, obj.A * x) + dot(obj.b, x)

# Restricted callable struct — only accepts Float64 (like TolerantObjective / ODE models)
# ForwardDiff CANNOT propagate Dual numbers through this.
struct RestrictedQuadratic
    A::Matrix{Float64}
    b::Vector{Float64}
end
(obj::RestrictedQuadratic)(x::Vector{Float64}) = 0.5 * dot(x, obj.A * x) + dot(obj.b, x)

# Rosenbrock as a plain function (for comparison)
rosenbrock(x) = (1 - x[1])^2 + 100 * (x[2] - x[1]^2)^2

# Known critical points for testing
const ROSENBROCK_MIN = [[1.0, 1.0]]

# Positive definite → minimum at [1, 2]
const PD_A = Matrix{Float64}(I, 2, 2)
const PD_B = [-1.0, -2.0]
const PD_MIN = [[1.0, 2.0]]

# Indefinite → saddle at origin
const INDEF_A = Float64[1 0; 0 -1]
const INDEF_B = [0.0, 0.0]
const INDEF_SADDLE = [[0.0, 0.0]]

# Negative definite → maximum at origin
const ND_A = Float64[-2 0; 0 -3]
const ND_B = [0.0, 0.0]
const ND_MAX = [[0.0, 0.0]]

# ── Tests ──────────────────────────────────────────────────────────────────

@testset "Hessian Classification Dispatch" begin
    @testset "Function dispatch (baseline)" begin
        cls = GlobtimPostProcessing.classify_refined_points(rosenbrock, ROSENBROCK_MIN)
        @test !isempty(cls)
        @test cls[1] == :minimum
    end

    @testset "Generic callable struct (ForwardDiff-compatible)" begin
        # GenericQuadratic accepts any vector → ForwardDiff Dual numbers work
        obj_pd = GenericQuadratic(PD_A, PD_B)
        @test !(obj_pd isa Function)
        @test GlobtimPostProcessing._as_function(obj_pd) isa Function

        # ForwardDiff path (default)
        cls = GlobtimPostProcessing.classify_refined_points(
            GlobtimPostProcessing._as_function(obj_pd),
            PD_MIN,
        )
        @test !isempty(cls)
        @test cls[1] == :minimum

        # Saddle
        obj_indef = GenericQuadratic(INDEF_A, INDEF_B)
        cls = GlobtimPostProcessing.classify_refined_points(
            GlobtimPostProcessing._as_function(obj_indef),
            INDEF_SADDLE,
        )
        @test cls[1] == :saddle

        # Maximum
        obj_nd = GenericQuadratic(ND_A, ND_B)
        cls = GlobtimPostProcessing.classify_refined_points(
            GlobtimPostProcessing._as_function(obj_nd),
            ND_MAX,
        )
        @test cls[1] == :maximum
    end

    @testset "Restricted callable struct (ODE-like, FiniteDiff only)" begin
        # RestrictedQuadratic takes ::Vector{Float64} only → ForwardDiff fails.
        # This simulates TolerantObjective (ODE models).
        obj_pd = RestrictedQuadratic(PD_A, PD_B)
        @test !(obj_pd isa Function)

        # ForwardDiff path → Hessian computation fails, returns :error
        cls_ad = GlobtimPostProcessing.classify_refined_points(
            GlobtimPostProcessing._as_function(obj_pd),
            PD_MIN;
            gradient_method = :forwarddiff,
        )
        @test cls_ad[1] == :error  # Expected: ForwardDiff can't handle Float64-restricted callables

        # FiniteDiff path → works correctly (this is what ODE models must use)
        cls_fd = GlobtimPostProcessing.classify_refined_points(
            GlobtimPostProcessing._as_function(obj_pd),
            PD_MIN;
            gradient_method = :finitediff,
        )
        @test cls_fd[1] == :minimum

        # Saddle
        obj_indef = RestrictedQuadratic(INDEF_A, INDEF_B)
        cls = GlobtimPostProcessing.classify_refined_points(
            GlobtimPostProcessing._as_function(obj_indef),
            INDEF_SADDLE;
            gradient_method = :finitediff,
        )
        @test cls[1] == :saddle

        # Maximum
        obj_nd = RestrictedQuadratic(ND_A, ND_B)
        cls = GlobtimPostProcessing.classify_refined_points(
            GlobtimPostProcessing._as_function(obj_nd),
            ND_MAX;
            gradient_method = :finitediff,
        )
        @test cls[1] == :maximum
    end

    @testset "ForwardDiff vs FiniteDiff consistency" begin
        # For ForwardDiff-compatible functions, both methods should agree
        cls_ad = GlobtimPostProcessing.classify_refined_points(
            rosenbrock,
            ROSENBROCK_MIN;
            gradient_method = :forwarddiff,
        )
        cls_fd = GlobtimPostProcessing.classify_refined_points(
            rosenbrock,
            ROSENBROCK_MIN;
            gradient_method = :finitediff,
        )
        @test cls_ad == cls_fd
        @test cls_ad[1] == :minimum
    end

    @testset "Multiple points" begin
        obj = GenericQuadratic(PD_A, PD_B)
        points = [PD_MIN[1], PD_MIN[1]]  # same point twice
        cls = GlobtimPostProcessing.classify_refined_points(
            GlobtimPostProcessing._as_function(obj),
            points,
        )
        @test length(cls) == 2
        @test all(c -> c == :minimum, cls)
    end

    @testset "3D objective" begin
        A3 = Float64[3 0 0; 0 2 0; 0 0 1]
        obj3 = GenericQuadratic(A3, zeros(3))
        cls = GlobtimPostProcessing.classify_refined_points(
            GlobtimPostProcessing._as_function(obj3),
            [[0.0, 0.0, 0.0]],
        )
        @test cls[1] == :minimum

        cls_fd = GlobtimPostProcessing.classify_refined_points(
            GlobtimPostProcessing._as_function(obj3),
            [[0.0, 0.0, 0.0]];
            gradient_method = :finitediff,
        )
        @test cls_fd[1] == :minimum
    end

    @testset "_as_function identity for plain functions" begin
        @test GlobtimPostProcessing._as_function(rosenbrock) === rosenbrock
    end
end

println("\nAll Hessian dispatch tests passed!")
