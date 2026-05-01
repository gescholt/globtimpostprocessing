# test_landscape_capture_types.jl
# Tests for LandscapeRefinementDetails, LandscapeMethodResult,
# LandscapeSubdivisionData, and their JSON loaders.

using GlobtimPostProcessing
using Test

const FIXTURE_DIR = joinpath(@__DIR__, "fixtures")

@testset "LandscapeRefinementDetails" begin
    @testset "parse_landscape_refinement" begin
        d = Dict{String,Any}(
            "raw_points" => [[0.1, 0.2], [0.3, 0.4]],
            "refined_points" => [[0.11, 0.21], [0.31, 0.41]],
            "converged" => [true, false],
            "cp_types" => ["min", "unknown"],
            "gradient_norms" => [1e-10, nothing],
            "objective_values" => [0.001, nothing],
            "iterations" => [5, 50],
        )
        ref = parse_landscape_refinement(d)

        @test ref isa LandscapeRefinementDetails
        @test length(ref.raw_points) == 2
        @test length(ref.refined_points) == 2
        @test ref.raw_points[1] ≈ [0.1, 0.2]
        @test ref.refined_points[2] ≈ [0.31, 0.41]
        @test ref.converged == [true, false]
        @test ref.cp_types == ["min", "unknown"]
        @test ref.gradient_norms[1] ≈ 1e-10
        @test isnan(ref.gradient_norms[2])
        @test ref.objective_values[1] ≈ 0.001
        @test isnan(ref.objective_values[2])
        @test ref.iterations == [5, 50]
    end

    @testset "parse_landscape_refinement missing key" begin
        d = Dict{String,Any}(
            "raw_points" => [[0.1, 0.2]],
            "refined_points" => [[0.11, 0.21]],
            # Missing converged, cp_types, etc.
        )
        @test_throws ErrorException parse_landscape_refinement(d)
    end
end

@testset "load_landscape_degree_sweep" begin
    path = joinpath(FIXTURE_DIR, "landscape_degree_sweep.json")

    @testset "basic loading" begin
        sweep = load_landscape_degree_sweep(path)

        @test sweep.problem == "test_2d"
        @test length(sweep.bounds) == 2
        @test sweep.bounds[1] ≈ [0.0, 1.0]
        @test sweep.p_true ≈ [0.5, 0.5]
    end

    @testset "methods parsed correctly" begin
        sweep = load_landscape_degree_sweep(path)

        @test length(sweep.methods) == 2  # deg 4 and 6 (deg 20 crashed)
        @test length(sweep.crashed_degrees) == 1
        @test sweep.crashed_degrees[1] == 20
    end

    @testset "degree 4 method" begin
        sweep = load_landscape_degree_sweep(path)
        m = sweep.methods[1]

        @test m isa LandscapeMethodResult
        @test m.label == "deg 4"
        @test m.degree == 4
        @test m.n_min == 1
        @test m.n_saddle == 1
        @test m.n_max == 0
        @test m.n_verified == 2
        @test length(m.cp_points) == 2
        @test m.cp_points[1] ≈ [0.48, 0.52]
        @test length(m.cp_values) == 2
        @test m.cp_values[1] ≈ 0.001
        @test m.cp_types == ["min", "saddle"]
        @test m.best_objective ≈ 0.001
        @test m.is_subdivision == false
    end

    @testset "degree 4 refinement details" begin
        sweep = load_landscape_degree_sweep(path)
        m = sweep.methods[1]

        @test m.refinement !== nothing
        ref = m.refinement
        @test ref isa LandscapeRefinementDetails
        @test length(ref.raw_points) == 2
        @test ref.raw_points[1] ≈ [0.47, 0.53]
        @test ref.refined_points[1] ≈ [0.48, 0.52]
        @test ref.converged == [true, true]
        @test ref.iterations == [5, 8]
    end

    @testset "degree 6 without refinement" begin
        sweep = load_landscape_degree_sweep(path)
        m = sweep.methods[2]

        @test m.label == "deg 6"
        @test m.degree == 6
        @test m.n_min == 2
        @test m.n_max == 1
        @test m.best_objective ≈ 0.0001
        @test m.refinement === nothing
    end

    @testset "validation errors" begin
        @test_throws ErrorException load_landscape_degree_sweep("nonexistent.json")
        @test_throws ErrorException load_landscape_degree_sweep(
            joinpath(FIXTURE_DIR, "landscape_subdivision.json"),
        )  # wrong structure (no 'degrees' key)
    end
