#!/usr/bin/env julia
"""
Interactive Experiment Analysis

Label-aware interactive plotting for GlobTim experiments.
Automatically discovers available tracking labels and creates appropriate visualizations.

Usage:
    julia interactive_analyze.jl [campaign_directory]

If no directory is provided, looks for experiments in ../collected_experiments_*
"""

using Pkg
Pkg.activate(@__DIR__)

using GlobtimPostProcessing
using Dates

"""
Discover campaign directories in the parent directory.
"""
function discover_campaigns()
    parent_dir = dirname(@__DIR__)
    campaigns = String[]

    for entry in readdir(parent_dir, join=true)
        if isdir(entry) && contains(basename(entry), "collected_experiments")
            push!(campaigns, entry)
        end
    end

    # Also check for experiment directories in globtimcore
    globtimcore_path = joinpath(parent_dir, "globtimcore", "hpc_results")
    if isdir(globtimcore_path)
        push!(campaigns, globtimcore_path)
    end

    # Sort by modification time (newest first)
    sort!(campaigns, by=d -> stat(d).mtime, rev=true)

    return campaigns
end

"""
Display campaign selection menu.
"""
function select_campaign(campaigns::Vector{String})
    println("\n" * "="^80)
    println("📂 AVAILABLE CAMPAIGN DIRECTORIES ($(length(campaigns)) found):")
    println("="^80)

    for (i, campaign) in enumerate(campaigns)
        name = basename(campaign)
        mtime = Dates.unix2datetime(stat(campaign).mtime)

        # Count experiments
        num_exps = 0
        for entry in readdir(campaign)
            exp_path = joinpath(campaign, entry)
            if isdir(exp_path) && isfile(joinpath(exp_path, "results_summary.json"))
                num_exps += 1
            end
        end

        println("[$i] $name")
        println("    Modified: $mtime | Experiments: $num_exps")
    end

    println("\n" * "="^80)
    print("Select campaign [1-$(length(campaigns))] or [q]uit: ")

    choice = strip(readline())

    if lowercase(choice) == "q"
        println("Goodbye!")
        exit(0)
    end

    idx = parse(Int, choice)

    if idx < 1 || idx > length(campaigns)
        error("Invalid selection: $idx")
    end

    return campaigns[idx]
end

"""
Display experiment analysis menu.
"""
function analyze_campaign_interactive(campaign_path::String)
    println("\n" * "="^80)
    println("Loading campaign: $(basename(campaign_path))")
    println("="^80)

    # Load campaign
    campaign = load_campaign_results(campaign_path)

    println("\nLoaded $(length(campaign.experiments)) experiments")

    # Display experiments with their tracking labels
    println("\n" * "="^80)
    println("📊 EXPERIMENTS:")
    println("="^80)

    for (i, exp) in enumerate(campaign.experiments)
        println("[$i] $(exp.experiment_id)")
        println("    Tracking labels: $(join(exp.enabled_tracking, ", "))")

        # Show key metrics
        degrees = get(exp.metadata, "degrees_processed", nothing)
        total_time = get(exp.metadata, "total_time", nothing)
        total_cp = get(exp.metadata, "total_critical_points", nothing)

        if degrees !== nothing
            println("    Degrees: $degrees | Time: $(round(total_time, digits=2))s | CP: $total_cp")
        end
    end

    # Menu
    println("\n" * "="^80)
    println("OPTIONS:")
    println("[1-$(length(campaign.experiments))] - Analyze single experiment")
    println("[c] - Compare all experiments in campaign")
    println("[b] - Back to campaign selection")
    println("[q] - Quit")
    println("="^80)
    print("Selection: ")

    choice = strip(readline())

    if lowercase(choice) == "q"
        exit(0)
    elseif lowercase(choice) == "b"
        return :back
    elseif lowercase(choice) == "c"
        analyze_full_campaign(campaign)
        return :continue
    else
        idx = parse(Int, choice)

        if idx < 1 || idx > length(campaign.experiments)
            println("Invalid selection")
            return :continue
        end

        analyze_single_experiment(campaign.experiments[idx])
        return :continue
    end
end

