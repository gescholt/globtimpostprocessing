"""
Coverage analysis for LV4D experiments.

Identifies missing parameter combinations and generates gap-filling scripts.
"""

# ============================================================================
# Coverage Report Data Structure
# ============================================================================

"""
    ExperimentKey

A single experiment configuration identified by (GN, domain, degree, seed).
"""
struct ExperimentKey
    GN::Int
    domain::Float64
    degree::Int
    seed::Int
end

function Base.show(io::IO, key::ExperimentKey)
    print(io, "ExperimentKey(GN=$(key.GN), domain=$(key.domain), degree=$(key.degree), seed=$(key.seed))")
end

"""
    CoverageReport

Result of coverage analysis comparing expected vs actual experiments.

# Fields
- `expected::Set{ExperimentKey}`: Expected experiment configurations
- `found::Set{ExperimentKey}`: Actually found configurations
- `missing_keys::Vector{ExperimentKey}`: Missing configurations (sorted)
- `coverage_pct::Float64`: Percentage of expected experiments found
- `expected_params::NamedTuple`: The expected parameter ranges used for analysis
"""
struct CoverageReport
    expected::Set{ExperimentKey}
    found::Set{ExperimentKey}
    missing_keys::Vector{ExperimentKey}
    coverage_pct::Float64
    expected_params::NamedTuple
end

# ============================================================================
# Coverage Analysis
# ============================================================================

"""
    analyze_coverage(results_root::Union{String, Nothing}; kwargs...) -> CoverageReport

Analyze experiment coverage by comparing expected vs actual experiments.

# Arguments
- `results_root::Union{String, Nothing}`: Path to experiment results directory, or `nothing` to search all

# Keyword Arguments
- `expected_gn::Vector{Int}`: Expected GN values (default: [8, 12, 16])
- `expected_domains::Vector{Float64}`: Expected domain values (required)
- `expected_degrees::AbstractVector{Int}`: Expected degrees (default: 4:2:12)
- `expected_seeds::AbstractVector{Int}`: Expected seeds (default: [1])

# Returns
`CoverageReport` containing expected, found, and missing experiment configurations.

# Example
```julia
report = analyze_coverage(nothing;  # Search all results directories
    expected_gn = [8, 12, 16],
    expected_domains = [0.01, 0.05, 0.1],
    expected_degrees = 4:2:12,
    expected_seeds = 1:5
)
print_coverage_report(report)
```
"""
function analyze_coverage(results_root::Union{String, Nothing};
                          expected_gn::Vector{Int} = [8, 12, 16],
                          expected_domains::Vector{Float64},
                          expected_degrees::AbstractVector{Int} = 4:2:12,
                          expected_seeds::AbstractVector{Int} = [1])

    # 1. Build expected set
    expected = Set{ExperimentKey}()
    for gn in expected_gn
        for domain in expected_domains
            for degree in expected_degrees
                for seed in expected_seeds
                    push!(expected, ExperimentKey(gn, domain, degree, seed))
                end
            end
        end
    end

    # 2. Query actual experiments
    found = Set{ExperimentKey}()
    exp_dirs = find_experiments(results_root)

    for exp_dir in exp_dirs
        params = parse_experiment_name(basename(exp_dir))
        params === nothing && continue

        # Extract seed (default to 0 if not present)
        seed = something(params.seed, 0)

        # For experiments with degree range, add all degrees in the range
        for degree in params.degree_min:params.degree_max
            # Only add if degree matches expected (e.g., even degrees only)
            if degree in expected_degrees
                push!(found, ExperimentKey(params.GN, params.domain, degree, seed))
            end
        end
    end

    # 3. Compute missing
    missing_set = setdiff(expected, found)
    missing_keys = sort(collect(missing_set); by=k -> (k.GN, k.domain, k.degree, k.seed))

    # 4. Coverage percentage
    found_expected = length(intersect(expected, found))
    coverage_pct = length(expected) > 0 ? (found_expected / length(expected) * 100) : 100.0

    # Store expected params for reference
    expected_params = (
        gn = expected_gn,
        domains = expected_domains,
        degrees = collect(expected_degrees),
        seeds = collect(expected_seeds)
    )

    return CoverageReport(expected, found, missing_keys, coverage_pct, expected_params)
end

# ============================================================================
# Report Formatting
# ============================================================================

# Helper: format vector for user-friendly display (no Julia array syntax)
_format_list(v::AbstractVector) = join(v, ", ")

# Helper: format seed range compactly
function _format_seeds(seeds::Vector{Int})
    if length(seeds) == 1
        return string(seeds[1])
    elseif seeds == collect(minimum(seeds):maximum(seeds))
        return "$(minimum(seeds))-$(maximum(seeds))"
    else
        return join(seeds, ",")
    end
end

