"""
    Plotting.jl

Label-aware adaptive plotting for GlobTim experiment results.
Automatically generates appropriate visualizations based on available tracking labels.
"""

using CairoMakie
using GLMakie

"""
    PlotBackend

Enum for plot backend selection.
"""
@enum PlotBackend begin
    Interactive  # GLMakie for interactive plots
    Static       # CairoMakie for static images
end

"""
    create_experiment_plots(result::ExperimentResult, stats::Dict; backend::PlotBackend=Static) -> Figure

Create adaptive plots based on available tracking labels.
"""
function create_experiment_plots(result::ExperimentResult, stats::Dict; backend::PlotBackend=Static)
    MakieModule = backend == Interactive ? GLMakie : CairoMakie

    # Determine which plots to create based on enabled tracking
    enabled = result.enabled_tracking

    # Count how many plot panels we need
    num_plots = 0
    plot_specs = []

    if "approximation_quality" in enabled
        num_plots += 1
        push!(plot_specs, (:approximation_quality, "L2 Approximation Error"))
    end

    if "parameter_recovery" in enabled
        num_plots += 1
        push!(plot_specs, (:parameter_recovery, "Parameter Recovery Error"))
    end

    if "numerical_stability" in enabled
        num_plots += 1
        push!(plot_specs, (:numerical_stability, "Condition Number"))
    end

    if "critical_point_count" in enabled || "refined_critical_points" in enabled
        num_plots += 1
        push!(plot_specs, (:critical_points, "Critical Points"))
    end

    if "polynomial_timing" in enabled || "solving_timing" in enabled
        num_plots += 1
        push!(plot_specs, (:timing, "Computation Time"))
    end

    # Create figure layout
    nrows = Int(ceil(num_plots / 2))
    ncols = min(num_plots, 2)

    fig = MakieModule.Figure(size=(800 * ncols, 600 * nrows))

    # Add title
    exp_id = result.experiment_id
    MakieModule.Label(fig[0, :], "Experiment: $exp_id",
                     fontsize=20, font=:bold)

    # Create plots
    for (idx, (plot_type, title)) in enumerate(plot_specs)
        row = div(idx - 1, 2) + 1
        col = mod(idx - 1, 2) + 1

        if plot_type == :approximation_quality
            create_approximation_plot!(fig[row, col], MakieModule, stats, title)
        elseif plot_type == :parameter_recovery
            create_parameter_recovery_plot!(fig[row, col], MakieModule, stats, title)
        elseif plot_type == :numerical_stability
            create_stability_plot!(fig[row, col], MakieModule, stats, title)
        elseif plot_type == :critical_points
            create_critical_points_plot!(fig[row, col], MakieModule, stats, title)
        elseif plot_type == :timing
            create_timing_plot!(fig[row, col], MakieModule, stats, title)
        end
    end

    return fig
end

"""
    create_approximation_plot!(gridpos, Makie, stats::Dict, title::String)

Plot L2 approximation error vs degree.
"""
function create_approximation_plot!(gridpos, Makie, stats::Dict, title::String)
    data = stats["approximation_quality"]
    degrees = data["degrees"]
    l2_errors = data["l2_errors"]

    ax = Makie.Axis(gridpos,
        title=title,
        xlabel="Polynomial Degree",
        ylabel="L2 Error (log scale)",
        yscale=log10
    )

    valid = .!isnan.(l2_errors)
    if any(valid)
        Makie.scatterlines!(ax, degrees[valid], l2_errors[valid],
            color=:blue, markersize=15, linewidth=3)
    end

    return ax
end

