# SubdivisionTreeAnalysis.jl
# Analysis functions for adaptive subdivision trees from globtim
#
# This module loads subdivision trees saved by globtim and computes
# additional analysis metrics for postprocessing.
#
# Supports two formats:
#   1. JLD2 (binary): load_subdivision_tree() — loads full SubdivisionTree objects
#   2. JSON (portable): load_subdivision_result() — loads summary results with
#      leaf bounds, degrees, L2 errors, and refined critical points

using JLD2
using JSON
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
#                    JSON RESULT LOADING                                       #
#==============================================================================#

"""
    SubdivisionResult

Typed container for a subdivision experiment result loaded from JSON.

Holds the experiment parameters, tree structure summary (leaf bounds, degrees,
L2 errors), raw/refined recovery metrics, and critical point data.

# Fields

**Experiment parameters:**
- `problem::String`: Problem identifier (e.g. "lv2d_sciml")
- `degree::Int`: Initial polynomial degree
- `max_degree::Int`: Maximum degree (equals `degree` if no degree bumping)
- `max_depth::Int`: Maximum subdivision depth
- `l2_tolerance::Float64`: L2 convergence tolerance
- `anisotropic::Bool`: Whether anisotropic degree bumping was used
- `label::String`: Human-readable run label

**Tree structure:**
- `n_leaves::Int`: Total number of leaf subdomains
- `n_converged::Int`: Number of converged leaves
- `leaf_bounds::Union{Nothing, Vector{Vector{Vector{Float64}}}}`: Per-leaf bounds `[leaf][dim] → [lo, hi]`
- `leaf_l2_errors::Union{Nothing, Vector{Float64}}`: Per-leaf L2 approximation errors
- `leaf_degrees::Union{Nothing, Vector{Union{Int, Vector{Int}}}}`: Per-leaf polynomial degrees (scalar or per-dim)

**Recovery metrics:**
- `raw_best_objective::Float64`: Best objective value from raw polynomial CPs
- `raw_best_distance::Union{Nothing, Float64}`: Distance to p_true from best raw CP
- `refined_best_objective::Union{Nothing, Float64}`: Best objective after refinement
- `refined_best_distance::Union{Nothing, Float64}`: Distance to p_true after refinement
- `n_min::Union{Nothing, Int}`: Number of local minima found
- `n_dedup::Union{Nothing, Int}`: Number of distinct CPs after deduplication

**Critical points:**
- `cp_points::Vector{Vector{Float64}}`: Refined critical point locations
- `cp_types::Vector{String}`: Classification of each refined CP ("min", "saddle", etc.)
- `raw_cp_points::Vector{Vector{Float64}}`: Raw (pre-refinement) critical points
- `p_true::Vector{Float64}`: True parameter vector (ground truth)
"""
struct SubdivisionResult
    # Experiment parameters
    problem::String
    degree::Int
    max_degree::Int
    max_depth::Int
    l2_tolerance::Float64
    anisotropic::Bool
    label::String
    # Tree structure
    n_leaves::Int
    n_converged::Int
    leaf_bounds::Union{Nothing, Vector{Vector{Vector{Float64}}}}
    leaf_l2_errors::Union{Nothing, Vector{Float64}}
    leaf_degrees::Union{Nothing, Vector{Union{Int, Vector{Int}}}}
    # Recovery metrics
    raw_best_objective::Float64
    raw_best_distance::Union{Nothing, Float64}
    refined_best_objective::Union{Nothing, Float64}
    refined_best_distance::Union{Nothing, Float64}
    n_min::Union{Nothing, Int}
    n_dedup::Union{Nothing, Int}
    # Critical points
    cp_points::Vector{Vector{Float64}}
    cp_types::Vector{String}
    raw_cp_points::Vector{Vector{Float64}}
    p_true::Vector{Float64}
end

"""
    _parse_leaf_degrees(raw::Vector) -> Vector{Union{Int, Vector{Int}}}

Parse leaf_degrees from JSON, handling both scalar ints (isotropic) and
per-dimension arrays (anisotropic).

JSON examples: `[4, 4, [4, 8], 6]` or `[4, 4, 4]`.
"""
function _parse_leaf_degrees(raw::Vector)
    result = Union{Int, Vector{Int}}[]
    for el in raw
        if el isa AbstractVector
            push!(result, Int.(el))
        else
            push!(result, Int(el))
        end
    end
    return result
end

