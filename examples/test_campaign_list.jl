#!/usr/bin/env julia
"""Test the improved campaign selection display"""

using Dates

function find_campaign_directories()
    """Search for campaign directories in standard locations"""
    search_paths = [
        "../globtimcore/experiments",
        "../globtimcore/hpc_results",
        "../globtimcore"
    ]

    campaigns = []

    for search_path in search_paths
        if !isdir(search_path)
            continue
        end

        # Find directories containing hpc_results (manual depth limit)
        function walk_limited(path, current_depth, max_depth)
            if current_depth > max_depth
                return
            end

            if basename(path) == "hpc_results" && isdir(path)
                push!(campaigns, path)
            end

            if isdir(path)
                for entry in readdir(path, join=true)
                    if isdir(entry)
                        walk_limited(entry, current_depth + 1, max_depth)
                    end
                end
            end
        end

        walk_limited(search_path, 0, 4)
    end

    return sort(unique(campaigns))
end

# Find campaigns
campaigns = find_campaign_directories()

# Collect campaign metadata
campaign_info = []
for campaign in campaigns
    exp_count = 0
    mtime = nothing

    try
        if isdir(campaign)
            # Count experiments
            exp_count = length(filter(d -> isdir(joinpath(campaign, d)) &&
                                           !startswith(d, "."),
                                    readdir(campaign)))

            # Get most recent modification time from experiments
            mtime = stat(campaign).mtime
            for entry in readdir(campaign, join=true)
                if isdir(entry)
                    entry_mtime = stat(entry).mtime
                    if mtime === nothing || entry_mtime > mtime
                        mtime = entry_mtime
                    end
                end
            end
        end
    catch e
        println("Warning: Error processing $campaign: $e")
    end

    push!(campaign_info, (path=campaign, exp_count=exp_count, mtime=mtime))
end

# Sort by modification time (most recent first)
sort!(campaign_info, by=x -> something(x.mtime, 0.0), rev=true)

println("Found $(length(campaign_info)) campaign(s) (sorted by most recent):")
println()

for (i, info) in enumerate(campaign_info)
    # Get relative path for nicer display
    rel_path = relpath(info.path, pwd())

    # Format timestamp
    time_str = if info.mtime !== nothing
        dt = Dates.unix2datetime(info.mtime)
        Dates.format(dt, "yyyy-mm-dd HH:MM")
    else
        "unknown"
    end

    println("[$i] $rel_path")
    println("    → $(info.exp_count) experiment(s), last modified: $time_str")
end
