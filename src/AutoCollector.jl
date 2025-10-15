"""
AutoCollector Module - Phase 1 Implementation

Automatic collection daemon that:
1. Monitors tracking JSON files for experiment completions
2. Automatically triggers collection when experiments complete
3. Updates tracking JSON status (launching → completed/collected)
4. Manages state to prevent duplicate collections
5. Optionally cleans up tmux sessions after successful collection

See: EXPERIMENT_COLLECTION_ANALYSIS.md Phase 1

Architecture:
```
┌─────────────────────────────────────────────────────────────┐
│                    AutoCollector Daemon                      │
│                                                              │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐  │
│  │   Monitor   │───▶│   Detect     │───▶│   Collect     │  │
│  │   Tracking  │    │   Complete   │    │   & Update    │  │
│  │   Files     │    │   Sessions   │    │   Status      │  │
│  └─────────────┘    └──────────────┘    └───────────────┘  │
│         │                   │                    │          │
│         ▼                   ▼                    ▼          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              CollectorState (JSON)                   │   │
│  │  - collected_experiments: Set{String}                │   │
│  │  - collection_history: Vector{Dict}                  │   │
│  │  - last_check_time: DateTime                         │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

Usage:
```julia
using AutoCollector

# Initialize collector state
state = CollectorState("~/.globtim/autocollector_state.json")

# Single polling cycle
results = poll_and_collect!(state, config)

# Run daemon (blocking)
run_daemon(config; check_interval=300)
```
"""
module AutoCollector

using JSON3
using Dates
using Logging

# Re-export ClusterCollection functions
include("ClusterCollection.jl")
using .ClusterCollection

export CollectorState, CollectorConfig
export load_state, save_state!
export poll_and_collect!, run_daemon
export check_remote_experiment_complete, collect_experiment_remote

#=============================================================================
    State Management
=============================================================================#

"""
    CollectorState

Persistent state for the auto-collector daemon.

# Fields
- `collected_experiments`: Set of experiment session names that have been collected
- `collection_history`: Vector of collection records with metadata
- `last_check_time`: When the last polling cycle completed
- `state_file`: Path to the JSON state file
"""
mutable struct CollectorState
    collected_experiments::Set{String}
    collection_history::Vector{Dict{String, Any}}
    last_check_time::DateTime
    state_file::String
end

"""
    CollectorState(state_file::String) -> CollectorState

Create a new CollectorState. If state_file exists, load from disk; otherwise initialize empty.
"""
function CollectorState(state_file::String)
    if isfile(state_file)
        return load_state(state_file)
    else
        return CollectorState(
            Set{String}(),
            Vector{Dict{String, Any}}(),
            now(),
            state_file
        )
    end
end

"""
    load_state(state_file::String) -> CollectorState

Load collector state from JSON file.
"""
function load_state(state_file::String)
    if !isfile(state_file)
        error("State file not found: $state_file")
    end

    data = JSON3.read(read(state_file, String))

    # Convert collection_history from JSON3 objects to Dict{String, Any}
    history = Vector{Dict{String, Any}}()
    for h in data.collection_history
        entry = Dict{String, Any}()
        for (k, v) in pairs(h)
            entry[String(k)] = v
        end
        push!(history, entry)
    end

    return CollectorState(
        Set{String}(data.collected_experiments),
        history,
        DateTime(data.last_check_time),
        state_file
    )
end

"""
    save_state!(state::CollectorState)

Save collector state to JSON file.
"""
function save_state!(state::CollectorState)
    mkpath(dirname(state.state_file))

    data = Dict(
        "collected_experiments" => collect(state.collected_experiments),
        "collection_history" => state.collection_history,
        "last_check_time" => Dates.format(state.last_check_time, "yyyy-mm-ddTHH:MM:SS")
    )

    open(state.state_file, "w") do f
        JSON3.pretty(f, data)
    end

    return nothing
end

#=============================================================================
    Configuration
=============================================================================#

