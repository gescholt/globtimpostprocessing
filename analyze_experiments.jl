#!/usr/bin/env julia

"""
Interactive Experiment Analysis Entry Point

Simplified workflow:
1. Show directories in globtim_results/ (excluding indices/)
2. Select ONE directory (objective function)
3. Recursively find experiments in that directory
4. Display flat list (sorted newest first)
5. Select ONE experiment
6. Show convergence by degree table with numerical stability metrics
7. Done

Requirements:
    GLOBTIM_RESULTS_ROOT environment variable must be set.
    Run: cd globtimcore && ./scripts/setup_results_root.sh

Usage:
    julia analyze_experiments.jl [--path <custom_path>]

If no path is provided, uses \$GLOBTIM_RESULTS_ROOT automatically.
"""

using Pkg
Pkg.activate(@__DIR__)

using GlobtimPostProcessing
using GlobtimPostProcessing: load_experiment_config, load_experiment_results,
                             compute_statistics, has_ground_truth,
                             load_critical_points_for_degree,
                             compute_parameter_recovery_stats,
                             load_quality_thresholds, check_l2_quality,
                             detect_stagnation, check_objective_distribution_quality
using DataFrames
using Printf
using Dates
using JSON3
using Statistics

# Terminal colors for better UX
const RESET = "\033[0m"
const BOLD = "\033[1m"
const GREEN = "\033[32m"
const BLUE = "\033[34m"
const YELLOW = "\033[33m"
const RED = "\033[31m"
const CYAN = "\033[36m"

# ===== CORE HELPER FUNCTIONS =====

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
    get_objective_directories(results_root::String) -> Vector{String}

Get list of objective function directories in results root, excluding special directories.
"""
function get_objective_directories(results_root::String)
    dirs = String[]

    for entry in readdir(results_root, join=true)
        if isdir(entry)
            basename_entry = basename(entry)
            # Exclude git, hidden directories, and indices
            if !startswith(basename_entry, ".") && basename_entry != "indices"
                push!(dirs, entry)
            end
        end
    end

    # Sort by modification time (newest first)
    sort!(dirs, by = p -> -stat(p).mtime)

    return dirs
end

"""
    display_objective_directories(dirs::Vector{String})

Display available objective function directories.
"""
function display_objective_directories(dirs::Vector{String})
    println("\n$(BOLD)$(CYAN)═══ Available Objective Functions ═══$(RESET)\n")

    for (idx, dir_path) in enumerate(dirs)
        dir_name = basename(dir_path)

        # Count experiments in this directory
        n_experiments = length(find_all_experiments_recursive(dir_path))

        # Format timestamp
        mtime = stat(dir_path).mtime
        timestamp = Dates.unix2datetime(mtime)
        time_str = Dates.format(timestamp, "yyyy-mm-dd HH:MM")

        # Add "LATEST" marker for the first one
        latest_marker = idx == 1 ? " $(BOLD)$(GREEN)[LATEST]$(RESET)" : ""

        println("$(BOLD)$idx.$(RESET) $(BLUE)$dir_name$(RESET)$latest_marker")
        println("   Experiments: $n_experiments")
        println("   Modified: $time_str\n")
    end
end

"""
    find_all_experiments_recursive(root_path::String) -> Vector{String}

Recursively find all experiment directories with results_summary.json.
Returns paths sorted by modification time (newest first).
"""
function find_all_experiments_recursive(root_path::String)
    experiments = String[]

    for (root, dirs, files) in walkdir(root_path)
        if "results_summary.json" in files
            push!(experiments, root)
        end
    end

    # Sort by modification time (newest first)
    sort!(experiments, by = p -> -stat(p).mtime)

    return experiments
end

"""
    display_experiments_list(experiments::Vector{String})

Display all found experiments in a numbered list with status indicators.
"""
function display_experiments_list(experiments::Vector{String})
    println("\n$(BOLD)$(CYAN)═══ Found $(length(experiments)) Experiments (sorted newest first) ═══$(RESET)\n")

    for (idx, exp_path) in enumerate(experiments)
        exp_name = basename(exp_path)

        # Format timestamp
        mtime = stat(exp_path).mtime
        timestamp = Dates.unix2datetime(mtime)
        time_str = Dates.format(timestamp, "yyyy-mm-dd HH:MM")

        # Check if results exist and are valid
        results_file = joinpath(exp_path, "results_summary.json")
        status = if isfile(results_file) && stat(results_file).size > 0
            "$(GREEN)✓$(RESET)"
        elseif isfile(results_file)
            "$(YELLOW)⚠$(RESET)"
        else
            "$(RED)✗$(RESET)"
        end

        # Add "LATEST" marker for the first one
        latest_marker = idx == 1 ? " $(BOLD)$(GREEN)[LATEST]$(RESET)" : ""

        println("$(BOLD)$idx.$(RESET) $status $(BLUE)$exp_name$(RESET)$latest_marker")
        println("   Modified: $time_str")
        println("   Path: $exp_path\n")
    end
end

"""
    display_experiment_metadata(exp_path::String)

