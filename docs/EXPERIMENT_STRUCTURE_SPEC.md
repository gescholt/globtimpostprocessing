# HPC Experiment Output Structure Specification

## Overview

This document defines the standardized file structure for globtimcore HPC experiment outputs and the TDD implementation plan for enhanced parameter display during post-processing.

## Problem Statement

**Current Issue:** Experiment folder names like `lotka_volterra_4d_exp1_range0.4_20251006_160126` don't clearly communicate the experiment parameters, making selection during post-processing difficult.

**Goal:** Display clear parameter summaries when loading campaigns so users can easily identify which experiment to analyze.

## Standardized File Structure

### Complete Experiment Directory

```
experiment_name_TIMESTAMP/
├── experiment_config.json           # ✅ PRIMARY: Input parameters
├── results_summary.json             # ⚠️  OUTPUT: Can be truncated
├── results_summary.jld2             # ✅ BINARY: Backup for results_summary
├── critical_points_deg_4.csv        # ✅ DATA: Per-degree critical points
├── critical_points_deg_5.csv
├── ...
└── critical_points_deg_N.csv
```

### Required Files (Priority Order)

1. **`experiment_config.json`** (MUST exist) - Contains all input parameters
2. **`critical_points_deg_*.csv`** (MUST exist) - Contains experiment outputs
3. **`results_summary.json`** OR **`results_summary.jld2`** (SHOULD exist) - Summary metrics

### File Specifications

#### 1. `experiment_config.json` Structure

**Purpose:** Store all input parameters for experiment reproducibility

**Required Fields:**
```json
{
  "model_func": "define_daisy_ex3_model_4D",
  "dimension": 4,
  "basis": "chebyshev",
  "GN": 16,
  "domain_range": 0.4,
  "sample_range": 0.4,
  "time_interval": [0.0, 10.0],
  "ic": [1.0, 2.0, 1.0, 1.0],
  "num_points": 25,
  "experiment_id": 1,
  "degree_range": [4, 12],
  "p_center": [0.224, 0.273, 0.473, 0.578],
  "p_true": [0.2, 0.3, 0.5, 0.6]
}
```

**Field Descriptions:**
- `model_func`: System being studied (e.g., Lotka-Volterra, Daisy)
- `dimension`: State space dimensionality (2D, 4D, etc.)
- `basis`: Polynomial basis (chebyshev, monomial)
- `GN`: Grid resolution parameter
- `domain_range`/`sample_range`: Domain size (critical for comparisons!)
- `time_interval`: Time span [t_start, t_end]
- `degree_range`: [min_degree, max_degree] tested
- `p_center`: Parameter center point
- `p_true`: True parameter values (for recovery studies)

#### 2. `critical_points_deg_N.csv` Structure

**Purpose:** Store detailed critical point information per polynomial degree

**Required Columns:**
```csv
x1,x2,...,xN,z,gradient_norm,hessian_eigenvalue_1,...,hessian_eigenvalue_N
```

Where:
- `x1, x2, ..., xN`: Coordinate columns (N = dimension)
- `z`: Objective function value at critical point
- `gradient_norm`: ||∇f|| at critical point
- `hessian_eigenvalue_i`: Eigenvalues of Hessian (for classification)

#### 3. `results_summary.json` Structure

**Purpose:** Aggregate metrics across all degrees

**Format:**
```json
[
  {
    "degree": 4,
    "worst_value": 38848.35,
    "condition_number": 16.0,
    "computation_time": 59.47,
    "mean_value": 38848.35,
    "critical_points": 1,
    "best_value": 38848.35,
    "L2_norm": 40559.82,
    "total_solutions": { ... }
  },
  { "degree": 5, ... },
  ...
]
```

**Known Issue:** Can be truncated mid-write (incomplete JSON). Always have CSV fallback.

## Display Requirements

### Campaign Loading Display

When running `load_campaign_results(path)`, display:

```
📂 Loading campaign results from: /path/to/campaign
  ℹ️  Experiment: lotka_volterra_4d_exp1_range0.4_20251006_160126
      Model: Lotka-Volterra 4D | Domain: 0.4 | Basis: chebyshev | GN: 16
      Degrees: 4-12 | Time: [0.0, 10.0] | ID: exp1
  ✓ Loaded: 1

  ℹ️  Experiment: lotka_volterra_4d_exp2_range0.8_20251006_225802
      Model: Lotka-Volterra 4D | Domain: 0.8 | Basis: chebyshev | GN: 16
      Degrees: 4-12 | Time: [0.0, 10.0] | ID: exp2
  ✓ Loaded: 2
```

### Parameter Summary Format

**Compact Display (for lists):**
```
Model: {model_func} | Dim: {dimension} | Domain: {domain_range} | Basis: {basis} | GN: {GN}
Degrees: {min_deg}-{max_deg} | Time: {time_interval} | ID: {experiment_id}
```

**Detailed Display (for single experiment):**
```
Experiment: {experiment_id}
System: {model_func} (Dimension: {dimension})
Domain: {domain_range} | Basis: {basis} | Grid: GN={GN}
Degrees Tested: {degree_range[0]} to {degree_range[1]}
Time Interval: {time_interval}
Initial Condition: {ic}
Parameter Center: {p_center}
True Parameters: {p_true}
```

## Implementation Plan (TDD Approach)

### Phase 1: Test Infrastructure ✅ (Completed Investigation)

**Status:** Investigated current structure, identified files

- [x] Understand current `ResultsLoader.jl` structure
- [x] Identify `experiment_config.json` format
- [x] Document CSV fallback mechanism
- [x] Map existing loading functions

