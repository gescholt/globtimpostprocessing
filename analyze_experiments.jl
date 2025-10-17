#!/usr/bin/env julia

"""
Interactive Experiment Analysis Entry Point

This script provides an interactive interface for discovering, selecting,
and analyzing GlobTim experiments organized in the standardized hierarchical structure.

Requirements:
    GLOBTIM_RESULTS_ROOT environment variable must be set.
    Run: cd globtimcore && ./scripts/setup_results_root.sh

Expected structure:
    \$GLOBTIM_RESULTS_ROOT/
    └── {objective_name}/
        └── {experiment_id}_{timestamp}/
            ├── experiment_config.json
            ├── results_summary.json
            └── critical_points_deg_*.csv

Usage:
    julia analyze_experiments.jl [--path <custom_path>]

If no path is provided, uses \$GLOBTIM_RESULTS_ROOT automatically.
"""

using Pkg
Pkg.activate(@__DIR__)

using GlobtimPostProcessing
using GlobtimPostProcessing: load_experiment_config, load_critical_points_for_degree,
                             has_ground_truth, compute_parameter_recovery_stats,
                             load_quality_thresholds, check_l2_quality,
                             detect_stagnation, check_objective_distribution_quality
using GlobtimPostProcessing.ExperimentCollector
using DataFrames
using Printf
using Dates
using CSV
using JSON3
using Statistics
using LinearAlgebra

# Load TrajectoryComparison module
include(joinpath(@__DIR__, "src", "TrajectoryComparison.jl"))
using .TrajectoryComparison

# Terminal colors for better UX
const RESET = "\033[0m"
const BOLD = "\033[1m"
const GREEN = "\033[32m"
const BLUE = "\033[34m"
const YELLOW = "\033[33m"
const RED = "\033[31m"
const CYAN = "\033[36m"

# Helper functions to convert between module types and display formats

"""
    display_campaigns(campaigns::Vector{CampaignInfo})

Display discovered campaigns in a numbered list, sorted by modification time (newest first).
"""
function display_campaigns(campaigns::Vector{CampaignInfo})
    println("\n$(BOLD)$(CYAN)═══ Discovered Campaigns (sorted by newest first) ═══$(RESET)\n")

    for (idx, campaign) in enumerate(campaigns)
        # Format timestamp
        timestamp = Dates.unix2datetime(campaign.mtime)
        time_str = Dates.format(timestamp, "yyyy-mm-dd HH:MM:SS")

        # Add "LATEST" marker for the first one
        latest_marker = idx == 1 ? " $(BOLD)$(GREEN)[LATEST]$(RESET)" : ""

        println("$(BOLD)$idx.$(RESET) $(GREEN)$(campaign.path)$(RESET)$latest_marker")
        println("   Campaign: $(campaign.name)")
        println("   Experiments: $(campaign.num_experiments)")
        println("   Modified: $time_str\n")
    end
end

"""
    get_user_choice(prompt::String, max_value::Int) -> Int

Get validated integer input from user.
"""
function get_user_choice(prompt::String, max_value::Int)
    while true
        print("$(BOLD)$prompt$(RESET) (1-$max_value, or 'q' to quit): ")
        response = strip(readline())

        if lowercase(response) == "q"
            println("\n$(YELLOW)Exiting...$(RESET)")
            exit(0)
        end

        try
            choice = parse(Int, response)
            if 1 <= choice <= max_value
                return choice
            else
                println("$(RED)Please enter a number between 1 and $max_value$(RESET)")
            end
        catch
            println("$(RED)Invalid input. Please enter a number or 'q' to quit$(RESET)")
        end
    end
end

"""
    display_experiment_list(campaign_path::String) -> Tuple{Vector{String}, Vector{Bool}}

Display experiments in a campaign and return list of experiment paths and validity flags.

Returns:
- Vector{String}: All experiment paths
- Vector{Bool}: Boolean flags indicating which experiments have valid results
"""
function display_experiment_list(campaign_path::String)
    exp_dirs = String[]
    valid_flags = Bool[]

    for entry in readdir(campaign_path)
        exp_path = joinpath(campaign_path, entry)
        if isdir(exp_path)
            push!(exp_dirs, exp_path)
        end
    end

    sort!(exp_dirs)

    println("\n$(BOLD)$(CYAN)═══ Experiments in Campaign ═══$(RESET)\n")

    for (idx, exp_path) in enumerate(exp_dirs)
        exp_name = basename(exp_path)

        # Check if results exist and are valid
        results_file = joinpath(exp_path, "results_summary.json")
        has_results = false
        status_msg = ""

        if isfile(results_file)
            # Check if file is not empty
            file_size = stat(results_file).size
            if file_size == 0
                status = "$(YELLOW)⚠$(RESET)"
                status_msg = " (empty results file)"
            else
                status = "$(GREEN)✓$(RESET)"
                has_results = true
            end
        else
            status = "$(RED)✗$(RESET)"
            status_msg = " (no results file)"
        end

        push!(valid_flags, has_results)

        println("$(BOLD)$idx.$(RESET) $status $(BLUE)$exp_name$(RESET)$status_msg")
        println("   Path: $exp_path")

        # Try to read basic info only if results exist
        if has_results
            try
                result = load_experiment_results(exp_path)
                if !isempty(result.enabled_tracking)
                    println("   Tracking: $(join(result.enabled_tracking, ", "))")
                else
                    println("   $(YELLOW)Warning: No tracking labels enabled$(RESET)")
                end
            catch e
                println("   $(RED)Error loading: $(sprint(showerror, e))$(RESET)")
                valid_flags[end] = false  # Mark as invalid if loading failed
            end
        end
        println()
    end

    return exp_dirs, valid_flags
end