"""
    CollectorConfig

Configuration for the auto-collector daemon.

# Fields
- `tracking_dir`: Directory containing tracking JSON files
- `cluster_host`: SSH hostname for cluster (e.g., "scholten@r04n02")
- `cluster_results_dir`: Remote results directory path
- `output_base`: Local directory for collected results
- `cleanup_tmux`: Whether to cleanup tmux sessions after collection (default: true)
- `check_interval`: Polling interval in seconds (default: 300 = 5 minutes)
- `collect_immediately`: Collect as soon as completion detected (default: true)
"""
struct CollectorConfig
    tracking_dir::String
    cluster_host::String
    cluster_results_dir::String
    output_base::String
    cleanup_tmux::Bool
    check_interval::Int
    collect_immediately::Bool
end

"""
    CollectorConfig(; kwargs...) -> CollectorConfig

Create CollectorConfig with defaults from environment variables.

Environment variable defaults:
- `TRACKING_DIR`: \$HOME/GlobalOptim/globtimcore/experiments/lv4d_campaign_2025/tracking
- `CLUSTER_HOST`: scholten@r04n02
- `CLUSTER_RESULTS_DIR`: /home/scholten/globtimcore/hpc_results
- `OUTPUT_BASE`: \$HOME/GlobalOptim/globtimpostprocessing
"""
function CollectorConfig(;
    tracking_dir::String = get(ENV, "TRACKING_DIR",
        joinpath(homedir(), "GlobalOptim/globtimcore/experiments/lv4d_campaign_2025/tracking")),
    cluster_host::String = get(ENV, "CLUSTER_HOST", "scholten@r04n02"),
    cluster_results_dir::String = get(ENV, "CLUSTER_RESULTS_DIR",
        "/home/scholten/globtimcore/hpc_results"),
    output_base::String = get(ENV, "OUTPUT_BASE",
        joinpath(homedir(), "GlobalOptim/globtimpostprocessing")),
    cleanup_tmux::Bool = true,
    check_interval::Int = 300,
    collect_immediately::Bool = true
)
    return CollectorConfig(
        tracking_dir, cluster_host, cluster_results_dir, output_base,
        cleanup_tmux, check_interval, collect_immediately
    )
end

#=============================================================================
    Remote Experiment Checking
=============================================================================#

"""
    check_remote_experiment_complete(session_name::String, config::CollectorConfig) -> Bool

Check if an experiment on the cluster has completed.

Uses SSH to check for completion markers:
1. "✨ Experiment complete!" in experiment.log
2. results_summary.json exists

Returns true if complete, false otherwise.
"""
function check_remote_experiment_complete(session_name::String, config::CollectorConfig)
    log_path = joinpath(config.cluster_results_dir, session_name, "experiment.log")

    # Method 1: Check for completion marker in log using shell command
    completion_marker = "✨ Experiment complete!"
    check_cmd = "ssh $(config.cluster_host) 'grep -q \"$completion_marker\" \"$log_path\" 2>/dev/null'"
    log_check = try
        success(pipeline(Cmd(["sh", "-c", check_cmd]), stderr=devnull))
    catch
        false
    end

    if log_check
        return true
    end

    # Method 2: Check for results_summary.json
    results_path = joinpath(config.cluster_results_dir, session_name, "results_summary.json")
    test_cmd = "ssh $(config.cluster_host) 'test -f \"$results_path\" 2>/dev/null'"
    results_check = try
        success(pipeline(Cmd(["sh", "-c", test_cmd]), stderr=devnull))
    catch
        false
    end

    return results_check
end

"""
    collect_experiment_remote(session_name::String, output_dir::String, config::CollectorConfig) -> Bool

Collect experiment results from cluster using rsync.

Returns true if collection successful, false otherwise.
"""
function collect_experiment_remote(session_name::String, output_dir::String, config::CollectorConfig)
    remote_dir = joinpath(config.cluster_results_dir, session_name)
    local_dir = joinpath(output_dir, "hpc_results", session_name)

    mkpath(local_dir)

    # Build and execute rsync command
    rsync_cmd = `rsync -az --progress $(config.cluster_host):$(remote_dir)/ $(local_dir)/`

    try
        run(rsync_cmd)
        return true
    catch e
        @error "Rsync failed for $session_name" exception=(e, catch_backtrace())
        return false
    end
