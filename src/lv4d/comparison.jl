"""
Method comparison analysis for LV4D experiments.

Provides unified analysis for comparing different polynomial approximation methods
(e.g., standard vs log-transformed).

Migrated from globtim/experiments/lv4d_2025/analyze_log_comparison.jl to follow
package architecture (analysis code belongs in globtimpostprocessing).
"""

# UnicodePlots is imported in parent module

# ============================================================================
# Data Structures
# ============================================================================

"""
    ComparisonData

Holds loaded comparison experiment data with metadata.

# Fields
- `df::DataFrame`: Raw comparison_results.csv data
- `methods::Vector{String}`: Available methods (e.g., ["standard", "log"])
- `domains::Vector{Float64}`: Unique domain values
- `degrees::Vector{Int}`: Unique degree values
- `dir::String`: Source directory path
"""
struct ComparisonData
    df::DataFrame
    methods::Vector{String}
    domains::Vector{Float64}
    degrees::Vector{Int}
    dir::String
end

# Required columns in comparison_results.csv
const COMPARISON_REQUIRED_COLS = [
    :seed, :domain, :degree, :method, :l2_error,
    :num_cps, :best_grad_norm, :best_dist_to_true, :best_objective, :runtime_sec
]

# ============================================================================
# Data Loading
# ============================================================================

"""
    load_comparison_data(path::String) -> ComparisonData

Load comparison experiment results from a directory or CSV file.

# Arguments
- `path`: Path to either:
  - A directory containing `comparison_results.csv`
  - A CSV file directly

# Returns
- `ComparisonData` with validated data

# Errors
- Throws error if file not found (no fallback)
- Throws error if required columns are missing
"""
function load_comparison_data(path::String)::ComparisonData
    # Determine CSV path
    csv_path = if isdir(path)
        joinpath(path, "comparison_results.csv")
    elseif isfile(path) && endswith(path, ".csv")
        path
    else
        error("Path must be a directory containing comparison_results.csv or a CSV file: $path")
    end

    isfile(csv_path) || error("comparison_results.csv not found: $csv_path")

    # Load data
    df = CSV.read(csv_path, DataFrame)
    nrow(df) > 0 || error("comparison_results.csv is empty: $csv_path")

    # Validate required columns
    cols = Symbol.(names(df))
    missing_cols = setdiff(COMPARISON_REQUIRED_COLS, cols)
    isempty(missing_cols) || error("Missing required columns in comparison_results.csv: $missing_cols")

    # Extract metadata
    methods = sort(unique(df.method))
    domains = sort(unique(df.domain))
    degrees = sort(unique(df.degree))
    dir = isdir(path) ? path : dirname(path)

    return ComparisonData(df, methods, domains, degrees, dir)
end

"""
    find_comparison_experiments(results_root::String; limit::Int=15) -> Vector{String}

Find comparison experiment directories in results root.
"""
function find_comparison_experiments(results_root::String; limit::Int=15)::Vector{String}
    isdir(results_root) || return String[]

    dirs = filter(isdir, readdir(results_root, join=true))
    comparison_dirs = filter(d -> occursin("log_comparison", basename(d)), dirs)
    sorted = sort(comparison_dirs, by=mtime, rev=true)
    return sorted[1:min(limit, length(sorted))]
end

# ============================================================================
# Analysis Functions
# ============================================================================

"""
    analyze_comparison(data::ComparisonData; metric::Symbol=:best_dist_to_true)

Full comparison analysis with visual output (colors and histograms).

# Arguments
- `data`: Loaded comparison data
- `metric`: Metric to compare by (:best_dist_to_true or :l2_error)

# Output
Prints to terminal:
- Overall summary table with winner highlighting
- Per-domain breakdown with head-to-head colors
- Histogram of method ratios (UnicodePlots)
"""
function analyze_comparison(data::ComparisonData; metric::Symbol=:best_dist_to_true)
    df = data.df
    metric_col = metric

    println("\n" * "="^70)
    println("Log vs Standard Comparison Analysis")
    println("="^70)
    println("Results: $(basename(data.dir))")
    println("Total runs: $(nrow(df))")
    println("Methods: $(join(data.methods, ", "))")
    println("Domains: $(data.domains)")
    println("Degrees: $(data.degrees)")
    println("Metric: $metric")

    # Load config for context if available
    config_path = joinpath(data.dir, "experiment_config.json")
    if isfile(config_path)
        config = JSON.parsefile(config_path)
        haskey(config, "GN") && println("GN: $(config["GN"])")
        haskey(config, "seeds") && println("Seeds: $(config["seeds"])")
    end

    # Overall summary
    _print_overall_summary(df, metric_col)

    # Per-domain breakdown
    for dom in data.domains
        _print_per_domain_summary(df, dom, metric_col)
    end

    # Ratio histogram
    _print_ratio_histogram(df, metric_col)

    println()
    return nothing
end

# ============================================================================
# Internal Display Functions
# ============================================================================

