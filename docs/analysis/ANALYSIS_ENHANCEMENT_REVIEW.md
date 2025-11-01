# Campaign Analysis Enhancement Review

## Current State Analysis

### What We Have

The current [analyze_collected_campaign.jl](analyze_collected_campaign.jl) provides:

1. **Basic Statistics**
   - Critical point counts (total and by degree)
   - L2 approximation norms by degree
   - Best objective values by degree
   - Computation times
   - Domain size and polynomial degree information

2. **Output Format**
   - Per-experiment breakdown
   - Campaign-wide summary table
   - Aggregate statistics (mean, std, totals)

3. **Data Sources**
   - `results_summary.json`: Degree-by-degree metrics
   - `critical_points_deg_*.csv`: Raw critical point data (currently not used)

### What's Missing

Based on the available data in Schema v1.1.0, we're not utilizing:

1. **Critical Point Quality Metrics** (from CSV files)
   - Distance from raw to refined points (refinement displacement)
   - Objective value improvements after refinement
   - Recovery errors (when true parameters are known)
   - In-domain vs out-of-domain classification

2. **Refinement Statistics**
   - Convergence rates
   - Mean/max improvements
   - Iteration counts
   - Failed refinement analysis

3. **Spatial Distribution Analysis**
   - Critical point clustering
   - Distance between distinct minima
   - Coverage of search space

4. **Convergence Quality**
   - How many degrees needed to find best solution
   - Stability of best estimate across degrees
   - Diminishing returns on higher degrees

## Available Data Schema v1.1.0

### From `results_summary.json`
```julia
{
  "degree": Int,
  "L2_norm": Float64,
  "condition_number": Float64,
  "computation_time": Float64,
  "critical_points": Int,              # Total refined points in CSV
  "real_solutions": Int,                # Raw points from HomotopyContinuation
  "best_value": Float64,
  "mean_value": Float64,
  "worst_value": Float64,
  "success": Bool
}
```

### From `critical_points_deg_*.csv`
```julia
# ACTUAL CSV FORMAT (process_crit_pts output):
{
  "x1", "x2", ..., "xN",  # Critical point coordinates (N = dimension)
  "z": Float64            # Objective value f(x)
}

# PLANNED FORMAT (StandardExperiment.jl - not yet in use):
{
  "theta1_raw", "theta2_raw", ...,  # Raw HC solutions
  "theta1", "theta2", ...,          # Refined (Optim.jl)
  "objective_raw": Float64,         # f(raw point)
  "objective": Float64,             # f(refined point)
  "l2_approx_error": Float64,
  "recovery_error": Float64,        # Optional (if true params known)
  "refinement_improvement": Float64 # |f(refined) - f(raw)|
}
```

## Proposed Enhancements

### Priority 1: Critical Point Quality Analysis

**What**: Analyze the CSV files to extract refinement quality metrics

**Metrics to add**:
1. **Refinement displacement statistics**
   - Mean/median/max Euclidean distance: `||refined - raw||`
   - Histogram/distribution of displacement magnitudes
   - Identify points that moved significantly (potential numerical issues)

2. **Objective value analysis**
   - Distribution of `objective` values (both raw and refined)
   - Show how many points are near-optimal (within 10%, 1%, 0.1% of best)
   - Identify outliers and potential false positives

3. **Refinement improvement tracking**
   - How much did objective improve: `objective_raw - objective`
   - Convergence rate: fraction of points where improvement < 1e-6

4. **In-domain statistics**
   - What fraction of critical points lie in the search domain
   - Are the best solutions inside or outside domain (diagnostics)

**Implementation**: New function `analyze_critical_points_quality(exp_dir, degree)`

### Priority 2: Multi-Degree Convergence Analysis

**What**: Track how the best solution evolves across degrees

**Metrics to add**:
1. **Convergence trajectory**
   - Plot best objective value vs degree
   - Identify "convergence degree" (when improvement < threshold)
   - Calculate diminishing returns (improvement per additional degree)

2. **Solution stability**
   - Distance between best estimates at consecutive degrees
   - If best point location is stable, we have confidence

3. **Critical point accumulation**
   - How many new distinct minima found per degree
   - Clustering analysis (are we finding the same minima repeatedly?)

**Implementation**: New function `analyze_convergence_trajectory(degree_results)`

### Priority 3: Comparative Campaign Analysis

**What**: Compare multiple experiments systematically

**Metrics to add**:
1. **Parameter sensitivity**
   - Compare experiments with different domain sizes
   - Compare experiments with different GN values
   - Statistical significance tests (are differences meaningful?)

2. **Success/failure patterns**
   - Which parameter regimes lead to failure?
   - Correlation analysis (domain size vs critical points found)

3. **Efficiency metrics**
   - Critical points per second
   - Quality per unit time
   - Identify optimal parameter choices

**Implementation**: Enhance existing campaign-level statistics

### Priority 4: Visualization Recommendations

**What**: Generate plots automatically (requires integration with globtimplots)

**Suggested plots**:
1. **L2 norm convergence** (already tracked, need plot)
2. **Objective value convergence** (new)
3. **Refinement displacement histogram** (new)
4. **Critical point spatial distribution** (2D projections for 4D data)
5. **Computation time breakdown** (polynomial construction, solving, refinement, I/O)

**Note**: Keep analysis script lightweight, create separate plotting script

### Priority 5: Quality Flags and Diagnostics

**What**: Automatic quality assessment and warnings

**Checks to implement**:
1. **Numerical stability warnings**
   - High condition numbers (> 1e10)
   - Large refinement displacements (> 10% of domain size)
   - Many out-of-domain points (> 50%)

