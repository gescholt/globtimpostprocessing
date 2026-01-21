"""
Local minima analysis from multi-start refinement results.

Clusters refined points to identify distinct local minima and analyze their structure.
"""

# ============================================================================
# Main Analysis Function
# ============================================================================

"""
    analyze_local_minima(csv_path::String, p_true::Vector{Float64};
                        cluster_threshold::Float64=0.05)

Analyze local minima structure from refinement results.

# Arguments
- `csv_path::String`: Path to refinement_comparison.csv or similar CSV
- `p_true::Vector{Float64}`: True parameter values
- `cluster_threshold::Float64=0.05`: Distance threshold for clustering points

# Output
Prints analysis of distinct local minima including:
- All refined points sorted by function value
- Clustered local minima with statistics
- Comparison of closest vs lowest-value minima
"""
function analyze_local_minima(csv_path::String, p_true::Vector{Float64};
                              cluster_threshold::Float64=0.05)
    df = CSV.read(csv_path, DataFrame)

    # Detect dimension from column names (refined_x1, refined_x2, ...)
    dim = _detect_dimension(df)
    if dim == 0
        error("Could not detect dimension from CSV columns")
    end

    # Extract refined points and values
    refined_points = _extract_refined_points(df, dim)
    refined_values = _get_refined_values(df)
    orthants = _get_orthants(df)

    # Sort by function value
    order = sortperm(refined_values)

    println("="^80)
    println("LOCAL MINIMA ANALYSIS")
    println("="^80)
    println()
    println("p_true = ", round.(p_true, digits=4))
    println()

    # Print all refined points
    _print_all_refined_points(refined_points, refined_values, orthants, p_true, order)

    # Cluster points to find distinct minima
    clusters, cluster_centers = _cluster_points(refined_points, refined_values, order,
                                                cluster_threshold)

    # Print cluster analysis
    _print_cluster_analysis(clusters, cluster_centers, refined_points, refined_values,
                            orthants, p_true, cluster_threshold)

    # Print summary
    _print_minima_summary(clusters, cluster_centers, refined_points, refined_values, p_true)

    return clusters, cluster_centers
end

# ============================================================================
# Helper Functions
# ============================================================================

function _detect_dimension(df::DataFrame)::Int
    for dim in 1:10
        if !hasproperty(df, Symbol("refined_x$dim"))
            return dim - 1
        end
    end
    return 0
end

function _extract_refined_points(df::DataFrame, dim::Int)::Vector{Vector{Float64}}
    return [[row[Symbol("refined_x$i")] for i in 1:dim] for row in eachrow(df)]
end

function _get_refined_values(df::DataFrame)::Vector{Float64}
    if hasproperty(df, :refined_value)
        return df.refined_value
    elseif hasproperty(df, :refined_f)
        return df.refined_f
    else
        error("CSV must contain 'refined_value' or 'refined_f' column")
    end
end

function _get_orthants(df::DataFrame)::Vector{Int}
    if hasproperty(df, :orthant)
        return df.orthant
    elseif hasproperty(df, :point_idx)
        return df.point_idx
    else
        return collect(1:nrow(df))
    end
end

function _print_all_refined_points(refined_points, refined_values, orthants, p_true, order)
    dim = length(refined_points[1])

    println("-"^80)
    println("ALL REFINED POINTS (sorted by f value)")
    println("-"^80)
    @printf("%-8s %-12s %-10s %-50s\n", "Index", "f(p)", "||p-p*||", "Coordinates")
    println("-"^80)

    for i in order
        pt = refined_points[i]
        dist = norm(pt .- p_true)
        coords = "[" * join([@sprintf("%.4f", x) for x in pt], ", ") * "]"
        @printf("%-8d %-12.4f %-10.4f %-50s\n",
                orthants[i], refined_values[i], dist, coords)
    end
    println("-"^80)
    println()
end

function _cluster_points(refined_points, refined_values, order, cluster_threshold)
    clusters = Vector{Vector{Int}}()
    cluster_centers = Vector{Vector{Float64}}()

    for i in order
        pt = refined_points[i]
        assigned = false

        for (ci, center) in enumerate(cluster_centers)
            if norm(pt .- center) < cluster_threshold
                push!(clusters[ci], i)
                # Update center to mean
                all_pts = [refined_points[j] for j in clusters[ci]]
                cluster_centers[ci] = mean(all_pts)
                assigned = true
                break
            end
        end

        if !assigned
            push!(clusters, [i])
            push!(cluster_centers, pt)
        end
    end

    return clusters, cluster_centers
end

function _print_cluster_analysis(clusters, cluster_centers, refined_points, refined_values,
                                 orthants, p_true, cluster_threshold)
    println("="^80)
    println("DISTINCT LOCAL MINIMA (cluster threshold = $cluster_threshold)")
    println("="^80)
    println()

    # Sort clusters by best function value
    cluster_best_vals = [minimum(refined_values[c]) for c in clusters]
    cluster_order = sortperm(cluster_best_vals)

    for (rank, ci) in enumerate(cluster_order)
        members = clusters[ci]
        center = cluster_centers[ci]
        best_idx = members[argmin([refined_values[j] for j in members])]
        best_val = refined_values[best_idx]
        dist_to_true = norm(center .- p_true)

        println("CLUSTER $rank:")
        println("  Center: ", round.(center, digits=4))
        @printf("  Distance to p_true: %.4f (%.1f%%)\n", dist_to_true, dist_to_true * 100)
        @printf("  Best f(p): %.4f\n", best_val)
        println("  Members: $(length(members)) points from indices ",
                [orthants[j] for j in members])

        if rank == 1 && dist_to_true < 0.1
            println("  *** LIKELY GLOBAL MINIMUM (near p_true) ***")
        elseif rank == 1
            println("  *** LOWEST f VALUE BUT FAR FROM p_true ***")
        end
        println()
    end
end

function _print_minima_summary(clusters, cluster_centers, refined_points, refined_values, p_true)
    println("="^80)
    println("SUMMARY")
    println("="^80)
    println()
    println("Total distinct local minima found: $(length(clusters))")
    println()

    # Find closest minimum to p_true
    distances = [norm(c .- p_true) for c in cluster_centers]
    closest_idx = argmin(distances)
    closest_center = cluster_centers[closest_idx]
    closest_dist = distances[closest_idx]
    closest_best_val = minimum(refined_values[clusters[closest_idx]])

    println("CLOSEST MINIMUM TO p_true:")
    println("  Center: ", round.(closest_center, digits=4))
    @printf("  Distance: %.4f\n", closest_dist)
    @printf("  Best f(p): %.4f\n", closest_best_val)
    println()

    # Find minimum with lowest f value
    cluster_best_vals = [minimum(refined_values[c]) for c in clusters]
    best_cluster_idx = argmin(cluster_best_vals)
    best_center = cluster_centers[best_cluster_idx]
    best_dist = norm(best_center .- p_true)
    best_val = cluster_best_vals[best_cluster_idx]

    println("LOWEST f VALUE MINIMUM:")
    println("  Center: ", round.(best_center, digits=4))
    @printf("  Distance to p_true: %.4f\n", best_dist)
    @printf("  Best f(p): %.4f\n", best_val)
    println()

    if closest_idx == best_cluster_idx
        println("✓ The closest minimum to p_true is also the global minimum")
    else
        println("✗ MISMATCH: Global minimum is NOT the closest to p_true")
        println("  This explains why recovery isn't perfect!")
    end
end
