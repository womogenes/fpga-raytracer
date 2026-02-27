## Reflector Repipeline

### Goal

Reduce end-to-end render cycles by shortening the reflector path that all surfaces pay, especially the diffuse-heavy `canonical_balls` scene.

### Baseline Reflector Structure

The original reflector serialized requests behind a local busy bit and mixed together:

- material read
- diffuse random-direction generation
- specular reflection
- glossy lerp + renormalize
- origin offset
- bounce color / emitted-light accumulation

The key throughput problem was not just arithmetic latency. The module only handled one hit at a time.

### Current Design

The current `ray_reflector.sv` is a streaming, ordered pipeline:

- accepts a new hit every cycle
- classifies each hit into `fast` or `blend`
- keeps request order with:
  - an order FIFO
  - a fast payload FIFO
  - a blend payload FIFO
- emits one ordered completion per cycle once results are ready

The latency classes are now:

- fast path: `10` cycles in the cocotb timing convention
- blend path: `21` cycles in the cocotb timing convention

Those are the timings used by [test_ray_reflector.py](/Users/wyf/code/fpga/fpga-raytracer-v3/fpga-raytracer-v3-reflector-repipe/sim/rtx/test_ray_reflector.py).

### Arithmetic Changes

The latency reduction comes from shortening the common normalization-heavy path, not from adding material-specific bypasses.

Implemented changes:

- added `one_sub_smoothness` to `material`
- precomputed `1.0 - smoothness` in scene export
- added `fp_inv_sqrt_fast` and `fp_vec3_normalize_fast`
- used the fast normalize path for:
  - diffuse bounce direction
  - final glossy blended direction
- added `prng_sphere_lfsr_fast` so the diffuse random-vector path matches the shorter normalization flow

### Testbench Hardening

Reflector unit tests now:

- use isolated cocotb build dirs
- check the reflector timing convention with `ReadOnly()` sampling
- include a burst test with back-to-back mixed-latency requests
- verify ordered one-per-cycle completions through the streaming interface

One simulator caveat remains in Icarus:

- `new_origin.y` can carry unresolved bits in zero-lane cases
- the burst-order check keys off `new_origin.x`, which is stable and sufficient for ordered-stream verification

### End-to-End Verification

Verified sequentially with `--scale 2 --frames 4` and `--enforce-gold`:

- `canonical_balls`
  - cpppf: `117.04036458333333`
  - raw RMSE: `104.32481328364152`
  - blur RMSE: `42.25805314440735`
  - speedup vs baseline: `22.49%`

- `chicken`
  - cpppf: `811.443359375`
  - raw RMSE: `29.411605442787753`
  - blur RMSE: `4.3404222198187465`
  - speedup vs baseline: `10.11%`

- `knight`
  - cpppf: `2281.734917534722`
  - raw RMSE: `44.54543593083941`
  - blur RMSE: `6.551589254467901`
  - speedup vs baseline: `4.81%`

Combined total-cycle improvement across those three runs:

- baseline total cycles: `31,801,991`
- new total cycles: `29,585,375`
- net improvement: `6.97%`

### Render Harness Fix

`test_rtx_parallel.py` now isolates per-invocation simulator scratch state:

- per-run chunk directory
- per-run Verilator build directory

This prevents concurrent scene renders from overwriting each other's copied `.mem` files and chunk outputs.
