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
    find_comparison_experiments(results_root::Union{String, Nothing}; limit::Int=15) -> Vector{String}

Find comparison experiment directories in results root.
When `results_root` is `nothing`, searches all known results directories.
"""
function find_comparison_experiments(results_root::Union{String, Nothing}; limit::Int=15)::Vector{String}
    # Get all roots if none specified
    roots = results_root === nothing ? find_all_results_roots() : [results_root]

    all_dirs = String[]
    for root in roots
        isdir(root) || continue
        dirs = filter(isdir, readdir(root, join=true))
        comparison_dirs = filter(d -> occursin("log_comparison", basename(d)), dirs)
        append!(all_dirs, comparison_dirs)
    end

    sorted = sort(all_dirs, by=mtime, rev=true)
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

        styled_table(summary_df; header=headers, formatters=(ft,), alignment=:r,
                     highlighters=(hl_better, hl_worse))
    else
        styled_table(summary_df; header=headers, formatters=(ft,), alignment=:r)
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

    styled_table(result_df; header=headers, formatters=(ft,), alignment=:r,
                 highlighters=(hl_winner, hl_loser))
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

# ============================================================================
# Single-Domain vs Subdivision Comparison
# ============================================================================

"""
    SubdivisionComparisonKey

Key tuple for matching single-domain and subdivision experiments.
Experiments are matched by (GN, degree, domain, seed).
"""
const SubdivisionComparisonKey = Tuple{Int, Int, Float64, Int}

"""
    find_matched_subdivision_pairs(experiments::Vector{LV4DExperimentData})
        -> Dict{SubdivisionComparisonKey, Tuple{LV4DExperimentData, LV4DExperimentData}}

Find matched pairs of single-domain and subdivision experiments.

Returns a Dict mapping (GN, degree, domain, seed) to (single, subdivision) tuples.
Only includes complete pairs where both methods exist for the same parameters.
"""
function find_matched_subdivision_pairs(experiments::Vector{LV4DExperimentData})
    # Separate by method type
    single = filter(e -> !e.params.is_subdivision, experiments)
    subdiv = filter(e -> e.params.is_subdivision, experiments)

    # Build lookup for single-domain experiments by key
    # Use degree_min as the "degree" key (experiments typically have degree_min == degree_max)
    single_lookup = Dict{SubdivisionComparisonKey, LV4DExperimentData}()
    for e in single
        seed = something(e.params.seed, 0)
        key = (e.params.GN, e.params.degree_min, e.params.domain, seed)
        single_lookup[key] = e
    end

    # Find matching pairs
    matched = Dict{SubdivisionComparisonKey, Tuple{LV4DExperimentData, LV4DExperimentData}}()
    for e in subdiv
        seed = something(e.params.seed, 0)
        key = (e.params.GN, e.params.degree_min, e.params.domain, seed)
        if haskey(single_lookup, key)
            matched[key] = (single_lookup[key], e)
        end
    end

    return matched
end

"""
    prepare_subdivision_comparison_df(matched::Dict{SubdivisionComparisonKey, Tuple{LV4DExperimentData, LV4DExperimentData}})
        -> DataFrame

Prepare a comparison DataFrame from matched experiment pairs.

