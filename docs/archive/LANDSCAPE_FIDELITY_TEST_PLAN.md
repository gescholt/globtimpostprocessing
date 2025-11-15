# Landscape Fidelity Testing Plan

## Overview

New code in branch `claude/classify-critical-points-01X8GGvTCxt6G6teFHGaDwGA` adds landscape fidelity assessment to `globtimpostprocessing`.

**Purpose**: Assess whether polynomial approximant critical points correctly identify objective function basins of attraction.

**Location**:
- Source: `src/LandscapeFidelity.jl`
- Demo: `examples/landscape_fidelity_demo.jl`
- Exports: Added to `src/GlobtimPostProcessing.jl`

---

## Architectural Compliance ✅

### Package Responsibility Check

| Aspect | Expected (globtimpostprocessing) | Actual | Status |
|--------|----------------------------------|--------|--------|
| **Primary Function** | Statistical analysis | Computing basin membership metrics | ✅ PASS |
| **Dependencies** | DataFrames, Statistics, LinearAlgebra | Same + optional ForwardDiff | ✅ PASS |
| **NO Plotting** | Must not use Makie/Plots | No plotting dependencies | ✅ PASS |
| **NO Core Algorithms** | Must not do optimization | Uses objective function only for evaluation | ✅ PASS |
| **Analysis Focus** | Compute statistics, quality metrics | Computes fidelity metrics and statistics | ✅ PASS |

**Verdict**: ✅ **COMPLIANT** - This code correctly belongs in `globtimpostprocessing`

### What the Code Does (Analysis, Not Algorithms)

1. **Computes distance metrics** - Euclidean distance, relative objective difference
2. **Estimates basin radius** - Using Hessian eigenvalues (mathematical analysis)
3. **Assesses basin membership** - Statistical checks with confidence scores
4. **Batch processing** - Aggregates fidelity assessments across multiple points

**What it does NOT do**:
- ❌ Run optimization (assumes you provide `x_min` from external optimizer)
- ❌ Solve for critical points (assumes you provide `x_star` from polynomial)
- ❌ Create plots (purely numerical assessment)

---

## Integration Points with Existing Workflow

### Current Workflow (Before)
```julia
# 1. Run experiment (globtimcore)
using Globtim
experiment = StandardExperiment(...)
results = run_experiment(experiment)  # Produces critical_points_deg_N.csv

# 2. Analyze (globtimpostprocessing)
using GlobtimPostProcessing
loaded = load_experiment_results("path/to/results")
classify_all_critical_points!(loaded.critical_points)  # min/max/saddle

# 3. Visualize (globtimplots)
using GlobtimPlots
fig = plot_critical_points(loaded.critical_points)
```

### New Workflow (With Fidelity Assessment)
```julia
# 1-2. Same as before (load + classify)

# 3. NEW: Assess landscape fidelity
using Optim  # For local refinement

# Define objective (from globtimcore registry or custom)
f = Globtim.create_objective_from_model("lotka_volterra_4d")

# For each polynomial minimum, run local optimization
df_minima = filter(row -> row.point_classification == "minimum", loaded.critical_points)
refined_points = []
for row in eachrow(df_minima)
    x_star = [row.x1, row.x2, row.x3, row.x4]
    result = optimize(f, x_star, BFGS())
    push!(refined_points, result.minimizer)
end

# Assess fidelity (batch)
fidelity_df = batch_assess_fidelity(df_minima, refined_points, f)

# Analyze results
valid_basins = sum(fidelity_df.is_same_basin)
total_minima = nrow(fidelity_df)
println("Landscape fidelity: $(valid_basins)/$(total_minima) = $(100*valid_basins/total_minima)%")

# 4. Visualize (globtimplots - potential new feature)
# Could add: plot_fidelity_comparison(fidelity_df)
```

---

## Test Plan

### Phase 1: Local Environment Testing (Development Machine)

#### Test 1.1: Package Installation & Import
**Objective**: Verify new code compiles and exports work

```bash
cd /Users/ghscholt/GlobalOptim/globtimpostprocessing
git checkout claude/classify-critical-points-01X8GGvTCxt6G6teFHGaDwGA
```

```julia
# In Julia REPL
using Pkg
Pkg.activate("/Users/ghscholt/GlobalOptim/globtimpostprocessing")
Pkg.instantiate()  # Install dependencies

# Test import
using GlobtimPostProcessing

# Verify exports
@assert isdefined(GlobtimPostProcessing, :check_objective_proximity)
@assert isdefined(GlobtimPostProcessing, :check_hessian_basin)
@assert isdefined(GlobtimPostProcessing, :assess_landscape_fidelity)
@assert isdefined(GlobtimPostProcessing, :batch_assess_fidelity)

println("✅ All exports available")
```

