"""
    ResultsLoader.jl

Handles loading experiment results from various formats (JSON, CSV, JLD2).
Automatically discovers and parses globtimcore output structure.

Includes fallback loading for truncated/corrupted JSON files using CSV data.
"""

# Include CSV fallback loader
include("CSVFallbackLoader.jl")
using .CSVFallbackLoader: can_use_csv_fallback, load_experiment_from_csv_fallback

"""
    load_experiment_results(path::String) -> ExperimentResult

Load experiment results from a file or directory.

Automatically detects globtimcore output format and parses:
- JSON metadata files with `enabled_tracking` labels
- Critical points DataFrames
- Performance metrics
- Tolerance validation results

# Arguments
- `path::String`: Path to experiment directory or result file

# Returns
- `ExperimentResult`: Parsed experiment data with metadata
"""
function load_experiment_results(path::String)
    if !ispath(path)
        error("Path not found: $path")
    end

    if isdir(path)
        return load_from_directory(path)
    else
        return load_from_file(path)
    end
end

"""
    is_single_experiment(path::String) -> Bool

Check if a directory is a single experiment (contains CSV/JSON result files directly).
"""
function is_single_experiment(path::String)
    if !isdir(path)
        return false
    end

    files = readdir(path)
    # Support both new format (critical_points_raw_deg_X.csv) and legacy (critical_points_deg_X.csv)
    has_csv = any(f -> endswith(f, ".csv") &&
        (startswith(f, "critical_points_raw_deg_") || startswith(f, "critical_points_deg_")), files)
    has_results = "results_summary.json" in files || "results_summary.jld2" in files

    return has_csv || has_results
end

"""
    load_campaign_results(campaign_dir::String) -> CampaignResults

Load experiment results from a campaign directory or single experiment.

Auto-detects whether the path is:
- A single experiment (contains CSV/JSON files directly) → loads as 1-experiment campaign
- A campaign directory (contains experiment subdirectories) → loads all experiments

Expects directory structure (campaign):
```
campaign_dir/
├── experiment_1/
├── experiment_2/
└── campaign_metadata.json (optional)
```

Or single experiment:
```
experiment_dir/
├── critical_points_deg_4.csv
├── critical_points_deg_5.csv
└── results_summary.json
```

# Arguments
- `campaign_dir::String`: Path to campaign directory or single experiment

# Returns
- `CampaignResults`: Collection of experiment results (1 or more)
"""
function load_campaign_results(campaign_dir::String)
    if !isdir(campaign_dir)
        error("Campaign directory not found: $campaign_dir")
    end

    println("📂 Loading campaign results from: $campaign_dir")

    experiments = ExperimentResult[]
    campaign_metadata = Dict{String, Any}()

    # Auto-detect: is this a single experiment or a campaign directory?
    if is_single_experiment(campaign_dir)
        # This is a single experiment - load it as a 1-experiment campaign
        println("  ℹ️  Detected single experiment (will load as 1-experiment campaign)")
        try
            exp_result = load_experiment_results(campaign_dir)
            push!(experiments, exp_result)
            println("  ✓ Loaded: $(exp_result.experiment_id)")
        catch e
            error("Failed to load experiment: $e")
        end
    else
        # This is a campaign directory - look for experiment subdirectories
        # Look for campaign metadata
        campaign_meta_path = joinpath(campaign_dir, "campaign_metadata.json")
        if isfile(campaign_meta_path)
            campaign_metadata = JSON.parsefile(campaign_meta_path)
        end

        # Find all experiment subdirectories
        for entry in readdir(campaign_dir, join=true)
            if isdir(entry)
                try
                    exp_result = load_experiment_results(entry)
                    push!(experiments, exp_result)
                    println("  ✓ Loaded: $(exp_result.experiment_id)")
                catch e
                    println("  ⚠ Skipped $(basename(entry)): $e")
                end
            end
        end
    end

    campaign_id = get(campaign_metadata, "campaign_id", basename(campaign_dir))

    return CampaignResults(
        campaign_id,
        experiments,
        campaign_metadata,
        now()
    )
end

