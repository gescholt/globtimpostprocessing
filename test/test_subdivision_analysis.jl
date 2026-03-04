# Test suite for SubdivisionTreeAnalysis.jl
# Uses duck-typed mock objects to avoid Globtim dependency

using Test
using DataFrames
using Statistics

# Import the module under test
using GlobtimPostProcessing:
    SubdivisionTreeStats,
    analyze_subdivision_tree,
    tree_leaves_to_dataframe,
    tree_depth_summary,
    print_subdivision_tree_report,
    compare_subdivision_trees,
    print_tree_comparison_table,
    SubdivisionResult,
    load_subdivision_result

#==============================================================================#
#                    MOCK OBJECTS (DUCK TYPING)                                #
#==============================================================================#

"""
Mock Subdomain - matches interface expected by SubdivisionTreeAnalysis.
Must have: center, half_widths, depth, l2_error
"""
struct MockSubdomain
    center::Vector{Float64}
    half_widths::Vector{Float64}
    depth::Int
    l2_error::Float64
end

"""
Mock Tree - matches interface expected by SubdivisionTreeAnalysis.
Must have: subdomains, converged_leaves, active_leaves
"""
struct MockTree
    subdomains::Vector{MockSubdomain}
    converged_leaves::Vector{Int}
    active_leaves::Vector{Int}
end

"""
Create a simple test tree with 5 subdomains (3 converged, 2 active).
2D problem with varying depths and L2 errors.
"""
function create_simple_test_tree()
    subdomains = [
        MockSubdomain([0.25, 0.25], [0.25, 0.25], 1, 1e-4),  # id=1, converged
        MockSubdomain([0.75, 0.25], [0.25, 0.25], 1, 1e-5),  # id=2, converged
        MockSubdomain([0.25, 0.75], [0.25, 0.25], 1, 1e-3),  # id=3, active
        MockSubdomain([0.625, 0.625], [0.125, 0.125], 2, 1e-6),  # id=4, converged
        MockSubdomain([0.875, 0.875], [0.125, 0.125], 2, 1e-2),  # id=5, active
    ]
    converged_leaves = [1, 2, 4]
    active_leaves = [3, 5]
    return MockTree(subdomains, converged_leaves, active_leaves)
end

"""
Create a 4D test tree for dimension checking.
"""
function create_4d_test_tree()
    subdomains = [
        MockSubdomain([0.5, 0.5, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5], 0, 1e-3),
        MockSubdomain([0.25, 0.25, 0.25, 0.25], [0.25, 0.25, 0.25, 0.25], 1, 1e-5),
    ]
    return MockTree(subdomains, [1, 2], Int[])
end

#==============================================================================#
#                    TEST SUITES                                               #
#==============================================================================#

@testset "analyze_subdivision_tree" begin
    tree = create_simple_test_tree()
    stats = analyze_subdivision_tree(tree)

    @test stats isa SubdivisionTreeStats

    # Leaf counts
    @test stats.n_leaves == 5
    @test stats.n_converged == 3
    @test stats.n_active == 2

    # Dimension
    @test stats.dimension == 2

    # Convergence rate
    @test stats.convergence_rate ≈ 3/5 atol=1e-10

    # Depth statistics
    @test stats.max_depth == 2
    @test stats.mean_depth ≈ (1 + 1 + 1 + 2 + 2) / 5  # 1.4

    # Error statistics
    errors = [1e-4, 1e-5, 1e-3, 1e-6, 1e-2]
    @test stats.total_l2_error ≈ sum(errors)
    @test stats.mean_l2_error ≈ mean(errors)
    @test stats.min_l2_error ≈ minimum(errors)
    @test stats.max_l2_error ≈ maximum(errors)
    @test stats.median_l2_error ≈ median(errors)

    # Quantiles exist
    @test haskey(stats.error_quantiles, :q10)
    @test haskey(stats.error_quantiles, :q50)
    @test haskey(stats.error_quantiles, :q90)

    # Depth distribution
    @test stats.depth_distribution[1] == 3  # 3 leaves at depth 1
    @test stats.depth_distribution[2] == 2  # 2 leaves at depth 2
end

@testset "tree_leaves_to_dataframe" begin
    tree = create_simple_test_tree()
    df = tree_leaves_to_dataframe(tree)

    @test df isa DataFrame
    @test nrow(df) == 5

    # Required columns
    @test :id in propertynames(df)
    @test :depth in propertynames(df)
    @test :l2_error in propertynames(df)
    @test :status in propertynames(df)
    @test :volume in propertynames(df)

    # Dimension-specific columns (2D)
    @test :center_1 in propertynames(df)
    @test :center_2 in propertynames(df)
    @test :width_1 in propertynames(df)
    @test :width_2 in propertynames(df)

    # Status values
    @test sum(df.status .== "converged") == 3
    @test sum(df.status .== "active") == 2

    # Volume calculation: prod(2 .* half_widths)
    # For depth=1 subdomain: 2*0.25 * 2*0.25 = 0.25
    depth1_rows = filter(row -> row.depth == 1, df)
    @test all(v -> v ≈ 0.25, depth1_rows.volume)
