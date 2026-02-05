"""
Critical point quality analysis for single LV4D experiments.

Displays histograms and statistics for:
1. Distance to true parameters ||x - p*||
2. Gradient norms ||∇f(x)||
3. Evaluation errors |f(x) - w_d(x)|
"""

# ============================================================================
# Constants
# ============================================================================

"""Gradient norm tolerance for considering a point a valid critical point."""
const GRADIENT_VALIDATION_TOL = 1e-6

# ============================================================================
# Main Analysis Function
# ============================================================================

"""
    analyze_quality(data::LV4DExperimentData)

Analyze critical point quality for a single experiment.

# Output Structure
1. Header with experiment info and config
2. SUMMARY section with key findings
3. TOP CANDIDATES table (sorted by distance to p_true)
4. STATUS line indicating success/failure

# Arguments
- `data::LV4DExperimentData`: Loaded experiment data
"""
function analyze_quality(data::LV4DExperimentData)
    # --- Header ---
    println()
    println("CRITICAL POINT ANALYSIS: $(basename(data.dir))")
    println("─" ^ min(70, 26 + length(basename(data.dir))))

    # Extract config from directory name
    params = parse_experiment_name(basename(data.dir))
    if params !== nothing
        if params.degree_min == params.degree_max
            @printf("Config: GN=%d, degree=%d, domain=%.2e\n", params.GN, params.degree_min, params.domain)
        else
            @printf("Config: GN=%d, degrees=%d-%d, domain=%.2e\n", params.GN, params.degree_min, params.degree_max, params.domain)
        end
    end
    @printf("True params: [%s]\n", join([@sprintf("%.3f", p) for p in data.p_true], ", "))

    if data.critical_points === nothing || nrow(data.critical_points) == 0
        println()
        println("No critical points found in this experiment.")
        return
    end

    df = data.critical_points

    # --- SUMMARY section ---
    println()
    println("SUMMARY")
    _print_quality_summary(df, data)

    # --- TOP CANDIDATES table ---
    println()
    _print_top_candidates(df, data)

    # --- STATUS line ---
    _print_quality_status(df, data)

    println()
end

"""
    analyze_quality(experiment_dir::String)

Convenience method that loads experiment and analyzes.
"""
function analyze_quality(experiment_dir::String)
    data = load_lv4d_experiment(experiment_dir)
    analyze_quality(data)
end

# ============================================================================
# New Output Functions
# ============================================================================

"""
    _print_quality_summary(df, data)

Print the SUMMARY section with key findings.
"""
function _print_quality_summary(df::DataFrame, data::LV4DExperimentData)
    n_total = nrow(df)

    # Count points in domain using shared function
    membership = analyze_domain_membership(df, data.p_center, data.domain_size)
    n_in_domain = membership === nothing ? 0 : membership.in_domain
    n_outside = n_total - n_in_domain

    @printf("• Found: %d critical points (%d in domain, %d outside)\n",
            n_total, n_in_domain, n_outside)

    # Best recovery error
    if hasproperty(df, :dist_to_true)
        valid_dists = filter(!isnan, df.dist_to_true)
        if !isempty(valid_dists)
            best_dist = minimum(valid_dists)
            # Convert to percentage relative error
            p_true_norm = norm(data.p_true)
            best_pct = (best_dist / p_true_norm) * 100
            @printf("• Best recovery: %.1f%% error (distance %.2e)\n", best_pct, best_dist)
        end
    end

    # Gradient validation
    if hasproperty(df, :gradient_norm)
        valid_grads = filter(!isnan, df.gradient_norm)
        n_valid = count(g -> g < GRADIENT_VALIDATION_TOL, valid_grads)
        @printf("• Gradient validation: %d/%d (%.0f%%) have ‖∇f‖ < 1e-6\n",
                n_valid, length(valid_grads), 100 * n_valid / max(1, length(valid_grads)))
    end
end

"""
    _print_top_candidates(df, data; limit=5)

Print TOP CANDIDATES table sorted by distance to true parameters.
"""
function _print_top_candidates(df::DataFrame, data::LV4DExperimentData; limit::Int=5)
    println("TOP $(limit) CANDIDATES (sorted by distance to p_true)")

    # Need dist_to_true column
    hasproperty(df, :dist_to_true) || return

    # Sort by distance
    sorted_df = sort(df, :dist_to_true)
    top_df = first(sorted_df, min(limit, nrow(sorted_df)))

    # Compute in_domain for each point
    x_cols = [Symbol("x$i") for i in 1:data.dim]
    in_domain_col = String[]
    if all(c -> hasproperty(top_df, c), x_cols)
        for row in eachrow(top_df)
            point = [row[c] for c in x_cols]
            in_bounds = all(abs.(point .- data.p_center) .<= data.domain_size)
            push!(in_domain_col, in_bounds ? "✓" : "✗")
        end
    else
        in_domain_col = fill("-", nrow(top_df))
    end

    # Build table columns
    p_true_norm = norm(data.p_true)
    dist_pct = [@sprintf("%.1f%%", (d / p_true_norm) * 100) for d in top_df.dist_to_true]

    # Objective value (z column)
    z_col = hasproperty(top_df, :z) ?
            [isnan(z) ? "-" : @sprintf("%.3f", z) for z in top_df.z] :
            fill("-", nrow(top_df))

    # Gradient norm
    grad_col = hasproperty(top_df, :gradient_norm) ?
               [isnan(g) ? "-" : @sprintf("%.0e", g) for g in top_df.gradient_norm] :
               fill("-", nrow(top_df))

    # Annotation for winner
    note_col = fill("", nrow(top_df))
    if nrow(top_df) > 0
        note_col[1] = "← WINNER"
    end

    display_df = DataFrame(
        :Rank => 1:nrow(top_df),
        :Distance => dist_pct,
        :fval => z_col,
        :grad => grad_col,
        :InDomain => in_domain_col,
        :Note => note_col
    )

    styled_table(display_df;
        header = ["#", "Distance", "f(x)", "‖∇f‖", "In?", ""],
        alignment = [:r, :r, :r, :r, :c, :l],
    )