Display experiment metadata from results_summary.json if available.
"""
function display_experiment_metadata(exp_path::String)
    try
        results_summary_path = joinpath(exp_path, "results_summary.json")
        if !isfile(results_summary_path)
            return
        end

        json_text = read(results_summary_path, String)
        data = JSON3.read(json_text)

        # Check if new format with metadata (data is an object, not array)
        if isa(data, JSON3.Object) && haskey(data, "metadata")
            metadata = data["metadata"]
            println("  $(BOLD)Experiment Metadata:$(RESET)")

            # Display key configuration parameters
            if haskey(metadata, "loss_function")
                println("    Loss function: $(metadata["loss_function"])")
            else
                println("    Loss function: $(YELLOW)not specified$(RESET)")
            end

            if haskey(metadata, "basis")
                println("    Basis: $(metadata["basis"])")
            else
                println("    Basis: $(YELLOW)not specified$(RESET)")
            end

            if haskey(metadata, "support_type")
                println("    Support type: $(metadata["support_type"])")
            else
                println("    Support type: $(YELLOW)not specified$(RESET)")
            end

            if haskey(metadata, "campaign")
                println("    Campaign: $(metadata["campaign"])")
            end

            if haskey(metadata, "dimension")
                println("    Dimension: $(metadata["dimension"])")
            end

            if haskey(metadata, "GN")
                println("    GN: $(metadata["GN"])")
            end
            println()
        else
            println("  $(YELLOW)No metadata available (old format)$(RESET)")
            println()
        end
    catch
        # Silently skip if metadata not available
    end
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

        # Parse JSON line by line to extract L2 norms
        l2_norms = Float64[]
        degrees = Int[]
        best_values = Float64[]

        json_text = read(results_summary_path, String)

        # Handle both old format (array) and new format (object with metadata+results)
        # For new format, we extract from the "results" field
        # For old format, we extract directly from the array
        # Both work with regex on the JSON text

        # Extract L2_norm values using regex
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

Display L2-norm convergence tracking table with numerical stability metrics.
Enhanced to include condition numbers and numerical rank from statistics.
"""
function display_convergence_by_degree(exp_path::String)
    try
        # Load experiment results
        result = load_experiment_results(exp_path)

        # Compute statistics
        stats = compute_statistics(result)

        # Extract numerical_stability data if available
        numerical_stability = get(stats, "numerical_stability", Dict())

        # Load results summary for degree-by-degree data
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
        condition_numbers = Float64[]

        for m in eachmatch(r"\"degree\":\s*(\d+)", json_text)
            push!(degrees, parse(Int, m.captures[1]))
        end

        for m in eachmatch(r"\"L2_norm\":\s*([0-9.e+-]+)", json_text)
            push!(l2_norms, parse(Float64, m.captures[1]))
        end

        for m in eachmatch(r"\"critical_points\":\s*(\d+)", json_text)
            push!(critical_points, parse(Int, m.captures[1]))
        end

        # Extract condition numbers from results_summary
        for m in eachmatch(r"\"condition_number\":\s*([0-9.e+-]+)", json_text)
            push!(condition_numbers, parse(Float64, m.captures[1]))
        end

        if isempty(degrees) || length(degrees) != length(l2_norms) || length(degrees) != length(critical_points)
            println("  $(YELLOW)⚠ Incomplete or inconsistent results data$(RESET)")
            return
        end

        # Display enhanced table header
        println("  " * "="^100)
        if !isempty(condition_numbers) && length(condition_numbers) == length(degrees)
            @printf("  %-8s | %-15s | %-15s | %-12s | %-15s\n",
                    "Degree", "L2 Norm", "Improvement", "Critical Pts", "Cond Number")
        else
            @printf("  %-8s | %-15s | %-15s | %-12s\n",
                    "Degree", "L2 Norm", "Improvement", "Critical Pts")
        end
        println("  " * "="^100)

        # Display each degree with improvement percentage and stability metrics
        for i in 1:length(degrees)
            degree = degrees[i]
            l2 = l2_norms[i]
            n_cp = critical_points[i]

            if i == 1
                # First degree has no improvement to compare
                if !isempty(condition_numbers) && length(condition_numbers) >= i
                    @printf("  %-8d | %-15.6g | %-15s | %-12d | %-15.6g\n",
                            degree, l2, "-", n_cp, condition_numbers[i])
                else
                    @printf("  %-8d | %-15.6g | %-15s | %-12d\n",
                            degree, l2, "-", n_cp)
                end
            else
                # Calculate improvement percentage
                prev_l2 = l2_norms[i-1]
                improvement_pct = (prev_l2 - l2) / prev_l2 * 100

                # Color code based on improvement
                improvement_color = improvement_pct > 0 ? GREEN : RED

                if !isempty(condition_numbers) && length(condition_numbers) >= i
                    @printf("  %-8d | %-15.6g | %s%14.1f%%%s | %-12d | %-15.6g\n",
                            degree, l2, improvement_color, improvement_pct, RESET, n_cp,
                            condition_numbers[i])
                else
                    @printf("  %-8d | %-15.6g | %s%14.1f%%%s | %-12d\n",
                            degree, l2, improvement_color, improvement_pct, RESET, n_cp)
                end
            end
        end
        println("  " * "="^100)

        # Calculate overall improvement
        if length(l2_norms) >= 2
            first_l2 = l2_norms[1]
            last_l2 = l2_norms[end]
            overall_improvement_factor = first_l2 / last_l2
            overall_reduction_pct = (first_l2 - last_l2) / first_l2 * 100

            println()
            println("  $(BOLD)Summary:$(RESET)")
            @printf("    Overall L2 improvement: %.2f× (%.1f%% reduction)\n",
                    overall_improvement_factor, overall_reduction_pct)
            @printf("    Final L2 norm: %.6g\n", last_l2)

            # Display numerical stability summary if available
            if haskey(numerical_stability, "mean_condition_number")
                @printf("    Mean condition number: %.6g\n", numerical_stability["mean_condition_number"])
            end
            if haskey(numerical_stability, "max_condition_number")
                @printf("    Max condition number: %.6g\n", numerical_stability["max_condition_number"])
            end
            if haskey(numerical_stability, "median_numerical_rank")
                @printf("    Median numerical rank: %.6g\n", numerical_stability["median_numerical_rank"])
            end
            if haskey(numerical_stability, "mean_numerical_rank")
                @printf("    Mean numerical rank: %.6g\n", numerical_stability["mean_numerical_rank"])
            end
        end

    catch e
        println("  $(RED)Error displaying convergence by degree:$(RESET) $e")
        Base.show_backtrace(stdout, catch_backtrace())
    end