end

@testset "tree_depth_summary" begin
    tree = create_simple_test_tree()
    df = tree_depth_summary(tree)

    @test df isa DataFrame
    @test nrow(df) == 2  # depths 1 and 2

    # Required columns
    @test :depth in propertynames(df)
    @test :n_leaves in propertynames(df)
    @test :n_converged in propertynames(df)
    @test :mean_l2_error in propertynames(df)

    # Verify row counts match depth distribution
    @test sum(df.n_leaves) == 5

    depth1_row = first(filter(row -> row.depth == 1, df))
    @test depth1_row.n_leaves == 3
    @test depth1_row.n_converged == 2  # ids 1, 2 are converged at depth 1

    depth2_row = first(filter(row -> row.depth == 2, df))
    @test depth2_row.n_leaves == 2
    @test depth2_row.n_converged == 1  # id 4 is converged at depth 2
end

@testset "print_subdivision_tree_report" begin
    tree = create_simple_test_tree()

    # Capture output to buffer
    io = IOBuffer()
    print_subdivision_tree_report(tree; io=io)
    output = String(take!(io))

    # Check key sections present
    @test occursin("SUBDIVISION", uppercase(output))
    @test occursin("L2", uppercase(output))
    @test occursin("STRUCTURE", uppercase(output))
    @test occursin("DEPTH", uppercase(output))

    # Check some statistics appear
    @test occursin("5", output)  # n_leaves
    @test occursin("3", output)  # n_converged
    @test occursin("2", output)  # dimension
end

@testset "compare_subdivision_trees" begin
    tree1 = create_simple_test_tree()
    tree2 = create_4d_test_tree()

    df = compare_subdivision_trees([tree1, tree2]; labels=["SimpleTree", "4DTree"])

    @test df isa DataFrame
    @test nrow(df) == 2

    # Required columns
    @test :label in propertynames(df)
    @test :n_leaves in propertynames(df)
    @test :n_converged in propertynames(df)
    @test :convergence_rate in propertynames(df)
    @test :max_depth in propertynames(df)
    @test :mean_l2_error in propertynames(df)
    @test :total_l2_error in propertynames(df)
    @test :dimension in propertynames(df)

    # Labels preserved
    @test "SimpleTree" in df.label
    @test "4DTree" in df.label

    # Dimensions correct
    simple_row = first(filter(row -> row.label == "SimpleTree", df))
    @test simple_row.dimension == 2
    @test simple_row.n_leaves == 5

    fourd_row = first(filter(row -> row.label == "4DTree", df))
    @test fourd_row.dimension == 4
    @test fourd_row.n_leaves == 2
end

@testset "print_tree_comparison_table" begin
    tree1 = create_simple_test_tree()
    tree2 = create_4d_test_tree()

    # Capture output to buffer
    io = IOBuffer()
    print_tree_comparison_table([tree1, tree2]; labels=["Tree1", "Tree2"], io=io)
    output = String(take!(io))

    # Check comparison section present
    @test occursin("COMPARISON", uppercase(output))

    # Check labels appear
    @test occursin("Tree1", output)
    @test occursin("Tree2", output)
end

#==============================================================================#
#                    JSON RESULT LOADING TESTS                                 #
#==============================================================================#

const FIXTURES_DIR = joinpath(@__DIR__, "fixtures")

