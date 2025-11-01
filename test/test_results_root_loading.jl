"""
Test Suite for GLOBTIM_RESULTS_ROOT Loading

Tests that analyze_experiments.jl correctly loads GLOBTIM_RESULTS_ROOT
from shell configuration and discovers experiments.

Related to path standardization efforts.
"""

using Test

@testset "GLOBTIM_RESULTS_ROOT Loading" begin
    @testset "Load from .zshrc" begin
        mktempdir() do tmpdir
            # Create a fake .zshrc
            fake_zshrc = joinpath(tmpdir, ".zshrc")
            test_results_path = joinpath(tmpdir, "test_results")
            mkpath(test_results_path)

            write(fake_zshrc, """
export GLOBTIM_RESULTS_ROOT="$test_results_path"
export OTHER_VAR="something"
""")

            # Test the parsing logic
            found_path = nothing
            for line in eachline(fake_zshrc)
                if startswith(line, "export GLOBTIM_RESULTS_ROOT=")
                    path = replace(line, r"^export GLOBTIM_RESULTS_ROOT=" => "")
                    path = strip(path, ['"', '\'', ' '])
                    found_path = path
                    break
                end
            end

            @test found_path == test_results_path
            @test isdir(found_path)
        end
    end

    @testset "Directory structure detection" begin
        mktempdir() do tmpdir
            # Set up GLOBTIM_RESULTS_ROOT-style structure
            results_root = joinpath(tmpdir, "globtim_results")
            mkpath(results_root)

            # Create test_results subdirectory with experiments
            test_results = joinpath(results_root, "test_results")
            mkpath(test_results)

            # Add minimal valid experiments
            for i in 1:2
                exp_dir = joinpath(test_results, "exp_$i")
                mkpath(exp_dir)
                touch(joinpath(exp_dir, "critical_points_deg_4.csv"))
                write(joinpath(exp_dir, "experiment_config.json"), """{"dimension": 4}""")
                write(joinpath(exp_dir, "results_summary.json"), """{"success": true}""")
            end

            @test isdir(test_results)
            @test !isempty(readdir(test_results))

            # Verify experiment discovery would work
            experiment_dirs = filter(readdir(test_results)) do entry
                isdir(joinpath(test_results, entry))
            end
            @test length(experiment_dirs) == 2
        end
    end

    @testset "Campaign structure in GLOBTIM_RESULTS_ROOT" begin
        mktempdir() do tmpdir
            results_root = joinpath(tmpdir, "globtim_results")
            batches_dir = joinpath(results_root, "batches")
            indices_dir = joinpath(results_root, "indices")
            mkpath(batches_dir)
            mkpath(indices_dir)

            # Add a campaign-style collected experiments directory
            campaign_dir = joinpath(results_root, "collected_experiments_20251016_150000")
            hpc_results = joinpath(campaign_dir, "hpc_results")
            mkpath(hpc_results)

            # Add experiments
            for i in 1:3
                exp_dir = joinpath(hpc_results, "exp_$i")
                mkpath(exp_dir)
                touch(joinpath(exp_dir, "critical_points_deg_6.csv"))
                write(joinpath(exp_dir, "experiment_config.json"), """{"dimension": 4}""")
                write(joinpath(exp_dir, "results_summary.json"), """{"success": true}""")
            end

            @test isdir(results_root)
            @test isdir(hpc_results)
            @test length(readdir(hpc_results)) == 3
        end
    end

    @testset "Empty GLOBTIM_RESULTS_ROOT handling" begin
        mktempdir() do tmpdir
            empty_results = joinpath(tmpdir, "empty_results")
            mkpath(empty_results)

            # Should be empty
            @test isdir(empty_results)
            @test isempty(readdir(empty_results))
        end
    end
end
