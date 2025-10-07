"""
    TidierTransforms.jl

Data transformation pipeline for GlobTim campaign analysis.

This module provides data transformations using DataFrames.jl for preprocessing
experiment results before visualization with VegaLite. Functions are designed
to work seamlessly with Tidier.jl when available.
"""

using DataFrames
using Statistics

"""
    campaign_to_tidy_dataframe(campaign::CampaignResults, campaign_stats::Dict) -> DataFrame

Convert campaign results to tidy (long-form) DataFrame using Tidier.jl pipeline.

# Transformations Applied
- Flatten nested statistics into rows (one row per degree per experiment)
- Extract and normalize parameter metadata
- Compute derived metrics (convergence rate, efficiency ratios)
- Handle missing values consistently
- Add categorical variables for grouping

# Returns
Tidy DataFrame with columns:
- experiment_id: Experiment identifier
- domain_size: Domain parameter
- GN: Grid number
- degree: Polynomial degree
- l2_error: Approximation error
- param_recovery_error: Parameter recovery error
- critical_points_at_degree: Number of critical points
- convergence_rate: Log(error) reduction per degree
- efficiency_ratio: Error reduction per computational cost
"""
function campaign_to_tidy_dataframe(campaign::CampaignResults, campaign_stats::Dict)
    # First, create raw DataFrame
    rows = []

    for exp_result in campaign.experiments
        exp_id = exp_result.experiment_id

        if !haskey(campaign_stats, exp_id)
            continue
        end

        exp_stats = campaign_stats[exp_id]

        # Extract metadata
        params_dict = get(exp_result.metadata, "params_dict", Dict())
        domain_size = get(params_dict, "domain_size_param", get(params_dict, "domain_size", missing))
        gn = get(params_dict, "GN", missing)
        total_cp = get(exp_result.metadata, "total_critical_points", 0)

        # Get computation time if available
        total_time = get(exp_result.metadata, "total_time", missing)

        # Extract per-degree data from approximation quality
        if haskey(exp_stats, "approximation_quality")
            aq = exp_stats["approximation_quality"]
            degrees = aq["degrees"]
            l2_errors = aq["l2_errors"]

            for (idx, deg) in enumerate(degrees)
                l2 = l2_errors[idx]

                # Get parameter recovery error at this degree
                param_error = missing
                if haskey(exp_stats, "parameter_recovery")
                    pr = exp_stats["parameter_recovery"]
                    if deg in pr["degrees"]
                        deg_idx = findfirst(==(deg), pr["degrees"])
                        param_error = pr["recovery_errors"][deg_idx]
                    end
                end

                # Get critical points count at this degree
                cp_count = missing
                if haskey(exp_stats, "critical_points")
                    cp = exp_stats["critical_points"]
                    if deg in cp["degrees"]
                        deg_idx = findfirst(==(deg), cp["degrees"])
                        cp_count = cp["refined_critical_points"][deg_idx]
                    end
                end

                # Get condition number if available
                cond_num = missing
                if haskey(exp_stats, "numerical_stability")
                    ns = exp_stats["numerical_stability"]
                    if deg in ns["degrees"]
                        deg_idx = findfirst(==(deg), ns["degrees"])
                        cond_num = ns["condition_numbers"][deg_idx]
                    end
                end

                push!(rows, (
                    experiment_id = exp_id,
                    domain_size = domain_size,
                    GN = gn,
                    total_critical_points = total_cp,
                    total_time = total_time,
                    degree = deg,
                    l2_error = l2,
                    param_recovery_error = param_error,
                    critical_points_at_degree = cp_count,
                    condition_number = cond_num
                ))
            end
        end
    end

    df = DataFrame(rows)

    if nrow(df) == 0
        return df
    end

    # Apply manual transformations for derived metrics
    # Sort by experiment and degree
    sort!(df, [:experiment_id, :degree])

    # Add log error column
    df[!, :log_l2_error] = log10.(df.l2_error)

    # Compute convergence rate per experiment
    df[!, :convergence_rate] = missing
    for exp_id in unique(df.experiment_id)
        exp_mask = df.experiment_id .== exp_id
        exp_rows = findall(exp_mask)

        if length(exp_rows) > 1
            for i in 2:length(exp_rows)
                row_idx = exp_rows[i]
                prev_idx = exp_rows[i-1]

                log_diff = df.log_l2_error[prev_idx] - df.log_l2_error[row_idx]
                deg_diff = df.degree[row_idx] - df.degree[prev_idx]

                if deg_diff > 0
                    df.convergence_rate[row_idx] = log_diff / deg_diff
                end
            end
        end
    end

    # Add normalized metrics
    df[!, :l2_error_normalized] = missing
    df[!, :param_error_normalized] = missing

    for exp_id in unique(df.experiment_id)
        exp_mask = df.experiment_id .== exp_id
        exp_rows = findall(exp_mask)

        if !isempty(exp_rows)
            first_l2 = df.l2_error[exp_rows[1]]
            df.l2_error_normalized[exp_rows] .= df.l2_error[exp_rows] ./ first_l2

            # Param error normalization
            param_errors = df.param_recovery_error[exp_rows]
            non_missing = .!ismissing.(param_errors)
            if any(non_missing)
                first_param = first(filter(!ismissing, param_errors))
                for i in exp_rows
                    if !ismissing(df.param_recovery_error[i])
                        df.param_error_normalized[i] = df.param_recovery_error[i] / first_param
                    end
                end
            end
        end
    end

    # Add categorical variables
    df[!, :domain_category] = map(df.domain_size) do ds
        ismissing(ds) && return missing
        ds < 0.1 ? "small" : ds < 1.0 ? "medium" : "large"
    end

    df[!, :error_category] = map(df.l2_error) do err
        ismissing(err) && return missing
        err < 1e-6 ? "excellent" : err < 1e-3 ? "good" : err < 1e-1 ? "moderate" : "poor"
    end

    return df
