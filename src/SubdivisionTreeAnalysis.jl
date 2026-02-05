# SubdivisionTreeAnalysis.jl
# Analysis functions for adaptive subdivision trees from globtim
#
# This module loads subdivision trees saved by globtim and computes
# additional analysis metrics for postprocessing.

using JLD2
using DataFrames
using Statistics
using Printf
using PrettyTables

#==============================================================================#
#                    TREE LOADING                                              #
#==============================================================================#

"""
    load_subdivision_tree(filename::AbstractString) -> (tree, metadata)

Load a SubdivisionTree from a JLD2 file created by `Globtim.save_tree()`.

# Returns
- `tree`: The loaded SubdivisionTree object
- `metadata`: Associated metadata dictionary

# Example
```julia
tree, metadata = load_subdivision_tree("results/tree.jld2")
println("Function: ", metadata["function"])
```
"""
function load_subdivision_tree(filename::AbstractString)
    !isfile(filename) && error("File not found: $filename")

    jldopen(filename, "r") do file
        tree = file["subdivision_tree"]
        metadata = haskey(file, "metadata") ? file["metadata"] : Dict()
        return (tree, metadata)
    end
end

#==============================================================================#
#                    TREE ANALYSIS STATISTICS                                  #
#==============================================================================#

"""
    SubdivisionTreeStats

Comprehensive statistics for a subdivision tree analysis.

# Fields
- `n_leaves::Int`: Total number of leaf subdomains
- `n_converged::Int`: Number of converged leaves (met tolerance)
- `n_active::Int`: Number of active (unconverged) leaves
- `max_depth::Int`: Maximum tree depth
- `mean_depth::Float64`: Mean depth of leaves
- `total_l2_error::Float64`: Sum of L2 errors across all leaves
- `mean_l2_error::Float64`: Mean L2 error per leaf
- `std_l2_error::Float64`: Standard deviation of L2 errors
- `min_l2_error::Float64`: Minimum L2 error
- `max_l2_error::Float64`: Maximum L2 error
- `median_l2_error::Float64`: Median L2 error
- `depth_distribution::Dict{Int, Int}`: Count of leaves at each depth
- `error_quantiles::NamedTuple`: L2 error quantiles (q10, q25, q50, q75, q90)
- `dimension::Int`: Problem dimension
- `convergence_rate::Float64`: Fraction of converged leaves
"""
struct SubdivisionTreeStats
    n_leaves::Int
    n_converged::Int
    n_active::Int
    max_depth::Int
    mean_depth::Float64
    total_l2_error::Float64
    mean_l2_error::Float64
    std_l2_error::Float64
    min_l2_error::Float64
    max_l2_error::Float64
    median_l2_error::Float64
    depth_distribution::Dict{Int, Int}
    error_quantiles::NamedTuple{(:q10, :q25, :q50, :q75, :q90), NTuple{5, Float64}}
    dimension::Int
    convergence_rate::Float64
end

"""
    analyze_subdivision_tree(tree) -> SubdivisionTreeStats

Compute comprehensive statistics for a subdivision tree.

This function uses duck typing - it works with any tree-like object that has:
- `subdomains::Vector` with elements having `depth` and `l2_error` fields
- `converged_leaves::Vector{Int}` and `active_leaves::Vector{Int}`

# Arguments
- `tree`: A SubdivisionTree or compatible object

# Returns
- `SubdivisionTreeStats` with all computed metrics
"""
function analyze_subdivision_tree(tree)
    leaf_ids = vcat(tree.converged_leaves, tree.active_leaves)
    isempty(leaf_ids) && error("Tree has no leaves")

    leaves = [tree.subdomains[id] for id in leaf_ids]
    errors = [sd.l2_error for sd in leaves]
    depths = [sd.depth for sd in leaves]

    # Depth distribution
    depth_dist = Dict{Int, Int}()
    for d in depths
        depth_dist[d] = get(depth_dist, d, 0) + 1
    end

    # Get dimension from first leaf
    dim = length(leaves[1].center)

    # Compute quantiles
    quantiles = (
        q10 = quantile(errors, 0.10),
        q25 = quantile(errors, 0.25),
        q50 = quantile(errors, 0.50),
        q75 = quantile(errors, 0.75),
        q90 = quantile(errors, 0.90)
    )

    n_leaves = length(leaf_ids)
    n_converged = length(tree.converged_leaves)

    return SubdivisionTreeStats(
        n_leaves,
        n_converged,
        length(tree.active_leaves),
        maximum(depths),
        mean(depths),
        sum(errors),
        mean(errors),
        std(errors),
        minimum(errors),
        maximum(errors),
        median(errors),
        depth_dist,
        quantiles,
        dim,
        n_converged / n_leaves
    )