"""
    display_quality_diagnostics(exp_path::String)

Display quality diagnostics for an experiment using configurable thresholds.
"""
function display_quality_diagnostics(exp_path::String)
    try
        # Load quality thresholds
        thresholds = load_quality_thresholds()

        # Load experiment config
        config = load_experiment_config(exp_path)
        dimension = get(config, "dimension", 4)

        # Load results summary to get L2 norms by degree
        results_summary_path = joinpath(exp_path, "results_summary.json")
        if !isfile(results_summary_path)
            println("  $(YELLOW)⚠ No results_summary.json found$(RESET)")
            return
        end

        # Parse JSON line by line to extract L2 norms (more robust for large files)
        l2_norms = Float64[]
        degrees = Int[]
        best_values = Float64[]

        json_text = read(results_summary_path, String)

        # Extract L2_norm values using regex (more robust than full JSON parse)
        for m in eachmatch(r"\"L2_norm\":\s*([0-9.e+-]+)", json_text)
            push!(l2_norms, parse(Float64, m.captures[1]))
        end

        # Extract degree values
        for m in eachmatch(r"\"degree\":\s*(\d+)", json_text)
            push!(degrees, parse(Int, m.captures[1]))
        end

        # Extract best_value
        for m in eachmatch(r"\"best_value\":\s*([0-9.e+-]+)", json_text)
            push!(best_values, parse(Float64, m.captures[1]))
        end

        if isempty(l2_norms)
            println("  $(YELLOW)⚠ No L2 norm data available$(RESET)")
            return
        end

        # Get final degree L2 norm for quality check
        final_l2 = l2_norms[end]
        final_degree = !isempty(degrees) ? degrees[end] : length(l2_norms) * 2 + 2

        # Check L2 quality
        l2_quality = check_l2_quality(final_l2, dimension, thresholds)
        quality_color = l2_quality == :excellent ? GREEN :
                       l2_quality == :good ? CYAN :
                       l2_quality == :fair ? YELLOW : RED
        quality_symbol = l2_quality == :poor ? "✗" : "✓"

        println("  $(quality_color)$(quality_symbol) L2 Norm Quality:$(RESET) $(uppercase(string(l2_quality)))")
        @printf("    Final L2 norm (degree %d): %.6g\n", final_degree, final_l2)

        threshold_key = "dim_$(dimension)"
        threshold = get(thresholds["l2_norm_thresholds"], threshold_key,
                       thresholds["l2_norm_thresholds"]["default"])
        @printf("    Threshold for %dD: %.6g\n", dimension, threshold)

        # Check convergence stagnation if we have multiple degrees
        if length(l2_norms) >= 3 && length(degrees) == length(l2_norms)
            l2_by_degree = Dict{Int, Float64}()
            for (i, degree) in enumerate(degrees)
                l2_by_degree[degree] = l2_norms[i]
            end

            stagnation = detect_stagnation(l2_by_degree, thresholds)
            if stagnation.is_stagnant
                println("  $(YELLOW)⚠ Convergence Stagnation:$(RESET) Detected at degree $(stagnation.stagnation_start_degree)")
                @printf("    Consecutive stagnant degrees: %d\n", stagnation.consecutive_stagnant_degrees)
            else
                println("  $(GREEN)✓ Convergence:$(RESET) Improving")
                if !isnothing(stagnation.avg_improvement_factor)
                    @printf("    Average improvement: %.1f%%\n", (1 - stagnation.avg_improvement_factor) * 100)
                end
            end
        end

        # Check objective distribution quality
        if length(best_values) >= 3
            dist_result = check_objective_distribution_quality(best_values, thresholds)
            if dist_result.has_outliers && dist_result.quality == :poor
                println("  $(YELLOW)⚠ Objective Distribution:$(RESET) High outlier fraction ($(dist_result.outlier_fraction * 100)%)")
                @printf("    Outliers: %d / %d\n", dist_result.num_outliers, length(best_values))
            else
                println("  $(GREEN)✓ Objective Distribution:$(RESET) Normal")
            end
        end

    catch e
        println("  $(RED)Error displaying quality diagnostics:$(RESET) $e")
    end
end

"""
    display_parameter_recovery(exp_path::String)

Display parameter recovery table for an experiment with ground truth.
"""
function display_parameter_recovery(exp_path::String)
    try
        # Load config to get p_true
        config = load_experiment_config(exp_path)
        p_true = collect(config["p_true"])

        # Load quality thresholds for recovery threshold
        thresholds = load_quality_thresholds()
        recovery_threshold = thresholds["parameter_recovery"]["param_distance_threshold"]

        # Get all degrees from CSV files
        csv_files = filter(f -> startswith(basename(f), "critical_points_deg_"),
                          readdir(exp_path, join=true))
        degrees = Int[]
        for csv_file in csv_files
            m = match(r"deg_(\d+)\.csv", basename(csv_file))
            if m !== nothing
                push!(degrees, parse(Int, m[1]))
            end
        end
        sort!(degrees)

        if isempty(degrees)
            println("  $(YELLOW)⚠ No critical points data available$(RESET)")
            return
        end

        # Display table header
        println("  Parameter recovery (p_true = $p_true)")
        println("  Recovery threshold: distance < $recovery_threshold")
        println()
        println("  " * "="^80)
        @printf("  %-8s | %-8s | %-12s | %-12s | %-12s\n",
                "Degree", "# CPs", "Min Dist", "Mean Dist", "Recoveries")
        println("  " * "="^80)

        # Display each degree
        for degree in degrees
            df = load_critical_points_for_degree(exp_path, degree)
            stats = compute_parameter_recovery_stats(df, p_true, recovery_threshold)
            n_points = nrow(df)

            recovery_color = stats["num_recoveries"] > 0 ? GREEN : YELLOW
            @printf("  %-8d | %-8d | %s%-12.6g%s | %-12.6g | %s%-12d%s\n",
                    degree, n_points,
                    stats["min_distance"] < recovery_threshold ? GREEN : "",
                    stats["min_distance"],
                    RESET,
                    stats["mean_distance"],
                    recovery_color, stats["num_recoveries"], RESET)
        end
        println("  " * "="^80)

        # Summary: best recovery across all degrees
        best_recovery = 0
        best_degree = degrees[1]
        best_min_dist = Inf

        for degree in degrees
            df = load_critical_points_for_degree(exp_path, degree)
            stats = compute_parameter_recovery_stats(df, p_true, recovery_threshold)
            if stats["num_recoveries"] > best_recovery
                best_recovery = stats["num_recoveries"]
                best_degree = degree
            end
            if stats["min_distance"] < best_min_dist
                best_min_dist = stats["min_distance"]
            end
        end

        println()
        println("  $(BOLD)Summary:$(RESET)")
        @printf("    Best minimum distance: %.6g\n", best_min_dist)
        @printf("    Best recovery count: %d (at degree %d)\n", best_recovery, best_degree)

        if best_min_dist < recovery_threshold
            println("    $(GREEN)✓ Ground truth recovered!$(RESET)")
        else
            println("    $(YELLOW)⚠ Ground truth not yet recovered$(RESET)")
        end

    catch e
        println("  $(RED)Error displaying parameter recovery:$(RESET) $e")
    end
end

