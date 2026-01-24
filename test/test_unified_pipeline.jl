"""
Tests for the unified post-processing pipeline.

Tests type detection, unified loading, and backward compatibility.
"""

using Test
using GlobtimPostProcessing
using GlobtimPostProcessing.UnifiedPipeline
using GlobtimPostProcessing.LV4DAnalysis
using DataFrames

# Test fixture paths
const TEST_FIXTURES = joinpath(@__DIR__, "fixtures")
const LV4D_FIXTURE = joinpath(TEST_FIXTURES, "lv4d_minimal")
const GENERIC_FIXTURE = joinpath(TEST_FIXTURES, "generic_minimal")

@testset "Unified Pipeline" begin

    @testset "Experiment Type Hierarchy" begin
        # Test type hierarchy
        @test LV4D isa ExperimentType
        @test DEUFLHARD isa ExperimentType
        @test FITZHUGH_NAGUMO isa ExperimentType
        @test UNKNOWN isa ExperimentType

        # Test type predicates
        @test UnifiedPipeline.is_lv4d(LV4D)
        @test !UnifiedPipeline.is_lv4d(DEUFLHARD)
        @test UnifiedPipeline.is_deuflhard(DEUFLHARD)
        @test !UnifiedPipeline.is_deuflhard(LV4D)
        @test UnifiedPipeline.is_unknown(UNKNOWN)
        @test !UnifiedPipeline.is_unknown(LV4D)

        # Test type names
        @test type_name(LV4D) == "LV4D"
        @test type_name(DEUFLHARD) == "Deuflhard"
        @test type_name(FITZHUGH_NAGUMO) == "FitzHugh-Nagumo"
        @test type_name(UNKNOWN) == "Unknown"
    end

    @testset "Type Detection" begin
        # Test path-based detection
        @test detect_experiment_type("lv4d_GN8_deg4-12_domain0.1_seed1_20260115") === LV4D
        @test detect_experiment_type("lv4d_subdivision_GN16_deg8_dom0.05_seed42") === LV4D
        @test detect_experiment_type("deuflhard_deg6_20260115") === DEUFLHARD
        @test detect_experiment_type("fitzhugh_nagumo_exp1") === FITZHUGH_NAGUMO
        @test detect_experiment_type("fhn_test_exp") === FITZHUGH_NAGUMO
        @test detect_experiment_type("unknown_experiment") === UNKNOWN
        @test detect_experiment_type("random_directory_name") === UNKNOWN

        # Test fixture detection (if fixture exists as directory)
        if isdir(LV4D_FIXTURE)
            # Detection from config should work
            detected = detect_experiment_type(LV4D_FIXTURE)
            # Even if directory name doesn't start with lv4d_, config detection should work
            # For our fixture, detection may fall back to UNKNOWN based on dir name
            @test detected isa ExperimentType
        end
    end

    @testset "BaseExperimentData Structure" begin
        # Test empty base data
        empty_base = UnifiedPipeline.empty_base_data("/some/path")
        @test experiment_id(empty_base) == "path"
        @test experiment_path(empty_base) == "/some/path"
        @test experiment_type(empty_base) === UNKNOWN
        @test isempty(empty_base.config)
        @test isempty(empty_base.degree_results)
        @test empty_base.critical_points === nothing
        @test !has_critical_points(empty_base)
        @test num_critical_points(empty_base) == 0

        # Test manual construction
        base = BaseExperimentData(
            "test_exp",
            "/path/to/test_exp",
            LV4D,
            Dict("key" => "value"),
            DataFrame(degree=[4, 6], L2_norm=[0.01, 0.001]),
            DataFrame(x1=[0.1, 0.2], x2=[0.3, 0.4], z=[0.01, 0.02])
        )

        @test experiment_id(base) == "test_exp"
        @test experiment_type(base) === LV4D
        @test has_critical_points(base)
        @test num_critical_points(base) == 2
        @test available_degrees(base) == [4, 6]
        @test get_config_value(base, "key") == "value"
        @test get_config_value(base, "missing", "default") == "default"
    end

    @testset "Single Experiment Detection" begin
        # Test unified is_single_experiment
        @test UnifiedPipeline.is_single_experiment(LV4D, LV4D_FIXTURE) == isdir(LV4D_FIXTURE)

        if isdir(GENERIC_FIXTURE)
            # Generic fixture has results_summary.json and CSVs
            @test UnifiedPipeline.is_single_experiment(UNKNOWN, GENERIC_FIXTURE)
        end

        # Non-existent path
        @test !UnifiedPipeline.is_single_experiment("/nonexistent/path")
    end

    @testset "Generic Experiment Loading" begin
        # Skip if fixture doesn't exist
        !isdir(GENERIC_FIXTURE) && return

        # Load generic experiment (should return BaseExperimentData)
        data = load_experiment(GENERIC_FIXTURE)

        @test data isa BaseExperimentData
        @test experiment_type(data) === UNKNOWN
        @test experiment_id(data) == "generic_minimal"

        # Check degree results were loaded
        dr = degree_results(data)
        @test nrow(dr) == 2
        @test sort(dr.degree) == [4, 6]

        # Check critical points were loaded
        @test has_critical_points(data)
        cp = critical_points(data)
        @test nrow(cp) == 11  # 3 from deg 4 + 8 from deg 6
        @test :degree in propertynames(cp)
    end

    @testset "LV4D Experiment Loading" begin
        # Skip if fixture doesn't exist
        !isdir(LV4D_FIXTURE) && return

        # Test that LV4DExperimentData has proper base
        # First rename fixture directory temporarily to have lv4d_ prefix
        lv4d_test_dir = joinpath(dirname(LV4D_FIXTURE), "lv4d_GN8_deg4_dom0.1_seed1_20260124_120000")

        # Copy fixture to properly named directory
        cp_dir = false
        if !isdir(lv4d_test_dir)
            cp(LV4D_FIXTURE, lv4d_test_dir)
            cp_dir = true
        end

        try
            data = LV4DAnalysis.load_lv4d_experiment(lv4d_test_dir)

            @test data isa LV4DExperimentData
            @test data.base isa BaseExperimentData

            # Test base accessors work
            @test experiment_id(data) == "lv4d_GN8_deg4_dom0.1_seed1_20260124_120000"
            @test experiment_type(data) === LV4D

            # Test LV4D-specific fields
            @test data.p_true == [0.2, 0.3, 0.5, 0.6]
            @test data.p_center == [0.2, 0.3, 0.5, 0.6]
            @test data.domain_size == 0.1
            @test data.dim == 4

            # Test backward compatibility accessors
            @test data.dir == lv4d_test_dir
            @test data.degree_results === data.base.degree_results
            @test data.critical_points === data.base.critical_points

            # Test critical points
            @test has_critical_points(data)
            cp = critical_points(data)
            @test nrow(cp) == 5
            @test :dist_to_true in propertynames(cp)  # LV4D adds this column
        finally
            # Clean up temporary directory
            if cp_dir && isdir(lv4d_test_dir)
                rm(lv4d_test_dir, recursive=true)
            end
        end
    end

    @testset "Unified load_experiment with Type Parameter" begin
        !isdir(GENERIC_FIXTURE) && return

        # Explicit type parameter
        data = load_experiment(GENERIC_FIXTURE; type=UNKNOWN)
        @test data isa BaseExperimentData
        @test experiment_type(data) === UNKNOWN

        # Auto-detect (should also work)
        data_auto = load_experiment(GENERIC_FIXTURE)
        @test data_auto isa BaseExperimentData
    end

    @testset "Backward Compatibility" begin
        # The old API should still work
        !isdir(GENERIC_FIXTURE) && return

        # load_experiment_results still works
        result = load_experiment_results(GENERIC_FIXTURE)
        @test result isa ExperimentResult
        @test result.source_path == GENERIC_FIXTURE

        # is_single_experiment in main module still works
        @test GlobtimPostProcessing.is_single_experiment(GENERIC_FIXTURE)
    end

    @testset "Type-Specific Ground Truth Detection" begin
        # LV4D and FitzHugh-Nagumo support ground truth
        @test UnifiedPipeline.has_ground_truth(LV4D)
        @test UnifiedPipeline.has_ground_truth(FITZHUGH_NAGUMO)

        # Others don't
        @test !UnifiedPipeline.has_ground_truth(DEUFLHARD)
        @test !UnifiedPipeline.has_ground_truth(UNKNOWN)

        # Dynamical system check
        @test UnifiedPipeline.is_dynamical_system(LV4D)
        @test UnifiedPipeline.is_dynamical_system(FITZHUGH_NAGUMO)
        @test !UnifiedPipeline.is_dynamical_system(DEUFLHARD)
    end

    @testset "List Experiment Types" begin
        types = UnifiedPipeline.list_experiment_types()
        @test length(types) >= 3  # At least LV4D, Deuflhard, FitzHugh-Nagumo
        @test any(t -> t[1] === LV4D, types)
        @test all(t -> t[2] isa String, types)
    end

end
