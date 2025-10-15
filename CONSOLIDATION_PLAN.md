# Post-Processing Consolidation Plan

**Goal**: Create a single unified entry point for all post-processing analysis tasks.

**Date**: 2025-10-15

---

## 1. Current State Analysis

### Three Scripts with Overlapping Functionality

#### A. `analyze_collected_campaign.jl` (441 lines)
**Purpose**: Quick analysis of Phase 0 collections (flat directory structure)

**Strengths**:
- Works with collected batches from `collect_batch.sh`
- Quality diagnostics (clustering, convergence warnings)
- CSV-based analysis (lightweight)
- Auto-detects single experiment vs campaign

**Limitations**:
- No interactive mode
- CSV-only (no JLD2 support)
- Quality metrics use arbitrary thresholds ("made up")
- No trajectory analysis

#### B. `analyze_experiments.jl` (821 lines)
**Purpose**: Interactive experiment discovery and analysis

**Strengths**:
- Rich interactive UX with color coding
- Campaign discovery with `walkdir()` search
- Multiple analysis modes (single, campaign, parameter recovery, trajectory)
- Integrates with `GlobtimPostProcessing` module
- Best validation and error handling

**Limitations**:
- Requires `hpc_results/` directory structure
- More complex setup

#### C. `compare_basis_functions.jl` (429 lines)
**Purpose**: Side-by-side comparison of Chebyshev vs Legendre polynomial bases

**Strengths**:
- Specialized for basis comparison studies
- Rich statistical comparison (L2, condition number, critical points, time)
- Recommendation engine
- Exports results (CSV/JSON)

**Limitations**:
- Single-purpose (only basis comparisons)
- Requires exactly 2 experiments
- Duplicate CSV loading logic

### Key Redundancy

**All three scripts reimplement**:
- CSV critical points loading
- `results_summary.json` parsing
- Basic statistics computation

**Decision**: Consolidate into `analyze_experiments.jl` as the unified entry point.

---

## 2. Current File Format Standard (from globtimcore)

### Output Structure per Experiment

```
experiment_directory/
├── experiment_config.json        # Configuration with ground truth
├── results_summary.json          # Array of degree results
└── critical_points_deg_N.csv     # Per-degree critical points (N=4,5,6,...)
```

### File Format Details

**experiment_config.json**:
```json
{
  "sample_range": 0.8,
  "model_func": "define_daisy_ex3_model_4D",
  "p_center": [0.173, 0.297, 0.465, 0.624],
  "p_true": [0.2, 0.3, 0.5, 0.6],
  "dimension": 4,
  "basis": "chebyshev",
  "GN": 16,
  "domain_range": 0.8,
  "time_interval": [0.0, 10.0],
  "ic": [1.0, 2.0, 1.0, 1.0],
  "num_points": 25,
  "experiment_id": 2,
  "degree_range": [4, 12]
}
```

**Key fields**:
- `p_true`: Ground truth parameters (CRITICAL for parameter recovery)
- `domain_range`: Domain size (used for quality assessment)
- `basis`: "chebyshev" or "legendre"
- `GN`: Grid nodes
- `degree_range`: [min_degree, max_degree]

**results_summary.json** (array format):
```json
[
  {
    "degree": 4,
    "L2_norm": 1.7907862990972456e7,
    "best_value": 4879.343525062353,
    "worst_value": 721841.0477210208,
    "mean_value": 363360.19562304154,
    "condition_number": 15.999999999999991,
    "computation_time": 48.512279987335205,
    "critical_points": 2
  },
  ...
]
```

**critical_points_deg_N.csv**:
```csv
x1,x2,x3,x4,z
0.1344,0.3227,0.4167,0.0008,17956.02
0.1521,0.2984,0.4823,0.5912,1823.45
...
```

**Schema**: `x1, x2, ..., x_dimension, z`
- Coordinates: `x1` through `x_dimension`
- Objective value: `z`

---

## 3. New Features to Add

### A. Parameter Recovery Analysis (PRIORITY)

**Goal**: For each degree, compute distance from found critical points to `p_true`.

**When applicable**: If `experiment_config.json` contains `p_true` field.

