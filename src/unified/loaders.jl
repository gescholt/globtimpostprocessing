"""
Unified experiment loading for all experiment types.

Provides dispatch-based loading that returns type-specific data structures.
"""

# ============================================================================
# Main Loading Interface
# ============================================================================

"""
    load_experiment(path::String; type::Union{ExperimentType, Nothing}=nothing)

Load experiment data from a directory with automatic type detection.

This is the main unified entry point for loading any experiment. It:
1. Detects experiment type from path/config (or uses provided type)
2. Dispatches to type-specific loader
3. Returns appropriate data structure

# Arguments
- `path::String`: Path to experiment directory
- `type::Union{ExperimentType, Nothing}=nothing`: Optional explicit type (auto-detected if nothing)

# Returns
- Type-specific experiment data (e.g., `LV4DExperimentData`, `BaseExperimentData`)

# Examples
```julia
# Auto-detect type
data = load_experiment("globtim_results/lotka_volterra_4d/lv4d_GN8_deg4-12_...")
# => LV4DExperimentData

# Explicit type
data = load_experiment("some_experiment", type=DEUFLHARD)
# => BaseExperimentData (Deuflhard uses base for now)
```

# Type Detection
The function uses `detect_experiment_type()` to determine the experiment type:
1. Check directory basename for known prefixes (lv4d_, deuflhard_, etc.)
2. Parse experiment_config.json for system_type or function_name
3. Fall back to UNKNOWN if type cannot be determined
"""
function load_experiment(path::String; type::Union{ExperimentType, Nothing}=nothing)
    # Validate path exists
    if !isdir(path)
        error("Experiment directory not found: $path")
    end

    # Detect or use provided type
    exp_type = type === nothing ? detect_experiment_type(path) : type

    # Dispatch to type-specific loader
    return load_experiment(exp_type, path)
end

# ============================================================================
# Type-Specific Loaders (Dispatch)
# ============================================================================

"""
    load_experiment(::LV4DType, path::String) -> LV4DExperimentData

Load LV4D experiment data.

Delegates to LV4DAnalysis.load_lv4d_experiment() but constructs proper
base data for unified interface.
"""
function load_experiment(::LV4DType, path::String)
    # LV4DAnalysis has its own loader - delegate to it
    # This will be updated in Phase 2 to return proper LV4DExperimentData with base
    # For now, call the existing loader
    return Main.GlobtimPostProcessing.LV4DAnalysis.load_lv4d_experiment(path)
end

"""
    load_experiment(::DeuflhardType, path::String) -> BaseExperimentData

Load Deuflhard experiment data.

Returns BaseExperimentData since Deuflhard experiments don't have
type-specific extensions yet.
"""
function load_experiment(::DeuflhardType, path::String)
    return _load_generic_experiment(path, DEUFLHARD)
end

"""
    load_experiment(::FitzHughNagumoType, path::String) -> BaseExperimentData

Load FitzHugh-Nagumo experiment data.

Returns BaseExperimentData for now. Can be extended with FHN-specific
data structure in the future.
"""
function load_experiment(::FitzHughNagumoType, path::String)
    return _load_generic_experiment(path, FITZHUGH_NAGUMO)
end

"""
    load_experiment(::UnknownType, path::String) -> BaseExperimentData

Load experiment with unknown type.

Uses generic loading strategy that works for any experiment format.
"""
function load_experiment(::UnknownType, path::String)
    return _load_generic_experiment(path, UNKNOWN)
end

# ============================================================================
# Generic Loader (Fallback)
# ============================================================================

"""
    _load_generic_experiment(path::String, type::ExperimentType) -> BaseExperimentData

Generic experiment loader that works for any experiment type.

Loads:
1. experiment_config.json (optional)
2. results_summary.json → degree_results DataFrame
3. critical_points_deg_*.csv → combined critical_points DataFrame
"""
function _load_generic_experiment(path::String, type::ExperimentType)::BaseExperimentData
    experiment_id = basename(path)

    # Load config (optional)
    config = _load_config_safe(path)

    # Load results summary → degree_results DataFrame
    degree_results = _load_degree_results(path)

    # Load critical points
    critical_points = _load_critical_points(path)

    return BaseExperimentData(
        experiment_id,
        path,
        type,
        config,
        degree_results,
        critical_points
    )
end

