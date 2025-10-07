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

# Terminal colors for better UX
const RESET = "\033[0m"
const BOLD = "\033[1m"
const GREEN = "\033[32m"
const BLUE = "\033[34m"
const YELLOW = "\033[33m"
const RED = "\033[31m"
const CYAN = "\033[36m"

"""
    discover_campaigns(root_path::String) -> Vector{String}

Recursively discover all campaign directories containing experiment results.
Returns paths to directories containing hpc_results or multiple experiment subdirs.
"""
function discover_campaigns(root_path::String)
    campaigns = String[]

    if !isdir(root_path)
        error("Path does not exist: $root_path")
    end

    for (root, dirs, files) in walkdir(root_path)
        # Check if this directory contains hpc_results
        if "hpc_results" in dirs
            hpc_path = joinpath(root, "hpc_results")
            # Count experiment directories
            exp_count = count(isdir(joinpath(hpc_path, d)) for d in readdir(hpc_path))
            if exp_count > 0
                push!(campaigns, hpc_path)
            end
        end
    end

    return sort(campaigns)
end

"""
    display_campaigns(campaigns::Vector{String})

Display discovered campaigns in a numbered list.
"""
function display_campaigns(campaigns::Vector{String})
    println("\n$(BOLD)$(CYAN)═══ Discovered Campaigns ═══$(RESET)\n")

    for (idx, campaign_path) in enumerate(campaigns)
        # Count experiments
        exp_count = count(isdir(joinpath(campaign_path, d)) for d in readdir(campaign_path))

        println("$(BOLD)$idx.$(RESET) $(GREEN)$campaign_path$(RESET)")
        println("   Experiments: $exp_count\n")
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
    display_experiment_list(campaign_path::String) -> Vector{String}

Display experiments in a campaign and return list of experiment paths.
"""
function display_experiment_list(campaign_path::String)
    exp_dirs = String[]

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

        # Check if results exist
        results_file = joinpath(exp_path, "results_summary.json")
        status = isfile(results_file) ? "$(GREEN)✓$(RESET)" : "$(RED)✗$(RESET)"

        println("$(BOLD)$idx.$(RESET) $status $(BLUE)$exp_name$(RESET)")
        println("   Path: $exp_path")

        # Try to read basic info
        if isfile(results_file)
            try
                result = load_experiment_results(exp_path)
                println("   Tracking: $(join(result.enabled_tracking, ", "))")
            catch e
                println("   $(RED)Error loading: $e$(RESET)")
            end
        end
        println()
    end

    return exp_dirs
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
    main()

Main interactive loop.
"""
function main()
    # Parse command line arguments
    experiment_root = if length(ARGS) >= 2 && ARGS[1] == "--path"
        ARGS[2]
    else
        # Default: look for globtimcore experiments relative to this script
        joinpath(dirname(@__DIR__), "globtimcore", "experiments")
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
    selected_campaign = campaigns[campaign_choice]

    # Display experiments
    experiments = display_experiment_list(selected_campaign)

    if isempty(experiments)
        println("$(RED)No experiments found in campaign$(RESET)")
        exit(1)
    end

    # Analysis mode selection
    println("\n$(BOLD)$(CYAN)═══ Analysis Mode ═══$(RESET)\n")
    println("$(BOLD)1.$(RESET) Analyze single experiment")
    println("$(BOLD)2.$(RESET) Analyze entire campaign")
    println()

    mode_choice = get_user_choice("Select mode", 2)

    if mode_choice == 1
        # Single experiment
        exp_choice = get_user_choice("Select experiment", length(experiments))
        analyze_single_experiment(experiments[exp_choice])
    else
        # Entire campaign
        analyze_campaign_interactive(selected_campaign)
    end

    println("\n$(BOLD)$(GREEN)═══ Analysis Complete ═══$(RESET)\n")
end

# Run main
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
