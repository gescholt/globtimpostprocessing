"""
Aggregate domain × degree sweep analysis.

Analyzes results from domain_degree_sweep.sh and identifies optimal configurations.
"""

# ============================================================================
# Main Analysis Function
# ============================================================================

"""
    analyze_sweep(results_dir::String, filter::ExperimentFilter; kwargs...)

Analyze sweep results using ExperimentFilter for experiment selection.

# Arguments
- `results_dir::String`: Path to results directory
- `filter::ExperimentFilter`: Filter specification for experiment selection
- `verbose::Bool=false`: Whether to show detailed analysis
- `save_output::Bool=true`: Whether to save CSV summary files
- `export_csv::Bool=false`: Whether to export data for plotting
- `top_l2::Union{Int, Nothing}=nothing`: Show top N configurations by lowest L2 error

# Example
```julia
# All GN=8 experiments with degree 4-12
filter = ExperimentFilter(gn=fixed(8), degree=sweep(4, 12))
analyze_sweep(results_root, filter; verbose=true)
```
"""
function analyze_sweep(results_dir::String, filter::ExperimentFilter;
                       verbose::Bool=false, save_output::Bool=true,
                       export_csv::Bool=false, top_l2::Union{Int, Nothing}=nothing)
    isdir(results_dir) || error("Results directory not found: $results_dir")

    # Use query interface to find matching experiments
    exp_dirs = query_experiments(results_dir, filter)

    if isempty(exp_dirs)
        println("No experiments match filter: $(format_filter(filter))")
        return DataFrame()
    end

    # Load results
    all_results = DataFrame[]
    for exp_dir in exp_dirs
        result = _load_experiment_results(exp_dir)
        if result !== nothing
            push!(all_results, result)
        end
    end

    if isempty(all_results)
        println("No valid results found!")
        return DataFrame()
    end

    df = vcat(all_results...)

    # Apply additional DataFrame-level filtering based on filter spec
    df_sweep = _apply_filter_to_dataframe(df, filter)
    summary = _aggregate_results(df_sweep)

    # Print compact header
    _print_filter_based_header(results_dir, df_sweep, filter)

    # Print compact summary table using PrettyTables
    _print_summary_table_compact(summary)

    # Print metric key
    _print_metric_key()

    # Print top N by L2 if requested
    if top_l2 !== nothing
        _print_top_experiments_by_l2(summary; limit=top_l2)
    end

    # Save outputs
    output_dir = nothing
    if save_output
        output_dir = _save_sweep_outputs(results_dir, summary, df_sweep)
        @debug "Saved: $(output_dir)/domain_degree_summary.csv"
    end

    # Export CSV for plotting
    if export_csv
        _export_convergence_csv(results_dir, df_sweep)
    end

    # Verbose mode: show detailed analysis
    if verbose
        println()
        println("Detailed Analysis:")
        println()
        _print_configurations(df)
        _analyze_distributions(exp_dirs)
        _print_optimal_configurations(summary)
        _print_domain_threshold_analysis(summary)
    end

    return summary
end

