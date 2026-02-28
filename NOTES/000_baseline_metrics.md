# Baseline metrics

Using the `summary.json` entries under `metrics/`, one row per scene. For scenes with multiple summaries, this table uses the comparable baseline run with `scale=2.0` and `frames=4`.

| Scene                   | Total Cycles | Cycles/Pixel/Frame |
| ----------------------- | ------------ | ------------------ |
| canonical_balls         | 1,391,540    | 150.992            |
| chicken                 | 8,319,737    | 902.749            |
| knight                  | 22,090,714   | 2396.996           |
| shiny_balls             | 3,981,312    | 432.000            |
| shiny_balls_small_walls | 2,162,554    | 234.652            |
| super_shiny_balls       | 4,727,808    | 513.000            |

This is our baseline. We would like to improve against this.

For the active RMSE scenes, these baseline cycles-per-pixel-per-frame values are also copied into `tools/ref/s2f4/manifest.json` as `baseline_cppf`.