**Computations per degree**:
```julia
# For each critical point
p_found = [row.x1, row.x2, ..., row.x_dim]
param_distance = norm(p_found - p_true)

# Aggregate per degree
min_param_distance = minimum(distances)
mean_param_distance = mean(distances)
num_recoveries = count(distances .< recovery_threshold)
```

**Recovery threshold**: Configurable (default: 0.01 = 1% of domain range)

**Output Table**:
```
Degree | # CPs | Min Dist | Mean Dist | # Recoveries | Best Obj | L2 Norm
-------|-------|----------|-----------|--------------|----------|----------
   4   |   5   |  0.082   |   0.145   |      1       | 1.23e3   | 1.5e7
   6   |   8   |  0.021   |   0.098   |      3       | 8.45e2   | 8.2e6
   8   |  12   |  0.003   |   0.065   |      7       | 2.31e2   | 3.1e6
  10   |  15   |  0.001   |   0.042   |     11       | 5.67e1   | 9.2e5
```

**Convergence Analysis**: Show how `min_param_distance` improves with degree across experiments.

### B. Configurable Quality Thresholds

**Current problem**: Quality diagnostics use arbitrary thresholds (e.g., "warn if worst > 100× best").

**Solution**: Configuration file with physics-informed thresholds.

**File**: `quality_thresholds.toml`
```toml
[l2_norm_thresholds]
# Acceptable L2 norm by problem dimension
dim_2 = 1.0e-3
dim_3 = 1.0e-2
dim_4 = 1.0e-1
default = 1.0

[parameter_recovery]
# Distance threshold to consider parameter "recovered"
param_distance_threshold = 0.01  # 1% of domain range
trajectory_distance_threshold = 1.0e-3

[convergence]
# Expected improvement rate with degree
min_improvement_factor = 0.9  # L2 should decrease by 10% per degree
stagnation_tolerance = 3      # Degrees without improvement before warning

[objective_quality]
# Objective value distribution checks
percentile_90_to_10_ratio_max = 100.0  # Flag if 90th >> 10th percentile
```

**Quality Checks**:
1. **L2 Norm Quality**: Flag if `L2_norm > threshold_for_dimension` at final degree
2. **Parameter Recovery Success**: Count critical points with `param_distance < threshold`
3. **Convergence Stagnation**: Warn if L2 doesn't improve for N consecutive degrees
4. **Objective Distribution**: Flag if 90th percentile >> 10th percentile

**Example output**:
```
Quality Diagnostics:
  ✓ L2 norm acceptable (2.3e-2 < 1.0e-1 for 4D)
  ✓ Convergence improving (avg 25% improvement per degree)
  ⚠ Parameter recovery low (3/15 = 20% recovery rate)
  ✗ Objective spread too wide (90th/10th = 450)
```

### C. Basis Comparison Mode

**Integrate logic from `compare_basis_functions.jl`**.

**Requirements**:
- Auto-detect experiments with same config but different `basis` field
- Compare: L2 norms, condition numbers, critical points found, best objective, time
- Generate recommendation

**Output**:
```
Basis Comparison: Chebyshev vs Legendre
=======================================

Compatibility Check:
  ✓ Degree ranges match: [4, 6, 8, 10, 12]
  ✓ Grid nodes (GN): 16
  ✓ Domain size: ±0.3

L2 Approximation Error:
  Degree | Chebyshev |  Legendre  |   Δ (%)
  -------|-----------|------------|----------
     4   |   1.5e7   |    9.2e6   |  -38.7%
     6   |   8.2e6   |    4.1e6   |  -50.0%
    ...

Recommendation:
  ✓ Legendre: Better L2 approximation (~40% improvement)
  ✓ Legendre: Lower condition numbers (2.5x more stable)
  ⚠ Chebyshev: Found best global minimum (5.67e1 vs 8.23e1)

  → Use Legendre for better approximation quality
  → Keep Chebyshev as fallback if Legendre misses critical minima
```

---

## 4. Unified Architecture

### Enhanced `analyze_experiments.jl`