"""
Print overall summary table with winner highlighting.
"""
function _print_overall_summary(df::DataFrame, metric_col::Symbol)
    println("\nOverall Summary (all domains combined)")

    summary_data = []
    for method in sort(unique(df.method))
        s = filter(r -> r.method == method && isfinite(r[metric_col]), df)
        n = nrow(s)
        n > 0 || continue

        push!(summary_data, (
            method = method,
            runs = n,
            metric_med = median(s[!, metric_col]),
            l2_approx_err_med = median(s.l2_error)
        ))
    end

    isempty(summary_data) && return

    summary_df = DataFrame(summary_data)
    metric_label = metric_col == :best_dist_to_true ? "dist_to_true(med)" : "$(metric_col)(med)"
    headers = ["method", "runs", metric_label, "L2 error (med)"]

    # Formatter for scientific notation
    ft = (v, _, j) -> j >= 3 && v isa Number && !isnan(v) ? @sprintf("%.2e", v) : string(v)

    # Determine winner (lower metric is better)
    if nrow(summary_df) >= 2
        winner_idx = argmin(summary_df.metric_med)
        winner = summary_df.method[winner_idx]

        hl_better = make_winner_highlighter((data, i, j) -> data[i, 1] == winner)
        hl_worse = make_loser_highlighter((data, i, j) -> data[i, 1] != winner)

        pretty_table(summary_df, header=headers, formatters=(ft,), alignment=:r,
                     tf=tf_unicode_rounded, highlighters=(hl_better, hl_worse))
    else
        pretty_table(summary_df, header=headers, formatters=(ft,), alignment=:r,
                     tf=tf_unicode_rounded)
    end
end

"""
Print per-domain summary with head-to-head coloring by degree.
"""
function _print_per_domain_summary(df::DataFrame, dom::Float64, metric_col::Symbol)
    println("\nDomain: $dom")

    # Filter to this domain with valid results
    dom_df = filter(r -> r.domain == dom && isfinite(r[metric_col]), df)
    isempty(dom_df) && return

    # Group by method+degree, compute medians
    domain_data = []
    degrees = sort(unique(dom_df.degree))
    methods = sort(unique(dom_df.method))

    for deg in degrees
        for method in methods
            s = filter(r -> r.degree == deg && r.method == method, dom_df)
            nrow(s) == 0 && continue
            push!(domain_data, (
                method = method,
                degree = deg,
                runs = nrow(s),
                l2_approx_err_med = median(s.l2_error),
                metric_med = median(s[!, metric_col])
            ))
        end
    end

    isempty(domain_data) && return

    # Sort by L2 approximation error (best approximation first)
    sorted_data = sort(domain_data, by=x -> x.l2_approx_err_med)

    # Create DataFrame and add rank column (by metric)
    result_df = DataFrame(sorted_data)
    metric_order = sortperm(result_df.metric_med)
    result_df.rank = zeros(Int, nrow(result_df))
    for (rank, idx) in enumerate(metric_order)
        result_df.rank[idx] = rank
    end

    metric_label = metric_col == :best_dist_to_true ? "dist_to_true(med)" : "$(metric_col)(med)"
    headers = ["method", "degree", "runs", "L2 error (med)", metric_label, "rank"]
    ft = (v, _, j) -> j in [4, 5] && v isa Number ? @sprintf("%.2e", v) : string(v)

    # Compute winner at each degree for head-to-head coloring
    degree_winners = Dict{Int, String}()
    for deg in degrees
        deg_rows = filter(r -> r.degree == deg, result_df)
        nrow(deg_rows) >= 2 || continue

        # Find method with lowest metric at this degree
        best_idx = argmin(deg_rows.metric_med)
        degree_winners[deg] = deg_rows.method[best_idx]
    end

    # Color: green = wins at that degree, red = loses at that degree
    hl_winner = make_winner_highlighter(
        (data, i, j) -> get(degree_winners, data[i, 2], "") == data[i, 1]
    )
    hl_loser = make_loser_highlighter(
        (data, i, j) -> haskey(degree_winners, data[i, 2]) &&
                        degree_winners[data[i, 2]] != data[i, 1]
    )

    pretty_table(result_df, header=headers, formatters=(ft,), alignment=:r,
                 tf=tf_unicode_rounded, highlighters=(hl_winner, hl_loser))
end

"""
Print histogram of method ratios using UnicodePlots.
"""
function _print_ratio_histogram(df::DataFrame, metric_col::Symbol)
    println("\nMetric Ratio (log / standard)")

    methods = sort(unique(df.method))
    length(methods) >= 2 || return

    # Assume first method alphabetically is baseline (typically "log" vs "standard")
    # Compute ratios: log_value / standard_value
    ratios = Float64[]
    for gdf in groupby(df, [:seed, :domain, :degree])
        nrow(gdf) != 2 && continue

        std_row = filter(r -> r.method == "standard", gdf)
        log_row = filter(r -> r.method == "log", gdf)
        (nrow(std_row) != 1 || nrow(log_row) != 1) && continue

        std_val = std_row[1, metric_col]
        log_val = log_row[1, metric_col]

        isfinite(std_val) && isfinite(log_val) && std_val > 0 && log_val > 0 &&
            push!(ratios, log_val / std_val)
    end

    isempty(ratios) && return

    log_ratios = log10.(ratios)
    # Adaptive binning: fewer bins for sparse data
    nbins = max(3, min(10, length(log_ratios) ÷ 2))
    n_log_better = count(r -> r < 1.0, ratios)
    n_std_better = count(r -> r > 1.0, ratios)
    title_str = @sprintf("n=%d | log wins: %d | std wins: %d | median=%.2f",
                         length(ratios), n_log_better, n_std_better, median(ratios))

    plt = UnicodePlots.histogram(log_ratios, nbins=nbins, vertical=true, height=10, width=60,
                                 xlabel="← log better | log₁₀(ratio) | std better →",
                                 title=title_str)
    println(plt)
end
