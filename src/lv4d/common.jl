"""
Common utilities for LV4D analysis.

Contains shared parsing, formatting, and utility functions used across analysis modules.
"""

# ============================================================================
# ANSI Terminal Colors
# ============================================================================

const ANSI_GREEN = "\e[32m"
const ANSI_RED = "\e[31m"
const ANSI_BOLD = "\e[1m"
const ANSI_RESET = "\e[0m"

"""
    make_winner_highlighter(condition::Function) -> Highlighter

Create a PrettyTables highlighter for "winner" rows (bold green).

The condition function should have signature (data, row, col) -> Bool.
"""
function make_winner_highlighter(condition::Function)
    Highlighter(condition, bold=true, foreground=:green)
end

"""
    make_loser_highlighter(condition::Function) -> Highlighter

Create a PrettyTables highlighter for "loser" rows (red).

The condition function should have signature (data, row, col) -> Bool.
"""
function make_loser_highlighter(condition::Function)
    Highlighter(condition, foreground=:red)
end

# ============================================================================
# Data Structures
# ============================================================================

"""
    ExperimentParams

Parsed parameters from an LV4D experiment directory name.

# Fields
- `GN::Int`: Grid nodes per dimension
- `degree_min::Int`: Minimum polynomial degree
- `degree_max::Int`: Maximum polynomial degree
- `domain::Float64`: Domain half-width (sample_range)
- `seed::Union{Int, Nothing}`: Random seed (if present)
- `is_subdivision::Bool`: Whether subdivision strategy was used
"""
struct ExperimentParams
    GN::Int
    degree_min::Int
    degree_max::Int
    domain::Float64
    seed::Union{Int, Nothing}
    is_subdivision::Bool
end

# ============================================================================
# Directory Name Parsing
# ============================================================================

"""
    parse_experiment_name(dirname::String) -> Union{ExperimentParams, Nothing}

Parse LV4D experiment directory name to extract parameters.

Handles patterns like:
- Old format: `lv4d_GN8_deg4-12_domain0.1_seed1_20260115_120000`
- Old format: `lv4d_subdivision_GN16_deg8-8_domain0.05_seed42_...`
- New format: `lv4d_GN8_deg8_dom8.0e-2_seed1_20260120_...` (scientific notation, single degree)

Returns `nothing` if the pattern doesn't match.
"""
function parse_experiment_name(dirname::String)::Union{ExperimentParams, Nothing}
    # New format with scientific notation: lv4d_GN{gn}_deg{deg}_dom{scientific}_seed{seed}_
    # Example: lv4d_GN8_deg8_dom8.0e-2_seed1_20260120_123456
    m = match(r"lv4d(?:_subdivision)?_GN(\d+)_deg(\d+)_dom([\d.eE+-]+)_seed(\d+)_", dirname)
    if m !== nothing
        degree = parse(Int, m.captures[2])
        return ExperimentParams(
            parse(Int, m.captures[1]),      # GN
            degree,                          # degree_min = degree_max (single degree)
            degree,                          # degree_max
            parse(Float64, m.captures[3]),  # domain (scientific notation)
            parse(Int, m.captures[4]),      # seed
            occursin("subdivision", dirname) || occursin("_subdiv", dirname)
        )
    end

    # New format without seed
    m = match(r"lv4d(?:_subdivision)?_GN(\d+)_deg(\d+)_dom([\d.eE+-]+)_", dirname)
    if m !== nothing
        degree = parse(Int, m.captures[2])
        return ExperimentParams(
            parse(Int, m.captures[1]),
            degree,
            degree,
            parse(Float64, m.captures[3]),
            nothing,  # seed
            occursin("subdivision", dirname) || occursin("_subdiv", dirname)
        )
    end

    # Degree range with dom prefix (scientific notation) and seed
    # Example: lv4d_GN12_deg4-12_dom1.0e-2_seed1_20260122_170020
    m = match(r"lv4d(?:_subdivision)?_GN(\d+)_deg(\d+)-(\d+)_dom([\d.eE+-]+)_seed(\d+)_", dirname)
    if m !== nothing
        return ExperimentParams(
            parse(Int, m.captures[1]),      # GN
            parse(Int, m.captures[2]),      # degree_min
            parse(Int, m.captures[3]),      # degree_max
            parse(Float64, m.captures[4]),  # domain (scientific notation)
            parse(Int, m.captures[5]),      # seed
            occursin("subdivision", dirname) || occursin("_subdiv", dirname)
        )
    end

    # Degree range with dom prefix (scientific notation) without seed
    # Example: lv4d_GN12_deg4-12_dom1.0e-2_20260122_170020
    m = match(r"lv4d(?:_subdivision)?_GN(\d+)_deg(\d+)-(\d+)_dom([\d.eE+-]+)_", dirname)
    if m !== nothing
        return ExperimentParams(
            parse(Int, m.captures[1]),
            parse(Int, m.captures[2]),
            parse(Int, m.captures[3]),
            parse(Float64, m.captures[4]),
            nothing,  # seed
            occursin("subdivision", dirname) || occursin("_subdiv", dirname)
        )
    end

    # Old format: lv4d[_subdivision]_GN{gn}_deg{min}-{max}_domain{domain}_seed{seed}_{timestamp}
    m = match(r"lv4d(?:_subdivision)?_GN(\d+)_deg(\d+)-(\d+)_domain([\d.]+)_seed(\d+)_", dirname)
    if m !== nothing
        return ExperimentParams(
            parse(Int, m.captures[1]),      # GN
            parse(Int, m.captures[2]),      # degree_min
            parse(Int, m.captures[3]),      # degree_max
            parse(Float64, m.captures[4]),  # domain
            parse(Int, m.captures[5]),      # seed
            occursin("subdivision", dirname) || occursin("_subdiv", dirname)
        )
    end

    # Old format without seed
    m = match(r"lv4d(?:_subdivision)?_GN(\d+)_deg(\d+)-(\d+)_domain([\d.]+)_", dirname)
    if m !== nothing
        return ExperimentParams(
            parse(Int, m.captures[1]),
            parse(Int, m.captures[2]),
            parse(Int, m.captures[3]),
            parse(Float64, m.captures[4]),
            nothing,  # seed
            occursin("subdivision", dirname) || occursin("_subdiv", dirname)
        )
    end

    return nothing
