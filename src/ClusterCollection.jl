"""
ClusterCollection Module - Phase 0 Implementation

Provides functionality for collecting experiment results from HPC cluster.
Moved from globtimcore to globtimpostprocessing as part of Phase 0 reorganization.

See: EXPERIMENT_COLLECTION_ANALYSIS.md Phase 0 implementation

Features:
- Read tracking JSON files
- Detect experiment completion
- Generate rsync commands for collection
- Batch collection support
- Collection summary generation

Usage:
```julia
using ClusterCollection

# Find tracking file
tracking_file = find_tracking_file("tracking_dir", "batch_id_or_issue")

# Read sessions
tracking_data = read_tracking_json(tracking_file)
sessions = tracking_data["sessions"]

# Collect batch (requires ENV["CLUSTER_HOST"] and ENV["REMOTE_HPC_RESULTS"])
collect_batch(tracking_file, output_dir)
```
"""
module ClusterCollection

using JSON3
using Dates

export collect_cluster_experiments, collect_batch
export read_tracking_json, find_tracking_file, get_batch_sessions
export check_experiment_complete, build_rsync_command
export generate_collection_summary, write_collection_summary

"""
    read_tracking_json(tracking_file::String) -> Dict

Read and parse a tracking JSON file.

Returns Dict with String keys: batch_id, issue_number, created_at, sessions
Throws exception if file doesn't exist or JSON is invalid.
"""
function read_tracking_json(tracking_file::String)
    if !isfile(tracking_file)
        error("Tracking file not found: $tracking_file")
    end

    try
        data = JSON3.read(read(tracking_file, String))
        # Convert to Dict with String keys for consistency
        result = Dict{String, Any}()
        for (k, v) in pairs(data)
            key_str = String(k)
            result[key_str] = if v isa AbstractVector
                # Convert arrays to Vector{Dict}
                [Dict(String(kk) => vv for (kk, vv) in pairs(item)) for item in v]
            else
                v
            end
        end
        return result
    catch e
        error("Failed to parse tracking JSON from $tracking_file: $e")
    end
end

"""
    find_tracking_file(tracking_dir::String, batch_id_or_issue::String) -> Union{String, Nothing}

Find tracking JSON file by batch ID or issue number.

# Arguments
- `tracking_dir`: Directory containing tracking JSON files
- `batch_id_or_issue`: Either batch ID (e.g., "batch_20251006_115044") or issue number (e.g., "139")

Returns path to tracking file, or nothing if not found.
"""
function find_tracking_file(tracking_dir::String, batch_id_or_issue::String)
    if !isdir(tracking_dir)
        return nothing
    end

    # Try to find by batch ID directly
    if startswith(batch_id_or_issue, "batch_")
        candidate = joinpath(tracking_dir, "$(batch_id_or_issue).json")
        if isfile(candidate)
            return candidate
        end
    end

    # Search all tracking files
    for file in readdir(tracking_dir)
        if !endswith(file, ".json")
            continue
        end

        tracking_file = joinpath(tracking_dir, file)

        try
            data = read_tracking_json(tracking_file)

            # Match by batch ID
            if haskey(data, "batch_id") && data["batch_id"] == batch_id_or_issue
                return tracking_file
            end

            # Match by issue number (convert to Int for comparison)
            if haskey(data, "issue_number")
                issue_str = string(data["issue_number"])
                if issue_str == batch_id_or_issue
                    return tracking_file
                end
            end
        catch
            # Skip invalid JSON files
            continue
        end
    end

    return nothing
end

"""
    get_batch_sessions(tracking_file::String) -> Vector{Dict}

Extract sessions array from tracking JSON file.

Returns vector of session dictionaries, each containing:
- session_name: Experiment directory name
- status: Current status (e.g., "launching", "completed")
- launch_time: When the experiment was launched
- experiment_id: Unique experiment identifier
"""
function get_batch_sessions(tracking_file::String)
    data = read_tracking_json(tracking_file)

    if !haskey(data, "sessions")
        error("Tracking file $tracking_file missing 'sessions' field")
    end

    sessions = data["sessions"]

    # Convert to Vector{Dict} if needed
    return [Dict(pairs(s)) for s in sessions]
end

