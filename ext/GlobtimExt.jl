module GlobtimExt

using GlobtimPostProcessing
using AbstractTrees
using Printf: @sprintf
using FiniteDiff: finite_difference_hessian
using Globtim: SubdivisionTree, total_error, n_leaves, n_active, get_max_depth, volume
using Globtim: compute_hessians, classify_critical_points

import GlobtimPostProcessing:
    TreeDisplayConfig,
    DEFAULT_CONFIG,
    DIM_COLORS,
    get_dim_color,
    split_position_viz,
    get_error_reduction,
    progress_bar,
    format_time,
    format_error

# Hessian classification override — provides actual classification when Globtim is loaded.
# Constrained to ::Function for Julia extension dispatch (callers wrap non-Function callables
# via _as_function before calling). Uses ForwardDiff for analytical objectives, or FiniteDiff
# for ODE objectives where ForwardDiff can't propagate Dual types through the ODE solver.
function GlobtimPostProcessing.classify_refined_points(
    objective_func::Function,
    points::Vector{Vector{Float64}};
    gradient_method::Symbol = :forwarddiff,
)
    if gradient_method == :finitediff
        # Finite-difference Hessians — works for any callable including ODE-based TolerantObjective
        n_dims = length(first(points))
        hessians = Vector{Matrix{Float64}}(undef, length(points))
        failed_points = Int[]
        for (i, pt) in enumerate(points)
            try
                hessians[i] = finite_difference_hessian(objective_func, pt)
            catch e
                push!(failed_points, i)
                @debug "Point $i: finite-difference Hessian failed" exception=(
                    e,
                    catch_backtrace(),
                )
                hessians[i] = fill(NaN, n_dims, n_dims)
            end
        end
        if !isempty(failed_points)
            @warn "Finite-difference Hessian failed for $(length(failed_points))/$(length(points)) points" failed_points=first(
                failed_points,
                5,
            )
        end
    else
        # ForwardDiff Hessians — fast and exact for analytical (non-ODE) objectives
        points_matrix = reduce(vcat, [pt' for pt in points])
        hessians = compute_hessians(objective_func, points_matrix)
    end
    return classify_critical_points(hessians)
end

# Tree node wrapper for AbstractTrees interface
struct TreeNode
    tree::SubdivisionTree
    id::Int
end

AbstractTrees.children(n::TreeNode) = begin
    sd = n.tree.subdomains[n.id]
    sd.children === nothing ? TreeNode[] :
    [TreeNode(n.tree, sd.children[1]), TreeNode(n.tree, sd.children[2])]
end

AbstractTrees.printnode(io::IO, n::TreeNode) = begin
    sd = n.tree.subdomains[n.id]
    if sd.split_dim !== nothing
        dim = sd.split_dim
        color = get_dim_color(dim)
        viz = split_position_viz(sd.split_pos)

        reduction = get_error_reduction(n.tree, n.id)
        if reduction !== nothing
            if reduction >= 0
                reduction_str = " $(round(Int, reduction))%↓"
                reduction_color = :cyan
            else
                reduction_str = " $(round(Int, -reduction))%↑"
                reduction_color = :red
            end
        else
            reduction_str = ""
            reduction_color = :white
        end

        printstyled(io, "x$(dim)", color = color)
        print(io, " $viz")
        printstyled(io, reduction_str, color = reduction_color)
    else
        if n.id in n.tree.converged_leaves
            printstyled(io, "✓", color = :green)
        else
            printstyled(io, "○", color = :yellow)
        end
        print(io, " [$(round(sd.l2_error, sigdigits=2))]")
    end
end

function GlobtimPostProcessing.compute_display_error(tree::SubdivisionTree)
    total = 0.0
    for id in tree.converged_leaves
        total += tree.subdomains[id].l2_error
    end
    for id in tree.active_leaves
        err = tree.subdomains[id].l2_error
        if isfinite(err)
            total += err
        else
            parent_id = tree.subdomains[id].parent_id
            if parent_id !== nothing
                total += tree.subdomains[parent_id].l2_error / 2
            end
        end
    end
    return total
end

function GlobtimPostProcessing.count_splits_per_dim(tree::SubdivisionTree)
    counts = Dict{Int,Int}()
    for sd in tree.subdomains
        if sd.split_dim !== nothing
            counts[sd.split_dim] = get(counts, sd.split_dim, 0) + 1
        end
    end
    return counts
end

function GlobtimPostProcessing.make_tracker(; max_leaves::Int = 50, show_dims::Bool = true)
    start_time = Ref(0.0)

    return function (tree, iteration)
        iteration == 1 && (start_time[] = time())

        leaves = n_leaves(tree)
        active = n_active(tree)
        conv = leaves - active
        depth = get_max_depth(tree)

        bar = progress_bar(leaves, max_leaves)

        dim_str = ""
        if show_dims
            counts = GlobtimPostProcessing.count_splits_per_dim(tree)
            if !isempty(counts)
                parts = ["x$d:$c" for (d, c) in sort(collect(counts))]
                dim_str = " [" * join(parts, " ") * "]"
            end
        end

        err_val = GlobtimPostProcessing.compute_display_error(tree)
        err_str = isfinite(err_val) ? string(round(err_val, sigdigits = 3)) : "?"

        time_str = format_time(time() - start_time[])

        print("\r\e[K")
        print(
            "[$iteration] [$bar] $leaves/$max_leaves d=$depth ($(conv)✓ $(active)○)$dim_str err=$err_str [$time_str]",
        )
        flush(stdout)
    end
end

function GlobtimPostProcessing.live_tracker(tree::SubdivisionTree, iteration)
    depth = get_max_depth(tree)
    leaves = n_leaves(tree)
    active = n_active(tree)
    conv = leaves - active

    err_val = GlobtimPostProcessing.compute_display_error(tree)
    err_str = isfinite(err_val) ? string(round(err_val, sigdigits = 3)) : "?"

    print("\r\e[K")
    print("[$iteration] d=$depth leaves=$leaves ($(conv)✓ $(active)○) err=$err_str")
    flush(stdout)
end

function GlobtimPostProcessing.print_summary(tree::SubdivisionTree)
    n_total = n_leaves(tree)
    n_conv = length(tree.converged_leaves)
    n_act = length(tree.active_leaves)

    split_counts = Dict{Int,Int}()
    for sd in tree.subdomains
        if sd.split_dim !== nothing
            split_counts[sd.split_dim] = get(split_counts, sd.split_dim, 0) + 1
        end
    end

    println("\nSummary: $n_total leaves ($n_conv converged, $n_act active)")
    if !isempty(split_counts)
        dims_str =
            join(["x$d=$(split_counts[d])" for d in sort(collect(keys(split_counts)))], " ")
        println("Splits: $dims_str")
    end
    println("Total L2 error: $(round(total_error(tree), sigdigits=4))")
end

function GlobtimPostProcessing.get_path_to_root(tree::SubdivisionTree, node_id::Int)
    path = [node_id]
    current = node_id
    while tree.subdomains[current].parent_id !== nothing
        current = tree.subdomains[current].parent_id
        pushfirst!(path, current)
    end
    return path
end

function GlobtimPostProcessing.format_path_compact(
    tree::SubdivisionTree,
    path::Vector{Int};
    config::TreeDisplayConfig = DEFAULT_CONFIG,
)
    parts = String[]
    for (i, id) in enumerate(path)
        sd = tree.subdomains[id]
        if i == length(path)
            symbol = id in tree.converged_leaves ? "✓" : "○"
            err_str = round(sd.l2_error, sigdigits = config.error_sigfigs)
            push!(parts, "$symbol[$err_str]")
        else
            if sd.split_dim !== nothing
                pos_str = @sprintf("%.1f", sd.split_pos)
                push!(parts, "x$(sd.split_dim)@$pos_str")
            end
        end
    end
    return join(parts, " → ")
end

function GlobtimPostProcessing.print_tree_compact(
    tree::SubdivisionTree;
    config::TreeDisplayConfig = DEFAULT_CONFIG,
    io::IO = stdout,
)
    all_leaves = vcat(collect(tree.converged_leaves), collect(tree.active_leaves))
    sort!(all_leaves, by = id -> -tree.subdomains[id].l2_error)

    for leaf_id in all_leaves
        path = GlobtimPostProcessing.get_path_to_root(tree, leaf_id)
        line = GlobtimPostProcessing.format_path_compact(tree, path; config = config)

        if config.use_colors
            color = leaf_id in tree.converged_leaves ? :green : :yellow
            printstyled(io, line, "\n", color = color)
        else
            println(io, line)
        end
    end
end

function GlobtimPostProcessing.print_tree_summary_only(
    tree::SubdivisionTree;
    top_n::Int = 10,
    io::IO = stdout,
)
    n_total = n_leaves(tree)
    n_conv = length(tree.converged_leaves)
    n_act = length(tree.active_leaves)
    depth = get_max_depth(tree)

    println(io, "Tree Summary ($n_total leaves)")
    println(io, "=" ^ 50)
    println(io, "Leaves: $n_conv converged, $n_act active")
    println(io, "Max depth: $depth")

    split_counts = GlobtimPostProcessing.count_splits_per_dim(tree)
    if !isempty(split_counts)
        dims_str = join(["x$d=$c" for (d, c) in sort(collect(split_counts))], " ")
        println(io, "Splits: $dims_str")
    end

    total_err = total_error(tree)
    println(io, "Total L2 error: $(round(total_err, sigdigits=4))")

    println(io)
    println(io, "Top $top_n leaves by error:")
    println(io, "-" ^ 50)

    all_leaves = vcat(collect(tree.converged_leaves), collect(tree.active_leaves))
    sort!(all_leaves, by = id -> -tree.subdomains[id].l2_error)

    for (i, leaf_id) in enumerate(all_leaves[1:min(top_n, length(all_leaves))])
        sd = tree.subdomains[leaf_id]
        status = leaf_id in tree.converged_leaves ? "✓" : "○"
        err_pct = total_err > 0 ? round(sd.l2_error / total_err * 100, digits = 1) : 0.0
        path = GlobtimPostProcessing.get_path_to_root(tree, leaf_id)
        path_str = join(
            [
                "x$(tree.subdomains[id].split_dim)" for
                id in path[1:(end-1)] if tree.subdomains[id].split_dim !== nothing
            ],
            "→",
        )
        println(
            io,
            "  $i. $status err=$(round(sd.l2_error, sigdigits=3)) ($err_pct%) depth=$(sd.depth) path: $path_str",
        )
    end

    if length(all_leaves) > top_n
        remaining = length(all_leaves) - top_n
        remaining_err =
            sum(tree.subdomains[id].l2_error for id in all_leaves[(top_n+1):end])
        remaining_pct =
            total_err > 0 ? round(remaining_err / total_err * 100, digits = 1) : 0.0
        println(io, "  ... and $remaining more leaves ($remaining_pct% of error)")
    end

    GlobtimPostProcessing.print_volume_distribution(tree; io = io)
end

function GlobtimPostProcessing.print_tree_auto(
    tree::SubdivisionTree;
    compact_threshold::Int = 20,
    summary_threshold::Int = 40,
    config::TreeDisplayConfig = DEFAULT_CONFIG,
    io::IO = stdout,
)
    n = n_leaves(tree)

    if n <= compact_threshold
        print_tree(TreeNode(tree, tree.root_id))
    elseif n <= summary_threshold
        println(io, "Compact view ($n leaves):")
        GlobtimPostProcessing.print_tree_compact(tree; config = config, io = io)
    else
        GlobtimPostProcessing.print_tree_summary_only(tree; io = io)
    end

    GlobtimPostProcessing.print_summary(tree)
end

function GlobtimPostProcessing.print_volume_distribution(
    tree::SubdivisionTree;
    io::IO = stdout,
)
    all_vols = Float64[]
    active_vols = Float64[]

    for id in tree.active_leaves
        v = volume(tree.subdomains[id])
        push!(all_vols, v)
        push!(active_vols, v)
    end
    for id in tree.converged_leaves
        v = volume(tree.subdomains[id])
        push!(all_vols, v)
    end

    root_vol = volume(tree.subdomains[tree.root_id])
    vol_ratios = all_vols ./ root_vol
    min_ratio = minimum(vol_ratios)

    min_exp = floor(Int, log10(min_ratio))
    bins = [10.0^i for i in min_exp:0]

    println(io, "\nVolume Distribution ($(n_leaves(tree)) leaves)")
    println(io, "─"^50)

    println(io, "All leaves:")
    GlobtimPostProcessing.print_histogram(vol_ratios, bins, io = io)

    if !isempty(active_vols)
        println(io, "\nActive (not converged):")
        active_ratios = active_vols ./ root_vol
        GlobtimPostProcessing.print_histogram(active_ratios, bins, io = io)
    end
end

end # module GlobtimExt