"""
    display_convergence_by_degree(exp_path::String)

Display L2-norm convergence tracking table showing how L2 norm improves with degree.
Implements Issue #12 Phase 1: L2-Norm Convergence Tracking.
"""
function display_convergence_by_degree(exp_path::String)
    try
        # Load results summary
        results_summary_path = joinpath(exp_path, "results_summary.json")
        if !isfile(results_summary_path)
            println("  $(YELLOW)⚠ No results_summary.json found$(RESET)")
            return
        end

        json_text = read(results_summary_path, String)

        # Extract data by degree
        degrees = Int[]
        l2_norms = Float64[]
        critical_points = Int[]

        for m in eachmatch(r"\"degree\":\s*(\d+)", json_text)
            push!(degrees, parse(Int, m.captures[1]))
        end

        for m in eachmatch(r"\"L2_norm\":\s*([0-9.e+-]+)", json_text)
            push!(l2_norms, parse(Float64, m.captures[1]))
        end

        for m in eachmatch(r"\"critical_points\":\s*(\d+)", json_text)
            push!(critical_points, parse(Int, m.captures[1]))
        end

        if isempty(degrees) || length(degrees) != length(l2_norms) || length(degrees) != length(critical_points)
            println("  $(YELLOW)⚠ Incomplete or inconsistent results data$(RESET)")
            return
        end

        # Display table header
        println("  " * "="^65)
        @printf("  %-8s | %-15s | %-15s | %-12s\n",
                "Degree", "L2 Norm", "Improvement", "Critical Pts")
        println("  " * "="^65)

        # Display each degree with improvement percentage
        for i in 1:length(degrees)
            degree = degrees[i]
            l2 = l2_norms[i]
            n_cp = critical_points[i]

            if i == 1
                # First degree has no improvement to compare
                @printf("  %-8d | %-15.6g | %-15s | %-12d\n",
                        degree, l2, "-", n_cp)
            else
                # Calculate improvement percentage
                prev_l2 = l2_norms[i-1]
                improvement_pct = (prev_l2 - l2) / prev_l2 * 100

                # Color code based on improvement
                improvement_color = improvement_pct > 0 ? GREEN : RED
                @printf("  %-8d | %-15.6g | %s%14.1f%%%s | %-12d\n",
                        degree, l2, improvement_color, improvement_pct, RESET, n_cp)
            end
        end
        println("  " * "="^65)

        # Calculate overall improvement
        if length(l2_norms) >= 2
            first_l2 = l2_norms[1]
            last_l2 = l2_norms[end]
            overall_improvement_factor = first_l2 / last_l2
            overall_reduction_pct = (first_l2 - last_l2) / first_l2 * 100

            println()
            println("  $(BOLD)Summary:$(RESET)")
            @printf("    Overall: %.2f× improvement (%.1f%% reduction)\n",
                    overall_improvement_factor, overall_reduction_pct)

            # Check for stagnation using existing function
            l2_by_degree = Dict{Int, Float64}()
            for (i, degree) in enumerate(degrees)
                l2_by_degree[degree] = l2_norms[i]
            end

            thresholds = load_quality_thresholds()
            stagnation = detect_stagnation(l2_by_degree, thresholds)

            if stagnation.is_stagnant
                println("    Status: $(YELLOW)⚠ Stagnation detected$(RESET)")
            else
                println("    Status: $(GREEN)✓ Improving$(RESET) (no stagnation detected)")
            end
        end

    catch e
        println("  $(RED)Error displaying convergence by degree:$(RESET) $e")
    end
end

"""
    analyze_single_experiment(exp_path::String)

Load and analyze a single experiment, displaying computed statistics.
"""
function analyze_single_experiment(exp_path::String)
    println("\n$(BOLD)$(CYAN)═══ Analyzing Experiment ═══$(RESET)\n")
    println("Path: $(BLUE)$exp_path$(RESET)\n")

    try
        # Load experiment
        result = load_experiment_results(exp_path)

        println("$(BOLD)Experiment ID:$(RESET) $(result.experiment_id)")
        println("$(BOLD)Enabled Tracking:$(RESET) $(join(result.enabled_tracking, ", "))")
        println()

        # Compute statistics
        println("$(BOLD)Computing statistics...$(RESET)")
        stats = compute_statistics(result)

        # Display statistics
        println("\n$(BOLD)$(GREEN)═══ Computed Statistics ═══$(RESET)\n")

        for (label, stat_dict) in stats
            println("$(BOLD)$(CYAN)[$label]$(RESET)")
            for (stat_name, value) in stat_dict
                if value isa Number
                    @printf("  %-30s: %.6g\n", stat_name, value)
                elseif value isa AbstractString
                    println("  $(stat_name): $value")
                else
                    println("  $(stat_name): $value")
                end
            end
            println()
        end

        # Display critical points info
        if !isnothing(result.critical_points)
            n_points = nrow(result.critical_points)
            println("$(BOLD)Critical Points:$(RESET) $n_points found")
        end

        # NEW: Quality Diagnostics (Phase 3, Issue #7)
        println("\n$(BOLD)$(GREEN)═══ Quality Diagnostics ═══$(RESET)\n")
        display_quality_diagnostics(exp_path)

        # NEW: Parameter Recovery (if p_true exists) (Phase 2, Issue #7)
        if has_ground_truth(exp_path)
            println("\n$(BOLD)$(GREEN)═══ Parameter Recovery ═══$(RESET)\n")
            display_parameter_recovery(exp_path)
        end

        # NEW: Convergence by Degree (Issue #12 Phase 1)
        println("\n$(BOLD)$(GREEN)═══ Convergence by Degree ═══$(RESET)\n")
        display_convergence_by_degree(exp_path)

    catch e
        println("$(RED)Error analyzing experiment:$(RESET)")
        println(e)
        Base.show_backtrace(stdout, catch_backtrace())
    end
end

"""
    analyze_campaign_interactive(campaign_path::String)

Load and analyze all experiments in a campaign.
"""
function analyze_campaign_interactive(campaign_path::String)
    println("\n$(BOLD)$(CYAN)═══ Analyzing Campaign ═══$(RESET)\n")
    println("Path: $(BLUE)$campaign_path$(RESET)\n")

    try
        # Load campaign
        println("$(BOLD)Loading campaign experiments...$(RESET)")
        campaign = load_campaign_results(campaign_path)

        println("$(BOLD)Campaign ID:$(RESET) $(campaign.campaign_id)")
        println("$(BOLD)Experiments:$(RESET) $(length(campaign.experiments))")
        println("$(BOLD)Collection Time:$(RESET) $(campaign.collection_timestamp)")
        println()

        # Analyze campaign - this already prints a nice summary
        GlobtimPostProcessing.analyze_campaign(campaign)

    catch e
        println("$(RED)Error analyzing campaign:$(RESET)")
        println(e)
        Base.show_backtrace(stdout, catch_backtrace())
    end
end

"""
    analyze_batch_interactive(experiments::Vector{String}, batch_name::String)

Load and analyze experiments from a batch (flat collection).
"""
function analyze_batch_interactive(experiments::Vector{String}, batch_name::String)
    println("\n$(BOLD)$(CYAN)═══ Analyzing Batch ═══$(RESET)\n")
    println("Batch: $(BLUE)$batch_name$(RESET)")
    println("Experiments: $(length(experiments))\n")

    try
        # Load each experiment
        println("$(BOLD)Loading batch experiments...$(RESET)")
        exp_results = []
        for exp_path in experiments
            try
                result = load_experiment_results(exp_path)
                push!(exp_results, result)
            catch e
                @warn "Failed to load experiment $(basename(exp_path)): $e"
            end
        end

        if isempty(exp_results)
            println("$(RED)No valid experiments could be loaded$(RESET)")
            return
        end

        println("$(BOLD)Successfully loaded:$(RESET) $(length(exp_results)) experiments")
        println()

        # Create a campaign-like structure
        campaign = GlobtimPostProcessing.CampaignResults(
            campaign_id = batch_name,
            experiments = exp_results,
            collection_timestamp = Dates.now()
        )

        # Analyze campaign - this already prints a nice summary
        GlobtimPostProcessing.analyze_campaign(campaign)

    catch e
        println("$(RED)Error analyzing batch:$(RESET)")
        println(e)
        Base.show_backtrace(stdout, catch_backtrace())
    end
end

"""
    load_all_critical_points(exp_path::String) -> Dict{Int, DataFrame}

Load all critical points CSV files for an experiment, indexed by degree.
Uses the ParameterRecovery module's load_critical_points_for_degree function.
"""
function load_all_critical_points(exp_path::String)
    csv_files = filter(f -> startswith(basename(f), "critical_points_deg_"), readdir(exp_path, join=true))

    results = Dict{Int, DataFrame}()
    for csv_file in csv_files
        # Extract degree from filename
        m = match(r"deg_(\d+)\.csv", basename(csv_file))
        if m !== nothing
            degree = parse(Int, m[1])
            df = load_critical_points_for_degree(exp_path, degree)
            results[degree] = df
        end
    end

    return results