"""
    load_from_directory(dir_path::String) -> ExperimentResult

Load experiment result from a directory containing globtimcore outputs.

Tries multiple loading strategies:
1. results_summary.json (primary format)
2. experiment_result_*.json (alternative format)
3. CSV fallback (for truncated/missing JSON)
"""
function load_from_directory(dir_path::String)
    # Look for results_summary.json first (primary format)
    results_file = joinpath(dir_path, "results_summary.json")

    if isfile(results_file)
        # Try to load from results_summary, but catch JSON parse errors
        try
            return load_from_results_summary(dir_path, results_file)
        catch e
            # JSON.jl throws ErrorException for parse errors, not a specific ParseError type
            if e isa ErrorException || e isa ArgumentError
                @warn "Failed to parse results_summary.json (possibly truncated), trying CSV fallback" exception=e
                # Fall through to CSV fallback
            else
                rethrow(e)
            end
        end
    end

    # Fall back to experiment_result_*.json format
    result_files = filter(f -> occursin(r"experiment_result_.*\.json", f), readdir(dir_path))

    if !isempty(result_files)
        return load_from_experiment_result(dir_path, joinpath(dir_path, result_files[1]))
    end

    # Final fallback: Try to load from CSV files if available
    if can_use_csv_fallback(dir_path)
        @info "Using CSV fallback loader for $dir_path"
        return load_from_csv_fallback_wrapper(dir_path)
    end

    error("No recognized result files found in $dir_path")
end

"""
    load_from_results_summary(dir_path::String, results_file::String) -> ExperimentResult

Load from results_summary.json format (primary globtimcore output).
"""
function load_from_results_summary(dir_path::String, results_file::String)
    data = JSON.parsefile(results_file)

    # Handle multiple formats:
    # 1. Array format: [{degree: 4, ...}, {degree: 5, ...}]
    # 2. Dict format with results_summary: {results_summary: {degree_4: {...}, degree_5: {...}}}
    # 3. Dict format with degree_results: {degree_results: [{degree: 4, ...}, ...]}
    if data isa Vector
        # Format 1: Convert array format to dict format
        normalized_data = Dict{String, Any}(
            "results_summary" => Dict{String, Any}(
                "degree_$(result["degree"])" => result
                for result in data if haskey(result, "degree")
            )
        )
        data = normalized_data
    elseif data isa AbstractDict && haskey(data, "degree_results") && !haskey(data, "results_summary")
        # Format 3: Convert degree_results array to results_summary dict
        degree_results = data["degree_results"]
        results_summary = Dict{String, Any}(
            "degree_$(result["degree"])" => result
            for result in degree_results if haskey(result, "degree")
        )
        # Create new dict with results_summary, preserving other fields
        normalized_data = Dict{String, Any}(data)
        normalized_data["results_summary"] = results_summary
        data = normalized_data
    end

    # Extract experiment ID
    experiment_id = get(data, "experiment_id", basename(dir_path))

    # Extract degrees from results_summary if not explicitly provided
    results_summary = get(data, "results_summary", Dict())
    degrees_processed = get(data, "degrees_processed", nothing)

    # If degrees_processed not found, extract from results_summary keys
    if degrees_processed === nothing && !isempty(results_summary)
        extracted_degrees = Int[]
        for key in keys(results_summary)
            # Extract degree number from "degree_N" keys
            degree_str = replace(string(key), "degree_" => "")
            try
                push!(extracted_degrees, parse(Int, degree_str))
            catch
                # Skip non-numeric keys
            end
        end
        degrees_processed = sort(extracted_degrees)
    end

    # Build metadata
    metadata = Dict{String, Any}(
        "params_dict" => get(data, "params_dict", Dict()),
        "system_info" => get(data, "system_info", Dict()),
        "experiment_type" => get(data, "experiment_type", "unknown"),
        "timestamp" => get(data, "timestamp", ""),
        "schema_version" => get(data, "schema_version", "1.0.0"),
        "total_time" => get(data, "total_time", nothing),
        "success_rate" => get(data, "success_rate", nothing),
        "total_critical_points" => get(data, "total_critical_points", nothing),
        "degrees_processed" => degrees_processed,
        "results_summary" => results_summary
    )

    # Discover tracking labels from data
    enabled_tracking, tracking_capabilities = discover_tracking_labels(data)

    # Load critical points from CSV files
    critical_points = load_critical_points_from_csvs(dir_path, data)

    # Extract performance metrics
    performance_metrics = extract_performance_metrics(data)

    # Extract tolerance validation
    tolerance_validation = extract_tolerance_validation(data)

    return ExperimentResult(
        experiment_id,
        metadata,
        enabled_tracking,
        tracking_capabilities,
        critical_points,
        performance_metrics,
        tolerance_validation,
        dir_path
    )