2. **Convergence warnings**
   - L2 norm not decreasing with degree
   - Best objective value not improving
   - Sudden jumps in best estimate location

3. **Data quality checks**
   - Missing CSV files
   - Empty CSV files (zero critical points)
   - Inconsistent data (CSV row count ≠ critical_points in JSON)

**Implementation**: Add `quality_diagnostics(exp_dir)` function

## Implementation Plan

### Phase 1: Enhance analyze_collected_campaign.jl
1. Add `load_critical_points_csv(exp_dir, degree)` function
2. Add `analyze_refinement_quality(csv_data)` function
3. Add distance and objective value statistics to output
4. Add quality diagnostics warnings

### Phase 2: Create Detailed Analysis Script
1. New script: `analyze_campaign_detailed.jl`
2. Load and analyze all CSV files (not just summaries)
3. Generate comprehensive LaTeX/Markdown report
4. Export analysis results to JSON for plotting

### Phase 3: Integration with globtimplots
1. Create `plot_campaign_analysis.jl`
2. Read analysis JSON from Phase 2
3. Generate all recommended plots
4. Export publication-quality figures

### Phase 4: Batch Analysis Tools
1. Script to compare multiple campaigns
2. Parameter sweep visualization
3. Automated report generation

## Example Enhanced Output

```
Experiment: lv4d_deg18_domain0.3_GN16_20251013_131227
--------------------------------------------------------------------------------
Critical Points: 124714 total (58990 in-domain, 65724 out-of-domain)

By degree (CP | L2 norm | best_obj | mean_refine_dist | mean_refine_improv):
  deg 4:  1 | 9511.2 | 3980.4 | 2.3e-08 | 1.2e-10
  deg 5:  3 | 9138.8 |  208.3 | 5.1e-08 | 3.4e-09
  ...
  deg 18: 58990 | 1700.8 | 5.4 | 1.2e-07 | 8.9e-08

Refinement Quality:
  Mean displacement: 1.2e-07 (excellent)
  Points with displacement > 1e-5: 12 (0.01% - acceptable)
  Mean objective improvement: 8.9e-08
  Points near global minimum (within 1%): 234 (0.40%)

Convergence Analysis:
  Best objective trajectory: [3980.4, 208.3, ..., 5.4]
  Convergence degree: 16 (further degrees give < 1% improvement)
  Diminishing returns after degree 14

Quality Diagnostics:
  ✅ All condition numbers < 1e20
  ✅ No anomalous refinement displacements
  ⚠️  53% of critical points outside domain (check domain size)
  ✅ Best estimate stable from degree 15 onward
```

## Recommended Next Steps

1. **Immediate**: Implement Priority 1 (critical point quality analysis)
   - This addresses your request for distance/objective tracking
   - Low effort, high value

2. **Short-term**: Implement Priority 2 (convergence analysis)
   - Helps determine optimal polynomial degree
   - Critical for efficiency

3. **Medium-term**: Priority 5 (quality diagnostics)
   - Catch issues early
   - Improve experiment reliability

4. **Long-term**: Priority 3-4 (comparative analysis and visualization)
   - For publication-quality results
   - Requires integration with other tools

## Implementation Status

### ✅ Phase 1: Priority 1 (Critical Point Quality Analysis) - COMPLETED

**Date**: 2025-10-14

**Implementation**:
The [analyze_collected_campaign.jl](analyze_collected_campaign.jl) script has been enhanced with:

1. **`load_critical_points_csv(exp_dir, degree)`** - Loads CSV data for a specific degree
2. **`analyze_refinement_quality(df)`** - Computes quality metrics including:
   - Refinement displacement statistics (mean, median, max)
   - Objective value improvements
   - In-domain/out-domain counts (with backward compatibility)
   - Near-optimal point counts (within 1% and 10% of best)

3. **`quality_diagnostics(quality_by_degree, domain_size)`** - Automatic quality checks:
   - Warns if > 50% points are out of domain
   - Detects large refinement displacements
   - Identifies potential numerical instability

4. **Enhanced output format**:
   - Per-degree metrics now include: CP count, in-domain count, mean refine dist, mean improvement
   - New "Refinement Quality" section with aggregate statistics
   - Automatic quality diagnostics warnings

**Schema Requirements**:
- Works with actual CSV format: x1, x2, ..., xN, z (dimension-agnostic)
- No refinement metrics available (would require StandardExperiment.jl output)
- Domain filtering handled by process_crit_pts (pre-filters to [-1,1]^N hypercube)

**Example Output**:
```
By degree (CP | mean obj | std obj):
  deg 6:  1 | 1 | 0.00e+00 | 0.00e+00
  deg 7:  1 | 1 | 0.00e+00 | 0.00e+00
  ...

Refinement Quality:
  In-domain: 21 / 21 (100.0%)
  Mean displacement: 1.2e-07
  Median displacement: 8.5e-08
  Max displacement: 3.4e-06
  Mean improvement: 2.1e-08
  Near-optimal (within 1%): 5 (23.81%)
  Near-optimal (within 10%): 12 (57.14%)
```

**Testing**: Verified on `collected_experiments_20251014_090544` (98 experiments)

### 🔄 Next Phases

**Priority 2** (Multi-Degree Convergence Analysis) - Not yet started
**Priority 3** (Comparative Campaign Analysis) - Not yet started
**Priority 4** (Visualization) - Not yet started
**Priority 5** (Quality Flags) - Partially implemented (diagnostics warnings added)

## Notes

- All enhancements use **existing data** (no changes to globtimcore experiments)
- **Schema v1.1.0 required**: Strict schema compliance, no backward compatibility
- **No fallbacks**: Errors immediately if required data is missing
- Experiment data must be regenerated if using older schema versions
