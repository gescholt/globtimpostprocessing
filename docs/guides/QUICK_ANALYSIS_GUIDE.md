# Quick Analysis Guide - Collected Experiments 2025-10-14

**Collection**: `collected_experiments_20251014_090544/`

## TL;DR - Run These Commands

### 1. Chebyshev vs Legendre Comparison (PRIORITY)

```bash
cd /Users/ghscholt/GlobalOptim/globtimpostprocessing

julia --project=. compare_basis_functions.jl \
  collected_experiments_20251014_090544/lv4d_basis_comparison_chebyshev_deg4-6_domain0.3_GN16_20251013_172835 \
  collected_experiments_20251014_090544/lv4d_basis_comparison_legendre_deg4-6_domain0.3_GN16_20251013_172835
```

**What it does**:
- Compares Chebyshev vs Legendre polynomial bases
- Shows L2 approximation quality, numerical stability, critical point discovery
- Provides recommendation on which basis to use

**Expected output**:
- Detailed comparison tables
- Summary statistics
- Recommendation (spoiler: Legendre is ~12% better for L2, 3-5x better stability)
- Saved results in `basis_comparison_analysis/`

---

### 2. Extended Degree Testing Analysis (deg 4-18)

```bash
julia --project=. analyze_collected_campaign.jl \
  collected_experiments_20251014_090544/lv4d_deg18_domain0.3_GN16_20251013_131227/
```

**What it does**:
- Analyzes convergence from degree 4 to 18
- Shows critical point explosion at deg 17-18 (62K and 57K points!)
- Identifies convergence plateau

**Key questions answered**:
- Does L2 decrease monotonically? (YES)
- Where does convergence plateau? (TBD from analysis)
- Are deg 13-18 worth it? (TBD - check computation time scaling)

---

### 3. Minimal 4D LV Tests (Quick Validation)

```bash
# Option 1: Analyze all together
julia --project=. analyze_collected_campaign.jl \
  collected_experiments_20251014_090544/ \
  --filter "minimal_4d_lv_test.*20251006"

# Option 2: Individual experiments (if needed)
cd collected_experiments_20251014_090544
for exp in minimal_4d_lv_test_GN=5_*_20251006_*/; do
  julia --project=.. analyze_collected_campaign.jl "$exp"
done
```

**What it does**:
- Validates DataFrame column infrastructure
- Shows GN scaling (GN=5,6,8)
- Domain size impact (0.1, 0.15, 0.2)

---

### 4. Parameter Recovery Experiments

```bash
julia --project=. analyze_collected_campaign.jl \
  collected_experiments_20251014_090544/ \
  --filter "4dlv_recovery.*exp_"
```

**What it does**:
- Analyzes parameter recovery quality
- Compares baseline/moderate/strong parameter sets
- Shows domain size impact on recovery

---

## Available Analysis Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `compare_basis_functions.jl` | **NEW** Compare Chebyshev vs Legendre | `julia --project=. compare_basis_functions.jl <cheb_dir> <leg_dir>` |
| `analyze_collected_campaign.jl` | Quick campaign overview | `julia --project=. analyze_collected_campaign.jl <exp_path>` |
| `generate_detailed_table.jl` | Degree-by-degree breakdown | `julia --project=. generate_detailed_table.jl <exp_path>` |
| `show_convergence_table.jl` | L2 convergence table | `julia --project=. show_convergence_table.jl <exp_path>` |
| `scripts/batch_analyze.jl` | Batch process all experiments | `julia --project=. scripts/batch_analyze.jl <collection_dir>` |

---

## Priority Order

**Today (2025-10-14)**:
1. ✅ Collection complete
2. ⏳ Run Chebyshev vs Legendre comparison
3. ⏳ Analyze deg 4-18 convergence

**This Week**:
4. Validate minimal tests (issue #139)
5. Parameter recovery analysis (issue #117)
6. Update GitLab issues with findings

---

## Key Findings (Preview)

### Chebyshev vs Legendre (from results_summary.json):

| Metric | Chebyshev | Legendre | Winner |
|--------|-----------|----------|--------|
| **L2 Approx** (deg 6) | 6821.72 | 6135.88 | **Legendre (-10%)** |
| **Condition Number** (deg 4) | 16.00 | 3.26 | **Legendre (4.9x better)** |
| **Best Minimum** (deg 5) | **208.28** | 16817.75 | **Chebyshev (81x better!)** |
| **Computation Time** | ~15-60s | ~15-60s | **Tied** |

**Takeaway**: Legendre is better for approximation/stability, but Chebyshev found the best global minimum. **Run both bases and compare!**

---

## Output Locations

All analysis outputs will be saved in:
- `collected_experiments_20251014_090544/basis_comparison_analysis/`
- Individual experiment directories contain `results_summary.json`
- CSV exports for further processing

---

## Next Steps After Analysis

1. Document findings in GitLab issues
2. Update experiment launch scripts to support both bases
3. Create visualization plots (L2 convergence, condition numbers)
4. Write up basis comparison for documentation
5. Consider extending to deg 20-24 if deg 18 shows continued improvement

---

## Getting Help

- Full analysis plan: `ANALYSIS_PLAN_20251014.md`
- Package docs: `README.md`
- Experiment collection summary: `COLLECTION_SUMMARY_20251014.md`

---

**Questions?** Check the detailed analysis plan or run scripts with `--help` flag.
