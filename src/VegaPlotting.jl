"""
    VegaPlotting.jl

Interactive data exploration with VegaLite for GlobTim experiment campaigns.

Uses DataFrames.jl for data transformations and VegaLite for
interactive visualizations with linked selections and dynamic filtering.
"""

using VegaLite
using DataFrames
using Statistics
using Tidier: @chain, @filter

# Include data transformation utilities
include("TidierTransforms.jl")

"""
    campaign_to_dataframe(campaign::CampaignResults, campaign_stats::Dict) -> DataFrame

Convert campaign results to long-form DataFrame suitable for VegaLite plotting.

Each row represents one degree from one experiment, with all relevant metadata flattened.
"""
function campaign_to_dataframe(campaign::CampaignResults, campaign_stats::Dict)
    rows = []

    for exp_result in campaign.experiments
        exp_id = exp_result.experiment_id

        # Skip if no stats available
        if !haskey(campaign_stats, exp_id)
            continue
        end

        exp_stats = campaign_stats[exp_id]

        # Extract metadata (params_dict may vary by experiment)
        params_dict = get(exp_result.metadata, "params_dict", Dict())
        domain_size = get(params_dict, "domain_size_param", get(params_dict, "domain_size", missing))
        gn = get(params_dict, "GN", missing)
        total_cp = get(exp_result.metadata, "total_critical_points", 0)

        # Extract per-degree data from approximation quality
        if haskey(exp_stats, "approximation_quality")
            aq = exp_stats["approximation_quality"]
            degrees = aq["degrees"]
            l2_errors = aq["l2_errors"]

            for (idx, deg) in enumerate(degrees)
                l2 = l2_errors[idx]

                # Get parameter recovery error at this degree if available
                param_error = missing
                if haskey(exp_stats, "parameter_recovery")
                    pr = exp_stats["parameter_recovery"]
                    if deg in pr["degrees"]
                        deg_idx = findfirst(==(deg), pr["degrees"])
                        param_error = pr["recovery_errors"][deg_idx]
                    end
                end

                # Get critical points count at this degree if available
                cp_count = missing
                if haskey(exp_stats, "critical_points")
                    cp = exp_stats["critical_points"]
                    if deg in cp["degrees"]
                        deg_idx = findfirst(==(deg), cp["degrees"])
                        cp_count = cp["refined_critical_points"][deg_idx]
                    end
                end

                push!(rows, (
                    experiment_id = exp_id,
                    domain_size = domain_size,
                    GN = gn,
                    total_critical_points = total_cp,
                    degree = deg,
                    l2_error = l2,
                    param_recovery_error = param_error,
                    critical_points_at_degree = cp_count
                ))
            end
        end
    end

    return DataFrame(rows)
end

"""
    create_interactive_campaign_explorer(campaign::CampaignResults, campaign_stats::Dict) -> VegaLite.VLSpec

Create interactive campaign comparison with linked selection.

Click experiments in the bar chart to filter all other views.
"""
function create_interactive_campaign_explorer(campaign::CampaignResults, campaign_stats::Dict)
    # Convert to DataFrame
    df = campaign_to_dataframe(campaign, campaign_stats)

    if nrow(df) == 0
        error("No data available to plot. Check that campaign_stats contains valid statistics.")
    end

    # Create multi-view dashboard with linked selection
    @vlplot(
        title = "Campaign: $(campaign.campaign_id)",
        data = df,
        vconcat = [
            # View 1: Experiment selector (bar chart of total critical points)
            {
                mark = :bar,
                title = "Select Experiments (click to highlight)",
                width = 600,
                height = 150,
                encoding = {
                    x = {
                        field = :experiment_id,
                        type = :nominal,
                        axis = {labelAngle = -45},
                        title = "Experiment ID"
                    },
                    y = {
                        field = :total_critical_points,
                        type = :quantitative,
                        title = "Total Critical Points"
                    },
                    color = {
                        condition = {
                            param = :brush,
                            field = :domain_size,
                            type = :quantitative,
                            scale = {scheme = :viridis}
                        },
                        value = :lightgray
                    },
                    tooltip = [
                        {:experiment_id, title = "Experiment"},
                        {:domain_size, title = "Domain Size"},
                        {:GN, title = "Grid Number"},
                        {:total_critical_points, title = "Critical Points"}
                    ]
                },
                params = [
                    {
                        name = :brush,
                        select = {type = :point, on = :click, toggle = true}
                    }
                ]
            },

            # View 2: L2 convergence (filtered by selection)
            {
                mark = {:line, point = true},
                title = "L2 Approximation Error (selected experiments)",
                width = 600,
                height = 250,
                transform = [{filter = {param = :brush}}],
                encoding = {
                    x = {
                        field = :degree,
                        type = :ordinal,
                        title = "Polynomial Degree"
                    },
                    y = {
                        field = :l2_error,
                        type = :quantitative,
                        scale = {type = :log},
                        title = "L2 Error (log scale)"
                    },
                    color = {
                        field = :experiment_id,
                        type = :nominal,
                        legend = {title = "Experiment"}
                    },
                    tooltip = [
                        {:experiment_id, title = "Experiment"},
                        {:degree, title = "Degree"},
                        {:l2_error, title = "L2 Error", format = ".2e"},
                        {:domain_size, title = "Domain Size"}
                    ]
                }
            },

            # View 3: Parameter recovery (if available)
            {
                mark = {:line, point = true},
                title = "Parameter Recovery Error",
                width = 600,
                height = 250,
                transform = [
                    {filter = {param = :brush}},
                    {filter = {field = :param_recovery_error, valid = true}}
                ],
                encoding = {
                    x = {
                        field = :degree,
                        type = :ordinal,
                        title = "Polynomial Degree"
                    },
                    y = {
                        field = :param_recovery_error,
                        type = :quantitative,
                        scale = {type = :log},
                        title = "Parameter Error (log scale)"
                    },
                    color = {
                        field = :experiment_id,
                        type = :nominal,
                        legend = {title = "Experiment"}
                    },
                    tooltip = [
                        {:experiment_id, title = "Experiment"},
                        {:degree, title = "Degree"},
                        {:param_recovery_error, title = "Param Error", format = ".2e"}
                    ]
                }
            }
        ]
    )