end

#=============================================================================
    Tracking JSON Updates
=============================================================================#

"""
    update_tracking_status!(tracking_file::String, session_name::String, new_status::String)

Update the status field for a session in the tracking JSON file.

# Arguments
- `tracking_file`: Path to tracking JSON file
- `session_name`: Session name to update
- `new_status`: New status value (e.g., "collected", "failed")
"""
function update_tracking_status!(tracking_file::String, session_name::String, new_status::String)
    if !isfile(tracking_file)
        error("Tracking file not found: $tracking_file")
    end

    # Read tracking data
    data = ClusterCollection.read_tracking_json(tracking_file)

    # Find and update session
    updated = false
    for session in data["sessions"]
        if session["session_name"] == session_name
            session["status"] = new_status
            session["status_updated_at"] = Dates.format(now(), "yyyy-mm-ddTHH:MM:SS")
            updated = true
            break
        end
    end

    if !updated
        @warn "Session $session_name not found in tracking file $tracking_file"
        return false
    end

    # Write back to file
    open(tracking_file, "w") do f
        JSON3.pretty(f, data)
    end

    return true
end

#=============================================================================
    Collection Logic
=============================================================================#

"""
    poll_and_collect!(state::CollectorState, config::CollectorConfig) -> Dict

Single polling cycle: check for completions and collect experiments.

Returns Dict with:
- `checked`: Number of experiments checked
- `completed`: Number of newly completed experiments found
- `collected`: Number successfully collected
- `failed`: Number that failed collection
- `experiments`: Details of each collected experiment
"""
function poll_and_collect!(state::CollectorState, config::CollectorConfig)
    @info "Starting polling cycle" timestamp=now()

    checked = 0
    completed = 0
    collected = 0
    failed = 0
    experiments = Dict{String, Any}[]

    # Find all tracking files
    if !isdir(config.tracking_dir)
        @error "Tracking directory not found" dir=config.tracking_dir
        return Dict(
            "checked" => 0,
            "completed" => 0,
            "collected" => 0,
            "failed" => 0,
            "experiments" => experiments
        )
    end

    tracking_files = filter(f -> endswith(f, ".json"), readdir(config.tracking_dir, join=true))

    @info "Found $(length(tracking_files)) tracking files"

    for tracking_file in tracking_files
        try
            process_tracking_file!(tracking_file, state, config, checked, completed, collected, failed, experiments)
        catch e
            @error "Error processing tracking file" file=tracking_file exception=(e, catch_backtrace())
        end
    end

    # Update state
    state.last_check_time = now()
    save_state!(state)

    result = Dict(
        "checked" => checked,
        "completed" => completed,
        "collected" => collected,
        "failed" => failed,
        "experiments" => experiments
    )

    @info "Polling cycle complete" result

    return result
end

"""
    process_tracking_file!(tracking_file, state, config, checked, completed, collected, failed, experiments)

Process a single tracking file for completions and collections.
"""
function process_tracking_file!(tracking_file::String, state::CollectorState, config::CollectorConfig,
                                checked::Int, completed::Int, collected::Int, failed::Int,
                                experiments::Vector{Dict{String, Any}})
    data = ClusterCollection.read_tracking_json(tracking_file)
    batch_id = get(data, "batch_id", "unknown")
    issue_number = get(data, "issue_number", 0)

    @debug "Processing tracking file" file=basename(tracking_file) batch_id issue_number

    sessions = get(data, "sessions", [])

    for session in sessions
        session_name = session["session_name"]
        current_status = get(session, "status", "unknown")

        # Skip if already collected
        if session_name in state.collected_experiments
            continue
        end

        # Skip if not in "launching" state
        if current_status != "launching"
            continue
        end

        checked += 1

        # Check if completed on cluster
        if !check_remote_experiment_complete(session_name, config)
            continue
        end

        @info "Detected completion" session=session_name batch=batch_id

        completed += 1

        # Collect immediately if configured
        if config.collect_immediately
            success = collect_single_experiment!(session_name, tracking_file, batch_id,
                                                issue_number, state, config, experiments)
            if success
                collected += 1
            else
                failed += 1
            end
        end
    end

    return nothing
