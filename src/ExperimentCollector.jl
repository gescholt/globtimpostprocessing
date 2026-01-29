"""
ExperimentCollector module

Provides functions for discovering, validating, and collecting experiment results
from both flat and hierarchical file system structures. Designed to be used
independently of analysis workflows.

Supports:
- Flat structure: All experiments directly in one directory
- Hierarchical structure: Experiments grouped by objective function
  (e.g., test_results/lotka_volterra_4d/exp_20251014_171206/)
- Campaign collections: Directories with hpc_results subdirectories
- Config-based grouping and filtering

Key functions:
- `detect_directory_structure`: Determine if path uses flat, hierarchical, or unknown structure
- `discover_experiments_flat`: Find experiments in flat collections
- `discover_experiments_hierarchical`: Find experiments grouped by objective
- `discover_experiments`: Auto-detect structure and discover appropriately
- `validate_experiment`: Check if a directory is a valid experiment
- `group_by_config_param`: Group experiments by config parameter values
- `group_by_degree_range`: Group experiments by degree range

Issues:
- globaloptim/globtimpostprocessing#9: Modularize and test experiment collection
- globaloptim/globtimpostprocessing#10: Support hierarchical experiment structure
- globaloptim/globtim#174: Hierarchical experiment output structure
"""
module ExperimentCollector

using JSON3
using Dates

export validate_experiment, discover_experiments, discover_campaigns
export discover_experiments_flat, discover_experiments_hierarchical
export detect_directory_structure, StructureType, Flat, Hierarchical, Unknown
export group_by_config_param, group_by_degree_range
export load_experiment_config, count_experiments
export ValidationResult, ExperimentInfo, CampaignInfo, ObjectiveGroup

"""
StructureType

Enumeration of supported directory structures.
"""
@enum StructureType begin
    Flat            # All experiments in one directory
    Hierarchical    # Experiments grouped by objective: base/objective/exp_timestamp/
    Unknown         # Cannot determine structure
end

"""
ValidationResult

Result of validating an experiment directory.

Fields:
- `is_valid::Bool`: Whether the experiment has all required components
- `has_csv::Bool`: Whether critical points CSV files exist
- `has_config::Bool`: Whether experiment_config.json exists
- `has_results::Bool`: Whether results_summary.json exists
- `path::String`: Path to the experiment directory
- `error_msg::Union{String, Nothing}`: Error message if validation failed
"""
struct ValidationResult
    is_valid::Bool
    has_csv::Bool
    has_config::Bool
    has_results::Bool
    path::String
    error_msg::Union{String, Nothing}
end

"""
ExperimentInfo

Information about a discovered experiment.

Fields:
- `path::String`: Absolute path to experiment directory
- `name::String`: Experiment directory name
- `objective::Union{String, Nothing}`: Objective function name (for hierarchical structure)
- `config::Union{Dict, Nothing}`: Loaded config (if available)
- `validation::ValidationResult`: Validation result for this experiment
"""
struct ExperimentInfo
    path::String
    name::String
    objective::Union{String, Nothing}
    config::Union{Dict, Nothing}
    validation::ValidationResult
end

# Convenience accessor
Base.getproperty(exp::ExperimentInfo, sym::Symbol) =
    sym === :is_valid ? getfield(exp, :validation).is_valid :
    getfield(exp, sym)

"""
ObjectiveGroup

Group of experiments for a single objective function (hierarchical structure).

Fields:
- `objective::String`: Objective function name
- `path::String`: Path to objective directory
- `experiments::Vector{ExperimentInfo}`: Experiments for this objective
"""
struct ObjectiveGroup
    objective::String
    path::String
    experiments::Vector{ExperimentInfo}
end

"""
CampaignInfo

Information about a discovered campaign.

Fields:
- `path::String`: Path to the campaign's hpc_results directory
- `name::String`: Campaign name (parent directory name)
- `num_experiments::Int`: Number of experiments in campaign
- `mtime::Float64`: Modification time (Unix timestamp)
"""
struct CampaignInfo
    path::String
    name::String
    num_experiments::Int
    mtime::Float64
end

