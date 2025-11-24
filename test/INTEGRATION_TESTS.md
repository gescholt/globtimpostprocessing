# Integration Tests with Real globtimcore Fixtures

This document describes the comprehensive integration tests that validate the complete GlobtimPostProcessing workflow using real data from globtimcore.

## Overview

**File**: `test/test_integration_real_fixtures.jl`

**Purpose**: End-to-end testing of the complete analysis pipeline:
```
Load fixtures → Refine critical points → Quality diagnostics → Report generation
```

**Data Source**: Real globtimcore output (Deuflhard_4d benchmark, 81+289 critical points)

## What's Tested

### 1. Data Loading (Phase 2 Format)
- ✅ Load `experiment_config.json`
- ✅ Load `results_summary.json`
- ✅ Load `critical_points_raw_deg_N.csv` (Phase 2 CSV format)
- ✅ Parse 4D critical points with `index, p1, p2, p3, p4, objective` columns
- ✅ Validate data consistency (domain bounds, finite values)

### 2. Objective Function Evaluation
- ✅ Load and use `deuflhard_4d_fixture()` from `test_functions.jl`
- ✅ Verify function properties (non-negative, minimum at origin, finite)
- ✅ Test evaluation on random points within domain

### 3. Critical Point Refinement
- ✅ Single point refinement with real objective function
- ✅ Batch refinement (10-20 points)
- ✅ Convergence rate analysis (>70% convergence expected)
- ✅ Improvement verification (refined ≤ raw objective)
- ✅ Phase 2 Tier 1 diagnostics (f_calls, time_elapsed, convergence_reason)

### 4. Quality Diagnostics
- ✅ Load quality thresholds from `quality_thresholds.toml`
- ✅ L2 norm assessment (dimension-aware, graded: excellent/good/fair/poor)
- ✅ Stagnation detection (convergence monitoring across degrees)
- ✅ Objective distribution quality (outlier detection using IQR)

### 5. Multi-Degree Analysis
- ✅ Compare degree 4 vs degree 6 results
- ✅ Verify L2 improvement with higher degree
- ✅ Check critical point count increases with degree
- ✅ Validate best objective improves or stays same

### 6. Complete Workflow
- ✅ Integrated pipeline: load → refine → analyze → assess quality
- ✅ Convergence statistics (rate, mean improvement, best value)
- ✅ Quality assessment (L2, distribution, stagnation)

## Test Data

**Fixtures Location**: `test/fixtures/`

**Files Used**:
- `experiment_config.json` - 4D Deuflhard configuration
- `results_summary.json` - L2 norms, condition numbers, timing
- `critical_points_raw_deg_4.csv` - 81 critical points (degree 4)
- `critical_points_raw_deg_6.csv` - 289 critical points (degree 6)
- `test_functions.jl` - `deuflhard_4d_fixture()` objective function

**Test Function**: Deuflhard_4d
- **Domain**: `[-1.2, 1.2]^4`
- **Properties**: Multiple local minima, global minimum ≈ origin
- **Type**: Parameter-free optimization (no p_true)

## Running the Tests

### Quick Run (Integration Tests Only)
```bash
cd globtimpostprocessing
julia --project=. test/run_integration_tests.jl
```

### Full Test Suite (Includes Integration Tests)
```bash
cd globtimpostprocessing
julia --project=. -e 'using Pkg; Pkg.test()'
```

### Run Specific Test Set
```julia
using Pkg
Pkg.activate(".")
using Test

@testset "Integration: Real Fixtures" begin
    include("test/test_integration_real_fixtures.jl")
end
```

## Expected Output

**Test Summary**:
```
Test Summary:                                    | Pass  Total
Integration: Real Fixtures End-to-End            |  XXX    XXX
  Fixture Availability                           |    6      6
  Load Experiment Configuration                  |    6      6
  Load Critical Points (Phase 2 Format)          |   10     10
  Objective Function Evaluation                  |   XX     XX
  Refinement: Single Critical Point              |   XX     XX
  Refinement: Batch Processing                   |   XX     XX
  Quality Diagnostics: L2 Assessment             |   XX     XX
  Quality Diagnostics: Stagnation Detection      |   XX     XX
  Quality Diagnostics: Objective Distribution    |   XX     XX
  Complete Workflow: Load → Refine → Analyze     |   XX     XX
  Multi-Degree Analysis                          |   XX     XX
  Refinement Convergence Analysis                |   XX     XX
  Data Consistency Checks                        |   XX     XX
  Objective Function Properties                  |   XX     XX

✅ All integration tests with real fixtures passed!
```