"""
    _load_config_safe(path::String) -> Dict{String, Any}

Load experiment_config.json if it exists, return empty Dict otherwise.
"""
function _load_config_safe(path::String)::Dict{String, Any}
    config_path = joinpath(path, "experiment_config.json")
    if isfile(config_path)
        try
            return JSON.parsefile(config_path)
        catch e
            @debug "Failed to parse experiment_config.json" exception=e
            return Dict{String, Any}()
        end
    end
    return Dict{String, Any}()
end

"""
    _load_degree_results(path::String) -> DataFrame

Load results_summary.json and convert to DataFrame.
"""
function _load_degree_results(path::String)::DataFrame
    results_path = joinpath(path, "results_summary.json")
    if !isfile(results_path)
        return DataFrame()
    end

    try
        data = JSON.parsefile(results_path)

        # Handle array format (common)
        if data isa Vector
            return _results_array_to_dataframe(data)
        end

        # Handle dict format with results_summary key
        if data isa AbstractDict
            if haskey(data, "results_summary")
                results_summary = data["results_summary"]
                if results_summary isa AbstractDict
                    return _results_dict_to_dataframe(results_summary)
                end
            elseif haskey(data, "degree_results")
                return _results_array_to_dataframe(data["degree_results"])
            end
        end

        return DataFrame()
    catch e
        @debug "Failed to parse results_summary.json" exception=e
        return DataFrame()
    end
end

"""
    _results_array_to_dataframe(results::Vector) -> DataFrame

Convert array-format results_summary to DataFrame.
"""
function _results_array_to_dataframe(results::Vector)::DataFrame
    rows = Dict{String, Any}[]

    for r in results
        r isa AbstractDict || continue
        get(r, "success", false) || continue

        row = Dict{String, Any}()
        row["degree"] = get(r, "degree", 0)
        row["L2_norm"] = _extract_l2_norm(r)
        row["critical_points"] = get(r, "critical_points", get(r, "total_critical_points", 0))
        row["condition_number"] = _parse_condition_number(get(r, "condition_number", NaN))
        row["computation_time"] = get(r, "computation_time", NaN)

        # Optional fields
        if haskey(r, "gradient_valid_rate")
            row["gradient_valid_rate"] = r["gradient_valid_rate"]
        end
        if haskey(r, "recovery_error")
            row["recovery_error"] = r["recovery_error"]
        end

        push!(rows, row)
    end

    return isempty(rows) ? DataFrame() : DataFrame(rows)
end

"""
    _results_dict_to_dataframe(results_summary::AbstractDict) -> DataFrame

Convert dict-format results_summary to DataFrame.
"""
function _results_dict_to_dataframe(results_summary::AbstractDict)::DataFrame
    rows = Dict{String, Any}[]

    for (key, r) in results_summary
        r isa AbstractDict || continue

        # Extract degree from key (e.g., "degree_4" → 4)
        degree_str = replace(string(key), "degree_" => "")
        degree = tryparse(Int, degree_str)
        degree === nothing && continue

        row = Dict{String, Any}()
        row["degree"] = degree
        row["L2_norm"] = _extract_l2_norm(r)
        row["critical_points"] = get(r, "critical_points", 0)
        row["condition_number"] = _parse_condition_number(get(r, "condition_number", NaN))
        row["computation_time"] = get(r, "total_computation_time", NaN)

        push!(rows, row)
    end

    return isempty(rows) ? DataFrame() : DataFrame(rows)
end

"""
    _extract_l2_norm(r::AbstractDict) -> Float64

Extract L2_norm from result dict, handling orthant_stats.
"""
function _extract_l2_norm(r::AbstractDict)::Float64
    l2_norm = get(r, "L2_norm", NaN)

    if (l2_norm isa Number && isnan(l2_norm)) || l2_norm === nothing
        orthant_stats = get(r, "orthant_stats", nothing)
        if orthant_stats !== nothing && !isempty(orthant_stats)
            orthant_l2s = [get(os, "L2_norm", NaN) for os in orthant_stats]
            valid_l2s = filter(x -> x isa Number && !isnan(x), orthant_l2s)
            l2_norm = isempty(valid_l2s) ? NaN : maximum(valid_l2s)
        end
    end

    return l2_norm isa Number ? Float64(l2_norm) : NaN
end

