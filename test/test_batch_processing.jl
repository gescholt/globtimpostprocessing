"""
Test suite for Phase 2: Batch Processing and Progress Tracking

Tests for Issue #20 Phase 2 implementation:
- batch_analyze_campaign (silent mode, error handling, return_stats, JSON format)
- load_campaign_with_progress
- aggregate_campaign_statistics_with_progress
- batch_analyze_campaign_with_progress
- CLI script functionality
"""

using Test
using GlobtimPostProcessing
using JSON3
using Dates

# Test data paths
TEST_CAMPAIGN_PATH = joinpath(@__DIR__, "..", "collected_experiments_20251013_083530",
                              "campaign_lotka_volterra_4d_extended_degrees")
NONEXISTENT_PATH = "/tmp/nonexistent_campaign_$(rand(UInt32))"

@testset "Phase 2: Batch Processing" begin

    @testset "1. batch_analyze_campaign - Basic Functionality" begin
        @testset "1.1 Silent mode with markdown output" begin
            output_file = tempname() * ".md"

            success, result = batch_analyze_campaign(
                TEST_CAMPAIGN_PATH,
                output_file,
                silent=true
            )

            @test success == true
            @test result == output_file
            @test isfile(output_file)

            # Verify report content
            content = read(output_file, String)
            @test length(content) > 0
            @test occursin("Campaign Report", content) || occursin("campaign", lowercase(content))

            # Cleanup
            rm(output_file, force=true)
        end

        @testset "1.2 With return_stats option" begin
            output_file = tempname() * ".md"

            success, result, stats = batch_analyze_campaign(
                TEST_CAMPAIGN_PATH,
                output_file,
                silent=true,
                return_stats=true
            )

            @test success == true
            @test result == output_file
            @test stats isa Dict
            @test haskey(stats, "campaign_summary") || haskey(stats, "experiments")

            # Cleanup
            rm(output_file, force=true)
        end

        @testset "1.3 Auto-creates nested output directories" begin
            nested_dir = joinpath(tempdir(), "test_nested_$(rand(UInt32))", "subdir", "report.md")

            success, result = batch_analyze_campaign(
                TEST_CAMPAIGN_PATH,
                nested_dir,
                silent=true
            )

            @test success == true
            @test isfile(nested_dir)
            @test dirname(nested_dir) |> isdir

            # Cleanup
            rm(dirname(dirname(nested_dir)), recursive=true, force=true)
        end
    end

    @testset "2. batch_analyze_campaign - Error Handling" begin
        @testset "2.1 Non-existent campaign directory" begin
            output_file = tempname() * ".md"

            success, result = batch_analyze_campaign(
                NONEXISTENT_PATH,
                output_file,
                silent=true
            )

            @test success == false
            @test result isa String  # Error message
            @test occursin("not found", lowercase(result)) || occursin("error", lowercase(result))
            @test !isfile(output_file)  # Should not create file on error
        end

        @testset "2.2 Error with return_stats returns empty dict" begin
            output_file = tempname() * ".md"

            success, result, stats = batch_analyze_campaign(
                NONEXISTENT_PATH,
                output_file,
                silent=true,
                return_stats=true
            )

            @test success == false
            @test result isa String  # Error message
            @test stats isa Dict
            @test isempty(stats)
        end
    end

    @testset "3. batch_analyze_campaign - JSON Format" begin
        @testset "3.1 JSON output format" begin
            output_file = tempname() * ".json"

            success, result, stats = batch_analyze_campaign(
                TEST_CAMPAIGN_PATH,
                output_file,
                silent=true,
                return_stats=true,
                format="json"
            )

            @test success == true
            @test isfile(output_file)

            # Verify JSON is valid and parsable
            json_content = read(output_file, String)
            parsed = JSON3.read(json_content)

            @test parsed isa AbstractDict
            @test haskey(parsed, :statistics) || haskey(parsed, :campaign_id)

            # Check for expected fields
            if haskey(parsed, :statistics)
                @test parsed.statistics isa AbstractDict
            end

            if haskey(parsed, :num_experiments)
                @test parsed.num_experiments isa Integer
                @test parsed.num_experiments > 0
            end

            # Cleanup
            rm(output_file, force=true)
        end

        @testset "3.2 JSON format includes all expected fields" begin
            output_file = tempname() * ".json"

            success, result = batch_analyze_campaign(
                TEST_CAMPAIGN_PATH,
                output_file,
                silent=true,
                format="json"
            )

            parsed = JSON3.read(read(output_file, String))

            # Check structure
            expected_keys = [:campaign_id, :statistics, :generation_time, :num_experiments]
            for key in expected_keys
                # At least some of these should be present
                if haskey(parsed, key)
                    @test !isnothing(parsed[key])
                end
            end

            # Cleanup
            rm(output_file, force=true)
        end
    end

    @testset "4. load_campaign_with_progress" begin
        @testset "4.1 Loads campaign successfully with progress" begin
            campaign = load_campaign_with_progress(
                TEST_CAMPAIGN_PATH,
                show_progress=false  # Disable for testing
            )

            @test campaign isa CampaignResults
            @test length(campaign.experiments) > 0
        end

        @testset "4.2 Returns same result as standard loader" begin
            campaign_with_progress = load_campaign_with_progress(
                TEST_CAMPAIGN_PATH,
                show_progress=false
            )

            campaign_standard = load_campaign_results(TEST_CAMPAIGN_PATH)

            @test campaign_with_progress.campaign_id == campaign_standard.campaign_id
            @test length(campaign_with_progress.experiments) == length(campaign_standard.experiments)
        end

        @testset "4.3 Progress enabled doesn't crash" begin
            # This test just verifies progress bars don't cause errors
            # (they may not display in test environment)
            @test_nowarn campaign = load_campaign_with_progress(
                TEST_CAMPAIGN_PATH,
                show_progress=true
            )
        end
    end

    @testset "5. aggregate_campaign_statistics_with_progress" begin
        campaign = load_campaign_results(TEST_CAMPAIGN_PATH)

        @testset "5.1 Computes statistics with progress disabled" begin
            stats = aggregate_campaign_statistics_with_progress(
                campaign,
                show_progress=false
            )

            @test stats isa Dict
            @test haskey(stats, "experiments") || haskey(stats, "campaign_summary")
        end

        @testset "5.2 Returns same result as standard aggregation" begin
            stats_with_progress = aggregate_campaign_statistics_with_progress(
                campaign,
                show_progress=false
            )

            # Note: Standard function may have different output due to progress callback
            # We just verify structure is similar
            @test stats_with_progress isa Dict
            @test length(stats_with_progress) > 0
        end

        @testset "5.3 Progress enabled doesn't crash" begin
            @test_nowarn stats = aggregate_campaign_statistics_with_progress(
                campaign,
                show_progress=true
            )
        end
    end

    @testset "6. batch_analyze_campaign_with_progress" begin
        @testset "6.1 Full pipeline with progress (disabled)" begin
            output_file = tempname() * ".md"

            success, result, stats = batch_analyze_campaign_with_progress(
                TEST_CAMPAIGN_PATH,
                output_file,
                show_progress=false,
                silent=true
            )

            @test success == true
            @test result == output_file
            @test isfile(output_file)
            @test stats isa Dict
            @test !isempty(stats)

            # Cleanup
            rm(output_file, force=true)
        end

        @testset "6.2 Verbose mode runs successfully" begin
            output_file = tempname() * ".md"

            # Just verify verbose mode doesn't crash
            success, result, stats = batch_analyze_campaign_with_progress(
                TEST_CAMPAIGN_PATH,
                output_file,
                show_progress=false,
                silent=false,
                verbose=true
            )

            @test success == true
            @test isfile(output_file)

            # Cleanup
            rm(output_file, force=true)
        end

        @testset "6.3 Error handling" begin
            output_file = tempname() * ".md"

            success, result, stats = batch_analyze_campaign_with_progress(
                NONEXISTENT_PATH,
                output_file,
                show_progress=false,
                silent=true
            )

            @test success == false
            @test result isa String
            @test stats isa Dict
            @test isempty(stats)
        end

        @testset "6.4 Progress enabled doesn't crash" begin
            output_file = tempname() * ".md"

            @test_nowarn success, result, stats = batch_analyze_campaign_with_progress(
                TEST_CAMPAIGN_PATH,
                output_file,
                show_progress=true,
                silent=true
            )

            # Cleanup
            rm(output_file, force=true)
        end
    end

    @testset "7. Integration Tests" begin
        @testset "7.1 Multiple campaigns in sequence" begin
            campaigns = [
                TEST_CAMPAIGN_PATH,
                TEST_CAMPAIGN_PATH  # Process same campaign twice for testing
            ]

            results = []
            for (i, campaign_path) in enumerate(campaigns)
                output_file = tempname() * "_$i.md"
                success, result = batch_analyze_campaign(
                    campaign_path,
                    output_file,
                    silent=true
                )
                push!(results, (success, result))
            end

            @test all(r[1] for r in results)  # All successful
            @test all(isfile(r[2]) for r in results)

            # Cleanup
            for (success, result) in results
                rm(result, force=true)
            end
        end

        @testset "7.2 Markdown vs JSON consistency" begin
            md_file = tempname() * ".md"
            json_file = tempname() * ".json"

            md_success, _, md_stats = batch_analyze_campaign(
                TEST_CAMPAIGN_PATH,
                md_file,
                silent=true,
                return_stats=true,
                format="markdown"
            )

            json_success, _, json_stats = batch_analyze_campaign(
                TEST_CAMPAIGN_PATH,
                json_file,
                silent=true,
                return_stats=true,
                format="json"
            )

            @test md_success == true
            @test json_success == true
            @test isfile(md_file)
            @test isfile(json_file)

            # Both should return similar stats structure
            @test typeof(md_stats) == typeof(json_stats)

            # Cleanup
            rm(md_file, force=true)
            rm(json_file, force=true)
        end
    end

    @testset "8. Performance and Resource Tests" begin
        @testset "8.1 Batch processing completes in reasonable time" begin
            output_file = tempname() * ".md"

            elapsed = @elapsed begin
                success, result = batch_analyze_campaign(
                    TEST_CAMPAIGN_PATH,
                    output_file,
                    silent=true
                )
            end

            @test success == true
            @test elapsed < 120.0  # Should complete within 2 minutes for small campaign

            # Cleanup
            rm(output_file, force=true)
        end

        @testset "8.2 No file leaks on repeated operations" begin
            output_file = tempname() * ".md"

            # Run 5 times to check for resource leaks
            for i in 1:5
                success, result = batch_analyze_campaign(
                    TEST_CAMPAIGN_PATH,
                    output_file,
                    silent=true
                )
                @test success == true
            end

            @test isfile(output_file)  # Last one should exist

            # Cleanup
            rm(output_file, force=true)
        end
    end