Returns DataFrame with columns:
- GN, degree, domain, seed: Experiment parameters
- method: "single" or "subdivision"
- L2_norm, critical_points, recovery_error: Key metrics
- gradient_valid_rate, hessian_minima, computation_time: Additional metrics
"""
function prepare_subdivision_comparison_df(
    matched::Dict{SubdivisionComparisonKey, Tuple{LV4DExperimentData, LV4DExperimentData}}
)
    rows = DataFrame[]

    for (key, (single_exp, subdiv_exp)) in matched
        GN, degree, domain, seed = key

        for (method_name, exp) in [("single", single_exp), ("subdivision", subdiv_exp)]
            # Get degree results for this experiment
            dr = exp.degree_results
            if isempty(dr)
                @debug "Empty degree_results for $(experiment_id(exp))"
                continue
            end

            # Filter to the specific degree
            deg_rows = filter(r -> r.degree == degree, dr)
            if isempty(deg_rows)
                error("No results for degree $degree in experiment $(experiment_id(exp)). Available degrees: $(unique(dr.degree))")
            end

            # Extract metrics with proper handling of missing/NaN values
            # Use collect to ensure we have concrete vectors
            l2_vals = collect(skipmissing(deg_rows.L2_norm))
            cp_vals = collect(skipmissing(deg_rows.critical_points))
            rec_vals = collect(skipmissing(deg_rows.recovery_error))
            grad_vals = collect(skipmissing(deg_rows.gradient_valid_rate))
            min_vals = collect(skipmissing(deg_rows.hessian_minima))
            time_vals = collect(skipmissing(deg_rows.computation_time))

            # Aggregate metrics across rows (e.g., if multiple orthants)
            row = DataFrame(
                GN = GN,
                degree = degree,
                domain = domain,
                seed = seed,
                method = method_name,
                L2_norm = isempty(l2_vals) ? NaN : maximum(l2_vals),
                critical_points = isempty(cp_vals) ? 0 : sum(cp_vals),
                recovery_error = isempty(rec_vals) ? NaN : minimum(rec_vals),
                gradient_valid_rate = isempty(grad_vals) ? 0.0 : mean(grad_vals),
                hessian_minima = isempty(min_vals) ? 0 : sum(min_vals),
                computation_time = isempty(time_vals) ? NaN : sum(time_vals)
            )
            push!(rows, row)
        end
    end

    return isempty(rows) ? DataFrame() : vcat(rows...)
end

"""
    print_subdivision_comparison(df::DataFrame; io::IO=stdout, show_aggregated::Bool=true)

Print formatted subdivision comparison tables.