"""
    create_parameter_recovery_plot!(gridpos, Makie, stats::Dict, title::String)

Plot parameter recovery error vs degree.
"""
function create_parameter_recovery_plot!(gridpos, Makie, stats::Dict, title::String)
    data = stats["parameter_recovery"]
    degrees = data["degrees"]
    errors = data["recovery_errors"]

    ax = Makie.Axis(gridpos,
        title=title,
        xlabel="Polynomial Degree",
        ylabel="Recovery Error (log scale)",
        yscale=log10
    )

    valid = .!isnan.(errors)
    if any(valid)
        Makie.scatterlines!(ax, degrees[valid], errors[valid],
            color=:green, markersize=15, linewidth=3)
    end

    # Add reference line for true parameters if available
    true_params = data["true_parameters"]
    if true_params !== nothing
        Makie.text!(ax, "True params: $(round.(true_params, digits=3))",
            position=(minimum(degrees), maximum(filter(!isnan, errors))),
            align=(:left, :top), fontsize=10)
    end

    return ax
end

"""
    create_stability_plot!(gridpos, Makie, stats::Dict, title::String)

Plot condition numbers vs degree.
"""
function create_stability_plot!(gridpos, Makie, stats::Dict, title::String)
    data = stats["numerical_stability"]
    degrees = data["degrees"]
    cond_numbers = data["condition_numbers"]

    ax = Makie.Axis(gridpos,
        title=title,
        xlabel="Polynomial Degree",
        ylabel="Condition Number"
    )

    valid = .!isnan.(cond_numbers)
    if any(valid)
        Makie.scatterlines!(ax, degrees[valid], cond_numbers[valid],
            color=:red, markersize=15, linewidth=3)
    end

    return ax
end

"""
    create_critical_points_plot!(gridpos, Makie, stats::Dict, title::String)

Plot critical point counts vs degree.
"""
function create_critical_points_plot!(gridpos, Makie, stats::Dict, title::String)
    data = stats["critical_points"]
    degrees = data["degrees"]
    refined = data["refined_critical_points"]

    ax = Makie.Axis(gridpos,
        title=title,
        xlabel="Polynomial Degree",
        ylabel="Number of Critical Points"
    )

    Makie.barplot!(ax, degrees, refined, color=:purple)

    return ax
end

"""
    create_timing_plot!(gridpos, Makie, stats::Dict, title::String)

Plot timing breakdown by degree.
"""
function create_timing_plot!(gridpos, Makie, stats::Dict, title::String)
    per_degree = stats["per_degree_data"]
    degrees = sort(collect(keys(per_degree)))

    poly_times = [get(per_degree[d], "polynomial_construction_time", 0.0) for d in degrees]
    solve_times = [get(per_degree[d], "critical_point_solving_time", 0.0) for d in degrees]
    refine_times = [get(per_degree[d], "refinement_time", 0.0) for d in degrees]

    ax = Makie.Axis(gridpos,
        title=title,
        xlabel="Polynomial Degree",
        ylabel="Time (seconds)",
        yscale=log10
    )

    Makie.scatterlines!(ax, degrees, poly_times,
        label="Polynomial Construction", color=:blue, markersize=10, linewidth=2)
    Makie.scatterlines!(ax, degrees, solve_times,
        label="Solving", color=:red, markersize=10, linewidth=2)
    Makie.scatterlines!(ax, degrees, refine_times,
        label="Refinement", color=:green, markersize=10, linewidth=2)

    Makie.axislegend(ax, position=:lt)

    return ax
end

"""
    save_plot(fig::Figure, output_path::String; format=:png)

Save a Makie figure to file.
"""
function save_plot(fig::Figure, output_path::String; format=:png)
    if format == :png
        CairoMakie.save(output_path, fig)
    elseif format == :pdf
        CairoMakie.save(output_path, fig, pt_per_unit=1)
    elseif format == :svg
        CairoMakie.save(output_path, fig)
    else
        error("Unsupported format: $format. Use :png, :pdf, or :svg")
    end

    println("Saved plot to: $output_path")
end