end

"""
    compute_campaign_summary_stats(df::DataFrame) -> DataFrame

Compute summary statistics across experiments using Tidier pipeline.

Groups by key parameters (domain_size, GN) and computes aggregated metrics.
"""
function compute_campaign_summary_stats(df::DataFrame)
    @chain df begin
        @group_by(domain_size, GN, degree)
        @summarize(
            n_experiments = n(),
            mean_l2_error = mean(skipmissing(l2_error)),
            std_l2_error = std(skipmissing(l2_error)),
            min_l2_error = minimum(skipmissing(l2_error)),
            max_l2_error = maximum(skipmissing(l2_error)),
            mean_param_error = mean(skipmissing(param_recovery_error)),
            mean_convergence_rate = mean(skipmissing(convergence_rate)),
            mean_critical_points = mean(skipmissing(critical_points_at_degree))
        )
        @ungroup()
        @arrange(domain_size, GN, degree)
    end
end

"""
    compute_convergence_analysis(df::DataFrame) -> DataFrame

Analyze convergence behavior across degrees using Tidier pipeline.

Fits log-linear convergence models and computes convergence rates.
"""
function compute_convergence_analysis(df::DataFrame)
    @chain df begin
        @filter(!ismissing(l2_error) && l2_error > 0)
        @group_by(experiment_id)
        @summarize(
            degrees_tested = length(degree),
            min_degree = minimum(degree),
            max_degree = maximum(degree),
            initial_error = first(l2_error),
            final_error = last(l2_error),
            error_reduction_ratio = first(l2_error) / last(l2_error),
            log_error_reduction = log10(first(l2_error) / last(l2_error)),
            mean_convergence_rate = mean(skipmissing(convergence_rate)),
            domain_size = first(domain_size),
            GN = first(GN)
        )
        @mutate(
            effective_convergence = log_error_reduction / (max_degree - min_degree),
            convergence_quality = if effective_convergence > 0.5
                "excellent"
            elseif effective_convergence > 0.3
                "good"
            elseif effective_convergence > 0.1
                "moderate"
            else
                "poor"
            end
        )
        @ungroup()
        @arrange(desc(effective_convergence))
    end
