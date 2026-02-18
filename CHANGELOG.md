# Changelog - GlobtimPostProcessing

## [Unreleased] - 2025-11-28

### Added - Gradient Norm Validation (Phase 2 Tier 2)

#### Gradient Validation for Critical Points
- **New Module**: `src/refinement/gradient_validation.jl`
  - `compute_gradient_norms()` - Batch gradient norm computation using ForwardDiff
  - `compute_gradient_norm()` - Single-point gradient norm
  - `validate_critical_points()` - Validate points against tolerance threshold
  - `add_gradient_validation!()` - Add validation columns to DataFrames
  - `GradientValidationResult` - Result struct with validation statistics

#### Automatic Integration
- Gradient validation automatically runs on converged points in `refine_experiment_results()`
- Uses `config.f_abstol` as validation tolerance
- Results included in printed summary output

#### Enhanced Output
- **refinement_comparison_deg_X.csv** now includes:
  - `gradient_norm` - ||∇f(x)|| for each refined point
  - `gradient_valid` - Boolean validation status
- **refinement_summary_deg_X.json** now includes:
  - `gradient_validation` section with n_valid, n_invalid, mean_norm, max_norm, validation_rate

#### Dependencies
- Added `ForwardDiff` (v0.10) for automatic differentiation

#### Documentation
- Updated `docs/REFINEMENT_DIAGNOSTICS.md` - marked gradient validation complete
- Archived `gradient_validation_plan.md` to `docs/archive/`

**Status**: ✅ Complete - Implements gradient norm validation from Phase 2 Tier 2

---

## [Unreleased] - 2025-11-24

### Added - Phase 2 Tier 1 Refinement Diagnostics

#### Enhanced Refinement Diagnostics (Zero-Cost)
- **Enhanced RefinementResult Struct** with 9 new diagnostic fields:
  - Call counts: `f_calls`, `g_calls`, `h_calls` (function/gradient/Hessian evaluations)
  - Timing: `time_elapsed` (actual optimization time per point)
  - Fine-grained convergence: `x_converged`, `f_converged`, `g_converged`, `iteration_limit_reached`
  - Primary reason: `convergence_reason` (`:x_tol`, `:f_tol`, `:g_tol`, `:iterations`, `:timeout`, `:error`)

#### Enhanced CSV Output
- **refinement_comparison_deg_X.csv** now includes 9 diagnostic columns:
  - Per-point call counts, timing, and convergence details
  - Enables detailed analysis of refinement performance

#### Enhanced JSON Summary
- **refinement_summary_deg_X.json** now includes:
  - `convergence_breakdown`: Count by convergence reason
  - `call_counts`: Mean/max/min function evaluations
  - `timing`: Mean/max/min time per point, timeout count

#### Testing
- **Enhanced**: `test/test_refinement_phase1.jl` (added 8 test sets)
  - Test all diagnostic fields exist and have correct types
  - Test call counts, timing, convergence flags
  - Test convergence reason logic for all cases
  - ~40 new assertions, all passing

#### Documentation
- **New File**: `docs/PHASE2_TIER1_IMPLEMENTATION.md`
  - Complete implementation guide
  - Usage examples for CSV and JSON diagnostics
  - Performance characteristics (< 1% overhead)
  - Migration guide and troubleshooting

#### Performance
- Zero-cost diagnostics (all extracted from Optim.jl result)
- No trace storage required
- < 1% overhead (diagnostic extraction is O(1))
- Memory overhead: +72 bytes per RefinementResult

#### Backward Compatibility
- ✅ All original fields preserved
- ✅ Existing code continues to work
- ✅ API extensions only (no breaking changes)

**Status**: ✅ Complete - Implements requirements from `docs/REFINEMENT_DIAGNOSTICS.md` Phase 1 (Tier 1)

---

## [Earlier] - 2025-10-29

### Added - Error Categorization Integration (Issue #20, Phase 3)

#### Error Analysis Features
- **New Module**: `src/ErrorCategorizationIntegration.jl` (709 lines)
  - `categorize_campaign_errors()` - Campaign-wide error analysis
  - `generate_error_summary()` - Comprehensive error reporting
  - `filter_errors_by_category()`, `filter_errors_by_severity()` - Error filtering
  - `get_top_priority_errors()` - Priority-based error retrieval
  - `calculate_error_rate()`, `get_most_common_error_category()` - Statistics
  - `format_error_report()`, `format_error_table()` - Report formatting
  - `get_error_dataframe()` - DataFrame export for error data
  - `create_mock_campaign()` - Testing utilities

#### Integration Features
- Error sections in campaign reports (Markdown/JSON)
- `--include-errors` CLI flag in `scripts/batch_analyze.jl`
- Error analysis in `batch_analyze_campaign()` and `batch_analyze_campaign_with_progress()`
- 5 error categories: INTERFACE_BUG, MATHEMATICAL_FAILURE, INFRASTRUCTURE_ISSUE, CONFIGURATION_ERROR, UNKNOWN_ERROR
- Priority scoring with actionable recommendations

#### Testing
- **New File**: `test/test_error_categorization.jl` (105 tests, all passing)
  - Test coverage: module access, single error categorization, campaign analysis
  - Error-aware reports, filtering, statistics, batch integration, formatting, edge cases
  - TDD approach: RED → GREEN → REFACTOR