"""
    analyze_sweep(results_dir::String; verbose::Bool=false, save_output::Bool=true,
                  domain_max::Float64=0.0050, degree_min::Int=4, degree_max::Int=10,
                  export_csv::Bool=false, top_l2::Union{Int, Nothing}=nothing)

Analyze domain × degree sweep results.

# Arguments
- `results_dir::String`: Path to results directory (or single experiment)
- `verbose::Bool=false`: Whether to show gradient/objective distributions and detailed analysis
- `save_output::Bool=true`: Whether to save CSV summary files
- `domain_max::Float64=0.0050`: Maximum domain size to include
- `degree_min::Int=4`: Minimum polynomial degree to include
- `degree_max::Int=10`: Maximum polynomial degree to include
- `export_csv::Bool=false`: Whether to export data for plotting
- `top_l2::Union{Int, Nothing}=nothing`: Show top N configurations by lowest L2 error

# Returns
Summary DataFrame with aggregated statistics per (GN, domain, degree).
"""
function analyze_sweep(results_dir::String; verbose::Bool=false, save_output::Bool=true,
                       domain_max::Float64=0.0050, degree_min::Int=4, degree_max::Int=10,
                       export_csv::Bool=false, top_l2::Union{Int, Nothing}=nothing)
    isdir(results_dir) || error("Results directory not found: $results_dir")

    # Handle single experiment vs sweep directory
    if is_single_experiment(results_dir)
        exp_dirs = [results_dir]
    else
        exp_dirs = find_experiments(results_dir)
    end

    # Load all results (silent)
    all_results = DataFrame[]
    for exp_dir in exp_dirs
        result = _load_experiment_results(exp_dir)
        if result !== nothing
            push!(all_results, result)
        end
    end

    if isempty(all_results)
        println("No valid results found!")
        return DataFrame()
    end

    df = vcat(all_results...)

    # Filter and aggregate (silent unless verbose)
    df_sweep = _filter_sweep_results_silent(df;
        domain_max=domain_max,
        degree_min=degree_min,
        degree_max=degree_max
    )
    summary = _aggregate_results(df_sweep)

    # Print compact header
    _print_compact_header(results_dir, df_sweep, domain_max, degree_min, degree_max)

    # Print compact summary table using PrettyTables
    _print_summary_table_compact(summary)

    # Print metric key (legend with precise definitions)
    _print_metric_key()

    # Print top N by L2 if requested
    if top_l2 !== nothing
        _print_top_experiments_by_l2(summary; limit=top_l2)
    end

    # Save outputs (silent in default mode)
    output_dir = nothing
    if save_output
        output_dir = _save_sweep_outputs(results_dir, summary, df_sweep)
        @debug "Saved: $(output_dir)/domain_degree_summary.csv"
    end

    # Export CSV for plotting
    if export_csv
        _export_convergence_csv(results_dir, df_sweep)
    end

    # Verbose mode: show detailed analysis
    if verbose
        println()
        println("Detailed Analysis:")
        println()

        # Show available configurations
        _print_configurations(df)

        # Filter info
        _print_filter_info(df_sweep, domain_max, degree_min, degree_max)

        # Analyze gradient and objective distributions
        _analyze_distributions(exp_dirs)

        # Find and print optimal configurations
        _print_optimal_configurations(summary)

        # Domain threshold analysis
        _print_domain_threshold_analysis(summary)
    end

    return summary
end

# ============================================================================
# Helper Functions
# ============================================================================

function _load_experiment_results(exp_dir::String)::Union{DataFrame, Nothing}
    results_file = joinpath(exp_dir, "results_summary.json")
    config_file = joinpath(exp_dir, "experiment_config.json")

    isfile(results_file) || return nothing

    try
        results = JSON.parsefile(results_file)
        config = isfile(config_file) ? JSON.parsefile(config_file) : Dict()

        dirname = basename(exp_dir)
        params = parse_experiment_name(dirname)
        params === nothing && return nothing

        rows = DataFrame[]
        for r in results
            get(r, "success", false) || continue

            # Handle L2_norm
            l2_norm = get(r, "L2_norm", NaN)
            if (l2_norm isa Number && isnan(l2_norm)) || l2_norm === nothing
                orthant_stats = get(r, "orthant_stats", nothing)
                if orthant_stats !== nothing && !isempty(orthant_stats)
                    orthant_l2s = [get(os, "L2_norm", NaN) for os in orthant_stats]
                    valid_l2s = filter(!isnan, orthant_l2s)
                    l2_norm = isempty(valid_l2s) ? NaN : maximum(valid_l2s)
                end
            end

            # Handle critical_points
            crit_pts = get(r, "critical_points", nothing)
            if crit_pts === nothing
                crit_pts = get(r, "total_critical_points", 0)
            end

            row = DataFrame(
                domain = params.domain,
                degree = get(r, "degree", 0),
                seed = something(params.seed, get(config, "seed", 0)),
                GN = params.GN,
                is_subdivision = params.is_subdivision,
                L2_norm = Float64(l2_norm isa Number ? l2_norm : NaN),
                condition_number = parse_condition_number(get(r, "condition_number", NaN)),
                critical_points = crit_pts,
                gradient_valid_rate = get(r, "gradient_valid_rate", 0.0),
                gradient_valid_count = get(r, "gradient_valid_count", 0),
                mean_gradient_norm = get(r, "mean_gradient_norm", NaN),
                min_gradient_norm = get(r, "min_gradient_norm", NaN),
                recovery_error = get(r, "recovery_error", NaN),
                hessian_minima = get(r, "hessian_minima", 0),
                hessian_saddle = get(r, "hessian_saddle", 0),
                hessian_degenerate = get(r, "hessian_degenerate", 0),
                computation_time = get(r, "computation_time", NaN),
                experiment_dir = dirname
            )
            push!(rows, row)
        end

        return isempty(rows) ? nothing : vcat(rows...)
    catch e
        @debug "Failed to load results from $exp_dir: $e"
        return nothing
    end
