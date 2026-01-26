"""
Unit tests for subdivision comparison functionality.

Tests the matching, DataFrame preparation, and comparison logic using mock data.
"""

using Test
using DataFrames
using Statistics
using Printf
using GlobtimPostProcessing
using GlobtimPostProcessing.LV4DAnalysis
using GlobtimPostProcessing.LV4DAnalysis: UnifiedPipeline, ExperimentParams

# ============================================================================
# Mock Data Construction
# ============================================================================

"""
Create a mock LV4DExperimentData struct for testing.
"""
function create_mock_experiment(;
    GN::Int=12,
    degree::Int=8,
    domain::Float64=0.08,
    seed::Int=1,
    is_subdivision::Bool=false,
    L2_norm::Float64=1e3,
    critical_points::Int=10,
    recovery_error::Float64=0.05,
    gradient_valid_rate::Float64=0.8,
    hessian_minima::Int=2,
    computation_time::Float64=60.0
)
    # Build ExperimentParams
    params = ExperimentParams(GN, degree, degree, domain, seed, is_subdivision)

    # Build degree results DataFrame
    degree_results = DataFrame(
        domain = [domain],
        degree = [degree],
        seed = [seed],
        GN = [GN],
        is_subdivision = [is_subdivision],
        L2_norm = [L2_norm],
        condition_number = [1e5],
        critical_points = [critical_points],
        gradient_valid_rate = [gradient_valid_rate],
        gradient_valid_count = [Int(round(critical_points * gradient_valid_rate))],
        mean_gradient_norm = [1e-4],
        min_gradient_norm = [1e-6],
        recovery_error = [recovery_error],
        hessian_minima = [hessian_minima],
        hessian_saddle = [critical_points - hessian_minima],
        hessian_degenerate = [0],
        computation_time = [computation_time],
        experiment_dir = ["mock_experiment"]
    )

    # Build BaseExperimentData
    method_str = is_subdivision ? "_subdivision" : ""
    exp_id = "lv4d$(method_str)_GN$(GN)_deg$(degree)_dom$(@sprintf("%.2e", domain))_seed$(seed)_mock"

    base = UnifiedPipeline.BaseExperimentData(
        exp_id,
        "/mock/path/$exp_id",
        LV4D,
        Dict{String,Any}(
            "p_true" => [0.2, 0.3, 0.5, 0.6],
            "p_center" => [0.2, 0.3, 0.5, 0.6],
            "sample_range" => domain
        ),
        degree_results,
        nothing  # critical_points
    )

    return LV4DExperimentData(
        base,
        params,
        [0.2, 0.3, 0.5, 0.6],  # p_true
        [0.2, 0.3, 0.5, 0.6],  # p_center
        domain,
        4  # dim
    )
end

# ============================================================================
# Tests
# ============================================================================