"""
    validate_experiment(exp_path::String) -> ValidationResult

Validate that a directory contains a complete experiment with required files.

A valid experiment must have:
1. At least one critical_points_deg_*.csv file
2. experiment_config.json
3. results_summary.json (or results_summary.jld2)

Returns a ValidationResult with detailed status.
"""
function validate_experiment(exp_path::String)::ValidationResult
    # Check if path exists and is a directory
    if !isdir(exp_path)
        return ValidationResult(
            false, false, false, false, exp_path,
            "Path does not exist or is not a directory"
        )
    end

    try
        files = readdir(exp_path)

        # Check for critical points CSV files
        # Support both new format (critical_points_raw_deg_X.csv) and legacy (critical_points_deg_X.csv)
        has_csv = any(f -> endswith(f, ".csv") &&
            (startswith(f, "critical_points_raw_deg_") || startswith(f, "critical_points_deg_")), files)

        # Check for config file
        has_config = "experiment_config.json" in files

        # Check for results file
        has_results = "results_summary.json" in files || "results_summary.jld2" in files

        # Experiment is valid if it has all required components
        is_valid = has_csv && has_config && has_results

        error_msg = if !is_valid
            missing = String[]
            !has_csv && push!(missing, "critical points CSV")
            !has_config && push!(missing, "experiment_config.json")
            !has_results && push!(missing, "results_summary.json")
            "Missing: " * join(missing, ", ")
        else
            nothing
        end

        return ValidationResult(is_valid, has_csv, has_config, has_results, exp_path, error_msg)
    catch e
        return ValidationResult(
            false, false, false, false, exp_path,
            "Error reading directory: $(sprint(showerror, e))"
        )
    end
end

"""
    is_experiment_directory(path::String) -> Bool

Check if a directory appears to be an experiment based on file contents.
"""
function is_experiment_directory(path::String)::Bool
    if !isdir(path)
        return false
    end

    validation = validate_experiment(path)
    return validation.has_csv || validation.has_config || validation.has_results
end

"""
    detect_directory_structure(root_path::String) -> StructureType

Detect if directory uses flat, hierarchical, or unknown experiment structure.

Detection logic:
1. Hierarchical: Subdirectories contain exp_YYYYMMDD_HHMMSS folders (experiments grouped by objective)
2. Flat: Experiment directories directly in root
3. Unknown: No recognizable pattern

# Examples
```julia
detect_directory_structure("test_results/")
# Returns: Hierarchical if structure is test_results/lotka_volterra_4d/exp_20251014_171206/
# Returns: Flat if structure is test_results/experiment_20251014_171206/
```
"""
function detect_directory_structure(root_path::String)::StructureType
    if !isdir(root_path)
        return Unknown
    end

    try
        entries = readdir(root_path)

        # Check for hierarchical: subdirectories containing exp_* folders
        hierarchical_indicators = 0
        flat_indicators = 0

        for entry in entries
            entry_path = joinpath(root_path, entry)
            if !isdir(entry_path)
                continue
            end

            # Check if this is directly an experiment (flat indicator)
            if is_experiment_directory(entry_path)
                flat_indicators += 1
                continue
            end

            # Check if this contains exp_* subdirectories (hierarchical indicator)
            try
                subdirs = readdir(entry_path)
                has_exp_subdirs = false
                exp_count = 0

                for subdir in subdirs
                    subdir_path = joinpath(entry_path, subdir)
                    if isdir(subdir_path) && (startswith(subdir, "exp_") ||
                                              is_experiment_directory(subdir_path))
                        exp_count += 1
                        if startswith(subdir, "exp_")
                            has_exp_subdirs = true
                        end
                    end
                end

                # Hierarchical if this directory contains multiple exp_* experiments
                if has_exp_subdirs && exp_count >= 1
                    hierarchical_indicators += 1
                end
            catch
                # Ignore errors reading subdirectories
                continue
            end
        end

        # Decide based on indicators
        if hierarchical_indicators > 0 && flat_indicators == 0
            return Hierarchical
        elseif flat_indicators > 0 && hierarchical_indicators == 0
            return Flat
        elseif hierarchical_indicators > 0 && flat_indicators > 0
            # Mixed structure - prefer hierarchical if it's the dominant pattern
            return hierarchical_indicators >= flat_indicators ? Hierarchical : Flat
        else
            return Unknown
        end
    catch e
        @warn "Error detecting directory structure: $e"
        return Unknown
    end
end

"""
    load_experiment_config(exp_path::String) -> Union{Dict, Nothing}

Load experiment config from experiment_config.json if it exists.
Returns nothing if config cannot be loaded.
"""
function load_experiment_config(exp_path::String)::Union{Dict, Nothing}
    config_path = joinpath(exp_path, "experiment_config.json")
    if !isfile(config_path)
        return nothing
    end

    try
        config_text = read(config_path, String)
        return JSON3.read(config_text, Dict{String, Any})
    catch e
        @warn "Failed to load config from $config_path: $e"
        return nothing
    end
end