end

function _print_configurations(df::DataFrame)
    println("Available configurations:")
    gn_values = sort(unique(df.GN))
    domain_values = sort(unique(df.domain))
    degree_values = sort(unique(df.degree))
    println("  GN: $gn_values")
    println("  Domains: $domain_values")
    println("  Degrees: $degree_values")
    println()
end

# ============================================================================
# Compact Output Functions (Default Mode)
# ============================================================================

"""
    _print_compact_header(results_dir, df_sweep, domain_max, degree_min, degree_max)

Print a compact header explaining the problem and data.
"""
function _print_compact_header(_results_dir::String, df_sweep::DataFrame,
                               domain_max::Float64, degree_min::Int, degree_max::Int)
    println("LV4D Parameter Recovery Analysis")
    println()

    gn_str = join(sort(unique(df_sweep.GN)), ",")
    println("Filter: GN∈{$gn_str}, domain≤$domain_max, degree∈[$degree_min,$degree_max]")
    println()
end

"""
    _print_summary_table_compact(summary)

Print a compact summary table using PrettyTables.
"""
function _print_summary_table_compact(summary::DataFrame)
    nrow(summary) == 0 && return

    # Build display columns
    gn_col = summary.GN
    domain_col = [@sprintf("%.4f", d) for d in summary.domain]
    deg_col = summary.degree
    success_col = [@sprintf("%.0f%%", r * 100) for r in summary.success_rate]
    rec_col = [isnan(r) ? "-" : @sprintf("%.2f%%", r * 100) for r in summary.mean_recovery]
    l2_col = [isnan(l) ? "-" : @sprintf("%.2f", l) for l in summary.mean_L2]

    # Build display DataFrame (no #exp column - implementation detail)
    display_df = DataFrame(
        GN = gn_col,
        Domain = domain_col,
        Deg = deg_col,
        Success = success_col,
        RecErr = rec_col,
        L2 = l2_col
    )

    # Print using PrettyTables with unicode rounded theme
    pretty_table(display_df;
        header = ["GN", "Domain", "Deg", "Success", "RecErr", "L2"],
        alignment = [:r, :r, :r, :r, :r, :r],
        crop = :none,
        tf = tf_unicode_rounded
    )
end

"""
    _print_metric_key()

Print a compact metric key explaining the columns with precise definitions.
"""
function _print_metric_key()
    println()
    println("Legend: Success = recovery<5%, RecErr = ‖p̂-p*‖/‖p*‖×100, L2 = ‖f-wₐ‖_L²")
end

"""
    _print_summary_footer(summary::DataFrame)

Print a summary line at the bottom showing key statistics.
"""
function _print_summary_footer(summary::DataFrame)
    n_configs = nrow(summary)
    n_experiments = sum(summary.n_seeds)

    # Find best L2
    valid_l2 = filter(row -> !isnan(row.mean_L2), summary)
    if nrow(valid_l2) > 0
        best_idx = argmin(valid_l2.mean_L2)
        best_row = valid_l2[best_idx, :]
        best_l2 = round(best_row.mean_L2, digits=2)
        best_domain = best_row.domain
        println()
        @printf("Summary: %d experiments, %d configurations, best L2=%.2f at domain=%.4f\n",
                n_experiments, n_configs, best_l2, best_domain)
    else
        println()
        @printf("Summary: %d experiments, %d configurations\n", n_experiments, n_configs)
    end
end

