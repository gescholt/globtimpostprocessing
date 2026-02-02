#!/usr/bin/env julia
"""
Analyze LV4D Experiment Results

Usage:
    julia --project=globtimpostprocessing scripts/analyze_lv4d_sweep.jl [options] [results_dir]

Options:
    --verbose, -v    Show detailed output including file paths and histograms
    --help, -h       Show this help

Arguments:
    results_dir      Path to experiment directory or parent containing experiments
"""

const SCRIPT_DIR = @__DIR__
const PROJECT_ROOT = abspath(joinpath(SCRIPT_DIR, ".."))

using Pkg
Pkg.activate(PROJECT_ROOT; io=devnull)

using DataFrames
using CSV
using JSON
using Statistics
using Printf
using Dates
using PrettyTables

# Global verbosity flag
VERBOSE = Ref(false)

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

# Analyze gradient norm distribution (verbose mode only for histogram)
function analyze_gradient_distribution(metrics_df::DataFrame)
    if !("gradient_norm" in names(metrics_df))
        return nothing
    end

    grads = metrics_df.gradient_norm
    valid_grads = filter(x -> !isnan(x) && x > 0, grads)
    n_valid = length(valid_grads)

    if n_valid == 0
        return nothing
    end

    sorted_grads = sort(valid_grads)
    p_min = minimum(sorted_grads)
    p50 = quantile(sorted_grads, 0.50)

    if VERBOSE[]
        println()
        @printf("Gradient Norms (%d CPs): min=%.2e  median=%.2e\n", n_valid, p_min, p50)

        # Histogram only in verbose mode
        bins = make_log_bins(valid_grads)
        for i in 1:(length(bins)-1)
            count = sum(bins[i] .<= valid_grads .< bins[i+1])
            if count > 0
                pct = count / n_valid * 100
                bar = repeat("█", min(40, round(Int, pct / 2.5)))
                label = format_bin_label(bins[i], bins[i+1])
                @printf("  %-16s %3d (%4.1f%%) %s\n", label, count, pct, bar)
            end
        end
    end

    return (min=p_min, median=p50, n=n_valid,
            pass_1e6=sum(valid_grads .< 1e-6),
            pass_1e3=sum(valid_grads .< 1e-3))
end

