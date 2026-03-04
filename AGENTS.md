# Purpose

Use this repo to evaluate HDL changes under `hdl/` for both implementation efficiency and rendered-image correctness.

# Synthesis flow

Run `python3 tools/vivado_metrics.py` from this directory. On macOS, this uses the Dockerized Vivado setup under `~/code/vivado` and reports post-route `Slice LUTs`, `WNS`, `TNS`, and whether timing met.

# Rendering flow

Run `python3 tools/render_scene_parallel.py [scene_name]` from this directory. The tool assumes scenes live under `ctrl/scenes/<scene_name>.json`, renders at the fixed `scale=2` and `frames=4` settings from `tools/ref/s2f4/manifest.json`, and prints a short pass/fail report with RMSEs and elapsed time.

# Correctness metrics

Use the rendered PNGs to compare against `tools/ref/s2f4/<scene>.png`. Thresholds live in `tools/ref/s2f4/manifest.json`, and the render tool reports one raw RMSE and one blur RMSE against that inferred reference image.

# Efficiency metrics

Use the render metrics JSON to read `total_cycles` and `cycles_per_pixel_per_frame`. Use the Vivado tool for implementation metrics and the render metrics for runtime cost.

## Notes

- When writing docs, only ever use sentence case for headers.
- Be very careful about pipelining and retiming. Sometimes when you modify stuff, other signals change when they arrive. You may have to update hardcoded delay values.