**Expected Result**: No compilation errors, all functions exported

---

#### Test 1.2: Demo Execution (No ForwardDiff)
**Objective**: Test basic functionality without optional dependency

```julia
# In Julia REPL (continued)
include("examples/landscape_fidelity_demo.jl")

# Should print ForwardDiff availability status
# Expected: "✗ ForwardDiff not available - install with: ..."

# Run demos (will skip Hessian checks)
demo_1_simple_quadratic()
demo_2_multiple_minima()
demo_4_batch_processing()
```

**Expected Results**:
- Demos run without errors
- Objective proximity checks execute
- Hessian checks skipped with informative messages
- Clear output showing basin membership assessments

**Validation Checklist**:
- [ ] `demo_1_simple_quadratic()` shows "SAME BASIN"
- [ ] `demo_2_multiple_minima()` correctly identifies good/bad matches
- [ ] `demo_4_batch_processing()` computes fidelity for 5 points
- [ ] No error messages (warnings about ForwardDiff OK)

---

#### Test 1.3: Demo Execution (With ForwardDiff)
**Objective**: Test full functionality with automatic differentiation

```julia
# Install ForwardDiff
using Pkg
Pkg.add("ForwardDiff")

# Reload demo (or restart Julia)
include("examples/landscape_fidelity_demo.jl")

# Should print: "✓ ForwardDiff available - can compute Hessians automatically"

# Run all demos (including Hessian checks)
demo_1_simple_quadratic()
demo_2_multiple_minima()
demo_4_batch_processing()
```

**Expected Results**:
- All demos execute Hessian basin checks
- Confidence scores computed using both criteria
- Basin radius estimates shown
- Relative distance metrics displayed

**Validation Checklist**:
- [ ] `demo_1`: Shows both objective proximity AND Hessian basin results
- [ ] `demo_1`: Confidence = 100% (both criteria agree)
- [ ] `demo_2`: Different confidence levels for good/bad matches
- [ ] `demo_4`: Hessian metrics appear in results (not `missing`)

---

#### Test 1.4: Real Experiment Integration
**Objective**: Test on actual globtimcore experiment results

**Prerequisites**:
- Need a completed experiment with `critical_points_deg_N.csv`
- Example: `/Users/ghscholt/globtim_results/lotka_volterra_4d_test/`

```julia
using Globtim
using GlobtimPostProcessing
using Optim
using ForwardDiff

# Load real experiment
experiment_path = "/Users/ghscholt/globtim_results/lotka_volterra_4d_test/"
result = load_experiment_results(experiment_path)

# Classify critical points
classify_all_critical_points!(result.critical_points)

# Get objective function
f = Globtim.create_objective_from_model("lotka_volterra_4d")

# Test on first minimum
df = result.critical_points
minima = filter(row -> row.point_classification == "minimum", df)

if nrow(minima) > 0
    first_min = first(eachrow(minima))
    x_star = Float64[first_min.x1, first_min.x2, first_min.x3, first_min.x4]

    # Run local optimization
    opt_result = optimize(f, x_star, BFGS())
    x_min = opt_result.minimizer

    # Compute Hessian
    H = ForwardDiff.hessian(f, x_min)

    # Assess fidelity
    fidelity = assess_landscape_fidelity(x_star, x_min, f, hessian_min=H)

    println("Polynomial minimum: $x_star")
    println("Refined minimum:    $x_min")
    println("Same basin: $(fidelity.is_same_basin)")
    println("Confidence: $(fidelity.confidence)")

    for c in fidelity.criteria
        println("  $(c.name): $(c.passed) (metric = $(c.metric))")
    end
else
    @warn "No minima found in experiment - cannot test real integration"
end
```

**Expected Results**:
- Loads experiment successfully
- Optimizes from polynomial minimum
- Computes fidelity assessment
- Shows meaningful metrics

**Validation Checklist**:
- [ ] Experiment loads without errors
- [ ] Optimization converges
- [ ] Fidelity assessment runs without errors
- [ ] Results are interpretable (confidence in [0, 1])

---

### Phase 2: Batch Processing Test

#### Test 2.1: Batch Assessment on Multiple Minima
**Objective**: Test batch processing function on real experiment