end

"""
    collect_single_experiment!(session_name, tracking_file, batch_id, issue_number, state, config, experiments)

Collect a single experiment and update state.
"""
function collect_single_experiment!(session_name::String, tracking_file::String,
                                   batch_id::String, issue_number::Int,
                                   state::CollectorState, config::CollectorConfig,
                                   experiments::Vector{Dict{String, Any}})
    @info "Collecting experiment" session=session_name

    # Create output directory
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    output_dir = joinpath(config.output_base, "collected_$(session_name)_$(timestamp)")

    # Attempt collection
    collection_success = collect_experiment_remote(session_name, output_dir, config)

    if collection_success
        @info "Collection successful" session=session_name output=output_dir

        # Update tracking JSON status
        update_tracking_status!(tracking_file, session_name, "collected")

        # Update state
        push!(state.collected_experiments, session_name)

        # Add to collection history
        record = Dict(
            "session_name" => session_name,
            "batch_id" => batch_id,
            "issue_number" => issue_number,
            "collected_at" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
            "output_directory" => output_dir,
            "status" => "success"
        )
        push!(state.collection_history, record)
        push!(experiments, record)

        # Cleanup tmux if configured
        if config.cleanup_tmux
            cleanup_tmux_session(session_name)
        end

        save_state!(state)

        return true
    else
        @error "Collection failed" session=session_name

        # Update tracking JSON status to failed
        update_tracking_status!(tracking_file, session_name, "collection_failed")

        # Add to collection history as failed
        record = Dict(
            "session_name" => session_name,
            "batch_id" => batch_id,
            "issue_number" => issue_number,
            "collected_at" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
            "status" => "failed"
        )
        push!(state.collection_history, record)
        push!(experiments, record)

        save_state!(state)

        return false
    end
end

"""
    cleanup_tmux_session(session_name::String)

Kill tmux session for collected experiment.
"""
function cleanup_tmux_session(session_name::String)
    cleanup_script = joinpath(homedir(), ".globtim/scripts/cleanup_tmux.sh")

    if !isfile(cleanup_script)
        @warn "Cleanup script not found, skipping tmux cleanup" script=cleanup_script
        return
    end

    try
        run(`$cleanup_script --batch $session_name`)
        @info "Tmux session cleaned up" session=session_name
    catch e
        @warn "Tmux cleanup failed" session=session_name exception=(e, catch_backtrace())
    end
end

#=============================================================================
    Daemon Runner
=============================================================================#

"""
    run_daemon(config::CollectorConfig; state_file="~/.globtim/autocollector_state.json")

Run the auto-collector daemon (blocking loop).

# Arguments
- `config`: CollectorConfig with daemon settings
- `state_file`: Path to state file (default: ~/.globtim/autocollector_state.json)

The daemon will:
1. Load/initialize state
2. Poll tracking files every `config.check_interval` seconds
3. Collect completed experiments automatically
4. Update tracking JSON and state
5. Optionally cleanup tmux sessions
"""
function run_daemon(config::CollectorConfig; state_file=joinpath(homedir(), ".globtim/autocollector_state.json"))
    @info "Starting AutoCollector daemon" config check_interval=config.check_interval

    # Initialize state
    state = CollectorState(state_file)

    @info "Loaded state" collected_count=length(state.collected_experiments) last_check=state.last_check_time

    # Main daemon loop
    try
        while true
            poll_and_collect!(state, config)

            @info "Sleeping for $(config.check_interval) seconds..."
            sleep(config.check_interval)
        end
    catch e
        if isa(e, InterruptException)
            @info "Daemon interrupted by user, shutting down gracefully"
        else
            @error "Daemon crashed" exception=(e, catch_backtrace())
            rethrow()
        end
    end
end

end # module AutoCollector
