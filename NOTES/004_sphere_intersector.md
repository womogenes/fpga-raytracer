# Sphere intersector latency reduction

## Final change

Accepted a radical sphere-only fast path and reduced `SPHERE_INTX_DELAY` from `29` to `20` cycles to match `TRIG_INTX_DELAY`.

The accepted design keeps the same sphere-intersection equation:

- `L = ray_origin - sphere_center`
- `b = 2 * dot(ray_dir, L)`
- `c = dot(L, L) - sphere_rad_sq`
- `x0 = (-b - sqrt(b*b - 4*c)) / 2`

What changed is the local implementation of the expensive building blocks:

- `fp_vec3_add` for `L`, `hit_pos`, and `hit_norm_prenorm`
- `fp_vec3_dot` for the two sphere dot products
- `fp_inv_sqrt`
- `fp_sqrt`
- `quadratic_solver`

The first accepted version used temporary `*_fast` wrapper modules for these blocks.
Those wrappers were later folded back into the canonical module names during cleanup
so the repo keeps one implementation per primitive.

The accepted sphere timing is:

- `L` add: 1 cycle
- two fast dots plus radius alignment: 4 cycles
- `b` / `c` formation: 1 more cycle
- `quadratic_solver`: 12 cycles
- `ray_dir * x0`: 1 cycle
- fast geometry add: 1 cycle
- final `hit_pos` / `hit_norm` alignment: 1 cycle

Total:

- `SPHERE_INTX_DELAY = 20`

Files:

- `hdl/math/sphere_intersector.sv`
- `hdl/math/fp_add.sv`
- `hdl/math/fp_vec3_ops.sv`
- `hdl/math/fp_inv_sqrt.sv`
- `hdl/math/fp_sqrt.sv`
- `hdl/math/quadratic_solver.sv`
- `hdl/rtx/ray_intersector.sv`
- `hdl/tb/top_level_test_sphere_intersector.sv`
- `tcl/build_sphere_intersector_test.tcl`

## Important bug found during bringup

The first fast solver attempt was mathematically wrong in a streaming context even though the single-operation algebra looked correct.

Root cause:

- I removed the register on `four_c` inside `quadratic_solver`
- that mixed `b_sq[n]` with `c[n+1]` under continuous input streaming

Fix:

- restore the one-cycle `four_c` register so `b_sq` and `4*c` stay sample-aligned

That fix preserved the intended `12`-cycle fast solver latency and made the solver regression pass.

## Downstream contract change

`ray_intersector` now sees `SPHERE_INTX_DELAY == TRIG_INTX_DELAY == 20`.

The triangle result alignment path therefore needed a zero-delay bypass instead of an unconditional pipeline with `DEPTH(SPHERE_INTX_DELAY - TRIG_INTX_DELAY)`.

Implemented:

- generated pipeline when `SPHERE_INTX_DELAY > TRIG_INTX_DELAY`
- direct assign bypass when the delays are equal

## Verification

### Module tests

Passed:

- `python3 sim/rtx/test_quadratic_solver.py`
- `python3 sim/rtx/test_sphere_intersector.py`
- `python3 sim/rtx/test_ray_intersector.py`
- `python3 sim/rtx/test_trig_intersector.py`
- `python3 sim/rtx/test_ray_caster.py`

Test-harness fixes made during verification:

- `sim/rtx/test_trig_intersector.py`
  - fixed cocotb module import path
  - forced headless matplotlib
  - removed the crash on empty `missedpoints`
- `sim/rtx/test_ray_caster.py`
  - added missing `hdl/rng/prng8.sv` to the source list
  - fixed cocotb module import path

### Isolated sphere synthesis

Command shape:

- `vivado -mode batch -source tcl/build_sphere_intersector_test.tcl -tclargs radical20`

Result:

- report: `obj_sphere_intersector/radical20/post_route_timing_summary.rpt`
- utilization: `obj_sphere_intersector/radical20/post_route_util.rpt`
- `WNS = 0.859 ns`
- `TNS = 0.000 ns`
- `Slice LUTs = 2870`
- timing met

### Whole design synthesis

Command:

- `python3 tools/vivado_metrics.py`

Result:

- report: `obj_rtx/post_route_timing_summary.rpt`
- utilization: `obj_rtx/post_route_util.rpt`
- `WNS = 0.121 ns`
- `TNS = 0.000 ns`
- `Slice LUTs = 26221`
- timing met

