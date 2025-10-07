#!/usr/bin/env julia
"""
    demo_vega_explorer.jl

Demo script to test VegaLite interactive campaign explorer.

Usage:
    julia --project=. examples/demo_vega_explorer.jl <path_to_campaign_directory>

Example:
    julia --project=. examples/demo_vega_explorer.jl ../globtimcore/hpc_results/minimal_4d_lv_test
"""

using GlobtimPostProcessing

# Include the new VegaPlotting module
include("../src/VegaPlotting.jl")

function main()
    if length(ARGS) < 1
        println("Usage: julia --project=. examples/demo_vega_explorer.jl <campaign_directory>")
        println("\nExample:")
        println("  julia --project=. examples/demo_vega_explorer.jl ../globtimcore/hpc_results/minimal_4d_lv_test")
        exit(1)
    end

    campaign_path = ARGS[1]

    println("="^60)
    println("VegaLite Campaign Explorer Demo")
    println("="^60)
    println("\nLoading campaign from: $campaign_path")

    # Load campaign results
    campaign = load_campaign_results(campaign_path)
    println("✓ Loaded $(length(campaign.experiments)) experiments")

    # Compute statistics for all experiments
    println("\nComputing statistics...")
    campaign_stats = Dict()
    for exp_result in campaign.experiments
        stats = compute_statistics(exp_result)
        campaign_stats[exp_result.experiment_id] = stats
    end
    println("✓ Statistics computed for all experiments")

    # Create interactive visualization
    println("\nCreating interactive VegaLite explorer...")
    viz = create_interactive_campaign_explorer(campaign, campaign_stats)

    println("✓ Visualization created!")
    println("\n" * "="^60)
    println("INSTRUCTIONS:")
    println("="^60)
    println("1. Click on experiments in the TOP BAR CHART to select/deselect them")
    println("2. Selected experiments are highlighted in color")
    println("3. The lower plots show ONLY selected experiments")
    println("4. Hover over any point to see detailed metadata")
    println("5. The visualization will open in your browser")
    println("="^60)

    # Display the plot (opens in browser)
    display(viz)

    println("\n✓ Visualization displayed in browser!")
    println("Press Ctrl+C to exit when done exploring...")

    # Keep script running so browser stays open
    try
        while true
            sleep(1)
        end
    catch InterruptException
        println("\n\nExiting...")
    end
end

main()
