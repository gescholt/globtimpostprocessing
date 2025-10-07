#!/usr/bin/env julia
"""
    demo_tidier_vega_suite.jl

Comprehensive demonstration of VegaLite + Tidier.jl visualization suite.

This script showcases all the advanced visualizations available in
GlobtimPostProcessing, demonstrating:
- Tidier.jl data transformations
- VegaLite interactive dashboards
- Multi-view linked selections
- Statistical analysis visualizations

Usage:
    julia --project=. examples/demo_tidier_vega_suite.jl <campaign_directory>

Example:
    julia --project=. examples/demo_tidier_vega_suite.jl ../globtimcore/hpc_results/minimal_4d_lv_test
"""

using GlobtimPostProcessing

function print_banner(text::String)
    println("\n" * "="^80)
    println("  " * text)
    println("="^80)
end

function main()
    if length(ARGS) < 1
        println("Usage: julia --project=. examples/demo_tidier_vega_suite.jl <campaign_directory>")
        println("\nExample:")
        println("  julia --project=. examples/demo_tidier_vega_suite.jl ../globtimcore/hpc_results/minimal_4d_lv_test")
        exit(1)
    end

    campaign_path = ARGS[1]

    print_banner("VegaLite + Tidier.jl Visualization Suite")
    println("\nCampaign: $campaign_path")

    # Load campaign results
    println("\n📦 Loading campaign results...")
    campaign = load_campaign_results(campaign_path)
    println("✓ Loaded $(length(campaign.experiments)) experiments")

    # Compute statistics for all experiments
    println("\n📊 Computing statistics...")
    campaign_stats = Dict()
    for exp_result in campaign.experiments
        stats = compute_statistics(exp_result)
        campaign_stats[exp_result.experiment_id] = stats
    end
    println("✓ Statistics computed for all experiments")

    # Get baseline experiment ID (first experiment)
    baseline_id = campaign.experiments[1].experiment_id
    println("\n📌 Using baseline: $baseline_id")

    # Demonstrate each visualization
    println("\n" * "="^80)
    println("AVAILABLE VISUALIZATIONS")
    println("="^80)
    println("\n1. Interactive Campaign Explorer (original)")
    println("2. Convergence Dashboard")
    println("3. Parameter Sensitivity Plot")
    println("4. Multi-Metric Comparison")
    println("5. Efficiency Analysis")
    println("6. Outlier Detection")
    println("7. Baseline Comparison")

    println("\n" * "="^80)
    println("Select visualization to display (1-7, or 'all' for all, 'q' to quit):")
    println("="^80)

    while true
        print("\nChoice: ")
        choice = readline()

        if choice == "q" || choice == "quit"
            println("Exiting...")
            break
        end

        try
            if choice == "all"
                display_all_visualizations(campaign, campaign_stats, baseline_id)
            elseif choice == "1"
                print_banner("1. Interactive Campaign Explorer")
                viz = create_interactive_campaign_explorer(campaign, campaign_stats)
                display(viz)
                println("✓ Visualization displayed!")
            elseif choice == "2"
                print_banner("2. Convergence Dashboard")
                viz = create_convergence_dashboard(campaign, campaign_stats)
                display(viz)
                println("✓ Visualization displayed!")
            elseif choice == "3"
                print_banner("3. Parameter Sensitivity Plot")
                viz = create_parameter_sensitivity_plot(campaign, campaign_stats)
                display(viz)
                println("✓ Visualization displayed!")
            elseif choice == "4"
                print_banner("4. Multi-Metric Comparison")
                viz = create_multi_metric_comparison(campaign, campaign_stats)
                display(viz)
                println("✓ Visualization displayed!")
            elseif choice == "5"
                print_banner("5. Efficiency Analysis")
                viz = create_efficiency_analysis(campaign, campaign_stats)
                display(viz)
                println("✓ Visualization displayed!")
            elseif choice == "6"
                print_banner("6. Outlier Detection")
                viz = create_outlier_detection_plot(campaign, campaign_stats, metric=:l2_error)
                display(viz)
                println("✓ Visualization displayed!")
            elseif choice == "7"
                print_banner("7. Baseline Comparison")
                viz = create_baseline_comparison(campaign, campaign_stats, baseline_id)
                display(viz)
                println("✓ Visualization displayed!")
            else
                println("⚠️  Invalid choice. Please select 1-7, 'all', or 'q'")
            end

            println("\nEnter another choice (1-7, 'all', or 'q' to quit):")
        catch e
            if isa(e, InterruptException)
                println("\n\nExiting...")
                break
            elseif isa(e, ErrorException)
                println("⚠️  Error: $(e.msg)")
                println("This visualization may require specific data not present in this campaign.")
            else
                println("⚠️  Unexpected error: $e")
            end
        end
    end
end

function display_all_visualizations(campaign, campaign_stats, baseline_id)
    print_banner("Displaying All Visualizations")

    visualizations = [
        ("Interactive Campaign Explorer", () -> create_interactive_campaign_explorer(campaign, campaign_stats)),
        ("Convergence Dashboard", () -> create_convergence_dashboard(campaign, campaign_stats)),
        ("Parameter Sensitivity", () -> create_parameter_sensitivity_plot(campaign, campaign_stats)),
        ("Multi-Metric Comparison", () -> create_multi_metric_comparison(campaign, campaign_stats)),
        ("Efficiency Analysis", () -> create_efficiency_analysis(campaign, campaign_stats)),
        ("Outlier Detection (L2 Error)", () -> create_outlier_detection_plot(campaign, campaign_stats, metric=:l2_error)),
        ("Baseline Comparison", () -> create_baseline_comparison(campaign, campaign_stats, baseline_id))
    ]

    for (name, viz_func) in visualizations
        try
            println("\n📊 Creating: $name...")
            viz = viz_func()
            display(viz)
            println("✓ $name displayed!")
            sleep(0.5)  # Brief pause between displays
        catch e
            println("⚠️  Skipping $name: $(e.msg)")
        end
    end

    println("\n✓ All visualizations displayed!")
end

# Run the demo
try
    main()
catch e
    if !isa(e, InterruptException)
        rethrow(e)
    end
end
