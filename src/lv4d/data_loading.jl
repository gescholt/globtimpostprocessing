"""
Unified data loading for LV4D experiments.

Provides consistent loading of experiment configs, results, and critical points.
"""

# Import unified pipeline types
using ..UnifiedPipeline: BaseExperimentData, ExperimentType, LV4DType, LV4D
using ..UnifiedPipeline: get_base, experiment_id, experiment_type, experiment_path

# ============================================================================
# Data Structures
# ============================================================================

"""
    LV4DExperimentData

Container for all data from a single LV4D experiment.

# Fields
- `base::BaseExperimentData`: Common experiment data (id, path, type, config, results)
- `params::ExperimentParams`: Parsed parameters from directory name
- `p_true::Vector{Float64}`: True parameter values
- `p_center::Vector{Float64}`: Domain center
- `domain_size::Float64`: Domain half-width (sample_range)
- `dim::Int`: Parameter dimension

# Accessors
Use `get_base(data)` to access the base data, or use forwarding accessors:
- `experiment_id(data)` - Get experiment ID
- `experiment_path(data)` - Get experiment path (same as data.base.path)
- `degree_results(data)` - Get degree results DataFrame
- `critical_points(data)` - Get critical points DataFrame

# Example
```julia
data = load_lv4d_experiment("path/to/lv4d_GN8_...")
println(experiment_id(data))  # "lv4d_GN8_..."
println(data.p_true)          # [0.2, 0.3, 0.5, 0.6]
```
"""
struct LV4DExperimentData
    base::BaseExperimentData
    params::ExperimentParams
    p_true::Vector{Float64}
    p_center::Vector{Float64}
    domain_size::Float64
    dim::Int
end

# Implement get_base protocol
UnifiedPipeline.get_base(data::LV4DExperimentData) = data.base

# Backward compatibility accessors
"""Get experiment directory path (backward compatible with data.dir)."""
Base.getproperty(data::LV4DExperimentData, sym::Symbol) = begin
    if sym === :dir
        return data.base.path
    elseif sym === :degree_results
        return data.base.degree_results
    elseif sym === :critical_points
        return data.base.critical_points
    else
        return getfield(data, sym)
    end
end

Base.propertynames(::LV4DExperimentData) = (:base, :params, :p_true, :p_center, :domain_size, :dim, :dir, :degree_results, :critical_points)

"""
    LV4DSweepData

Container for aggregated sweep data across multiple experiments.

# Fields
- `experiments::Vector{LV4DExperimentData}`: Individual experiment data
- `results_root::String`: Root directory of sweep
- `summary::DataFrame`: Aggregated summary statistics
"""
struct LV4DSweepData
    experiments::Vector{LV4DExperimentData}
    results_root::String
    summary::DataFrame
end

# ============================================================================
# Config Loading
# ============================================================================

"""
    load_experiment_config_json(experiment_dir::String) -> Dict{String, Any}

Load experiment_config.json from an experiment directory.
"""
function load_experiment_config_json(experiment_dir::String)::Dict{String, Any}
    config_path = joinpath(experiment_dir, "experiment_config.json")
    isfile(config_path) || error("experiment_config.json not found in $experiment_dir")
    return JSON.parsefile(config_path)
end

"""
    load_results_summary_json(experiment_dir::String) -> Vector{Dict{String, Any}}

Load results_summary.json from an experiment directory.
"""
function load_results_summary_json(experiment_dir::String)::Vector{Any}
    results_path = joinpath(experiment_dir, "results_summary.json")
    isfile(results_path) || error("results_summary.json not found in $experiment_dir")
    return JSON.parsefile(results_path)
end

# ============================================================================
# Critical Points Loading
# ============================================================================

"""
    load_critical_points_csv(experiment_dir::String) -> DataFrame

Load and combine all critical_points_deg_*.csv files from an experiment directory.
Adds a `degree` column based on filename.
"""
function load_critical_points_csv(experiment_dir::String)::DataFrame
    csv_files = filter(readdir(experiment_dir)) do f
        startswith(f, "critical_points_deg_") && endswith(f, ".csv")
    end

    if isempty(csv_files)
        return DataFrame()
    end

    dfs = DataFrame[]
    for csv_file in csv_files
        m = match(r"critical_points_deg_(\d+)\.csv", csv_file)
        m === nothing && continue

        degree = parse(Int, m.captures[1])
        df = CSV.read(joinpath(experiment_dir, csv_file), DataFrame)
        df[!, :degree] .= degree
        push!(dfs, df)
    end

    return isempty(dfs) ? DataFrame() : vcat(dfs...)
end