## Test Coverage

### Modules Tested
1. ✅ `ResultsLoader.jl` - `load_experiment_config()`, `load_critical_points_for_degree()`
2. ✅ `CriticalPointRefinement.jl` - `refine_critical_point()`, `refine_critical_points_batch()`
3. ✅ `QualityDiagnostics.jl` - `check_l2_quality()`, `detect_stagnation()`, `check_objective_distribution_quality()`
4. ✅ `ParameterRecovery.jl` - (not tested here - needs p_true fixture)

### Test Scenarios
- ✅ Single experiment, single degree
- ✅ Single experiment, multiple degrees
- ✅ Small batch refinement (5-10 points)
- ✅ Medium batch refinement (20 points)
- ✅ Quality assessment across degrees
- ✅ Convergence diagnostics

### Not Covered (Limitations)
- ❌ Parameter recovery analysis (fixture has no p_true)
- ❌ Campaign-wide analysis (single experiment fixture)
- ❌ Basis comparison (only Chebyshev fixture)
- ❌ Mode 1-5 interactive script integration (needs separate test)

## Success Criteria

**All tests pass if**:
1. ✅ All fixture files load without errors
2. ✅ Objective function evaluates correctly on all test points
3. ✅ Refinement achieves ≥70% convergence rate
4. ✅ Refined values ≤ raw values (improvements or same)
5. ✅ Quality diagnostics complete without errors
6. ✅ L2 norm decreases with higher degree (6 < 4)
7. ✅ No NaN, Inf, or out-of-domain values
8. ✅ Diagnostics fields populated (f_calls, time, convergence_reason)

## Troubleshooting

### Test Fails: "Fixture files not found"
**Solution**: Ensure you're running from package root:
```bash
cd /path/to/globtimpostprocessing
julia --project=. test/run_integration_tests.jl
```

### Test Fails: "deuflhard_4d_fixture not defined"
**Solution**: The test includes `test_functions.jl` automatically. Check the file exists:
```bash
ls test/fixtures/test_functions.jl
```

### Test Fails: Low convergence rate (<70%)
**Possible causes**:
- Optim.jl version mismatch
- Numerical precision issues
- Timeout too short

**Solution**: Check refinement config:
```julia
result = refine_critical_point(f, p; max_iterations=1000, f_abstol=1e-8)
```

### Test Fails: Quality diagnostics errors
**Possible causes**:
- Missing `quality_thresholds.toml`
- TOML parsing issues

**Solution**: Verify config file exists:
```bash
ls quality_thresholds.toml
cat quality_thresholds.toml  # Check format
```

## Regenerating Fixtures

If fixtures become outdated or need updating:

```bash
cd /path/to/globtimcore/test/fixtures
julia --project=../.. generate_postprocessing_fixtures.jl
```

**When to regenerate**:
- After globtimcore CSV format changes
- After critical point filtering logic updates
- To update with latest algorithms

**Time**: ~20 seconds

## Future Extensions

**To add**:
1. ✅ Parameter recovery tests (need fixture with p_true, e.g., Lotka-Volterra)
2. ✅ Campaign-level integration test (multiple experiments)
3. ✅ Basis comparison test (Chebyshev vs Legendre fixtures)
4. ✅ Mode 1-5 script integration test (analyze_experiments.jl)
5. ✅ Export functionality test (markdown/CSV/JSON reports)

## Related Documentation

- `test/fixtures/README.md` - Fixture data description
- `test/test_refinement_phase1.jl` - Refinement unit tests (simple functions)
- `test/test_quality_diagnostics.jl` - Quality diagnostics unit tests
- `CONSOLIDATION_PLAN.md` - Overall integration plan

---

**Status**: ✅ Implemented and ready for testing
**Last Updated**: 2025-11-24
**Maintainer**: GlobtimPostProcessing Team
