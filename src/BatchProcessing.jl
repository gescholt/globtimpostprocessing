"""
BatchProcessing - Phase 2.1 Implementation

Provides non-interactive batch processing functionality for campaign analysis.
Functions operate silently (no user interaction) and return structured results.
"""

# This file is included in GlobtimPostProcessing.jl main module
# No need for separate module declaration

"""
    batch_analyze_campaign(campaign_path::String, output_file::String; kwargs...)

Perform batch analysis of a campaign without user interaction.

# Arguments
- `campaign_path::String`: Path to campaign directory containing experiment results
- `output_file::String`: Path where markdown report will be saved

# Keyword Arguments
- `silent::Bool=false`: If true, suppresses all output except errors
- `return_stats::Bool=false`: If true, returns statistics dict as third return value
- `format::String="markdown"`: Output format ("markdown" or "json")
- `include_errors::Bool=false`: If true, includes error categorization analysis in report

# Returns
When `return_stats=false`:
- `(success::Bool, result::String)`: On success returns (true, report_path),
                                      on failure returns (false, error_message)

When `return_stats=true`:
- `(success::Bool, report_path::String, stats::Dict)`: Returns success status,
                                                         report path, and statistics

# Examples
```julia
# Basic usage
success, report_path = batch_analyze_campaign("campaign_dir", "report.md", silent=true)

# With statistics
success, report_path, stats = batch_analyze_campaign(
    "campaign_dir",
    "report.md",
    silent=true,
    return_stats=true
)

# JSON format
success, report_path, stats = batch_analyze_campaign(
    "campaign_dir",
    "report.json",
    silent=true,
    return_stats=true,
    format="json"
)
```
"""
function batch_analyze_campaign(
    campaign_path::String,
    output_file::String;
    silent::Bool=false,
    return_stats::Bool=false,
    format::String="markdown",
    include_errors::Bool=false
)
    try
        # Validate campaign path
        if !isdir(campaign_path)
            error_msg = "Campaign directory not found: $campaign_path"
            !silent && @error error_msg
            return return_stats ? (false, error_msg, Dict()) : (false, error_msg)
        end

        # Auto-create output directory if needed
        output_dir = dirname(output_file)
        if !isempty(output_dir) && !isdir(output_dir)
            !silent && @info "Creating output directory: $output_dir"
            mkpath(output_dir)
        end

        # Load campaign
        !silent && @info "Loading campaign from: $campaign_path"
        campaign = load_campaign_results(campaign_path)

        # Aggregate statistics
        !silent && @info "Computing campaign statistics..."
        agg_stats = aggregate_campaign_statistics(campaign)

        # Generate and save report based on format
        if format == "json"
            # JSON format
            !silent && @info "Generating JSON report..."

            json_output = Dict(
                "campaign_id" => campaign.campaign_id,
                "statistics" => agg_stats,
                "report_markdown" => generate_campaign_report(campaign, include_errors=include_errors),
                "generation_time" => string(now()),
                "collection_timestamp" => string(campaign.collection_timestamp),
                "num_experiments" => length(campaign.experiments)
            )

            # Add error analysis if requested
            if include_errors
                json_output["error_analysis"] = categorize_campaign_errors(campaign)
            end

            !silent && @info "Saving JSON report to: $output_file"
            open(output_file, "w") do io
                JSON3.pretty(io, json_output)
            end
        else
            # Markdown format (default)
            !silent && @info "Generating markdown report..."
            report_content = generate_campaign_report(campaign, include_errors=include_errors)

            !silent && @info "Saving report to: $output_file"
            save_report(report_content, output_file)
        end

        !silent && @info "✓ Batch analysis complete: $output_file"

        # Return based on return_stats flag
        if return_stats
            return (true, output_file, agg_stats)
        else
            return (true, output_file)
        end

    catch e
        error_msg = "Batch analysis failed: $(sprint(showerror, e))"
        !silent && @error error_msg

        if return_stats
            return (false, error_msg, Dict())
        else
            return (false, error_msg)
        end
    end
end