"""
    print_coverage_report(report::CoverageReport; max_missing::Int=50)

Print a formatted coverage report to terminal.

# Arguments
- `report::CoverageReport`: Coverage analysis result
- `max_missing::Int=50`: Maximum number of missing combinations to display
"""
function print_coverage_report(report::CoverageReport; max_missing::Int=50)
    params = report.expected_params

    println()
    println("="^60)
    println("Coverage Report")
    println("="^60)

    # Summary statistics
    n_expected = length(report.expected)
    n_found = length(intersect(report.expected, report.found))
    n_missing = length(report.missing_keys)

    # Infer step from degrees vector (assumes uniform spacing)
    deg_step = length(params.degrees) > 1 ? params.degrees[2] - params.degrees[1] : 2
    println()
    println("Checking: GN={$(_format_list(params.gn))} × domains={$(_format_list(params.domains))}")
    println("          degrees=$(first(params.degrees)):$deg_step:$(last(params.degrees)) × seeds=$(_format_seeds(params.seeds))")
    println()
    println("-"^60)

    @printf("Coverage: %.1f%% (%d/%d experiments)\n", report.coverage_pct, n_found, n_expected)

    if n_missing == 0
        println("\nAll expected experiments are present.")
        return
    end

    # Group missing by (GN, domain, degree) to show seed gaps compactly
    grouped = group_missing_by_config(report.missing_keys)

    println("\nMissing ($n_missing experiments in $(length(grouped)) config groups):")

    displayed = 0
    for ((gn, domain, degree), seeds) in sort(collect(grouped); by=first)
        displayed += 1
        if displayed > max_missing
            remaining = length(grouped) - max_missing
            println("  ... and $remaining more config groups")
            break
        end

        seed_str = "seeds=$(_format_seeds(seeds))"
        @printf("  GN=%-2d  domain=%-8.2e  degree=%-2d  %s\n",
                gn, domain, degree, seed_str)
    end

    println()
end

"""
    group_missing_by_config(missing_keys::Vector{ExperimentKey}) -> Dict

Group missing experiment keys by (GN, domain, degree), collecting seeds.

# Returns
Dict mapping (GN, domain, degree) tuples to vectors of missing seeds.
"""
function group_missing_by_config(missing_keys::Vector{ExperimentKey})
    grouped = Dict{Tuple{Int, Float64, Int}, Vector{Int}}()

    for key in missing_keys
        config = (key.GN, key.domain, key.degree)
        if !haskey(grouped, config)
            grouped[config] = Int[]
        end
        push!(grouped[config], key.seed)
    end

    # Sort seeds within each group
    for seeds in values(grouped)
        sort!(seeds)
    end

    return grouped
end

"""
    get_missing_combinations(report::CoverageReport) -> Vector{ExperimentKey}

Get the list of missing experiment configurations.
"""
function get_missing_combinations(report::CoverageReport)
    return report.missing_keys
end

# ============================================================================
# Gap-Filling Config Generation
# ============================================================================

"""
    generate_gap_filling_configs(report::CoverageReport;
                                 output_dir::String,
                                 degree_range_mode::Symbol=:single) -> Vector{String}

Generate TOML config files for missing experiment combinations.

# Arguments
- `report::CoverageReport`: Coverage analysis result

# Keyword Arguments
- `output_dir::String`: Directory to write config files

# Returns
Vector of paths to generated config files.

# Example
```julia
report = analyze_coverage(results_root; ...)
configs = generate_gap_filling_configs(report; output_dir="experiments/fill_gaps/")
```
"""
function generate_gap_filling_configs(report::CoverageReport;
                                      output_dir::String)

    if isempty(report.missing_keys)
        @info "No missing experiments - nothing to generate"
        return String[]
    end

    mkpath(output_dir)

    # Group missing by (GN, domain, degree) to batch seeds
    grouped = group_missing_by_config(report.missing_keys)

    generated_files = String[]

    for ((gn, domain, degree), seeds) in sort(collect(grouped); by=first)
        # Create config content
        config_content = _generate_config_toml(gn, domain, degree, seeds)

        # Generate filename
        domain_str = _format_domain_for_filename(domain)
        filename = "gap_GN$(gn)_dom$(domain_str)_deg$(degree).toml"
        filepath = joinpath(output_dir, filename)

        # Write file
        open(filepath, "w") do io
            print(io, config_content)
        end

        push!(generated_files, filepath)
    end

    @info "Generated $(length(generated_files)) config files in $output_dir"
    return generated_files
end

"""
    _generate_config_toml(gn, domain, degree, seeds) -> String

Generate TOML config content for a gap-filling experiment.
"""
function _generate_config_toml(gn::Int, domain::Float64, degree::Int, seeds::Vector{Int})
    # Format domain for display
    domain_str = @sprintf("%.2e", domain)

    # Seeds as batch
    seeds_str = if length(seeds) == 1
        "seed = $(seeds[1])"
    else
        # Format as range if consecutive, else as explicit list
        if seeds == collect(minimum(seeds):maximum(seeds))
            "seeds = \"$(minimum(seeds)):$(maximum(seeds))\""
        else
            "seeds = \"$(join(seeds, ","))\""
        end
    end

    return """
# Gap-filling config: GN=$gn, domain=$domain_str, degree=$degree
# Generated by LV4DAnalysis.analyze_coverage()

[experiment]
name = "gap_fill_GN$(gn)_dom$(_format_domain_for_filename(domain))_deg$(degree)"
description = "Fill gap in experiment coverage"

[grid]
GN = $gn
degree_range = "$degree:$degree"
basis = "chebyshev"

[domain]
size = $domain

[sampling]
$seeds_str

[output]
error_metric = "L2_norm"
"""
end

"""
    _format_domain_for_filename(domain::Float64) -> String

Format domain value for use in filenames (no special characters).
"""
function _format_domain_for_filename(domain::Float64)
    # Convert to scientific notation string, replace characters
    s = @sprintf("%.0e", domain)
    # Replace minus sign and plus sign in exponent
    s = replace(s, "e+" => "e")
    s = replace(s, "e-" => "em")
    return s
end

# ============================================================================
# Quick Analysis Functions
# ============================================================================

"""
    summarize_coverage(results_root::String; kwargs...)

Quick coverage summary without full report object.

Prints summary statistics and returns coverage percentage.
"""
function summarize_coverage(results_root::String; kwargs...)
    report = analyze_coverage(results_root; kwargs...)
    print_coverage_report(report)
    return report.coverage_pct
end
