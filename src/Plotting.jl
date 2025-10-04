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
    generate_experiment_labels(campaign::CampaignResults) -> Vector{String}

Generate concise, informative labels for experiments in a campaign.
Automatically detects which parameter varies and creates labels accordingly.

# Strategy
1. Identify which parameters vary across experiments
2. If only one parameter varies, label by that parameter value
3. If multiple parameters vary, create compact multi-parameter labels
4. Handle common parameter types (domain_size_param, parameter_set, etc.)
"""
function generate_experiment_labels(campaign::CampaignResults)
    labels = String[]
    n_exp = length(campaign.experiments)

    if n_exp == 0
        return labels
    end

    # Extract parameter dictionaries from all experiments
    param_dicts = [get(exp.metadata, "params_dict", Dict()) for exp in campaign.experiments]

    # Find parameters that vary across experiments
    all_keys = Set{String}()
    for pd in param_dicts
        union!(all_keys, keys(pd))
    end

    varying_params = String[]
    param_values = Dict{String, Vector{Any}}()

    # Parameters to exclude from automatic labeling (not informative)
    excluded_params = Set(["experiment_id", "timestamp"])

    for key in all_keys
        # Skip excluded parameters
        if key in excluded_params
            continue
        end

        values = [get(pd, key, missing) for pd in param_dicts]
        unique_values = unique(skipmissing(values))

        if length(unique_values) > 1
            push!(varying_params, key)
            param_values[key] = values
        end
    end

    # Generate labels based on varying parameters
    if isempty(varying_params)
        # No varying parameters - use experiment IDs
        for (idx, exp) in enumerate(campaign.experiments)
            exp_id = get(get(exp.metadata, "params_dict", Dict()), "experiment_id", "exp_$idx")
            push!(labels, string(exp_id))
        end
    elseif length(varying_params) == 1
        # Single varying parameter - use clean value labels
        param = varying_params[1]
        label_prefix = get_param_label_prefix(param)

        for value in param_values[param]
            label = format_param_value(param, value, label_prefix)
            push!(labels, label)
        end
    else
        # Multiple varying parameters - create compact multi-param labels
        for i in 1:n_exp
            parts = String[]
            for param in sort(varying_params)
                value = param_values[param][i]
                if value !== missing
                    formatted = format_param_value(param, value, "")
                    push!(parts, formatted)
                end
            end
            push!(labels, join(parts, ", "))
        end
    end

    return labels
end

"""
    get_param_label_prefix(param_name::String) -> String

Get a human-readable prefix for a parameter name.
"""
function get_param_label_prefix(param_name::String)
    prefixes = Dict(
        "domain_size_param" => "domain=",
        "domain_size" => "domain=",
        "parameter_set" => "",  # No prefix for parameter sets
        "GN" => "GN=",
        "max_time" => "t=",
        "experiment_id" => ""
    )

    return get(prefixes, param_name, "$param_name=")
end

"""
    format_param_value(param_name::String, value::Any, prefix::String) -> String

Format a parameter value for display in labels.
"""
function format_param_value(param_name::String, value::Any, prefix::String)
    if value === missing
        return "N/A"
    end

    # Special formatting for specific parameter types
    if param_name == "domain_size_param" || param_name == "domain_size"
        return "$(prefix)±$(value)"
    elseif param_name == "parameter_set"
        # Capitalize first letter for parameter sets
        return uppercasefirst(string(value))
    elseif isa(value, AbstractFloat)
        # Format floats nicely
        return "$(prefix)$(round(value, digits=3))"
    else
        return "$(prefix)$(value)"
    end
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
    data = stats["timing"]
    per_degree = data["per_degree_data"]
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
    create_single_plot(result::ExperimentResult, stats::Dict, plot_type::Symbol, title::String; backend::PlotBackend=Interactive) -> Figure

Create a single plot window for a specific plot type.
"""
function create_single_plot(result::ExperimentResult, stats::Dict, plot_type::Symbol, title::String; backend::PlotBackend=Interactive)
    MakieModule = backend == Interactive ? GLMakie : CairoMakie

    fig = MakieModule.Figure(size=(1000, 700))

    # Add experiment ID as title
    MakieModule.Label(fig[0, :], "$(result.experiment_id): $title",
                     fontsize=20, font=:bold)

    # Create the plot in the main area
    if plot_type == :approximation_quality
        create_approximation_plot!(fig[1, 1], MakieModule, stats, title)
    elseif plot_type == :parameter_recovery
        create_parameter_recovery_plot!(fig[1, 1], MakieModule, stats, title)
    elseif plot_type == :numerical_stability
        create_stability_plot!(fig[1, 1], MakieModule, stats, title)
    elseif plot_type == :critical_points
        create_critical_points_plot!(fig[1, 1], MakieModule, stats, title)
    elseif plot_type == :timing
        create_timing_plot!(fig[1, 1], MakieModule, stats, title)
    elseif plot_type == :convergence_trajectory
        create_convergence_trajectory_plot!(fig[1, 1], MakieModule, stats, title)
    elseif plot_type == :residual_distribution
        create_residual_distribution_plot!(fig[1, 1], MakieModule, stats, title)
    else
        error("Unknown plot type: $plot_type")
    end

    return fig