end

#==============================================================================#
#                    DATAFRAME EXTRACTION                                      #
#==============================================================================#

"""
    tree_leaves_to_dataframe(tree) -> DataFrame

Extract leaf subdomain data as a DataFrame for analysis.

# Columns
- `id::Int`: Subdomain ID in tree
- `depth::Int`: Depth in tree
- `l2_error::Float64`: L2 approximation error
- `status::String`: "converged" or "active"
- `center_1`, `center_2`, ...: Center coordinates
- `width_1`, `width_2`, ...: Half-widths in each dimension
- `volume::Float64`: Subdomain volume

# Example
```julia
tree, _ = load_subdivision_tree("tree.jld2")
df = tree_leaves_to_dataframe(tree)
filter(row -> row.status == "converged", df)
```
"""
function tree_leaves_to_dataframe(tree)
    leaf_ids = vcat(tree.converged_leaves, tree.active_leaves)
    isempty(leaf_ids) && return DataFrame()

    dim = length(tree.subdomains[1].center)

    # Build column arrays
    ids = Int[]
    depths = Int[]
    l2_errors = Float64[]
    statuses = String[]
    volumes = Float64[]
    centers = [Float64[] for _ in 1:dim]
    widths = [Float64[] for _ in 1:dim]

    converged_set = Set(tree.converged_leaves)

    for id in leaf_ids
        sd = tree.subdomains[id]
        push!(ids, id)
        push!(depths, sd.depth)
        push!(l2_errors, sd.l2_error)
        push!(statuses, id in converged_set ? "converged" : "active")
        push!(volumes, prod(2 .* sd.half_widths))

        for d in 1:dim
            push!(centers[d], sd.center[d])
            push!(widths[d], sd.half_widths[d])
        end
    end

    # Build DataFrame
    df = DataFrame(
        id = ids,
        depth = depths,
        l2_error = l2_errors,
        status = statuses,
        volume = volumes
    )

    # Add center and width columns
    for d in 1:dim
        df[!, Symbol("center_$d")] = centers[d]
        df[!, Symbol("width_$d")] = widths[d]
    end

    return df
end

"""
    tree_depth_summary(tree) -> DataFrame

Summarize tree statistics by depth level.

# Columns
- `depth::Int`: Tree depth
- `n_leaves::Int`: Number of leaves at this depth
- `n_converged::Int`: Converged leaves at this depth
- `mean_l2_error::Float64`: Mean L2 error at this depth
- `std_l2_error::Float64`: Std deviation of L2 error
- `min_l2_error::Float64`: Minimum L2 error
- `max_l2_error::Float64`: Maximum L2 error
- `total_volume::Float64`: Total volume of leaves at this depth
"""
function tree_depth_summary(tree)
    df = tree_leaves_to_dataframe(tree)
    isempty(df) && return DataFrame()

    # Group by depth
    result = DataFrame(
        depth = Int[],
        n_leaves = Int[],
        n_converged = Int[],
        mean_l2_error = Float64[],
        std_l2_error = Float64[],
        min_l2_error = Float64[],
        max_l2_error = Float64[],
        total_volume = Float64[]
    )

    for depth in sort(unique(df.depth))
        depth_df = filter(row -> row.depth == depth, df)

        push!(result, (
            depth = depth,
            n_leaves = nrow(depth_df),
            n_converged = sum(depth_df.status .== "converged"),
            mean_l2_error = mean(depth_df.l2_error),
            std_l2_error = nrow(depth_df) > 1 ? std(depth_df.l2_error) : 0.0,
            min_l2_error = minimum(depth_df.l2_error),
            max_l2_error = maximum(depth_df.l2_error),
            total_volume = sum(depth_df.volume)
        ))
    end

    return result
end

#==============================================================================#
#                    REPORTING                                                 #
#==============================================================================#