end

"""
    extract_param_vector(row, n_params::Int) -> Vector{Float64}

Extract parameter vector [x1, x2, ..., xn] from a DataFrame row.
"""
function extract_param_vector(row, n_params::Int)
    return [row[Symbol("x$i")] for i in 1:n_params]
end

"""
    generate_detailed_table_from_list(exp_dirs::Vector{String}, batch_name::String)

Generate detailed parameter recovery table from a list of experiment directories.
"""
function generate_detailed_table_from_list(exp_dirs::Vector{String}, batch_name::String)
    println("\n$(BOLD)$(CYAN)═══ Detailed Parameter Recovery Analysis ═══$(RESET)\n")
    println("Batch: $(BLUE)$batch_name$(RESET)")
    println("Experiments: $(length(exp_dirs))\n")

    println("="^120)
    println("$(BOLD)📊 DETAILED BATCH ANALYSIS: Parameter Recovery$(RESET)")
    println("="^120)

    # Collect all experiment data
    exp_data = []

    for exp_path in exp_dirs
        exp_name = basename(exp_path)

        # Load config to get true parameters
        try
            config = load_experiment_config(exp_path)

            # Use p_true if available, otherwise use p_center
            p_true = haskey(config, "p_true") ? collect(config["p_true"]) : collect(config["p_center"])
            # Use domain_range if available, otherwise use sample_range
            sample_range = haskey(config, "domain_range") ? config["domain_range"] : config["sample_range"]

            # Load all critical points
            cp_by_degree = load_all_critical_points(exp_path)

            if isempty(cp_by_degree)
                @warn "No critical points found for $exp_name"
                continue
            end

            push!(exp_data, (
                name = exp_name,
                sample_range = sample_range,
                p_true = p_true,
                cp_by_degree = cp_by_degree
            ))
        catch e
            @warn "Failed to load experiment $exp_name: $e"
            continue
        end
    end

    # Continue with rest of detailed table generation (same as original)
    _generate_detailed_table_impl(exp_data)
end

"""
    generate_detailed_table(campaign_path::String)

Generate detailed parameter recovery table from CSV data.
"""
function generate_detailed_table(campaign_path::String)
    println("\n$(BOLD)$(CYAN)═══ Detailed Parameter Recovery Analysis ═══$(RESET)\n")
    println("Path: $(BLUE)$campaign_path$(RESET)\n")

    exp_dirs = filter(isdir, readdir(campaign_path, join=true))
    sort!(exp_dirs)

    println("="^120)
    println("$(BOLD)📊 DETAILED CAMPAIGN ANALYSIS: Parameter Recovery$(RESET)")
    println("="^120)

    # Collect all experiment data
    exp_data = []

    for exp_path in exp_dirs
        exp_name = basename(exp_path)

        # Load config to get true parameters
        try
            config = load_experiment_config(exp_path)

            # Use p_true if available, otherwise use p_center
            p_true = haskey(config, "p_true") ? collect(config["p_true"]) : collect(config["p_center"])
            # Use domain_range if available, otherwise use sample_range
            sample_range = haskey(config, "domain_range") ? config["domain_range"] : config["sample_range"]

            # Load all critical points
            cp_by_degree = load_all_critical_points(exp_path)

            if isempty(cp_by_degree)
                @warn "No critical points found for $exp_name"
                continue
            end

            push!(exp_data, (
                name = exp_name,
                sample_range = sample_range,
                p_true = p_true,
                cp_by_degree = cp_by_degree
            ))
        catch e
            @warn "Failed to load experiment $exp_name: $e"
            continue
        end
    end

    _generate_detailed_table_impl(exp_data)
end

"""
    _generate_detailed_table_impl(exp_data::Vector)

Shared implementation for generating detailed parameter recovery tables.
"""
function _generate_detailed_table_impl(exp_data::Vector)
    # Sort by sample range
    sort!(exp_data, by = x -> x.sample_range)

    # Print summary table
    println("\n$(BOLD)📋 SUMMARY BY EXPERIMENT$(RESET)")
    println("-"^120)
    @printf("%-50s | %12s | %12s | %20s | %20s\n",
        "Experiment", "Range", "# Degrees", "Total Crit Pts", "Best Distance")
    println("-"^120)

    for exp in exp_data
        total_cp = sum(nrow(df) for df in values(exp.cp_by_degree))
        degrees = sort(collect(keys(exp.cp_by_degree)))

        # Find best parameter recovery across all degrees
        best_dist = Inf
        n_params = length(exp.p_true)
        for (_, df) in exp.cp_by_degree
            if nrow(df) > 0
                distances = [param_distance(extract_param_vector(row, n_params), exp.p_true) for row in eachrow(df)]
                best_dist = min(best_dist, minimum(distances))
            end
        end

        short_name = replace(exp.name, r"^lotka_volterra_4d_" => "")

        @printf("%-50s | %12s | %12d | %20d | %20.6f\n",
            short_name, "±$(exp.sample_range)", length(degrees), total_cp,
            best_dist == Inf ? NaN : best_dist)
    end

    println("-"^120)

    # Print detailed per-degree breakdown
    println("\n$(BOLD)📈 DETAILED PER-DEGREE ANALYSIS$(RESET)")
    println("="^120)

    for exp in exp_data
        println("\n$(BOLD)$(exp.name)$(RESET)")
        println("  Sample range: ±$(exp.sample_range)")
        println("  True parameters: [$(join([@sprintf("%.6f", p) for p in exp.p_true], ", "))]")
        println()

        @printf("  %-8s | %12s | %20s | %20s | %20s\n",
            "Degree", "# Crit Pts", "Min Distance", "Mean Distance", "Best Objective")
        println("  " * "-"^100)

        degrees = sort(collect(keys(exp.cp_by_degree)))
        n_params = length(exp.p_true)

        for deg in degrees
            df = exp.cp_by_degree[deg]
            n_cp = nrow(df)

            if n_cp > 0
                # Compute distances to true parameter using module function
                distances = [param_distance(extract_param_vector(row, n_params), exp.p_true) for row in eachrow(df)]
                min_dist = minimum(distances)
                mean_dist = mean(distances)
                best_obj = minimum(df.z)

                @printf("  %-8d | %12d | %20.6f | %20.6f | %20.3e\n",
                    deg, n_cp, min_dist, mean_dist, best_obj)
            else
                @printf("  %-8d | %12d | %20s | %20s | %20s\n",
                    deg, n_cp, "N/A", "N/A", "N/A")
            end
        end
    end

    # Convergence analysis: how does best distance improve with degree?
    println("\n$(BOLD)📉 CONVERGENCE ANALYSIS: Best Parameter Distance vs Degree$(RESET)")
    println("="^120)
    println()

    # Create convergence table
    @printf("%-8s", "Degree")
    for (i, exp) in enumerate(exp_data)
        # Try to extract exp number from name, otherwise use index
        m = match(r"_exp(\d+)_", exp.name)
        if m !== nothing
            short_name = "Exp$(m[1])"
        else
            # Use range and index for experiments with same range
            short_name = "±$(exp.sample_range) #$i"
        end
        @printf(" | %15s", short_name)
    end
    println()
    println("-"^(8 + length(exp_data) * 18))

    # Get all unique degrees
    all_degrees = Set{Int}()
    for exp in exp_data
        union!(all_degrees, keys(exp.cp_by_degree))
    end
    degrees = sort(collect(all_degrees))

    for deg in degrees
        @printf("%-8d", deg)

        for exp in exp_data
            if haskey(exp.cp_by_degree, deg)
                df = exp.cp_by_degree[deg]
                if nrow(df) > 0
                    n_params = length(exp.p_true)
                    distances = [param_distance(extract_param_vector(row, n_params), exp.p_true) for row in eachrow(df)]
                    min_dist = minimum(distances)
                    @printf(" | %15.6f", min_dist)
                else
                    @printf(" | %15s", "N/A")
                end
            else
                @printf(" | %15s", "-")
            end
        end
        println()
    end

    println("\n" * "="^120)