@testset "load_subdivision_result — full fixture" begin
    path = joinpath(FIXTURES_DIR, "subdivision_result.json")
    r = load_subdivision_result(path)

    @test r isa SubdivisionResult

    # Experiment parameters
    @test r.problem == "lv2d_sciml"
    @test r.degree == 4
    @test r.max_degree == 8
    @test r.max_depth == 5
    @test r.l2_tolerance ≈ 0.0001
    @test r.anisotropic == false
    @test occursin("Isotropic", r.label)
    @test occursin("4", r.label) && occursin("8", r.label)

    # Tree structure
    @test r.n_leaves == 5
    @test r.n_converged == 3

    # Leaf bounds: 5 leaves × 2 dims × [lo, hi]
    @test r.leaf_bounds !== nothing
    @test length(r.leaf_bounds) == 5
    @test length(r.leaf_bounds[1]) == 2        # 2D
    @test length(r.leaf_bounds[1][1]) == 2     # [lo, hi]
    @test r.leaf_bounds[1][1] ≈ [0.0, 0.5]
    @test r.leaf_bounds[3][2] ≈ [0.5, 1.0]

    # Leaf L2 errors
    @test r.leaf_l2_errors !== nothing
    @test length(r.leaf_l2_errors) == 5
    @test r.leaf_l2_errors[1] ≈ 1e-5
    @test r.leaf_l2_errors[5] ≈ 1e-2

    # Leaf degrees — mixed isotropic/anisotropic
    @test r.leaf_degrees !== nothing
    @test length(r.leaf_degrees) == 5
    @test r.leaf_degrees[1] == 4           # scalar (isotropic)
    @test r.leaf_degrees[2] == 6           # scalar
    @test r.leaf_degrees[3] == [4, 8]      # per-dim (anisotropic)
    @test r.leaf_degrees[4] == 8           # scalar

    # Recovery metrics
    @test r.raw_best_objective ≈ 0.00123
    @test r.raw_best_distance ≈ 0.045
    @test r.refined_best_objective ≈ 1.5e-6
    @test r.refined_best_distance ≈ 0.0012
    @test r.n_min == 2
    @test r.n_dedup == 3

    # Critical points
    @test length(r.cp_points) == 3
    @test r.cp_points[1] ≈ [0.201, 0.299]
    @test length(r.cp_types) == 3
    @test r.cp_types[1] == "min"
    @test r.cp_types[2] == "saddle"

    # Raw critical points
    @test length(r.raw_cp_points) == 4
    @test r.raw_cp_points[1] ≈ [0.19, 0.31]

    # True parameters
    @test r.p_true ≈ [0.2, 0.3]
end

@testset "load_subdivision_result — minimal fixture (no refined, no leaf data)" begin
    path = joinpath(FIXTURES_DIR, "subdivision_result_minimal.json")
    r = load_subdivision_result(path)

    @test r isa SubdivisionResult

    # Parameters
    @test r.problem == "rosenbrock_2d"
    @test r.degree == 6
    @test r.max_degree == 6   # defaults to degree when missing
    @test r.max_depth == 3
    @test r.l2_tolerance ≈ 0.001
    @test r.anisotropic == false
    @test occursin("Subdivision only", r.label)
    @test occursin("6", r.label)

    # Tree structure
    @test r.n_leaves == 2
    @test r.n_converged == 1

    # Missing optional fields → nothing
    @test r.leaf_bounds === nothing
    @test r.leaf_l2_errors === nothing
    @test r.leaf_degrees === nothing

    # No refined section → nothing/empty
    @test r.refined_best_objective === nothing
    @test r.refined_best_distance === nothing
    @test r.n_min === nothing
    @test r.n_dedup === nothing
    @test isempty(r.cp_points)
    @test isempty(r.cp_types)
    @test isempty(r.raw_cp_points)

    # No p_true in recovery_raw
    @test isempty(r.p_true)

    # Raw recovery — no distance key
    @test r.raw_best_objective ≈ 0.05
    @test r.raw_best_distance === nothing
end

@testset "load_subdivision_result — error cases" begin
    # File not found
    @test_throws ErrorException load_subdivision_result("/nonexistent/file.json")

    # Not a .json file
    @test_throws ErrorException load_subdivision_result(joinpath(FIXTURES_DIR, "experiment_config.json")[1:end-5] * ".txt")

    # Create a temporary JSON missing required sections
    tmpdir = mktempdir()
    missing_params = joinpath(tmpdir, "bad.json")
    write(missing_params, """{"problem": "test", "tree": {"n_total_leaves": 1, "n_converged": 0}}""")
    @test_throws ErrorException load_subdivision_result(missing_params)

    missing_tree = joinpath(tmpdir, "bad2.json")
    write(missing_tree, """{"problem": "test", "parameters": {"degree": 4, "max_depth": 3, "l2_tolerance": 0.01}}""")
    @test_throws ErrorException load_subdivision_result(missing_tree)
end

@testset "SubdivisionResult struct field types" begin
    path = joinpath(FIXTURES_DIR, "subdivision_result.json")
    r = load_subdivision_result(path)

    # Verify concrete types (not Any)
    @test r.problem isa String
    @test r.degree isa Int
    @test r.max_degree isa Int
    @test r.max_depth isa Int
    @test r.l2_tolerance isa Float64
    @test r.anisotropic isa Bool
    @test r.label isa String
    @test r.n_leaves isa Int
    @test r.n_converged isa Int
    @test r.raw_best_objective isa Float64
    @test r.cp_points isa Vector{Vector{Float64}}
    @test r.cp_types isa Vector{String}
    @test r.raw_cp_points isa Vector{Vector{Float64}}
    @test r.p_true isa Vector{Float64}
end