"""
    create_campaign_comparison_plot(campaign::CampaignResults, stats::Vector; backend::PlotBackend=Static) -> Figure

Create comparison plots across multiple experiments in a campaign.
"""
function create_campaign_comparison_plot(campaign::CampaignResults, campaign_stats::Dict; backend::PlotBackend=Static)
    MakieModule = backend == Interactive ? GLMakie : CairoMakie

    fig = MakieModule.Figure(size=(1600, 1200))

    MakieModule.Label(fig[0, :], "Campaign: $(campaign.campaign_id)",
                     fontsize=20, font=:bold)

    # Extract data from all experiments
    num_experiments = length(campaign.experiments)

    # Plot 1: L2 errors comparison
    ax1 = MakieModule.Axis(fig[1, 1],
        title="L2 Approximation Error Comparison",
        xlabel="Polynomial Degree",
        ylabel="L2 Error (log scale)",
        yscale=log10
    )

    colors = Makie.wong_colors()

    for (idx, exp_result) in enumerate(campaign.experiments)
        if haskey(campaign_stats, exp_result.experiment_id)
            exp_stats = campaign_stats[exp_result.experiment_id]

            if haskey(exp_stats, "approximation_quality")
                data = exp_stats["approximation_quality"]
                degrees = data["degrees"]
                errors = data["l2_errors"]
                valid = .!isnan.(errors)

                if any(valid)
                    exp_name = split(exp_result.experiment_id, "_")[end]
                    MakieModule.scatterlines!(ax1, degrees[valid], errors[valid],
                        label=exp_name,
                        color=colors[mod1(idx, length(colors))],
                        markersize=10, linewidth=2)
                end
            end
        end
    end

    MakieModule.axislegend(ax1, position=:rt)

    # Plot 2: Parameter recovery comparison
    ax2 = MakieModule.Axis(fig[1, 2],
        title="Parameter Recovery Error Comparison",
        xlabel="Polynomial Degree",
        ylabel="Recovery Error (log scale)",
        yscale=log10
    )

    for (idx, exp_result) in enumerate(campaign.experiments)
        if haskey(campaign_stats, exp_result.experiment_id)
            exp_stats = campaign_stats[exp_result.experiment_id]

            if haskey(exp_stats, "parameter_recovery")
                data = exp_stats["parameter_recovery"]
                degrees = data["degrees"]
                errors = data["recovery_errors"]
                valid = .!isnan.(errors)

                if any(valid)
                    exp_name = split(exp_result.experiment_id, "_")[end]
                    MakieModule.scatterlines!(ax2, degrees[valid], errors[valid],
                        label=exp_name,
                        color=colors[mod1(idx, length(colors))],
                        markersize=10, linewidth=2)
                end
            end
        end
    end

    MakieModule.axislegend(ax2, position=:rt)

    # Plot 3: Total computation time comparison
    ax3 = MakieModule.Axis(fig[2, 1],
        title="Total Computation Time",
        xlabel="Experiment",
        ylabel="Time (seconds)",
        yscale=log10
    )

    exp_names = []
    total_times = Float64[]

    for exp_result in campaign.experiments
        exp_name = split(exp_result.experiment_id, "_")[end]
        push!(exp_names, exp_name)

        total_time = get(exp_result.metadata, "total_time", 0.0)
        push!(total_times, total_time)
    end

    MakieModule.barplot!(ax3, 1:length(exp_names), total_times, color=:orange)
    ax3.xticks = (1:length(exp_names), exp_names)
    ax3.xticklabelrotation = π/4

    # Plot 4: Critical points comparison
    ax4 = MakieModule.Axis(fig[2, 2],
        title="Total Critical Points Found",
        xlabel="Experiment",
        ylabel="Number of Critical Points"
    )

    critical_points = Int[]

    for exp_result in campaign.experiments
        total_cp = get(exp_result.metadata, "total_critical_points", 0)
        push!(critical_points, total_cp)
    end

    MakieModule.barplot!(ax4, 1:length(exp_names), critical_points, color=:purple)
    ax4.xticks = (1:length(exp_names), exp_names)
    ax4.xticklabelrotation = π/4

    return fig
end
