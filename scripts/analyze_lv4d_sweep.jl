#!/usr/bin/env julia
"""
Analyze Domain × Degree Sweep Results

Aggregates results from domain_degree_sweep.sh and identifies optimal configurations
for LV4D parameter estimation.

Usage:
    julia --project=globtimpostprocessing globtimpostprocessing/scripts/analyze_lv4d_sweep.jl [results_dir]

Arguments:
    results_dir: Path to lotka_volterra_4d results or single experiment directory

Output:
    - domain_degree_summary.csv: Aggregated metrics per (domain, degree)
    - Console report with optimal configurations

PE-01 Experiment Analysis - January 2026
"""

const SCRIPT_DIR = @__DIR__
const PROJECT_ROOT = abspath(joinpath(SCRIPT_DIR, ".."))

using Pkg
Pkg.activate(PROJECT_ROOT)

using DataFrames
using CSV
using JSON
using Statistics
using Printf
using Dates
using PrettyTables

# Parse experiment directory name to extract parameters
# Handles both old and new naming conventions:
#   Old: lv4d_GN12_deg4-8_domain0.0001_seed1_20260116_155210
#   New: lv4d_GN12_deg8_dom1.0e-4_seed1_20260116_155210_subdiv
function parse_experiment_name(dirname::String)
    # Pattern with seed - handles both old (domain) and new (dom) prefixes
    # Handles both deg4-8 (range) and deg8 (single) formats
    # Handles both decimal (0.001) and scientific (1.0e-3) domain values
    m = match(r"lv4d_GN(\d+)_deg(\d+)(?:-(\d+))?_dom(?:ain)?([\d.eE+-]+)_seed(\d+)_", dirname)
    if m !== nothing
        deg_min = parse(Int, m.captures[2])
        deg_max = m.captures[3] !== nothing ? parse(Int, m.captures[3]) : deg_min
        return (
            GN = parse(Int, m.captures[1]),
            degree_min = deg_min,
            degree_max = deg_max,
            domain = parse(Float64, m.captures[4]),
            seed = parse(Int, m.captures[5]),
            is_subdivision = endswith(dirname, "_subdiv")
        )
    end

    # Try pattern without seed
    m = match(r"lv4d_GN(\d+)_deg(\d+)(?:-(\d+))?_dom(?:ain)?([\d.eE+-]+)_", dirname)
    if m !== nothing
        deg_min = parse(Int, m.captures[2])
        deg_max = m.captures[3] !== nothing ? parse(Int, m.captures[3]) : deg_min
        return (
            GN = parse(Int, m.captures[1]),
            degree_min = deg_min,
            degree_max = deg_max,
            domain = parse(Float64, m.captures[4]),
            seed = nothing,
            is_subdivision = endswith(dirname, "_subdiv")
        )
    end

    return nothing
end

# Parse condition_number which may be "NaN" string or a number
function parse_condition_number(val)
    if val isa Number
        return Float64(val)
    elseif val isa String && lowercase(val) == "nan"
        return NaN
    else
        return NaN
    end
end

# Load critical point metrics (gradient_norm and z values) from CSV files
function load_critical_point_metrics(exp_dir::String)
    dirname = basename(exp_dir)
    params = parse_experiment_name(dirname)
    if params === nothing
        return nothing
    end

    # Find all critical_points_deg_*.csv files
    csv_files = filter(f -> startswith(f, "critical_points_deg_") && endswith(f, ".csv"),
                       readdir(exp_dir))

    if isempty(csv_files)
        return nothing
    end

    rows = DataFrame[]
    for csv_file in csv_files
        # Extract degree from filename: critical_points_deg_X.csv
        m = match(r"critical_points_deg_(\d+)\.csv", csv_file)
        if m === nothing
            continue
        end
        degree = parse(Int, m.captures[1])

        try
            df = CSV.read(joinpath(exp_dir, csv_file), DataFrame)
            has_grad = "gradient_norm" in names(df)
            has_z = "z" in names(df)

            if has_grad || has_z
                for i in 1:nrow(df)
                    push!(rows, DataFrame(
                        domain = params.domain,
                        degree = degree,
                        GN = params.GN,
                        gradient_norm = has_grad ? Float64(df.gradient_norm[i]) : NaN,
                        z = has_z ? Float64(df.z[i]) : NaN
                    ))
                end
            end
        catch e
            @debug "Failed to load $csv_file: $e"
        end
    end

    return isempty(rows) ? nothing : vcat(rows...)