end

"""
    analyze_single_experiment(exp_path::String)

Load and analyze a single experiment, displaying computed statistics and convergence table.
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

        # Compute and display statistics
        println("$(BOLD)Computing statistics...$(RESET)")
        stats = compute_statistics(result)

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

        # Display Metadata
        println("\n$(BOLD)$(GREEN)═══ Experiment Metadata ═══$(RESET)\n")
        display_experiment_metadata(exp_path)

        # Quality Diagnostics
        println("\n$(BOLD)$(GREEN)═══ Quality Diagnostics ═══$(RESET)\n")
        display_quality_diagnostics(exp_path)

        # Parameter Recovery (if p_true exists)
        if has_ground_truth(exp_path)
            println("\n$(BOLD)$(GREEN)═══ Parameter Recovery ═══$(RESET)\n")
            display_parameter_recovery(exp_path)
        end

        # Convergence by degree table with numerical stability
        println("\n$(BOLD)$(GREEN)═══ Convergence by Degree ═══$(RESET)\n")
        display_convergence_by_degree(exp_path)

    catch e
        println("$(RED)Error analyzing experiment:$(RESET)")
        println(e)
        Base.show_backtrace(stdout, catch_backtrace())
    end
end

"""
    main()

Main interactive loop - simplified workflow.
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

    # Step 1: Show objective directories
    println("\n$(BOLD)Scanning for objective function directories...$(RESET)")
    objective_dirs = get_objective_directories(experiment_root)

    if isempty(objective_dirs)
        println("\n$(RED)No objective directories found in $experiment_root$(RESET)")
        exit(1)
    end

    display_objective_directories(objective_dirs)

    # Step 2: Select ONE objective directory
    dir_choice = get_user_choice("Select objective function directory", length(objective_dirs))
    selected_dir = objective_dirs[dir_choice]

    println("\n$(BOLD)Selected:$(RESET) $(BLUE)$(basename(selected_dir))$(RESET)")

    # Step 3: Find experiments in selected directory
    println("\n$(BOLD)Scanning for experiments in $(basename(selected_dir))...$(RESET)")
    experiments = find_all_experiments_recursive(selected_dir)

    if isempty(experiments)
        println("\n$(RED)No experiments found in $selected_dir$(RESET)")
        println("$(YELLOW)Make sure experiment directories contain results_summary.json$(RESET)")
        exit(1)
    end

    # Step 4: Display flat list
    display_experiments_list(experiments)

    # Step 5: Select ONE experiment
    exp_choice = get_user_choice("Select experiment to analyze", length(experiments))
    selected_exp = experiments[exp_choice]

    # Step 6: Analyze and show convergence table
    analyze_single_experiment(selected_exp)

    println("\n$(BOLD)$(GREEN)═══ Analysis Complete ═══$(RESET)\n")
end

# Run main
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