end

"""
    compute_efficiency_metrics(df::DataFrame) -> DataFrame

Compute computational efficiency metrics using Tidier pipeline.

Analyzes error reduction per unit of computational cost.
"""
function compute_efficiency_metrics(df::DataFrame)
    @chain df begin
        @filter(!ismissing(l2_error) && !ismissing(total_time))
        @group_by(experiment_id)
        @mutate(
            # Computational complexity scales roughly as degree^d (d = dimension)
            complexity_estimate = degree^4,  # Assuming 4D problems
            time_per_degree = total_time / n(),
            error_time_efficiency = -log10(l2_error) / (time_per_degree * degree)
        )
        @ungroup()
    end
end

"""
    filter_best_experiments(df::DataFrame, metric::Symbol, n::Int=5) -> DataFrame

Select top N experiments by specified metric using Tidier pipeline.

# Arguments
- df: Input tidy DataFrame
- metric: Metric to rank by (e.g., :l2_error, :param_recovery_error)
- n: Number of top experiments to select

# Returns
DataFrame containing only the best N experiments
"""
function filter_best_experiments(df::DataFrame, metric::Symbol, n::Int=5)
    @chain df begin
        @group_by(experiment_id)
        @summarize(
            best_metric_value = minimum(skipmissing(!!metric)),
            domain_size = first(domain_size),
            GN = first(GN)
        )
        @ungroup()
        @arrange(best_metric_value)
        @slice(1:min(n, nrow(@current_data())))
    end
end

"""
    pivot_metrics_longer(df::DataFrame) -> DataFrame

Convert multiple metric columns to long format for faceted VegaLite plots.

Transforms columns like l2_error, param_recovery_error into:
- metric_name
- metric_value
"""
function pivot_metrics_longer(df::DataFrame)
    # Select relevant columns
    base_cols = [:experiment_id, :domain_size, :GN, :degree]
    metric_cols = [:l2_error, :param_recovery_error, :condition_number]

    # Filter to existing columns
    available_metrics = filter(col -> col in names(df), metric_cols)

    if isempty(available_metrics)
        return df
    end

    df_long = @chain df begin
        @select(!!base_cols..., !!available_metrics...)
        # Stack metrics into long format
        DataFrames.stack(available_metrics, base_cols,
                        variable_name=:metric_name, value_name=:metric_value)
        @filter(!ismissing(metric_value))
        @mutate(
            log_metric_value = log10(metric_value),
            metric_category = if metric_name == "l2_error"
                "Approximation"
            elseif metric_name == "param_recovery_error"
                "Parameter Recovery"
            elseif metric_name == "condition_number"
                "Numerical Stability"
            else
                "Other"
            end
        )
    end

    return df_long
end

"""
    compute_parameter_sensitivity(df::DataFrame) -> DataFrame

Analyze how varying parameters affect metrics using Tidier pipeline.

Groups by parameter values and computes statistics to identify sensitivities.
"""
function compute_parameter_sensitivity(df::DataFrame)
    @chain df begin
        @group_by(domain_size, degree)
        @summarize(
            n_experiments = n(),
            mean_l2 = mean(skipmissing(l2_error)),
            std_l2 = std(skipmissing(l2_error)),
            mean_param_recovery = mean(skipmissing(param_recovery_error)),
            std_param_recovery = std(skipmissing(param_recovery_error))
        )
        @ungroup()
        @mutate(
            cv_l2 = std_l2 / mean_l2,  # Coefficient of variation
            cv_param = if !ismissing(mean_param_recovery) && mean_param_recovery > 0
                std_param_recovery / mean_param_recovery
            else
                missing
            end
        )
        @arrange(domain_size, degree)
    end