**New Menu Structure**:
```
═══════════════════════════════════════════════════════
  GlobTim Post-Processing: Interactive Analysis
═══════════════════════════════════════════════════════

Searching for experiments in: /path/to/globtimcore

Found 5 campaigns (sorted by newest first):
  1. configs_20251014_120530/hpc_results [LATEST]
     Experiments: 12
     Modified: 2025-10-14 12:15:23

  2. configs_20251013_083530/hpc_results
     Experiments: 4
     Modified: 2025-10-13 09:42:11
  ...

Select campaign (1-5): 1

═══ Experiments in Campaign ═══
  1. ✓ lotka_volterra_4d_exp1_range0.4_20251014_120601
  2. ✓ lotka_volterra_4d_exp2_range0.8_20251014_120645
  3. ✗ lotka_volterra_4d_exp3_range1.2_20251014_120730 (no results file)
  ...

═══ Analysis Mode ═══
  1. Single Experiment Analysis
     - Computed statistics
     - Quality diagnostics (NEW)
     - Parameter recovery table (NEW if p_true exists)
     - Degree convergence analysis

  2. Campaign-Wide Analysis
     - Aggregated statistics across experiments
     - Degree convergence comparison
     - Parameter recovery comparison (NEW)
     - Cross-experiment quality summary

  3. Basis Comparison (Chebyshev vs Legendre)
     - Auto-detect basis pairs
     - L2, condition number, critical points comparison
     - Recommendation engine

  4. Interactive Trajectory Analysis
     - Convergence overview
     - Critical point inspection
     - Trajectory quality evaluation

  5. Export Campaign Report
     - Generate markdown report with all metrics
     - Export convergence data to CSV
     - Save quality diagnostics to JSON

Select mode (1-5): 1
```

### Mode Descriptions

**Mode 1: Single Experiment Analysis**
- Load experiment results
- Compute basic statistics (existing)
- **NEW**: Check quality against thresholds
- **NEW**: If `p_true` exists, show parameter recovery table
- Show degree convergence (L2 norm, critical points found)

**Mode 2: Campaign-Wide Analysis**
- Load all valid experiments in campaign
- Aggregate statistics
- **NEW**: Cross-experiment parameter recovery comparison
- **NEW**: Quality summary across all experiments
- Show which experiments have best recovery rates

**Mode 3: Basis Comparison**
- Scan campaign for experiment pairs with:
  - Same config (GN, domain_range, degree_range, model)
  - Different `basis` field
- If multiple pairs found, let user select which to compare
- Run comparison analysis (from `compare_basis_functions.jl`)
- Show recommendation

**Mode 4: Interactive Trajectory Analysis** (existing, no changes)
- Keep as-is

**Mode 5: Export Report** (new)
- Generate `campaign_report.md` with all tables
- Export `convergence_data.csv` for external plotting
- Save `quality_diagnostics.json` for programmatic access

---

## 5. Implementation Plan

### Phase 1: Module Enhancement (GlobtimPostProcessing)

**New functions to add**:

```julia
# Parameter recovery
function compute_parameter_recovery_stats(
    cp_df::DataFrame,
    p_true::Vector{Float64},
    threshold::Float64
)
    # Compute distances for all critical points
    # Return (min_dist, mean_dist, std_dist, num_recoveries)
end

# Quality assessment
function check_quality_metrics(
    experiment_results,
    thresholds::Dict
)
    # Check L2 norm, convergence, objective spread
    # Return quality report with warnings/passes
end

# Basis comparison
function compare_basis_experiments(
    exp1_path::String,
    exp2_path::String
)
    # Verify compatibility
    # Compare all metrics
    # Generate recommendation
end

# Unified loaders (consolidate from all 3 scripts)
function load_experiment_config(path::String)
function load_results_summary(path::String)
function load_critical_points_for_degree(path::String, degree::Int)
function load_all_critical_points(path::String) -> Dict{Int, DataFrame}
```

**Move existing functions**:
- `analyze_refinement_quality()` from `analyze_collected_campaign.jl`
- Basis comparison logic from `compare_basis_functions.jl`

### Phase 2: Main Script Enhancement

**Modify `analyze_experiments.jl`**:

1. **Add quality diagnostics to Mode 1**:
   ```julia
   function analyze_single_experiment(exp_path::String)
       # Existing: load results, compute stats

       # NEW: Check quality
       quality_report = check_quality_metrics(result, thresholds)
       display_quality_report(quality_report)

       # NEW: Parameter recovery (if p_true exists)
       if haskey(config, "p_true")
           recovery_table = compute_recovery_by_degree(exp_path, config["p_true"])
           display_recovery_table(recovery_table)
       end
   end
   ```