end

"""
    load_from_experiment_result(dir_path::String, result_file::String) -> ExperimentResult

Load from experiment_result_*.json format (alternative format).
"""
function load_from_experiment_result(dir_path::String, result_file::String)
    data = JSON.parsefile(result_file)

    metadata = get(data, "experiment_metadata", Dict())
    enabled_tracking = get(data, "enabled_tracking", String[])
    tracking_capabilities = get(data, "tracking_capabilities", String[])
    performance_metrics = get(data, "performance_metrics", nothing)
    tolerance_validation = get(data, "tolerance_validation", nothing)

    # Parse critical points DataFrame
    critical_points = nothing
    if haskey(data, "critical_points_dataframe")
        cp_data = data["critical_points_dataframe"]
        if haskey(cp_data, "columns") && haskey(cp_data, "data")
            critical_points = DataFrame([row for row in cp_data["data"]], cp_data["columns"])
        end
    end

    experiment_id = get(metadata, "experiment_id", basename(dir_path))

    return ExperimentResult(
        experiment_id,
        metadata,
        enabled_tracking,
        tracking_capabilities,
        critical_points,
        performance_metrics,
        tolerance_validation,
        dir_path
    )
end

"""
    discover_tracking_labels(data::AbstractDict) -> (Vector{String}, Vector{String})

Discover enabled tracking labels from results_summary.json data.
"""
function discover_tracking_labels(data::AbstractDict)
    enabled_tracking = String[]
    tracking_capabilities = String[]

    results_summary = get(data, "results_summary", Dict())

    if isempty(results_summary)
        return enabled_tracking, tracking_capabilities
    end

    # Get first degree to discover fields
    first_key = first(keys(results_summary))
    first_data = results_summary[first_key]

    # Label mappings
    label_map = Dict(
        "l2_approx_error" => "approximation_quality",
        "condition_number" => "numerical_stability",
        "critical_points" => "critical_point_count",
        "critical_points_refined" => "refined_critical_points",
        "recovery_error" => "parameter_recovery",
        "best_objective" => "optimization_quality",
        "polynomial_construction_time" => "polynomial_timing",
        "critical_point_solving_time" => "solving_timing",
        "refinement_time" => "refinement_timing",
        "total_computation_time" => "total_timing",
        "refinement_stats" => "refinement_quality",
    )

    for (field, label) in label_map
        if haskey(first_data, field)
            push!(tracking_capabilities, label)
            value = first_data[field]
            if value !== nothing
                push!(enabled_tracking, label)
            end
        end
    end

    # Check for parameter recovery
    system_info = get(data, "system_info", Dict())
    if haskey(system_info, "true_parameters")
        push!(tracking_capabilities, "distance_to_true_parameters")
        push!(enabled_tracking, "distance_to_true_parameters")
    end

    return enabled_tracking, tracking_capabilities
end

"""
    load_critical_points_from_csvs(dir_path::String, data::AbstractDict) -> Union{DataFrame, Nothing}

Load critical points from CSV files (critical_points_deg_N.csv).
"""
function load_critical_points_from_csvs(dir_path::String, data::AbstractDict)
    results_summary = get(data, "results_summary", Dict())

    if isempty(results_summary)
        return nothing
    end

    all_points = DataFrame[]

    for degree_key in keys(results_summary)
        degree_str = replace(string(degree_key), "degree_" => "")
        degree = parse(Int, degree_str)

        # Try new format first (Phase 2), fall back to legacy format
        csv_file_raw = joinpath(dir_path, "critical_points_raw_deg_$(degree).csv")
        csv_file_legacy = joinpath(dir_path, "critical_points_deg_$(degree).csv")
        csv_file = isfile(csv_file_raw) ? csv_file_raw : csv_file_legacy

        if !isfile(csv_file)
            continue
        end

        try
            df = CSV.read(csv_file, DataFrame, header=true)
            df[!, :degree] = fill(degree, nrow(df))
            push!(all_points, df)
        catch e
            @warn "Failed to load critical points for degree $degree" exception=e
        end
    end

    return isempty(all_points) ? nothing : vcat(all_points...)
end