"""
    check_experiment_complete(experiment_dir::String) -> Bool

Check if an experiment has completed successfully.

Completion is detected by:
1. experiment.log contains "✨ Experiment complete!"
2. results_summary.json exists (alternative marker)

Returns true if experiment is complete, false otherwise.
"""
function check_experiment_complete(experiment_dir::String)
    if !isdir(experiment_dir)
        return false
    end

    # Method 1: Check experiment.log for completion marker
    log_file = joinpath(experiment_dir, "experiment.log")
    if isfile(log_file)
        try
            log_content = read(log_file, String)
            if occursin("✨ Experiment complete!", log_content)
                return true
            end
        catch
            # Log file exists but can't read - not complete
        end
    end

    # Method 2: Check for results_summary.json as alternative marker
    results_file = joinpath(experiment_dir, "results_summary.json")
    if isfile(results_file)
        return true
    end

    return false
end

"""
    build_rsync_command(cluster_host::String, remote_dir::String, local_dir::String) -> String

Generate rsync command for collecting experiment results.

# Arguments
- `cluster_host`: SSH host (e.g., "user@cluster.example.com")
- `remote_dir`: Remote experiment directory path
- `local_dir`: Local destination directory

Returns rsync command string with:
- `-a`: Archive mode (recursive, preserve permissions, etc.)
- `-z`: Compression
- `--progress`: Show transfer progress
"""
function build_rsync_command(cluster_host::String, remote_dir::String, local_dir::String)
    return "rsync -az --progress $(cluster_host):$(remote_dir)/ $(local_dir)/"
end

"""
    generate_collection_summary(sessions::Vector, output_dir::String,
                                batch_id::String, issue_number) -> Dict

Generate collection summary metadata.

Returns Dict with:
- batch_id: Batch identifier
- issue_number: GitLab issue number
- total_experiments: Number of experiments collected
- collection_timestamp: When collection occurred
- output_directory: Where experiments were collected to
- experiments: List of experiment names
"""
function generate_collection_summary(sessions::Vector, output_dir::String,
                                    batch_id::String, issue_number)
    experiment_names = [s["session_name"] for s in sessions]

    return Dict(
        "batch_id" => batch_id,
        "issue_number" => issue_number,
        "total_experiments" => length(sessions),
        "collection_timestamp" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
        "output_directory" => output_dir,
        "experiments" => experiment_names
    )
end

"""
    write_collection_summary(summary::Dict, output_file::String)

Write collection summary to JSON file.
"""
function write_collection_summary(summary::Dict, output_file::String)
    mkpath(dirname(output_file))

    open(output_file, "w") do f
        JSON3.pretty(f, summary)
    end
end

"""
    collect_batch(tracking_file::String, output_dir::String;
                  cluster_host::String=get(ENV, "CLUSTER_HOST", ""),
                  remote_hpc_results::String=get(ENV, "REMOTE_HPC_RESULTS", ""),
                  dry_run::Bool=false) -> Dict

Collect all experiments in a batch from HPC cluster.

# Arguments
- `tracking_file`: Path to tracking JSON file
- `output_dir`: Local directory to collect experiments to
- `cluster_host`: SSH host for cluster (requires ENV["CLUSTER_HOST"] or explicit param)
- `remote_hpc_results`: Remote hpc_results directory path (requires ENV["REMOTE_HPC_RESULTS"] or explicit param)
- `dry_run`: If true, print commands without executing (default: false)

Returns collection summary Dict.

# Required Environment Variables (if not passed explicitly)
- `CLUSTER_HOST`: SSH host string (e.g., "user@cluster.example.com")
- `REMOTE_HPC_RESULTS`: Path to hpc_results on cluster (e.g., "/home/user/hpc_results")

# Example
```julia
# Set environment variables
ENV["CLUSTER_HOST"] = "user@cluster.example.com"
ENV["REMOTE_HPC_RESULTS"] = "/home/user/hpc_results"

collect_batch("tracking/batch_20251006_115044.json",
              "collected_experiments_20251013",
              dry_run=true)
```
"""
function collect_batch(tracking_file::String, output_dir::String;
                      cluster_host::String=get(ENV, "CLUSTER_HOST", ""),
                      remote_hpc_results::String=get(ENV, "REMOTE_HPC_RESULTS", ""),
                      dry_run::Bool=false)
    # Validate required configuration
    if isempty(cluster_host)
        error("cluster_host not specified. Set ENV[\"CLUSTER_HOST\"] or pass cluster_host parameter explicitly.")
    end
    if isempty(remote_hpc_results)
        error("remote_hpc_results not specified. Set ENV[\"REMOTE_HPC_RESULTS\"] or pass remote_hpc_results parameter explicitly.")
    end
    println("🔍 Collecting batch from tracking file: $(basename(tracking_file))")

    # Read tracking data
    tracking_data = read_tracking_json(tracking_file)
    batch_id = get(tracking_data, "batch_id", "unknown")
    issue_number = get(tracking_data, "issue_number", 0)
    sessions = get_batch_sessions(tracking_file)

    println("📋 Batch ID: $batch_id")
    println("🎫 Issue: #$issue_number")
    println("📊 Total experiments: $(length(sessions))")

    # Create output directory structure
    hpc_results_out = joinpath(output_dir, "hpc_results")
    if !dry_run
        mkpath(hpc_results_out)
    end

    println("\n📥 Collecting experiments...")

    collected_sessions = []

    for (idx, session) in enumerate(sessions)
        session_name = session["session_name"]
        println("\n[$idx/$(length(sessions))] $session_name")

        remote_dir = joinpath(remote_hpc_results, session_name)
        local_dir = joinpath(hpc_results_out, session_name)

        # Build rsync command
        rsync_cmd = build_rsync_command(cluster_host, remote_dir, local_dir)

        println("   📦 rsync command: $rsync_cmd")

        if !dry_run
            # Create local directory
            mkpath(local_dir)

            # Execute rsync
            try
                run(`sh -c $rsync_cmd`)
                println("   ✅ Collected successfully")
                push!(collected_sessions, session)
            catch e
                println("   ❌ Collection failed: $e")
            end
        else
            println("   🔵 DRY RUN - would execute rsync")
            push!(collected_sessions, session)
        end
    end

    # Generate summary
    summary = generate_collection_summary(collected_sessions, output_dir, batch_id, issue_number)

    if !dry_run
        summary_file = joinpath(output_dir, "collection_summary.json")
        write_collection_summary(summary, summary_file)
        println("\n📄 Collection summary: $summary_file")
    end

    println("\n✅ Batch collection complete!")
    println("📂 Output directory: $output_dir/hpc_results")
    println("📊 Collected: $(length(collected_sessions))/$(length(sessions)) experiments")

    return summary