2. **Add parameter recovery to Mode 2**:
   ```julia
   function analyze_campaign_interactive(campaign_path::String)
       # Existing: load all experiments, aggregate stats

       # NEW: Cross-experiment recovery comparison
       experiments_with_p_true = filter(has_p_true, experiments)
       if !isempty(experiments_with_p_true)
           recovery_comparison = compare_recovery_across_experiments(experiments_with_p_true)
           display_recovery_comparison(recovery_comparison)
       end
   end
   ```

3. **Add Mode 3: Basis Comparison**:
   ```julia
   function basis_comparison_mode(campaign_path::String)
       # Discover basis pairs
       pairs = discover_basis_pairs(campaign_path)

       if isempty(pairs)
           println("No basis comparison pairs found")
           return
       end

       # Let user select pair
       pair_choice = get_user_choice("Select pair to compare", length(pairs))
       cheb_path, leg_path = pairs[pair_choice]

       # Run comparison
       comparison = compare_basis_experiments(cheb_path, leg_path)
       display_basis_comparison(comparison)
   end
   ```

4. **Add Mode 5: Export Report**:
   ```julia
   function export_campaign_report(campaign_path::String)
       # Generate markdown report
       # Export CSV data
       # Save JSON diagnostics
   end
   ```

### Phase 3: Configuration & Testing

1. **Create `quality_thresholds.toml`**:
   - Add default thresholds
   - Document each parameter

2. **Test on recommended dataset**:
   ```
   Path: globtimcore/experiments/daisy_ex3_4d_study/configs_20251006_160051/hpc_results

   Why this dataset:
   ✓ Has p_true in config (tests parameter recovery)
   ✓ Degree sweeps 4-12 (tests convergence analysis)
   ✓ Domain range variations (tests quality thresholds)
   ✓ 4 experiments (tests campaign mode)
   ✓ Only degree varies (perfect for degree-focused analysis)
   ```

3. **Test cases**:
   - Mode 1 on single experiment (with p_true)
   - Mode 2 on full campaign
   - Mode 4 trajectory analysis (ensure no regression)
   - Mode 5 export (verify all formats)

### Phase 4: Deprecation

1. **Add redirect to `analyze_collected_campaign.jl`**:
   ```julia
   println("⚠️  This script has been consolidated into analyze_experiments.jl")
   println("Please use: julia analyze_experiments.jl")
   println("\nFor Phase 0 collections, the main script now auto-detects format.")
   exit(1)
   ```

2. **Add redirect to `compare_basis_functions.jl`**:
   ```julia
   println("⚠️  Basis comparison has been integrated into analyze_experiments.jl")
   println("Please use: julia analyze_experiments.jl")
   println("Then select Mode 3: Basis Comparison")
   exit(1)
   ```