end

"""
    create_convergence_trajectory_plot!(gridpos, Makie, stats::Dict, title::String)

Plot convergence trajectories showing improvement rates across degrees.
"""
function create_convergence_trajectory_plot!(gridpos, Makie, stats::Dict, title::String)
    # Check if we have approximation quality data
    if !haskey(stats, "approximation_quality")
        ax = Makie.Axis(gridpos, title="$title (No Data)")
        Makie.text!(ax, "No approximation quality data available",
            position=(0.5, 0.5), align=(:center, :center))
        return ax
    end

    data = stats["approximation_quality"]
    degrees = data["degrees"]
    l2_errors = data["l2_errors"]

    valid = .!isnan.(l2_errors)

    if !any(valid) || sum(valid) < 2
        ax = Makie.Axis(gridpos, title="$title (Insufficient Data)")
        Makie.text!(ax, "Need at least 2 valid data points",
            position=(0.5, 0.5), align=(:center, :center))
        return ax
    end

    valid_degrees = degrees[valid]
    valid_errors = l2_errors[valid]

    # Calculate improvement factors
    improvements = Float64[]
    for i in 2:length(valid_errors)
        ratio = valid_errors[i-1] / valid_errors[i]
        push!(improvements, ratio)
    end

    ax = Makie.Axis(gridpos,
        title=title,
        xlabel="Degree Transition",
        ylabel="Improvement Factor",
        yscale=log10
    )

    # Plot improvement factors
    transition_labels = ["$(valid_degrees[i])→$(valid_degrees[i+1])" for i in 1:length(improvements)]

    Makie.barplot!(ax, 1:length(improvements), improvements,
        color=:orange, strokecolor=:black, strokewidth=1)

    ax.xticks = (1:length(improvements), transition_labels)
    ax.xticklabelrotation = π/4

    # Add reference line at 1.0 (no improvement)
    Makie.hlines!(ax, [1.0], color=:red, linestyle=:dash, linewidth=2, label="No improvement")

    Makie.axislegend(ax, position=:lt)

    return ax
end

"""
    create_residual_distribution_plot!(gridpos, Makie, stats::Dict, title::String)

Plot histogram of residuals/errors to show distribution quality.
"""
function create_residual_distribution_plot!(gridpos, Makie, stats::Dict, title::String)
    # For now, we'll create a simplified version using available data
    # In the future, this could show spatial distribution of approximation errors

    if !haskey(stats, "approximation_quality")
        ax = Makie.Axis(gridpos, title="$title (No Data)")
        Makie.text!(ax, "No approximation quality data available",
            position=(0.5, 0.5), align=(:center, :center))
        return ax
    end

    data = stats["approximation_quality"]
    degrees = data["degrees"]
    l2_errors = data["l2_errors"]

    valid = .!isnan.(l2_errors)

    if !any(valid)
        ax = Makie.Axis(gridpos, title="$title (No Valid Data)")
        return ax
    end

    valid_degrees = degrees[valid]
    valid_errors = l2_errors[valid]

    ax = Makie.Axis(gridpos,
        title=title,
        xlabel="Polynomial Degree",
        ylabel="Log10(Error)"
    )

    # Create a scatter plot showing error distribution
    log_errors = log10.(valid_errors)

    Makie.scatter!(ax, valid_degrees, log_errors,
        color=:teal, markersize=20, marker=:circle)

    # Add trend line if we have enough points
    if length(valid_errors) >= 2
        # Fit a line to show convergence trend
        Makie.lines!(ax, valid_degrees, log_errors,
            color=:gray, linestyle=:dash, linewidth=2, label="Trend")
    end

    Makie.axislegend(ax, position=:rt)

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
end