"""
    _print_top_experiments_by_l2(summary::DataFrame; limit::Int=20)

Print the top N configurations ranked by lowest L2 approximation error.
"""
function _print_top_experiments_by_l2(summary::DataFrame; limit::Int=20)
    # Filter out rows with NaN L2 values
    valid = filter(row -> !isnan(row.mean_L2), summary)

    if nrow(valid) == 0
        println("\nNo valid L2 data available for ranking.")
        return
    end

    # Sort by L2 (ascending = best first)
    sorted = sort(valid, :mean_L2)
    top_n = first(sorted, min(limit, nrow(sorted)))

    # Build display columns (no #exp column - implementation detail)
    gn_col = top_n.GN
    domain_col = [@sprintf("%.4f", d) for d in top_n.domain]
    deg_col = top_n.degree
    l2_col = [@sprintf("%.2f", l) for l in top_n.mean_L2]
    success_col = [@sprintf("%.0f%%", r * 100) for r in top_n.success_rate]

    display_df = DataFrame(
        GN = gn_col,
        Domain = domain_col,
        Deg = deg_col,
        L2 = l2_col,
        Success = success_col
    )

    # Use PrettyTables title parameter instead of decorative banner
    println()
    pretty_table(display_df;
        header = ["GN", "Domain", "Deg", "L2", "Success"],
        alignment = [:r, :r, :r, :r, :r],
        crop = :none,
        tf = tf_unicode_rounded,
        title = @sprintf("Top %d Configurations by Lowest L2 Error", min(limit, nrow(sorted)))
    )
end

"""
    _filter_sweep_results_silent(df; domain_max, degree_min, degree_max)

Filter sweep results without printing (for compact mode).
"""
function _filter_sweep_results_silent(df::DataFrame;
                                      domain_max::Float64=0.0050,
                                      degree_min::Int=4,
                                      degree_max::Int=10)::DataFrame
    sweep_filter = (df.domain .<= domain_max) .&
                   (df.degree .>= degree_min) .&
                   (df.degree .<= degree_max)
    df_sweep = df[sweep_filter, :]

    # If no results, use all data
    if nrow(df_sweep) == 0
        df_sweep = df
    end

    return df_sweep
end

"""
    _apply_filter_to_dataframe(df::DataFrame, filter::ExperimentFilter) -> DataFrame

Apply ExperimentFilter to a DataFrame of results.
"""
function _apply_filter_to_dataframe(df::DataFrame, filter::ExperimentFilter)::DataFrame
    mask = trues(nrow(df))

    # Apply GN filter
    if filter.gn !== nothing
        if filter.gn isa FixedValue
            mask .&= df.GN .== filter.gn.value
        elseif filter.gn isa SweepRange
            mask .&= (df.GN .>= filter.gn.min) .& (df.GN .<= filter.gn.max)
        end
    end

    # Apply degree filter
    if filter.degree !== nothing
        if filter.degree isa FixedValue
            mask .&= df.degree .== filter.degree.value
        elseif filter.degree isa SweepRange
            mask .&= (df.degree .>= filter.degree.min) .& (df.degree .<= filter.degree.max)
        end
    end

    # Apply domain filter
    if filter.domain !== nothing
        if filter.domain isa FixedValue
            mask .&= df.domain .== filter.domain.value
        elseif filter.domain isa SweepRange
            mask .&= (df.domain .>= filter.domain.min) .& (df.domain .<= filter.domain.max)
        end
    end

    # Apply seed filter
    if filter.seed !== nothing && hasproperty(df, :seed)
        if filter.seed isa FixedValue
            mask .&= df.seed .== filter.seed.value
        elseif filter.seed isa SweepRange
            mask .&= (df.seed .>= filter.seed.min) .& (df.seed .<= filter.seed.max)
        end
    end

    df_filtered = df[mask, :]

    # If no results, return all data
    if nrow(df_filtered) == 0
        @debug "No results match filter, returning all data"
        return df
    end

    return df_filtered
end

"""
    _print_filter_based_header(results_dir, df_sweep, filter)

Print header for filter-based analysis.
"""
function _print_filter_based_header(_results_dir::String, df_sweep::DataFrame, filter::ExperimentFilter)
    println("LV4D Parameter Recovery Analysis")
    println()
    println("Filter: $(format_filter(filter))")
    println("Matched: $(nrow(df_sweep)) experiment-degree combinations")
    println()
end

"""
    _print_filter_info(df_sweep, domain_max, degree_min, degree_max)

Print filter information (for verbose mode).
"""
function _print_filter_info(df_sweep::DataFrame, domain_max::Float64,
                           degree_min::Int, degree_max::Int)
    println("Filter: domain ≤ $(domain_max), degree ∈ [$degree_min, $degree_max]")
    println("Sweep results: $(nrow(df_sweep)) experiments")
    println()
end

