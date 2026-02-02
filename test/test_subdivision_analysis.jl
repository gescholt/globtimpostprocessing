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
    print_tree_comparison_table

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
