using Test
using GlobtimPostProcessing

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
            Dict{String, Any}("test" => "value"),
            ["label1", "label2"],
            ["label1", "label2", "label3"],
            nothing,
            nothing,
            nothing,
            "/tmp/test"
        )

        @test exp_result.experiment_id == "test_experiment"
        @test length(exp_result.enabled_tracking) == 2
        @test length(exp_result.tracking_capabilities) == 3
    end

    # Run ClusterCollection tests (Phase 0)
    @testset "ClusterCollection (Phase 0)" begin
        include("test_cluster_collection.jl")
    end

    # Run AutoCollector tests (Phase 1)
    @testset "AutoCollector (Phase 1)" begin
        include("test_auto_collector.jl")
    end

    # Run Parameter Recovery tests (Issue #7)
    @testset "Parameter Recovery (Issue #7)" begin
        include("test_parameter_recovery.jl")
    end
end