"""
    load_campaign_with_progress(campaign_path::String; show_progress::Bool=true)

Load campaign results with optional progress bar display.

# Arguments
- `campaign_path::String`: Path to campaign directory

# Keyword Arguments
- `show_progress::Bool=true`: If true, displays progress bar during loading

# Returns
- `CampaignResults`: Loaded campaign results

# Examples
```julia
# With progress
campaign = load_campaign_with_progress("campaign_dir")

# Silent mode
campaign = load_campaign_with_progress("campaign_dir", show_progress=false)
```
"""
function load_campaign_with_progress(
    campaign_path::String;
    show_progress::Bool=true
)
    if !show_progress
        # Fall back to standard loading without progress
        return load_campaign_results(campaign_path)
    end

    # Get list of experiment directories
    exp_dirs = filter(isdir,
                     [joinpath(campaign_path, d) for d in readdir(campaign_path)])

    if isempty(exp_dirs)
        error("No experiment directories found in: $campaign_path")
    end

    # Create progress bar
    progress = Progress(length(exp_dirs),
                       desc="Loading campaign: ",
                       barlen=40,
                       showspeed=true)

    # Load experiments with progress tracking
    for _ in exp_dirs
        # Progress is shown while scanning directories
        next!(progress)
    end

    # Use standard loader (it handles the actual loading)
    # We just showed progress for the directory scanning
    campaign = load_campaign_results(campaign_path)

    return campaign
end

"""
    aggregate_campaign_statistics_with_progress(campaign::CampaignResults; show_progress::Bool=true)

Compute campaign statistics with optional progress tracking.

# Arguments
- `campaign::CampaignResults`: Campaign to analyze

# Keyword Arguments
- `show_progress::Bool=true`: If true, displays progress during computation

# Returns
- `Dict`: Aggregated statistics dictionary

# Examples
```julia
campaign = load_campaign_results("campaign_dir")
stats = aggregate_campaign_statistics_with_progress(campaign)
```
"""
function aggregate_campaign_statistics_with_progress(
    campaign::CampaignResults;
    show_progress::Bool=true
)
    if !show_progress
        # Fall back to standard aggregation
        return aggregate_campaign_statistics(campaign)
    end

    num_experiments = length(campaign.experiments)
    progress = Progress(num_experiments,
                       desc="Computing statistics: ",
                       barlen=40,
                       showspeed=true)

    # Define progress callback that updates the progress bar in real-time
    progress_callback = (current, total, label) -> next!(progress)

    # Call aggregate_campaign_statistics with real-time progress callback
    # Progress bar updates as each experiment is processed
    stats = aggregate_campaign_statistics(campaign, progress_callback=progress_callback)

    return stats
end

"""
    batch_analyze_campaign_with_progress(campaign_path, output_file; kwargs...)

Perform batch campaign analysis with multi-stage progress tracking.

# Arguments
- `campaign_path::String`: Path to campaign directory
- `output_file::String`: Path for output report

# Keyword Arguments
- `show_progress::Bool=true`: Display progress bars
- `silent::Bool=false`: Suppress non-progress output
- `verbose::Bool=false`: Enable verbose logging

# Returns
- `(success::Bool, report_path::String, stats::Dict)`: Always returns statistics

# Stages
1. Loading campaign (with progress)
2. Computing statistics (with progress)
3. Generating report
4. Saving report

# Examples
```julia
success, report, stats = batch_analyze_campaign_with_progress(
    "campaign_dir",
    "report.md",
    show_progress=true
)
```
"""
function batch_analyze_campaign_with_progress(
    campaign_path::String,
    output_file::String;
    show_progress::Bool=true,
    silent::Bool=false,
    verbose::Bool=false,
    include_errors::Bool=false
)
    try
        # Validate inputs
        if !isdir(campaign_path)
            error_msg = "Campaign directory not found: $campaign_path"
            !silent && @error error_msg
            return (false, error_msg, Dict())
        end

        # Auto-create output directory
        output_dir = dirname(output_file)
        if !isempty(output_dir) && !isdir(output_dir)
            verbose && @info "Creating output directory: $output_dir"
            mkpath(output_dir)
        end

        # Stage 1: Load campaign with progress
        verbose && println("Stage 1/4: Loading campaign...")
        campaign = load_campaign_with_progress(campaign_path, show_progress=show_progress)
        verbose && println("✓ Loaded $(length(campaign.experiments)) experiments")

        # Stage 2: Compute statistics with progress
        verbose && println("Stage 2/4: Computing statistics...")
        stats = aggregate_campaign_statistics_with_progress(campaign, show_progress=show_progress)
        verbose && println("✓ Statistics computed")

        # Stage 3: Generate report
        verbose && println("Stage 3/4: Generating report...")
        report_content = generate_campaign_report(campaign, include_errors=include_errors)
        verbose && println("✓ Report generated ($(length(report_content)) chars)")

        # Stage 4: Save report
        verbose && println("Stage 4/4: Saving report...")
        save_report(report_content, output_file)
        verbose && println("✓ Report saved to: $output_file")

        !silent && @info "✓ Complete: $output_file"

        return (true, output_file, stats)

    catch e
        error_msg = "Batch analysis with progress failed: $(sprint(showerror, e))"
        !silent && @error error_msg
        return (false, error_msg, Dict())
    end
end