"""
    extract_performance_metrics(data::AbstractDict) -> Union{Dict, Nothing}

Extract timing and performance metrics from results_summary.
"""
function extract_performance_metrics(data::AbstractDict)
    results_summary = get(data, "results_summary", Dict())

    if isempty(results_summary)
        return nothing
    end

    metrics = Dict{String, Any}()

    poly_times = Float64[]
    solving_times = Float64[]
    refinement_times = Float64[]
    total_times = Float64[]

    for (_, degree_data) in results_summary
        push!(poly_times, get(degree_data, "polynomial_construction_time", 0.0))
        push!(solving_times, get(degree_data, "critical_point_solving_time", 0.0))
        push!(refinement_times, get(degree_data, "refinement_time", 0.0))
        push!(total_times, get(degree_data, "total_computation_time", 0.0))
    end

    metrics["polynomial_construction"] = Dict(
        "mean" => mean(poly_times),
        "total" => sum(poly_times),
        "max" => maximum(poly_times)
    )

    metrics["critical_point_solving"] = Dict(
        "mean" => mean(solving_times),
        "total" => sum(solving_times),
        "max" => maximum(solving_times)
    )

    metrics["refinement"] = Dict(
        "mean" => mean(refinement_times),
        "total" => sum(refinement_times),
        "max" => maximum(refinement_times)
    )

    metrics["total_computation"] = Dict(
        "mean" => mean(total_times),
        "total" => sum(total_times),
        "max" => maximum(total_times)
    )

    metrics["experiment_total_time"] = get(data, "total_time", sum(total_times))

    return metrics
end

"""
    extract_tolerance_validation(data::AbstractDict) -> Union{Dict, Nothing}

Extract refinement and validation statistics.
"""
function extract_tolerance_validation(data::AbstractDict)
    results_summary = get(data, "results_summary", Dict())

    if isempty(results_summary)
        return nothing
    end

    validation = Dict{String, Any}()
    refinement_stats = []

    for (_, degree_data) in results_summary
        if haskey(degree_data, "refinement_stats")
            push!(refinement_stats, degree_data["refinement_stats"])
        end
    end

    if !isempty(refinement_stats)
        validation["refinement_stats"] = refinement_stats

        total_converged = sum(something(get(stat, "converged", nothing), 0) for stat in refinement_stats)
        total_failed = sum(something(get(stat, "failed", nothing), 0) for stat in refinement_stats)

        validation["convergence_summary"] = Dict(
            "total_converged" => total_converged,
            "total_failed" => total_failed,
            "success_rate" => total_converged / max(total_converged + total_failed, 1)
        )
    end

    return isempty(validation) ? nothing : validation
end

"""
    load_from_file(file_path::String) -> ExperimentResult

Load experiment result from a single JSON file.
"""
function load_from_file(file_path::String)
    if !endswith(file_path, ".json")
        error("Only JSON files supported for single-file loading")
    end

    data = JSON.parsefile(file_path)

    # Parse according to experiment_runner output format
    metadata = get(data, "experiment_metadata", get(data, "input_config", Dict()))
    enabled_tracking = get(data, "enabled_tracking", String[])
    tracking_capabilities = get(data, "tracking_capabilities", String[])
    performance_metrics = get(data, "performance_metrics", nothing)
    tolerance_validation = get(data, "tolerance_validation", nothing)

    # Parse DataFrame if present
    critical_points = nothing
    if haskey(data, "critical_points_dataframe")
        cp_data = data["critical_points_dataframe"]
        if haskey(cp_data, "columns") && haskey(cp_data, "data")
            critical_points = DataFrame([row for row in cp_data["data"]], cp_data["columns"])
        end
    end

    experiment_id = get(metadata, "experiment_id", basename(dirname(file_path)))

    return ExperimentResult(
        experiment_id,
        metadata,
        enabled_tracking,
        tracking_capabilities,
        critical_points,
        performance_metrics,
        tolerance_validation,
        file_path
    )
end

"""
    load_from_csv_fallback_wrapper(dir_path::String) -> ExperimentResult

Wrapper to convert CSV fallback loader output to ExperimentResult struct.
"""
function load_from_csv_fallback_wrapper(dir_path::String)
    result_nt = load_experiment_from_csv_fallback(dir_path)

    return ExperimentResult(
        result_nt.experiment_id,
        result_nt.metadata,
        result_nt.enabled_tracking,
        result_nt.tracking_capabilities,
        result_nt.critical_points,
        result_nt.performance_metrics,
        result_nt.tolerance_validation,
        result_nt.source_path
    )
end