"""
    _filter_sweep_results(df::DataFrame; domain_max, degree_min, degree_max)

Filter sweep results to specified domain and degree ranges.
"""
function _filter_sweep_results(df::DataFrame;
                              domain_max::Float64=0.0050,
                              degree_min::Int=4,
                              degree_max::Int=10)::DataFrame
    sweep_filter = (df.domain .<= domain_max) .&
                   (df.degree .>= degree_min) .&
                   (df.degree .<= degree_max)
    df_sweep = df[sweep_filter, :]

    if nrow(df_sweep) == 0
        println("No results with domain <= $(domain_max), degree ∈ [$degree_min, $degree_max]")
        println("Using all results instead")
        df_sweep = df
    else
        println("Filter: domain ≤ $(domain_max), degree ∈ [$degree_min, $degree_max]")
    end

    println("Sweep results: $(nrow(df_sweep)) experiments")
    println()
    return df_sweep
end

function _aggregate_results(df::DataFrame)::DataFrame
    summary = combine(
        groupby(df, [:GN, :domain, :degree]),
        :L2_norm => mean => :mean_L2,
        :L2_norm => std => :std_L2,
        :gradient_valid_rate => mean => :mean_grad_valid,
        :gradient_valid_rate => std => :std_grad_valid,
        :recovery_error => mean => :mean_recovery,
        :recovery_error => std => :std_recovery,
        :recovery_error => (x -> mean(x .< 0.05)) => :success_rate,
        :hessian_minima => mean => :mean_minima,
        :critical_points => mean => :mean_crit_pts,
        :computation_time => mean => :mean_time,
        nrow => :n_seeds
    )
    sort!(summary, [:GN, :domain, :degree])
    return summary
end

function _print_summary_table(summary::DataFrame)
    println("Summary: Mean metrics per (GN, domain, degree)")
    println()

    @printf("%4s %8s %4s %9s %8s %8s %8s %6s %4s\n",
            "GN", "Domain", "Deg", "L2_norm", "∇Valid%", "RecErr%", "Recov<5%", "#CPs", "#exp")
    println("-"^80)

    for row in eachrow(summary)
        l2_str = isnan(row.mean_L2) ? "      -" : @sprintf("%9.2f", row.mean_L2)
        grad_str = @sprintf("%7.1f%%", row.mean_grad_valid * 100)
        rec_str = isnan(row.mean_recovery) ? "      -" : @sprintf("%7.2f%%", row.mean_recovery * 100)
        success_str = @sprintf("%7.1f%%", row.success_rate * 100)
        crit_str = @sprintf("%6.1f", row.mean_crit_pts)

        # Highlight good results
        highlight = ""
        if row.mean_L2 < 0.1 && row.mean_grad_valid > 0.5 && row.success_rate > 0.8
            highlight = " ***"
        elseif row.mean_L2 < 1.0 && row.success_rate > 0.5
            highlight = " *"
        end

        @printf("%4d %s %4d %s %s %s %s %s %4d%s\n",
                row.GN, format_domain(row.domain), row.degree, l2_str, grad_str,
                rec_str, success_str, crit_str, row.n_seeds, highlight)
    end
    println()
    println("Highlights: *** = excellent (L2<0.1, ∇Valid>50%, Recov<5% in >80%)")
    println("            *   = good (L2<1.0, Recov<5% in >50%)")
    println()
end

function _save_sweep_outputs(results_dir::String, summary::DataFrame, df_sweep::DataFrame)
    output_dir = joinpath(results_dir, "sweep_analysis")
    mkpath(output_dir)

    summary_file = joinpath(output_dir, "domain_degree_summary.csv")
    CSV.write(summary_file, summary)

    raw_file = joinpath(output_dir, "all_sweep_results.csv")
    CSV.write(raw_file, df_sweep)

    return output_dir
end

function _analyze_distributions(exp_dirs::Vector{String})
    all_metrics = DataFrame[]
    for exp_dir in exp_dirs
        metrics_df = load_critical_point_metrics(exp_dir)
        if metrics_df !== nothing
            push!(all_metrics, metrics_df)
        end
    end

    if !isempty(all_metrics)
        metrics_df = vcat(all_metrics...)
        _analyze_gradient_distribution(metrics_df)
        println()
        _analyze_objective_distribution(metrics_df)
        println()
    end
end