"""
    load_critical_point_metrics(experiment_dir::String) -> Union{DataFrame, Nothing}

Load critical point metrics (gradient_norm, z values) from CSV files.
Returns DataFrame with columns: domain, degree, GN, gradient_norm, z
"""
function load_critical_point_metrics(experiment_dir::String)::Union{DataFrame, Nothing}
    dirname = basename(experiment_dir)
    params = parse_experiment_name(dirname)
    params === nothing && return nothing

    csv_files = filter(readdir(experiment_dir)) do f
        startswith(f, "critical_points_deg_") && endswith(f, ".csv")
    end

    isempty(csv_files) && return nothing

    rows = DataFrame[]
    for csv_file in csv_files
        m = match(r"critical_points_deg_(\d+)\.csv", csv_file)
        m === nothing && continue
        degree = parse(Int, m.captures[1])

        try
            df = CSV.read(joinpath(experiment_dir, csv_file), DataFrame)
            has_grad = "gradient_norm" in names(df)
            has_z = "z" in names(df)

            if has_grad || has_z
                for i in 1:nrow(df)
                    push!(rows, DataFrame(
                        domain = params.domain,
                        degree = degree,
                        GN = params.GN,
                        gradient_norm = has_grad ? Float64(df.gradient_norm[i]) : NaN,
                        z = has_z ? Float64(df.z[i]) : NaN
                    ))
                end
            end
        catch e
            @debug "Failed to load $csv_file: $e"
        end
    end

    return isempty(rows) ? nothing : vcat(rows...)
end

# ============================================================================
# Main Experiment Loading
# ============================================================================

"""
    load_lv4d_experiment(experiment_dir::String) -> LV4DExperimentData

Load all data from a single LV4D experiment directory.

# Arguments
- `experiment_dir::String`: Path to experiment directory

# Returns
`LV4DExperimentData` containing parsed config, results, and critical points.
"""
function load_lv4d_experiment(experiment_dir::String)::LV4DExperimentData
    dirname_str = basename(experiment_dir)
    params = parse_experiment_name(dirname_str)
    params === nothing && error("Could not parse experiment name: $dirname_str")

    # Load config
    config = load_experiment_config_json(experiment_dir)
    p_true = Float64.(config["p_true"])
    p_center = Float64.(config["p_center"])
    # Handle both config formats: "sample_range" (standard) and "domain_range" (subdivision)
    domain_size = Float64(get(config, "sample_range", get(config, "domain_range", NaN)))
    isnan(domain_size) && error("Config missing both 'sample_range' and 'domain_range' keys")
    dim = length(p_true)

    # Load results summary and convert to DataFrame
    results = load_results_summary_json(experiment_dir)
    degree_results = _parse_results_summary(results, params, config)

    # Load critical points
    critical_points = load_critical_points_csv(experiment_dir)

    # Add distance to true parameters if coordinates exist
    if !isempty(critical_points)
        x_cols = [Symbol("x$i") for i in 1:dim]
        if all(c -> hasproperty(critical_points, c), x_cols)
            distances = [
                norm([row[c] for c in x_cols] .- p_true)
                for row in eachrow(critical_points)
            ]
            critical_points[!, :dist_to_true] = distances
        end
    end

    # Construct BaseExperimentData
    cp_result = isempty(critical_points) ? nothing : critical_points
    base = BaseExperimentData(
        dirname_str,
        experiment_dir,
        LV4D,
        config,
        degree_results,
        cp_result
    )

    return LV4DExperimentData(
        base, params, p_true, p_center, domain_size, dim
    )
end

"""
    _parse_results_summary(results, params, config) -> DataFrame

Parse results_summary.json into a DataFrame.
"""
function _parse_results_summary(results::Vector, params::ExperimentParams,
                                config::Dict)::DataFrame
    rows = DataFrame[]

    for r in results
        get(r, "success", false) || continue

        # Handle L2_norm: either direct or from orthant_stats
        l2_norm = get(r, "L2_norm", NaN)
        if (l2_norm isa Number && isnan(l2_norm)) || l2_norm === nothing
            orthant_stats = get(r, "orthant_stats", nothing)
            if orthant_stats !== nothing && !isempty(orthant_stats)
                orthant_l2s = [get(os, "L2_norm", NaN) for os in orthant_stats]
                valid_l2s = filter(!isnan, orthant_l2s)
                l2_norm = isempty(valid_l2s) ? NaN : maximum(valid_l2s)
            end
        end

        # Handle critical_points
        crit_pts = get(r, "critical_points", nothing)
        if crit_pts === nothing
            crit_pts = get(r, "total_critical_points", 0)
        end

        row = DataFrame(
            domain = params.domain,
            degree = get(r, "degree", 0),
            seed = something(params.seed, get(config, "seed", nothing), 0),
            GN = params.GN,
            is_subdivision = params.is_subdivision,
            L2_norm = Float64(l2_norm isa Number ? l2_norm : NaN),
            condition_number = parse_condition_number(get(r, "condition_number", NaN)),
            critical_points = crit_pts,
            gradient_valid_rate = get(r, "gradient_valid_rate", 0.0),
            gradient_valid_count = get(r, "gradient_valid_count", 0),
            mean_gradient_norm = get(r, "mean_gradient_norm", NaN),
            min_gradient_norm = get(r, "min_gradient_norm", NaN),
            recovery_error = get(r, "recovery_error", NaN),
            hessian_minima = get(r, "hessian_minima", 0),
            hessian_saddle = get(r, "hessian_saddle", 0),
            hessian_degenerate = get(r, "hessian_degenerate", 0),
            computation_time = get(r, "computation_time", NaN),
            experiment_dir = basename(get(config, "experiment_dir", ""))
        )
        push!(rows, row)
    end

    return isempty(rows) ? DataFrame() : vcat(rows...)