end

"""
    create_convergence_dashboard(campaign::CampaignResults, campaign_stats::Dict) -> VegaLite.VLSpec

Create comprehensive convergence analysis dashboard using Tidier-transformed data.

Features:
- Convergence rate visualization
- Error reduction trajectories
- Parameter sensitivity analysis
- Efficiency metrics
"""
function create_convergence_dashboard(campaign::CampaignResults, campaign_stats::Dict)
    # Use Tidier pipeline to prepare data
    df_tidy = campaign_to_tidy_dataframe(campaign, campaign_stats)

    if nrow(df_tidy) == 0
        error("No data available for convergence dashboard")
    end

    # Compute convergence analysis
    df_convergence = compute_convergence_analysis(df_tidy)

    @vlplot(
        title = "Convergence Analysis: $(campaign.campaign_id)",
        data = df_convergence,
        vconcat = [
            # View 1: Convergence quality distribution
            {
                mark = {:bar, tooltip = true},
                title = "Convergence Quality Distribution",
                width = 600,
                height = 200,
                encoding = {
                    x = {
                        field = :convergence_quality,
                        type = :nominal,
                        title = "Convergence Quality",
                        sort = ["excellent", "good", "moderate", "poor"]
                    },
                    y = {
                        aggregate = :count,
                        type = :quantitative,
                        title = "Number of Experiments"
                    },
                    color = {
                        field = :convergence_quality,
                        type = :nominal,
                        scale = {
                            domain = ["excellent", "good", "moderate", "poor"],
                            range = ["#2ecc71", "#3498db", "#f39c12", "#e74c3c"]
                        },
                        legend = nothing
                    }
                }
            },

            # View 2: Effective convergence scatter
            {
                mark = {:point, size = 100},
                title = "Effective Convergence vs Domain Size",
                width = 600,
                height = 250,
                selection = {
                    hover = {type = :single, on = :mouseover, empty = :none}
                },
                encoding = {
                    x = {
                        field = :domain_size,
                        type = :quantitative,
                        title = "Domain Size"
                    },
                    y = {
                        field = :effective_convergence,
                        type = :quantitative,
                        title = "Effective Convergence (log reduction per degree)"
                    },
                    color = {
                        field = :convergence_quality,
                        type = :nominal,
                        scale = {
                            domain = ["excellent", "good", "moderate", "poor"],
                            range = ["#2ecc71", "#3498db", "#f39c12", "#e74c3c"]
                        },
                        legend = {title = "Quality"}
                    },
                    size = {
                        field = :error_reduction_ratio,
                        type = :quantitative,
                        scale = {type = :log},
                        legend = {title = "Error Reduction"}
                    },
                    opacity = {
                        condition = {selection = :hover, value = 1.0},
                        value = 0.7
                    },
                    tooltip = [
                        {:experiment_id, title = "Experiment"},
                        {:domain_size, title = "Domain Size"},
                        {:effective_convergence, title = "Effective Convergence", format = ".3f"},
                        {:error_reduction_ratio, title = "Error Reduction", format = ".2e"},
                        {:degrees_tested, title = "Degrees Tested"}
                    ]
                }
            },

            # View 3: Error reduction trajectories
            {
                mark = {:line, point = true},
                title = "Initial vs Final Error",
                width = 600,
                height = 250,
                encoding = {
                    x = {
                        field = :initial_error,
                        type = :quantitative,
                        scale = {type = :log},
                        title = "Initial L2 Error (log scale)"
                    },
                    y = {
                        field = :final_error,
                        type = :quantitative,
                        scale = {type = :log},
                        title = "Final L2 Error (log scale)"
                    },
                    color = {
                        field = :domain_size,
                        type = :quantitative,
                        scale = {scheme = :viridis},
                        legend = {title = "Domain Size"}
                    },
                    tooltip = [
                        {:experiment_id, title = "Experiment"},
                        {:initial_error, title = "Initial Error", format = ".2e"},
                        {:final_error, title = "Final Error", format = ".2e"},
                        {:log_error_reduction, title = "Log Reduction", format = ".2f"}
                    ]
                }
            }
        ]
    )
