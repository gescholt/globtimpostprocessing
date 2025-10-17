#!/usr/bin/env julia

"""
Simple Experiment Convergence Viewer

Quickly select an experiment and view degree-by-degree convergence.
No complex navigation - just pick an experiment and see the results.

Usage:
    julia show_experiment_convergence.jl
"""

using Pkg
Pkg.activate(@__DIR__)

using GlobtimPostProcessing
using GlobtimPostProcessing: load_experiment_config, load_quality_thresholds, detect_stagnation
using Printf

# Terminal colors
const RESET = "\033[0m"
const BOLD = "\033[1m"
const GREEN = "\033[32m"
const YELLOW = "\033[33m"
const RED = "\033[31m"
const CYAN = "\033[36m"
const BLUE = "\033[34m"

"""
    find_all_experiments(root_path::String) -> Vector{String}

Recursively find all experiment directories with results_summary.json.
"""
function find_all_experiments(root_path::String)
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
    display_convergence_by_degree(exp_path::String)

Display L2-norm convergence table for an experiment.
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
        println("\n" * "="^70)
        @printf("%-8s | %-18s | %-18s | %-12s\n",
                "Degree", "L2 Norm", "Improvement", "Critical Pts")
        println("="^70)

        # Display each degree with improvement percentage
        for i in 1:length(degrees)
            degree = degrees[i]
            l2 = l2_norms[i]
            n_cp = critical_points[i]

            if i == 1
                # First degree has no improvement to compare
                @printf("%-8d | %-18.6g | %-18s | %-12d\n",
                        degree, l2, "-", n_cp)
            else
                # Calculate improvement percentage
                prev_l2 = l2_norms[i-1]
                improvement_pct = (prev_l2 - l2) / prev_l2 * 100

                # Color code based on improvement
                improvement_color = improvement_pct > 0 ? GREEN : RED
                @printf("%-8d | %-18.6g | %s%17.1f%%%s | %-12d\n",
                        degree, l2, improvement_color, improvement_pct, RESET, n_cp)
            end
        end
        println("="^70)

        # Calculate overall improvement
        if length(l2_norms) >= 2
            first_l2 = l2_norms[1]
            last_l2 = l2_norms[end]
            overall_improvement_factor = first_l2 / last_l2
            overall_reduction_pct = (first_l2 - last_l2) / first_l2 * 100

            println()
            println("$(BOLD)Summary:$(RESET)")
            @printf("  Overall: %.2f× improvement (%.1f%% reduction)\n",
                    overall_improvement_factor, overall_reduction_pct)
            @printf("  From degree %d to %d: %.6g → %.6g\n",
                    degrees[1], degrees[end], first_l2, last_l2)

            # Check for stagnation
            l2_by_degree = Dict{Int, Float64}()
            for (i, degree) in enumerate(degrees)
                l2_by_degree[degree] = l2_norms[i]
            end

            thresholds = load_quality_thresholds()
            stagnation = detect_stagnation(l2_by_degree, thresholds)

            if stagnation.is_stagnant
                println("  Status: $(YELLOW)⚠ Stagnation detected at degree $(stagnation.stagnation_start_degree)$(RESET)")
            else
                println("  Status: $(GREEN)✓ Improving$(RESET) (no stagnation detected)")
            end
        end
        println()

    catch e
        println("  $(RED)Error displaying convergence:$(RESET) $e")
        rethrow(e)
    end
end

"""
    get_user_choice(prompt::String, max_value::Int) -> Int

Get validated integer input from user.
"""
function get_user_choice(prompt::String, max_value::Int)
    while true
        print("$(prompt) (1-$max_value, or 'q' to quit): ")
        flush(stdout)
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

function main()
    println("$(BOLD)$(CYAN)╔════════════════════════════════════════════╗$(RESET)")
    println("$(BOLD)$(CYAN)║  Simple Experiment Convergence Viewer     ║$(RESET)")
    println("$(BOLD)$(CYAN)╚════════════════════════════════════════════╝$(RESET)")
    println()

    # Get results root
    results_root = if haskey(ENV, "GLOBTIM_RESULTS_ROOT")
        ENV["GLOBTIM_RESULTS_ROOT"]
    else
        joinpath(homedir(), "GlobalOptim", "globtim_results")
    end

    if !isdir(results_root)
        println("$(RED)Error: Results directory not found: $results_root$(RESET)")
        println("Set GLOBTIM_RESULTS_ROOT environment variable or ensure ~/GlobalOptim/globtim_results exists")
        exit(1)
    end

    println("$(BOLD)Searching for experiments...$(RESET)")
    experiments = find_all_experiments(results_root)

    if isempty(experiments)
        println("$(RED)No experiments found with results_summary.json$(RESET)")
        exit(1)
    end

    println("$(GREEN)Found $(length(experiments)) experiments$(RESET)\n")

    # Display experiments
    println("$(BOLD)$(CYAN)═══ Select Experiment ═══$(RESET)\n")

    for (idx, exp_path) in enumerate(experiments)
        exp_name = basename(exp_path)

        # Check file validity
        results_file = joinpath(exp_path, "results_summary.json")
        file_size = stat(results_file).size
        status = file_size > 0 ? "$(GREEN)✓$(RESET)" : "$(YELLOW)⚠$(RESET)"

        println("$(BOLD)$idx.$(RESET) $status $(BLUE)$exp_name$(RESET)")
    end

    println()

    # Select experiment
    choice = get_user_choice("Select experiment", length(experiments))
    selected_exp = experiments[choice]

    # Display results
    println("\n$(BOLD)$(GREEN)═══ Convergence Analysis ═══$(RESET)")
    println("$(BOLD)Experiment:$(RESET) $(basename(selected_exp))")
    println("$(BOLD)Path:$(RESET) $selected_exp")

    display_convergence_by_degree(selected_exp)

    println("$(BOLD)$(GREEN)═══ Done ═══$(RESET)\n")
end

# Run main
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