end

@testset "load_landscape_subdivision" begin
    path = joinpath(FIXTURE_DIR, "landscape_subdivision.json")

    @testset "method result" begin
        result = load_landscape_subdivision(path)
        m = result.method

        @test m isa LandscapeMethodResult
        @test m.label == "subdiv 4→8"
        @test m.degree == 4
        @test m.n_min == 1
        @test m.n_saddle == 1
        @test m.n_max == 0
        @test m.n_verified == 2
        @test length(m.cp_points) == 2
        @test m.cp_points[1] ≈ [0.49, 0.51]
        @test m.cp_values ≈ [0.0005, 0.3]
        @test m.cp_types == ["min", "saddle"]
        @test m.best_objective ≈ 0.0005
        @test m.is_subdivision == true
    end

    @testset "refinement details" begin
        result = load_landscape_subdivision(path)
        ref = result.method.refinement

        @test ref !== nothing
        @test ref isa LandscapeRefinementDetails
        @test length(ref.raw_points) == 5
        @test ref.converged == [true, true, true, false, true]
        @test ref.cp_types == ["min", "saddle", "unknown", "unknown", "unknown"]
        @test isnan(ref.gradient_norms[4])  # null → NaN
        @test isnan(ref.objective_values[4])
        @test ref.iterations == [6, 10, 15, 50, 12]
    end

    @testset "subdivision data" begin
        result = load_landscape_subdivision(path)
        sd = result.subdiv_data

        @test sd isa LandscapeSubdivisionData
        @test sd.n_leaves == 3
        @test sd.degree == 4
        @test sd.max_degree == 8
        @test sd.label == "subdiv 4→8"
        @test length(sd.leaf_bounds) == 3
        @test sd.leaf_bounds[1][1] ≈ [0.0, 0.5]
        @test sd.leaf_bounds[1][2] ≈ [0.0, 0.5]
        @test length(sd.leaf_l2_errors) == 3
        @test sd.leaf_l2_errors[1] ≈ 0.00005
    end

    @testset "minimal subdivision (no refinement, no CPs)" begin
        path_min = joinpath(FIXTURE_DIR, "landscape_subdivision_minimal.json")
        result = load_landscape_subdivision(path_min)
        m = result.method
        sd = result.subdiv_data

        @test m.label == "subdiv deg 6"  # max_degree == degree → no bump
        @test m.degree == 6
        @test m.n_min == 0
        @test m.n_verified == 0
        @test isempty(m.cp_points)
        @test m.best_objective === nothing
        @test m.refinement === nothing
        @test m.is_subdivision == true

        @test sd.n_leaves == 2
        @test sd.degree == 6
        @test sd.max_degree == 6
        @test isempty(sd.leaf_bounds)
        @test isempty(sd.leaf_l2_errors)
    end

    @testset "validation errors" begin
        @test_throws ErrorException load_landscape_subdivision("nonexistent.json")
    end
end

@testset "load real sandbox data" begin
    # Test against actual experiment data if available
    sweep_path = joinpath(
        @__DIR__,
        "..",
        "..",
        "experiments",
        "sandbox",
        "results",
        "lv2d_sciml_degree_sweep.json",
    )
    subdiv_path = joinpath(
        @__DIR__,
        "..",
        "..",
        "experiments",
        "sandbox",
        "results",
        "lv2d_sciml_deg4to8_tol0.0001_d5_aniso.json",
    )

    if isfile(sweep_path)
        @testset "real degree sweep" begin
            sweep = load_landscape_degree_sweep(sweep_path)
            @test sweep.problem == "lv2d_sciml"
            @test length(sweep.bounds) == 2
            @test length(sweep.p_true) == 2
            @test !isempty(sweep.methods)
            for m in sweep.methods
                @test m isa LandscapeMethodResult
                @test m.degree > 0
                @test m.is_subdivision == false
            end
        end
    end

    if isfile(subdiv_path)
        @testset "real subdivision result" begin
            result = load_landscape_subdivision(subdiv_path)
            @test result.method isa LandscapeMethodResult
            @test result.method.is_subdivision == true
            @test result.subdiv_data isa LandscapeSubdivisionData
            @test result.subdiv_data.n_leaves > 0
        end
    end
end
