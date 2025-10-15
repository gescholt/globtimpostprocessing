"""
Test suite for ClusterCollection module (Phase 0 - EXPERIMENT_COLLECTION_ANALYSIS.md)

Tests cover:
- Experiment directory collection
- Individual experiment collection
- Batch collection
- Tracking JSON integration
- SSH rsync operations (mocked in tests)
"""

using Test
using JSON3
using Dates
using Logging

# Load the module under test
include("../src/ClusterCollection.jl")
using .ClusterCollection

# Test fixtures directory
const TEST_FIXTURES_DIR = joinpath(@__DIR__, "fixtures", "cluster_collection")

"""
Setup test fixtures for cluster collection tests
"""
function setup_cluster_collection_fixtures()
    mkpath(TEST_FIXTURES_DIR)

    # Create mock tracking JSON
    tracking_dir = joinpath(TEST_FIXTURES_DIR, "tracking")
    mkpath(tracking_dir)

    tracking_data = Dict(
        "batch_id" => "batch_20251006_115044",
        "issue_number" => 139,
        "created_at" => "2025-10-06T11:50:44",
        "sessions" => [
            Dict(
                "session_name" => "minimal_4d_lv_test_GN=8_domain_size_param=0.15_max_time=45.0_20251006_115101",
                "status" => "launching",
                "launch_time" => "2025-10-06T11:51:01",
                "experiment_id" => "exp_001"
            ),
            Dict(
                "session_name" => "minimal_4d_lv_test_GN=5_domain_size_param=0.1_max_time=45.0_20251006_115045",
                "status" => "launching",
                "launch_time" => "2025-10-06T11:50:45",
                "experiment_id" => "exp_002"
            )
        ]
    )

    tracking_file = joinpath(tracking_dir, "batch_20251006_115044.json")
    open(tracking_file, "w") do f
        JSON3.pretty(f, tracking_data)
    end

    # Create mock experiment result directory structure
    hpc_results_dir = joinpath(TEST_FIXTURES_DIR, "hpc_results")
    mkpath(hpc_results_dir)

    for session in tracking_data["sessions"]
        exp_dir = joinpath(hpc_results_dir, session["session_name"])
        mkpath(exp_dir)

        # Create mock experiment.log with completion marker
        open(joinpath(exp_dir, "experiment.log"), "w") do f
            write(f, "Starting experiment...\n")
            write(f, "Running computations...\n")
            write(f, "✨ Experiment complete!\n")
        end

        # Create mock results_summary.json
        results = Dict(
            "status" => "success",
            "total_critical_points" => 42,
            "total_time" => 123.45
        )
        open(joinpath(exp_dir, "results_summary.json"), "w") do f
            JSON3.pretty(f, results)
        end

        # Create mock experiment_params.json
        params = Dict(
            "GN" => 8,
            "domain_size_param" => 0.15,
            "max_time" => 45.0
        )
        open(joinpath(exp_dir, "experiment_params.json"), "w") do f
            JSON3.pretty(f, params)
        end
    end

    return TEST_FIXTURES_DIR
end

"""
Cleanup test fixtures
"""
function cleanup_cluster_collection_fixtures()
    if isdir(TEST_FIXTURES_DIR)
        rm(TEST_FIXTURES_DIR, recursive=true, force=true)
    end
end