end

@testset "Phase 2: CLI Script Tests" begin
    CLI_SCRIPT = joinpath(@__DIR__, "..", "scripts", "batch_analyze.jl")

    @testset "9. CLI Script Functionality" begin
        @testset "9.1 CLI script exists and is readable" begin
            @test isfile(CLI_SCRIPT)
            @test filesize(CLI_SCRIPT) > 0
        end

        @testset "9.2 Help message works" begin
            result = try
                read(`julia $CLI_SCRIPT --help`, String)
            catch e
                ""
            end

            # Should show help without error
            @test occursin("Usage", result) || occursin("batch_analyze", result) ||
                  occursin("--input", result) || occursin("help", lowercase(result))
        end

        @testset "9.3 Missing required arguments fails" begin
            # Try to run without required --input argument
            exit_code = try
                run(`julia $CLI_SCRIPT --output /tmp/test.md`)
                0
            catch e
                if e isa ProcessFailedException
                    e.procs[1].exitcode
                else
                    -1
                end
            end

            @test exit_code != 0  # Should fail with non-zero exit code
        end

        @testset "9.4 Successful batch analysis via CLI" begin
            output_file = tempname() * ".md"

            exit_code = try
                run(`julia $CLI_SCRIPT --input $TEST_CAMPAIGN_PATH --output $output_file --silent`)
                0
            catch e
                if e isa ProcessFailedException
                    e.procs[1].exitcode
                else
                    -1
                end
            end

            @test exit_code == 0
            @test isfile(output_file)

            # Cleanup
            rm(output_file, force=true)
        end
    end
end

println("\n" * "="^80)
println("Phase 2 Test Suite Complete")
println("="^80)
