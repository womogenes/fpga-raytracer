# Purpose

Use this repo to evaluate HDL changes under `hdl/` for both implementation efficiency and rendered-image correctness.

# Synthesis flow

Run `python3 tools/vivado_metrics.py` from this directory. On macOS, this uses the Dockerized Vivado setup under `~/code/vivado` and reports post-route `Slice LUTs`, `WNS`, `TNS`, and whether timing met.

# Rendering flow

Run `python3 tools/render_scene_parallel.py` from this directory. By default it renders `ctrl/scenes/canonical_balls.json`; pass `--json` to use another scene. It writes PNGs under `images/<scene>/<timestamp>/` and run logs plus metrics under `metrics/<scene>/<timestamp>/`.

# Correctness metrics

Use the rendered PNGs to compare against `images/<scene>/_gold/`. The render tool reports `raw_rmse_vs_run1`, `blur_rmse_vs_run1`, and `expected_correct_value` for both metrics. Lower is better; compare candidates against the scene-matched gold set.

# Efficiency metrics

Use the render metrics JSON to read `total_cycles` and `cycles_per_pixel_per_frame`. Use the Vivado tool for implementation metrics and the render metrics for runtime cost.
