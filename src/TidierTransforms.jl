"""
    TidierTransforms.jl

Simplified data transformation functions for VegaLite visualizations.
Uses pure DataFrames.jl without Tidier dependency for maximum compatibility.
"""

using DataFrames
using Statistics

# Simple stub implementations for the key functions needed by VegaPlotting

function compute_convergence_analysis(df::DataFrame)
    # Group by experiment and compute convergence metrics
    result_rows = []
    
    for exp_id in unique(df.experiment_id)
        exp_data = df[df.experiment_id .== exp_id, :]
        
        if nrow(exp_data) < 2
            continue
        end
        
        degrees = exp_data.degree
        errors = exp_data.l2_error
        
        initial_error = first(errors)
        final_error = last(errors)
        error_reduction_ratio = initial_error / final_error
        log_error_reduction = log10(error_reduction_ratio)
        
        # Convergence rate
        conv_rates = Float64[]
        for i in 2:length(errors)
            if errors[i] > 0 && errors[i-1] > 0
                rate = (log10(errors[i-1]) - log10(errors[i])) / (degrees[i] - degrees[i-1])
                push!(conv_rates, rate)
            end
        end
        mean_conv_rate = isempty(conv_rates) ? missing : mean(conv_rates)
        
        effective_convergence = log_error_reduction / (maximum(degrees) - minimum(degrees))
        
        convergence_quality = if effective_convergence > 0.5
            "excellent"
        elseif effective_convergence > 0.3
            "good"
        elseif effective_convergence > 0.1
            "moderate"
        else
            "poor"
        end
        
        push!(result_rows, (
            experiment_id = exp_id,
            degrees_tested = nrow(exp_data),
            min_degree = minimum(degrees),
            max_degree = maximum(degrees),
            initial_error = initial_error,
            final_error = final_error,
            error_reduction_ratio = error_reduction_ratio,
            log_error_reduction = log_error_reduction,
            mean_convergence_rate = mean_conv_rate,
            effective_convergence = effective_convergence,
            convergence_quality = convergence_quality,
            domain_size = first(exp_data.domain_size),
            GN = first(exp_data.GN)
        ))
    end
    
    return DataFrame(result_rows)
end

function compute_parameter_sensitivity(df::DataFrame)
    # Aggregate by domain_size and degree
    gdf = groupby(df, [:domain_size, :degree])
    
    result = combine(gdf,
        nrow => :n_experiments,
        :l2_error => (x -> mean(skipmissing(x))) => :mean_l2,
        :l2_error => (x -> std(skipmissing(x))) => :std_l2,
        :param_recovery_error => (x -> mean(skipmissing(x))) => :mean_param_recovery,
        :param_recovery_error => (x -> std(skipmissing(x))) => :std_param_recovery
    )
    
    # Add coefficient of variation
    result[!, :cv_l2] = result.std_l2 ./ result.mean_l2
    result[!, :cv_param] = result.std_param_recovery ./ result.mean_param_recovery
    
    sort!(result, [:domain_size, :degree])
    
    return result
end

function compute_efficiency_metrics(df::DataFrame)
    df_result = copy(df)
    
    # Computational complexity (degree^4 for 4D)
    df_result[!, :complexity_estimate] = df_result.degree .^ 4
    
    # Time per degree
    df_result[!, :time_per_degree] = df_result.total_time ./ df_result.degree
    
    # Efficiency: log error reduction per time·degree
    df_result[!, :error_time_efficiency] = map(1:nrow(df_result)) do i
        if !ismissing(df_result.l2_error[i]) && df_result.l2_error[i] > 0 &&
           !ismissing(df_result.time_per_degree[i]) && df_result.time_per_degree[i] > 0
            return -log10(df_result.l2_error[i]) / (df_result.time_per_degree[i] * df_result.degree[i])
        else
            return missing
        end
    end
    
    return df_result
end

function pivot_metrics_longer(df::DataFrame)
    # Stack l2_error, param_recovery_error, condition_number into long format
    base_cols = [:experiment_id, :domain_size, :GN, :degree]
    metric_cols = Symbol[]
    
    for col in [:l2_error, :param_recovery_error, :condition_number]
        if col in names(df)
            push!(metric_cols, col)
        end
    end
    
    if isempty(metric_cols)
        return df
    end
    
    # Use DataFrames.stack
    df_long = stack(df, metric_cols, base_cols, variable_name=:metric_name, value_name=:metric_value)
    
    # Filter out missing
    filter!(row -> !ismissing(row.metric_value), df_long)
    
    # Add log metric
    df_long[!, :log_metric_value] = log10.(df_long.metric_value)
    
    # Add metric category
    df_long[!, :metric_category] = map(df_long.metric_name) do name
        if name == :l2_error
            "Approximation"
        elseif name == :param_recovery_error
            "Parameter Recovery"
        elseif name == :condition_number
            "Numerical Stability"
        else
            "Other"
        end
    end
    
    return df_long
end

function add_comparison_baseline(df::DataFrame, baseline_id::String)
    # Extract baseline data
    baseline_data = df[df.experiment_id .== baseline_id, [:degree, :l2_error, :param_recovery_error]]
    rename!(baseline_data, :l2_error => :baseline_l2, :param_recovery_error => :baseline_param)
    
    # Left join with main data
    df_result = leftjoin(df, baseline_data, on=:degree)
    
    # Compute improvement ratios
    df_result[!, :l2_improvement_ratio] = df_result.baseline_l2 ./ df_result.l2_error
    df_result[!, :param_improvement_ratio] = df_result.baseline_param ./ df_result.param_recovery_error
    df_result[!, :better_than_baseline] = df_result.l2_improvement_ratio .> 1.0
    
    return df_result
end

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
