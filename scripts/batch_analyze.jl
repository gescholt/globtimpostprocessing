#!/usr/bin/env julia
"""
batch_analyze.jl - Batch Campaign Analysis CLI

Non-interactive command-line tool for automated campaign analysis and report generation.
Part of Phase 2.1 implementation for Issue #20.

Usage:
    julia scripts/batch_analyze.jl --input <campaign_path> --output <report_path> [--silent]

Arguments:
    --input PATH    Path to campaign directory (required)
    --output PATH   Path for output markdown report (required)
    --silent        Suppress all output except errors (optional)
    --help          Show this help message

Exit codes:
    0   Success
    1   Error (invalid arguments, campaign not found, processing error)

Examples:
    # Basic batch analysis
    julia scripts/batch_analyze.jl --input collected_experiments_20251004 --output report.md

    # Silent mode (no output)
    julia scripts/batch_analyze.jl --input campaign_dir --output report.md --silent

    # With nested output directory (auto-created)
    julia scripts/batch_analyze.jl --input campaign_dir --output reports/2025/campaign.md
"""

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using GlobtimPostProcessing

# Parse command line arguments
function parse_args(args::Vector{String})
    parsed = Dict{String, Any}(
        "input" => nothing,
        "output" => nothing,
        "format" => "markdown",
        "silent" => false,
        "help" => false
    )

    i = 1
    while i <= length(args)
        arg = args[i]

        if arg == "--help" || arg == "-h"
            parsed["help"] = true
            return parsed

        elseif arg == "--input"
            if i + 1 > length(args)
                error("--input requires a path argument")
            end
            parsed["input"] = args[i + 1]
            i += 2

        elseif arg == "--output"
            if i + 1 > length(args)
                error("--output requires a path argument")
            end
            parsed["output"] = args[i + 1]
            i += 2

        elseif arg == "--format"
            if i + 1 > length(args)
                error("--format requires a format argument (markdown or json)")
            end
            format_arg = args[i + 1]
            if !(format_arg in ["markdown", "json"])
                error("--format must be 'markdown' or 'json', got: $format_arg")
            end
            parsed["format"] = format_arg
            i += 2

        elseif arg == "--silent"
            parsed["silent"] = true
            i += 1

        else
            error("Unknown argument: $arg")
        end
    end

    return parsed
end

function show_help()
    println("""
    batch_analyze.jl - Batch Campaign Analysis CLI

    Usage:
        julia scripts/batch_analyze.jl --input <campaign_path> --output <report_path> [OPTIONS]

    Arguments:
        --input PATH      Path to campaign directory (required)
        --output PATH     Path for output report (required)
        --format FORMAT   Output format: markdown or json (default: markdown)
        --silent          Suppress all output except errors (optional)
        --help, -h        Show this help message

    Exit codes:
        0   Success
        1   Error (invalid arguments, campaign not found, processing error)

    Examples:
        # Basic batch analysis (markdown)
        julia scripts/batch_analyze.jl --input collected_experiments_20251004 --output report.md

        # JSON format
        julia scripts/batch_analyze.jl --input campaign_dir --output report.json --format json

        # Silent mode (no output)
        julia scripts/batch_analyze.jl --input campaign_dir --output report.md --silent

        # With nested output directory (auto-created)
        julia scripts/batch_analyze.jl --input campaign_dir --output reports/2025/campaign.md
    """)
end

function main()
    try
        # Parse arguments
        args = parse_args(ARGS)

        # Show help if requested
        if args["help"]
            show_help()
            exit(0)
        end

        # Validate required arguments
        if args["input"] === nothing
            @error "Missing required argument: --input"
            println("\nUse --help for usage information")
            exit(1)
        end

        if args["output"] === nothing
            @error "Missing required argument: --output"
            println("\nUse --help for usage information")
            exit(1)
        end

        campaign_path = args["input"]
        output_file = args["output"]
        format_arg = args["format"]
        silent = args["silent"]

        # Run batch analysis
        success, result = batch_analyze_campaign(
            campaign_path,
            output_file,
            silent=silent,
            return_stats=false,
            format=format_arg
        )

        if success
            if !silent
                println("\n✓ Batch analysis complete")
                println("  Report saved to: $result")
            end
            exit(0)
        else
            @error "Batch analysis failed: $result"
            exit(1)
        end

    catch e
        if isa(e, ErrorException) && occursin("Unknown argument", e.msg)
            @error e.msg
            println("\nUse --help for usage information")
            exit(1)
        elseif isa(e, ErrorException) && occursin("requires a path argument", e.msg)
            @error e.msg
            println("\nUse --help for usage information")
            exit(1)
        else
            @error "Unexpected error: $(sprint(showerror, e))"
            exit(1)
        end
    end
end

# Run main if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