end

"""
    create_parameter_sensitivity_plot(campaign::CampaignResults, campaign_stats::Dict) -> VegaLite.VLSpec

Create parameter sensitivity analysis plot using Tidier aggregations.

Shows how varying parameters (domain_size, GN) affect metrics.
"""
function create_parameter_sensitivity_plot(campaign::CampaignResults, campaign_stats::Dict)
    df_tidy = campaign_to_tidy_dataframe(campaign, campaign_stats)

    if nrow(df_tidy) == 0
        error("No data available for parameter sensitivity plot")
    end

    # Compute sensitivity analysis
    df_sensitivity = compute_parameter_sensitivity(df_tidy)

    @vlplot(
        title = "Parameter Sensitivity: $(campaign.campaign_id)",
        data = df_sensitivity,
        vconcat = [
            # L2 error sensitivity
            {
                mark = {:line, point = true, strokeWidth = 2},
                title = "L2 Error vs Domain Size (by Degree)",
                width = 600,
                height = 300,
                encoding = {
                    x = {
                        field = :domain_size,
                        type = :quantitative,
                        title = "Domain Size"
                    },
                    y = {
                        field = :mean_l2,
                        type = :quantitative,
                        scale = {type = :log},
                        title = "Mean L2 Error (log scale)"
                    },
                    color = {
                        field = :degree,
                        type = :ordinal,
                        legend = {title = "Polynomial Degree"}
                    },
                    strokeDash = {
                        field = :degree,
                        type = :ordinal
                    },
                    tooltip = [
                        {:domain_size, title = "Domain Size"},
                        {:degree, title = "Degree"},
                        {:mean_l2, title = "Mean L2", format = ".2e"},
                        {:std_l2, title = "Std L2", format = ".2e"},
                        {:n_experiments, title = "N Experiments"}
                    ]
                }
            },

            # Error bars showing variability
            {
                mark = {:errorbar, extent = :stdev},
                width = 600,
                height = 80,
                encoding = {
                    x = {
                        field = :domain_size,
                        type = :quantitative,
                        title = "Domain Size"
                    },
                    y = {
                        field = :mean_l2,
                        type = :quantitative,
                        scale = {type = :log},
                        title = "L2 Error Range"
                    },
                    yError = {
                        field = :std_l2
                    },
                    color = {
                        field = :degree,
                        type = :ordinal
                    }
                }
            }
        ]
    )
end