end

"""
    analyze_trajectories_interactive(exp_path::String)

Interactive trajectory analysis for critical point evaluation.

Allows user to:
1. View convergence analysis across degrees
2. Select a specific degree
3. Inspect individual critical points
4. Evaluate trajectory quality for selected critical points
"""
function analyze_trajectories_interactive(exp_path::String)
    println("\n$(BOLD)$(CYAN)═══ Interactive Trajectory Analysis ═══$(RESET)\n")
    println("Path: $(BLUE)$exp_path$(RESET)\n")

    try
        # Step 1: Show convergence overview
        println("$(BOLD)Computing convergence analysis...$(RESET)\n")
        convergence = TrajectoryComparison.analyze_experiment_convergence(exp_path)

        if isempty(convergence.degrees)
            println("$(RED)No critical points found for this experiment.$(RESET)")
            return
        end

        println("$(BOLD)$(GREEN)Convergence Summary:$(RESET)")
        println("-" ^ 80)
        @printf("%-8s | %14s | %10s | %18s | %18s\n",
               "Degree", "Critical Pts", "Recoveries", "Best Param Dist", "Best Traj Dist")
        println("-" ^ 80)

        for deg in convergence.degrees
            @printf("%-8d | %14d | %10d | %18.6e | %18.6e\n",
                   deg,
                   convergence.num_critical_points_by_degree[deg],
                   convergence.num_recoveries_by_degree[deg],
                   convergence.best_param_distance_by_degree[deg],
                   convergence.best_trajectory_distance_by_degree[deg])
        end
        println("-" ^ 80)
        println()

        # Step 2: Select degree
        println("$(BOLD)Available degrees:$(RESET) $(join(convergence.degrees, ", "))")
        degree_choice = get_user_choice("Select degree to analyze", length(convergence.degrees))
        selected_degree = convergence.degrees[degree_choice]

        println("\n$(BOLD)Analyzing degree $selected_degree...$(RESET)\n")

        # Step 3: Load and evaluate critical points for selected degree
        cp_df = TrajectoryComparison.load_critical_points_for_degree(exp_path, selected_degree)

        if nrow(cp_df) == 0
            println("$(YELLOW)No critical points found for degree $selected_degree.$(RESET)")
            return
        end

        config = convergence.config
        evaluated_df = TrajectoryComparison.evaluate_all_critical_points(config, cp_df)

        # Rank by parameter distance
        ranked_df = TrajectoryComparison.rank_critical_points(evaluated_df, :param_distance)

        # Display top critical points
        n_display = min(20, nrow(ranked_df))
        println("$(BOLD)$(GREEN)Top $n_display Critical Points (by parameter distance):$(RESET)")
        println("-" ^ 120)
        @printf("%-6s | %-10s | %-18s | %-18s | %-18s | %-10s\n",
               "Rank", "Objective", "Param Distance", "Traj Distance", "Is Recovery", "Params")
        println("-" ^ 120)

        for i in 1:n_display
            row = ranked_df[i, :]
            n_params = length(config["p_true"])
            param_str = "[" * join([@sprintf("%.4f", row[Symbol("x$j")]) for j in 1:n_params], ", ") * "]"

            recovery_str = row.is_recovery ? "$(GREEN)✓$(RESET)" : "$(RED)✗$(RESET)"

            @printf("%-6d | %-10.3e | %-18.6e | %-18.6e | %-10s | %s\n",
                   i,
                   row.z,
                   row.param_distance,
                   row.trajectory_distance,
                   recovery_str,
                   param_str)
        end
        println("-" ^ 120)
        println()

        # Step 4: Interactive critical point selection
        while true
            print("$(BOLD)Enter critical point rank to inspect (1-$(nrow(ranked_df)), or 'q' to quit):$(RESET) ")
            response = strip(readline())

            if lowercase(response) == "q"
                break
            end

            try
                rank = parse(Int, response)
                if 1 <= rank <= nrow(ranked_df)
                    inspect_critical_point(ranked_df[rank, :], config, selected_degree)
                else
                    println("$(RED)Please enter a rank between 1 and $(nrow(ranked_df))$(RESET)")
                end
            catch
                println("$(RED)Invalid input. Please enter a number or 'q' to quit$(RESET)")
            end
        end

    catch e
        println("$(RED)Error during trajectory analysis:$(RESET)")
        println(e)
        Base.show_backtrace(stdout, catch_backtrace())
    end
end

"""
    inspect_critical_point(cp_row, config::Dict, degree::Int)

Display detailed information about a specific critical point.
"""
function inspect_critical_point(cp_row, config, degree::Int)
    println("\n$(BOLD)$(CYAN)═══ Critical Point Details ═══$(RESET)\n")

    n_params = length(config["p_true"])
    p_found = [cp_row[Symbol("x$i")] for i in 1:n_params]
    p_true = collect(config["p_true"])

    println("$(BOLD)Polynomial Degree:$(RESET) $degree")
    println("$(BOLD)Rank:$(RESET) $(cp_row.rank)")
    println()

    println("$(BOLD)Parameter Values:$(RESET)")
    println("  Found: [$(join([@sprintf("%.6f", p) for p in p_found], ", "))]")
    println("  True:  [$(join([@sprintf("%.6f", p) for p in p_true], ", "))]")
    println()

    println("$(BOLD)Quality Metrics:$(RESET)")
    @printf("  Objective function value:  %.6e\n", cp_row.z)
    @printf("  Parameter distance (L2):   %.6e\n", cp_row.param_distance)
    @printf("  Trajectory distance (L2):  %.6e\n", cp_row.trajectory_distance)
    println("  Parameter recovery:        ", cp_row.is_recovery ? "$(GREEN)YES$(RESET)" : "$(RED)NO$(RESET)")
    println()

    # Component-wise parameter comparison
    println("$(BOLD)Component-wise Parameter Comparison:$(RESET)")
    @printf("  %-10s | %-15s | %-15s | %-15s\n", "Component", "Found", "True", "Abs Error")
    println("  " * "-"^60)
    for i in 1:n_params
        @printf("  %-10s | %15.6f | %15.6f | %15.6e\n",
               "p$i",
               p_found[i],
               p_true[i],
               abs(p_found[i] - p_true[i]))
    end
    println()
end