end

# Create adaptive log-scale bins for histogram
function make_log_bins(values; n_bins=8)
    valid = filter(x -> x > 0 && isfinite(x), values)
    if isempty(valid)
        return [1e-6, 1e-4, 1e-2, 1e0, 1e2, 1e4, 1e6]
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

# Format bin label for log-scale histogram
function format_bin_label(lo, hi)
    if hi == Inf
        return @sprintf("[%.0e, ∞)", lo)
    else
        return @sprintf("[%.0e, %.0e)", lo, hi)
    end
end

# Analyze and print gradient norm distribution with adaptive binning
function analyze_gradient_distribution(metrics_df::DataFrame)
    if !("gradient_norm" in names(metrics_df))
        println("No gradient_norm column found.")
        return
    end

    grads = metrics_df.gradient_norm
    valid_grads = filter(x -> !isnan(x) && x > 0, grads)
    n_valid = length(valid_grads)

    println("="^80)
    println("GRADIENT NORM DISTRIBUTION ($n_valid critical points)")
    println("="^80)
    println()

    if n_valid == 0
        println("No valid gradient norms found.")
        return
    end

    # Percentiles
    sorted_grads = sort(valid_grads)
    p_min = minimum(sorted_grads)
    p25 = quantile(sorted_grads, 0.25)
    p50 = quantile(sorted_grads, 0.50)
    p75 = quantile(sorted_grads, 0.75)
    p_max = maximum(sorted_grads)

    println("Percentiles:")
    @printf("  min: %.2e    p25: %.2e    median: %.2e    p75: %.2e    max: %.2e\n",
            p_min, p25, p50, p75, p_max)
    println()

    # Adaptive log-scale histogram
    bins = make_log_bins(valid_grads)

    println("Log-scale histogram:")
    for i in 1:(length(bins)-1)
        count = sum(bins[i] .<= valid_grads .< bins[i+1])
        pct = count / n_valid * 100
        bar = repeat("█", min(50, round(Int, pct / 2)))
        label = format_bin_label(bins[i], bins[i+1])
        @printf("  %-18s %4d (%5.1f%%) %s\n", label, count, pct, bar)
    end
    println()

    # Per-domain breakdown
    println("By domain (median gradient norm):")
    for domain in sort(unique(metrics_df.domain))
        domain_grads = filter(x -> !isnan(x) && x > 0, metrics_df[metrics_df.domain .== domain, :gradient_norm])
        if !isempty(domain_grads)
            med = quantile(domain_grads, 0.5)
            min_g = minimum(domain_grads)
            @printf("  domain=%.4f: median=%.2e, min=%.2e (n=%d)\n",
                    domain, med, min_g, length(domain_grads))
        end
    end
    println()

    # Threshold analysis
    println("Gradient validation threshold analysis:")
    @printf("  Current threshold (1e-6):  %d/%d pass (%.1f%%)\n",
            sum(valid_grads .< 1e-6), n_valid, 100 * sum(valid_grads .< 1e-6) / n_valid)
    @printf("  Relaxed (1e-3):            %d/%d pass (%.1f%%)\n",
            sum(valid_grads .< 1e-3), n_valid, 100 * sum(valid_grads .< 1e-3) / n_valid)
    @printf("  Relaxed (1e+2):            %d/%d pass (%.1f%%)\n",
            sum(valid_grads .< 1e2), n_valid, 100 * sum(valid_grads .< 1e2) / n_valid)
    @printf("  Min observed:              %.2e\n", p_min)