```julia
using Globtim
using GlobtimPostProcessing
using Optim
using ForwardDiff

# Load experiment
experiment_path = "/Users/ghscholt/globtim_results/lotka_volterra_4d_test/"
result = load_experiment_results(experiment_path)
classify_all_critical_points!(result.critical_points)

# Get objective
f = Globtim.create_objective_from_model("lotka_volterra_4d")

# Filter minima
df = result.critical_points
minima_df = filter(row -> row.point_classification == "minimum", df)

println("Found $(nrow(minima_df)) polynomial minima")

# Run local optimization for each minimum
refined_points = []
hessians = []

for row in eachrow(minima_df)
    x_star = Float64[row.x1, row.x2, row.x3, row.x4]

    # Optimize
    opt_result = optimize(f, x_star, BFGS())
    push!(refined_points, opt_result.minimizer)

    # Compute Hessian
    H = ForwardDiff.hessian(f, opt_result.minimizer)
    push!(hessians, H)
end

# Batch assess fidelity
fidelity_results = batch_assess_fidelity(minima_df, refined_points, f,
                                         hessian_min_list=hessians)

# Analyze results
println("\n" * "="^70)
println("Batch Fidelity Assessment Results")
println("="^70)

for (i, row) in enumerate(eachrow(fidelity_results))
    status = row.is_same_basin ? "✅" : "❌"
    println("Point $i: $status confidence=$(round(row.fidelity_confidence, digits=2))")
    println("  Obj metric: $(round(row.objective_proximity_metric, digits=6))")
    println("  Hess metric: $(round(row.hessian_basin_metric, digits=6))")
end

# Summary statistics
valid_basins = sum(fidelity_results.is_same_basin)
total = nrow(fidelity_results)
fidelity_rate = 100 * valid_basins / total

println("\n" * "="^70)
println("Summary: $valid_basins / $total minima in same basin")
println("Landscape Fidelity: $(round(fidelity_rate, digits=1))%")
println("="^70)
```

**Expected Results**:
- Processes all minima without errors
- Returns DataFrame with fidelity columns
- Shows interpretable summary statistics

**Validation Checklist**:
- [ ] Batch function processes all points
- [ ] Output DataFrame has new columns: `is_same_basin`, `fidelity_confidence`, metrics
- [ ] No `missing` values in metrics (with Hessians provided)
- [ ] Fidelity rate is reasonable (depends on experiment quality)

---

### Phase 3: Edge Cases & Error Handling

#### Test 3.1: Degenerate Cases
**Objective**: Verify handling of pathological inputs

```julia
using GlobtimPostProcessing
using LinearAlgebra

# Test Case 1: Saddle point (negative eigenvalue)
f_saddle(x) = x[1]^2 - x[2]^2  # Saddle at origin
x_star = [0.01, 0.01]
x_min = [0.0, 0.0]
H_saddle = [2.0 0.0; 0.0 -2.0]  # One negative eigenvalue

result = check_hessian_basin(x_star, x_min, f_saddle, H_saddle)
println("Saddle point test: is_same_basin = $(result.is_same_basin)")
# Expected: false (not a minimum, basin_radius = NaN)

# Test Case 2: Flat region (zero eigenvalue)
f_flat(x) = x[1]^2  # Flat in x2 direction
x_star = [0.01, 0.5]
x_min = [0.0, 0.0]
H_flat = [2.0 0.0; 0.0 0.0]  # Degenerate

result = check_hessian_basin(x_star, x_min, f_flat, H_flat)
println("Flat region test: is_same_basin = $(result.is_same_basin)")
# Expected: false (degenerate minimum)

# Test Case 3: Global minimum (f_min ≈ 0)
f_global(x) = sum(x.^2)
x_star = [0.01, 0.01]
x_min = [0.0, 0.0]
H_global = [2.0 0.0; 0.0 2.0]

result = assess_landscape_fidelity(x_star, x_min, f_global, hessian_min=H_global)
println("Global minimum test: confidence = $(result.confidence)")
# Expected: High confidence, uses absolute threshold for basin radius
```

**Validation Checklist**:
- [ ] Saddle points handled gracefully (returns false, no crash)
- [ ] Degenerate Hessians handled (returns NaN basin radius)
- [ ] Global minima (f_min ≈ 0) handled correctly
- [ ] No exceptions thrown for edge cases

---

#### Test 3.2: Dimension Mismatch
**Objective**: Verify input validation

```julia
using GlobtimPostProcessing

f(x) = sum(x.^2)

# Mismatched dimensions
x_star = [0.1, 0.2]  # 2D
x_min = [0.0, 0.0, 0.0]  # 3D

try
    result = check_objective_proximity(x_star, x_min, f)
    println("❌ Should have thrown error for dimension mismatch")
catch e
    println("✅ Caught expected error: $e")
end
```

**Expected Result**: Appropriate error message for dimension mismatch

---

### Phase 4: Performance Testing

#### Test 4.1: Scalability Check
**Objective**: Assess performance on large numbers of critical points