"""
    _parse_condition_number(val) -> Float64

Parse condition_number which may be "NaN" string or a number.
"""
function _parse_condition_number(val)::Float64
    if val isa Number
        return Float64(val)
    elseif val isa String && lowercase(val) == "nan"
        return NaN
    else
        return NaN
    end
end

"""
    _load_critical_points(path::String) -> Union{DataFrame, Nothing}

Load and combine all critical_points_deg_*.csv files.
"""
function _load_critical_points(path::String)::Union{DataFrame, Nothing}
    csv_files = filter(readdir(path)) do f
        (startswith(f, "critical_points_deg_") || startswith(f, "critical_points_raw_deg_")) &&
        endswith(f, ".csv")
    end

    isempty(csv_files) && return nothing

    dfs = DataFrame[]
    for csv_file in csv_files
        # Extract degree from filename
        m = match(r"critical_points(?:_raw)?_deg_(\d+)\.csv", csv_file)
        m === nothing && continue

        degree = parse(Int, m.captures[1])
        try
            df = CSV.read(joinpath(path, csv_file), DataFrame)
            df[!, :degree] .= degree
            push!(dfs, df)
        catch e
            @debug "Failed to load $csv_file" exception=e
        end
    end

    return isempty(dfs) ? nothing : vcat(dfs...)
end

# ============================================================================
# Single Experiment Detection (Unified)
# ============================================================================

"""
    is_single_experiment(path::String) -> Bool

Check if a path is a single experiment directory (vs parent containing experiments).

Unified check that works for all experiment types.
"""
function is_single_experiment(path::String)::Bool
    !isdir(path) && return false

    # Dispatch on detected type for type-specific checks
    exp_type = detect_experiment_type(path)
    return is_single_experiment(exp_type, path)
end

"""
    is_single_experiment(::ExperimentType, path::String) -> Bool

Generic single experiment check.

Type-specific dispatches (e.g., LV4DType) are defined in their respective modules.
"""
function is_single_experiment(::ExperimentType, path::String)::Bool
    files = readdir(path)
    has_csv = any(f -> endswith(f, ".csv") &&
        (startswith(f, "critical_points_raw_deg_") || startswith(f, "critical_points_deg_")), files)
    has_results = "results_summary.json" in files || "results_summary.jld2" in files
    return has_csv || has_results
end

# ============================================================================
# Batch Loading
# ============================================================================

"""
    load_experiments(paths::Vector{String}; type::Union{ExperimentType, Nothing}=nothing)

Load multiple experiments.

# Arguments
- `paths`: Vector of experiment directory paths
- `type`: Optional explicit type (applied to all experiments)

# Returns
- Vector of experiment data structures (may be mixed types if type=nothing)
"""
function load_experiments(paths::Vector{String}; type::Union{ExperimentType, Nothing}=nothing)
    results = []
    for path in paths
        try
            data = load_experiment(path; type=type)
            push!(results, data)
        catch e
            @debug "Failed to load experiment" path=path exception=e
        end
    end
    return results
end

"""
    find_and_load_experiments(root::String; type::Union{ExperimentType, Nothing}=nothing, pattern=nothing)

Find and load all experiments in a directory.

# Arguments
- `root`: Root directory to search
- `type`: Optional explicit type filter
- `pattern`: Optional regex or string pattern to filter experiment names

# Returns
- Vector of loaded experiment data
"""
function find_and_load_experiments(root::String;
                                   type::Union{ExperimentType, Nothing}=nothing,
                                   pattern::Union{String, Regex, Nothing}=nothing)
    !isdir(root) && return []

    # Find experiment directories
    exp_dirs = String[]
    for entry in readdir(root, join=true)
        !isdir(entry) && continue

        # Filter by pattern if provided
        if pattern !== nothing
            regex = pattern isa Regex ? pattern : Regex(pattern)
            !occursin(regex, basename(entry)) && continue
        end

        # Check if it's an experiment
        if is_single_experiment(entry)
            # Filter by type if provided
            if type !== nothing
                detected = detect_experiment_type(entry)
                typeof(detected) != typeof(type) && continue
            end
            push!(exp_dirs, entry)
        end
    end

    # Sort by modification time (most recent first)
    sort!(exp_dirs, by=mtime, rev=true)

    return load_experiments(exp_dirs; type=type)
end
