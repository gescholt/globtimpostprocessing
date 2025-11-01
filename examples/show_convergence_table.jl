#!/usr/bin/env julia

using CSV, DataFrames, JSON3, Printf, Statistics, LinearAlgebra

function load_config(exp_path)
    config_file = joinpath(exp_path, "experiment_config.json")
    isfile(config_file) ? JSON3.read(read(config_file, String)) : nothing
end

function load_all_critical_points(exp_path)
    csv_files = filter(f -> startswith(basename(f), "critical_points_deg_"), readdir(exp_path, join=true))
    results = Dict{Int, DataFrame}()
    for csv_file in csv_files
        m = match(r"deg_(\d+)\.csv", basename(csv_file))
        if m !== nothing
            degree = parse(Int, m[1])
            df = CSV.read(csv_file, DataFrame)
            results[degree] = df
        end
    end
    return results
end

function param_distance(cp_row, p_true)
    p_found = [cp_row.x1, cp_row.x2, cp_row.x3, cp_row.x4]
    return norm(p_found .- p_true)
end

campaign_path = length(ARGS) >= 1 ? ARGS[1] : "../globtimcore/experiments/lotka_volterra_4d_study/configs_20251008_215942/hpc_results"

exp_dirs = filter(isdir, readdir(campaign_path, join=true))
sort!(exp_dirs)

exp_data = []
for exp_path in exp_dirs
    config = load_config(exp_path)
    config === nothing && continue

    p_true = haskey(config, :p_true) ? collect(config.p_true) : collect(config.p_center)
    sample_range = haskey(config, :domain_range) ? config.domain_range : config.sample_range
    cp_by_degree = load_all_critical_points(exp_path)

    push!(exp_data, (
        name = basename(exp_path),
        sample_range = sample_range,
        p_true = p_true,
        cp_by_degree = cp_by_degree
    ))
end

println("\n📉 CONVERGENCE ANALYSIS: Best Parameter Distance vs Degree")
println("  Campaign: $(basename(dirname(campaign_path)))")
println("  Total experiments: $(length(exp_data))")
println("="^120)

@printf("%-8s", "Degree")
for (i, exp) in enumerate(exp_data)
    short_name = "±$(exp.sample_range) #$i"
    @printf(" | %15s", short_name)
end
println()
println("-"^(8 + length(exp_data) * 18))

all_degrees = Set{Int}()
for exp in exp_data
    union!(all_degrees, keys(exp.cp_by_degree))
end
degrees = sort(collect(all_degrees))

for deg in degrees
    @printf("%-8d", deg)
    for exp in exp_data
        if haskey(exp.cp_by_degree, deg)
            df = exp.cp_by_degree[deg]
            if nrow(df) > 0
                distances = [param_distance(row, exp.p_true) for row in eachrow(df)]
                min_dist = minimum(distances)
                @printf(" | %15.6f", min_dist)
            else
                @printf(" | %15s", "N/A")
            end
        else
            @printf(" | %15s", "-")
        end
    end
    println()
end

println("\n" * "="^120)
