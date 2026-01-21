"""
Critical point quality analysis for single LV4D experiments.

Displays histograms and statistics for:
1. Distance to true parameters ||x - p*||
2. Gradient norms ||∇f(x)||
3. Evaluation errors |f(x) - w_d(x)|
"""

# ============================================================================
# Main Analysis Function
# ============================================================================

"""
    analyze_quality(data::LV4DExperimentData; verbose::Bool=true)

Analyze critical point quality for a single experiment.

Displays:
- Domain membership statistics
- Histogram of ||x - p*|| distance to true parameters
- Histogram of ||∇f(x)|| gradient norms
- Histogram of |f(x) - w_d(x)| evaluation errors
- Summary table of all critical points

# Arguments
- `data::LV4DExperimentData`: Loaded experiment data
- `verbose::Bool=true`: Whether to show histograms and detailed output
"""
function analyze_quality(data::LV4DExperimentData; verbose::Bool=true)
    println("\n" * "="^70)
    println("Critical Point Quality Analysis")
    println("="^70)
    println("Results: $(basename(data.dir))")

    if data.critical_points === nothing || nrow(data.critical_points) == 0
        println("No critical points found in this experiment.")
        return
    end

    df = data.critical_points
    println("Total critical points: $(nrow(df))")
    @printf("True parameters: [%s]\n", join([@sprintf("%.4f", p) for p in data.p_true], ", "))
    @printf("Domain center:   [%s]\n", join([@sprintf("%.4f", p) for p in data.p_center], ", "))
    @printf("Domain size:     ±%.4f (bounds = center ± %.4f)\n", data.domain_size, data.domain_size)

    # Domain membership analysis
    domain_stats = analyze_domain_membership(df, data.p_center, data.domain_size)
    if domain_stats !== nothing
        _print_domain_stats(domain_stats)
    end

    # Degree summary table (when multiple degrees)
    if length(unique(df.degree)) > 1
        _print_degree_summary(df)
    end

    if verbose
        # Histogram 1: Distance to true parameters
        _print_distance_histogram(df)

        # Histogram 2: Gradient norms
        _print_gradient_histogram(df)

        # Histogram 3: Evaluation errors
        _print_eval_error_histogram(df)
    end

    # Summary table
    _print_summary_table(df, data)

    println()
end

"""
    analyze_quality(experiment_dir::String; verbose::Bool=true)

Convenience method that loads experiment and analyzes.
"""
function analyze_quality(experiment_dir::String; verbose::Bool=true)
    data = load_lv4d_experiment(experiment_dir)
    analyze_quality(data; verbose=verbose)
end

# ============================================================================
# Helper Functions
# ============================================================================

function _print_domain_stats(stats)
    frac_pct = stats.fraction_in * 100
    println()
    @printf("Domain membership: %d/%d (%.1f%%) critical points IN domain\n",
            stats.in_domain, stats.total, frac_pct)
    if stats.out_of_domain > 0
        @printf("  ⚠ %d points OUTSIDE domain bounds\n", stats.out_of_domain)
        for (i, v) in enumerate(stats.per_dim_violations)
            if v > 0
                @printf("    x%d: %d violations\n", i, v)
            end
        end
    end
end

function _print_degree_summary(df::DataFrame)
    hasproperty(df, :gradient_norm) || return
    hasproperty(df, :eval_error) || return

    gdf = groupby(df, :degree)
    summary = combine(gdf,
        nrow => :count,
        :gradient_norm => (x -> minimum(filter(!isnan, x))) => :grad_min,
        :gradient_norm => (x -> median(filter(!isnan, x))) => :grad_med,
        :gradient_norm => (x -> maximum(filter(!isnan, x))) => :grad_max,
        :eval_error => (x -> minimum(filter(!isnan, x))) => :err_min,
        :eval_error => (x -> maximum(filter(!isnan, x))) => :err_max
    )
    sort!(summary, :degree)

    println("\n" * "-"^70)
    println("Degree Summary")
    println("-"^70)

    headers = ["deg", "#CPs", "min ‖∇f‖", "med ‖∇f‖", "max ‖∇f‖", "min |f-w|", "max |f-w|"]
    ft = (v, _, j) -> begin
        if j >= 3 && v isa Number && !isnan(v)
            @sprintf("%.2e", v)
        else
            string(v)
        end
    end
    pretty_table(summary, header=headers, formatters=(ft,),
                alignment=:r, crop=:none, tf=tf_unicode_rounded)
end

function _print_distance_histogram(df::DataFrame)
    hasproperty(df, :dist_to_true) || return

    dists = filter(!isnan, df.dist_to_true)
    isempty(dists) && return

    println("\n" * "-"^70)
    println("||x - p*|| distance to true parameters (log₁₀)")
    println("-"^70)

    log_dists = log10.(max.(dists, 1e-16))
    nbins = max(5, min(15, length(log_dists) ÷ 3 + 1))

    # Text-based histogram
    _print_text_histogram(log_dists, nbins, "log₁₀(||x-p*||)")

    best_recovery = minimum(dists)
    @printf("  n=%d | best=%.2e | range=[%.2e, %.2e]\n",
            length(dists), best_recovery, minimum(dists), maximum(dists))
