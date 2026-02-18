# VegaLite + Data Processing Integration

**Status**: Phase 1 Complete ✅
**Date**: October 7, 2025
**Component**: Data Visualization & Analysis Pipeline

---

## Objective

Integrate VegaLite.jl for interactive data visualization with data transformation pipeline for campaign analysis in globtimpostprocessing.

## Approach: Test-Driven Development (TDD)

Following a minimal, incremental approach:
1. Start with simplest visualization (L2 error plot)
2. Test with real campaign data
3. Add features incrementally
4. Expand to additional metrics only after core functionality works

---

## Phase 1: Minimal L2 Visualization ✅

### Implementation

**Files Created:**

1. **`src/VegaPlotting_minimal.jl`** (100 lines)
   ```julia
   # Core functions:
   - campaign_to_l2_dataframe(campaign, campaign_stats) -> DataFrame
   - plot_l2_convergence(campaign, campaign_stats) -> VLSpec
   ```
   - Extracts L2 approximation errors from campaign statistics
   - Creates interactive line plot with log scale
   - Uses pure DataFrames.jl (no Tidier dependency)

2. **`examples/test_minimal_l2_plot.jl`** (Test harness)
   - Loads campaign results
   - Computes statistics
   - Displays L2 convergence plot
   - Step-by-step output for debugging

3. **`README_VEGALITE.md`** (Documentation)
   - Usage instructions
   - Troubleshooting guide
   - Development roadmap

### Visualization Features

**L2 Convergence Plot:**
- **X-axis**: Polynomial degree (ordinal)
- **Y-axis**: L2 approximation error (log scale)
- **Color encoding**: Experiment ID
- **Interactive tooltips**: Hover to see details
- **Browser-based**: Opens in default browser via VegaLite

### Data Pipeline

```
Campaign Results
    ↓
Statistics Computation (compute_statistics)
    ↓
DataFrame Extraction (campaign_to_l2_dataframe)
    ↓
VegaLite Specification (plot_l2_convergence)
    ↓
Interactive Browser Visualization
```

### Testing

**Test Command:**
```bash
cd /path/to/globtimpostprocessing
julia --project=. examples/test_minimal_l2_plot.jl \
    ../globtimcore/experiments/lotka_volterra_4d_study/configs_20251006_160051/hpc_results
```

**Expected Output:**
```
Testing Minimal L2 Plot
============================================================
Campaign: .../hpc_results

[1/4] Loading campaign...
✓ Loaded N experiments

[2/4] Computing statistics...
✓ Statistics computed

[3/4] Creating L2 DataFrame...
✓ DataFrame created with M rows
  Columns: ["experiment_id", "degree", "l2_error"]
  Experiments: N
  Degrees: [2, 3, 4, ...]

[4/4] Creating VegaLite plot...
✓ Plot created!

SUCCESS! Opening plot in browser...
```

---

## Design Decisions

### 1. No Tidier.jl Dependency

**Decision**: Use pure DataFrames.jl for transformations

**Rationale**:
- Simpler dependency tree
- More predictable behavior
- Standard Julia ecosystem
- Easier debugging

**Alternative Considered**: Full Tidier.jl integration with dplyr-like syntax
- **Issue**: Complex macro expansion, compilation errors
- **Trade-off**: More verbose code but guaranteed to work

### 2. Minimal Surface Area

**Decision**: Start with just 2 functions

**Rationale**:
- Test-driven approach requires working baseline
- Easy to verify correctness
- Clear path for incremental features
- Reduces debugging surface

### 3. Browser-Based Visualization

**Decision**: Use VegaLite's browser rendering

**Rationale**:
- Full interactivity (zoom, pan, tooltips)
- Publication-ready graphics
- Easy to save as HTML/PNG/SVG
- No additional visualization backend needed

---

## Phase 2: Interactive Features (Pending)

Once Phase 1 is tested and working, add:

### 2.1 Linked Selection

```julia
# Click experiments in legend to filter
# Select regions to zoom
@vlplot(
    selection = {
        exp_select = {type = :multi, fields = [:experiment_id], bind = :legend}
    },
    encoding = {
        opacity = {
            condition = {selection = :exp_select, value = 1.0},
            value = 0.2
        }
    }
)
```

