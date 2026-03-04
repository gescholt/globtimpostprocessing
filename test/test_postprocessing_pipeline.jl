# Test suite for postprocess_experiment() pipeline
#
# Uses the existing Deuflhard 4D fixtures (critical_points_raw_deg_4.csv,
# critical_points_raw_deg_6.csv) with the deuflhard_4d_fixture test function.

using Test
using JSON
using Dates

using GlobtimPostProcessing:
    PostprocessingResult,
    postprocess_experiment,
    RefinedExperimentResult,
    KnownCriticalPoints,
    CaptureResult,
    CaptureVerdict,
    RefinementConfig,
    ode_refinement_config

# Test functions are loaded once in runtests.jl via include("fixtures/test_functions.jl")
# deuflhard_4d_fixture and deuflhard_2d are available here.

const FIXTURES_DIR = joinpath(@__DIR__, "fixtures")
const DEUFLHARD_BOUNDS = [(-1.2, 1.2), (-1.2, 1.2), (-1.2, 1.2), (-1.2, 1.2)]

@testset "postprocess_experiment — Deuflhard 4D fixtures" begin
    # Work in a temporary copy so we don't pollute the fixtures directory
    tmpdir = mktempdir()
    for f in readdir(FIXTURES_DIR)
        src = joinpath(FIXTURES_DIR, f)
        isfile(src) && cp(src, joinpath(tmpdir, f); force=true)
    end

    # Suppress output during tests
    io = IOBuffer()

    result = postprocess_experiment(
        tmpdir,
        deuflhard_4d_fixture;
        bounds = DEUFLHARD_BOUNDS,
        refinement_config = RefinementConfig(),  # default NelderMead, fast
        gradient_method = :forwarddiff,
        reference_goal = :critical_point,
        reference_accept_tol = 1e-1,   # relaxed for test speed
        save_summary = true,
        io = io,
    )

    @test result isa PostprocessingResult
    @test result.experiment_dir == tmpdir

    # Should discover degrees 4 and 6
    @test result.degrees == [4, 6]

    # Both degrees should have refinement results
    @test length(result.refinements) == 2
    @test haskey(result.refinements, 4)
    @test haskey(result.refinements, 6)
    @test result.refinements[4] isa RefinedExperimentResult
    @test result.refinements[6] isa RefinedExperimentResult

    # Refinement should have processed points
    @test result.refinements[4].n_raw > 0
    @test result.refinements[6].n_raw > 0

    # Per-degree refinement files should be saved
    @test isfile(joinpath(tmpdir, "critical_points_refined_deg_4.csv"))
    @test isfile(joinpath(tmpdir, "critical_points_refined_deg_6.csv"))
    @test isfile(joinpath(tmpdir, "refinement_summary_deg_4.json"))
    @test isfile(joinpath(tmpdir, "refinement_summary_deg_6.json"))
    @test isfile(joinpath(tmpdir, "refinement_comparison_deg_4.csv"))
    @test isfile(joinpath(tmpdir, "refinement_comparison_deg_6.csv"))

    # Reference CPs should be built (may be nothing if all refinements rejected,
    # but for Deuflhard 4D they should succeed)
    if result.known_cps !== nothing
        @test result.known_cps isa KnownCriticalPoints
        @test length(result.known_cps.points) > 0
        @test result.known_cps.domain_diameter > 0

        # Capture analysis should have entries for each degree
        @test length(result.degree_capture_results) == 2
        @test result.degree_capture_results[1][1] in [4, 6]  # degree
        @test result.degree_capture_results[1][2] isa CaptureResult

        # Verdict should exist
        @test result.verdict !== nothing
        @test result.verdict isa CaptureVerdict
        @test result.verdict.label in ["EXCELLENT", "GOOD", "POOR"]
        @test result.verdict.best_degree in [4, 6]
    end

    # Timestamp should be recent
    @test result.timestamp isa DateTime
    @test Dates.value(Dates.now() - result.timestamp) < 120_000  # within 2 minutes

    # Consolidated summary should be saved
    summary_path = joinpath(tmpdir, "postprocessing_summary.json")
    @test isfile(summary_path)

    # Validate JSON structure
    summary = JSON.parsefile(summary_path)
    @test summary["pipeline_version"] == "1.0.0"
    @test summary["degrees"] == [4, 6]
    @test haskey(summary, "refinement")
    @test haskey(summary["refinement"], "degree_4")
    @test haskey(summary["refinement"], "degree_6")
    @test summary["refinement"]["degree_4"]["n_raw"] > 0
    @test summary["refinement"]["degree_6"]["n_raw"] > 0

    if result.known_cps !== nothing
        @test summary["reference_critical_points"] !== nothing
        @test haskey(summary, "capture_analysis")
        @test haskey(summary, "verdict")
        @test summary["verdict"]["label"] in ["EXCELLENT", "GOOD", "POOR"]
    end
end

@testset "postprocess_experiment — error cases" begin
    # Non-existent directory
    @test_throws ErrorException postprocess_experiment(
        "/nonexistent/dir", x -> sum(x.^2);
        bounds = [(-1.0, 1.0)],
    )

    # Directory with no raw CP files
    tmpdir = mktempdir()
    @test_throws ErrorException postprocess_experiment(
        tmpdir, x -> sum(x.^2);
        bounds = [(-1.0, 1.0)],
    )
end

@testset "postprocess_experiment — save_summary=false" begin
    tmpdir = mktempdir()
    for f in readdir(FIXTURES_DIR)
        src = joinpath(FIXTURES_DIR, f)
        isfile(src) && cp(src, joinpath(tmpdir, f); force=true)
    end

    io = IOBuffer()
    result = postprocess_experiment(
        tmpdir,
        deuflhard_4d_fixture;
        bounds = DEUFLHARD_BOUNDS,
        gradient_method = :forwarddiff,
        reference_accept_tol = 1e-1,
        save_summary = false,
        io = io,
    )

    # Per-degree files should still be saved (by refine_experiment_results)
    @test isfile(joinpath(tmpdir, "critical_points_refined_deg_4.csv"))

    # But consolidated summary should NOT be saved
    @test !isfile(joinpath(tmpdir, "postprocessing_summary.json"))
end

@testset "PostprocessingResult struct fields" begin
    tmpdir = mktempdir()
    for f in readdir(FIXTURES_DIR)
        src = joinpath(FIXTURES_DIR, f)
        isfile(src) && cp(src, joinpath(tmpdir, f); force=true)
    end

    io = IOBuffer()
    result = postprocess_experiment(
        tmpdir,
        deuflhard_4d_fixture;
        bounds = DEUFLHARD_BOUNDS,
        gradient_method = :forwarddiff,
        reference_accept_tol = 1e-1,
        io = io,
    )

    @test result.experiment_dir isa String
    @test result.degrees isa Vector{Int}
    @test result.refinements isa Dict{Int, RefinedExperimentResult}
    @test result.degree_capture_results isa Vector{Tuple{Int, CaptureResult}}
    @test result.timestamp isa DateTime
end