@testset "ClusterCollection Module" begin

    # Setup fixtures
    fixtures_dir = setup_cluster_collection_fixtures()

    try
        @testset "Tracking JSON Reading" begin
            tracking_file = joinpath(fixtures_dir, "tracking", "batch_20251006_115044.json")

            @test isfile(tracking_file)

            tracking_data = ClusterCollection.read_tracking_json(tracking_file)

            @test haskey(tracking_data, "batch_id")
            @test tracking_data["batch_id"] == "batch_20251006_115044"
            @test haskey(tracking_data, "sessions")
            @test length(tracking_data["sessions"]) == 2
            @test tracking_data["issue_number"] == 139
        end

        @testset "Experiment Completion Detection" begin
            exp_dir = joinpath(fixtures_dir, "hpc_results",
                              "minimal_4d_lv_test_GN=8_domain_size_param=0.15_max_time=45.0_20251006_115101")

            @test isdir(exp_dir)

            # Test completion detection by log file
            is_complete = ClusterCollection.check_experiment_complete(exp_dir)
            @test is_complete == true

            # Test with incomplete experiment (no completion marker)
            incomplete_dir = joinpath(fixtures_dir, "hpc_results", "incomplete_exp")
            mkpath(incomplete_dir)
            open(joinpath(incomplete_dir, "experiment.log"), "w") do f
                write(f, "Starting experiment...\n")
                write(f, "Running...\n")
            end

            is_complete_incomplete = ClusterCollection.check_experiment_complete(incomplete_dir)
            @test is_complete_incomplete == false

            # Test with results_summary.json as alternative marker
            results_only_dir = joinpath(fixtures_dir, "hpc_results", "results_only_exp")
            mkpath(results_only_dir)
            open(joinpath(results_only_dir, "results_summary.json"), "w") do f
                JSON3.pretty(f, Dict("status" => "success"))
            end

            is_complete_results = ClusterCollection.check_experiment_complete(results_only_dir)
            @test is_complete_results == true
        end

        @testset "Batch Session Extraction" begin
            tracking_file = joinpath(fixtures_dir, "tracking", "batch_20251006_115044.json")

            sessions = ClusterCollection.get_batch_sessions(tracking_file)

            @test length(sessions) == 2
            @test sessions[1]["session_name"] == "minimal_4d_lv_test_GN=8_domain_size_param=0.15_max_time=45.0_20251006_115101"
            @test sessions[1]["status"] == "launching"
        end

        @testset "Collection Target Resolution" begin
            # Test by batch ID
            tracking_dir = joinpath(fixtures_dir, "tracking")
            batch_id = "batch_20251006_115044"

            tracking_file = ClusterCollection.find_tracking_file(tracking_dir, batch_id)
            @test tracking_file !== nothing
            @test isfile(tracking_file)

            # Test by issue number
            tracking_file_by_issue = ClusterCollection.find_tracking_file(tracking_dir, "139")
            @test tracking_file_by_issue !== nothing
            @test tracking_file_by_issue == tracking_file

            # Test not found
            missing_file = ClusterCollection.find_tracking_file(tracking_dir, "nonexistent")
            @test missing_file === nothing
        end

        @testset "Rsync Command Generation" begin
            cluster_host = "scholten@r04n02"
            remote_dir = "/home/scholten/globtimcore/hpc_results/experiment_001"
            local_dir = "/tmp/collected/experiment_001"

            cmd = ClusterCollection.build_rsync_command(cluster_host, remote_dir, local_dir)

            @test occursin("rsync", cmd)
            @test occursin("-az", cmd)  # Archive + compress
            @test occursin("--progress", cmd)
            @test occursin(cluster_host, cmd)
            @test occursin(remote_dir, cmd)
            @test occursin(local_dir, cmd)
        end

        @testset "Collection Summary Generation" begin
            sessions = [
                Dict("session_name" => "exp_001", "status" => "launching"),
                Dict("session_name" => "exp_002", "status" => "launching")
            ]

            output_dir = joinpath(fixtures_dir, "test_output")
            mkpath(output_dir)

            summary = ClusterCollection.generate_collection_summary(
                sessions,
                output_dir,
                "batch_20251006_115044",
                139
            )

            @test haskey(summary, "batch_id")
            @test haskey(summary, "issue_number")
            @test haskey(summary, "total_experiments")
            @test summary["total_experiments"] == 2
            @test haskey(summary, "collection_timestamp")
            @test haskey(summary, "output_directory")
        end

        @testset "Mock Batch Collection (without SSH)" begin
            # This test simulates the collection process without actually running SSH
            tracking_file = joinpath(fixtures_dir, "tracking", "batch_20251006_115044.json")
            output_dir = joinpath(fixtures_dir, "test_collection_output")

            # Simulate collection by copying local fixtures
            tracking_data = ClusterCollection.read_tracking_json(tracking_file)
            sessions = tracking_data["sessions"]

            mkpath(output_dir)
            hpc_results_out = joinpath(output_dir, "hpc_results")
            mkpath(hpc_results_out)

            # Copy experiments locally (simulating rsync)
            for session in sessions
                src_dir = joinpath(fixtures_dir, "hpc_results", session["session_name"])
                dst_dir = joinpath(hpc_results_out, session["session_name"])
                cp(src_dir, dst_dir)
            end

            # Verify collection structure
            @test isdir(hpc_results_out)
            @test length(readdir(hpc_results_out)) == 2

            # Verify files were copied
            for session in sessions
                exp_dir = joinpath(hpc_results_out, session["session_name"])
                @test isdir(exp_dir)
                @test isfile(joinpath(exp_dir, "experiment.log"))
                @test isfile(joinpath(exp_dir, "results_summary.json"))
                @test isfile(joinpath(exp_dir, "experiment_params.json"))
            end
        end

        @testset "Error Handling" begin
            # Test with nonexistent tracking file
            @test_throws Exception ClusterCollection.read_tracking_json("/nonexistent/file.json")

            # Test with invalid JSON
            invalid_json = joinpath(fixtures_dir, "invalid.json")
            open(invalid_json, "w") do f
                write(f, "{ invalid json }")
            end
            @test_throws Exception ClusterCollection.read_tracking_json(invalid_json)

            # Test with nonexistent experiment directory
            @test ClusterCollection.check_experiment_complete("/nonexistent/dir") == false
        end

    finally
        # Cleanup
        cleanup_cluster_collection_fixtures()
    end