### 2.2 Multi-View Dashboard

```julia
@vlplot(
    vconcat = [
        # View 1: Experiment selector
        {mark = :bar, ...},
        # View 2: L2 convergence (filtered)
        {mark = :line, transform = [{filter = {param = :brush}}], ...}
    ]
)
```

---

## Phase 3: Additional Metrics (Pending)

After interactive features work, expand to:

### 3.1 Parameter Recovery

```julia
function plot_parameter_recovery(campaign, campaign_stats)
    # Extract param_recovery_error from statistics
    # Create convergence plot similar to L2
end
```

### 3.2 Multi-Metric Comparison

```julia
function plot_multi_metric(campaign, campaign_stats)
    # Faceted plot showing L2, parameter recovery, condition numbers
    # Uses DataFrames.stack() to create long-format data
end
```

### 3.3 Convergence Analysis

```julia
function plot_convergence_quality(campaign, campaign_stats)
    # Compute convergence rates
    # Classify experiments by quality
    # Show distribution
end
```

---

## Phase 4: Statistical Analysis (Future)

### 4.1 Data Transformations

```julia
# Pure DataFrames.jl implementations
function compute_convergence_metrics(df::DataFrame)
    # Group by experiment
    # Compute error reduction rates
    # Add quality classifications
end

function compute_efficiency_metrics(df::DataFrame)
    # Combine timing data with errors
    # Compute error/time ratios
end
```

### 4.2 Advanced Visualizations

- Parameter sensitivity plots
- Outlier detection with z-scores
- Baseline comparisons (improvement ratios)
- Efficiency analysis (computational cost vs accuracy)

---

## Current Status Summary

### ✅ Complete

- [x] Minimal L2 visualization infrastructure
- [x] Test harness for validation
- [x] Documentation (README, usage guide)
- [x] Pure DataFrames.jl pipeline (no Tidier issues)

### ⏳ Ready for Testing

- [ ] Test with real campaign data
- [ ] Verify browser rendering works
- [ ] Validate data extraction correctness
- [ ] Check plot interactivity

### 📋 Pending (After Phase 1 Validation)

- [ ] Add interactive selection
- [ ] Multi-view dashboards
- [ ] Additional metrics (param recovery, condition numbers)
- [ ] Convergence analysis
- [ ] Statistical transformations

---

## Dependencies

### Required
- **VegaLite.jl** v3.3.0 - Declarative visualization grammar
- **DataFrames.jl** v1.6 - Data manipulation
- **Statistics** (stdlib) - Basic statistics

### Not Used (Removed)
- ~~Tidier.jl~~ - Caused compilation issues, replaced with pure DataFrames

### Existing
- **GlobtimPostProcessing** - Campaign loading, statistics computation

---

## Known Issues

### None Currently

Phase 1 minimal implementation designed to avoid known pitfalls:
- ✅ No complex macro expansions
- ✅ No Tidier.jl dependency issues
- ✅ Simple, testable functions
- ✅ Standard DataFrames operations

---

## Validation Checklist

Before proceeding to Phase 2, validate:

- [ ] `plot_l2_convergence()` renders in browser
- [ ] All experiments appear in plot
- [ ] Log scale shows proper error reduction
- [ ] Tooltips display correct information
- [ ] Colors distinguish experiments clearly
- [ ] Data extraction matches expected values

---

## References

### Internal Documentation
- `README_VEGALITE.md` - Usage guide
- `docs/tidier_vega_guide.md` - Advanced features (for future phases)

### External Resources
- [VegaLite.jl Documentation](https://www.queryverse.org/VegaLite.jl/stable/)
- [Vega-Lite Grammar](https://vega.github.io/vega-lite/)
- [DataFrames.jl Documentation](https://dataframes.juliadata.org/)

---

## Next Actions

1. **Test Phase 1** with real campaign data
2. **Validate** L2 plot renders correctly
3. **Document** any issues encountered
4. **Proceed to Phase 2** only after Phase 1 confirmed working

---

**Last Updated**: October 7, 2025
**Author**: Development with Claude Code
**Review Status**: Awaiting Phase 1 testing
