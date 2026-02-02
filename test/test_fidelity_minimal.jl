"""
Minimal Landscape Fidelity Test (without CriticalPointClassification dependency)
"""

using LinearAlgebra
using Statistics
using DataFrames
using Printf

# Load LandscapeFidelity module
include("src/LandscapeFidelity.jl")

println("="^70)
println("Minimal Landscape Fidelity Tests")
println("="^70)

# Test 1: Objective Proximity
println("\n### Test 1: Objective Proximity Check ###")
f(x) = sum((x .- 0.5).^2)
x_star = [0.48, 0.52, 0.49, 0.51]
x_min = [0.50, 0.50, 0.50, 0.50]

result = check_objective_proximity(x_star, x_min, f, tolerance=0.05)
println("Polynomial minimum: $x_star")
println("Refined minimum:    $x_min")
println("Same basin: $(result.is_same_basin)")
println("Relative difference: $(round(result.metric, digits=6))")
@assert result.is_same_basin "Test 1 failed: should be same basin"
println("✅ Test 1 PASSED")

# Test 2: Hessian Basin (without ForwardDiff - manual Hessian)
println("\n### Test 2: Hessian Basin Check (Manual Hessian) ###")
H = [2.0 0.0 0.0 0.0;
     0.0 2.0 0.0 0.0;
     0.0 0.0 2.0 0.0;
     0.0 0.0 0.0 2.0]  # Hessian of quadratic

result_hess = check_hessian_basin(x_star, x_min, f, H)
println("Inside basin: $(result_hess.is_same_basin)")
println("Distance: $(round(result_hess.distance, digits=6))")
println("Basin radius: $(round(result_hess.basin_radius, digits=6))")
println("Relative distance: $(round(result_hess.metric, digits=6))")
@assert result_hess.is_same_basin "Test 2 failed: should be inside basin"
println("✅ Test 2 PASSED")

# Test 3: Composite Assessment
println("\n### Test 3: Composite Assessment ###")
result_composite = assess_landscape_fidelity(x_star, x_min, f, hessian_min=H)
println("Overall same basin: $(result_composite.is_same_basin)")
println("Confidence: $(round(100*result_composite.confidence, digits=1))%")
for c in result_composite.criteria
    println("  $(c.name): $(c.passed) (metric = $(round(c.metric, digits=6)))")
end
@assert result_composite.is_same_basin "Test 3 failed: composite assessment should pass"
@assert result_composite.confidence >= 0.5 "Test 3 failed: low confidence"
println("✅ Test 3 PASSED")

# Test 4: Batch Assessment
println("\n### Test 4: Batch Assessment ###")
df = DataFrame(
    x1 = [0.48, 0.21, 0.79],
    x2 = [0.52, 0.19, 0.81],
    z = [f([0.48, 0.52]), f([0.21, 0.19]), f([0.79, 0.81])]
)

# Mock refined points
refined = [[0.50, 0.50], [0.20, 0.20], [0.80, 0.80]]
hessians = [H[1:2,1:2], H[1:2,1:2], H[1:2,1:2]]

# Temporarily add classification column for batch function
df[!, :point_classification] = fill("minimum", 3)

f2(x) = sum((x .- [0.5, 0.5]).^2)  # 2D version
result_batch = batch_assess_fidelity(df, refined, f2, hessian_min_list=hessians)

println("Processed $(nrow(result_batch)) points")
println("Valid basins: $(sum(result_batch.is_same_basin))/$(nrow(result_batch))")
for (i, row) in enumerate(eachrow(result_batch))
    status = row.is_same_basin ? "✅" : "❌"
    println("  Point $i: $status (confidence = $(round(row.fidelity_confidence, digits=2)))")
end
@assert nrow(result_batch) == 3 "Test 4 failed: wrong number of results"
println("✅ Test 4 PASSED")

# Test 5: Degenerate case (saddle point)
println("\n### Test 5: Edge Case - Degenerate Hessian ###")
f_saddle(x) = x[1]^2 - x[2]^2
H_saddle = [2.0 0.0; 0.0 -2.0]  # One negative eigenvalue
x_s = [0.01, 0.01]
x_m = [0.0, 0.0]

result_deg = check_hessian_basin(x_s, x_m, f_saddle, H_saddle)
println("Degenerate case (saddle): is_same_basin = $(result_deg.is_same_basin)")
@assert !result_deg.is_same_basin "Test 5 failed: saddle should not be classified as basin"
println("✅ Test 5 PASSED")

println("\n" * "="^70)
println("ALL TESTS PASSED ✅")
println("="^70)
println("\nLandscape Fidelity module is working correctly!")
println("Key functions tested:")
println("  ✅ check_objective_proximity()")
println("  ✅ estimate_basin_radius()")
println("  ✅ check_hessian_basin()")
println("  ✅ assess_landscape_fidelity()")
println("  ✅ batch_assess_fidelity()")
