## Single-Lane Wavefront Summary

This branch changes the tracer from a single-ray `IDLE -> INTX -> REFLECT` loop into a single-lane wavefront scheduler. Primary rays and bounced rays now share a work queue in `ray_tracer`, the reflector is fixed-latency and fully pipelined at the module boundary, and `ray_caster` launches whenever the tracer can accept more work instead of waiting for global `ray_done`.

The main correctness bug found during bring-up was not the wavefront scheduling itself. `ray_reflector` had a one-cycle output alignment bug: `reflect_done` and the color outputs were fixed at 37 cycles, but `new_origin` was still one cycle early. That corrupted back-to-back reflected rays. The fix was to align `new_origin` to the same output contract and add a back-to-back reflector test.

## Current Design

- `ray_caster` accepts a new launch when `ray_ready` is high and no maker request is already pending.
- `ray_tracer` owns:
  - one shared work FIFO for primary and bounced rays
  - one active intersector context
  - one fixed-latency reflector sideband pipe
  - one result FIFO for completed pixels
- Bounce rays have priority over new primary launches when re-entering the intersector work queue.
- The scene stays single-lane and single-stream: there is still only one intersector sweep active at a time.

## Validation

Focused tests:

- `python3 sim/rtx/test_ray_reflector.py`
- `python3 sim/rtx/test_ray_tracer.py`
- `python3 sim/rtx/test_ray_tracer_scene.py`
- `python3 sim/rtx/test_rtx_parallel.py --scale 0.25 --frames 1 --chunks 1 --json ctrl/scenes/canonical_balls.json --data-dir /tmp/fpga-raytracer-data --output-prefix /tmp/fpga-raytracer-out`

Latest smoke result:

- `canonical_balls` `8x4`, `1` frame: `1769` total cycles, `55.281` cycles/pixel/frame

Acceptance renders all pass current manifest thresholds:

| Scene           | Raw RMSE | Blur RMSE |
| --------------- | -------: | --------: |
| canonical_balls |     34.4 |       5.4 |
| chicken         |     22.8 |       4.0 |
| knight          |     21.2 |       3.4 |
| shiny_balls     |     35.5 |       5.6 |

## Performance

Speedup below is relative to `tools/ref/s2f4/manifest.json` baseline `cppf`.

| Scene           | Current CPPF | Baseline CPPF | Speedup |
| --------------- | -----------: | ------------: | ------: |
| canonical_balls |       55.968 |       150.992 | +62.93% |
| chicken         |      693.289 |       902.749 | +23.20% |
| knight          |     2135.806 |      2396.996 | +10.90% |
| shiny_balls     |      170.806 |       432.000 | +60.46% |

Weighted over the four manifest scenes, the branch is `+21.30%` faster overall.

## Implementation Snapshot

Post-route timing on the current tree meets timing:

- `WNS = 0.178 ns`
- `TNS = 0.000 ns`
- `WHS = 0.062 ns`
- `THS = 0.000 ns`

Post-route utilization:

- `27,610` Slice LUTs
- `40,177` Slice Registers
- `40` BRAM tiles
- `131` DSPs