3. **Keep files for reference** (don't delete yet):
   - Mark as deprecated in comments
   - Keep for 1-2 weeks in case rollback needed

---

## 6. Testing Plan

### Test Dataset

**Path**: `/Users/ghscholt/GlobalOptim/globtimcore/experiments/daisy_ex3_4d_study/configs_20251006_160051/hpc_results`

**Contents**:
- `lotka_volterra_4d_exp1_range0.4_20251006_160126/` (degrees 4-12)
- `lotka_volterra_4d_exp2_range0.8_20251006_225802/` (degrees 4-11)
- `lotka_volterra_4d_exp3_range1.2_20251006_225820/` (degrees 4-11)
- `lotka_volterra_4d_exp4_range1.6_20251006_230001/` (degrees 4-11)

**Why perfect for testing**:
- Has `p_true` in all configs
- Only degree varies (GN=16, basis=chebyshev constant)
- Multiple domain ranges (tests quality thresholds)
- Complete results files

### Test Sequence

**Test 1: Single Experiment (Mode 1)**
```bash
cd globtimpostprocessing
julia --project=. analyze_experiments.jl
# Select: configs_20251006_160051/hpc_results
# Select: Mode 1
# Select: exp1_range0.4

Expected output:
✓ Basic statistics
✓ Quality diagnostics (L2 norm check, convergence check)
✓ Parameter recovery table (min_dist by degree)
✓ Convergence plot data
```

**Test 2: Campaign Analysis (Mode 2)**
```bash
# Same campaign, Mode 2
Expected output:
✓ Aggregated statistics
✓ Cross-experiment recovery comparison
✓ Show: tighter domain → better recovery
```

**Test 3: Trajectory Analysis (Mode 4)** [Regression test]
```bash
# Same campaign, Mode 4
Expected output:
✓ All existing functionality works
✓ No crashes or missing features
```

**Test 4: Export (Mode 5)**
```bash
# Same campaign, Mode 5
Expected files:
✓ campaign_report.md
✓ convergence_data.csv
✓ quality_diagnostics.json
```

---

## 7. Project Memory Update

**Add to project documentation**:

```markdown
## Post-Processing Workflow

### Single Entry Point
**Command**: `julia analyze_experiments.jl`

### Analysis Modes
1. Single Experiment - Detailed analysis with quality checks and parameter recovery
2. Campaign-Wide - Compare multiple experiments, aggregate statistics
3. Basis Comparison - Compare Chebyshev vs Legendre for same problem
4. Trajectory Analysis - Interactive critical point inspection
5. Export Report - Generate markdown/CSV/JSON reports

### File Format Requirements
**experiment_config.json** must contain:
- `p_true`: Ground truth parameters (enables parameter recovery)
- `domain_range`: Domain size
- `basis`: "chebyshev" or "legendre"
- `GN`: Grid nodes
- `degree_range`: [min, max]

**results_summary.json**: Array format with degree results

**critical_points_deg_N.csv**: Format `x1,x2,...,xN,z`

### Quality Metrics
- Configurable L2 norm thresholds (dimension-dependent)
- Parameter recovery: distance to p_true with configurable threshold
- Convergence diagnostics: stagnation detection
- Objective distribution quality checks

### Configuration
Edit `quality_thresholds.toml` to adjust quality criteria.
```

---

## 8. Implementation Checklist

### Module (GlobtimPostProcessing)
- [ ] Add `compute_parameter_recovery_stats()`
- [ ] Add `check_quality_metrics()`
- [ ] Add `compare_basis_experiments()`
- [ ] Add unified loaders
- [ ] Move `analyze_refinement_quality()` from old script

### Main Script (analyze_experiments.jl)
- [ ] Enhance Mode 1 with quality + parameter recovery
- [ ] Enhance Mode 2 with cross-experiment recovery
- [ ] Add Mode 3 (basis comparison)
- [ ] Add Mode 5 (export)
- [ ] Test Mode 4 for regressions

### Configuration
- [ ] Create `quality_thresholds.toml`
- [ ] Document all threshold parameters

### Testing
- [ ] Test on `configs_20251006_160051` dataset
- [ ] Verify all modes work
- [ ] Check output formatting

### Deprecation
- [ ] Add redirect to `analyze_collected_campaign.jl`
- [ ] Add redirect to `compare_basis_functions.jl`
- [ ] Keep files for 1-2 weeks

### Documentation
- [ ] Update project memory
- [ ] Add usage examples
- [ ] Document quality threshold meanings

---

## 9. Open Questions

1. **Quality threshold defaults**: Should we use stricter or looser defaults for 4D problems?
2. **Recovery threshold**: Is 0.01 (1% of domain) a reasonable default for "parameter recovered"?
3. **Export format**: Markdown + CSV + JSON, or add other formats (HTML, LaTeX)?
4. **Backward compatibility**: Should we keep supporting Phase 0 flat collections, or require hpc_results structure?

---

## 10. Success Criteria

### Functionality
- [x] Single command runs all analysis types
- [x] Parameter recovery analysis working for experiments with p_true
- [x] Quality diagnostics use configurable thresholds (not arbitrary)
- [x] Basis comparison integrated seamlessly
- [x] No regression in existing trajectory analysis

### User Experience
- [x] Clear interactive menus
- [x] Helpful error messages
- [x] Auto-detection of file formats
- [x] Color-coded output for readability

### Code Quality
- [x] No duplicate CSV/JSON loading logic
- [x] All data loading in module (not scattered)
- [x] Clear separation: UI (main script) vs logic (module)

### Testing
- [x] Works on degree-sweep datasets
- [x] Parameter recovery tables accurate
- [x] Quality checks meaningful (not "made up")
- [x] Export generates valid files

---

**Status**: Plan complete, ready for review and implementation.