end

"""
    parse_condition_number(val) -> Float64

Parse condition_number which may be "NaN" string or a number.
"""
function parse_condition_number(val)::Float64
    if val isa Number
        return Float64(val)
    elseif val isa String && lowercase(val) == "nan"
        return NaN
    else
        return NaN
    end
end

# ============================================================================
# Directory Utilities
# ============================================================================

"""
    is_single_experiment(path::String) -> Bool

Check if a path is a single LV4D experiment directory (vs parent containing experiments).

Note: This is the LV4D-specific implementation. The unified pipeline dispatches
to `is_single_experiment(::LV4DType, path)` which calls this function.
"""
function is_single_experiment(path::String)::Bool
    return startswith(basename(path), "lv4d_") && isfile(joinpath(path, "results_summary.json"))
end

# Implement unified dispatch for LV4DType
UnifiedPipeline.is_single_experiment(::LV4DType, path::String) = is_single_experiment(path)

"""
    find_results_root() -> String

Find the LV4D results directory using environment variable or default location.
"""
function find_results_root()::String
    results_root = get(ENV, "GLOBTIM_RESULTS_ROOT", nothing)
    if results_root !== nothing && isdir(results_root)
        lv4d_dir = joinpath(results_root, "lotka_volterra_4d")
        if isdir(lv4d_dir)
            return lv4d_dir
        end
    end

    # Try relative to script location (assumes we're in GlobalOptim)
    possible_roots = [
        joinpath(dirname(dirname(dirname(@__DIR__))), "globtim_results", "lotka_volterra_4d"),
        joinpath(dirname(dirname(@__DIR__)), "globtim_results", "lotka_volterra_4d"),
        expanduser("~/GlobalOptim/globtim_results/lotka_volterra_4d")
    ]

    for root in possible_roots
        if isdir(root)
            return root
        end
    end

    error("Could not find LV4D results directory. Set GLOBTIM_RESULTS_ROOT environment variable.")
end

"""
    find_experiments(results_root::String; pattern::Union{String, Regex, Nothing}=nothing) -> Vector{String}

Find experiment directories in the results root, optionally filtered by pattern.
"""
function find_experiments(results_root::String;
                         pattern::Union{String, Regex, Nothing}=nothing)::Vector{String}
    isdir(results_root) || return String[]

    dirs = filter(isdir, readdir(results_root, join=true))
    dirs = filter(d -> startswith(basename(d), "lv4d_"), dirs)

    if pattern !== nothing
        regex = pattern isa Regex ? pattern : Regex(pattern)
        dirs = filter(d -> occursin(regex, basename(d)), dirs)
    end

    return sort(dirs, by=mtime, rev=true)  # Most recent first
end

"""
    list_recent_experiments(results_root::String; limit::Int=15) -> Vector{String}

List recent experiment directories sorted by modification time.
"""
function list_recent_experiments(results_root::String; limit::Int=15)::Vector{String}
    experiments = find_experiments(results_root)
    return experiments[1:min(limit, length(experiments))]