"""
    create_multi_metric_comparison(campaign::CampaignResults, campaign_stats::Dict) -> VegaLite.VLSpec

Create faceted comparison of multiple metrics using Tidier's pivot_longer.

Shows L2 error, parameter recovery, and condition number in parallel.
"""
function create_multi_metric_comparison(campaign::CampaignResults, campaign_stats::Dict)
    df_tidy = campaign_to_tidy_dataframe(campaign, campaign_stats)

    if nrow(df_tidy) == 0
        error("No data available for multi-metric comparison")
    end

    # Pivot to long format for faceting
    df_long = pivot_metrics_longer(df_tidy)

    @vlplot(
        title = "Multi-Metric Comparison: $(campaign.campaign_id)",
        data = df_long,
        facet = {
            row = {
                field = :metric_category,
                type = :nominal,
                title = "Metric Type",
                header = {labelAngle = 0}
            }
        },
        spec = {
            width = 600,
            height = 200,
            mark = {:line, point = true},
            selection = {
                exp_select = {
                    type = :multi,
                    fields = [:experiment_id],
                    bind = :legend
                }
            },
            encoding = {
                x = {
                    field = :degree,
                    type = :ordinal,
                    title = "Polynomial Degree"
                },
                y = {
                    field = :log_metric_value,
                    type = :quantitative,
                    title = "Log10(Metric Value)"
                },
                color = {
                    field = :experiment_id,
                    type = :nominal,
                    legend = {title = "Experiment"}
                },
                opacity = {
                    condition = {selection = :exp_select, value = 1.0},
                    value = 0.2
                },
                tooltip = [
                    {:experiment_id, title = "Experiment"},
                    {:degree, title = "Degree"},
                    {:metric_name, title = "Metric"},
                    {:metric_value, title = "Value", format = ".2e"},
                    {:domain_size, title = "Domain Size"}
                ]
            }
        },
        resolve = {scale = {y = :independent}}
    )
end

"""
    create_efficiency_analysis(campaign::CampaignResults, campaign_stats::Dict) -> VegaLite.VLSpec

Create computational efficiency analysis using Tidier-computed metrics.

Analyzes error reduction per unit of computational cost.
"""
function create_efficiency_analysis(campaign::CampaignResults, campaign_stats::Dict)
    df_tidy = campaign_to_tidy_dataframe(campaign, campaign_stats)

    if nrow(df_tidy) == 0
        error("No data available for efficiency analysis")
    end

    # Filter to experiments with timing data
    df_efficiency = @chain df_tidy begin
        @filter(!ismissing(total_time))
    end

    if nrow(df_efficiency) == 0
        error("No timing data available for efficiency analysis")
    end

    df_efficiency = compute_efficiency_metrics(df_efficiency)

    @vlplot(
        title = "Computational Efficiency: $(campaign.campaign_id)",
        data = df_efficiency,
        vconcat = [
            # Efficiency vs degree
            {
                mark = {:line, point = true},
                title = "Error-Time Efficiency vs Degree",
                width = 600,
                height = 250,
                encoding = {
                    x = {
                        field = :degree,
                        type = :ordinal,
                        title = "Polynomial Degree"
                    },
                    y = {
                        field = :error_time_efficiency,
                        type = :quantitative,
                        title = "Efficiency (log error reduction per time·degree)"
                    },
                    color = {
                        field = :experiment_id,
                        type = :nominal,
                        legend = {title = "Experiment"}
                    },
                    tooltip = [
                        {:experiment_id, title = "Experiment"},
                        {:degree, title = "Degree"},
                        {:l2_error, title = "L2 Error", format = ".2e"},
                        {:time_per_degree, title = "Time/Degree", format = ".2f"},
                        {:error_time_efficiency, title = "Efficiency", format = ".3f"}
                    ]
                }
            },

            # Complexity scaling
            {
                mark = {:point, size = 100},
                title = "Computational Complexity vs Error",
                width = 600,
                height = 250,
                encoding = {
                    x = {
                        field = :complexity_estimate,
                        type = :quantitative,
                        scale = {type = :log},
                        title = "Complexity Estimate (degree^4, log scale)"
                    },
                    y = {
                        field = :l2_error,
                        type = :quantitative,
                        scale = {type = :log},
                        title = "L2 Error (log scale)"
                    },
                    color = {
                        field = :domain_size,
                        type = :quantitative,
                        scale = {scheme = :plasma},
                        legend = {title = "Domain Size"}
                    },
                    size = {
                        field = :degree,
                        type = :ordinal,
                        legend = {title = "Degree"}
                    },
                    tooltip = [
                        {:experiment_id, title = "Experiment"},
                        {:degree, title = "Degree"},
                        {:l2_error, title = "L2 Error", format = ".2e"},
                        {:complexity_estimate, title = "Complexity", format = ".0f"},
                        {:total_time, title = "Total Time", format = ".2f"}
                    ]
                }
            }
        ]
    )
end