@testset "Subdivision Comparison Tests" begin

    @testset "find_matched_subdivision_pairs" begin
        # Create a set of experiments with some matching pairs
        experiments = LV4DExperimentData[]

        # Matched pair 1: GN=12, deg=8, dom=0.08, seed=1
        push!(experiments, create_mock_experiment(GN=12, degree=8, domain=0.08, seed=1, is_subdivision=false, L2_norm=1000.0))
        push!(experiments, create_mock_experiment(GN=12, degree=8, domain=0.08, seed=1, is_subdivision=true, L2_norm=800.0))

        # Matched pair 2: GN=12, deg=8, dom=0.08, seed=2
        push!(experiments, create_mock_experiment(GN=12, degree=8, domain=0.08, seed=2, is_subdivision=false, L2_norm=1100.0))
        push!(experiments, create_mock_experiment(GN=12, degree=8, domain=0.08, seed=2, is_subdivision=true, L2_norm=900.0))

        # Unmatched single (no subdivision counterpart)
        push!(experiments, create_mock_experiment(GN=12, degree=10, domain=0.08, seed=1, is_subdivision=false))

        # Unmatched subdivision (no single counterpart)
        push!(experiments, create_mock_experiment(GN=16, degree=8, domain=0.08, seed=1, is_subdivision=true))

        matched = find_matched_subdivision_pairs(experiments)

        @test length(matched) == 2
        @test haskey(matched, (12, 8, 0.08, 1))
        @test haskey(matched, (12, 8, 0.08, 2))
        @test !haskey(matched, (12, 10, 0.08, 1))  # Unmatched single
        @test !haskey(matched, (16, 8, 0.08, 1))   # Unmatched subdiv

        # Verify pair structure
        pair1 = matched[(12, 8, 0.08, 1)]
        @test !pair1[1].params.is_subdivision  # First is single
        @test pair1[2].params.is_subdivision   # Second is subdivision
    end

    @testset "prepare_subdivision_comparison_df" begin
        experiments = LV4DExperimentData[]

        # Create matched pair with known values
        push!(experiments, create_mock_experiment(
            GN=12, degree=8, domain=0.08, seed=1, is_subdivision=false,
            L2_norm=1000.0, recovery_error=0.05, critical_points=10, hessian_minima=3
        ))
        push!(experiments, create_mock_experiment(
            GN=12, degree=8, domain=0.08, seed=1, is_subdivision=true,
            L2_norm=800.0, recovery_error=0.03, critical_points=15, hessian_minima=5
        ))

        matched = find_matched_subdivision_pairs(experiments)
        df = prepare_subdivision_comparison_df(matched)

        @test nrow(df) == 2
        @test Set(df.method) == Set(["single", "subdivision"])

        single_row = first(filter(r -> r.method == "single", eachrow(df)))
        subdiv_row = first(filter(r -> r.method == "subdivision", eachrow(df)))

        @test single_row.L2_norm == 1000.0
        @test subdiv_row.L2_norm == 800.0
        @test single_row.recovery_error == 0.05
        @test subdiv_row.recovery_error == 0.03
        @test single_row.critical_points == 10
        @test subdiv_row.critical_points == 15
        @test single_row.hessian_minima == 3
        @test subdiv_row.hessian_minima == 5
    end

    @testset "prepare_subdivision_comparison_df schema" begin
        experiments = LV4DExperimentData[]
        push!(experiments, create_mock_experiment(is_subdivision=false))
        push!(experiments, create_mock_experiment(is_subdivision=true))

        matched = find_matched_subdivision_pairs(experiments)
        df = prepare_subdivision_comparison_df(matched)

        # Verify expected columns exist
        expected_cols = [:GN, :degree, :domain, :seed, :method,
                        :L2_norm, :critical_points, :recovery_error,
                        :gradient_valid_rate, :hessian_minima, :computation_time]

        for col in expected_cols
            @test hasproperty(df, col)
        end
    end

    @testset "print_subdivision_comparison formatting" begin
        experiments = LV4DExperimentData[]

        # Multiple seeds to test aggregation
        for seed in 1:3
            push!(experiments, create_mock_experiment(
                seed=seed, is_subdivision=false,
                L2_norm=1000.0 + seed * 100, recovery_error=0.05 + seed * 0.01
            ))
            push!(experiments, create_mock_experiment(
                seed=seed, is_subdivision=true,
                L2_norm=800.0 + seed * 50, recovery_error=0.03 + seed * 0.005
            ))
        end

        matched = find_matched_subdivision_pairs(experiments)
        df = prepare_subdivision_comparison_df(matched)

        # Capture output to IOBuffer
        buf = IOBuffer()
        print_subdivision_comparison(df; io=buf, show_aggregated=true)
        output = String(take!(buf))

        # Verify key elements are present
        @test occursin("Per-Configuration Results:", output)
        @test occursin("Single L2", output)
        @test occursin("Subdiv L2", output)
        @test occursin("Aggregated", output)  # Because multiple seeds
    end

    @testset "compare_single_vs_subdivision with filters" begin
        # This test verifies the filtering logic works
        # (actual file loading is tested separately)

        experiments = LV4DExperimentData[]

        # GN=12 experiments
        push!(experiments, create_mock_experiment(GN=12, degree=8, domain=0.08, seed=1, is_subdivision=false))
        push!(experiments, create_mock_experiment(GN=12, degree=8, domain=0.08, seed=1, is_subdivision=true))

        # GN=16 experiments
        push!(experiments, create_mock_experiment(GN=16, degree=8, domain=0.08, seed=1, is_subdivision=false))
        push!(experiments, create_mock_experiment(GN=16, degree=8, domain=0.08, seed=1, is_subdivision=true))

        # Test GN filter
        gn12_exps = filter(e -> e.params.GN == 12, experiments)
        @test length(gn12_exps) == 2

        matched_12 = find_matched_subdivision_pairs(gn12_exps)
        @test length(matched_12) == 1
        @test haskey(matched_12, (12, 8, 0.08, 1))
    end

    @testset "empty experiment handling" begin
        # No experiments
        empty_experiments = LV4DExperimentData[]
        matched = find_matched_subdivision_pairs(empty_experiments)
        @test isempty(matched)

        df = prepare_subdivision_comparison_df(matched)
        @test isempty(df)

        # Print should handle empty gracefully
        buf = IOBuffer()
        print_subdivision_comparison(df; io=buf)
        output = String(take!(buf))
        @test occursin("No matched pairs", output)
    end

    @testset "single-only experiments (no matches)" begin
        experiments = LV4DExperimentData[]
        push!(experiments, create_mock_experiment(GN=12, is_subdivision=false))
        push!(experiments, create_mock_experiment(GN=16, is_subdivision=false))

        matched = find_matched_subdivision_pairs(experiments)
        @test isempty(matched)
    end

    @testset "subdivision-only experiments (no matches)" begin
        experiments = LV4DExperimentData[]
        push!(experiments, create_mock_experiment(GN=12, is_subdivision=true))
        push!(experiments, create_mock_experiment(GN=16, is_subdivision=true))

        matched = find_matched_subdivision_pairs(experiments)
        @test isempty(matched)
    end

end

# Run tests when executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    using Test
    @testset "All Subdivision Comparison Tests" begin
        include(@__FILE__)
    end
end
