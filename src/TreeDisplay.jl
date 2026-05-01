# TreeDisplay.jl
# Pure formatting utilities for subdivision tree display.
# Globtim-dependent functions (make_tracker, print_tree_*, etc.) are provided
# via the GlobtimExt package extension — load Globtim to activate them.

using AbstractTrees
using Printf: @sprintf

#=============================================================================
# Configuration
=============================================================================#

"""
    TreeDisplayConfig

Configuration for text-based tree display.
"""
Base.@kwdef struct TreeDisplayConfig
    show_split_position::Bool = true    # Show ASCII [---|------] visualization
    show_error_reduction::Bool = true   # Show n%↓ or n%↑ after splits
    show_depth::Bool = false            # Show depth indicator
    error_sigfigs::Int = 2              # Significant figures for error display
    split_viz_width::Int = 10           # Width of split position ASCII bar
    max_display_depth::Union{Int,Nothing} = nothing  # Truncate display at this depth
    compact::Bool = false               # Use compact one-line-per-leaf format
    use_colors::Bool = true             # Enable colored output
end

# Default configuration
const DEFAULT_CONFIG = TreeDisplayConfig()

#=============================================================================
# Tracker utility functions (pure, testable, no Globtim dependency)
=============================================================================#

"""
    progress_bar(current, max, width=10) -> String

Create ASCII progress bar: "█████░░░░░" for 50% progress.
"""
function progress_bar(current::Int, max::Int, width::Int = 10)
    progress = clamp(current / max, 0.0, 1.0)
    filled = round(Int, progress * width)
    return "█"^filled * "░"^(width - filled)
end

"""
    format_error(errors) -> String

Format error sum, returning "?" if no finite errors.
"""
function format_error(errors::Vector{Float64})
    finite = filter(isfinite, errors)
    isempty(finite) ? "?" : string(round(sum(finite), sigdigits = 3))
end

"""
    format_time(seconds) -> String

Format elapsed time as "5.5s" or "1.5m".
"""
function format_time(seconds::Float64)
    seconds < 60 ? "$(round(seconds, digits=1))s" : "$(round(seconds/60, digits=1))m"
end

# Dimension colors (cycle through for >6 dimensions)
const DIM_COLORS = [:red, :green, :blue, :yellow, :magenta, :cyan]
get_dim_color(dim::Int) = DIM_COLORS[mod1(dim, length(DIM_COLORS))]

# ASCII split position: [----|---------] shows where split occurs in [-1,1]
function split_position_viz(split_pos::Float64, width::Int = 10)
    pos = round(Int, (split_pos + 1) / 2 * (width - 1))
    pos = clamp(pos, 0, width - 1)
    return "[" * "-"^pos * "|" * "-"^(width - 1 - pos) * "]"
end

# Error reduction from parent to children (percentage)
function get_error_reduction(tree, node_id::Int)
    sd = tree.subdomains[node_id]
    sd.children === nothing && return nothing
    left_id, right_id = sd.children
    left_err = tree.subdomains[left_id].l2_error
    right_err = tree.subdomains[right_id].l2_error
    children_total = left_err + right_err
    if sd.l2_error > 0 && sd.l2_error != Inf
        return (sd.l2_error - children_total) / sd.l2_error * 100
    end
    return nothing
end

# Print legend for dimension colors
function print_legend(n_dims::Int)
    println("\nLegend:")
    for i in 1:min(n_dims, 6)
        printstyled("  x$i", color = get_dim_color(i))
        println(" = Dimension $i")
    end
    printstyled("  ✓", color = :green)
    println(" = converged")
    printstyled("  ○", color = :yellow)
    println(" = active")
end

"""
    print_histogram(values, bins; bar_width=20, io=stdout)

Print ASCII histogram for given values and bin edges.
"""
function print_histogram(
    values::Vector{Float64},
    bins::Vector{Float64};
    bar_width::Int = 20,
    io::IO = stdout,
)
    n = length(values)
    for i in 1:(length(bins)-1)
        lo, hi = bins[i], bins[i+1]
        count = sum(lo .<= values .< hi)
        count == 0 && continue
        pct = n > 0 ? count / n * 100 : 0.0
        bar_len = round(Int, pct / 100 * bar_width)
        bar = "█"^bar_len * "░"^(bar_width - bar_len)

        range_str = @sprintf("[%5.1f%%-%5.1f%%]", lo * 100, hi * 100)
        count_str = @sprintf("%3d (%4.1f%%)", count, pct)

        println(io, "  $(rpad(range_str, 16)) $bar $count_str")
    end
end

#=============================================================================
# Stubs — activated by GlobtimExt when Globtim is loaded
=============================================================================#

"""
    compute_display_error(tree) -> Float64

Requires Globtim to be loaded (activates GlobtimExt).
"""
function compute_display_error end

"""
    count_splits_per_dim(tree) -> Dict{Int,Int}

Requires Globtim to be loaded (activates GlobtimExt).
"""
function count_splits_per_dim end

"""
    make_tracker(; max_leaves=50, show_dims=true) -> callback

Create a live progress tracker callback for `adaptive_refine`.
Requires Globtim to be loaded (activates GlobtimExt).
"""
function make_tracker end

"""
    live_tracker(tree, iteration)

Simple live progress tracker. Requires Globtim to be loaded (activates GlobtimExt).
"""
function live_tracker end

"""
    print_summary(tree)

Requires Globtim to be loaded (activates GlobtimExt).
"""
function print_summary end

"""
    get_path_to_root(tree, node_id) -> Vector{Int}

Requires Globtim to be loaded (activates GlobtimExt).
"""
function get_path_to_root end

"""
    format_path_compact(tree, path; config=DEFAULT_CONFIG) -> String

Requires Globtim to be loaded (activates GlobtimExt).
"""
function format_path_compact end

"""
    print_tree_compact(tree; config=DEFAULT_CONFIG, io=stdout)

Requires Globtim to be loaded (activates GlobtimExt).
"""
function print_tree_compact end

"""
    print_tree_summary_only(tree; top_n=10, io=stdout)

Requires Globtim to be loaded (activates GlobtimExt).
"""
function print_tree_summary_only end

"""
    print_tree_auto(tree; compact_threshold=20, summary_threshold=40, config=DEFAULT_CONFIG, io=stdout)

Requires Globtim to be loaded (activates GlobtimExt).
"""
function print_tree_auto end

"""
    print_volume_distribution(tree; io=stdout)

Requires Globtim to be loaded (activates GlobtimExt).
"""
function print_volume_distribution end