end

"""
    collect_cluster_experiments(cluster_host::String, results_dir::String, output_dir::String;
                                pattern::Union{String,Nothing}=nothing,
                                dry_run::Bool=false) -> Vector{String}

Collect individual experiments from cluster (legacy function for compatibility).

# Arguments
- `cluster_host`: SSH host (e.g., "user@cluster.example.com")
- `results_dir`: Remote results directory path
- `output_dir`: Local destination directory
- `pattern`: Optional regex pattern to filter experiment directories
- `dry_run`: If true, print commands without executing

Returns vector of collected experiment directory names.

# Example
```julia
collect_cluster_experiments("user@cluster.example.com",
                           "/home/user/hpc_results",
                           "collected_experiments_20251013",
                           pattern="minimal_4d_lv_test_.*")
```
"""
function collect_cluster_experiments(cluster_host::String, results_dir::String, output_dir::String;
                                    pattern::Union{String,Nothing}=nothing,
                                    dry_run::Bool=false)
    println("🔍 Listing experiments on cluster...")

    # List experiments on cluster
    list_cmd = `ssh $cluster_host "ls -1 $results_dir"`

    try
        output = read(list_cmd, String)
        all_experiments = split(strip(output), '\n')
        filter!(e -> !isempty(e), all_experiments)

        # Apply pattern filter if provided
        experiments = if pattern !== nothing
            filter(e -> occursin(Regex(pattern), e), all_experiments)
        else
            all_experiments
        end

        println("📊 Found $(length(experiments)) experiments")

        if isempty(experiments)
            println("⚠️  No experiments found matching criteria")
            return String[]
        end

        # Create output directory
        if !dry_run
            mkpath(output_dir)
        end

        collected = String[]

        for (idx, exp_name) in enumerate(experiments)
            println("\n[$idx/$(length(experiments))] $exp_name")

            remote_dir = joinpath(results_dir, exp_name)
            local_dir = joinpath(output_dir, exp_name)

            rsync_cmd = build_rsync_command(cluster_host, remote_dir, local_dir)

            println("   📦 $rsync_cmd")

            if !dry_run
                mkpath(local_dir)
                try
                    run(`sh -c $rsync_cmd`)
                    println("   ✅ Collected")
                    push!(collected, exp_name)
                catch e
                    println("   ❌ Failed: $e")
                end
            else
                println("   🔵 DRY RUN")
                push!(collected, exp_name)
            end
        end

        println("\n✅ Collection complete: $(length(collected))/$(length(experiments)) experiments")

        return collected

    catch e
        error("Failed to list experiments on cluster: $e")
    end
end

end # module ClusterCollection
