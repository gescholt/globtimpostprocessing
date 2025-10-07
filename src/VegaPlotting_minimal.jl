"""
    VegaPlotting_minimal.jl

Minimal VegaLite plotting for L2 error visualization.
Start simple, test-driven approach.
"""

using VegaLite
using DataFrames
using Statistics

"""
    campaign_to_l2_dataframe(campaign::CampaignResults, campaign_stats::Dict) -> DataFrame

Convert campaign results to simple DataFrame with L2 errors.
Minimal version - just experiment_id, degree, and l2_error.
"""
function campaign_to_l2_dataframe(campaign::CampaignResults, campaign_stats::Dict)
    rows = []

    for exp_result in campaign.experiments
        exp_id = exp_result.experiment_id

        if !haskey(campaign_stats, exp_id)
            continue
        end

        exp_stats = campaign_stats[exp_id]

        # Extract L2 errors from approximation_quality
        if haskey(exp_stats, "approximation_quality")
            aq = exp_stats["approximation_quality"]
            degrees = aq["degrees"]
            l2_errors = aq["l2_errors"]

            for (idx, deg) in enumerate(degrees)
                l2 = l2_errors[idx]

                push!(rows, (
                    experiment_id = exp_id,
                    degree = deg,
                    l2_error = l2
                ))
            end
        end
    end

    return DataFrame(rows)
end

"""
    plot_l2_convergence(campaign::CampaignResults, campaign_stats::Dict) -> VegaLite.VLSpec

Create simple L2 error convergence plot.
"""
function plot_l2_convergence(campaign::CampaignResults, campaign_stats::Dict)
    # Convert to DataFrame
    df = campaign_to_l2_dataframe(campaign, campaign_stats)

    if nrow(df) == 0
        error("No L2 error data available to plot")
    end

    # Simple line plot with log scale
    @vlplot(
        title = "L2 Approximation Error",
        data = df,
        mark = {:line, point = true},
        width = 600,
        height = 400,
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
                {:l2_error, title = "L2 Error", format = ".2e"}
            ]
        }
    )
end