function _analyze_gradient_distribution(metrics_df::DataFrame)
    "gradient_norm" in names(metrics_df) || return

    grads = metrics_df.gradient_norm
    valid_grads = filter(x -> !isnan(x) && x > 0, grads)
    n_valid = length(valid_grads)

    println("Gradient Norm Distribution ($n_valid points):")
    println()

    n_valid == 0 && return

    # Percentiles
    print("Percentiles:")
    print_percentiles(valid_grads, "gradient_norm")
    println()

    # Histogram
    print_log_histogram(valid_grads, "Log-scale histogram:")
    println()

    # Per-domain breakdown
    println("By domain (median gradient norm):")
    for domain in sort(unique(metrics_df.domain))
        domain_grads = filter(x -> !isnan(x) && x > 0,
                             metrics_df[metrics_df.domain .== domain, :gradient_norm])
        if !isempty(domain_grads)
            med = quantile(domain_grads, 0.5)
            min_g = minimum(domain_grads)
            @printf("  domain=%.4f: median=%.2e, min=%.2e (%d points)\n",
                    domain, med, min_g, length(domain_grads))
        end
    end
    println()

    # Threshold analysis
    println("Gradient validation threshold analysis:")
    @printf("  Current (1e-6):  %d/%d pass (%.1f%%)\n",
            sum(valid_grads .< 1e-6), n_valid, 100 * sum(valid_grads .< 1e-6) / n_valid)
    @printf("  Relaxed (1e-3):  %d/%d pass (%.1f%%)\n",
            sum(valid_grads .< 1e-3), n_valid, 100 * sum(valid_grads .< 1e-3) / n_valid)
    @printf("  Relaxed (1e+2):  %d/%d pass (%.1f%%)\n",
            sum(valid_grads .< 1e2), n_valid, 100 * sum(valid_grads .< 1e2) / n_valid)
end

function _analyze_objective_distribution(metrics_df::DataFrame)
    "z" in names(metrics_df) || return

    z_vals = metrics_df.z
    valid_z = filter(x -> !isnan(x) && isfinite(x) && x > 0, z_vals)
    n_valid = length(valid_z)

    println("Objective Value Distribution ($n_valid points):")
    println()

    n_valid == 0 && return

    # Percentiles
    print("Percentiles:")
    print_percentiles(valid_z, "objective")
    println()

    # Histogram
    print_log_histogram(valid_z, "Log-scale histogram:")
    println()

    # Per-domain breakdown
    println("By domain (median objective value):")
    for domain in sort(unique(metrics_df.domain))
        domain_z = filter(x -> !isnan(x) && isfinite(x) && x > 0,
                         metrics_df[metrics_df.domain .== domain, :z])
        if !isempty(domain_z)
            med = quantile(domain_z, 0.5)
            min_z = minimum(domain_z)
            @printf("  domain=%.4f: median=%.2e, min=%.2e (%d points)\n",
                    domain, med, min_z, length(domain_z))
        end
    end
    println()

    # Summary
    p_min = minimum(valid_z)
    println("Best critical points (lowest objective):")
    @printf("  Minimum f(x): %.4f\n", p_min)
    @printf("  Below 1.0:    %d/%d (%.1f%%)\n",
            sum(valid_z .< 1.0), n_valid, 100 * sum(valid_z .< 1.0) / n_valid)
    @printf("  Below 10.0:   %d/%d (%.1f%%)\n",
            sum(valid_z .< 10.0), n_valid, 100 * sum(valid_z .< 10.0) / n_valid)
end

