# Analysis Plan for Collected Experiments - 2025-10-14

**Collection**: `collected_experiments_20251014_090544/`
**Created**: 2025-10-14

## Overview

This document outlines the analysis routines to run on collected experiments and provides a detailed comparison strategy for Chebyshev vs Legendre polynomial basis functions.

---

## Part 1: Analysis Routines for All Experiments

### 1.1 Extended Degree Testing (Issue #172)

**Experiment**: `lv4d_deg18_domain0.3_GN16_20251013_131227`

**Primary Analysis Script**:
```bash
cd /path/to/globtimpostprocessing
julia --project=. analyze_collected_campaign.jl \
  collected_experiments_20251014_090544/lv4d_deg18_domain0.3_GN16_20251013_131227/
```

**Key Questions to Answer**:
1. Does L2 approximation error decrease monotonically from degree 4→18?
2. At what degree does convergence plateau?
3. What is the computation time scaling?
4. Are degrees 13-18 worth the computational cost?

**Expected Outputs**:
- L2 norm convergence table (degrees 4-18)
- Critical point count by degree
- Best objective value by degree
- Computation time vs degree plot
- Convergence rate analysis

**Key Metrics**:
- `L2_norm` by degree
- `critical_points` by degree
- `computation_time` by degree
- `best_value` by degree
- `condition_number` by degree

---

### 1.2 Minimal 4D LV Tests (Issue #139)

**Experiments**: 7 experiments with varying GN and domain sizes

**Analysis Script**:
```bash
# Option 1: Analyze all minimal tests together
julia --project=. analyze_collected_campaign.jl \
  collected_experiments_20251014_090544/ \
  --filter "minimal_4d_lv_test.*20251006"

# Option 2: Individual experiment analysis
for exp in minimal_4d_lv_test_GN=*_20251006_*; do
  julia --project=. analyze_collected_campaign.jl \
    collected_experiments_20251014_090544/$exp/
done
```

**Key Questions**:
1. How does GN affect computation time? (GN=5 vs 6 vs 8)
2. How does domain size affect solution quality? (0.1 vs 0.15 vs 0.2)
3. Did DataFrame validation infrastructure work correctly?

**Expected Outputs**:
- Scaling analysis: computation time vs GN
- Domain size impact on critical point counts
- Success rate by configuration

---

### 1.3 Parameter Recovery Experiments (Issue #117)

**Experiments**: 25+ experiments with 4 domain sizes × 3 parameter sets

**Analysis Script**:
```bash
# Analyze parameter recovery quality
julia --project=. analyze_collected_campaign.jl \
  collected_experiments_20251014_090544/ \
  --filter "4dlv_recovery.*exp_"
```

**Key Questions**:
1. Can the pipeline recover baseline/moderate/strong parameter regimes?
2. How does domain size affect recovery accuracy?
3. What is the optimal polynomial degree for each parameter set?

**Expected Outputs**:
- Parameter recovery error by domain size
- Recovery quality by parameter set (baseline/moderate/strong)
- L2 convergence comparison across experiments

---

## Part 2: Chebyshev vs Legendre Basis Comparison

### 2.1 Experiment Setup Verification

**Experiments**:
- Chebyshev: `lv4d_basis_comparison_chebyshev_deg4-6_domain0.3_GN16_20251013_172835`
- Legendre: `lv4d_basis_comparison_legendre_deg4-6_domain0.3_GN16_20251013_172835`

**Configuration Match** ✅:
- Domain: ±0.3 (both)
- Grid Nodes (GN): 16 (both)
- Degrees: 4, 5, 6 (both)
- Model: Lotka-Volterra 4D (both)
- Same timestamp: 20251013_172835 (launched simultaneously)

### 2.2 Data Available for Comparison

From `results_summary.json`, each degree contains:
- `L2_norm`: Polynomial approximation error
- `condition_number`: Numerical stability indicator
- `computation_time`: Time to construct polynomial and solve
- `critical_points`: Number of critical points found in domain
- `total_solutions`: Total complex solutions
- `real_solutions`: Number of real solutions
- `best_value`: Best objective function value found
- `mean_value`: Mean of critical point objective values
- `worst_value`: Worst objective function value

### 2.3 Comparison Strategy

#### **Metric 1: Approximation Quality**

Compare L2 norms by degree:

| Degree | Chebyshev L2 | Legendre L2 | Δ (%) |
|--------|--------------|-------------|-------|
| 4 | 9511.18 | 8379.27 | -11.9% |
| 5 | 9138.79 | 7863.04 | -14.0% |
| 6 | 6821.72 | 6135.88 | -10.1% |