"""
    create_outlier_detection_plot(campaign::CampaignResults, campaign_stats::Dict; metric::Symbol=:l2_error) -> VegaLite.VLSpec

Create outlier detection visualization using Tidier's annotation functions.

Highlights experiments with unusual metric values.
"""
function create_outlier_detection_plot(campaign::CampaignResults, campaign_stats::Dict; metric::Symbol=:l2_error)
    df_tidy = campaign_to_tidy_dataframe(campaign, campaign_stats)

    if nrow(df_tidy) == 0
        error("No data available for outlier detection")
    end

    # Annotate outliers
    df_outliers = annotate_outliers(df_tidy, metric, threshold=2.5)

    @vlplot(
        title = "Outlier Detection: $(String(metric))",
        data = df_outliers,
        vconcat = [
            # Main scatter plot with outliers highlighted
            {
                mark = {:point, size = 100},
                width = 600,
                height = 300,
                encoding = {
                    x = {
                        field = :degree,
                        type = :ordinal,
                        title = "Polynomial Degree"
                    },
                    y = {
                        field = metric,
                        type = :quantitative,
                        scale = {type = :log},
                        title = "$(String(metric)) (log scale)"
                    },
                    color = {
                        field = :is_outlier,
                        type = :nominal,
                        scale = {
                            domain = [false, true],
                            range = ["#3498db", "#e74c3c"]
                        },
                        legend = {title = "Outlier"}
                    },
                    size = {
                        condition = {test = "datum.is_outlier", value = 150},
                        value = 80
                    },
                    tooltip = [
                        {:experiment_id, title = "Experiment"},
                        {:degree, title = "Degree"},
                        {metric, title = String(metric), format = ".2e"},
                        {:z_score, title = "Z-Score", format = ".2f"},
                        {:is_outlier, title = "Outlier"}
                    ]
                }
            },

            # Z-score distribution
            {
                mark = :bar,
                width = 600,
                height = 150,
                encoding = {
                    x = {
                        field = :z_score,
                        type = :quantitative,
                        bin = {maxbins = 30},
                        title = "Z-Score"
                    },
                    y = {
                        aggregate = :count,
                        type = :quantitative,
                        title = "Count"
                    },
                    color = {
                        field = :is_outlier,
                        type = :nominal,
                        scale = {
                            domain = [false, true],
                            range = ["#3498db", "#e74c3c"]
                        }
                    }
                }
            }
        ]
    )
end

"""
    create_baseline_comparison(campaign::CampaignResults, campaign_stats::Dict, baseline_id::String) -> VegaLite.VLSpec

Create comparison plot relative to a baseline experiment using Tidier transformations.

Shows improvement ratios for all other experiments compared to baseline.
"""
function create_baseline_comparison(campaign::CampaignResults, campaign_stats::Dict, baseline_id::String)
    df_tidy = campaign_to_tidy_dataframe(campaign, campaign_stats)

    if nrow(df_tidy) == 0
        error("No data available for baseline comparison")
    end

    # Add baseline comparison
    df_compared = add_comparison_baseline(df_tidy, baseline_id)

    # Filter to non-baseline experiments
    df_compared = @chain df_compared begin
        @filter(experiment_id != baseline_id)
        @filter(!ismissing(l2_improvement_ratio))
    end

    @vlplot(
        title = "Performance vs Baseline: $baseline_id",
        data = df_compared,
        vconcat = [
            # Improvement ratio heatmap
            {
                mark = :rect,
                width = 600,
                height = 300,
                encoding = {
                    x = {
                        field = :degree,
                        type = :ordinal,
                        title = "Polynomial Degree"
                    },
                    y = {
                        field = :experiment_id,
                        type = :nominal,
                        title = "Experiment"
                    },
                    color = {
                        field = :l2_improvement_ratio,
                        type = :quantitative,
                        scale = {
                            scheme = :redyellowgreen,
                            domainMid = 1.0
                        },
                        legend = {title = "Improvement Ratio (>1 is better)"}
                    },
                    tooltip = [
                        {:experiment_id, title = "Experiment"},
                        {:degree, title = "Degree"},
                        {:l2_improvement_ratio, title = "L2 Improvement", format = ".2f"},
                        {:better_than_baseline, title = "Better than Baseline"}
                    ]
                }
            },

            # Bar chart showing overall performance
            {
                mark = :bar,
                width = 600,
                height = 200,
                transform = [
                    {
                        aggregate = [{op = :mean, field = :l2_improvement_ratio, as = :mean_improvement}],
                        groupby = [:experiment_id]
                    }
                ],
                encoding = {
                    x = {
                        field = :experiment_id,
                        type = :nominal,
                        title = "Experiment",
                        axis = {labelAngle = -45}
                    },
                    y = {
                        field = :mean_improvement,
                        type = :quantitative,
                        title = "Mean Improvement Ratio"
                    },
                    color = {
                        field = :mean_improvement,
                        type = :quantitative,
                        scale = {
                            scheme = :redyellowgreen,
                            domainMid = 1.0
                        },
                        legend = nothing
                    }
                }
            }
        ]
    )
end
