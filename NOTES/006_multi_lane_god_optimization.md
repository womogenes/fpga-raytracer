## Multi-lane god optimization

This branch takes the wavefront tracer from the earlier single-intersector and four-intersector versions to an eight-intersector design that still keeps the rest of the machine simple: one shared work FIFO, one shared reflector, one shared result FIFO, and one broadcast scene-object stream.

The important architectural change beyond simply doubling the lane count was the reflector handoff fix. The first eight-lane attempt failed timing because intersector completion selection and reflector launch were one big combinational cone. The fix was to register the selected done-lane payload for one cycle before feeding `ray_reflector`, which preserved one reflected launch per cycle while cutting the critical path enough to close timing.

## Current Design

- `ray_tracer` now defaults `NUM_INTERSECTORS` to `8`.
- New primary rays and bounced rays share one work FIFO.
- The scheduler launches at most one queued ray per cycle into the lowest-index idle intersector lane.
- All intersector lanes consume the same broadcast `scene_buffer` object stream.
- Completed hits are staged through a one-cycle registered boundary before the shared reflector.
- Misses and final reflected results still retire through the shared result FIFO and explicit pixel coordinates.

## Validation

Focused tests passing on this branch:

- `python3 sim/rtx/test_ray_tracer.py`
- `python3 sim/rtx/test_ray_tracer_scene.py`
- `python3 sim/rtx/test_ray_intersector_multi.py`

Manifest-backed RMSE renders all pass:

| Scene           | Raw RMSE | Blur RMSE |
| --------------- | -------: | --------: |
| canonical_balls |     33.4 |       4.9 |
| chicken         |     22.2 |       4.0 |
| knight          |     21.4 |       3.1 |
| shiny_balls     |     35.0 |       5.3 |

## Performance

Current `scale=2`, `frames=4` cycle counts:

| Scene           | Total Cycles | CPPF   |
| --------------- | -----------: | -----: |
| canonical_balls |      181,869 | 19.734 |
| chicken         |      834,766 | 90.578 |
| knight          |    2,483,200 | 269.444 |
| shiny_balls     |      288,512 | 31.306 |

Cycle improvement versus the recorded baseline in `NOTES/000_baseline_metrics.md`:

| Scene           | Improvement |
| --------------- | ----------: |
| canonical_balls |     +86.93% |
| chicken         |     +89.97% |
| knight          |     +88.76% |
| shiny_balls     |     +92.75% |

Cycle improvement versus prior validated implementations:

| Scene           | vs single-intersector overlap | vs four-intersector |
| --------------- | ----------------------------: | ------------------: |
| canonical_balls |                       +64.74% |              +2.71% |
| chicken         |                       +86.94% |             +48.63% |
| knight          |                       +87.38% |             +49.67% |
| shiny_balls     |                       +81.67% |             +31.11% |

Aggregate totals across the four acceptance scenes:

- baseline: `35,783,303` cycles
- single-intersector overlap: `28,162,880` cycles
- four-intersector: `7,164,144` cycles
- current eight-intersector: `3,788,347` cycles

That is `+89.41%` faster than baseline, `+86.55%` faster than the single-intersector overlap design, and `+47.12%` faster than the prior four-intersector design.

## Implementation snapshot

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
