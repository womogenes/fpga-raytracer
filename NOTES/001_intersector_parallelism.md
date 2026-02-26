# Summary

The current ray tracer spends most of its time in intersection, not reflection, once scenes get beyond a handful of objects. `ray_reflector` is a fixed 37-cycle stage, while `ray_intersector` takes `29 + num_objs` cycles and `ray_tracer` serializes the two. The best throughput win is therefore not squeezing the reflector harder, but allowing more ray work to overlap and making scene delivery compatible with parallel lanes.

The one concrete math-kernel experiment worth testing is a 1-cycle `fp_add`. The current 2-cycle production adder already had strong margin in an earlier out-of-context probe, so any 1-cycle replacement has to prove itself with simulation first and then post-route timing.

## Current cycle model

`ray_tracer` is a strict `IDLE -> INTX -> REFLECT` FSM. There is no overlap between intersection and reflection. A hit launches `ray_reflector`, a miss skips it entirely.

`ray_reflector` is exactly 37 cycles from `hit_valid` to `reflect_done`.

`ray_intersector` takes `29 + num_objs` cycles from its `ray_valid` pulse to `hit_valid`. The `29` comes from the fixed sphere-aligned pipeline depth, and the extra `num_objs` comes from scanning one object result per cycle.

The hit-path share of reflector work is therefore:

`37 / (37 + 29 + num_objs) = 37 / (66 + num_objs)`

## Reflector utilization

On misses, reflector utilization is zero because reflection is skipped.

On hit paths, the reflector fraction falls quickly as scene size grows:

| `num_objs` | Intersector cycles | Reflector cycles | Reflector share |
|---|---:|---:|---:|
| `5` | `34` | `37` | `52.1%` |
| `12` | `41` | `37` | `47.4%` |
| `142` | `171` | `37` | `17.8%` |
| `405` | `434` | `37` | `7.9%` |

That means the reflector is only competitive with the intersector on very small scenes. On larger scenes it is mostly waiting for intersection to finish.

## Why simple intersector replication is not enough

Adding more intersectors alone does not solve the main bottlenecks.

`ray_tracer` only allows one ray in flight, so a simple queue in front of the existing FSM is not enough. The scheduler itself has to support multiple outstanding rays.

`scene_buffer` exposes a single free-running object stream with no request or ready interface. That makes it awkward to feed multiple independent lanes safely, and it prevents lane-local replay or targeted object fetch.

If extra intersectors are added without fixing scheduling and scene delivery, they mostly increase area without unlocking the intended throughput gain.

## What parallelism would actually help

The useful architecture is a multi-ray design:

1. Keep multiple rays in flight at once.
2. Give each lane its own local nearest-hit reduction state.
3. Replace the current free-running scene stream with banked, duplicated, or request-driven scene delivery.
4. Merge or queue reflection work explicitly instead of hiding it behind the current serialized FSM.

That is the real path to making intersector parallelism pay off.

## Candidate cycle reductions inside existing modules

The highest-value cycle reduction is inside `ray_tracer`, not the math kernels. The TODO already points at removing the strict FSM behavior and allowing the intersector input to choose between new rays and reflected rays more directly.

The next useful place to look is `ray_reflector`. It has obvious special-case opportunities for fully diffuse or fully specular material behavior, where some of the blend-style work could be bypassed. Those changes need correctness checks and timing review, but they are more promising than trying to compress heavy FP kernels blindly.

`ray_caster` is also assuming the tracer is always slower. Making that interface backpressure-safe would matter once the tracer becomes more parallel.

Inside the intersectors, `sphere_intersector` is dominated by the `quadratic_solver` path. It is `29` cycles total, with `16` cycles already consumed inside the quadratic stage and the rest mostly spent on vector-dot, scaling, and alignment pipes. That means there is not much cheap slack to remove unless the solver itself changes.

`trig_intersector` is more flexible. Its total latency is `20` cycles, and several of those cycles are there to align the determinant, inverse-determinant, and bounds-check signals. A careful redesign could probably save a couple of cycles there, but it is not likely to produce the kind of throughput improvement that multi-ray scheduling would.

By contrast, `fp_inv`, `fp_inv_sqrt`, and `fp_sqrt` are poor short-term targets for cycle collapse. They are already central to the timing budget and are likely to break 100 MHz without a broader redesign.

## `fp_add` one-cycle hypothesis

The production `fp_add` is a 2-cycle design. An earlier out-of-context probe showed it already has healthy 100 MHz margin, so it is safe as-is.

The interesting question is whether a 1-cycle adder is possible if it is implemented carefully enough. The right way to test that is:

1. Build one or more experimental 1-cycle adders in isolation.
2. Verify correctness before synthesis.
3. Benchmark them using a focused top-level synth harness at 100 MHz.

The most plausible route is not just deleting a pipeline stage. It is making the 1-cycle logic friendlier to the FPGA fabric by keeping the add/subtract on the carry chain and reducing the cost of leading-zero detection and normalization.

The current experiment setup does exactly that: it keeps the add/subtract on a narrow carry-chain-friendly path, uses a direct leading-zero detector instead of a generic pipelined helper, and bypasses useless alignment work when the exponent gap is larger than the mantissa precision. The remaining question is whether that is enough to survive post-route timing at 100 MHz.

## Recommendation

Do not treat the reflector as the main limiter for realistic scenes. Treat intersector throughput and tracer scheduling as the main performance problem.

Do pursue a careful 1-cycle `fp_add` experiment, but only as an experiment. Keep the current production 2-cycle `fp_add` unless a 1-cycle candidate passes simulation and post-route timing cleanly at 100 MHz.