Critical path note:

- the top post-route setup path is still in `highdef_fb/rtx_data_fifo/xpm_fifo_axis_inst/xpm_fifo_base_inst/gen_cdc_pntr.rd_pntr_cdc_inst`
- the top path is not in `fp_add`, `quadratic_solver`, `sphere_intersector`, or `ray_intersector`
- the accepted 20-cycle sphere path did not become the timing bottleneck

## Render verification

Render verifier note:

- `tools/render_scene_parallel.py` was previously updated to compare only against gold images with the same output size
- there are still no compatible `320x180` gold references for the `scale=10` preview renders
- final render validation therefore uses direct baseline-vs-candidate RMSE and visual comparison

### canonical_balls

Baseline:

- summary: `/Users/wyf/code/fpga/fpga-raytracer-v3/fpga-raytracer/metrics/canonical_balls/2026-02-25-23-34-41/summary.json`
- `cycles_per_pixel_per_frame = 126.59009548611111`

Candidate:

- summary: `metrics/canonical_balls/2026-02-26-13-55-13/summary.json`
- `cycles_per_pixel_per_frame = 108.12774305555556`
- candidate vs baseline raw RMSE: `44.32848187740649`
- candidate vs baseline blur RMSE: `6.1252206120511525`
- visual inspection: no obvious regression

Speedup:

- `14.584357772746257%`

### knight

Baseline:

- summary: `/Users/wyf/code/fpga/fpga-raytracer-v3/fpga-raytracer/metrics/knight/2026-02-26-00-22-14/summary.json`
- `cycles_per_pixel_per_frame = 2326.0925217013887`

Candidate:

- summary: `metrics/knight/2026-02-26-14-01-04/summary.json`
- `cycles_per_pixel_per_frame = 2281.1090798611112`
- candidate vs baseline raw RMSE: `27.51553138851933`
- candidate vs baseline blur RMSE: `3.9829337898180124`
- visual inspection: no obvious regression

Speedup:

- `1.9338629663524707%`

## Final speedup

- `canonical_balls`: `14.584357772746257%`
- `knight`: `1.9338629663524707%`
- simple mean: `8.259110369549363%`

## Outcome

Accepted the `29 -> 20` cycle reduction for `sphere_intersector`.

Reason:

- focused module tests pass
- downstream `ray_intersector` regression passes
- isolated sphere synth passes timing at 100 MHz
- whole design synth still passes timing at 100 MHz
- preview renders show no obvious visual regression
- end-to-end render speed improved substantially on `canonical_balls` and modestly on `knight`
## Instructions

(these instructions are also in `fpga-raytracer/NOTES/004_*.md` should you need to refer back to them at any point)

Make a new git worktree for this project.

Goal: get the sphere_intersector module down in cycle count. Currently it is pipelined across some number of stages stages to fit within the 100 MHz clock, but we think it is possible to get it down to fewer cycles.

Loop:
1. Propose change to sphere_intersector.
2. Check that it passes sim/math/rtx/test_sphere_intersector.py. Feel free to harden this test as you work.
3. (One-time task) Write a testbench top level sv file that drives sphere_intersector. It should plug in random inputs to an sphere_intersector module so synthesis is forced to fully synthesize it.
4. Synthesize this top level test sv file. You will will need a corresponding tcl file. You may reuse top_level_test.xdc. Ensure that WNS is nonnegative.

If you find a change that makes sphere_intersector faster and it fits in 100 MHz, proceed to the next step.

Next loop:
1. Synthesize the whole design (top_level_rtx.sv) using tools/vivado_metrics.py. Ensure that WNS is nonnegative. Specifically look at the adder.
2. If this passes, repipeline stuff to account for sphere_intersector's new cycle count.
3. Test individual modules as you repipeline; lots of tests already exist in sim/. Start with math modules and work up to rtx modules. More planning may be required at this stage.

Once everything is tested, move on:
1. Test with tools/render_scene_parallel.py. Ensure that image RMSEs are not degraded.
2. Inspect visually if they are and go back to the very beginning if stuff doesn't work. Be patient; this is a long task. Make use of testbenches.

At the very end, render canonical_balls.json and knight.json at scale=10 with frames=4 for previewing and report percentage speedup.

Clean up after you finish.

Notes:
1. Do not spawn interactive processes, as they require user input and will make you hang.