```julia
using GlobtimPostProcessing
using BenchmarkTools
using DataFrames

# Generate synthetic critical points
n_points = 100
f(x) = sum((x .- 0.5).^2)

# Create DataFrame
df = DataFrame(
    x1 = rand(n_points),
    x2 = rand(n_points),
    x3 = rand(n_points),
    x4 = rand(n_points),
    hessian_eigenvalue_1 = fill(2.0, n_points),
    hessian_eigenvalue_2 = fill(2.0, n_points),
    hessian_eigenvalue_3 = fill(2.0, n_points),
    hessian_eigenvalue_4 = fill(2.0, n_points),
    point_classification = fill("minimum", n_points)
)

# Generate refined points (all converge to [0.5, 0.5, 0.5, 0.5])
refined = [fill(0.5, 4) for _ in 1:n_points]

# Benchmark batch assessment (without Hessian)
@time fidelity_results = batch_assess_fidelity(df, refined, f)

println("Processed $n_points points")
println("Time per point: $(round((@elapsed batch_assess_fidelity(df, refined, f)) / n_points * 1000, digits=2)) ms")
```

**Expected Results**:
- Processes 100 points in < 1 second (without Hessian)
- Linear scaling with number of points
- No memory issues

**Validation Checklist**:
- [ ] Completes in reasonable time
- [ ] Memory usage scales linearly
- [ ] No performance degradation

---

### Phase 5: Documentation & Usability

#### Test 5.1: Help System
**Objective**: Verify documentation is accessible

```julia
using GlobtimPostProcessing

# Check docstrings
?check_objective_proximity
?check_hessian_basin
?assess_landscape_fidelity
?batch_assess_fidelity
```

**Validation Checklist**:
- [ ] All functions have docstrings
- [ ] Docstrings include examples
- [ ] Parameters are documented
- [ ] Return types are clear

---

#### Test 5.2: Demo Clarity
**Objective**: Ensure demos are beginner-friendly

```bash
# Run demos and check output clarity
julia -e 'include("examples/landscape_fidelity_demo.jl"); demo_1_simple_quadratic()'
```

**Validation Checklist**:
- [ ] Clear section headers
- [ ] Interpretation guidance provided
- [ ] Results are easy to understand
- [ ] Next steps are suggested

---

## Integration Test Summary

### Test Execution Checklist

| Test | Description | Status | Notes |
|------|-------------|--------|-------|
| 1.1 | Package installation | ⬜ | Compile & import |
| 1.2 | Demos (no ForwardDiff) | ⬜ | Basic functionality |
| 1.3 | Demos (with ForwardDiff) | ⬜ | Full functionality |
| 1.4 | Real experiment | ⬜ | Integration test |
| 2.1 | Batch processing | ⬜ | Multiple minima |
| 3.1 | Edge cases | ⬜ | Degenerate inputs |
| 3.2 | Error handling | ⬜ | Invalid inputs |
| 4.1 | Performance | ⬜ | Scalability |
| 5.1 | Documentation | ⬜ | Help system |
| 5.2 | Demo clarity | ⬜ | User experience |

---

## Potential Issues & Mitigation

### Issue 1: ForwardDiff Dependency
**Problem**: Optional dependency might not be available
**Mitigation**:
- ✅ Code already handles gracefully with try-catch
- ✅ Demos skip Hessian checks with clear messaging
- Recommendation: Add ForwardDiff to Project.toml as optional dependency

### Issue 2: Optimization Required
**Problem**: Users need to run local optimization separately
**Mitigation**:
- Document workflow clearly in demo
- Consider future enhancement: Add optional optimization wrapper

### Issue 3: Objective Function Availability
**Problem**: Users need access to objective function definition
**Mitigation**:
- Use `Globtim.create_objective_from_model()` for standard test functions
- Document how to provide custom objectives

---

## Success Criteria

Code is ready for merging if:
1. ✅ All Phase 1 tests pass (import, demos, real experiment)
2. ✅ All Phase 2 tests pass (batch processing)
3. ✅ Phase 3 edge cases handled gracefully
4. ✅ Performance is acceptable (Phase 4)
5. ✅ Documentation is complete (Phase 5)

---

## Next Steps After Testing

1. **Merge to master** if all tests pass
2. **Update CHANGELOG.md** with new features
3. **Add to README.md** usage example
4. **Consider plotting integration** (globtimplots):
   - Add `plot_fidelity_comparison()` to visualize basin membership
   - Show confidence scores visually
5. **HPC integration**: Test on cluster experiments with large numbers of critical points

---

## Files Modified/Added

### New Files
- `src/LandscapeFidelity.jl` (498 lines)
- `examples/landscape_fidelity_demo.jl` (405 lines)

### Modified Files
- `src/GlobtimPostProcessing.jl` (added exports)

### Documentation Needed
- Update `README.md` with landscape fidelity section
- Update `CHANGELOG.md` with new feature
- Consider adding to `docs/` if documentation exists
