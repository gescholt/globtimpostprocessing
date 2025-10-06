#!/usr/bin/env julia
"""
Test Phase 1 Implementation - Campaign Analysis

This script tests the newly implemented campaign analysis functions:
- aggregate_campaign_statistics()
- analyze_campaign()
- generate_campaign_report()
- save_campaign_report()
"""

using Pkg
Pkg.activate(@__DIR__)

using GlobtimPostProcessing

println("="^80)
println("PHASE 1 TESTING: Campaign Analysis & Report Generation")
println("="^80)

# Test with real campaign data
campaign_path = "../collected_experiments_20251004"

if !isdir(campaign_path)
    println("❌ Campaign directory not found: $campaign_path")
    exit(1)
end

println("\n📂 Loading campaign: $campaign_path")
campaign = load_campaign_results(campaign_path)

println("\n" * "="^80)
println("TEST 1: aggregate_campaign_statistics()")
println("="^80)

try
    agg_stats = aggregate_campaign_statistics(campaign)

    println("✓ Function executed successfully")
    println("\nReturned keys:")
    for key in keys(agg_stats)
        println("  - $key")
    end

    # Verify structure
    @assert haskey(agg_stats, "experiments")
    @assert haskey(agg_stats, "aggregated_metrics")
    @assert haskey(agg_stats, "campaign_summary")
    @assert haskey(agg_stats, "parameter_variations")
    println("\n✓ All expected keys present")

    # Check campaign summary
    summary = agg_stats["campaign_summary"]
    println("\nCampaign Summary:")
    println("  Experiments: $(summary["num_experiments"])")
    println("  Success rate: $(round(summary["success_rate"]*100, digits=1))%")
    println("  Total time: $(round(summary["total_computation_hours"], digits=2)) hours")

catch e
    println("❌ TEST FAILED")
    println("Error: $e")
    rethrow(e)
end

println("\n" * "="^80)
println("TEST 2: analyze_campaign()")
println("="^80)

try
    agg_stats = analyze_campaign(campaign)
    println("✓ Function executed successfully")
catch e
    println("❌ TEST FAILED")
    println("Error: $e")
    rethrow(e)
end

println("\n" * "="^80)
println("TEST 3: generate_campaign_report()")
println("="^80)

try
    report = generate_campaign_report(campaign)

    println("✓ Function executed successfully")
    println("\nReport length: $(length(report)) characters")
    println("\nFirst 500 characters of report:")
    println("-"^80)
    println(report[1:min(500, length(report))])
    println("-"^80)

    # Verify report contains expected sections
    @assert occursin("Campaign Analysis Report", report)
    @assert occursin("Campaign Summary", report)
    @assert occursin("Parameter Analysis", report)
    @assert occursin("Aggregated Metrics", report)
    println("\n✓ All expected sections present in report")

catch e
    println("❌ TEST FAILED")
    println("Error: $e")
    rethrow(e)
end

println("\n" * "="^80)
println("TEST 4: save_campaign_report()")
println("="^80)

try
    output_path = joinpath(@__DIR__, "test_campaign_report.md")
    report = save_campaign_report(campaign, output_path)

    println("✓ Function executed successfully")

    # Verify file was created
    @assert isfile(output_path)
    println("✓ Report file created: $output_path")

    # Verify file contents match returned report
    file_contents = read(output_path, String)
    @assert file_contents == report
    println("✓ File contents match returned report")

    println("\nReport saved to: $output_path")
    println("File size: $(stat(output_path).size) bytes")

catch e
    println("❌ TEST FAILED")
    println("Error: $e")
    rethrow(e)
end

println("\n" * "="^80)
println("✅ ALL PHASE 1 TESTS PASSED")
println("="^80)

println("\nImplemented functions:")
println("  ✓ aggregate_campaign_statistics()")
println("  ✓ analyze_campaign()")
println("  ✓ generate_campaign_report()")
println("  ✓ save_campaign_report()")

println("\nPhase 1 implementation is complete and functional!")