function _print_optimal_configurations(summary::DataFrame)
    println("Optimal Configurations:")
    println()

    valid_l2 = summary[.!isnan.(summary.mean_L2), :]

    # Best L2
    if nrow(valid_l2) > 0
        best_l2_idx = argmin(valid_l2.mean_L2)
        best_l2 = valid_l2[best_l2_idx, :]
        println("Best polynomial approximation (lowest L2 error):")
        println("  GN=$(best_l2.GN), domain=$(best_l2.domain), degree=$(best_l2.degree): " *
                "L2=$(round(best_l2.mean_L2, digits=3))")
    else
        println("Best polynomial approximation: No valid results")
    end
    println()

    # Best gradient validation
    best_grad_idx = argmax(summary.mean_grad_valid)
    best_grad = summary[best_grad_idx, :]
    println("Best gradient validation (highest % of true critical points):")
    println("  GN=$(best_grad.GN), domain=$(best_grad.domain), degree=$(best_grad.degree): " *
            "$(round(best_grad.mean_grad_valid * 100, digits=1))% with ||∇f||<1e-6")
    println()

    # Best recovery success rate
    best_success_idx = argmax(summary.success_rate)
    best_success = summary[best_success_idx, :]
    println("Best parameter recovery (highest % achieving <5% error):")
    println("  GN=$(best_success.GN), domain=$(best_success.domain), degree=$(best_success.degree): " *
            "$(round(best_success.success_rate * 100, digits=1))% of experiments")
    println()

    # Excellent configurations
    excellent = summary[(summary.mean_L2 .< 0.1) .&
                       (summary.mean_grad_valid .> 0.5) .&
                       (summary.success_rate .> 0.8), :]
    if nrow(excellent) > 0
        println("EXCELLENT configurations (L2<0.1, ∇Valid>50%, Recovery<5% in >80% of runs):")
        for row in eachrow(excellent)
            println("  GN=$(row.GN), domain=$(row.domain), degree=$(row.degree): " *
                    "L2=$(round(row.mean_L2, digits=3)), " *
                    "∇Valid=$(round(row.mean_grad_valid * 100, digits=1))%, " *
                    "RecovSuccess=$(round(row.success_rate * 100, digits=1))%")
        end
    else
        println("No configurations meet all excellent criteria")

        good_grad = summary[summary.mean_grad_valid .> 0.1, :]
        if nrow(good_grad) > 0
            println("\nConfigurations with >10% gradient validation:")
            for row in eachrow(good_grad)
                println("  GN=$(row.GN), domain=$(row.domain), degree=$(row.degree): " *
                        "L2=$(round(row.mean_L2, digits=3)), " *
                        "GradValid=$(round(row.mean_grad_valid * 100, digits=1))%")
            end
        else
            println("\nNo configurations achieved >10% gradient validation.")
            println("Consider: smaller domains (< 0.01) or higher GN or higher degrees")
        end
    end
    println()
end

function _print_domain_threshold_analysis(summary::DataFrame)
    println("Domain Threshold Analysis (by GN):")
    println()

    for gn in sort(unique(summary.GN))
        println("GN=$gn:")
        @printf("  %8s  %3s  %8s  %6s  %6s\n", "Domain", "Deg", "L2", "Grad%", "Succ%")
        @printf("  %8s  %3s  %8s  %6s  %6s\n", "--------", "---", "--------", "------", "------")

        gn_results = summary[summary.GN .== gn, :]

        for domain in sort(unique(gn_results.domain))
            domain_results = gn_results[gn_results.domain .== domain, :]
            nrow(domain_results) == 0 && continue

            best_idx = argmax(domain_results.success_rate)
            best = domain_results[best_idx, :]

            @printf("  %8.4f  %3d  %8.2f  %5.1f%%  %5.1f%%\n",
                    domain, best.degree, best.mean_L2,
                    best.mean_grad_valid * 100, best.success_rate * 100)
        end
        println()
    end
end

# ============================================================================
# CSV Export for Plotting
# ============================================================================

"""
    _export_convergence_csv(results_dir::String, df_sweep::DataFrame)

Export sweep data in a format suitable for plotting convergence analysis.

CSV Schema:
- domain: Domain half-width
- degree: Polynomial degree
- GN: Grid nodes
- seed: Random seed
- L2_norm: ||f - w_d||_L2 (polynomial approximation error)
- recovery_error: ||p_best - p_true|| / ||p_true||
- gradient_valid_rate: Fraction with ||∇f|| < 1e-6
- critical_points: Number of CPs found
- success: recovery_error < 0.05
"""
function _export_convergence_csv(results_dir::String, df_sweep::DataFrame)
    output_dir = joinpath(results_dir, "sweep_analysis")
    mkpath(output_dir)

    # Create plotting-friendly DataFrame
    df_plot = DataFrame(
        domain = df_sweep.domain,
        degree = df_sweep.degree,
        GN = df_sweep.GN,
        seed = df_sweep.seed,
        L2_norm = df_sweep.L2_norm,
        recovery_error = df_sweep.recovery_error,
        gradient_valid_rate = df_sweep.gradient_valid_rate,
        critical_points = df_sweep.critical_points,
        success = df_sweep.recovery_error .< 0.05
    )

    output_file = joinpath(output_dir, "lv4d_convergence_data.csv")
    CSV.write(output_file, df_plot)

    @debug "Exported: $output_file"

    return output_file
end
