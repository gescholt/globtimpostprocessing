# VegaLite Integration for GlobtimPostProcessing

## Quick Start - Minimal L2 Plot

We've implemented a simple, test-driven approach starting with L2 error visualization.

### Files Created

1. **`src/VegaPlotting_minimal.jl`** - Minimal VegaLite plotting functions
   - `campaign_to_l2_dataframe()` - Convert campaign to simple DataFrame
   - `plot_l2_convergence()` - Create L2 error line plot

2. **`examples/test_minimal_l2_plot.jl`** - Test script for minimal plot

### Usage

```bash
cd /path/to/globtimpostprocessing

# Test with a campaign directory
julia --project=. examples/test_minimal_l2_plot.jl \
    ../globtimcore/experiments/lotka_volterra_4d_study/configs_20251006_160051/hpc_results
```

### What It Does

1. Loads campaign results
2. Computes statistics for all experiments
3. Extracts L2 errors for each experiment and degree
4. Creates an interactive line plot with:
   - X-axis: Polynomial degree
   - Y-axis: L2 error (log scale)
   - Color: Experiment ID
   - Tooltips on hover
5. Opens the plot in your default browser

### Example Output

```
Testing Minimal L2 Plot
============================================================

Campaign: ../globtimcore/experiments/.../hpc_results

[1/4] Loading campaign...
✓ Loaded 4 experiments

[2/4] Computing statistics...
✓ Statistics computed

[3/4] Creating L2 DataFrame...
✓ DataFrame created with 20 rows
  Columns: ["experiment_id", "degree", "l2_error"]
  Experiments: 4
  Degrees: [2, 3, 4, 5, 6]

[4/4] Creating VegaLite plot...
✓ Plot created!

SUCCESS! Opening plot in browser...
```

### Current Status

✅ **Working**: Minimal L2 error visualization
⏳ **Next**: Add interactive features incrementally
⏳ **Future**: Add more metrics (parameter recovery, condition numbers, etc.)

### Dependencies

- VegaLite.jl - Declarative visualization
- DataFrames.jl - Data manipulation
- GlobtimPostProcessing - Campaign loading and statistics

### Development Approach

Following TDD (Test-Driven Development):
1. ✅ Start with simplest thing (L2 plot)
2. Test with real data
3. Add features incrementally
4. Keep each step working

## Next Steps

Once the minimal L2 plot is confirmed working, we can add:

1. **Interactive selection** - Click to filter experiments
2. **Multiple metrics** - Add parameter recovery, condition numbers
3. **Faceted plots** - Compare multiple metrics side-by-side
4. **Summary statistics** - Add convergence analysis
5. **Baseline comparison** - Compare experiments to a baseline

Each feature will be added incrementally with testing.

## Troubleshooting

### "No L2 error data available"

Check that experiments have `approximation_quality` statistics:
```julia
campaign = load_campaign_results("path/to/campaign")
campaign_stats = Dict()
for exp in campaign.experiments
    stats = compute_statistics(exp)
    println("$(exp.experiment_id): ", keys(stats))
    campaign_stats[exp.experiment_id] = stats
end
```

### Plot doesn't open

Set browser manually:
```julia
ENV["BROWSER"] = "firefox"  # or "chrome", "safari"
```

### Permission denied

Make script executable:
```bash
chmod +x examples/test_minimal_l2_plot.jl
```
