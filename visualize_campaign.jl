#!/usr/bin/env julia

using Pkg
Pkg.activate(".")

using GlobtimPostProcessing
using CairoMakie
using DataFrames
using Statistics

# Load campaign results
campaign_path = "/Users/ghscholt/GlobalOptim/globtimcore/experiments/lotka_volterra_4d_study/configs_20251006_160051/hpc_results"
println("📂 Loading campaign results...")
results = load_campaign_results(campaign_path)

# Create figure
fig = Figure(size=(1600, 1200), fontsize=14)

# Extract sample ranges from metadata for labeling
ranges = [exp.metadata["sample_range"] for exp in results.experiments]
labels = ["Range $r" for r in ranges]

# 1. Critical points count comparison
ax1 = Axis(fig[1, 1:2],
    xlabel="Experiment",
    ylabel="Number of Critical Points",
    title="Critical Points Discovery vs Initial Range")

counts = [size(exp.critical_points, 1) for exp in results.experiments]
barplot!(ax1, 1:4, counts,
    color=:steelblue,
    strokecolor=:black, strokewidth=1)
ax1.xticks = (1:4, labels)

# Add value labels on bars
for (i, count) in enumerate(counts)
    text!(ax1, i, count, text=string(count),
        align=(:center, :bottom), offset=(0, 5))
end

# 2-5. Distribution of critical points in parameter space (2D projections)
# We'll show x1 vs x2, x1 vs x3, x1 vs x4, and x2 vs x3

ax2 = Axis(fig[2, 1],
    xlabel="x1 (prey growth rate)",
    ylabel="x2 (predation rate)",
    title="Parameter Space: x1-x2 Projection")

ax3 = Axis(fig[2, 2],
    xlabel="x1 (prey growth rate)",
    ylabel="x3 (predator death rate)",
    title="Parameter Space: x1-x3 Projection")

ax4 = Axis(fig[3, 1],
    xlabel="x1 (prey growth rate)",
    ylabel="x4 (predator efficiency)",
    title="Parameter Space: x1-x4 Projection")

ax5 = Axis(fig[3, 2],
    xlabel="x2 (predation rate)",
    ylabel="x3 (predator death rate)",
    title="Parameter Space: x2-x3 Projection")

colors = [:red, :blue, :green, :orange]
markers = [:circle, :diamond, :utriangle, :rect]

for (i, exp) in enumerate(results.experiments)
    cp = exp.critical_points

    # x1 vs x2
    scatter!(ax2, cp.x1, cp.x2,
        color=(colors[i], 0.4),
        marker=markers[i],
        markersize=8,
        label=labels[i])

    # x1 vs x3
    scatter!(ax3, cp.x1, cp.x3,
        color=(colors[i], 0.4),
        marker=markers[i],
        markersize=8,
        label=labels[i])

    # x1 vs x4
    scatter!(ax4, cp.x1, cp.x4,
        color=(colors[i], 0.4),
        marker=markers[i],
        markersize=8,
        label=labels[i])

    # x2 vs x3
    scatter!(ax5, cp.x2, cp.x3,
        color=(colors[i], 0.4),
        marker=markers[i],
        markersize=8,
        label=labels[i])
end

# Add legends
axislegend(ax2, position=:rb)

# 6. Objective value comparison
ax6 = Axis(fig[4, 1:2],
    xlabel="Experiment",
    ylabel="Objective Value (log scale)",
    title="Best Objective Values Found",
    yscale=log10)

# Find minimum z value for each experiment
min_z = [minimum(exp.critical_points.z) for exp in results.experiments]
max_z = [maximum(exp.critical_points.z) for exp in results.experiments]
mean_z = [Statistics.mean(exp.critical_points.z) for exp in results.experiments]

scatter!(ax6, 1:4, min_z,
    color=:green, markersize=15, marker=:diamond,
    label="Best (minimum)")
scatter!(ax6, 1:4, mean_z,
    color=:blue, markersize=12, marker=:circle,
    label="Mean")
scatter!(ax6, 1:4, max_z,
    color=:red, markersize=10, marker=:utriangle,
    label="Worst (maximum)")

ax6.xticks = (1:4, labels)
axislegend(ax6, position=:rt)

# Overall title
Label(fig[0, :],
    "Lotka-Volterra 4D: Impact of Initial Sampling Range on Critical Point Discovery",
    fontsize=20, font=:bold)

# Display
display(fig)

# Keep window open
println("\n✅ Visualization complete!")
println("Press Enter to close window...")
readline()
