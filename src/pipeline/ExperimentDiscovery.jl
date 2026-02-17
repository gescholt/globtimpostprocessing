"""
    ExperimentDiscovery.jl - Scan for completed experiments

Discovers completed experiments by looking for `.EXPERIMENT_COMPLETE` markers.
"""

using Dates

# ============================================================================
# Completion Marker Parsing
# ============================================================================

"""
    is_experiment_complete(experiment_dir) -> Bool

Check if an experiment directory is complete.

Checks for (in order):
1. `.EXPERIMENT_COMPLETE` marker file (new experiments)
2. `results_summary.json` file (backward compatibility for older experiments)
"""
function is_experiment_complete(experiment_dir::String)::Bool
    # Primary: check for completion marker (new experiments)
    marker_path = joinpath(experiment_dir, ".EXPERIMENT_COMPLETE")
    if isfile(marker_path)
        return true
    end

    # Fallback: check for results_summary.json (older experiments)
    summary_path = joinpath(experiment_dir, "results_summary.json")
    return isfile(summary_path)
end

"""
    parse_completion_marker(experiment_dir) -> Union{Dict{String, Any}, Nothing}

Parse the completion marker file and return metadata.
Falls back to extracting metadata from results_summary.json for older experiments.
"""
function parse_completion_marker(experiment_dir::String)::Union{Dict{String, Any}, Nothing}
    marker_path = joinpath(experiment_dir, ".EXPERIMENT_COMPLETE")

    # Try parsing completion marker first
    if isfile(marker_path)
        metadata = Dict{String, Any}()
        try
            for line in eachline(marker_path)
                if occursin("=", line)
                    key, value = split(line, "=", limit=2)
                    key = strip(key)
                    value = strip(value)

                    # Parse value types
                    if key == "completed_at"
                        try
                            metadata[key] = DateTime(value)
                        catch e
                            @debug "Could not parse DateTime" value exception=(e, catch_backtrace())
                            metadata[key] = value
                        end
                    elseif value in ["true", "false"]
                        metadata[key] = value == "true"
                    elseif all(isdigit, value) || (startswith(value, "-") && all(isdigit, value[2:end]))
                        metadata[key] = parse(Int, value)
                    elseif occursin(".", value) && tryparse(Float64, value) !== nothing
                        metadata[key] = parse(Float64, value)
                    else
                        metadata[key] = value
                    end
                end
            end
            return metadata
        catch e
            @warn "Failed to parse completion marker" experiment_dir exception=e
        end
    end

    # Fallback: extract metadata from results_summary.json or experiment_config.json
    metadata = Dict{String, Any}("legacy" => true)

    # Try to get completion time from directory mtime
    try
        metadata["completed_at"] = DateTime(Dates.unix2datetime(mtime(experiment_dir)))
    catch e
        @debug "Could not get mtime for completion timestamp" experiment_dir exception=(e, catch_backtrace())
        metadata["completed_at"] = now()
    end

    # Try to extract info from config
    config_path = joinpath(experiment_dir, "experiment_config.json")
    if isfile(config_path)
        try
            config = JSON.parsefile(config_path)
            metadata["GN"] = get(config, "GN", nothing)
            metadata["domain"] = get(config, "domain_range", nothing)
            metadata["seed"] = get(config, "seed", nothing)
        catch e
            @warn "Failed to parse experiment config" config_path exception=(e, catch_backtrace())
        end
    end

    return metadata
end

# ============================================================================
# Experiment Discovery
# ============================================================================

"""
    find_completed_experiments(results_root; pattern="lotka_volterra_4d") -> Vector{String}

Find all experiment directories with completion markers.

Returns paths to experiment directories that have `.EXPERIMENT_COMPLETE` file.
"""
function find_completed_experiments(
    results_root::String;
    pattern::String="lotka_volterra_4d"
)::Vector{String}
    completed = String[]

    if !isdir(results_root)
        @warn "Results root not found" results_root
        return completed
    end

    # Search in the pattern subdirectory
    search_dir = joinpath(results_root, pattern)
    if !isdir(search_dir)
        # Also try without pattern (search results_root directly)
        search_dir = results_root
    end

    if !isdir(search_dir)
        return completed
    end

    for entry in readdir(search_dir, join=true)
        if isdir(entry) && is_experiment_complete(entry)
            push!(completed, entry)
        end
    end

    # Sort by modification time (newest first)
    sort!(completed, by=mtime, rev=true)
    return completed
end

"""
    scan_for_experiments!(registry; pattern="lotka_volterra_4d") -> Int

Scan for new completed experiments and add them to the registry.

Returns the number of new experiments discovered.

Parameters are extracted from the experiment directory name using `extract_params_from_name`.
"""
function scan_for_experiments!(
    registry::PipelineRegistry;
    pattern::String="lotka_volterra_4d"
)::Int
    completed = find_completed_experiments(registry.results_root; pattern=pattern)
    new_count = 0

    for exp_path in completed
        if !experiment_exists(registry, exp_path)
            name = basename(exp_path)
            marker_data = parse_completion_marker(exp_path)

            completed_at = if marker_data !== nothing && haskey(marker_data, "completed_at")
                marker_data["completed_at"] isa DateTime ? marker_data["completed_at"] : nothing
            else
                # Use directory modification time as fallback
                DateTime(Dates.unix2datetime(mtime(exp_path)))
            end

            # Extract params from name (add_experiment! will do this automatically if params=nothing)
            # but we can pass explicit params if we want to override
            add_experiment!(registry, exp_path, name;
                completed_at=completed_at
            )
            new_count += 1
        end
    end

    registry.last_scan = now()
    return new_count
end

"""
    discover_experiment_type(experiment_dir) -> Symbol

Detect the type of experiment from its directory name or config.
"""
function discover_experiment_type(experiment_dir::String)::Symbol
    name = lowercase(basename(experiment_dir))

    if startswith(name, "lv4d") || contains(name, "lotka_volterra_4d")
        return :lv4d
    elseif contains(name, "deuflhard")
        return :deuflhard
    elseif contains(name, "fhn") || contains(name, "fitzhugh")
        return :fhn
    else
        # Try to detect from config file
        config_path = joinpath(experiment_dir, "experiment_config.json")
        if isfile(config_path)
            try
                config = JSON.parsefile(config_path)
                obj_name = get(config, "objective_name", "")
                if contains(obj_name, "lotka_volterra")
                    return :lv4d
                elseif contains(obj_name, "deuflhard")
                    return :deuflhard
                end
            catch e
                @debug "Could not detect experiment type from config" config_path exception=(e, catch_backtrace())
            end
        end
        return :unknown
    end
end
