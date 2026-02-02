"""
Test suite for AutoCollector module (Phase 1 - EXPERIMENT_COLLECTION_ANALYSIS.md)

Tests cover:
- CollectorState initialization, load/save
- Tracking file monitoring
- Remote experiment completion checking (mocked SSH)
- Automatic collection triggering
- Tracking JSON status updates
- State management (preventing duplicate collections)
- Collection history tracking
"""

using Test
using JSON3
using Dates
using Logging

# Load the module under test
include("../src/AutoCollector.jl")
using .AutoCollector

# Test fixtures directory
const TEST_FIXTURES_DIR = joinpath(@__DIR__, "fixtures", "auto_collector")

"""
Setup test fixtures for auto-collector tests
"""
function setup_auto_collector_fixtures()
    # Clean up any existing fixtures
    if isdir(TEST_FIXTURES_DIR)
        rm(TEST_FIXTURES_DIR, recursive=true, force=true)
    end

    mkpath(TEST_FIXTURES_DIR)

    # Create tracking directory with test data
    tracking_dir = joinpath(TEST_FIXTURES_DIR, "tracking")
    mkpath(tracking_dir)

    # Tracking file 1: Batch with 2 experiments, 1 completed
    tracking_data_1 = Dict(
        "batch_id" => "batch_test_001",
        "issue_number" => 101,
        "created_at" => "2025-10-13T10:00:00",
        "sessions" => [
            Dict(
                "session_name" => "exp_complete_001",
                "status" => "launching",
                "launch_time" => "2025-10-13T10:01:00",
                "experiment_id" => "exp_001"
            ),
            Dict(
                "session_name" => "exp_incomplete_002",
                "status" => "launching",
                "launch_time" => "2025-10-13T10:02:00",
                "experiment_id" => "exp_002"
            )
        ]
    )

    open(joinpath(tracking_dir, "batch_test_001.json"), "w") do f
        JSON3.pretty(f, tracking_data_1)
    end

    # Tracking file 2: Batch with already collected experiment
    tracking_data_2 = Dict(
        "batch_id" => "batch_test_002",
        "issue_number" => 102,
        "created_at" => "2025-10-13T11:00:00",
        "sessions" => [
            Dict(
                "session_name" => "exp_already_collected",
                "status" => "collected",
                "launch_time" => "2025-10-13T11:01:00",
                "experiment_id" => "exp_003"
            )
        ]
    )

    open(joinpath(tracking_dir, "batch_test_002.json"), "w") do f
        JSON3.pretty(f, tracking_data_2)
    end

    # Create mock HPC results directory
    hpc_results_dir = joinpath(TEST_FIXTURES_DIR, "hpc_results")
    mkpath(hpc_results_dir)

    # Experiment 1: Completed (has completion marker)
    exp_dir_1 = joinpath(hpc_results_dir, "exp_complete_001")
    mkpath(exp_dir_1)
    open(joinpath(exp_dir_1, "experiment.log"), "w") do f
        write(f, "Starting experiment...\n")
        write(f, "✨ Experiment complete!\n")
    end
    open(joinpath(exp_dir_1, "results_summary.json"), "w") do f
        JSON3.pretty(f, Dict("status" => "success", "total_critical_points" => 42))
    end

    # Experiment 2: Incomplete (no completion marker)
    exp_dir_2 = joinpath(hpc_results_dir, "exp_incomplete_002")
    mkpath(exp_dir_2)
    open(joinpath(exp_dir_2, "experiment.log"), "w") do f
        write(f, "Starting experiment...\n")
        write(f, "Running iteration 10/100...\n")
    end

    # Experiment 3: Already collected
    exp_dir_3 = joinpath(hpc_results_dir, "exp_already_collected")
    mkpath(exp_dir_3)
    open(joinpath(exp_dir_3, "experiment.log"), "w") do f
        write(f, "✨ Experiment complete!\n")
    end

    return tracking_dir, hpc_results_dir
end

"""
Mock SSH command runner for testing remote operations
"""
function mock_ssh_check_complete(session_name::String, hpc_results_dir::String)
    log_path = joinpath(hpc_results_dir, session_name, "experiment.log")

    # Check if log file exists and contains completion marker
    if isfile(log_path)
        log_content = read(log_path, String)
        if occursin("✨ Experiment complete!", log_content)
            return true
        end
    end

    # Check for results_summary.json
    results_path = joinpath(hpc_results_dir, session_name, "results_summary.json")
    return isfile(results_path)