end

"""
    _print_quality_status(df, data)

Print STATUS line indicating success/failure.
"""
function _print_quality_status(df::DataFrame, data::LV4DExperimentData)
    println()

    # Success threshold: 5% relative error
    SUCCESS_THRESHOLD = 0.05

    if !hasproperty(df, :dist_to_true)
        println("STATUS: ? - Unable to determine (no distance data)")
        return
    end

    valid_dists = filter(!isnan, df.dist_to_true)
    if isempty(valid_dists)
        println("STATUS: ? - No valid distance measurements")
        return
    end

    best_dist = minimum(valid_dists)
    p_true_norm = norm(data.p_true)
    best_rel_error = best_dist / p_true_norm

    if best_rel_error < SUCCESS_THRESHOLD
        @printf("STATUS: ✓ SUCCESS - Best candidate achieves < 5%% recovery error (%.1f%%)\n",
                best_rel_error * 100)
    else
        @printf("STATUS: ✗ FAILED - Best candidate has %.1f%% error (threshold: 5%%)\n",
                best_rel_error * 100)
    end
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
    styled_table(summary; header=headers, formatters=(ft,),
                alignment=:r)
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

    styled_table(table_df; header=headers, formatters=(ft,),
                 alignment=:r)
end

# ============================================================================
# Programmatic Summary (Returns data instead of printing)
# ============================================================================

"""
    get_quality_summary(data::LV4DExperimentData) -> NamedTuple

Get a structured summary of experiment quality metrics.

Returns a NamedTuple with:
- `total_cps`: Total critical points found
- `in_domain`: Critical points within domain bounds
- `best_recovery_error`: Minimum relative recovery error (%)
- `best_recovery_distance`: Minimum absolute distance to p_true
- `best_point`: Best candidate point coordinates
- `best_degree`: Degree that found the best point
- `gradient_valid_count`: Points with ||∇f|| < 1e-6
- `all_saddles`: True if all points are saddles (no minima)
- `success`: True if best recovery < 5%

# Example
```julia
data = load_lv4d_experiment(exp_path)
summary = get_quality_summary(data)
println("Best recovery: \$(summary.best_recovery_error)%")
```
"""
function get_quality_summary(data::LV4DExperimentData)
    if data.critical_points === nothing || nrow(data.critical_points) == 0
        return (
            total_cps = 0,
            in_domain = 0,
            best_recovery_error = NaN,
            best_recovery_distance = NaN,
            best_point = Float64[],
            best_degree = 0,
            gradient_valid_count = 0,
            all_saddles = true,
            success = false
        )
    end

    df = data.critical_points
    x_cols = [Symbol("x$i") for i in 1:data.dim]

    # Count in-domain using shared function
    membership = analyze_domain_membership(df, data.p_center, data.domain_size)
    n_in_domain = membership === nothing ? 0 : membership.in_domain

    # Best recovery
    best_dist = NaN
    best_error = NaN
    best_point = Float64[]
    best_degree = 0
    if hasproperty(df, :dist_to_true)
        best_idx = argmin(df.dist_to_true)
        best_dist = df.dist_to_true[best_idx]
        best_error = (best_dist / norm(data.p_true)) * 100
        best_degree = df.degree[best_idx]
        if all(c -> hasproperty(df, c), x_cols)
            best_point = [df[best_idx, c] for c in x_cols]
        end
    end

    # Gradient validation
    gradient_valid = 0
    if hasproperty(df, :gradient_norm)
        gradient_valid = count(g -> !isnan(g) && g < GRADIENT_VALIDATION_TOL, df.gradient_norm)
    end

    # Classification check
    all_saddles = sum(skipmissing(data.degree_results.hessian_minima)) == 0

    return (
        total_cps = nrow(df),
        in_domain = n_in_domain,
        best_recovery_error = best_error,
        best_recovery_distance = best_dist,
        best_point = best_point,
        best_degree = best_degree,
        gradient_valid_count = gradient_valid,
        all_saddles = all_saddles,
        success = best_error < 5.0
    )
end

"""
    get_quality_summary(experiment_dir::String) -> NamedTuple

Load experiment and return quality summary.
"""
function get_quality_summary(experiment_dir::String)
    data = load_lv4d_experiment(experiment_dir)
    return get_quality_summary(data)
end