"""
    display_batches(batches::Vector{BatchInfo})

Display discovered batches in a numbered list, sorted by modification time (newest first).
"""
function display_batches(batches::Vector{BatchInfo})
    println("\n$(BOLD)$(CYAN)═══ Discovered Batches (sorted by newest first) ═══$(RESET)\n")

    for (idx, batch) in enumerate(batches)
        # Format timestamp
        timestamp = Dates.unix2datetime(batch.mtime)
        time_str = Dates.format(timestamp, "yyyy-mm-dd HH:MM:SS")

        # Add "LATEST" marker for the first one
        latest_marker = idx == 1 ? " $(BOLD)$(GREEN)[LATEST]$(RESET)" : ""

        println("$(BOLD)$idx.$(RESET) $(GREEN)$(batch.batch_name)$(RESET)$latest_marker")
        println("   Experiments: $(length(batch.experiments))")
        println("   Modified: $time_str")
        println("   Location: $(BLUE)$(batch.collection_path)$(RESET)\n")
    end
end

"""
    get_experiments_for_batch(batch::BatchInfo) -> Vector{String}

Get all experiment paths from a BatchInfo object.
"""
function get_experiments_for_batch(batch::BatchInfo)
    return [exp.path for exp in batch.experiments]
end

"""
    group_by_config_param(experiments::Vector{String}, param_key::String)
    -> Dict{Any, Vector{String}}

Group experiments by a specific config parameter value.
Wrapper that converts String paths to work with ExperimentCollector.
"""
function group_by_config_param(experiments::Vector{String}, param_key::String)
    # Convert String paths to ExperimentInfo objects
    exp_infos = ExperimentInfo[]
    for exp_path in experiments
        validation = validate_experiment(exp_path)
        config = load_experiment_config(exp_path)
        push!(exp_infos, ExperimentInfo(
            exp_path,
            basename(exp_path),
            nothing,
            config,
            validation
        ))
    end

    # Use ExperimentCollector's group_by_config_param
    groups_by_info = ExperimentCollector.group_by_config_param(exp_infos, param_key)

    # Convert back to String paths
    groups = Dict{Any, Vector{String}}()
    for (key, infos) in groups_by_info
        groups[key] = [info.path for info in infos]
    end

    return groups
end

"""
    group_by_degree_range(experiments::Vector{String})
    -> Dict{Tuple{Int,Int}, Vector{String}}

Group experiments by (min_degree, max_degree) range.
Wrapper that converts String paths to work with ExperimentCollector.
"""
function group_by_degree_range(experiments::Vector{String})
    # Convert String paths to ExperimentInfo objects
    exp_infos = ExperimentInfo[]
    for exp_path in experiments
        validation = validate_experiment(exp_path)
        config = load_experiment_config(exp_path)
        push!(exp_infos, ExperimentInfo(
            exp_path,
            basename(exp_path),
            nothing,
            config,
            validation
        ))
    end

    # Use ExperimentCollector's group_by_degree_range
    groups_by_info = ExperimentCollector.group_by_degree_range(exp_infos)

    # Convert back to String paths
    groups = Dict{Tuple{Int,Int}, Vector{String}}()
    for (key, infos) in groups_by_info
        groups[key] = [info.path for info in infos]
    end

    return groups
end

"""
    select_from_hierarchical(experiments_by_obj::Dict{String, Vector{String}})
    -> Vector{String}

Interactive selection from hierarchical experiment structure.
Returns selected experiment paths.
"""
function select_from_hierarchical(experiments_by_obj::Dict{String, Vector{String}})
    # Step 1: Select objective function with enhanced metadata display
    obj_names = sort(collect(keys(experiments_by_obj)))

    println("\n$(BOLD)$(CYAN)═══ Select Objective Function ═══$(RESET)\n")

    # Display objectives with metadata
    for (idx, obj_name) in enumerate(obj_names)
        experiments = experiments_by_obj[obj_name]
        n_exp = length(experiments)

        # Get timestamp range (oldest to newest)
        if !isempty(experiments)
            mtimes = Float64[]
            for exp_path in experiments
                try
                    push!(mtimes, stat(exp_path).mtime)
                catch
                    # Skip if stat fails
                end
            end

            if !isempty(mtimes)
                oldest = Dates.unix2datetime(minimum(mtimes))
                newest = Dates.unix2datetime(maximum(mtimes))
                oldest_str = Dates.format(oldest, "yyyy-mm-dd HH:MM")
                newest_str = Dates.format(newest, "yyyy-mm-dd HH:MM")

                println("$(BOLD)$idx.$(RESET) $(GREEN)$obj_name$(RESET)")
                println("   Experiments: $n_exp")
                if oldest == newest
                    println("   Created: $newest_str")
                else
                    println("   Time range: $oldest_str → $newest_str")
                end
                println()
            else
                println("$(BOLD)$idx.$(RESET) $(GREEN)$obj_name$(RESET) ($n_exp experiments)")
            end
        else
            println("$(BOLD)$idx.$(RESET) $(GREEN)$obj_name$(RESET) ($n_exp experiments)")
        end
    end

    obj_choice = get_user_choice("Select objective", length(obj_names))
    selected_obj = obj_names[obj_choice]
    experiments = experiments_by_obj[selected_obj]

    println("\n$(BOLD)Selected objective:$(RESET) $(GREEN)$selected_obj$(RESET)")
    println("$(BOLD)Experiments:$(RESET) $(length(experiments))")

    # Step 2: Group by config parameters for batch selection
    println("\n$(BOLD)Group experiments by:$(RESET)")
    println("$(BOLD)1.$(RESET) Domain size parameter")
    println("$(BOLD)2.$(RESET) Grid nodes")
    println("$(BOLD)3.$(RESET) Degree range")
    println("$(BOLD)4.$(RESET) No grouping (all experiments)")

    group_choice = get_user_choice("Select grouping", 4)

    if group_choice == 1
        groups = group_by_config_param(experiments, "domain_size_param")
        group_label = "domain_size_param"
    elseif group_choice == 2
        groups = group_by_config_param(experiments, "grid_nodes")
        group_label = "grid_nodes"
    elseif group_choice == 3
        groups = group_by_degree_range(experiments)
        group_label = "degree_range"
    else
        return experiments  # No grouping - return all experiments
    end

    if isempty(groups)
        println("$(YELLOW)No groups found for the selected parameter. Using all experiments.$(RESET)")
        return experiments
    end

    # Step 3: Display and select from groups
    println("\n$(BOLD)$(CYAN)═══ Select Group ═══$(RESET)\n")
    group_keys = sort(collect(keys(groups)))

    for (idx, key) in enumerate(group_keys)
        n_exp = length(groups[key])
        if group_choice == 3  # degree_range
            println("$(BOLD)$idx.$(RESET) $(GREEN)Degrees $(key[1])-$(key[2])$(RESET) ($n_exp experiments)")
        else
            println("$(BOLD)$idx.$(RESET) $(GREEN)$group_label = $key$(RESET) ($n_exp experiments)")
        end
    end
    println("$(BOLD)$(length(group_keys)+1).$(RESET) All groups combined ($(length(experiments)) experiments)")

    group_selection = get_user_choice("Select group", length(group_keys) + 1)

    if group_selection <= length(group_keys)
        selected_key = group_keys[group_selection]
        selected_experiments = groups[selected_key]
        println("\n$(BOLD)Selected:$(RESET) $(length(selected_experiments)) experiments")
        return selected_experiments
    else
        println("\n$(BOLD)Selected:$(RESET) All experiments ($(length(experiments)))")
        return experiments
    end
