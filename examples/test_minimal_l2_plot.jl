#!/usr/bin/env julia
"""
    test_minimal_l2_plot.jl

Minimal test for L2 error visualization with VegaLite.
TDD approach - start with the simplest thing that works.

Usage:
    julia --project=. examples/test_minimal_l2_plot.jl [campaign_directory]

If no directory is provided, script will search for available campaigns
and let you select interactively.
"""

using GlobtimPostProcessing
using Dates

# Include the minimal plotting module
include("../src/VegaPlotting_minimal.jl")

function find_campaign_directories()
    """Search for campaign directories in standard locations"""
    search_paths = [
        "../globtimcore/experiments",
        "../globtimcore/hpc_results",
        "../globtimcore"
    ]

    campaigns = []

    for search_path in search_paths
        if !isdir(search_path)
            continue
        end

        # Find directories containing hpc_results (manual depth limit)
        function walk_limited(path, current_depth, max_depth)
            if current_depth > max_depth
                return
            end

            if basename(path) == "hpc_results" && isdir(path)
                push!(campaigns, path)
            end

            if isdir(path)
                for entry in readdir(path, join=true)
                    if isdir(entry)
                        walk_limited(entry, current_depth + 1, max_depth)
                    end
                end
            end
        end

        walk_limited(search_path, 0, 4)
    end

    return sort(unique(campaigns))
end

function select_campaign_interactive()
    """Let user select a campaign directory interactively"""
    println("="^60)
    println("Searching for campaign directories...")
    println("="^60)

    campaigns = find_campaign_directories()

    if isempty(campaigns)
        println("\n❌ No campaign directories found!")
        println("\nSearched in:")
        println("  - ../globtimcore/experiments")
        println("  - ../globtimcore/hpc_results")
        println("  - ../globtimcore")
        println("\nPlease provide path manually:")
        print("Campaign path: ")
        return strip(readline())
    end

    # Collect campaign metadata
    campaign_info = []
    for campaign in campaigns
        exp_count = 0
        mtime = nothing

        try
            if isdir(campaign)
                # Count experiments
                exp_count = length(filter(d -> isdir(joinpath(campaign, d)) &&
                                               !startswith(d, "."),
                                        readdir(campaign)))

                # Get most recent modification time from experiments
                mtime = stat(campaign).mtime
                for entry in readdir(campaign, join=true)
                    if isdir(entry)
                        entry_mtime = stat(entry).mtime
                        if mtime === nothing || entry_mtime > mtime
                            mtime = entry_mtime
                        end
                    end
                end
            end
        catch
        end

        push!(campaign_info, (path=campaign, exp_count=exp_count, mtime=mtime))
    end

    # Sort by modification time (most recent first)
    sort!(campaign_info, by=x -> something(x.mtime, 0.0), rev=true)

    println("\nFound $(length(campaign_info)) campaign(s) (sorted by most recent):")
    println()

    for (i, info) in enumerate(campaign_info)
        # Get relative path for nicer display
        rel_path = relpath(info.path, pwd())

        # Format timestamp
        time_str = if info.mtime !== nothing
            dt = Dates.unix2datetime(info.mtime)
            Dates.format(dt, "yyyy-mm-dd HH:MM")
        else
            "unknown"
        end

        println("[$i] $rel_path")
        println("    → $(info.exp_count) experiment(s), last modified: $time_str")
    end

    println()
    println("="^60)
    print("Select campaign (1-$(length(campaign_info)), or 'q' to quit): ")

    while true
        choice = strip(readline())

        if choice == "q" || choice == "quit"
            println("Exiting...")
            exit(0)
        end

        try
            idx = parse(Int, choice)
            if 1 <= idx <= length(campaign_info)
                return campaign_info[idx].path
            else
                print("Invalid choice. Enter 1-$(length(campaign_info)): ")
            end
        catch
            print("Invalid input. Enter a number (1-$(length(campaign_info))): ")
        end
    end
end

function main()
    # Get campaign path from args or interactive selection
    campaign_path = if length(ARGS) >= 1
        ARGS[1]
    else
        select_campaign_interactive()
    end

    if !isdir(campaign_path)
        println("\n❌ Error: Directory does not exist: $campaign_path")
        exit(1)
    end

    println("\n" * "="^60)
    println("Testing Minimal L2 Plot")
    println("="^60)
    println("\nCampaign: $campaign_path")

    # Step 1: Load campaign
    println("\n[1/4] Loading campaign...")
    campaign = load_campaign_results(campaign_path)
    println("✓ Loaded $(length(campaign.experiments)) experiments")

    # Validate campaign has experiments
    if isempty(campaign.experiments)
        println("\n❌ Error: No valid experiments found in campaign!")
        println("\nThis campaign has no successfully loaded experiments.")
        println("All experiment files appear to be corrupted or incomplete.")
        println("\nPlease select a different campaign with valid data.")
        exit(1)
    end

    # Step 2: Compute statistics
    println("\n[2/4] Computing statistics...")
    campaign_stats = Dict()
    for exp_result in campaign.experiments
        stats = compute_statistics(exp_result)
        campaign_stats[exp_result.experiment_id] = stats
    end
    println("✓ Statistics computed")

    # Step 3: Convert to DataFrame
    println("\n[3/4] Creating L2 DataFrame...")
    df = campaign_to_l2_dataframe(campaign, campaign_stats)
    println("✓ DataFrame created with $(nrow(df)) rows")

    if nrow(df) == 0
        println("\n❌ Error: DataFrame is empty after conversion!")
        println("Campaign has experiments but no L2 data could be extracted.")
        exit(1)
    end

    println("  Columns: $(names(df))")
    println("  Experiments: $(length(unique(df.experiment_id)))")
    println("  Degrees: $(sort(unique(df.degree)))")

    # Display sample data
    println("\nSample data (first 5 rows):")
    println(first(df, 5))

    # Step 4: Create plot
    println("\n[4/4] Creating VegaLite plot...")
    viz = plot_l2_convergence(campaign, campaign_stats)
    println("✓ Plot created!")

    println("\n" * "="^60)
    println("SUCCESS! Opening plot in browser...")
    println("="^60)

    # Display the plot
    display(viz)

    println("\n✓ Plot displayed!")
    println("Press Ctrl+C to exit...")

    # Keep running
    try
        while true
            sleep(1)
        end
    catch InterruptException
        println("\nExiting...")
    end
end

try
    main()
catch e
    if !isa(e, InterruptException)
        println("\n❌ Error: $e")
        rethrow(e)
    end
end
