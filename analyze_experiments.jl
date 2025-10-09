#!/usr/bin/env julia

"""
Interactive Experiment Analysis Entry Point

This script provides an interactive interface for discovering, selecting,
and analyzing GlobTim experiments and campaigns.

Usage:
    julia analyze_experiments.jl [--path <experiment_root>]

If no path is provided, searches for experiments in ../globtimcore/experiments
"""

using Pkg
Pkg.activate(@__DIR__)

using GlobtimPostProcessing
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

"""
    is_experiment_directory(path::String) -> Bool

Check if a directory is a single experiment (contains CSV files directly).
"""
function is_experiment_directory(path::String)
    if !isdir(path)
        return false
    end

    # Check for experiment indicators: CSV files or results_summary.json
    files = readdir(path)
    has_csv = any(f -> endswith(f, ".csv") && startswith(f, "critical_points_deg_"), files)
    has_results = "results_summary.json" in files || "results_summary.jld2" in files

    return has_csv || has_results
end

"""
    is_campaign_directory(path::String) -> Bool

Check if a directory is a campaign (contains multiple experiment subdirectories).
A true campaign should have at least 2 experiments with related parameters.
"""
function is_campaign_directory(path::String)
    if !isdir(path)
        return false
    end

    # Get subdirectories that look like experiments
    subdirs = filter(d -> isdir(joinpath(path, d)), readdir(path))
    exp_dirs = filter(d -> is_experiment_directory(joinpath(path, d)), subdirs)

    # Need at least 2 experiments to be a campaign
    # (Single experiment should be analyzed as such, not as a 1-experiment "campaign")
    if length(exp_dirs) < 2
        return false
    end

    # Additional heuristic: check if experiments share common naming pattern
    # indicating they're part of a designed study (e.g., exp1, exp2, exp3 or GN=X variations)
    # For now, just require >= 2 experiments
    return true
end

"""
    discover_campaigns(root_path::String) -> Vector{Tuple{String, Float64}}

Recursively discover all campaign directories containing experiment results.
Returns tuples of (path, modification_time) sorted by modification time (newest first).

A campaign must:
1. Have "hpc_results" as a subdirectory (not be hpc_results itself)
2. Contain at least 2 experiment subdirectories
3. Not be the top-level hpc_results collection directory

Single experiments and the top-level hpc_results collection are excluded.
"""
function discover_campaigns(root_path::String)
    campaigns = Tuple{String, Float64}[]

    if !isdir(root_path)
        error("Path does not exist: $root_path")
    end

    for (root, dirs, _) in walkdir(root_path)
        # Check if this directory contains hpc_results subdirectory
        if "hpc_results" in dirs
            hpc_path = joinpath(root, "hpc_results")

            # Skip flat collection directories (hpc_results at top level of globtimcore, Examples, etc.)
            # A true campaign should have hpc_results nested within a study/config directory
            root_basename = basename(root)

            # Heuristic: True campaigns are typically in directories named like:
            # - configs_YYYYMMDD_HHMMSS (timestamp-based config directories)
            # - *_study, *_campaign, *_experiment directories
            # - batch_* directories
            # Skip if hpc_results is directly under globtimcore, Examples, archives, etc.
            is_likely_collection = root_basename in ["globtimcore", "Examples", "hpc_results"] ||
                                  contains(root, "/archives/") ||
                                  (contains(root, "/Examples/") && !startswith(root_basename, "configs_"))

            if is_likely_collection
                continue
            end

            # Check if this is a true campaign (multiple related experiments)
            if is_campaign_directory(hpc_path)
                # Get modification time of the hpc_results directory
                mtime = stat(hpc_path).mtime
                push!(campaigns, (hpc_path, mtime))
            end
        end
    end

    # Sort by modification time, newest first
    sort!(campaigns, by=x->x[2], rev=true)

    return campaigns
end

"""
    display_campaigns(campaigns::Vector{Tuple{String, Float64}})

Display discovered campaigns in a numbered list, sorted by modification time (newest first).
"""
function display_campaigns(campaigns::Vector{Tuple{String, Float64}})
    println("\n$(BOLD)$(CYAN)═══ Discovered Campaigns (sorted by newest first) ═══$(RESET)\n")

    for (idx, (campaign_path, mtime)) in enumerate(campaigns)
        # Count experiments
        exp_count = count(isdir(joinpath(campaign_path, d)) for d in readdir(campaign_path))

        # Format timestamp
        timestamp = Dates.unix2datetime(mtime)
        time_str = Dates.format(timestamp, "yyyy-mm-dd HH:MM:SS")

        # Add "LATEST" marker for the first one
        latest_marker = idx == 1 ? " $(BOLD)$(GREEN)[LATEST]$(RESET)" : ""

        println("$(BOLD)$idx.$(RESET) $(GREEN)$campaign_path$(RESET)$latest_marker")
        println("   Experiments: $exp_count")
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
    load_config(exp_path::String) -> Union{Dict, Nothing}