"""
    load_subdivision_result(path::String) -> SubdivisionResult

Load a subdivision experiment result from a JSON file.

The JSON format contains sections: `parameters`, `tree`, `recovery_raw`,
`refined`, and optionally `refinement_details`. This is the portable format
produced by sandbox experiment scripts, as opposed to the binary JLD2 format
loaded by [`load_subdivision_tree`](@ref).

# JSON structure
```json
{
  "problem": "lv2d_sciml",
  "parameters": {
    "degree": 4, "max_degree": 8, "max_depth": 5,
    "l2_tolerance": 0.0001, "anisotropic": false
  },
  "tree": {
    "n_total_leaves": 12, "n_converged": 10,
    "leaf_bounds": [[[lo, hi], [lo, hi]], ...],
    "leaf_l2_errors": [0.001, ...],
    "leaf_degrees": [4, [4, 8], ...]
  },
  "recovery_raw": {
    "best_objective": 0.001, "best_distance": 0.05,
    "p_true": [0.2, 0.3]
  },
  "refined": {
    "n_min": 2, "n_after_dedup": 3,
    "best_min_objective": 1e-4, "best_min_distance": 0.01,
    "points": [[0.2, 0.3], ...], "cp_types": ["min", "saddle", ...]
  }
}
```

# Example
```julia
result = load_subdivision_result("results/lv2d_deg4to8.json")
println(result.problem)          # "lv2d_sciml"
println(result.n_leaves)         # 12
println(result.leaf_bounds[1])   # [[lo1, hi1], [lo2, hi2]]
```
"""
function load_subdivision_result(path::String)
    !isfile(path) && error("File not found: $path")
    endswith(path, ".json") || error("Expected .json file, got: $path")

    data = JSON.parsefile(path)

    # Required sections
    haskey(data, "parameters") || error("Missing 'parameters' section in $path")
    haskey(data, "tree") || error("Missing 'tree' section in $path")

    params = data["parameters"]
    tree = data["tree"]

    deg = Int(params["degree"])
    max_deg = Int(get(params, "max_degree", deg))

    # Recovery (raw)
    recovery_raw = get(data, "recovery_raw", nothing)
    raw_obj = recovery_raw !== nothing ? Float64(recovery_raw["best_objective"]) : NaN
    raw_dist = recovery_raw !== nothing ? (
        haskey(recovery_raw, "best_distance") && recovery_raw["best_distance"] !== nothing ?
            Float64(recovery_raw["best_distance"]) : nothing
    ) : nothing

    # Refined results
    refined = get(data, "refined", nothing)
    has_refined = refined !== nothing && get(refined, "n_after_dedup", 0) > 0
    ref_obj = has_refined && haskey(refined, "best_min_objective") ?
        Float64(refined["best_min_objective"]) : nothing
    ref_dist = has_refined && haskey(refined, "best_min_distance") ?
        Float64(refined["best_min_distance"]) : nothing

    # Tree structure (leaf data for visualization)
    leaf_bounds = haskey(tree, "leaf_bounds") ?
        [Vector{Float64}[Float64.(b) for b in lb] for lb in tree["leaf_bounds"]] :
        nothing
    leaf_l2_errors = haskey(tree, "leaf_l2_errors") ?
        Float64.(tree["leaf_l2_errors"]) : nothing
    leaf_degrees = haskey(tree, "leaf_degrees") ?
        _parse_leaf_degrees(tree["leaf_degrees"]) : nothing

    # Critical points (refined)
    cp_points = has_refined && haskey(refined, "points") ?
        Vector{Float64}[Float64.(p) for p in refined["points"]] : Vector{Float64}[]
    cp_types = has_refined && haskey(refined, "cp_types") ?
        String.(refined["cp_types"]) : String[]

    # Raw critical points (pre-refinement)
    ref_details = get(data, "refinement_details", nothing)
    raw_cp_points = ref_details !== nothing && haskey(ref_details, "raw_points") ?
        Vector{Float64}[Float64.(p) for p in ref_details["raw_points"]] : Vector{Float64}[]

    # True parameters
    p_true = recovery_raw !== nothing && haskey(recovery_raw, "p_true") ?
        Float64.(recovery_raw["p_true"]) : Float64[]

    # Build label
    aniso = Bool(get(params, "anisotropic", false))
    label = if max_deg > deg
        aniso ? "Anisotropic deg bump ($deg→$max_deg)" :
                "Isotropic deg bump ($deg→$max_deg)"
    else
        "Subdivision only (deg $deg)"
    end

    return SubdivisionResult(
        String(data["problem"]),
        deg, max_deg, Int(params["max_depth"]),
        Float64(params["l2_tolerance"]), aniso, label,
        Int(tree["n_total_leaves"]), Int(tree["n_converged"]),
        leaf_bounds, leaf_l2_errors, leaf_degrees,
        raw_obj, raw_dist, ref_obj, ref_dist,
        has_refined ? get(refined, "n_min", nothing) : nothing,
        has_refined ? get(refined, "n_after_dedup", nothing) : nothing,
        cp_points, cp_types, raw_cp_points, p_true,
    )
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