end

# Analyze and print objective value (z) distribution at critical points
function analyze_objective_distribution(metrics_df::DataFrame)
    if !("z" in names(metrics_df))
        println("No z column found.")
        return
    end

    z_vals = metrics_df.z
    valid_z = filter(x -> !isnan(x) && isfinite(x) && x > 0, z_vals)
    n_valid = length(valid_z)

    println("="^80)
    println("OBJECTIVE VALUE DISTRIBUTION ($n_valid critical points)")
    println("="^80)
    println()

    if n_valid == 0
        println("No valid objective values found.")
        return
    end

    # Percentiles
    sorted_z = sort(valid_z)
    p_min = minimum(sorted_z)
    p25 = quantile(sorted_z, 0.25)
    p50 = quantile(sorted_z, 0.50)
    p75 = quantile(sorted_z, 0.75)
    p_max = maximum(sorted_z)

    println("Percentiles:")
    @printf("  min: %.2e    p25: %.2e    median: %.2e    p75: %.2e    max: %.2e\n",
            p_min, p25, p50, p75, p_max)
    println()

    # Adaptive log-scale histogram
    bins = make_log_bins(valid_z)

    println("Log-scale histogram:")
    for i in 1:(length(bins)-1)
        count = sum(bins[i] .<= valid_z .< bins[i+1])
        pct = count / n_valid * 100
        bar = repeat("█", min(50, round(Int, pct / 2)))
        label = format_bin_label(bins[i], bins[i+1])
        @printf("  %-18s %4d (%5.1f%%) %s\n", label, count, pct, bar)
    end
    println()

    # Per-domain breakdown
    println("By domain (median objective value):")
    for domain in sort(unique(metrics_df.domain))
        domain_z = filter(x -> !isnan(x) && isfinite(x) && x > 0, metrics_df[metrics_df.domain .== domain, :z])
        if !isempty(domain_z)
            med = quantile(domain_z, 0.5)
            min_z = minimum(domain_z)
            @printf("  domain=%.4f: median=%.2e, min=%.2e (n=%d)\n",
                    domain, med, min_z, length(domain_z))
        end
    end
    println()

    # Summary: best critical points (lowest objective values)
    println("Best critical points (lowest objective):")
    @printf("  Minimum f(x): %.4f\n", p_min)
    @printf("  Below 1.0:    %d/%d (%.1f%%)\n",
            sum(valid_z .< 1.0), n_valid, 100 * sum(valid_z .< 1.0) / n_valid)
    @printf("  Below 10.0:   %d/%d (%.1f%%)\n",
            sum(valid_z .< 10.0), n_valid, 100 * sum(valid_z .< 10.0) / n_valid)
    @printf("  Below 100.0:  %d/%d (%.1f%%)\n",
            sum(valid_z .< 100.0), n_valid, 100 * sum(valid_z .< 100.0) / n_valid)
end

# Load results from a single experiment directory
function load_experiment_results(exp_dir::String)
    results_file = joinpath(exp_dir, "results_summary.json")
    config_file = joinpath(exp_dir, "experiment_config.json")

    if !isfile(results_file)
        return nothing
    end

    try
        results = JSON.parsefile(results_file)
        config = isfile(config_file) ? JSON.parsefile(config_file) : Dict()

        # Parse directory name for parameters
        dirname = basename(exp_dir)
        params = parse_experiment_name(dirname)

        if params === nothing
            @debug "Could not parse experiment name: $dirname"
            return nothing
        end

        # Extract metrics from results (which is an array of per-degree results)
        rows = DataFrame[]

        for r in results
            if !get(r, "success", false)
                continue
            end

            # Handle L2_norm: either direct or from orthant_stats (subdivision experiments)
            l2_norm = get(r, "L2_norm", NaN)
            if (l2_norm isa Number && isnan(l2_norm)) || l2_norm === nothing
                # Try to get from orthant_stats (subdivision experiments use max L2 across orthants)
                orthant_stats = get(r, "orthant_stats", nothing)
                if orthant_stats !== nothing && !isempty(orthant_stats)
                    orthant_l2s = [get(os, "L2_norm", NaN) for os in orthant_stats]
                    valid_l2s = filter(!isnan, orthant_l2s)
                    l2_norm = isempty(valid_l2s) ? NaN : maximum(valid_l2s)
                end
            end

            # Handle critical_points: either direct or total_critical_points (subdivision)
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