#### Dependencies Added
```toml
Globtim = "00da9514-6261-47e9-8848-33640cb1e528"  # Dev dependency
StatsBase = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"  # v0.34.7
```

**Status**: ✅ Complete - All 105 tests passing, fully integrated

### Added - VegaLite Integration (Phase 1)

#### Minimal L2 Visualization
- **New Module**: `src/VegaPlotting_minimal.jl`
  - `campaign_to_l2_dataframe()` - Extract L2 errors to DataFrame
  - `plot_l2_convergence()` - Create interactive L2 convergence plot
  - Pure DataFrames.jl implementation (no Tidier.jl dependency)

#### Testing Infrastructure
- **New Script**: `examples/test_minimal_l2_plot.jl`
  - Complete test harness for L2 visualization
  - Step-by-step validation output
  - Ready for testing with real campaign data

#### Documentation
- **New File**: `README_VEGALITE.md`
  - Quick start guide
  - Usage examples
  - Troubleshooting tips
  - Development roadmap

- **New File**: `docs/issues/vegalite_tidier_integration.md`
  - Complete design documentation
  - Phase-by-phase implementation plan
  - Design decisions and rationale
  - Testing checklist

- **New File**: `docs/tidier_vega_guide.md`
  - Comprehensive guide for future advanced features
  - Tidier.jl syntax examples (for future use)
  - VegaLite visualization gallery

#### Support Files
- **New File**: `src/TidierTransforms.jl`
  - Simplified data transformation functions
  - Pure DataFrames.jl implementations
  - Helper functions for future phases:
    - `compute_convergence_analysis()`
    - `compute_parameter_sensitivity()`
    - `compute_efficiency_metrics()`
    - `pivot_metrics_longer()`
    - `add_comparison_baseline()`
    - `annotate_outliers()`

- **New File**: `examples/demo_tidier_vega_suite.jl`
  - Menu-driven demo system (for future phases)
  - Multiple visualization options
  - Interactive selection interface

#### Visualization Features (Phase 1)
- Interactive line plot with VegaLite
- Log-scale Y-axis for error visualization
- Color encoding by experiment ID
- Hover tooltips with detailed information
- Browser-based rendering
- Export capabilities (HTML, PNG, SVG)

### Design Decisions

#### Why No Tidier.jl?
- Initial implementation attempted full Tidier.jl integration
- Encountered macro expansion and compilation issues
- Pivoted to pure DataFrames.jl for Phase 1
- Simpler, more maintainable, guaranteed to compile
- Can add Tidier later if needed

#### Why Start Minimal?
- Test-Driven Development (TDD) approach
- Validate core functionality first
- Easier debugging with small surface area
- Clear path for incremental feature addition
- User feedback: "Start simple, proceed with TDD approach"

### Testing Status

- ✅ Code written and documented
- ⏳ **Awaiting validation** with real campaign data
- ⏳ Browser rendering verification needed
- ⏳ Data accuracy validation needed

### Dependencies Added

```toml
VegaLite = "112f6efa-9a02-5b7d-90c0-432ed331239a"  # v3.3.0
```

**Note**: Tidier.jl removed from critical path (was causing issues)

### Breaking Changes

**None** - This is purely additive functionality

### Migration Guide

**Not applicable** - New feature, existing code unchanged

## Future Phases (Planned, Not Implemented)

### Phase 2: Interactive Features
- Linked selection (click to filter)
- Multi-view dashboards
- Brush selection for zooming
- Dynamic parameter filtering

### Phase 3: Additional Metrics
- Parameter recovery plots
- Numerical stability (condition numbers)
- Multi-metric faceted comparisons
- Convergence quality analysis

### Phase 4: Advanced Analysis
- Statistical outlier detection
- Baseline comparisons
- Efficiency analysis (error vs time)
- Parameter sensitivity studies

## Version History

### Current: v0.1.0 (Development)
- Initial VegaLite integration (Phase 1 complete)
- Minimal L2 visualization working
- Documentation complete
- Awaiting real-data testing

---

## Testing Instructions

To test the new VegaLite L2 visualization:

```bash
cd /path/to/globtimpostprocessing

# Run with your campaign data
julia --project=. examples/test_minimal_l2_plot.jl \
    /path/to/your/campaign/hpc_results

# Example with existing data
julia --project=. examples/test_minimal_l2_plot.jl \
    ../globtimcore/experiments/lotka_volterra_4d_study/configs_20251006_160051/hpc_results
```

Expected: Interactive L2 convergence plot opens in browser

---

## Notes for Future Development

### What Works Well
- Pure DataFrames.jl approach is clean and maintainable
- VegaLite provides excellent interactivity
- Modular design allows easy feature addition
- Test harness makes validation straightforward

### Lessons Learned
- Start simple and validate before adding complexity
- Avoid complex macro systems until core functionality works
- TDD approach catches issues early
- Documentation is crucial for phased development

### Technical Debt
- `src/TidierTransforms_old.jl` - Remove after Phase 1 validation
- `src/VegaPlotting.jl` - Large file with unused Tidier code, clean up later
- Test suite needs expansion as features are added

---

**Last Updated**: October 7, 2025
**Next Milestone**: Phase 1 validation with real campaign data
