# Archived Scripts

This directory contains deprecated scripts that have been replaced by the unified `analyze_experiments.jl`.

## Files

### analyze_collected_campaign.jl
- **Deprecated**: 2025-10-15
- **Replaced by**: `analyze_experiments.jl`
- **Reason**: Consolidated into unified analysis script per issue #7
- **Features now in main script**: Parameter recovery, configurable quality thresholds, convergence analysis

### compare_basis_functions.jl
- **Deprecated**: 2025-11-28
- **Replaced by**: `analyze_experiments.jl` (Mode 3: Basis Comparison)
- **Reason**: Being integrated into unified analysis script
- **Original purpose**: Compare Chebyshev vs Legendre polynomial basis experiments
- **Note**: The standalone script still works but is no longer maintained. Use Mode 3 in `analyze_experiments.jl` for basis comparison.

## Main Entry Point

All interactive analysis should now use:

```bash
julia --project=. analyze_experiments.jl
```

This provides a multi-mode interface including:
1. Single experiment analysis
2. Campaign-wide analysis
3. Basis comparison
4. Quality diagnostics
5. Parameter recovery