end

# ============================================================================
# Sweep Loading
# ============================================================================

"""
    LoadResult

Result of loading experiments with success/failure tracking.

# Fields
- `loaded::Vector{LV4DExperimentData}`: Successfully loaded experiments
- `failed::Vector{String}`: Paths to experiments that failed to load
- `errors::Dict{String, String}`: Error messages for failed loads
"""
struct LoadResult
    loaded::Vector{LV4DExperimentData}
    failed::Vector{String}
    errors::Dict{String, String}
end

"""
    load_sweep_experiments(results_root::String; pattern=nothing, report_failures::Bool=false) -> Vector{LV4DExperimentData}

Load multiple experiments from a results directory.

# Arguments
- `results_root::String`: Directory containing experiment subdirectories
- `pattern::Union{String, Regex, Nothing}`: Optional filter pattern
- `report_failures::Bool=false`: Print summary of failed loads

# Returns
Vector of `LV4DExperimentData` for all matching experiments.

See also: [`load_sweep_experiments_with_report`](@ref) for detailed failure info.
"""
function load_sweep_experiments(results_root::Union{String, Nothing};
                               pattern::Union{String, Regex, Nothing}=nothing,
                               report_failures::Bool=false
                               )::Vector{LV4DExperimentData}
    result = load_sweep_experiments_with_report(results_root; pattern=pattern)

    if report_failures && !isempty(result.failed)
        println("Skipped $(length(result.failed)) experiments that failed to load:")
        for path in result.failed
            println("  - $(basename(path)): $(result.errors[path])")
        end
    end

    return result.loaded
end

"""
    load_sweep_experiments_with_report(results_root::Union{String, Nothing}; pattern=nothing) -> LoadResult

Load multiple experiments with detailed failure reporting.

# Arguments
- `results_root::Union{String, Nothing}`: Directory containing experiment subdirectories, or `nothing` to search all
- `pattern::Union{String, Regex, Nothing}`: Optional filter pattern

# Returns
`LoadResult` containing:
- `loaded`: Successfully loaded experiments
- `failed`: Paths to failed experiments
- `errors`: Dict mapping failed paths to error messages

# Example
```julia
result = load_sweep_experiments_with_report(nothing)  # Search all
println("Loaded: \$(length(result.loaded)), Failed: \$(length(result.failed))")
if !isempty(result.failed)
    for (path, err) in result.errors
        println("  \$(basename(path)): \$err")
    end
end
```
"""
function load_sweep_experiments_with_report(results_root::Union{String, Nothing};
                                           pattern::Union{String, Regex, Nothing}=nothing
                                           )::LoadResult
    exp_dirs = find_experiments(results_root; pattern=pattern)
    loaded = LV4DExperimentData[]
    failed = String[]
    errors = Dict{String, String}()

    for exp_dir in exp_dirs
        try
            data = load_lv4d_experiment(exp_dir)
            push!(loaded, data)
        catch e
            push!(failed, exp_dir)
            errors[exp_dir] = sprint(showerror, e)
            @debug "Failed to load experiment $(basename(exp_dir)): $e"
        end
    end

    return LoadResult(loaded, failed, errors)
end

# ============================================================================
# Domain Membership Analysis
# ============================================================================

"""
    analyze_domain_membership(df::DataFrame, center::Vector{Float64}, domain_size::Float64)

Check if critical points are within domain bounds [center - domain_size, center + domain_size].

# Returns
NamedTuple with:
- `total`: Total number of critical points
- `in_domain`: Count of points inside domain
- `out_of_domain`: Count of points outside domain
- `fraction_in`: Fraction of points inside domain
- `per_dim_violations`: Vector of counts of violations per dimension
"""
function analyze_domain_membership(df::DataFrame, center::Vector{Float64},
                                   domain_size::Float64)
    dim = length(center)
    x_cols = [Symbol("x$i") for i in 1:dim]

    all(c -> hasproperty(df, c), x_cols) || return nothing

    in_domain_count = 0
    per_dim_violations = zeros(Int, dim)

    for row in eachrow(df)
        point = [row[c] for c in x_cols]
        deviations = abs.(point .- center)
        in_bounds = deviations .<= domain_size

        if all(in_bounds)
            in_domain_count += 1
        else
            for i in 1:dim
                if !in_bounds[i]
                    per_dim_violations[i] += 1
                end
            end
        end
    end

    return (
        total = nrow(df),
        in_domain = in_domain_count,
        out_of_domain = nrow(df) - in_domain_count,
        fraction_in = in_domain_count / max(1, nrow(df)),
        per_dim_violations = per_dim_violations
    )
end