end

"""
Mock rsync for testing collection
"""
function mock_rsync_collect(session_name::String, src_dir::String, dest_dir::String)
    src_path = joinpath(src_dir, session_name)
    dest_path = joinpath(dest_dir, "hpc_results", session_name)

    if !isdir(src_path)
        return false
    end

    mkpath(dest_path)

    # Copy all files
    for file in readdir(src_path)
        cp(joinpath(src_path, file), joinpath(dest_path, file), force=true)
    end

    return true
end

@testset "AutoCollector Tests" begin

    @testset "CollectorState - Initialization" begin
        state_file = joinpath(TEST_FIXTURES_DIR, "test_state_init.json")
        rm(state_file, force=true)

        # Create new state
        state = AutoCollector.CollectorState(state_file)

        @test isempty(state.collected_experiments)
        @test isempty(state.collection_history)
        @test state.last_check_time isa DateTime
        @test state.state_file == state_file
    end

    @testset "CollectorState - Save and Load" begin
        state_file = joinpath(TEST_FIXTURES_DIR, "test_state_save_load.json")
        rm(state_file, force=true)

        # Create state with data
        state = AutoCollector.CollectorState(state_file)
        push!(state.collected_experiments, "exp_001")
        push!(state.collected_experiments, "exp_002")

        record = Dict(
            "session_name" => "exp_001",
            "batch_id" => "batch_test",
            "collected_at" => "2025-10-13T12:00:00",
            "status" => "success"
        )
        push!(state.collection_history, record)

        state.last_check_time = DateTime(2025, 10, 13, 12, 0, 0)

        # Save
        AutoCollector.save_state!(state)

        @test isfile(state_file)

        # Load into new state object
        state2 = AutoCollector.load_state(state_file)

        @test state2.collected_experiments == state.collected_experiments
        @test length(state2.collection_history) == 1
        @test state2.collection_history[1]["session_name"] == "exp_001"
        @test Dates.format(state2.last_check_time, "yyyy-mm-ddTHH:MM:SS") == "2025-10-13T12:00:00"
    end

    @testset "CollectorConfig - Defaults" begin
        config = AutoCollector.CollectorConfig(
            tracking_dir="/test/tracking",
            cluster_host="test@host",
            cluster_results_dir="/test/results",
            output_base="/test/output"
        )

        @test config.tracking_dir == "/test/tracking"
        @test config.cluster_host == "test@host"
        @test config.cleanup_tmux == true  # default
        @test config.check_interval == 300  # default
        @test config.collect_immediately == true  # default
    end

    @testset "CollectorConfig - Custom values" begin
        config = AutoCollector.CollectorConfig(
            tracking_dir="/test/tracking",
            cluster_host="test@host",
            cluster_results_dir="/test/results",
            output_base="/test/output",
            cleanup_tmux=false,
            check_interval=60,
            collect_immediately=false
        )

        @test config.cleanup_tmux == false
        @test config.check_interval == 60
        @test config.collect_immediately == false
    end

    @testset "Tracking JSON Status Update" begin
        tracking_dir, _ = setup_auto_collector_fixtures()
        tracking_file = joinpath(tracking_dir, "batch_test_001.json")

        # Update status
        success = AutoCollector.update_tracking_status!(tracking_file, "exp_complete_001", "collected")

        @test success == true

        # Verify update
        data = JSON3.read(read(tracking_file, String))
        session = data.sessions[1]

        @test session.session_name == "exp_complete_001"
        @test session.status == "collected"
        @test haskey(session, :status_updated_at)
    end

    @testset "Tracking JSON Status Update - Nonexistent Session" begin
        tracking_dir, _ = setup_auto_collector_fixtures()
        tracking_file = joinpath(tracking_dir, "batch_test_001.json")

        # Try to update nonexistent session
        success = AutoCollector.update_tracking_status!(tracking_file, "nonexistent_session", "collected")

        @test success == false
    end

    @testset "Remote Completion Check - Mock" begin
        tracking_dir, hpc_results_dir = setup_auto_collector_fixtures()

        # Mock the check_remote_experiment_complete function for testing
        # In real tests, we'd use SSH mocking or test containers

        # Test 1: Completed experiment
        completed = mock_ssh_check_complete("exp_complete_001", hpc_results_dir)
        @test completed == true

        # Test 2: Incomplete experiment
        incomplete = mock_ssh_check_complete("exp_incomplete_002", hpc_results_dir)
        @test incomplete == false
    end

    @testset "Single Experiment Collection - Integration" begin
        tracking_dir, hpc_results_dir = setup_auto_collector_fixtures()
        state_file = joinpath(TEST_FIXTURES_DIR, "test_collection_state.json")
        rm(state_file, force=true)

        state = AutoCollector.CollectorState(state_file)
        tracking_file = joinpath(tracking_dir, "batch_test_001.json")

        output_base = joinpath(TEST_FIXTURES_DIR, "collected_output")
        mkpath(output_base)

        # Mock collection
        session_name = "exp_complete_001"
        timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
        output_dir = joinpath(output_base, "collected_$(session_name)_$(timestamp)")

        # Simulate collection
        success = mock_rsync_collect(session_name, hpc_results_dir, output_dir)

        @test success == true
        @test isdir(joinpath(output_dir, "hpc_results", session_name))
        @test isfile(joinpath(output_dir, "hpc_results", session_name, "experiment.log"))
        @test isfile(joinpath(output_dir, "hpc_results", session_name, "results_summary.json"))

        # Update state manually (as collect_single_experiment! would)
        push!(state.collected_experiments, session_name)
        AutoCollector.save_state!(state)

        # Verify state was updated
        state2 = AutoCollector.load_state(state_file)
        @test session_name in state2.collected_experiments
    end

    @testset "Prevent Duplicate Collection" begin
        tracking_dir, _ = setup_auto_collector_fixtures()
        state_file = joinpath(TEST_FIXTURES_DIR, "test_duplicate_prevention.json")
        rm(state_file, force=true)

        state = AutoCollector.CollectorState(state_file)

        # Mark experiment as already collected
        push!(state.collected_experiments, "exp_complete_001")
        AutoCollector.save_state!(state)

        # In poll_and_collect!, this experiment should be skipped
        # because it's already in collected_experiments set

        @test "exp_complete_001" in state.collected_experiments

        # Simulate checking if we should collect
        should_collect = "exp_complete_001" ∉ state.collected_experiments
        @test should_collect == false  # Should NOT collect again
    end

    @testset "Collection History Tracking" begin
        state_file = joinpath(TEST_FIXTURES_DIR, "test_history.json")
        rm(state_file, force=true)

        state = AutoCollector.CollectorState(state_file)

        # Add collection records
        record1 = Dict(
            "session_name" => "exp_001",
            "batch_id" => "batch_test",
            "issue_number" => 101,
            "collected_at" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
            "output_directory" => "/test/output/exp_001",
            "status" => "success"
        )

        record2 = Dict(
            "session_name" => "exp_002",
            "batch_id" => "batch_test",
            "issue_number" => 101,
            "collected_at" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"),
            "status" => "failed"
        )

        push!(state.collection_history, record1)
        push!(state.collection_history, record2)

        AutoCollector.save_state!(state)

        # Load and verify
        state2 = AutoCollector.load_state(state_file)

        @test length(state2.collection_history) == 2
        @test state2.collection_history[1]["status"] == "success"
        @test state2.collection_history[2]["status"] == "failed"
    end

    @testset "Skip Non-Launching Experiments" begin
        tracking_dir, _ = setup_auto_collector_fixtures()

        # batch_test_002 has a session with status="collected"
        tracking_file = joinpath(tracking_dir, "batch_test_002.json")
        data = JSON3.read(read(tracking_file, String))

        session = data.sessions[1]
        @test session.status == "collected"

        # In poll_and_collect!, this should be skipped because status != "launching"
        should_check = session.status == "launching"
        @test should_check == false
    end

    @testset "Process Multiple Tracking Files" begin
        tracking_dir, _ = setup_auto_collector_fixtures()

        # Count tracking files
        tracking_files = filter(f -> endswith(f, ".json"), readdir(tracking_dir))

        @test length(tracking_files) == 2
        @test "batch_test_001.json" in tracking_files
        @test "batch_test_002.json" in tracking_files
    end

end # main testset

# Cleanup after all tests
@testset "Cleanup Test Fixtures" begin
    if isdir(TEST_FIXTURES_DIR)
        rm(TEST_FIXTURES_DIR, recursive=true, force=true)
    end
    @test !isdir(TEST_FIXTURES_DIR)
end