Shows:
1. Per-configuration results with side-by-side metrics
2. Aggregated results (mean across seeds) if show_aggregated=true
"""
function print_subdivision_comparison(df::DataFrame; io::IO=stdout, show_aggregated::Bool=true)
    if isempty(df)
        println(io, "No matched pairs to display.")
        return
    end

    # Create wide-format comparison table
    single_df = filter(r -> r.method == "single", df)
    subdiv_df = filter(r -> r.method == "subdivision", df)

    # Build comparison rows
    comparison_rows = DataFrame[]
    for single_row in eachrow(single_df)
        key = (single_row.GN, single_row.degree, single_row.domain, single_row.seed)
        subdiv_match = filter(r -> (r.GN, r.degree, r.domain, r.seed) == key, subdiv_df)
        nrow(subdiv_match) == 1 || continue

        subdiv_row = first(eachrow(subdiv_match))
        push!(comparison_rows, DataFrame(
            GN = single_row.GN,
            degree = single_row.degree,
            domain = single_row.domain,
            seed = single_row.seed,
            single_L2 = single_row.L2_norm,
            subdiv_L2 = subdiv_row.L2_norm,
            single_recovery = single_row.recovery_error,
            subdiv_recovery = subdiv_row.recovery_error,
            single_cps = single_row.critical_points,
            subdiv_cps = subdiv_row.critical_points,
            single_minima = single_row.hessian_minima,
            subdiv_minima = subdiv_row.hessian_minima
        ))
    end

    if isempty(comparison_rows)
        println(io, "No matched pairs to display.")
        return
    end

    wide_df = vcat(comparison_rows...)
    sort!(wide_df, [:domain, :degree, :seed])

    # Print per-configuration table
    println(io)
    println(io, "Per-Configuration Results:")
    println(io, "-"^80)

    headers = [
        "Degree", "Domain", "Seed",
        "Single L2", "Subdiv L2",
        "Single Rec%", "Subdiv Rec%",
        "Single CPs", "Subdiv CPs"
    ]

    # Format for display
    display_df = DataFrame(
        degree = wide_df.degree,
        domain = [@sprintf("%.4f", d) for d in wide_df.domain],
        seed = wide_df.seed,
        single_L2 = [@sprintf("%.2e", v) for v in wide_df.single_L2],
        subdiv_L2 = [@sprintf("%.2e", v) for v in wide_df.subdiv_L2],
        single_recovery = [isnan(v) ? "-" : @sprintf("%.1f%%", v*100) for v in wide_df.single_recovery],
        subdiv_recovery = [isnan(v) ? "-" : @sprintf("%.1f%%", v*100) for v in wide_df.subdiv_recovery],
        single_cps = wide_df.single_cps,
        subdiv_cps = wide_df.subdiv_cps
    )

    # Highlight better values (lower L2/recovery is better)
    function l2_highlight(data, i, j)
        j in [4, 5] || return false
        single_val = wide_df.single_L2[i]
        subdiv_val = wide_df.subdiv_L2[i]
        if j == 4
            return single_val < subdiv_val
        else
            return subdiv_val < single_val
        end
    end

    function recovery_highlight(data, i, j)
        j in [6, 7] || return false
        single_val = wide_df.single_recovery[i]
        subdiv_val = wide_df.subdiv_recovery[i]
        (isnan(single_val) || isnan(subdiv_val)) && return false
        if j == 6
            return single_val < subdiv_val
        else
            return subdiv_val < single_val
        end
    end

    hl_better = Highlighter((data, i, j) -> l2_highlight(data, i, j) || recovery_highlight(data, i, j),
                            bold=true, foreground=:green)

    styled_table(io, display_df; header=headers,
                 alignment=:r, highlighters=(hl_better,))

    # Aggregated view (mean across seeds)
    if show_aggregated && length(unique(wide_df.seed)) > 1
        println(io)
        println(io, "Aggregated (mean across seeds):")
        println(io, "-"^60)

        agg_df = combine(groupby(wide_df, [:GN, :degree, :domain]),
            :single_L2 => mean => :single_L2_mean,
            :subdiv_L2 => mean => :subdiv_L2_mean,
            :single_recovery => (x -> mean(filter(!isnan, x))) => :single_rec_mean,
            :subdiv_recovery => (x -> mean(filter(!isnan, x))) => :subdiv_rec_mean,
            :single_cps => mean => :single_cps_mean,
            :subdiv_cps => mean => :subdiv_cps_mean,
            nrow => :n_experiments
        )
        sort!(agg_df, [:domain, :degree])

        agg_display = DataFrame(
            degree = agg_df.degree,
            domain = [@sprintf("%.4f", d) for d in agg_df.domain],
            n = agg_df.n_experiments,
            single_L2 = [@sprintf("%.2e", v) for v in agg_df.single_L2_mean],
            subdiv_L2 = [@sprintf("%.2e", v) for v in agg_df.subdiv_L2_mean],
            single_rec = [isnan(v) ? "-" : @sprintf("%.1f%%", v*100) for v in agg_df.single_rec_mean],
            subdiv_rec = [isnan(v) ? "-" : @sprintf("%.1f%%", v*100) for v in agg_df.subdiv_rec_mean]
        )

        agg_headers = ["Degree", "Domain", "Seeds", "Single L2", "Subdiv L2", "Single Rec%", "Subdiv Rec%"]
        styled_table(io, agg_display; header=agg_headers, alignment=:r)
    end
end

"""
    compare_single_vs_subdivision(
        results_root::String;
        GN::Union{Int, Nothing}=nothing,
        degree::Union{Int, Nothing}=nothing,
        domain::Union{Float64, Nothing}=nothing,
        seed::Union{Int, Nothing}=nothing,
        io::IO=stdout
    ) -> DataFrame

Compare matched single-domain and subdivision experiments.

Loads all experiments from `results_root`, matches single-domain experiments
with their subdivision counterparts by (GN, degree, domain, seed), and
reports side-by-side metrics.

# Arguments
- `results_root::String`: Directory containing experiment subdirectories
- `GN::Union{Int, Nothing}`: Filter by grid nodes (optional)
- `degree::Union{Int, Nothing}`: Filter by polynomial degree (optional)
- `domain::Union{Float64, Nothing}`: Filter by domain size (optional)
- `seed::Union{Int, Nothing}`: Filter by random seed (optional)
- `io::IO`: Output stream for printing (default: stdout)

# Returns
DataFrame with columns:
- GN, degree, domain, seed, method: Experiment identifiers
- L2_norm, critical_points, recovery_error: Key metrics
- gradient_valid_rate, hessian_minima, computation_time: Additional metrics