end

function _print_gradient_histogram(df::DataFrame)
    hasproperty(df, :gradient_norm) || return

    grads = filter(!isnan, df.gradient_norm)
    isempty(grads) && return

    GRADIENT_TOL = 1e-6

    println("\n" * "-"^70)
    println("||∇f(x)|| at polynomial CPs (log₁₀; valid if <-6)")
    println("-"^70)

    log_grads = log10.(max.(grads, 1e-16))
    nbins = max(5, min(15, length(log_grads) ÷ 3 + 1))

    _print_text_histogram(log_grads, nbins, "log₁₀(||∇f||)")

    valid_count = count(g -> g < GRADIENT_TOL, grads)
    @printf("  n=%d | range=[%.2e, %.2e] | %d valid (||∇f||<1e-6)\n",
            length(grads), minimum(grads), maximum(grads), valid_count)
end

function _print_eval_error_histogram(df::DataFrame)
    hasproperty(df, :eval_error) || return

    errs = filter(!isnan, df.eval_error)
    isempty(errs) && return

    println("\n" * "-"^70)
    println("|f(x) - w_d(x)| evaluation error (log₁₀; polynomial quality)")
    println("-"^70)

    log_errs = log10.(max.(errs, 1e-16))
    nbins = max(5, min(15, length(log_errs) ÷ 3 + 1))

    _print_text_histogram(log_errs, nbins, "log₁₀(|f-w|)")

    @printf("  n=%d | range=[%.2e, %.2e]\n",
            length(errs), minimum(errs), maximum(errs))
end

function _print_text_histogram(values::AbstractVector, nbins::Int, xlabel::String)
    n = length(values)
    min_val, max_val = extrema(values)
    bin_width = (max_val - min_val) / nbins

    for i in 1:nbins
        lo = min_val + (i-1) * bin_width
        hi = min_val + i * bin_width
        count = i == nbins ? sum(lo .<= values .<= hi) : sum(lo .<= values .< hi)
        pct = count / n * 100
        bar = repeat("█", min(40, round(Int, pct * 40 / 100 * 2)))
        @printf("  [%+6.2f,%+6.2f) %4d (%5.1f%%) %s\n", lo, hi, count, pct, bar)
    end
end

function _print_summary_table(df::DataFrame, data::LV4DExperimentData)
    println("\n" * "-"^70)
    println("Critical Points Summary (sorted by distance to p_true)")
    println("-"^70)
    println("Column legend:")
    println("  deg      = Polynomial degree")
    println("  f(x)     = Objective value at critical point")
    println("  ||x-p*|| = Euclidean distance to true parameters p_true")
    println("  in?      = ✓ if point is within domain bounds, ✗ if outside")
    println("  ||∇f||   = Gradient norm of f at x (small = true CP of f)")
    println("  |f-w|    = |f(x) - w_d(x)| polynomial approximation error at x")
    println()

    # Add in_domain indicator column
    x_cols = [Symbol("x$i") for i in 1:data.dim]
    if all(c -> hasproperty(df, c), x_cols)
        in_domain_col = Bool[]
        for row in eachrow(df)
            point = [row[c] for c in x_cols]
            in_bounds = all(abs.(point .- data.p_center) .<= data.domain_size)
            push!(in_domain_col, in_bounds)
        end
        df = copy(df)  # Don't modify original
        df[!, :in_domain] = in_domain_col
    end

    # Build table columns
    cols_to_show = [:degree]
    hasproperty(df, :z) && push!(cols_to_show, :z)
    hasproperty(df, :dist_to_true) && push!(cols_to_show, :dist_to_true)
    hasproperty(df, :in_domain) && push!(cols_to_show, :in_domain)
    hasproperty(df, :gradient_norm) && push!(cols_to_show, :gradient_norm)
    hasproperty(df, :eval_error) && push!(cols_to_show, :eval_error)
    hasproperty(df, :critical_type) && push!(cols_to_show, :critical_type)

    # Sort by distance to truth
    sort_cols = hasproperty(df, :dist_to_true) ? [:dist_to_true, :degree] : [:degree]
    sorted_df = sort(df, sort_cols)
    table_df = select(sorted_df, cols_to_show)

    # Column headers
    header_map = Dict(
        :degree => "deg",
        :z => "f(x)",
        :dist_to_true => "||x-p*||",
        :in_domain => "in?",
        :gradient_norm => "||∇f||",
        :eval_error => "|f-w|",
        :critical_type => "type"
    )
    headers = [get(header_map, c, string(c)) for c in cols_to_show]

    # Formatter
    ft = (v, _, j) -> begin
        col = cols_to_show[j]
        if col in [:z, :dist_to_true, :gradient_norm, :eval_error] && v isa Number && !isnan(v)
            @sprintf("%.2e", v)
        elseif col == :in_domain && v isa Bool
            v ? "✓" : "✗"
        else
            string(v)
        end
    end

    pretty_table(table_df, header=headers, formatters=(ft,),
                 alignment=:r, crop=:none, tf=tf_unicode_rounded)
end
