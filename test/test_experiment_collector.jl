"""
Test Suite for ExperimentCollector Module

Tests hierarchical and flat experiment discovery, validation, and grouping.

Related Issues:
- globaloptim/globtimpostprocessing#9: Modularize and test experiment collection
- globaloptim/globtimpostprocessing#10: Support hierarchical experiment structure
- globaloptim/globtimcore#174: Hierarchical experiment output structure
"""

using Test
using GlobtimPostProcessing
using GlobtimPostProcessing.ExperimentCollector
using GlobtimPostProcessing.ExperimentCollector: StructureType, Flat, Hierarchical, Unknown,
                                                  detect_directory_structure,
                                                  discover_experiments_hierarchical,
                                                  load_experiment_config,
                                                  group_by_config_param,
                                                  group_by_degree_range,
                                                  count_experiments
using JSON3

# Helper function to create mock experiment directory
function create_mock_experiment(path::String;
                                 has_csv::Bool=true,
                                 has_config::Bool=true,
                                 has_results::Bool=true,
                                 config_content::Union{Dict, Nothing}=nothing)
    mkpath(path)

    if has_csv
        touch(joinpath(path, "critical_points_deg_8.csv"))
    end

    if has_config
        config = isnothing(config_content) ? Dict(
            "objective_name" => "test_objective",
            "grid_nodes" => 8,
            "domain_size_param" => 0.1,
            "min_degree" => 4,
            "max_degree" => 12
        ) : config_content

        open(joinpath(path, "experiment_config.json"), "w") do io
            JSON3.write(io, config)
        end
    end

    if has_results
        results = Dict("status" => "completed", "num_critical_points" => 10)
        open(joinpath(path, "results_summary.json"), "w") do io
            JSON3.write(io, results)
        end
    end
end