# Example
```julia
using GlobtimPostProcessing.LV4DAnalysis

# Compare all matched experiments
df = compare_single_vs_subdivision("/path/to/results")

# Filter to specific GN and domain
df = compare_single_vs_subdivision("/path/to/results"; GN=12, domain=0.08)
```
"""
function compare_single_vs_subdivision(
    results_root::Union{String, Nothing};
    GN::Union{Int, Nothing}=nothing,
    degree::Union{Int, Nothing}=nothing,
    domain::Union{Float64, Nothing}=nothing,
    seed::Union{Int, Nothing}=nothing,
    io::IO=stdout
)::DataFrame
    println(io)
    println(io, "="^70)
    println(io, "SINGLE-DOMAIN VS SUBDIVISION COMPARISON")
    println(io, "="^70)
    results_str = results_root === nothing ? "(all results directories)" : results_root
    println(io, "Results: $results_str")

    # Load all experiments
    experiments = load_sweep_experiments(results_root)

    if isempty(experiments)
        println(io, "No experiments found in $results_root")
        return DataFrame()
    end

    # Apply filters
    if GN !== nothing
        experiments = filter(e -> e.params.GN == GN, experiments)
    end
    if degree !== nothing
        experiments = filter(e -> e.params.degree_min == degree, experiments)
    end
    if domain !== nothing
        experiments = filter(e -> isapprox(e.params.domain, domain; rtol=0.01), experiments)
    end
    if seed !== nothing
        experiments = filter(e -> e.params.seed == seed, experiments)
    end

    n_single = count(e -> !e.params.is_subdivision, experiments)
    n_subdiv = count(e -> e.params.is_subdivision, experiments)
    println(io, "Experiments: $n_single single-domain, $n_subdiv subdivision")

    # Find matched pairs
    matched = find_matched_subdivision_pairs(experiments)
    println(io, "Matched pairs: $(length(matched))")

    if isempty(matched)
        println(io, "\nNo matched pairs found. Ensure both single-domain and subdivision")
        println(io, "experiments exist for the same (GN, degree, domain, seed) combinations.")
        return DataFrame()
    end

    # Prepare comparison DataFrame
    df = prepare_subdivision_comparison_df(matched)

    if isempty(df)
        println(io, "\nFailed to extract metrics from matched experiments.")
        return DataFrame()
    end

    # Print comparison
    print_subdivision_comparison(df; io=io)

    # Print summary statistics
    println(io)
    println(io, "Summary Statistics:")
    println(io, "-"^40)

    single_metrics = filter(r -> r.method == "single", df)
    subdiv_metrics = filter(r -> r.method == "subdivision", df)

    if !isempty(single_metrics) && !isempty(subdiv_metrics)
        # L2 comparison
        single_l2_med = median(filter(!isnan, single_metrics.L2_norm))
        subdiv_l2_med = median(filter(!isnan, subdiv_metrics.L2_norm))
        l2_ratio = subdiv_l2_med / single_l2_med
        l2_winner = l2_ratio < 1.0 ? "subdivision" : "single"
        @printf(io, "  L2 median: single=%.2e, subdiv=%.2e (ratio=%.2f, %s better)\n",
                single_l2_med, subdiv_l2_med, l2_ratio, l2_winner)

        # Recovery comparison
        single_rec = filter(!isnan, single_metrics.recovery_error)
        subdiv_rec = filter(!isnan, subdiv_metrics.recovery_error)
        if !isempty(single_rec) && !isempty(subdiv_rec)
            single_rec_med = median(single_rec)
            subdiv_rec_med = median(subdiv_rec)
            rec_ratio = subdiv_rec_med / single_rec_med
            rec_winner = rec_ratio < 1.0 ? "subdivision" : "single"
            @printf(io, "  Recovery median: single=%.1f%%, subdiv=%.1f%% (ratio=%.2f, %s better)\n",
                    single_rec_med*100, subdiv_rec_med*100, rec_ratio, rec_winner)
        end

        # Critical points
        single_cps = sum(single_metrics.critical_points)
        subdiv_cps = sum(subdiv_metrics.critical_points)
        @printf(io, "  Total critical points: single=%d, subdiv=%d\n", single_cps, subdiv_cps)

        # Hessian minima
        single_minima = sum(single_metrics.hessian_minima)
        subdiv_minima = sum(subdiv_metrics.hessian_minima)
        @printf(io, "  Total Hessian minima: single=%d, subdiv=%d\n", single_minima, subdiv_minima)
    end

    println(io)
    return df
end
