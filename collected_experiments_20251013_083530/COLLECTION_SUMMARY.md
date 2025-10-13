# Experiment Collection Summary

**Collection Date**: October 13, 2025 08:35:30
**Collector**: collect_cluster_experiments.jl + manual rsync
**Source**: scholten@r04n02:/home/scholten/globtimcore/hpc_results/

---

## Overview

This collection contains **3 distinct campaigns** with **11 total experiments** from the most recent cluster runs, focusing on 4D Lotka-Volterra parameter studies with various configurations.

---

## Campaign 1: Extended Degrees (Lotka-Volterra 4D)

**Directory**: `campaign_lotka_volterra_4d_extended_degrees/`

**Experiments**: 4
**Degree Range**: 4-12 (extended from usual 4-8)
**Domain Ranges**: 0.4, 0.8, 1.2, 1.6

### Experiments:
1. **lotka_volterra_4d_exp1_range0.4_20251009_153430**
   - Domain: ±0.4
   - Degrees: 4-12
   - Status: Complete with CSV files
   - Critical points per degree: 1-29 (increasing with degree)

2. **lotka_volterra_4d_exp2_range0.8_20251009_153430**
   - Domain: ±0.8
   - Degrees: 4-12
   - Status: Complete with CSV files

3. **lotka_volterra_4d_exp3_range1.2_20251009_153430**
   - Domain: ±1.2
   - Degrees: 4-12
   - Status: Complete with CSV files

4. **lotka_volterra_4d_exp4_range1.6_20251009_153430**
   - Domain: ±1.6
   - Degrees: 4-12
   - Status: Complete with CSV files

### Purpose:
- Study convergence behavior with extended polynomial degrees
- Analyze how critical point count and quality change with degree
- Compare performance across different domain sizes

### Data Available:
- ✅ Critical point CSV files (x1, x2, x3, x4, z coordinates)
- ✅ Results summary JSON (L2 norms, condition numbers, timing)
- ✅ Experiment configuration
- ✅ Timing reports

---

## Campaign 2: Domain Sweep

**Directory**: `campaign_lv4d_domain_sweep/`

**Experiments**: 3
**Degree Range**: Unknown (metadata only)
**Domain Ranges**: 0.2, 0.4, 0.8

### Experiments:
1. **lv4d_domain_sweep_0.2_20251011_185054**
   - Domain: ±0.2
   - Status: Summary only (no CSV files)
   - Size: 80 KB (results_summary.jld2 + json)

2. **lv4d_domain_sweep_0.4_20251011_185159**
   - Domain: ±0.4
   - Status: Summary only (no CSV files)
   - Size: 80 KB

3. **lv4d_domain_sweep_0.8_20251011_185200**
   - Domain: ±0.8
   - Status: Summary only (no CSV files)
   - Size: 80 KB

### Purpose:
- Systematic domain size comparison
- Latest runs (October 11, 2025)

### Data Available:
- ✅ Results summary JLD2 (DrWatson format with Git provenance)
- ✅ Results summary JSON
- ❌ No CSV files (likely all critical points outside domain or no critical points found)

**Note**: These experiments completed successfully but produced no critical points within the search domain. This suggests the domain sizes may be too small, or polynomial approximation quality was insufficient to find meaningful critical points.

---

## Campaign 3: Extended Challenging

**Directory**: `campaign_extended_challenging/`

**Experiments**: 4
**Degree Ranges**: Variable per experiment (4-6, 4-7, 5-8, 6-9)
**Domain Ranges**: 0.15, 0.2, 0.25, 0.3

### Experiments:
1. **extended_4d_lv_challenging_0.15_deg4-6_20250924_233446**
   - Domain: ±0.15
   - Degrees: 4-6
   - Date: September 24, 2025
   - Status: Empty (no results files)

2. **extended_4d_lv_challenging_0.2_deg4-7_20250924_233446**
   - Domain: ±0.2
   - Degrees: 4-7
   - Date: September 24, 2025
   - Status: Empty (no results files)

3. **extended_4d_lv_challenging_0.25_deg5-8_20250924_233456**
   - Domain: ±0.25
   - Degrees: 5-8
   - Date: September 24, 2025
   - Status: Empty (no results files)

4. **extended_4d_lv_challenging_0.3_deg6-9_20250924_233456**
   - Domain: ±0.3
   - Degrees: 6-9
   - Date: September 24, 2025
   - Status: Empty (no results files)

### Purpose:
- Test challenging configurations with small domains
- Variable degree ranges optimized per domain size

### Data Available:
- ❌ Empty directories (experiments may have failed or never completed)

**Action Required**: Check cluster logs to determine if these experiments failed or were interrupted.

---

## Parameter Analysis

**Directory**: `parameter_analysis/`

Contains aggregated parameter-aware dataset from minimal_4d_lv_test_* experiments (separate from the three campaigns above).

### Files:
- `parameter_summary.csv` (2.4 KB) - Summary statistics per experiment/degree
- `full_parameter_dataset.csv` (10 KB) - Complete critical point data with parameters
- `analysis_metadata.json` (215 B) - Collection metadata

### Contents:
- Total experiments: 9
- Total critical points: 54
- Degree range: 4-5
- From: minimal_4d_lv_test experiments (not the campaigns above)