@testset "ExperimentCollector" begin

    @testset "validate_experiment" begin
        @testset "Valid experiment with CSV files" begin
            # Create temporary experiment directory
            mktempdir() do tmpdir
                exp_dir = joinpath(tmpdir, "test_exp")
                mkdir(exp_dir)

                # Create minimal valid experiment structure
                touch(joinpath(exp_dir, "critical_points_deg_4.csv"))
                write(joinpath(exp_dir, "experiment_config.json"), """{"dimension": 4}""")
                write(joinpath(exp_dir, "results_summary.json"), """{"success": true}""")

                result = validate_experiment(exp_dir)
                @test result.is_valid == true
                @test result.has_csv == true
                @test result.has_config == true
                @test result.has_results == true
            end
        end

        @testset "Invalid experiment - empty directory" begin
            mktempdir() do tmpdir
                exp_dir = joinpath(tmpdir, "empty_exp")
                mkdir(exp_dir)

                result = validate_experiment(exp_dir)
                @test result.is_valid == false
                @test result.has_csv == false
            end
        end

        @testset "Invalid experiment - missing results" begin
            mktempdir() do tmpdir
                exp_dir = joinpath(tmpdir, "incomplete_exp")
                mkdir(exp_dir)

                touch(joinpath(exp_dir, "critical_points_deg_4.csv"))
                write(joinpath(exp_dir, "experiment_config.json"), """{"dimension": 4}""")
                # Missing results_summary.json

                result = validate_experiment(exp_dir)
                @test result.is_valid == false
                @test result.has_csv == true
                @test result.has_config == true
                @test result.has_results == false
            end
        end

        @testset "Invalid experiment - not a directory" begin
            mktempdir() do tmpdir
                fake_exp = joinpath(tmpdir, "not_a_dir.txt")
                touch(fake_exp)

                result = validate_experiment(fake_exp)
                @test result.is_valid == false
            end
        end
    end

    @testset "discover_experiments" begin
        @testset "Flat structure - experiments directly in path" begin
            mktempdir() do tmpdir
                # Create 3 valid experiments
                for i in 1:3
                    exp_dir = joinpath(tmpdir, "exp_$i")
                    mkdir(exp_dir)
                    touch(joinpath(exp_dir, "critical_points_deg_4.csv"))
                    write(joinpath(exp_dir, "experiment_config.json"), """{"dimension": 4}""")
                    write(joinpath(exp_dir, "results_summary.json"), """{"success": true}""")
                end

                experiments = discover_experiments(tmpdir)
                @test length(experiments) == 3
                @test all(exp -> exp.is_valid, experiments)
            end
        end

        @testset "Mixed valid and invalid experiments" begin
            mktempdir() do tmpdir
                # Valid experiment
                exp1 = joinpath(tmpdir, "exp_valid")
                mkdir(exp1)
                touch(joinpath(exp1, "critical_points_deg_4.csv"))
                write(joinpath(exp1, "experiment_config.json"), """{"dimension": 4}""")
                write(joinpath(exp1, "results_summary.json"), """{"success": true}""")

                # Invalid experiment (has CSV but missing other files)
                exp2 = joinpath(tmpdir, "exp_invalid")
                mkdir(exp2)
                touch(joinpath(exp2, "critical_points_deg_4.csv"))
                # Missing config and results - makes it invalid

                # Not an experiment directory (random file)
                touch(joinpath(tmpdir, "readme.txt"))

                experiments = discover_experiments(tmpdir)
                @test length(experiments) == 2  # Both found, but one invalid
                @test count(exp -> exp.is_valid, experiments) == 1
            end
        end

        @testset "Empty directory" begin
            mktempdir() do tmpdir
                experiments = discover_experiments(tmpdir)
                @test length(experiments) == 0
            end
        end
    end

    @testset "discover_campaigns" begin
        @testset "Single campaign with hpc_results structure" begin
            mktempdir() do tmpdir
                # Create campaign structure
                campaign_dir = joinpath(tmpdir, "collected_experiments_20251015_120000")
                hpc_results = joinpath(campaign_dir, "hpc_results")
                mkpath(hpc_results)

                # Add 2 experiments (minimum for campaign)
                for i in 1:2
                    exp_dir = joinpath(hpc_results, "exp_$i")
                    mkdir(exp_dir)
                    touch(joinpath(exp_dir, "critical_points_deg_4.csv"))
                    write(joinpath(exp_dir, "experiment_config.json"), """{"dimension": 4}""")
                    write(joinpath(exp_dir, "results_summary.json"), """{"success": true}""")
                end

                campaigns = discover_campaigns(tmpdir)
                @test length(campaigns) == 1
                @test campaigns[1].path == hpc_results
                @test campaigns[1].num_experiments == 2
            end
        end

        @testset "Multiple campaigns" begin
            mktempdir() do tmpdir
                # Create 2 campaign structures
                for j in 1:2
                    campaign_dir = joinpath(tmpdir, "campaign_$j")
                    hpc_results = joinpath(campaign_dir, "hpc_results")
                    mkpath(hpc_results)

                    # Add experiments
                    for i in 1:3
                        exp_dir = joinpath(hpc_results, "exp_$(j)_$i")
                        mkdir(exp_dir)
                        touch(joinpath(exp_dir, "critical_points_deg_4.csv"))
                        write(joinpath(exp_dir, "experiment_config.json"), """{"dimension": 4}""")
                        write(joinpath(exp_dir, "results_summary.json"), """{"success": true}""")
                    end
                end

                campaigns = discover_campaigns(tmpdir)
                @test length(campaigns) == 2
                @test all(c -> c.num_experiments >= 2, campaigns)
            end
        end

        @testset "Filter out single-experiment 'campaigns'" begin
            mktempdir() do tmpdir
                # Create structure with only 1 experiment (should be filtered)
                campaign_dir = joinpath(tmpdir, "single_exp_campaign")
                hpc_results = joinpath(campaign_dir, "hpc_results")
                mkpath(hpc_results)

                exp_dir = joinpath(hpc_results, "exp_1")
                mkdir(exp_dir)
                touch(joinpath(exp_dir, "critical_points_deg_4.csv"))
                write(joinpath(exp_dir, "experiment_config.json"), """{"dimension": 4}""")
                write(joinpath(exp_dir, "results_summary.json"), """{"success": true}""")

                campaigns = discover_campaigns(tmpdir)
                @test length(campaigns) == 0  # Filtered out
            end
        end

        @testset "Sorted by modification time" begin
            mktempdir() do tmpdir
                # Create 2 campaigns with different modification times
                for (j, delay) in enumerate([0, 2])
                    campaign_dir = joinpath(tmpdir, "campaign_$j")
                    hpc_results = joinpath(campaign_dir, "hpc_results")
                    mkpath(hpc_results)

                    for i in 1:2
                        exp_dir = joinpath(hpc_results, "exp_$i")
                        mkdir(exp_dir)
                        touch(joinpath(exp_dir, "critical_points_deg_4.csv"))
                        write(joinpath(exp_dir, "experiment_config.json"), """{"dimension": 4}""")
                        write(joinpath(exp_dir, "results_summary.json"), """{"success": true}""")
                    end

                    sleep(delay)  # Ensure different modification times
                end

                campaigns = discover_campaigns(tmpdir)
                @test length(campaigns) == 2
                # Newest first
                @test campaigns[1].mtime > campaigns[2].mtime
            end
        end
    end

    @testset "Integration: Nested campaign discovery" begin
        mktempdir() do tmpdir
            # Create realistic structure: experiments/cluster/system/collection/hpc_results/experiments
            system_path = joinpath(tmpdir, "cluster", "lotka_volterra_4d")
            mkpath(system_path)

            # Add a collection with campaign
            collection = joinpath(system_path, "collected_experiments_20251015_120000")
            hpc_results = joinpath(collection, "hpc_results")
            mkpath(hpc_results)

            for i in 1:3
                exp_dir = joinpath(hpc_results, "lv4d_exp_$i")
                mkdir(exp_dir)
                touch(joinpath(exp_dir, "critical_points_deg_6.csv"))
                write(joinpath(exp_dir, "experiment_config.json"), """{"dimension": 4, "function": "lotka_volterra_4d"}""")
                write(joinpath(exp_dir, "results_summary.json"), """{"success": true, "total_cp": 10}""")
            end

            campaigns = discover_campaigns(tmpdir)
            @test length(campaigns) >= 1
            @test any(c -> c.num_experiments == 3, campaigns)
        end
    end

    # ============================================================================
    # New tests for hierarchical structure support (Issues #9, #10, globtimcore#174)
    # ============================================================================

    @testset "detect_directory_structure" begin
        @testset "Flat structure detection" begin
            mktempdir() do tmpdir
                # Create flat structure
                create_mock_experiment(joinpath(tmpdir, "exp1_20251014_100000"))
                create_mock_experiment(joinpath(tmpdir, "exp2_20251014_110000"))

                @test detect_directory_structure(tmpdir) == Flat
            end
        end

        @testset "Hierarchical structure detection" begin
            mktempdir() do tmpdir
                # Create hierarchical structure
                obj1_path = joinpath(tmpdir, "lotka_volterra_4d")
                mkpath(obj1_path)
                create_mock_experiment(joinpath(obj1_path, "exp_20251014_100000"))
                create_mock_experiment(joinpath(obj1_path, "exp_20251014_110000"))

                obj2_path = joinpath(tmpdir, "extended_brusselator")
                mkpath(obj2_path)
                create_mock_experiment(joinpath(obj2_path, "exp_20251014_120000"))

                @test detect_directory_structure(tmpdir) == Hierarchical
            end
        end

        @testset "Empty/unknown structure" begin
            mktempdir() do tmpdir
                @test detect_directory_structure(tmpdir) == Unknown
            end
        end
    end

    @testset "discover_experiments_hierarchical" begin
        @testset "Basic hierarchical discovery" begin
            mktempdir() do tmpdir
                # Create hierarchical structure
                lv4d_path = joinpath(tmpdir, "lotka_volterra_4d")
                mkpath(lv4d_path)
                create_mock_experiment(joinpath(lv4d_path, "exp_20251014_100000"), config_content=Dict(
                    "objective_name" => "lotka_volterra_4d",
                    "grid_nodes" => 8
                ))
                create_mock_experiment(joinpath(lv4d_path, "exp_20251014_110000"), config_content=Dict(
                    "objective_name" => "lotka_volterra_4d",
                    "grid_nodes" => 16
                ))

                bruss_path = joinpath(tmpdir, "extended_brusselator")
                mkpath(bruss_path)
                create_mock_experiment(joinpath(bruss_path, "exp_20251014_120000"), config_content=Dict(
                    "objective_name" => "extended_brusselator",
                    "grid_nodes" => 8
                ))

                experiments_by_obj = discover_experiments_hierarchical(tmpdir)

                @test length(experiments_by_obj) == 2
                @test haskey(experiments_by_obj, "lotka_volterra_4d")
                @test haskey(experiments_by_obj, "extended_brusselator")

                lv4d_exps = experiments_by_obj["lotka_volterra_4d"]
                @test length(lv4d_exps) == 2
                @test all(exp -> exp.objective == "lotka_volterra_4d", lv4d_exps)
                @test all(exp -> exp.is_valid, lv4d_exps)

                bruss_exps = experiments_by_obj["extended_brusselator"]
                @test length(bruss_exps) == 1
                @test bruss_exps[1].objective == "extended_brusselator"
            end
        end

        @testset "Experiments sorted chronologically" begin
            mktempdir() do tmpdir
                obj_path = joinpath(tmpdir, "test_obj")
                mkpath(obj_path)

                # Create experiments with timestamps in non-sorted order
                create_mock_experiment(joinpath(obj_path, "exp_20251014_150000"))
                create_mock_experiment(joinpath(obj_path, "exp_20251014_100000"))
                create_mock_experiment(joinpath(obj_path, "exp_20251014_130000"))

                experiments_by_obj = discover_experiments_hierarchical(tmpdir)
                exps = experiments_by_obj["test_obj"]

                @test length(exps) == 3
                # Should be sorted by name (which is timestamp-based)
                @test exps[1].name < exps[2].name < exps[3].name
                @test exps[1].name == "exp_20251014_100000"
                @test exps[3].name == "exp_20251014_150000"
            end
        end
    end

    @testset "discover_experiments - Auto-detection" begin
        @testset "Auto-detect flat" begin
            mktempdir() do tmpdir
                create_mock_experiment(joinpath(tmpdir, "exp1"))
                create_mock_experiment(joinpath(tmpdir, "exp2"))

                result = discover_experiments(tmpdir)
                @test result isa Vector{ExperimentInfo}
                @test length(result) == 2
            end
        end

        @testset "Auto-detect hierarchical" begin
            mktempdir() do tmpdir
                obj_path = joinpath(tmpdir, "test_obj")
                mkpath(obj_path)
                create_mock_experiment(joinpath(obj_path, "exp_20251014_100000"))
                create_mock_experiment(joinpath(obj_path, "exp_20251014_110000"))

                result = discover_experiments(tmpdir)
                @test result isa Dict{String, Vector{ExperimentInfo}}
                @test haskey(result, "test_obj")
                @test length(result["test_obj"]) == 2
            end
        end

        @testset "Force structure type" begin
            mktempdir() do tmpdir
                # Create ambiguous structure
                create_mock_experiment(joinpath(tmpdir, "exp1"))

                # Force flat
                result_flat = discover_experiments(tmpdir, structure=Flat)
                @test result_flat isa Vector{ExperimentInfo}

                # Force hierarchical
                result_hier = discover_experiments(tmpdir, structure=Hierarchical)
                @test result_hier isa Dict{String, Vector{ExperimentInfo}}
            end
        end
    end

    @testset "group_by_config_param" begin
        mktempdir() do tmpdir
            # Create experiments with different configs
            experiments = ExperimentInfo[]

            for (i, gn) in enumerate([8, 8, 16, 16])
                exp_path = joinpath(tmpdir, "group_test_$i")
                config = Dict(
                    "objective_name" => "test",
                    "grid_nodes" => gn,
                    "domain_size_param" => i <= 2 ? 0.1 : 0.4
                )
                create_mock_experiment(exp_path, config_content=config)
                validation = validate_experiment(exp_path)
                loaded_config = load_experiment_config(exp_path)
                push!(experiments, ExperimentInfo(
                    exp_path,
                    "exp_$i",
                    nothing,
                    loaded_config,
                    validation
                ))
            end

            # Group by grid_nodes
            groups_gn = group_by_config_param(experiments, "grid_nodes")
            @test length(groups_gn) == 2
            @test haskey(groups_gn, 8)
            @test haskey(groups_gn, 16)
            @test length(groups_gn[8]) == 2
            @test length(groups_gn[16]) == 2

            # Group by domain_size_param
            groups_ds = group_by_config_param(experiments, "domain_size_param")
            @test length(groups_ds) == 2
            @test haskey(groups_ds, 0.1)
            @test haskey(groups_ds, 0.4)
        end
    end

    @testset "group_by_degree_range" begin
        mktempdir() do tmpdir
            experiments = ExperimentInfo[]

            configs_data = [
                (4, 12, "test1"),
                (4, 12, "test2"),
                (4, 18, "test3"),
                (18, 18, "test4")
            ]

            for (i, (min_deg, max_deg, name)) in enumerate(configs_data)
                exp_path = joinpath(tmpdir, "degree_test_$i")
                config = Dict(
                    "objective_name" => "test",
                    "min_degree" => min_deg,
                    "max_degree" => max_deg
                )
                create_mock_experiment(exp_path, config_content=config)
                validation = validate_experiment(exp_path)
                loaded_config = load_experiment_config(exp_path)
                push!(experiments, ExperimentInfo(
                    exp_path,
                    name,
                    nothing,
                    loaded_config,
                    validation
                ))
            end

            groups = group_by_degree_range(experiments)

            @test length(groups) == 3
            @test haskey(groups, (4, 12))
            @test haskey(groups, (4, 18))
            @test haskey(groups, (18, 18))
            @test length(groups[(4, 12)]) == 2
            @test length(groups[(4, 18)]) == 1

            # Test degree_range array format
            exp_path = joinpath(tmpdir, "degree_array_test")
            config = Dict(
                "objective_name" => "test",
                "degree_range" => [10, 20]
            )
            create_mock_experiment(exp_path, config_content=config)
            validation = validate_experiment(exp_path)
            loaded_config = load_experiment_config(exp_path)
            exp_with_array = ExperimentInfo(
                exp_path,
                "array_test",
                nothing,
                loaded_config,
                validation
            )

            groups2 = group_by_degree_range([exp_with_array])
            @test haskey(groups2, (10, 20))
        end
    end

    @testset "load_experiment_config" begin
        mktempdir() do tmpdir
            # Test successful load
            exp_path = joinpath(tmpdir, "config_test")
            config_content = Dict(
                "objective_name" => "test_load",
                "grid_nodes" => 32,
                "custom_param" => "value"
            )
            create_mock_experiment(exp_path, config_content=config_content)

            loaded = load_experiment_config(exp_path)
            @test !isnothing(loaded)
            @test loaded["objective_name"] == "test_load"
            @test loaded["grid_nodes"] == 32

            # Test missing config
            no_config_path = joinpath(tmpdir, "no_config")
            mkpath(no_config_path)
            @test isnothing(load_experiment_config(no_config_path))

            # Test malformed config
            bad_config_path = joinpath(tmpdir, "bad_config")
            mkpath(bad_config_path)
            open(joinpath(bad_config_path, "experiment_config.json"), "w") do io
                write(io, "{invalid json")
            end
            @test isnothing(load_experiment_config(bad_config_path))
        end
    end

    @testset "count_experiments" begin
        mktempdir() do tmpdir
            # Create mixed structure
            create_mock_experiment(joinpath(tmpdir, "flat_exp1"))
            create_mock_experiment(joinpath(tmpdir, "flat_exp2"))

            obj_path = joinpath(tmpdir, "obj1")
            mkpath(obj_path)
            create_mock_experiment(joinpath(obj_path, "exp_1"))
            create_mock_experiment(joinpath(obj_path, "exp_2"))

            count = count_experiments(tmpdir)
            @test count >= 2  # At least some experiments counted
        end
    end

    @testset "Backwards compatibility - Flat structure still works" begin
        mktempdir() do tmpdir
            # Test that old flat structure discovery still works exactly as before
            for i in 1:3
                exp_dir = joinpath(tmpdir, "exp_$i")
                mkdir(exp_dir)
                touch(joinpath(exp_dir, "critical_points_deg_4.csv"))
                write(joinpath(exp_dir, "experiment_config.json"), """{"dimension": 4}""")
                write(joinpath(exp_dir, "results_summary.json"), """{"success": true}""")
            end

            # Old API still works
            experiments = discover_experiments(tmpdir)
            @test experiments isa Vector{ExperimentInfo}
            @test length(experiments) == 3
            @test all(exp -> exp.is_valid, experiments)
        end
    end

    @testset "Integration: Real-world hierarchical structure" begin
        mktempdir() do tmpdir
            # Simulate globtimcore test_results/ with hierarchical organization
            test_results = joinpath(tmpdir, "test_results")
            mkpath(test_results)

            # Multiple objectives with multiple experiments each
            for (obj_name, num_exps) in [
                ("lotka_volterra_4d", 5),
                ("extended_brusselator", 3),
                ("degn_harrison", 2)
            ]
                obj_path = joinpath(test_results, obj_name)
                mkpath(obj_path)

                for i in 1:num_exps
                    timestamp = "2025101$(4+i÷2)_$(100000 + i*10000)"
                    exp_path = joinpath(obj_path, "exp_$timestamp")
                    create_mock_experiment(exp_path, config_content=Dict(
                        "objective_name" => obj_name,
                        "grid_nodes" => 8 + (i-1)*8,
                        "domain_size_param" => 0.1 * i,
                        "min_degree" => 4,
                        "max_degree" => 12 + i*2
                    ))
                end
            end

            # Discover and validate
            @test detect_directory_structure(test_results) == Hierarchical

            experiments_by_obj = discover_experiments_hierarchical(test_results)
            @test length(experiments_by_obj) == 3
            @test length(experiments_by_obj["lotka_volterra_4d"]) == 5
            @test length(experiments_by_obj["extended_brusselator"]) == 3
            @test length(experiments_by_obj["degn_harrison"]) == 2

            # Test config-based grouping within an objective
            lv4d_exps = experiments_by_obj["lotka_volterra_4d"]
            groups_by_gn = group_by_config_param(lv4d_exps, "grid_nodes")
            @test length(groups_by_gn) == 5  # 5 different GN values

            # Test count
            total = count_experiments(test_results)
            @test total == 10  # 5 + 3 + 2
        end
    end
end
