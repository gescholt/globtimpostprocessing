using Test
using GlobtimPostProcessing

# Include shared test fixtures once (used by test_capture_analysis, test_refinement_phase1,
# test_integration_real_fixtures — previously each included it independently, causing
# duplicate method definition warnings)
include(joinpath(@__DIR__, "fixtures", "test_functions.jl"))

# Include shared test utility modules once (used by test_cp_verification, test_ground_truth,
# test_gradient_hessian_accuracy, test_hessian_classification_correctness — previously
# each included them independently, causing module redefinition errors)
include(joinpath(@__DIR__, "test_utils", "cp_verification.jl"))
include(joinpath(@__DIR__, "test_utils", "ground_truth_functions.jl"))
using .CPVerification
using .GroundTruthFunctions

# Shared constant used by test_ground_truth, test_gradient_hessian_accuracy,
# test_hessian_classification_correctness
const GT_DIR = joinpath(@__DIR__, "fixtures", "ground_truth")

@testset "GlobtimPostProcessing.jl" begin
    @testset "Module Loading" begin
        @test isdefined(GlobtimPostProcessing, :load_experiment_results)
        @test isdefined(GlobtimPostProcessing, :load_campaign_results)
        @test isdefined(GlobtimPostProcessing, :compute_statistics)
        @test isdefined(GlobtimPostProcessing, :ExperimentResult)
        @test isdefined(GlobtimPostProcessing, :CampaignResults)
    end

    @testset "Data Structures" begin
        # Test ExperimentResult construction
        exp_result = ExperimentResult(
            "test_experiment",
            Dict{String,Any}("test" => "value"),
            ["label1", "label2"],
            ["label1", "label2", "label3"],
            nothing,
            nothing,
            nothing,
            "/tmp/test",
        )

        @test exp_result.experiment_id == "test_experiment"
        @test length(exp_result.enabled_tracking) == 2
        @test length(exp_result.tracking_capabilities) == 3
    end

    # Run Data Loading tests (Issue #7, Phase 1)
    @testset "Data Loading (Issue #7, Phase 1)" begin
        include("test_data_loading.jl")
    end

    # Run Parameter Recovery tests (Issue #7)
    @testset "Parameter Recovery (Issue #7)" begin
        include("test_parameter_recovery.jl")
    end

    # Run Parameter Recovery Real Data tests (Issue #7, Phase 2)
    @testset "Parameter Recovery - Real Data (Issue #7, Phase 2)" begin
        include("test_parameter_recovery_real_data.jl")
    end

    # Run Quality Diagnostics tests (Issue #7, Phase 3)
    @testset "Quality Diagnostics (Issue #7, Phase 3)" begin
        include("test_quality_diagnostics.jl")
    end

    # Run Batch Processing tests (Issue #20, Phase 2)
    # COMMENTED OUT: Requires ErrorCategorization which needs Globtim
    # @testset "Batch Processing (Issue #20, Phase 2)" begin
    #     include("test_batch_processing.jl")
    # end

    # Run Error Categorization tests (Issue #20, Phase 3)
    # COMMENTED OUT: Requires Globtim dependency
    # @testset "Error Categorization (Issue #20, Phase 3)" begin
    #     include("test_error_categorization.jl")
    # end

    # Run Critical Point Classification tests
    @testset "Critical Point Classification" begin
        include("test_critical_point_classification.jl")
    end

    # Run Landscape Fidelity tests
    @testset "Landscape Fidelity" begin
        include("test_landscape_fidelity.jl")
    end

    # Run Phase 1 Refinement tests (simple functions, no Globtim dependency)
    @testset "Phase 1 Refinement" begin
        include("test_refinement_phase1.jl")
    end

    # Run Capture Analysis tests (known CP capture rates, no Globtim dependency)
    @testset "Capture Analysis" begin
        include("test_capture_analysis.jl")
    end

    # Run Integration tests with Real Fixtures (uses real globtim data)
    @testset "Integration: Real Fixtures" begin
        include("test_integration_real_fixtures.jl")
    end

    # Run Unified Pipeline tests (January 2026)
    @testset "Unified Pipeline" begin
        include("test_unified_pipeline.jl")
    end

    # Run Loader Consolidation tests (tibf — February 2026)
    @testset "Loader Consolidation" begin
        include("test_loader_consolidation.jl")
    end

    # Run LV4D TUI tests (January 2026 - domain filter fix)
    @testset "LV4D TUI" begin
        include("test_lv4d_tui.jl")
    end

    # Run LV4D Sweep tests (January 2026 - error message improvement)
    @testset "LV4D Sweep" begin
        include("test_lv4d_sweep.jl")
    end

    # Run Subdivision Tree Analysis tests (January 2026)
    @testset "Subdivision Tree Analysis" begin
        include("test_subdivision_analysis.jl")
    end

    # Run Valley Walking tests (February 2026)
    @testset "Valley Walking" begin
        include("test_valley_walking.jl")
    end

    # Run Postprocessing Pipeline tests (March 2026)
    @testset "Postprocessing Pipeline" begin
        include("test_postprocessing_pipeline.jl")
    end

    # Landscape capture data types (March 2026)
    @testset "Landscape Capture Types" begin
        include("test_landscape_capture_types.jl")
    end

    # CP verification oracle (Level 0 — March 2026)
    @testset "CP Verification Oracle" begin
        include("test_cp_verification.jl")
    end

    # Ground truth reference data (Level 1 — March 2026)
    @testset "Ground Truth Reference Data" begin
        include("test_ground_truth.jl")
    end

    # Gradient/Hessian accuracy (Level 2 — March 2026)
    @testset "Gradient/Hessian Accuracy" begin
        include("test_gradient_hessian_accuracy.jl")
    end

    # Hessian classification correctness (Level 3 — March 2026)
    @testset "Hessian Classification Correctness" begin
        include("test_hessian_classification_correctness.jl")
    end

    # Aqua.jl quality assurance tests
    include("test_aqua.jl")
end