"""
    discover_experiments_flat(root_path::String) -> Vector{ExperimentInfo}

Discover experiments in a flat directory structure.
All experiments are directly in the root_path.

# Example
```julia
# Structure: test_results/experiment1/, experiment2/, ...
experiments = discover_experiments_flat("test_results")
```
"""
function discover_experiments_flat(root_path::String)::Vector{ExperimentInfo}
    experiments = ExperimentInfo[]

    if !isdir(root_path)
        @warn "Path does not exist or is not a directory: $root_path"
        return experiments
    end

    # Check each entry in root_path
    for entry in readdir(root_path)
        entry_path = joinpath(root_path, entry)

        # Skip files, only process directories
        if !isdir(entry_path)
            continue
        end

        # Validate as potential experiment
        validation = validate_experiment(entry_path)

        # If it has any experiment-like files, add it
        if validation.has_csv || validation.has_config || validation.has_results
            # Try to load config
            config = load_experiment_config(entry_path)

            push!(experiments, ExperimentInfo(
                entry_path,
                entry,
                nothing,  # No objective in flat structure
                config,
                validation
            ))
        end
    end

    return experiments
end

"""
    discover_experiments_hierarchical(root_path::String) -> Dict{String, Vector{ExperimentInfo}}

Discover experiments in hierarchical structure grouped by objective function.

Returns a dictionary mapping objective_name => [experiments].

# Structure
```
root_path/
├── lotka_volterra_4d/
│   ├── exp_20251014_171206/
│   └── exp_20251014_171530/
├── extended_brusselator/
│   └── exp_20251014_180000/
```

# Example
```julia
experiments_by_obj = discover_experiments_hierarchical("test_results")
# Returns: Dict("lotka_volterra_4d" => [...], "extended_brusselator" => [...])
```
"""
function discover_experiments_hierarchical(root_path::String)::Dict{String, Vector{ExperimentInfo}}
    results = Dict{String, Vector{ExperimentInfo}}()

    if !isdir(root_path)
        @warn "Path does not exist or is not a directory: $root_path"
        return results
    end

    for obj_name in readdir(root_path)
        obj_path = joinpath(root_path, obj_name)
        if !isdir(obj_path)
            continue
        end

        experiments = ExperimentInfo[]
        for exp_dir in readdir(obj_path)
            exp_path = joinpath(obj_path, exp_dir)
            if !isdir(exp_path)
                continue
            end

            # Validate this as an experiment
            validation = validate_experiment(exp_path)

            if validation.has_csv || validation.has_config || validation.has_results
                # Load config
                config = load_experiment_config(exp_path)

                push!(experiments, ExperimentInfo(
                    exp_path,
                    exp_dir,
                    obj_name,  # Store objective name
                    config,
                    validation
                ))
            end
        end

        if !isempty(experiments)
            # Sort by experiment name (timestamp-based for chronological order)
            sort!(experiments, by=e -> e.name)
            results[obj_name] = experiments
        end
    end

    return results
end

"""
    discover_experiments(path::String; recursive::Bool=false, structure::Union{StructureType, Nothing}=nothing)
    -> Union{Vector{ExperimentInfo}, Dict{String, Vector{ExperimentInfo}}}

Auto-detect structure and discover experiments appropriately.

Returns:
- `Vector{ExperimentInfo}` for flat structure
- `Dict{String, Vector{ExperimentInfo}}` for hierarchical structure (objective => experiments)

# Arguments
- `path`: Root path to search
- `recursive`: If true and structure is unknown, search recursively
- `structure`: Force a specific structure type (or auto-detect if nothing)

# Examples
```julia
# Auto-detect and discover
experiments = discover_experiments("test_results")

# Force flat discovery
experiments = discover_experiments("test_results", structure=Flat)

# Force hierarchical discovery
experiments_by_obj = discover_experiments("test_results", structure=Hierarchical)
```
"""
function discover_experiments(
    path::String;
    recursive::Bool=false,
    structure::Union{StructureType, Nothing}=nothing
)::Union{Vector{ExperimentInfo}, Dict{String, Vector{ExperimentInfo}}}

    # Detect structure if not provided
    detected_structure = isnothing(structure) ? detect_directory_structure(path) : structure

    if detected_structure == Hierarchical
        return discover_experiments_hierarchical(path)
    elseif detected_structure == Flat
        return discover_experiments_flat(path)
    else
        # Unknown structure - try recursive search as fallback
        if recursive
            @warn "Unknown directory structure, falling back to recursive search"
            return discover_experiments_flat(path)  # Fallback to flat
        else
            @warn "Unknown directory structure at $path. Try recursive=true or specify structure explicitly."
            return ExperimentInfo[]
        end
    end
end

"""
    group_by_config_param(experiments::Vector{ExperimentInfo}, param_key::String)
    -> Dict{Any, Vector{ExperimentInfo}}

Group experiments by a specific config parameter value.

# Examples
```julia
# Group by domain_size_param
groups = group_by_config_param(experiments, "domain_size_param")
# Returns: Dict(0.1 => [...], 0.4 => [...], 0.8 => [...])

# Group by grid_nodes
groups = group_by_config_param(experiments, "grid_nodes")
# Returns: Dict(8 => [...], 16 => [...])
```
"""
function group_by_config_param(
    experiments::Vector{ExperimentInfo},
    param_key::String
)::Dict{Any, Vector{ExperimentInfo}}
    groups = Dict{Any, Vector{ExperimentInfo}}()

    for exp in experiments
        # Skip if config not loaded
        if isnothing(exp.config)
            continue
        end

        if haskey(exp.config, param_key)
            param_val = exp.config[param_key]

            if !haskey(groups, param_val)
                groups[param_val] = ExperimentInfo[]
            end
            push!(groups[param_val], exp)
        end
    end

    return groups
