## Multi-Intersector Wavefront Summary

This branch widens the wavefront tracer from one intersector lane to eight parallel intersector lanes while keeping the rest of the architecture simple: one shared work FIFO, one shared reflector, one shared result FIFO, and one broadcast scene-object stream.

`ray_tracer` can now keep up to `NUM_INTERSECTORS` intersection sweeps active at once. Each lane owns its own in-flight ray context and nearest-hit reduction state, and completed lanes are merged back into the existing miss-or-reflect path.

## Current Design

- `ray_tracer` now has a compile-time `NUM_INTERSECTORS` parameter, currently defaulted to `8`.
- New primary rays and bounced rays share the same work FIFO.
- The intersector scheduler launches at most one queued ray per cycle into the lowest-index idle lane.
- All intersector lanes consume the same broadcast `scene_buffer` object stream.
- `ray_reflector` is still shared and fixed-latency. Hit completions are selected from the done lane and then either:
  - emit a miss/final pixel into the result FIFO, or
  - feed the shared reflector and requeue the bounced ray.
- Pixel retirement remains coordinate-based, so completions may come back out of raster order without changing framebuffer semantics.

## Validation

Focused tests passing on this branch:

- `python3 sim/rtx/test_ray_tracer.py`
- `python3 sim/rtx/test_ray_tracer_scene.py`
- `python3 sim/rtx/test_ray_intersector_multi.py`
- `python3 sim/rtx/test_rtx_parallel.py --scale 0.25 --frames 1 --chunks 1 --json ctrl/scenes/canonical_balls.json --data-dir /tmp/fpga-raytracer-data --output-prefix /tmp/fpga-raytracer-out`

Current smoke result:

- `canonical_balls`, `8x4`, `1` frame: `771` total cycles, `24.094` cycles/pixel/frame

Full render acceptance from the current eight-lane RTL:

| Scene           | Raw RMSE | Blur RMSE |
| --------------- | -------: | --------: |
| canonical_balls |     33.4 |       4.9 |
| chicken         |     22.2 |       4.0 |
| knight          |     21.4 |       3.1 |
| shiny_balls     |     35.0 |       5.3 |

## Performance

Speedup is measured against `tools/ref/s2f4/manifest.json` baseline `cppf`.

| Scene           | Current CPPF | Baseline CPPF | Speedup |
| --------------- | -----------: | ------------: | ------: |
| canonical_balls |       19.734 |       150.992 | +86.93% |
| chicken         |       90.578 |       902.749 | +89.97% |
| knight          |      269.444 |      2396.996 | +88.76% |
| shiny_balls     |       31.306 |       432.000 | +92.75% |

Weighted across the four manifest scenes, the branch is `+89.41%` faster overall.

## Implementation Snapshot

Post-route timing on the current eight-lane tree meets timing:

- `WNS = 0.081 ns`
- `TNS = 0.000 ns`
- `WHS = 0.035 ns`
- `THS = 0.000 ns`

Post-route utilization:

- `97,467` Slice LUTs
- `134,197` Slice Registers
- `40` BRAM tiles
- `495` DSPs