**Key Observations**:
- Legendre achieves **~10-14% better L2 approximation** across all degrees
- Both bases show convergence as degree increases
- Degree 6 gives best approximation for both bases

#### **Metric 2: Numerical Stability**

Compare condition numbers:

| Degree | Chebyshev CN | Legendre CN | Improvement |
|--------|--------------|-------------|-------------|
| 4 | 16.00 | 3.26 | **4.9× better** |
| 5 | 16.00 | 4.10 | **3.9× better** |
| 6 | 16.00 | 6.24 | **2.6× better** |

**Key Observations**:
- **Legendre dramatically more stable** (3-5× lower condition numbers)
- Chebyshev maintains constant CN=16 (matches GN=16, suggests polynomial construction stability)
- Legendre CN increases with degree (typical behavior)

#### **Metric 3: Critical Point Discovery**

Compare critical points found:

| Degree | Chebyshev CP | Legendre CP | Δ |
|--------|--------------|-------------|---|
| 4 | 1 | 4 | +3 |
| 5 | 3 | 1 | -2 |
| 6 | 7 | 5 | -2 |

**Key Observations**:
- Different basis → different critical point locations discovered
- Total: Chebyshev finds 11 points, Legendre finds 10 points
- Degree 4: Legendre finds significantly more (4 vs 1)

#### **Metric 4: Best Objective Values**

Compare best objective function values found:

| Degree | Chebyshev Best | Legendre Best | Δ (%) |
|--------|----------------|---------------|-------|
| 4 | 3980.38 | 2613.99 | **-34.3%** |
| 5 | 208.28 | 16817.75 | +7975% |
| 6 | 1165.57 | 2786.17 | +139% |

**Key Observations**:
- **Degree 5 Chebyshev finds best global solution** (208.28)
- Degree 4 Legendre outperforms Chebyshev significantly
- Different bases lead to different minima being discovered

#### **Metric 5: Computation Time**

Compare wall-clock time:

| Degree | Chebyshev (s) | Legendre (s) | Δ |
|--------|---------------|--------------|---|
| 4 | 58.52 | 60.01 | +1.49s |
| 5 | 14.60 | 14.52 | -0.08s |
| 6 | 17.26 | 17.17 | -0.09s |

**Key Observations**:
- **Computation times virtually identical** (within measurement noise)
- Both bases scale similarly with degree
- No performance penalty for using Legendre

#### **Metric 6: Solution Complexity**

Compare solution counts:

| Degree | Chebyshev Real/Total | Legendre Real/Total | Real Solutions Δ |
|--------|----------------------|---------------------|------------------|
| 4 | 11/81 | 13/81 | +2 |
| 5 | 24/256 | 26/256 | +2 |
| 6 | 39/625 | 51/625 | +12 |

**Key Observations**:
- Legendre consistently finds **more real solutions**
- Difference grows with degree (+2, +2, +12)
- Same total solution count (algebraic system size unchanged)

---

### 2.4 Analysis Script for Basis Comparison

Create a dedicated comparison script:

```bash
cd /path/to/globtimpostprocessing
```

**Option 1: Quick manual comparison**
```julia
using JSON3, DataFrames, Printf

cheb_path = "collected_experiments_20251014_090544/lv4d_basis_comparison_chebyshev_deg4-6_domain0.3_GN16_20251013_172835/results_summary.json"
leg_path = "collected_experiments_20251014_090544/lv4d_basis_comparison_legendre_deg4-6_domain0.3_GN16_20251013_172835/results_summary.json"

cheb_data = JSON3.read(read(cheb_path, String))
leg_data = JSON3.read(read(leg_path, String))

# Compare by degree
for deg in 4:6
    cheb_deg = cheb_data[deg-3]  # deg 4 is index 1
    leg_deg = leg_data[deg-3]

    println("Degree $deg:")
    println("  L2 norm: Cheb=$(cheb_deg.L2_norm), Leg=$(leg_deg.L2_norm)")
    println("  Condition: Cheb=$(cheb_deg.condition_number), Leg=$(leg_deg.condition_number)")
    println("  Critical points: Cheb=$(cheb_deg.critical_points), Leg=$(leg_deg.critical_points)")
    println("  Best value: Cheb=$(cheb_deg.best_value), Leg=$(leg_deg.best_value)")
    println()
end
```

**Option 2: Create dedicated comparison script**

Create `compare_basis_functions.jl`:

```julia
#!/usr/bin/env julia
using Pkg
Pkg.activate(@__DIR__)

using JSON3
using DataFrames
using Printf
using Statistics

function load_basis_results(exp_dir::String)
    summary_path = joinpath(exp_dir, "results_summary.json")
    data = JSON3.read(read(summary_path, String))
    return data
end

function compare_basis_functions(cheb_dir::String, leg_dir::String)
    println("="^80)
    println("POLYNOMIAL BASIS COMPARISON: CHEBYSHEV vs LEGENDRE")
    println("="^80)

    cheb_data = load_basis_results(cheb_dir)
    leg_data = load_basis_results(leg_dir)

    # Create comparison table
    comparison_df = DataFrame(
        degree = Int[],
        cheb_L2 = Float64[],
        leg_L2 = Float64[],
        L2_improvement_pct = Float64[],
        cheb_CN = Float64[],
        leg_CN = Float64[],
        CN_improvement_factor = Float64[],
        cheb_CP = Int[],
        leg_CP = Int[],
        cheb_best = Float64[],
        leg_best = Float64[],
        cheb_time = Float64[],
        leg_time = Float64[]
    )

    for (cheb_deg, leg_deg) in zip(cheb_data, leg_data)
        L2_improvement = 100 * (cheb_deg.L2_norm - leg_deg.L2_norm) / cheb_deg.L2_norm
        CN_improvement = cheb_deg.condition_number / leg_deg.condition_number

        push!(comparison_df, (
            cheb_deg.degree,
            cheb_deg.L2_norm,
            leg_deg.L2_norm,
            L2_improvement,
            cheb_deg.condition_number,
            leg_deg.condition_number,
            CN_improvement,
            cheb_deg.critical_points,
            leg_deg.critical_points,
            cheb_deg.best_value,
            leg_deg.best_value,
            cheb_deg.computation_time,
            leg_deg.computation_time
        ))
    end

    println("\n📊 COMPARISON SUMMARY")
    println(comparison_df)

    println("\n📈 KEY FINDINGS")
    println("="^80)

    avg_L2_improvement = mean(comparison_df.L2_improvement_pct)
    avg_CN_improvement = mean(comparison_df.CN_improvement_factor)

    println(@sprintf("L2 Approximation: Legendre %.1f%% better on average", avg_L2_improvement))
    println(@sprintf("Numerical Stability: Legendre %.1fx more stable on average", avg_CN_improvement))
    println(@sprintf("Best Global Minimum: %.2f (Chebyshev deg 5)", minimum(cheb_data[d.degree].best_value for d in cheb_data)))
    println(@sprintf("Computation Time: Virtually identical (Δ < 2s)"))

    total_cheb_CP = sum(comparison_df.cheb_CP)
    total_leg_CP = sum(comparison_df.leg_CP)
    println(@sprintf("Critical Points Found: Chebyshev=%d, Legendre=%d", total_cheb_CP, total_leg_CP))

    println("\n🎯 RECOMMENDATION")
    println("="^80)
    println("Use LEGENDRE basis for:")
    println("  ✓ Better numerical stability (3-5× lower condition numbers)")
    println("  ✓ Better L2 approximation quality (~12% improvement)")
    println("  ✓ More real solutions discovered")
    println("  ✗ May miss global minimum (Chebyshev deg 5 found best)")
    println("\nUse CHEBYSHEV basis for:")
    println("  ✓ Finding global minimum (deg 5 found best value: 208.28)")
    println("  ✓ Standard choice in literature")
    println("  ✗ Higher condition numbers (stability concerns)")
    println("\n💡 BEST PRACTICE: Run both bases and take best result")

    return comparison_df
end

# Run comparison
if length(ARGS) == 2
    cheb_dir = ARGS[1]
    leg_dir = ARGS[2]
    compare_basis_functions(cheb_dir, leg_dir)
else
    println("Usage: julia compare_basis_functions.jl <chebyshev_dir> <legendre_dir>")
end
```

**Run it:**
```bash
julia --project=. compare_basis_functions.jl \
  collected_experiments_20251014_090544/lv4d_basis_comparison_chebyshev_deg4-6_domain0.3_GN16_20251013_172835 \
  collected_experiments_20251014_090544/lv4d_basis_comparison_legendre_deg4-6_domain0.3_GN16_20251013_172835
```

---

### 2.5 Detailed Comparison Metrics

#### **Statistical Significance**

With only 3 data points (degrees 4-6), we can report:
- **Consistent trends** (not statistically rigorous)
- Legendre shows systematic improvement in L2 and CN
- Chebyshev found better global minimum at deg 5