end

"""
    group_by_degree_range(experiments::Vector{ExperimentInfo})
    -> Dict{Tuple{Int,Int}, Vector{ExperimentInfo}}

Group experiments by (min_degree, max_degree) range.

# Example
```julia
groups = group_by_degree_range(experiments)
# Returns: Dict((4, 12) => [...], (4, 18) => [...], (18, 18) => [...])
```
"""
function group_by_degree_range(
    experiments::Vector{ExperimentInfo}
)::Dict{Tuple{Int,Int}, Vector{ExperimentInfo}}
    groups = Dict{Tuple{Int,Int}, Vector{ExperimentInfo}}()

    for exp in experiments
        # Skip if config not loaded
        if isnothing(exp.config)
            continue
        end

        config = exp.config

        # Try different field names for degree range
        min_deg = get(config, "min_degree", get(config, "min_deg", nothing))
        max_deg = get(config, "max_degree", get(config, "max_deg", nothing))

        # Handle degree_range array format
        if haskey(config, "degree_range") && config["degree_range"] isa AbstractVector
            deg_range = config["degree_range"]
            if length(deg_range) >= 2
                min_deg = deg_range[1]
                max_deg = deg_range[2]
            end
        end

        if !isnothing(min_deg) && !isnothing(max_deg)
            deg_range = (Int(min_deg), Int(max_deg))

            if !haskey(groups, deg_range)
                groups[deg_range] = ExperimentInfo[]
            end
            push!(groups[deg_range], exp)
        end
    end

    return groups
end

"""
    discover_campaigns(root_path::String) -> Vector{CampaignInfo}

Discover all campaign directories containing multiple experiments.

A campaign must:
1. Have an `hpc_results` subdirectory (or be named hpc_results itself)
2. Contain at least 2 valid or partially valid experiments
3. Match naming patterns (collected_experiments_*, configs_*, etc.)

Returns campaigns sorted by modification time (newest first).

This function is designed for the legacy campaign/collection structure,
not for the new hierarchical structure.
"""
function discover_campaigns(root_path::String)::Vector{CampaignInfo}
    campaigns = CampaignInfo[]

    if !isdir(root_path)
        error("Path does not exist: $root_path")
    end

    for (root, dirs, _) in walkdir(root_path)
        # Check if this directory contains hpc_results subdirectory
        if "hpc_results" in dirs
            hpc_path = joinpath(root, "hpc_results")
            root_basename = basename(root)

            # Filter: Allow certain naming patterns
            is_allowed_campaign = startswith(root_basename, "collected_experiments_") ||
                                 startswith(root_basename, "configs_") ||
                                 contains(root_basename, "_study") ||
                                 contains(root_basename, "_campaign")

            # Skip top-level collection directories
            is_likely_collection = root_basename in ["globtim", "globtimcore", "Examples", "hpc_results",
                                                     "local", "cluster", "experiments"] ||
                                   contains(root, "/archives/")

            if is_likely_collection && !is_allowed_campaign
                continue
            end

            # Check if this has enough experiments to be a campaign
            experiments = discover_experiments_flat(hpc_path)

            # Campaign must have at least 2 experiments
            if length(experiments) >= 2
                mtime = stat(hpc_path).mtime
                push!(campaigns, CampaignInfo(
                    hpc_path,
                    root_basename,
                    length(experiments),
                    mtime
                ))
            end
        end
    end

    # Sort by modification time, newest first
    sort!(campaigns, by=c -> c.mtime, rev=true)

    return campaigns
end

"""
    count_experiments(path::String) -> Int

Recursively count all valid experiments in a directory tree.
Works with both flat and hierarchical structures.
"""
function count_experiments(path::String)::Int
    if !isdir(path)
        return 0
    end

    # Try to detect structure and count accordingly
    structure = detect_directory_structure(path)

    if structure == Hierarchical
        experiments_by_obj = discover_experiments_hierarchical(path)
        return sum(length(exps) for exps in values(experiments_by_obj))
    elseif structure == Flat
        experiments = discover_experiments_flat(path)
        return length(experiments)
    else
        # Unknown - do recursive count
        count = 0
        for entry in readdir(path)
            entry_path = joinpath(path, entry)
            if isdir(entry_path)
                if is_experiment_directory(entry_path)
                    count += 1
                else
                    count += count_experiments(entry_path)
                end
            end
        end
        return count
    end
end

end # module