end

@testset "Integration: Full Collection Workflow" begin
    # This test verifies the complete workflow:
    # 1. Find tracking file
    # 2. Read sessions
    # 3. Check completion
    # 4. Collect (mocked)
    # 5. Generate summary

    fixtures_dir = setup_cluster_collection_fixtures()

    try
        tracking_dir = joinpath(fixtures_dir, "tracking")
        batch_id = "batch_20251006_115044"
        output_dir = joinpath(fixtures_dir, "integration_test_output")

        # Step 1: Find tracking file
        tracking_file = ClusterCollection.find_tracking_file(tracking_dir, batch_id)
        @test tracking_file !== nothing

        # Step 2: Read sessions
        tracking_data = ClusterCollection.read_tracking_json(tracking_file)
        sessions = tracking_data["sessions"]
        @test length(sessions) == 2

        # Step 3: Check completion (simulated - local files)
        completed_sessions = filter(sessions) do session
            exp_dir = joinpath(fixtures_dir, "hpc_results", session["session_name"])
            ClusterCollection.check_experiment_complete(exp_dir)
        end
        @test length(completed_sessions) == 2

        # Step 4: Collect (simulated)
        mkpath(output_dir)
        hpc_results_out = joinpath(output_dir, "hpc_results")
        mkpath(hpc_results_out)

        for session in completed_sessions
            src_dir = joinpath(fixtures_dir, "hpc_results", session["session_name"])
            dst_dir = joinpath(hpc_results_out, session["session_name"])
            cp(src_dir, dst_dir)
        end

        # Step 5: Generate summary
        summary = ClusterCollection.generate_collection_summary(
            completed_sessions,
            output_dir,
            batch_id,
            tracking_data["issue_number"]
        )

        @test summary["total_experiments"] == 2
        @test summary["batch_id"] == batch_id

        # Verify summary file was created
        summary_file = joinpath(output_dir, "collection_summary.json")
        ClusterCollection.write_collection_summary(summary, summary_file)
        @test isfile(summary_file)

        # Verify we can read it back
        summary_read = JSON3.read(read(summary_file, String), Dict)
        @test summary_read["batch_id"] == batch_id

    finally
        cleanup_cluster_collection_fixtures()
    end
end