Load experiment configuration from JSON file.
"""
function load_config(exp_path::String)
    config_file = joinpath(exp_path, "experiment_config.json")
    if isfile(config_file)
        return JSON3.read(read(config_file, String))
    end
    return nothing
end

"""
    load_all_critical_points(exp_path::String) -> Dict{Int, DataFrame}

Load all critical points CSV files for an experiment, indexed by degree.
"""
function load_all_critical_points(exp_path::String)
    csv_files = filter(f -> startswith(basename(f), "critical_points_deg_"), readdir(exp_path, join=true))

    results = Dict{Int, DataFrame}()
    for csv_file in csv_files
        # Extract degree from filename
        m = match(r"deg_(\d+)\.csv", basename(csv_file))
        if m !== nothing
            degree = parse(Int, m[1])
            df = CSV.read(csv_file, DataFrame)
            results[degree] = df
        end
    end

    return results
end

"""
    param_distance(cp_row, p_true::Vector) -> Float64

Compute L2 distance between critical point parameters and true parameters.
"""
function param_distance(cp_row, p_true::Vector)
    p_found = [cp_row.x1, cp_row.x2, cp_row.x3, cp_row.x4]
    return norm(p_found .- p_true)
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
        config = load_config(exp_path)
        if config === nothing
            @warn "No config found for $exp_name"
            continue
        end

        # Use p_true if available, otherwise use p_center
        p_true = haskey(config, :p_true) ? collect(config.p_true) : collect(config.p_center)
        # Use domain_range if available, otherwise use sample_range
        sample_range = haskey(config, :domain_range) ? config.domain_range : config.sample_range

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
    end

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
        for (_, df) in exp.cp_by_degree
            if nrow(df) > 0
                distances = [param_distance(row, exp.p_true) for row in eachrow(df)]
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

        for deg in degrees
            df = exp.cp_by_degree[deg]
            n_cp = nrow(df)

            if n_cp > 0
                # Compute distances to true parameter
                distances = [param_distance(row, exp.p_true) for row in eachrow(df)]
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
                    distances = [param_distance(row, exp.p_true) for row in eachrow(df)]
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
    main()

Main interactive loop.
"""
function main()
    # Parse command line arguments
    experiment_root = if length(ARGS) >= 2 && ARGS[1] == "--path"
        ARGS[2]
    else
        # Default: look for globtimcore root (searches for hpc_results within)
        joinpath(dirname(@__DIR__), "globtimcore")
    end

    println("$(BOLD)$(CYAN)╔════════════════════════════════════════════════╗$(RESET)")
    println("$(BOLD)$(CYAN)║  GlobTim Post-Processing: Interactive Analysis ║$(RESET)")
    println("$(BOLD)$(CYAN)╚════════════════════════════════════════════════╝$(RESET)")
    println()
    println("$(BOLD)Searching for experiments in:$(RESET)")
    println("  $(BLUE)$experiment_root$(RESET)")

    # Discover campaigns
    campaigns = discover_campaigns(experiment_root)

    if isempty(campaigns)
        println("\n$(RED)No campaigns found in the specified directory.$(RESET)")
        println("Make sure the path contains experiment results with hpc_results directories.")
        exit(1)
    end

    # Display campaigns
    display_campaigns(campaigns)

    # Select campaign
    campaign_choice = get_user_choice("Select campaign", length(campaigns))
    selected_campaign = campaigns[campaign_choice][1]  # Extract path from tuple

    # Display experiments
    experiments, valid_flags = display_experiment_list(selected_campaign)

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

    # Analysis mode selection
    println("\n$(BOLD)$(CYAN)═══ Analysis Mode ═══$(RESET)\n")
    println("$(BOLD)1.$(RESET) Analyze single experiment (requires valid results)")
    println("$(BOLD)2.$(RESET) Analyze entire campaign (aggregated statistics, uses all valid experiments)")
    println("$(BOLD)3.$(RESET) Detailed parameter recovery table (uses all experiments with CSV data)")
    println("$(BOLD)4.$(RESET) Interactive trajectory analysis (requires valid results)")
    println()

    mode_choice = get_user_choice("Select mode", 4)

    if mode_choice == 1
        # Single experiment - require valid results
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
    elseif mode_choice == 2
        # Entire campaign - works with partial results
        analyze_campaign_interactive(selected_campaign)
    elseif mode_choice == 3
        # Detailed parameter recovery table - works with CSV data
        generate_detailed_table(selected_campaign)
    else
        # Interactive trajectory analysis (mode 4) - require valid results
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

    println("\n$(BOLD)$(GREEN)═══ Analysis Complete ═══$(RESET)\n")
end

# Run main
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