end

"""
    add_comparison_baseline(df::DataFrame, baseline_exp_id::String) -> DataFrame

Add columns comparing each experiment to a baseline using Tidier pipeline.

# Arguments
- df: Input DataFrame
- baseline_exp_id: Experiment ID to use as baseline

# Returns
DataFrame with additional columns showing relative performance
"""
function add_comparison_baseline(df::DataFrame, baseline_exp_id::String)
    # Extract baseline data
    df_baseline = @chain df begin
        @filter(experiment_id == baseline_exp_id)
        @select(degree, baseline_l2 = l2_error, baseline_param = param_recovery_error)
    end

    # Join with original data and compute ratios
    df_compared = @chain df begin
        # Left join on degree
        leftjoin(df_baseline, on=:degree)
        @mutate(
            l2_improvement_ratio = if !ismissing(baseline_l2) && !ismissing(l2_error)
                baseline_l2 / l2_error
            else
                missing
            end,
            param_improvement_ratio = if !ismissing(baseline_param) && !ismissing(param_recovery_error)
                baseline_param / param_recovery_error
            else
                missing
            end,
            better_than_baseline = if !ismissing(l2_improvement_ratio)
                l2_improvement_ratio > 1.0
            else
                missing
            end
        )
    end

    return df_compared
end

"""
    compute_rolling_statistics(df::DataFrame, window_size::Int=3) -> DataFrame

Compute rolling window statistics using Tidier pipeline.

Useful for smoothing noisy metrics across degrees.
"""
function compute_rolling_statistics(df::DataFrame, window_size::Int=3)
    @chain df begin
        @arrange(experiment_id, degree)
        @group_by(experiment_id)
        @mutate(
            l2_rolling_mean = if nrow(@current_data()) >= window_size
                # Simple rolling mean implementation
                rolling_mean(l2_error, window_size)
            else
                l2_error
            end,
            convergence_rolling_mean = if nrow(@current_data()) >= window_size
                rolling_mean(convergence_rate, window_size)
            else
                convergence_rate
            end
        )
        @ungroup()
    end
end

"""
    rolling_mean(x::Vector, window::Int) -> Vector

Helper function to compute rolling mean for use in Tidier pipelines.
"""
function rolling_mean(x::Vector, window::Int)
    n = length(x)
    result = similar(x)

    for i in 1:n
        start_idx = max(1, i - window + 1)
        end_idx = min(n, i)
        result[i] = mean(skipmissing(x[start_idx:end_idx]))
    end

    return result
end

"""
    create_facet_ready_data(df::DataFrame, facet_by::Symbol) -> DataFrame

Prepare data for VegaLite faceted plots using Tidier pipeline.

Ensures proper grouping and ordering for multi-panel visualizations.
"""
function create_facet_ready_data(df::DataFrame, facet_by::Symbol)
    @chain df begin
        @group_by(!!facet_by)
        @mutate(
            facet_label = string(!!facet_by, " = ", first(!!facet_by)),
            group_size = n()
        )
        @ungroup()
        @arrange(!!facet_by, degree)
    end
end

"""
    annotate_outliers(df::DataFrame, metric::Symbol; threshold::Float64=3.0) -> DataFrame

Identify and annotate outliers using z-score method.

Uses z-score method to flag outliers beyond threshold standard deviations.
"""
function annotate_outliers(df::DataFrame, metric::Symbol; threshold::Float64=3.0)
    df_result = copy(df)

    metric_values = df_result[!, metric]
    metric_mean = mean(skipmissing(metric_values))
    metric_std = std(skipmissing(metric_values))

    df_result[!, :z_score] = map(metric_values) do val
        if ismissing(val) || metric_std == 0
            return missing
        else
            return (val - metric_mean) / metric_std
        end
    end

    df_result[!, :is_outlier] = map(df_result.z_score) do z
        ismissing(z) ? false : abs(z) > threshold
    end

    return df_result
end