"""
    create_campaign_comparison_plot(campaign::CampaignResults, stats::Vector; backend::PlotBackend=Static) -> Figure or Vector{Figure}

Create comparison plots across multiple experiments in a campaign.
For Interactive backend, returns a vector of separate figures (one per window).
For Static backend, returns a single combined figure.
"""
function create_campaign_comparison_plot(campaign::CampaignResults, campaign_stats::Dict; backend::PlotBackend=Static)
    MakieModule = backend == Interactive ? GLMakie : CairoMakie

    # Generate intelligent labels for experiments
    exp_labels = generate_experiment_labels(campaign)
    colors = Makie.wong_colors()

    if backend == Interactive
        # Create separate windows for interactive mode
        figures = []

        # Window 1: L2 errors and parameter recovery
        fig1 = MakieModule.Figure(size=(1200, 500))
        MakieModule.Label(fig1[0, :], "Campaign: $(campaign.campaign_id) - Approximation Quality",
                         fontsize=18, font=:bold)

        ax1 = MakieModule.Axis(fig1[1, 1],
            title="L2 Approximation Error Comparison",
            xlabel="Polynomial Degree",
            ylabel="L2 Error (log scale)",
            yscale=log10
        )

        for (idx, exp_result) in enumerate(campaign.experiments)
            if haskey(campaign_stats, exp_result.experiment_id)
                exp_stats = campaign_stats[exp_result.experiment_id]

                if haskey(exp_stats, "approximation_quality")
                    data = exp_stats["approximation_quality"]
                    degrees = data["degrees"]
                    errors = data["l2_errors"]
                    valid = .!isnan.(errors)

                    if any(valid)
                        MakieModule.scatterlines!(ax1, degrees[valid], errors[valid],
                            label=exp_labels[idx],
                            color=colors[mod1(idx, length(colors))],
                            markersize=10, linewidth=2)
                    end
                end
            end
        end

        ax2 = MakieModule.Axis(fig1[1, 2],
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
                        MakieModule.scatterlines!(ax2, degrees[valid], errors[valid],
                            label=exp_labels[idx],
                            color=colors[mod1(idx, length(colors))],
                            markersize=10, linewidth=2)
                    end
                end
            end
        end

        MakieModule.Legend(fig1[2, 1:2], ax1, "Experiments", orientation=:horizontal,
                          tellwidth=false, tellheight=true, nbanks=2)
        push!(figures, fig1)

        # Window 2: Critical points
        fig2 = MakieModule.Figure(size=(800, 500))
        MakieModule.Label(fig2[0, :], "Campaign: $(campaign.campaign_id) - Critical Points",
                         fontsize=18, font=:bold)

        ax3 = MakieModule.Axis(fig2[1, 1],
            title="Total Critical Points Found",
            xlabel="Experiment",
            ylabel="Number of Critical Points"
        )

        critical_points = Int[]
        for exp_result in campaign.experiments
            total_cp = get(exp_result.metadata, "total_critical_points", 0)
            push!(critical_points, total_cp)
        end

        MakieModule.barplot!(ax3, 1:length(exp_labels), critical_points,
            color=[colors[mod1(i, length(colors))] for i in 1:length(exp_labels)])
        ax3.xticks = (1:length(exp_labels), exp_labels)
        ax3.xticklabelrotation = π/4

        push!(figures, fig2)

        return figures
    else
        # Static backend: single combined figure
        fig = MakieModule.Figure(size=(1600, 800))

        MakieModule.Label(fig[0, :], "Campaign: $(campaign.campaign_id)",
                         fontsize=20, font=:bold)

        # Plot 1: L2 errors comparison
        ax1 = MakieModule.Axis(fig[1, 1],
            title="L2 Approximation Error Comparison",
            xlabel="Polynomial Degree",
            ylabel="L2 Error (log scale)",
            yscale=log10
        )

        for (idx, exp_result) in enumerate(campaign.experiments)
            if haskey(campaign_stats, exp_result.experiment_id)
                exp_stats = campaign_stats[exp_result.experiment_id]

                if haskey(exp_stats, "approximation_quality")
                    data = exp_stats["approximation_quality"]
                    degrees = data["degrees"]
                    errors = data["l2_errors"]
                    valid = .!isnan.(errors)

                    if any(valid)
                        MakieModule.scatterlines!(ax1, degrees[valid], errors[valid],
                            label=exp_labels[idx],
                            color=colors[mod1(idx, length(colors))],
                            markersize=10, linewidth=2)
                    end
                end
            end
        end

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
                        MakieModule.scatterlines!(ax2, degrees[valid], errors[valid],
                            label=exp_labels[idx],
                            color=colors[mod1(idx, length(colors))],
                            markersize=10, linewidth=2)
                    end
                end
            end
        end

        # Plot 3: Critical points comparison
        ax3 = MakieModule.Axis(fig[1, 3],
            title="Total Critical Points Found",
            xlabel="Experiment",
            ylabel="Number of Critical Points"
        )

        critical_points = Int[]
        for exp_result in campaign.experiments
            total_cp = get(exp_result.metadata, "total_critical_points", 0)
            push!(critical_points, total_cp)
        end

        MakieModule.barplot!(ax3, 1:length(exp_labels), critical_points,
            color=[colors[mod1(i, length(colors))] for i in 1:length(exp_labels)])
        ax3.xticks = (1:length(exp_labels), exp_labels)
        ax3.xticklabelrotation = π/4

        # Single legend at the bottom for all plots
        MakieModule.Legend(fig[2, 1:3], ax1, "Experiments", orientation=:horizontal,
                          tellwidth=false, tellheight=true, nbanks=2)

        return fig
    end
end