"""
Analyze a single experiment with interactive plotting.
"""
function analyze_single_experiment(result::ExperimentResult)
    println("\n" * "="^80)
    println("EXPERIMENT: $(result.experiment_id)")
    println("="^80)

    # Display metadata
    println("\nMetadata:")
    system_info = get(result.metadata, "system_info", Dict())
    for (key, value) in system_info
        if key != "true_parameters"
            println("  $key: $value")
        end
    end

    true_params = get(system_info, "true_parameters", nothing)
    if true_params !== nothing
        println("\nTrue Parameters: $true_params")
    end

    # Compute statistics
    stats = compute_statistics(result)

    println("\nEnabled tracking labels:")
    for label in result.enabled_tracking
        println("  ✓ $label")
    end

    # Display summary statistics
    if haskey(stats, "approximation_quality")
        qual = stats["approximation_quality"]
        println("\nApproximation Quality:")
        println("  Mean L2 error: $(qual["mean_error"])")
        println("  Min L2 error: $(qual["min_error"]) (degree $(qual["best_degree"]))")
    end

    if haskey(stats, "parameter_recovery")
        rec = stats["parameter_recovery"]
        println("\nParameter Recovery:")
        println("  Mean recovery error: $(rec["mean_error"])")
        println("  Min recovery error: $(rec["min_error"]) (degree $(rec["best_degree"]))")
    end

    if haskey(stats, "critical_points")
        cp = stats["critical_points"]
        println("\nCritical Points:")
        println("  Total refined: $(cp["total_refined"])")
    end

    # Plotting options
    while true
        println("\n" * "="^80)
        println("PLOTTING OPTIONS:")
        println("[1] Interactive plots - navigate by category")
        println("[2] Interactive plot - all in one window")
        println("[3] Save static plot (PNG)")
        println("[b] Back")
        println("="^80)
        print("Selection: ")

        plot_choice = strip(readline())

        if lowercase(plot_choice) == "b"
            return
        elseif plot_choice == "1"
            navigate_experiment_plots(result, stats)
        elseif plot_choice == "2"
            fig = create_experiment_plots(result, stats, backend=Interactive)
            display(fig)
            println("\nPress Enter to continue...")
            readline()
        elseif plot_choice == "3"
            output_file = joinpath(result.source_path, "analysis_plot.png")
            println("\nSaving to: $output_file")
            fig = create_experiment_plots(result, stats, backend=Static)
            save_plot(fig, output_file)
            println("\nPress Enter to continue...")
            readline()
        end
    end
end

"""
Navigate through experiment plots by category.
"""
function navigate_experiment_plots(result::ExperimentResult, stats::Dict)
    # Build list of available plot categories
    available_plots = []

    if haskey(stats, "approximation_quality")
        push!(available_plots, ("approximation_quality", "L2 Approximation Error"))
    end

    if haskey(stats, "parameter_recovery")
        push!(available_plots, ("parameter_recovery", "Parameter Recovery Error"))
    end

    if haskey(stats, "numerical_stability")
        push!(available_plots, ("numerical_stability", "Condition Number"))
    end

    if haskey(stats, "critical_points")
        push!(available_plots, ("critical_points", "Critical Points"))
    end

    if haskey(stats, "timing")
        push!(available_plots, ("timing", "Computation Time"))
    end

    # Add new advanced plot types
    if haskey(stats, "approximation_quality")
        push!(available_plots, ("convergence_trajectory", "Convergence Rate Analysis"))
        push!(available_plots, ("residual_distribution", "Error Distribution"))
    end

    if isempty(available_plots)
        println("No plots available for this experiment")
        return
    end

    current_idx = 1

    while true
        plot_type, plot_title = available_plots[current_idx]

        println("\n" * "="^80)
        println("VIEWING: $plot_title ($(current_idx)/$(length(available_plots)))")
        println("="^80)

        # Create single plot window
        fig = create_single_plot(result, stats, plot_type, plot_title, backend=Interactive)
        display(fig)

        println("\n" * "="^80)
        println("NAVIGATION:")
        println("[n/j] Next plot  |  [p/k] Previous plot  |  [s] Save current plot")
        println("[a] Save all plots  |  [1-$(length(available_plots))] Jump to plot  |  [b/q] Back/Quit")
        println("="^80)

        for (idx, (_, title)) in enumerate(available_plots)
            marker = idx == current_idx ? "→" : " "
            println("$marker [$idx] $title")
        end

        print("\nSelection: ")
        choice = strip(readline())

        if lowercase(choice) == "b" || lowercase(choice) == "q"
            break
        elseif lowercase(choice) == "n" || lowercase(choice) == "j"
            current_idx = mod1(current_idx + 1, length(available_plots))
        elseif lowercase(choice) == "p" || lowercase(choice) == "k"
            current_idx = mod1(current_idx - 1, length(available_plots))
        elseif lowercase(choice) == "s"
            # Save current plot
            plot_type, plot_title = available_plots[current_idx]
            output_file = joinpath(result.source_path, "plot_$(plot_type).png")
            println("\n💾 Saving to: $output_file")
            fig_to_save = create_single_plot(result, stats, plot_type, plot_title, backend=Static)
            save_plot(fig_to_save, output_file)
            println("✓ Saved!")
            println("\nPress Enter to continue...")
            readline()
        elseif lowercase(choice) == "a"
            # Save all plots
            println("\n💾 Saving all plots...")
            for (plot_type, plot_title) in available_plots
                output_file = joinpath(result.source_path, "plot_$(plot_type).png")
                println("  Saving $plot_title...")
                fig_to_save = create_single_plot(result, stats, plot_type, plot_title, backend=Static)
                save_plot(fig_to_save, output_file)
            end
            println("✓ All plots saved to: $(result.source_path)")
            println("\nPress Enter to continue...")
            readline()
        elseif tryparse(Int, choice) !== nothing
            idx = parse(Int, choice)
            if 1 <= idx <= length(available_plots)
                current_idx = idx
            else
                println("Invalid plot number")
            end
        end
    end