end

# ============================================================================
# Formatting Utilities
# ============================================================================

"""
    format_domain(d::Real) -> String

Format domain value with appropriate precision for display.
"""
function format_domain(d::Real)::String
    if d < 0.001
        return @sprintf("%9.5f", d)
    elseif d < 0.01
        return @sprintf("%8.4f", d)
    elseif d < 0.1
        return @sprintf("%8.3f", d)
    else
        return @sprintf("%8.2f", d)
    end
end

"""
    format_scientific(x::Real; digits::Int=2) -> String

Format number in scientific notation with specified significant digits.
"""
function format_scientific(x::Real; digits::Int=2)::String
    if isnan(x) || !isfinite(x)
        return "      -"
    end
    return @sprintf("%.*e", digits, x)
end

"""
    format_percentage(x::Real; digits::Int=1) -> String

Format number as percentage with specified decimal places.
"""
function format_percentage(x::Real; digits::Int=1)::String
    if isnan(x) || !isfinite(x)
        return "    -"
    end
    return @sprintf("%.*f%%", digits, x * 100)
end

# ============================================================================
# Log-Scale Histogram Utilities
# ============================================================================

"""
    make_log_bins(values; n_bins::Int=8) -> Vector{Float64}

Create adaptive log-scale bins for histogram display.
"""
function make_log_bins(values; n_bins::Int=8)::Vector{Float64}
    valid = filter(x -> x > 0 && isfinite(x), values)
    if isempty(valid)
        return [1e-6, 1e-4, 1e-2, 1e0, 1e2, 1e4, 1e6, Inf]
    end

    log_min = floor(log10(minimum(valid)))
    log_max = ceil(log10(maximum(valid)))

    # Ensure at least 2 bins
    if log_max <= log_min
        log_max = log_min + 1
    end

    step = max(1.0, (log_max - log_min) / n_bins)
    bins = [10.0^i for i in log_min:step:(log_max + step)]
    push!(bins, Inf)
    return bins
end

"""
    format_bin_label(lo::Real, hi::Real) -> String

Format a bin label for log-scale histogram display.
"""
function format_bin_label(lo::Real, hi::Real)::String
    if hi == Inf
        return @sprintf("[%.0e, ∞)", lo)
    else
        return @sprintf("[%.0e, %.0e)", lo, hi)
    end
end

"""
    print_log_histogram(values::Vector, title::String; n_bins::Int=8, width::Int=50)

Print a text-based log-scale histogram to terminal.
"""
function print_log_histogram(values::AbstractVector{<:Real}, title::String;
                            n_bins::Int=8, width::Int=50)
    valid = filter(x -> !isnan(x) && x > 0, values)
    n_valid = length(valid)

    if n_valid == 0
        println("No valid values found for histogram.")
        return
    end

    bins = make_log_bins(valid; n_bins=n_bins)

    println(title)
    for i in 1:(length(bins)-1)
        count = sum(bins[i] .<= valid .< bins[i+1])
        pct = count / n_valid * 100
        bar = repeat("█", min(width, round(Int, pct * width / 100 * 2)))
        label = format_bin_label(bins[i], bins[i+1])
        @printf("  %-18s %4d (%5.1f%%) %s\n", label, count, pct, bar)
    end
end

"""
    print_percentiles(values::AbstractVector{<:Real}, name::String)

Print percentile statistics for a vector of values.
"""
function print_percentiles(values::AbstractVector{<:Real}, name::String)
    valid = filter(x -> !isnan(x) && isfinite(x), values)
    if isempty(valid)
        println("No valid $name values.")
        return
    end

    sorted = sort(valid)
    p_min = minimum(sorted)
    p25 = quantile(sorted, 0.25)
    p50 = quantile(sorted, 0.50)
    p75 = quantile(sorted, 0.75)
    p_max = maximum(sorted)

    @printf("  min: %.2e  p25: %.2e  median: %.2e  p75: %.2e  max: %.2e\n",
            p_min, p25, p50, p75, p_max)
end

# ============================================================================
# Time/Age Formatting
# ============================================================================

"""
    format_age(seconds::Real) -> String

Format a time duration in human-readable form.
"""
function format_age(seconds::Real)::String
    if seconds < 60
        return "$(round(Int, seconds))s"
    elseif seconds < 3600
        return "$(round(Int, seconds/60))m"
    elseif seconds < 86400
        return "$(round(Int, seconds/3600))h"
    else
        return "$(round(Int, seconds/86400))d"
    end
end