"""
    print_subdivision_tree_report(tree; io::IO=stdout)

Print a detailed analysis report for a subdivision tree.

# Arguments
- `tree`: SubdivisionTree or compatible object
- `io`: Output stream (default: stdout)
"""
function print_subdivision_tree_report(tree; io::IO=stdout)
    stats = analyze_subdivision_tree(tree)

    println(io, "=" ^ 70)
    println(io, "SUBDIVISION TREE ANALYSIS REPORT")
    println(io, "=" ^ 70)
    println(io)

    # Structure summary
    println(io, "STRUCTURE")
    println(io, "-" ^ 70)
    @printf(io, "  Dimension:           %d\n", stats.dimension)
    @printf(io, "  Total leaves:        %d\n", stats.n_leaves)
    @printf(io, "  Converged:           %d (%.1f%%)\n", stats.n_converged, stats.convergence_rate * 100)
    @printf(io, "  Active:              %d\n", stats.n_active)
    @printf(io, "  Max depth:           %d\n", stats.max_depth)
    @printf(io, "  Mean depth:          %.2f\n", stats.mean_depth)
    println(io)

    # L2 error summary
    println(io, "L2 APPROXIMATION ERROR")
    println(io, "-" ^ 70)
    @printf(io, "  Total:               %.4e\n", stats.total_l2_error)
    @printf(io, "  Mean:                %.4e\n", stats.mean_l2_error)
    @printf(io, "  Std:                 %.4e\n", stats.std_l2_error)
    @printf(io, "  Min:                 %.4e\n", stats.min_l2_error)
    @printf(io, "  Max:                 %.4e\n", stats.max_l2_error)
    @printf(io, "  Median:              %.4e\n", stats.median_l2_error)
    println(io)

    # Quantiles
    println(io, "  Quantiles:")
    @printf(io, "    10th:              %.4e\n", stats.error_quantiles.q10)
    @printf(io, "    25th:              %.4e\n", stats.error_quantiles.q25)
    @printf(io, "    50th:              %.4e\n", stats.error_quantiles.q50)
    @printf(io, "    75th:              %.4e\n", stats.error_quantiles.q75)
    @printf(io, "    90th:              %.4e\n", stats.error_quantiles.q90)
    println(io)

    # Depth distribution table
    println(io, "DEPTH DISTRIBUTION")
    println(io, "-" ^ 70)
    depth_df = tree_depth_summary(tree)

    styled_table(io, depth_df;
        header = ["Depth", "Leaves", "Converged", "Mean L2", "Std L2", "Min L2", "Max L2", "Volume"],
        formatters = (ft_printf("%.2e", [4, 5, 6, 7]), ft_printf("%.3f", [8])),
        alignment = [:c, :c, :c, :r, :r, :r, :r, :r],
    )

    println(io)
    println(io, "=" ^ 70)

    nothing
end

"""
    compare_subdivision_trees(trees::Vector; labels=nothing) -> DataFrame

Compare statistics across multiple subdivision trees.

# Arguments
- `trees`: Vector of SubdivisionTree objects
- `labels`: Optional labels for each tree (default: "Tree 1", "Tree 2", ...)

# Returns
DataFrame with columns: label, n_leaves, n_converged, max_depth, mean_l2, total_l2
"""
function compare_subdivision_trees(trees::Vector; labels=nothing)
    n = length(trees)
    labels = labels === nothing ? ["Tree $i" for i in 1:n] : labels

    result = DataFrame(
        label = String[],
        n_leaves = Int[],
        n_converged = Int[],
        convergence_rate = Float64[],
        max_depth = Int[],
        mean_l2_error = Float64[],
        total_l2_error = Float64[],
        dimension = Int[]
    )

    for (tree, label) in zip(trees, labels)
        stats = analyze_subdivision_tree(tree)
        push!(result, (
            label = label,
            n_leaves = stats.n_leaves,
            n_converged = stats.n_converged,
            convergence_rate = stats.convergence_rate,
            max_depth = stats.max_depth,
            mean_l2_error = stats.mean_l2_error,
            total_l2_error = stats.total_l2_error,
            dimension = stats.dimension
        ))
    end

    return result
end

"""
    print_tree_comparison_table(trees::Vector; labels=nothing, io::IO=stdout)

Print a comparison table for multiple subdivision trees.
"""
function print_tree_comparison_table(trees::Vector; labels=nothing, io::IO=stdout)
    df = compare_subdivision_trees(trees; labels=labels)

    println(io, "SUBDIVISION TREE COMPARISON")
    println(io, "=" ^ 70)

    styled_table(io, df;
        header = ["Label", "Leaves", "Conv", "Conv%", "Depth", "Mean L2", "Total L2", "Dim"],
        formatters = (ft_printf("%.1f%%", [4]), ft_printf("%.2e", [6, 7])),
        alignment = [:l, :c, :c, :c, :c, :r, :r, :c],
    )

    nothing
end