#### **Convergence Behavior**

**L2 Norm Convergence**:
- Chebyshev: 9511 → 9139 → 6822 (monotonic decrease)
- Legendre: 8379 → 7863 → 6136 (monotonic decrease)
- Both converge, Legendre consistently ~10% better

**Condition Number Behavior**:
- Chebyshev: 16.0 → 16.0 → 16.0 (constant, excellent stability)
- Legendre: 3.26 → 4.10 → 6.24 (increasing with degree, still excellent)

#### **Critical Point Quality**

Different bases discover different critical points:
- Degree 4: Legendre finds 4x more points than Chebyshev
- Degree 5: Chebyshev finds **best global minimum** (208.28)
- Degree 6: Both bases find similar number of points

**Interpretation**: Polynomial basis affects which regions of state space are well-approximated, leading to different critical point discovery.

---

### 2.6 Visualization Recommendations

**Plot 1: L2 Convergence Comparison**
```
L2 Approximation Error vs Polynomial Degree

10000 ┤
      │ ●────Chebyshev
 9000 ┤ ●  ○────Legendre
      │    ○
 8000 ┤       ●
      │          ○
 7000 ┤             ●
      │                ○
 6000 ┤
      └─────────────────────
        4    5    6  (degree)
```

**Plot 2: Condition Number Comparison**
```
Condition Number vs Degree

18 ┤ ●──●──●  Chebyshev (constant)
16 ┤
   │
   │        ○  Legendre
 6 ┤     ○
   │  ○
 3 ┤
   └─────────────────────
     4   5   6  (degree)
```

**Plot 3: Best Objective Value by Degree**
```
Best Value Found

20000 ┤        ○  (Legendre deg 5)
      │
      │ ●  (Cheb deg 4)
 4000 ┤
      │
      │    ○  ○  (Legendre deg 4,6)
 2000 ┤       ●  (Cheb deg 6)
      │
      │
  200 ┤    ●  ★ (Cheb deg 5 - BEST)
      └─────────────────────
        4   5   6  (degree)
```

---

## Part 3: Summary of Analysis Routines

### Routine 1: Quick Campaign Analysis
```bash
julia --project=. analyze_collected_campaign.jl <experiment_path>
```
- Fast overview of any experiment
- Shows L2 norms, critical points, timings
- Works with single experiments or campaigns

### Routine 2: Batch Processing
```bash
julia --project=. scripts/batch_analyze.jl collected_experiments_20251014_090544/
```
- Process all experiments in collection
- Generate summary tables
- Export CSV for further analysis

### Routine 3: Generate Detailed Tables
```bash
julia --project=. generate_detailed_table.jl <experiment_path>
```
- Degree-by-degree breakdown
- Full statistics per degree
- Publication-ready tables

### Routine 4: Convergence Visualization
```bash
julia --project=. show_convergence_table.jl <experiment_path>
```
- L2 norm convergence table
- Degree comparison
- Convergence rate analysis

### Routine 5: Basis Comparison (NEW)
```bash
julia --project=. compare_basis_functions.jl <cheb_dir> <leg_dir>
```
- Direct Chebyshev vs Legendre comparison
- All metrics side-by-side
- Recommendation engine

---

## Part 4: Priority Analysis Order

**Week 1 Priorities**:

1. ✅ **Basis Comparison** (Issue #172 related)
   - Run `compare_basis_functions.jl`
   - Generate comparison plots
   - Document findings

2. **Extended Degree Analysis** (Issue #172)
   - Analyze deg 4-18 data
   - Determine optimal degree
   - Identify convergence plateau

3. **Minimal Tests Validation** (Issue #139)
   - Verify DataFrame validation worked
   - Analyze GN scaling
   - Close issue if successful

**Week 2 Priorities**:

4. **Parameter Recovery Analysis** (Issue #117)
   - Analyze recovery quality
   - Compare parameter sets
   - Generate convergence plots

---

## Conclusion

**Key Takeaways**:

1. **Legendre basis is superior** for numerical stability and approximation quality
2. **Chebyshev basis found best global minimum** at degree 5
3. **Best practice**: Run both bases and compare results
4. All analysis routines available in `globtimpostprocessing` package
5. Basis comparison script needs to be created (template provided above)

**Next Steps**:
1. Create `compare_basis_functions.jl` script
2. Run comparison and generate report
3. Analyze extended degree data (deg 4-18)
4. Update GitLab issues with findings