# Check if a directory is a single experiment (vs parent containing experiments)
function is_single_experiment(path::String)
    return startswith(basename(path), "lv4d_") && isfile(joinpath(path, "results_summary.json"))
end

# Main analysis function
function analyze_sweep(results_dir::String)
    println("="^70)
    println("PE-01: Domain × Degree Sweep Analysis")
    println("="^70)
    println("Results directory: $results_dir")
    println()

    # Find all experiment directories
    if !isdir(results_dir)
        error("Results directory not found: $results_dir")
    end

    # Check if this is a single experiment directory
    if is_single_experiment(results_dir)
        println("Single experiment mode: $(basename(results_dir))")
        exp_dirs = [results_dir]
    else
        exp_dirs = filter(isdir, [joinpath(results_dir, d) for d in readdir(results_dir)])
        exp_dirs = filter(d -> startswith(basename(d), "lv4d_"), exp_dirs)
    end

    println("Found $(length(exp_dirs)) experiment directories")

    # Load all results
    all_results = DataFrame[]
    for exp_dir in exp_dirs
        result = load_experiment_results(exp_dir)
        if result !== nothing
            push!(all_results, result)
        end
    end

    if isempty(all_results)
        println("No valid results found!")
        return
    end

    df = vcat(all_results...)
    println("Loaded $(nrow(df)) individual experiment results")
    println()

    # Show available configurations
    println("Available configurations:")
    gn_values = sort(unique(df.GN))
    domain_values = sort(unique(df.domain))
    degree_values = sort(unique(df.degree))
    println("  GN: $(gn_values)")
    println("  Domains: $(domain_values)")
    println("  Degrees: $(degree_values)")
    println()

    # Filter to small domains (0.01-0.15) and reasonable degrees (4-20)
    # This is intentionally flexible to analyze whatever results are available
    sweep_filter = (df.domain .<= 0.15) .& (df.degree .>= 4) .& (df.degree .<= 20)
    df_sweep = df[sweep_filter, :]

    if nrow(df_sweep) == 0
        println("No results with domain <= 0.15")
        df_sweep = df  # Fall back to all results
    end

    println("Sweep results: $(nrow(df_sweep)) experiments")
    println()

    # Aggregate by (GN, domain, degree) to avoid mixing different GN experiments
    summary = combine(
        groupby(df_sweep, [:GN, :domain, :degree]),
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

    # Sort by GN, domain, then degree
    sort!(summary, [:GN, :domain, :degree])

    # Print summary table using PrettyTables
    println("="^80)
    println("SUMMARY: Mean metrics per (GN, domain, degree)")
    println("="^80)
    println()

    # Build data matrix for PrettyTables
    n_rows = nrow(summary)
    data = Matrix{Any}(undef, n_rows, 9)
    for (i, row) in enumerate(eachrow(summary))
        data[i, 1] = row.GN
        data[i, 2] = row.domain
        data[i, 3] = row.degree
        data[i, 4] = isnan(row.mean_L2) ? "-" : round(row.mean_L2, digits=2)
        data[i, 5] = @sprintf("%.1f%%", row.mean_grad_valid * 100)
        data[i, 6] = isnan(row.mean_recovery) ? "-" : @sprintf("%.2f%%", row.mean_recovery * 100)
        data[i, 7] = @sprintf("%.1f%%", row.success_rate * 100)
        data[i, 8] = Int(round(row.mean_crit_pts))  # Critical points as integer
        data[i, 9] = row.n_seeds
    end

    pretty_table(data,
        header = ["GN", "Domain", "Deg", "L2", "Grad%", "RecErr%", "Succ%", "Crit", "n"],
        alignment = [:r, :r, :r, :r, :r, :r, :r, :r, :r],
        tf = tf_unicode_rounded,
        crop = :none
    )
    println()

    # Save summary CSV
    output_dir = joinpath(results_dir, "sweep_analysis")
    mkpath(output_dir)
    summary_file = joinpath(output_dir, "domain_degree_summary.csv")
    CSV.write(summary_file, summary)
    println("Summary saved: $summary_file")

    # Also save raw results
    raw_file = joinpath(output_dir, "all_sweep_results.csv")
    CSV.write(raw_file, df_sweep)
    println("Raw results saved: $raw_file")
    println()

    # Load and analyze critical point metrics (gradient norms and objective values)
    all_metrics = DataFrame[]
    for exp_dir in exp_dirs
        metrics_df = load_critical_point_metrics(exp_dir)
        if metrics_df !== nothing
            push!(all_metrics, metrics_df)
        end
    end

    if !isempty(all_metrics)
        metrics_df = vcat(all_metrics...)
        analyze_gradient_distribution(metrics_df)
        println()
        analyze_objective_distribution(metrics_df)
        println()
    end

    # Find optimal configurations
    println("="^80)
    println("OPTIMAL CONFIGURATIONS")
    println("="^80)
    println()

    # Filter out rows with NaN L2 for finding best
    valid_l2 = summary[.!isnan.(summary.mean_L2), :]

    # Best L2 norm
    if nrow(valid_l2) > 0
        best_l2_idx = argmin(valid_l2.mean_L2)
        best_l2 = valid_l2[best_l2_idx, :]
        println("Best L2 approximation:")
        println("  GN=$(best_l2.GN), domain=$(best_l2.domain), degree=$(best_l2.degree): L2=$(round(best_l2.mean_L2, digits=3)) (n=$(best_l2.n_seeds))")
    else
        println("Best L2 approximation: No valid results")
        best_l2 = summary[1, :]  # Fallback for later use
    end
    println()

    # Best gradient validation
    best_grad_idx = argmax(summary.mean_grad_valid)
    best_grad = summary[best_grad_idx, :]
    println("Best gradient validation:")
    println("  GN=$(best_grad.GN), domain=$(best_grad.domain), degree=$(best_grad.degree): $(round(best_grad.mean_grad_valid * 100, digits=1))% valid (n=$(best_grad.n_seeds))")
    println()

    # Best recovery success rate
    best_success_idx = argmax(summary.success_rate)
    best_success = summary[best_success_idx, :]
    println("Best recovery success (<5% error):")
    println("  GN=$(best_success.GN), domain=$(best_success.domain), degree=$(best_success.degree): $(round(best_success.success_rate * 100, digits=1))% success (n=$(best_success.n_seeds))")
    println()

    # Best overall (Pareto-optimal: L2 < 0.1, grad_valid > 0.5, success > 0.8)
    excellent = summary[(summary.mean_L2 .< 0.1) .& (summary.mean_grad_valid .> 0.5) .& (summary.success_rate .> 0.8), :]
    if nrow(excellent) > 0
        println("EXCELLENT configurations (L2<0.1, GradValid>50%, Success>80%):")
        for row in eachrow(excellent)
            println("  GN=$(row.GN), domain=$(row.domain), degree=$(row.degree): L2=$(round(row.mean_L2, digits=3)), GradValid=$(round(row.mean_grad_valid * 100, digits=1))%, Success=$(round(row.success_rate * 100, digits=1))%")
        end
    else
        println("No configurations meet all excellent criteria (L2<0.1, GradValid>50%, Success>80%)")

        # Find threshold where gradient validation starts working
        good_grad = summary[summary.mean_grad_valid .> 0.1, :]
        if nrow(good_grad) > 0
            println("\nConfigurations with >10% gradient validation:")
            for row in eachrow(good_grad)
                println("  GN=$(row.GN), domain=$(row.domain), degree=$(row.degree): L2=$(round(row.mean_L2, digits=3)), GradValid=$(round(row.mean_grad_valid * 100, digits=1))%")
            end
        else
            println("\nNo configurations achieved >10% gradient validation yet.")
            println("Consider: smaller domains (< 0.01) or higher GN or higher degrees")
        end
    end
    println()

    # Domain threshold analysis (grouped by GN) using PrettyTables
    println("="^80)
    println("DOMAIN THRESHOLD ANALYSIS (by GN)")
    println("="^80)
    println()

    for gn in sort(unique(summary.GN))
        println("GN=$gn:")
        gn_results = summary[summary.GN .== gn, :]

        # Build table data
        domains = sort(unique(gn_results.domain))
        table_data = Matrix{Any}(undef, length(domains), 5)

        for (i, domain) in enumerate(domains)
            domain_results = gn_results[gn_results.domain .== domain, :]
            if nrow(domain_results) == 0
                continue
            end

            best_idx = argmax(domain_results.success_rate)
            best = domain_results[best_idx, :]

            table_data[i, 1] = domain
            table_data[i, 2] = best.degree
            table_data[i, 3] = round(best.mean_L2, digits=2)
            table_data[i, 4] = @sprintf("%.1f%%", best.mean_grad_valid * 100)
            table_data[i, 5] = @sprintf("%.1f%%", best.success_rate * 100)
        end

        pretty_table(table_data,
            header = ["Domain", "Deg", "L2", "Grad%", "Succ%"],
            alignment = [:r, :r, :r, :r, :r],
            tf = tf_unicode_rounded,
            crop = :none
        )
        println()
    end

    # Save optimal configurations
    optimal_file = joinpath(output_dir, "optimal_configurations.txt")
    open(optimal_file, "w") do io
        println(io, "PE-01 Domain-Degree Sweep: Optimal Configurations")
        println(io, "Generated: $(now())")
        println(io, "="^60)
        println(io)
        println(io, "Best L2: GN=$(best_l2.GN), domain=$(best_l2.domain), degree=$(best_l2.degree), L2=$(best_l2.mean_L2)")
        println(io, "Best GradValid: GN=$(best_grad.GN), domain=$(best_grad.domain), degree=$(best_grad.degree), rate=$(best_grad.mean_grad_valid)")
        println(io, "Best Success: GN=$(best_success.GN), domain=$(best_success.domain), degree=$(best_success.degree), rate=$(best_success.success_rate)")
        println(io)
        if nrow(excellent) > 0
            println(io, "Excellent configurations:")
            for row in eachrow(excellent)
                println(io, "  GN=$(row.GN), domain=$(row.domain), degree=$(row.degree)")
            end
        end
    end
    println("Optimal configurations saved: $optimal_file")

    println()
    println("="^80)
    println("ANALYSIS COMPLETE")
    println("="^80)

    return summary
end

# Main entry point
function main()
    # Determine results directory
    results_dir = if length(ARGS) >= 1
        ARGS[1]
    else
        # Default: look for globtim_results relative to GlobalOptim root
        globoptim_root = abspath(joinpath(PROJECT_ROOT, ".."))
        results_root = get(ENV, "GLOBTIM_RESULTS_ROOT", joinpath(globoptim_root, "globtim_results"))
        joinpath(results_root, "lotka_volterra_4d")
    end

    analyze_sweep(results_dir)
end

# Run main
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