# Analyze objective value distribution (verbose mode only for histogram)
function analyze_objective_distribution(metrics_df::DataFrame)
    if !("z" in names(metrics_df))
        return nothing
    end

    z_vals = metrics_df.z
    valid_z = filter(x -> !isnan(x) && isfinite(x) && x > 0, z_vals)
    n_valid = length(valid_z)

    if n_valid == 0
        return nothing
    end

    sorted_z = sort(valid_z)
    p_min = minimum(sorted_z)
    p50 = quantile(sorted_z, 0.50)

    if VERBOSE[]
        @printf("Objective Values (%d CPs): min=%.4f  median=%.2e\n", n_valid, p_min, p50)

        bins = make_log_bins(valid_z)
        for i in 1:(length(bins)-1)
            count = sum(bins[i] .<= valid_z .< bins[i+1])
            if count > 0
                pct = count / n_valid * 100
                bar = repeat("█", min(40, round(Int, pct / 2.5)))
                label = format_bin_label(bins[i], bins[i+1])
                @printf("  %-16s %3d (%4.1f%%) %s\n", label, count, pct, bar)
            end
        end
    end

    return (min=p_min, median=p50, n=n_valid,
            below_1=sum(valid_z .< 1.0),
            below_10=sum(valid_z .< 10.0))
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
    # Find experiment directories
    if !isdir(results_dir)
        error("Not found: $results_dir")
    end

    exp_dirs = if is_single_experiment(results_dir)
        [results_dir]
    else
        filter(d -> startswith(basename(d), "lv4d_") && isdir(d),
               [joinpath(results_dir, d) for d in readdir(results_dir)])
    end

    # Load results
    all_results = DataFrame[]
    for exp_dir in exp_dirs
        result = load_experiment_results(exp_dir)
        result !== nothing && push!(all_results, result)
    end

    if isempty(all_results)
        println("No valid results found in $(length(exp_dirs)) directories")
        return nothing
    end

    df = vcat(all_results...)

    # Header
    exp_name = basename(results_dir)
    n_exp = length(exp_dirs)
    println()
    println("LV4D Analysis: $exp_name ($n_exp exp, $(nrow(df)) results)")
    println("─"^70)

    # Filter and aggregate
    sweep_filter = (df.degree .>= 4) .& (df.degree .<= 20)
    df_sweep = df[sweep_filter, :]
    if nrow(df_sweep) == 0
        df_sweep = df
    end

    summary = combine(
        groupby(df_sweep, [:GN, :domain, :degree]),
        :L2_norm => mean => :mean_L2,
        :gradient_valid_rate => mean => :mean_grad_valid,
        :recovery_error => mean => :mean_recovery,
        :recovery_error => (x -> mean(x .< 0.05)) => :success_rate,
        :critical_points => mean => :mean_crit_pts,
        nrow => :n_seeds
    )
    sort!(summary, [:GN, :domain, :degree])

    # Build and print summary table
    n_rows = nrow(summary)
    data = Matrix{Any}(undef, n_rows, 8)
    for (i, row) in enumerate(eachrow(summary))
        data[i, 1] = row.GN
        data[i, 2] = row.domain
        data[i, 3] = row.degree
        data[i, 4] = isnan(row.mean_L2) ? "-" : round(row.mean_L2, digits=1)
        data[i, 5] = @sprintf("%.0f%%", row.mean_grad_valid * 100)
        data[i, 6] = isnan(row.mean_recovery) ? "-" : @sprintf("%.2f%%", row.mean_recovery * 100)
        data[i, 7] = @sprintf("%.0f%%", row.success_rate * 100)
        data[i, 8] = Int(round(row.mean_crit_pts))
    end

    pretty_table(data,
        header = ["GN", "Domain", "Deg", "L2", "Grad", "RecErr", "Succ", "CPs"],
        alignment = [:r, :r, :r, :r, :r, :r, :r, :r],
        tf = tf_unicode_rounded,
        crop = :none
    )

    # Save files silently
    output_dir = joinpath(results_dir, "sweep_analysis")
    mkpath(output_dir)
    CSV.write(joinpath(output_dir, "summary.csv"), summary)
    CSV.write(joinpath(output_dir, "raw.csv"), df_sweep)

    # Critical point metrics (verbose only for histograms)
    all_metrics = DataFrame[]
    for exp_dir in exp_dirs
        m = load_critical_point_metrics(exp_dir)
        m !== nothing && push!(all_metrics, m)
    end

    grad_stats = nothing
    obj_stats = nothing
    if !isempty(all_metrics)
        metrics_df = vcat(all_metrics...)
        grad_stats = analyze_gradient_distribution(metrics_df)
        obj_stats = analyze_objective_distribution(metrics_df)
    end

    # Compact summary line
    valid_l2 = summary[.!isnan.(summary.mean_L2), :]
    if nrow(valid_l2) > 0
        best_idx = argmax(summary.success_rate)
        best = summary[best_idx, :]
        println()
        @printf("Best: GN=%d dom=%.1e deg=%d → L2=%.1f RecErr=%.2f%% Succ=%.0f%%\n",
                best.GN, best.domain, best.degree, best.mean_L2,
                best.mean_recovery * 100, best.success_rate * 100)

        # Show grad/obj stats on one line if available
        if grad_stats !== nothing && obj_stats !== nothing
            @printf("CPs: n=%d  ‖∇f‖_min=%.1e  f_min=%.3f\n",
                    grad_stats.n, grad_stats.min, obj_stats.min)
        end
    end

    # Verbose: show file paths
    if VERBOSE[]
        println()
        println("Saved: $(joinpath(output_dir, "summary.csv"))")
    end

    println()
    return summary
end

# Main entry point
function main()
    # Parse arguments
    args = filter(a -> !startswith(a, "-"), ARGS)
    flags = filter(a -> startswith(a, "-"), ARGS)

    # Handle flags
    if "-h" in flags || "--help" in flags
        println(@doc analyze_lv4d_sweep)
        return
    end

    VERBOSE[] = "-v" in flags || "--verbose" in flags

    # Determine results directory
    results_dir = if !isempty(args)
        args[1]
    else
        globoptim_root = abspath(joinpath(PROJECT_ROOT, ".."))
        results_root = get(ENV, "GLOBTIM_RESULTS_ROOT", joinpath(globoptim_root, "globtim_results"))
        joinpath(results_root, "lotka_volterra_4d")
    end

    analyze_sweep(results_dir)
end

# Module docstring for help
@doc """
Analyze LV4D Experiment Results

Usage:
    julia --project=globtimpostprocessing scripts/analyze_lv4d_sweep.jl [options] [results_dir]

Options:
    --verbose, -v    Show detailed output including file paths and histograms
    --help, -h       Show this help
""" analyze_lv4d_sweep

# Run main
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