**Note**: This was generated from a different set of experiments and should be analyzed separately from the three campaigns.

---

## Collection Statistics

### By Campaign:
| Campaign | Experiments | Complete | Has CSV Data | Has Summary | Status |
|----------|-------------|----------|--------------|-------------|---------|
| Extended Degrees | 4 | 4 | ✅ Yes | ✅ Yes | Ready |
| Domain Sweep | 3 | 3 | ❌ No | ✅ Yes | Metadata only |
| Extended Challenging | 4 | 0 | ❌ No | ❌ No | Empty/Failed |

### Total:
- **Experiments collected**: 11
- **Experiments with data**: 7
- **Experiments with CSV files**: 4 (Extended Degrees campaign only)
- **Empty/Failed experiments**: 4 (Extended Challenging campaign)

### Data Sizes:
- Extended Degrees: ~40-60 KB per experiment (with CSV files)
- Domain Sweep: ~80 KB per experiment (JLD2 + JSON only)
- Extended Challenging: 0 KB (empty)
- Parameter Analysis: 12.6 KB total

### Total Collection Size: ~1.5 MB

---

## Recommended Next Steps

### 1. Process Extended Degrees Campaign ⭐ PRIORITY
```bash
cd /Users/ghscholt/GlobalOptim/globtimpostprocessing
julia --project=. analyze_experiments.jl \
  collected_experiments_20251013_083530/campaign_lotka_volterra_4d_extended_degrees/
```

**Analysis focus**:
- Convergence behavior with extended degrees (4-12)
- Critical point count vs degree
- Objective function values vs degree
- Domain size impact (0.4, 0.8, 1.2, 1.6)

### 2. Investigate Domain Sweep Results
```bash
# Check why no CSV files were generated
cd collected_experiments_20251013_083530/campaign_lv4d_domain_sweep/
for exp in lv4d_domain_sweep_*; do
    echo "=== $exp ==="
    jq '.results_summary | keys' $exp/results_summary.json
done
```

**Questions**:
- Why no critical points in domain?
- Were polynomial approximations too poor?
- Should we widen domain or change numerical parameters?

### 3. Investigate Extended Challenging Failures
```bash
# Check cluster logs
ssh scholten@r04n02 "ls -l /home/scholten/globtimcore/hpc_results/extended_4d_lv_challenging_*/"

# Look for experiment logs
ssh scholten@r04n02 "cat /home/scholten/globtimcore/hpc_results/extended_4d_lv_challenging_*/experiment.log"
```

**Action**: Determine if experiments failed, were interrupted, or never ran.

### 4. Generate Comparative Analysis
After processing Campaign 1, create:
- L2 convergence plots (degree vs error)
- Critical point count plots
- Computation time analysis
- Domain size comparison

### 5. Statistical Summary
Generate comprehensive statistical report:
- Success rates by domain size
- Convergence rates by degree
- Performance metrics
- Recommendations for future experiments

---

## GitLab Integration

**Issues to Update**:
- Add collection summary to relevant experiment tracking issues
- Document Extended Degrees campaign results
- Report Domain Sweep findings (no critical points)
- Investigate Extended Challenging failures

**Suggested GitLab Commands**:
```bash
# Update issue with collection summary
/Users/ghscholt/GlobalOptim/scripts/glab-multi-repo.sh globtimcore issue note <issue_num> \
  -m "Collected 11 experiments from cluster (Oct 13, 2025). See collected_experiments_20251013_083530/COLLECTION_SUMMARY.md"
```

---

## Files and Directories

```
collected_experiments_20251013_083530/
├── COLLECTION_SUMMARY.md (this file)
├── campaign_extended_challenging/
│   ├── extended_4d_lv_challenging_0.15_deg4-6_20250924_233446/ (empty)
│   ├── extended_4d_lv_challenging_0.2_deg4-7_20250924_233446/ (empty)
│   ├── extended_4d_lv_challenging_0.25_deg5-8_20250924_233456/ (empty)
│   └── extended_4d_lv_challenging_0.3_deg6-9_20250924_233456/ (empty)
├── campaign_lotka_volterra_4d_extended_degrees/
│   ├── lotka_volterra_4d_exp1_range0.4_20251009_153430/ (complete with CSV)
│   ├── lotka_volterra_4d_exp2_range0.8_20251009_153430/ (complete with CSV)
│   ├── lotka_volterra_4d_exp3_range1.2_20251009_153430/ (complete with CSV)
│   └── lotka_volterra_4d_exp4_range1.6_20251009_153430/ (complete with CSV)
├── campaign_lv4d_domain_sweep/
│   ├── lv4d_domain_sweep_0.2_20251011_185054/ (JSON/JLD2 only)
│   ├── lv4d_domain_sweep_0.4_20251011_185159/ (JSON/JLD2 only)
│   └── lv4d_domain_sweep_0.8_20251011_185200/ (JSON/JLD2 only)
└── parameter_analysis/ (from separate minimal_4d_lv_test experiments)
    ├── analysis_metadata.json
    ├── full_parameter_dataset.csv
    └── parameter_summary.csv
```

---

**Collection Complete**: ✅
**Ready for Analysis**: Campaign 1 (Extended Degrees) ✅
**Requires Investigation**: Campaign 2 (Domain Sweep), Campaign 3 (Extended Challenging)