end

"""
    main()

Main interactive loop.
"""
function main()
    # Parse command line arguments
    experiment_root = if length(ARGS) >= 2 && ARGS[1] == "--path"
        ARGS[2]
    else
        # Try GLOBTIM_RESULTS_ROOT first, then intelligently search for globtim_results
        if haskey(ENV, "GLOBTIM_RESULTS_ROOT")
            results_root = ENV["GLOBTIM_RESULTS_ROOT"]
            if !isdir(results_root)
                error("GLOBTIM_RESULTS_ROOT is set but directory does not exist: '$results_root'")
            end
            results_root
        else
            # Smart search for globtim_results in GlobalOptim hierarchy
            candidates = [
                joinpath(homedir(), "GlobalOptim", "globtim_results"),
                joinpath(dirname(@__DIR__), "globtim_results"),  # ../globtim_results
                joinpath(pwd(), "globtim_results"),              # ./globtim_results
                # Also try finding GlobalOptim parent
                joinpath(dirname(dirname(@__DIR__)), "globtim_results")
            ]

            results_root = nothing
            for candidate in candidates
                if isdir(candidate)
                    results_root = candidate
                    break
                end
            end

            if isnothing(results_root)
                error("""
                    Could not find globtim_results directory!

                    Searched locations:
                    $(join(["  - " * c for c in candidates], "\n"))

                    Solutions:
                    1. Set GLOBTIM_RESULTS_ROOT: export GLOBTIM_RESULTS_ROOT=~/GlobalOptim/globtim_results
                    2. Use --path: julia analyze_experiments.jl --path /path/to/results
                    3. Run from GlobalOptim directory with globtim_results/ subdirectory
                    """)
            end

            results_root
        end
    end

    println("$(BOLD)$(CYAN)╔════════════════════════════════════════════════╗$(RESET)")
    println("$(BOLD)$(CYAN)║  GlobTim Post-Processing: Interactive Analysis ║$(RESET)")
    println("$(BOLD)$(CYAN)╚════════════════════════════════════════════════╝$(RESET)")
    println()
    println("$(BOLD)Results root:$(RESET)")
    println("  $(BLUE)$experiment_root$(RESET)")

    # Detect directory structure
    structure = detect_directory_structure(experiment_root)

    print("\n$(BOLD)Detected structure:$(RESET) ")
    if structure == Hierarchical
        println("$(GREEN)Hierarchical$(RESET) (organized by objective function)")
    elseif structure == Flat
        println("$(YELLOW)Flat$(RESET) (all experiments in one directory)")
    else
        println("$(RED)Unknown$(RESET)")
    end

    # Initialize variables for tracking state
    experiments = String[]
    valid_flags = Bool[]
    batch_name = ""
    selected_campaign = ""

    if structure == Unknown
        println("\n$(YELLOW)Could not detect flat or hierarchical structure at top level.$(RESET)")
        println("$(YELLOW)Searching recursively for campaign directories...$(RESET)\n")

        # Try to discover campaigns recursively
        campaigns = discover_campaigns(experiment_root)

        if isempty(campaigns)
            println("\n$(RED)Could not find any campaigns or experiments in $experiment_root$(RESET)")
            println("$(YELLOW)Hint: Make sure the directory contains:$(RESET)")
            println("  - Campaign directories with hpc_results/ subdirectories")
            println("  - Or flat experiment directories")
            println("  - Or hierarchical objective/experiment directories")
            exit(1)
        end

        # Found campaigns - display and let user select
        display_campaigns(campaigns)
        campaign_choice = get_user_choice("Select campaign", length(campaigns))
        selected_campaign_info = campaigns[campaign_choice]
        selected_campaign = selected_campaign_info.path

        # Now display experiments in this campaign and continue with existing flow
        experiments, valid_flags = display_experiment_list(selected_campaign)
        batch_name = selected_campaign_info.name

    elseif structure == Hierarchical
        println("\n$(BOLD)Detected hierarchical experiment structure.$(RESET)")

        # Discover experiments by objective using ExperimentCollector
        experiments_by_obj_info = discover_experiments_hierarchical(experiment_root)

        if isempty(experiments_by_obj_info)
            println("\n$(RED)No experiments found in hierarchical structure.$(RESET)")
            exit(1)
        end

        # Convert ExperimentInfo to String paths for compatibility with existing code
        experiments_by_obj = Dict{String, Vector{String}}()
        for (obj_name, exp_infos) in experiments_by_obj_info
            experiments_by_obj[obj_name] = [exp.path for exp in exp_infos]
        end

        # Interactive selection
        experiments = select_from_hierarchical(experiments_by_obj)

        if isempty(experiments)
            println("\n$(RED)No experiments selected.$(RESET)")
            exit(1)
        end

        # Display selected experiments
        println("\n$(BOLD)$(CYAN)═══ Selected Experiments ═══$(RESET)\n")
        for (idx, exp_path) in enumerate(experiments)
            exp_name = basename(exp_path)

            # Check if results exist and are valid
            results_file = joinpath(exp_path, "results_summary.json")
            has_results = false
            status_msg = ""

            if isfile(results_file)
                file_size = stat(results_file).size
                if file_size == 0
                    status = "$(YELLOW)⚠$(RESET)"
                    status_msg = " (empty results file)"
                else
                    status = "$(GREEN)✓$(RESET)"
                    has_results = true
                end
            else
                status = "$(RED)✗$(RESET)"
                status_msg = " (no results file)"
            end

            push!(valid_flags, has_results)

            println("$(BOLD)$idx.$(RESET) $status $(BLUE)$exp_name$(RESET)$status_msg")
            println("   Path: $exp_path")

            if has_results
                try
                    result = load_experiment_results(exp_path)
                    if !isempty(result.enabled_tracking)
                        println("   Tracking: $(join(result.enabled_tracking, ", "))")
                    else
                        println("   $(YELLOW)Warning: No tracking labels enabled$(RESET)")
                    end
                catch e
                    println("   $(RED)Error loading: $(sprint(showerror, e))$(RESET)")
                    valid_flags[end] = false
                end
            end
            println()
        end

        # Use the first experiment's parent directory as selected_campaign for compatibility
        if !isempty(experiments)
            selected_campaign = dirname(experiments[1])
        end

    elseif structure == Flat
        println("\n$(BOLD)Detected flat experiment collection. Grouping by batch...$(RESET)")

        # Discover batches using ExperimentCollector
        batches = discover_batches(experiment_root)

        if isempty(batches)
            # Check if there's a single experiment we can analyze directly
            all_entries = readdir(experiment_root, join=true)
            experiment_dirs = filter(isdir, all_entries)

            if length(experiment_dirs) == 1
                single_exp = experiment_dirs[1]
                println("\n$(YELLOW)Found single experiment (not a batch). Analyzing directly...$(RESET)")
                println("  $(BLUE)$(basename(single_exp))$(RESET)\n")

                # Call analyze_single_experiment directly
                analyze_single_experiment(single_exp)
                exit(0)
            else
                println("\n$(RED)No batches found (need at least 2 experiments per batch).$(RESET)")
                exit(1)
            end
        end

        # Display batches
        display_batches(batches)

        # Select batch
        batch_choice = get_user_choice("Select batch", length(batches))
        selected_batch = batches[batch_choice]

        # Get experiments for this batch
        experiments = get_experiments_for_batch(selected_batch)
        batch_name = selected_batch.batch_name
        println("\n$(BOLD)Selected batch: $(GREEN)$batch_name$(RESET)$(RESET)")
        println("$(BOLD)Experiments in batch:$(RESET) $(length(experiments))")

        # Create a virtual campaign path for display
        selected_campaign = selected_batch.collection_path

        # Display experiments (but filter to only show those in this batch)
        println("\n$(BOLD)$(CYAN)═══ Experiments in Batch ═══$(RESET)\n")
        valid_flags = Bool[]

        for (idx, exp_path) in enumerate(experiments)
            exp_name = basename(exp_path)

            # Check if results exist and are valid
            results_file = joinpath(exp_path, "results_summary.json")
            has_results = false
            status_msg = ""

            if isfile(results_file)
                file_size = stat(results_file).size
                if file_size == 0
                    status = "$(YELLOW)⚠$(RESET)"
                    status_msg = " (empty results file)"
                else
                    status = "$(GREEN)✓$(RESET)"
                    has_results = true
                end
            else
                status = "$(RED)✗$(RESET)"
                status_msg = " (no results file)"
            end

            push!(valid_flags, has_results)

            println("$(BOLD)$idx.$(RESET) $status $(BLUE)$exp_name$(RESET)$status_msg")
            println("   Path: $exp_path")

            if has_results
                try
                    result = load_experiment_results(exp_path)
                    if !isempty(result.enabled_tracking)
                        println("   Tracking: $(join(result.enabled_tracking, ", "))")
                    else
                        println("   $(YELLOW)Warning: No tracking labels enabled$(RESET)")
                    end
                catch e
                    println("   $(RED)Error loading: $(sprint(showerror, e))$(RESET)")
                    valid_flags[end] = false
                end
            end
            println()
        end
    end

    if isempty(experiments)
        println("$(RED)No experiments found in campaign$(RESET)")
        exit(1)
    end

    # Count valid experiments
    num_valid = count(valid_flags)
    if num_valid == 0
        println("$(RED)No valid experiments found in campaign (all missing or incomplete results)$(RESET)")
        exit(1)
    end

    # NEW: Allow user to select specific experiment(s) before choosing analysis mode
    println("\n$(BOLD)$(CYAN)═══ Select Experiment Scope ═══$(RESET)\n")
    println("$(BOLD)1.$(RESET) Select specific experiment (for detailed single-experiment analysis)")
    println("$(BOLD)2.$(RESET) Use all experiments (for campaign-wide analysis)")
    println()

    scope_choice = get_user_choice("Select scope", 2)

    selected_exp_idx = nothing
    if scope_choice == 1
        # User wants to select a specific experiment
        if num_valid == 0
            println("$(RED)No valid experiments available$(RESET)")
            exit(1)
        end
        selected_exp_idx = get_user_choice("Select experiment", length(experiments))
        if !valid_flags[selected_exp_idx]
            println("$(YELLOW)Warning: Selected experiment does not have valid results$(RESET)")
        end
    end

    # Analysis mode selection - adjust menu based on scope
    println("\n$(BOLD)$(CYAN)═══ Analysis Mode ═══$(RESET)\n")

    if !isnothing(selected_exp_idx)
        # Single experiment selected - only show single-experiment modes
        println("$(BOLD)1.$(RESET) Analyze single experiment (requires valid results)")
        println("$(BOLD)2.$(RESET) Interactive trajectory analysis (requires valid results)")
        println()
        mode_choice = get_user_choice("Select mode", 2)

        # Map to original mode numbers (1→1, 2→4)
        actual_mode = mode_choice == 1 ? 1 : 4
    else
        # All experiments selected - show all modes
        println("$(BOLD)1.$(RESET) Analyze single experiment (requires valid results)")
        println("$(BOLD)2.$(RESET) Analyze entire campaign (aggregated statistics, uses all valid experiments)")
        println("$(BOLD)3.$(RESET) Detailed parameter recovery table (uses all experiments with CSV data)")
        println("$(BOLD)4.$(RESET) Interactive trajectory analysis (requires valid results)")
        println()
        actual_mode = get_user_choice("Select mode", 4)
    end

    if actual_mode == 1
        # Single experiment - require valid results
        if !isnothing(selected_exp_idx)
            # Use pre-selected experiment
            if !valid_flags[selected_exp_idx]
                println("$(RED)Selected experiment does not have valid results. Please select an experiment marked with $(GREEN)✓$(RESET)")
                exit(1)
            end
            analyze_single_experiment(experiments[selected_exp_idx])
        else
            # Ask user to select experiment
            if num_valid == 0
                println("$(RED)No valid experiments available for single experiment analysis$(RESET)")
                exit(1)
            end
            exp_choice = get_user_choice("Select experiment", length(experiments))
            if !valid_flags[exp_choice]
                println("$(RED)Selected experiment does not have valid results. Please select an experiment marked with $(GREEN)✓$(RESET)")
                exit(1)
            end
            analyze_single_experiment(experiments[exp_choice])
        end
    elseif actual_mode == 2
        # Entire campaign - works with partial results
        if structure == :flat
            # For flat collections, we need to pass the filtered experiments
            analyze_batch_interactive(experiments, batch_name)
        elseif structure == :hierarchical
            # For hierarchical, use batch name as the selected objective
            obj_name = basename(selected_campaign)
            analyze_batch_interactive(experiments, obj_name)
        else
            analyze_campaign_interactive(selected_campaign)
        end
    elseif actual_mode == 3
        # Detailed parameter recovery table - works with CSV data
        if structure == :flat
            generate_detailed_table_from_list(experiments, batch_name)
        elseif structure == :hierarchical
            # For hierarchical, use selected experiments
            obj_name = basename(selected_campaign)
            generate_detailed_table_from_list(experiments, obj_name)
        else
            generate_detailed_table(selected_campaign)
        end
    else
        # Interactive trajectory analysis (mode 4) - require valid results
        if !isnothing(selected_exp_idx)
            # Use pre-selected experiment
            if !valid_flags[selected_exp_idx]
                println("$(RED)Selected experiment does not have valid results. Please select an experiment marked with $(GREEN)✓$(RESET)")
                exit(1)
            end
            analyze_trajectories_interactive(experiments[selected_exp_idx])
        else
            # Ask user to select experiment
            if num_valid == 0
                println("$(RED)No valid experiments available for trajectory analysis$(RESET)")
                exit(1)
            end
            exp_choice = get_user_choice("Select experiment", length(experiments))
            if !valid_flags[exp_choice]
                println("$(RED)Selected experiment does not have valid results. Please select an experiment marked with $(GREEN)✓$(RESET)")
                exit(1)
            end
            analyze_trajectories_interactive(experiments[exp_choice])
        end
    end

    println("\n$(BOLD)$(GREEN)═══ Analysis Complete ═══$(RESET)\n")
end

# Run main
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