end

"""
Analyze full campaign with comparison plots.
"""
function analyze_full_campaign(campaign::CampaignResults)
    println("\n" * "="^80)
    println("CAMPAIGN ANALYSIS: $(campaign.campaign_id)")
    println("="^80)

    # Compute statistics for all experiments
    campaign_stats = Dict{String, Any}()

    for exp in campaign.experiments
        stats = compute_statistics(exp)
        campaign_stats[exp.experiment_id] = stats
    end

    # Display summary
    println("\nCampaign Summary:")
    println("  Total experiments: $(length(campaign.experiments))")

    total_time = sum(get(exp.metadata, "total_time", 0.0) for exp in campaign.experiments)
    println("  Total computation time: $(round(total_time / 3600, digits=2)) hours")

    total_cp = sum(get(exp.metadata, "total_critical_points", 0) for exp in campaign.experiments)
    println("  Total critical points found: $total_cp")

    # Plotting
    println("\n" * "="^80)
    println("PLOTTING OPTIONS:")
    println("[1] Interactive comparison plot")
    println("[2] Save static comparison plot")
    println("[3] Both")
    println("[b] Back")
    println("="^80)
    print("Selection: ")

    plot_choice = strip(readline())

    if lowercase(plot_choice) == "b"
        return
    end

    if plot_choice in ["1", "3"]
        figs = create_campaign_comparison_plot(campaign, campaign_stats, backend=Interactive)
        # Interactive backend returns a vector of figures - display each one
        if figs isa Vector
            for (idx, fig) in enumerate(figs)
                println("\n📊 Displaying comparison plot $(idx)/$(length(figs))...")
                display(fig)
            end
        else
            display(figs)
        end
    end

    if plot_choice in ["2", "3"]
        output_file = joinpath(dirname(campaign.experiments[1].source_path), "campaign_comparison.png")
        println("\nSaving to: $output_file")
        fig = create_campaign_comparison_plot(campaign, campaign_stats, backend=Static)
        save_plot(fig, output_file)
    end

    println("\nPress Enter to continue...")
    readline()
end

"""
Main interactive loop.
"""
function main()
    println("╔" * "="^78 * "╗")
    println("║" * " "^15 * "GlobTim Interactive Analysis" * " "^34 * "║")
    println("║" * " "^20 * "Label-Aware Plotting" * " "^37 * "║")
    println("╚" * "="^78 * "╝")

    # Check for command-line argument
    if length(ARGS) > 0
        campaign_path = ARGS[1]

        if !isdir(campaign_path)
            println("❌ Error: Directory not found: $campaign_path")
            exit(1)
        end

        while true
            result = analyze_campaign_interactive(campaign_path)

            if result == :back
                break
            end
        end
    else
        # Interactive selection mode
        while true
            campaigns = discover_campaigns()

            if isempty(campaigns)
                println("❌ No campaign directories found")
                println("   Looking for directories matching 'collected_experiments_*'")
                exit(1)
            end

            campaign_path = select_campaign(campaigns)

            while true
                result = analyze_campaign_interactive(campaign_path)

                if result == :back
                    break
                end
            end
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