### Phase 2: Parameter Extraction Tests

**Objective:** Write tests first for parameter extraction

**Test File:** `globtimpostprocessing/test/test_parameter_extraction.jl`

**Test Cases:**
```julia
@testset "Parameter Extraction" begin
    @test extract_display_params(config) returns correct fields
    @test format_compact_params(params) produces expected string
    @test format_detailed_params(params) produces expected string
    @test handle_missing_fields(incomplete_config) provides defaults
end
```

**Mock Data:** Create fixture `test/fixtures/experiment_config_sample.json`

### Phase 3: Implement Parameter Extraction (TDD)

**File:** `globtimpostprocessing/src/ParameterExtraction.jl`

**Functions to Implement:**
```julia
"""Extract display-relevant parameters from experiment_config.json"""
function extract_display_parameters(config_dict::Dict) -> Dict{String, Any}

"""Format parameters for compact display (campaign list)"""
function format_compact_summary(params::Dict) -> String

"""Format parameters for detailed display (single experiment)"""
function format_detailed_summary(params::Dict) -> String

"""Load experiment_config.json from directory"""
function load_experiment_config(dir_path::String) -> Dict{String, Any}
```

**TDD Cycle:**
1. Write test (RED)
2. Implement minimal code to pass (GREEN)
3. Refactor for clarity (REFACTOR)
4. Repeat for each function

### Phase 4: Integration with ResultsLoader

**File:** Modify `globtimpostprocessing/src/ResultsLoader.jl`

**Changes:**
```julia
# Add to load_from_directory()
function load_from_directory(dir_path::String)
    # NEW: Load and display experiment config
    config = load_experiment_config(dir_path)
    param_summary = format_compact_summary(extract_display_parameters(config))
    println("  ℹ️  $param_summary")

    # ... existing loading logic ...
end
```

**Integration Tests:**
```julia
@testset "ResultsLoader Display Integration" begin
    @test load_experiment_results() prints parameter summary
    @test load_campaign_results() prints summary for each experiment
end
```

### Phase 5: Enhanced Campaign Display

**File:** `globtimpostprocessing/src/CampaignDisplay.jl` (NEW)

**Features:**
- Table view of all experiments in campaign
- Filterable by parameter (e.g., show only domain_range=0.8)
- Sortable by any parameter
- Export campaign summary to CSV

**Functions:**
```julia
"""Display campaign as parameter table"""
function display_campaign_table(campaign::CampaignResults)

"""Filter campaign by parameter criteria"""
function filter_campaign(campaign::CampaignResults; kwargs...) -> CampaignResults

"""Export campaign metadata to CSV"""
function export_campaign_summary(campaign::CampaignResults, output_file::String)
```

### Phase 6: Validation & Edge Cases

**Test Scenarios:**
1. ✅ Truncated `results_summary.json` → Use CSV fallback
2. ✅ Missing `experiment_config.json` → Error with helpful message
3. ✅ Incomplete `experiment_config.json` → Use defaults, warn user
4. ✅ Mixed formats in campaign → Handle gracefully
5. ✅ Non-standard folder names → Extract from config, not filename

### Phase 7: Documentation & Examples

**Files to Create:**
1. `docs/PARAMETER_DISPLAY_GUIDE.md` - User guide
2. `examples/campaign_parameter_display_demo.jl` - Usage examples
3. Update `README.md` with new features

## File Structure Validation Rules

### Critical Rules (MUST)
1. Every experiment directory MUST contain `experiment_config.json`
2. Every experiment directory MUST contain at least one `critical_points_deg_*.csv`
3. `experiment_config.json` MUST be valid JSON (test during loading)
4. `experiment_config.json` MUST contain required fields (see spec above)

### Best Practices (SHOULD)
1. Include both `results_summary.json` AND `results_summary.jld2`
2. Use atomic writes for JSON (write to temp, then rename)
3. Flush buffers before closing files (prevent truncation)
4. Include timestamp in experiment directory name
5. Include key parameters in directory name (e.g., `_range0.4_`)

### Recommended Improvements (FUTURE)
1. Add JSON schema validation for `experiment_config.json`
2. Add checksums/hashes for data integrity verification
3. Include git commit SHA in config for reproducibility
4. Add HPC job metadata (node, walltime, memory used)

## Implementation Timeline

### Week 1: Foundation
- [ ] Phase 2: Write parameter extraction tests
- [ ] Phase 3: Implement parameter extraction (TDD)

### Week 2: Integration
- [ ] Phase 4: Integrate with ResultsLoader
- [ ] Phase 5: Enhanced campaign display features

### Week 3: Polish
- [ ] Phase 6: Validation & edge case testing
- [ ] Phase 7: Documentation & examples

## Success Criteria

1. ✅ Users see clear parameter summaries when loading campaigns
2. ✅ No need to examine folder names to understand experiments
3. ✅ Easy comparison of parameters across experiments
4. ✅ Graceful handling of incomplete/corrupted files
5. ✅ Full test coverage for parameter extraction
6. ✅ Clear documentation for HPC users

## Related Issues

- **JSON Truncation:** `results_summary.json` truncation issue (seen in archived configs)
- **CSV Fallback:** Already implemented, works well
- **Metadata Tracking:** Related to Issue #124 (tracking labels), Issue #128 (enhanced metrics)

## Notes

- Current `ResultsLoader.jl` already has excellent CSV fallback mechanism
- `experiment_config.json` is reliably written (not truncated in test cases)
- Focus on making parameter extraction robust and user-friendly
- TDD approach ensures reliability for production HPC workflows
