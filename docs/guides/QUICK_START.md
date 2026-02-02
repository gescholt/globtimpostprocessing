# Quick Start - VegaLite L2 Visualization

## Run the Interactive Demo

```bash
cd /Users/ghscholt/GlobalOptim/globtimpostprocessing

# Run without arguments - it will find campaigns and let you choose
julia --project=. examples/test_minimal_l2_plot.jl
```

## What Happens

1. **Script searches** for campaign directories in:
   - `../globtimcore/experiments`
   - `../globtimcore/hpc_results`
   - `../globtimcore`

2. **You select** a campaign from the list:
   ```
   Found 3 campaign(s):

   [1] ../globtimcore/experiments/.../hpc_results
       → 4 experiment(s)
   [2] ../globtimcore/experiments/.../hpc_results
       → 1 experiment(s)
   [3] ../globtimcore/hpc_results/...
       → 12 experiment(s)

   Select campaign (1-3, or 'q' to quit): _
   ```

3. **Script processes**:
   - Loads campaign results
   - Computes statistics
   - Extracts L2 errors
   - Creates VegaLite plot

4. **Browser opens** with interactive L2 convergence plot:
   - Line chart showing error vs degree
   - Log scale on Y-axis
   - Color-coded by experiment
   - Hover for tooltips
   - Zoom/pan enabled

## Manual Path

You can also provide the path directly:

```bash
julia --project=. examples/test_minimal_l2_plot.jl /path/to/campaign/hpc_results
```

## Expected Output

```
============================================================
Searching for campaign directories...
============================================================

Found 3 campaign(s):

[1] ../globtimcore/experiments/lotka_volterra_4d_study/configs_20251006_160051/hpc_results
    → 1 experiment(s)
[2] ../globtimcore/experiments/lotka_volterra_4d_study/configs_20251005_105246/hpc_results
    → 4 experiment(s)
[3] ../globtimcore/experiments/lotka_volterra_4d_study/configs_20250915_224434/hpc_results
    → 12 experiment(s)

============================================================
Select campaign (1-3, or 'q' to quit): 2

============================================================
Testing Minimal L2 Plot
============================================================

Campaign: ../globtimcore/experiments/lotka_volterra_4d_study/configs_20251005_105246/hpc_results

[1/4] Loading campaign...
✓ Loaded 4 experiments

[2/4] Computing statistics...
✓ Statistics computed

[3/4] Creating L2 DataFrame...
✓ DataFrame created with 20 rows
  Columns: ["experiment_id", "degree", "l2_error"]
  Experiments: 4
  Degrees: [2, 3, 4, 5, 6]

Sample data (first 5 rows):
 Row │ experiment_id                          degree  l2_error
     │ String                                 Int64   Float64
─────┼──────────────────────────────────────────────────────────
   1 │ lotka_volterra_4d_exp1_range0.4_...       2   0.0123
   2 │ lotka_volterra_4d_exp1_range0.4_...       3   0.00234
   3 │ lotka_volterra_4d_exp1_range0.4_...       4   0.000456
   ...

[4/4] Creating VegaLite plot...
✓ Plot created!

============================================================
SUCCESS! Opening plot in browser...
============================================================

✓ Plot displayed!
Press Ctrl+C to exit...
```

## Troubleshooting

### No campaigns found?

The script searches 3 levels deep. If your campaigns are elsewhere:

```bash
# Provide path manually
julia --project=. examples/test_minimal_l2_plot.jl /your/custom/path/hpc_results
```

### Plot doesn't open in browser?

Set your browser manually in Julia:

```julia
ENV["BROWSER"] = "firefox"  # or "chrome", "safari"
```

### Dependencies missing?

Make sure the package environment is instantiated:

```bash
cd /Users/ghscholt/GlobalOptim/globtimpostprocessing
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## What's Next?

After validating this minimal L2 plot works:

1. ✅ **Phase 1 Complete**: Basic L2 visualization
2. ⏳ **Phase 2**: Add interactive filtering (click to select experiments)
3. ⏳ **Phase 3**: Add more metrics (parameter recovery, condition numbers)
4. ⏳ **Phase 4**: Statistical analysis (convergence rates, outlier detection)

---

**Ready to test?** Just run:
```bash
julia --project=. examples/test_minimal_l2_plot.jl
```
