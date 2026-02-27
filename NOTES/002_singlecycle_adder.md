## Instructions

(these instructions are also in `fpga-raytracer/NOTES/002_singlecycle_adder.md` should need to refer back to them at any point)

Make a new git worktree for this project.

Goal: get the fp_add module down to a single-cycle module. Currently it is pipelined across 2 stages to fit within the 100 MHz clock, but we think it is possible to get it down to 1 stage.

Loop:
1. Propose change to fp_add.
2. Check that it passes sim/math/fp_ops/test_fp_add.py. Feel free to harden this test as you work.
3. (One-time task) Write a testbench top level sv file that drives fp_add. It should plug in random inputs to an fp_add module so synthesis is forced to fully synthesize it.
4. Synthesize this top level test sv file. You will will need a corresponding tcl file. You may reuse top_level_test.xdc. Ensure that WNS is nonnegative.

If you find a change that makes fp_add single-cycle and it fits in 100 MHz, proceed to the next step.

Next loop:
1. Synthesize the whole design (top_level_rtx.sv) using tools/vivado_metrics.py. Ensure that WNS is nonnegative. Specifically look at the adder.
2. If this passes, repipeline stuff to account for fp_add only being one cycle instead of two.
3. Test individual modules as you repipeline; lots of tests already exist in sim/. Start with math modules and work up to rtx modules.

Once everything is tested, move on:
1. Test with tools/render_scene_parallel.py. Ensure that image RMSEs are not degraded.
2. Inspect visually if they are and go back to previous loop if stuff doesn't work. Be patient; this is a long task.

At the very end, render canonical_balls.json and knight.json at scale=10 with frames=4 for previewing and report percentage speedup.

Clean up after you finish.

## Implementation logs

### Worktree and branch setup

- Created a dedicated worktree for this effort and repaired its Git metadata when the original registration was stale.
- Active checkout path:
  - `/Users/wyf/code/fpga/fpga-raytracer-v3/fpga-raytracer-v3-fpadd-singlecycle`
- Branch history used for this work:
  - `william/fpadd-singlecycle`
  - `codex/sphere-intx-latency`
  - merged branch `william/fpadd-singlecycle-sphere-intx`

### fp_add single-cycle change

- Converted `hdl/math/fp_add.sv` from a 2-cycle pipeline to a 1-cycle module.
- Kept the same overall add/subtract/normalize algorithm, but removed the intermediate pipeline stage and kept only the final output register.
- Added a large-exponent-gap bypass so the smaller mantissa is forced to zero instead of doing a pointless wide shift.
- Preserved the CLZ-based normalization path in the same cycle.
- Updated global timing constants and downstream latency assumptions so the rest of the design treats `FP_ADD_DELAY = 1`.

### Focused fp_add bring-up

- Restored the focused synthesis harness for adder experiments:
  - `hdl/top_level_test.sv`
  - `build_test.tcl`
  - `hdl/tb/fp_add/fp_add_one_cycle_baseline.sv`
  - `hdl/tb/fp_add/fp_add_one_cycle_opt.sv`
- Hardened `sim/math/fp_ops/test_fp_add.py` so it can run from the repo root and acts as a real regression.
- Added baseline-compare infrastructure for math modules:
  - `sim/math/fp_ops/test_fp_add_vs_baseline.py`
  - `sim/math/fp_ops/test_fp_inv_sqrt_vs_baseline.py`
  - `sim/math/fp_ops/test_fp_vec3_dot_vs_baseline.py`
  - `sim/math/fp_ops/test_fp_vec3_normalize_vs_baseline.py`

### Focused adder timing result

- Verified the isolated one-cycle adder at 100 MHz.
- Focused report:
  - `obj_test/fp_add_one_cycle_baseline/post_route_timing_summary.rpt`
- Result:
  - `WNS = +1.126 ns`
  - `TNS = 0.000`

### Full-design repipeline after fp_add = 1 cycle

- Re-audited and updated downstream math and RTX latency alignment so the design remains functionally correct with the shorter adder.
- Revalidated math and RTX modules while repipelining.
- Added or improved targeted checks around material-dictionary and scene-backed paths so image-color alignment issues could be caught at the testbench level.

### Merge with sphere-intersector work

- Committed the fp_add work on:
  - `7e93fbd Make fp_add single-cycle`
- Committed the sphere-intersector work on:
  - `65cc531 Reduce sphere intersector latency`
- Merged both lines of work with a real two-parent merge commit:
  - `582b1a3 Merge codex/sphere-intx-latency into william/fpadd-singlecycle-sphere-intx`

### Merge resolution decisions

- Kept the fast sphere-local datapath in:
  - `hdl/math/sphere_intersector.sv`
- Kept the single-cycle-adder branch's end-of-ray correctness behavior in:
  - `hdl/rtx/ray_intersector.sv`
- Took the fast-path regression tests from the sphere branch where they were clearly better:
  - `sim/rtx/test_quadratic_solver.py`
  - `sim/rtx/test_sphere_intersector.py`
  - `sim/rtx/test_ray_intersector.py`
- Replaced the old plotting-heavy `sim/rtx/test_trig_intersector.py` with a deterministic functional regression.

### Post-merge simplification pass

- Simplified `hdl/rtx/ray_intersector.sv` without changing the verified timing contract:
  - removed dead `pre_obj_count` state
  - introduced a single derived `first_result` token
  - kept the measured merged `RAY_INTERSECTOR_OVERHEAD = 1`
- Recorded in follow-up commit:
  - `5d42d80 Simplify ray_intersector bookkeeping`

### Final verified module regressions

- `python3 sim/math/fp_ops/test_fp_add.py`
- `python3 sim/rtx/test_quadratic_solver.py`
- `python3 sim/rtx/test_sphere_intersector.py`
- `python3 sim/rtx/test_trig_intersector.py`
- `python3 sim/rtx/test_ray_intersector.py`
- `python3 sim/rtx/test_ray_intersector_scene.py`
- `python3 sim/rtx/test_ray_tracer_scene.py`
- `python3 sim/rtx/test_ray_reflector.py`

### Final end-to-end render verification

- The final accepted render checks used `scale=2` and `frames=4`.
- The earlier `scale=10` preview requirement was explicitly dropped later and is not part of the final accepted scope.

#### canonical_balls

- Summary:
  - `metrics/canonical_balls/2026-02-26-15-57-21/summary.json`
- Result:
  - `total_cycles = 846914`
  - `cycles_per_pixel_per_frame = 91.89605034722223`
  - `raw_rmse_min = 44.193170441340904`
  - `blur_rmse_min = 5.787980941539945`
  - RMSE gates: pass
- Speedup vs baseline:
  - `39.14%`

#### chicken

- Summary:
  - `metrics/chicken/2026-02-26-15-59-01/summary.json`
- Result:
  - `total_cycles = 7144920`
  - `cycles_per_pixel_per_frame = 775.2734375`
  - `raw_rmse_min = 29.411605442787753`
  - `blur_rmse_min = 4.3404222198187465`
  - RMSE gates: pass
- Speedup vs baseline:
  - `14.12%`

#### knight

- Summary:
  - `metrics/knight/2026-02-26-16-00-48/summary.json`
- Result:
  - `total_cycles = 20631394`
  - `cycles_per_pixel_per_frame = 2238.6495225694443`
  - `raw_rmse_min = 44.54543593083941`
  - `blur_rmse_min = 6.551589254467901`
  - RMSE gates: pass
- Speedup vs baseline:
  - `6.61%`

### Final full-design Vivado result

- Re-ran `python3 tools/vivado_metrics.py` after the simplification pass.
- Reports:
  - `obj_rtx/post_route_timing_summary.rpt`
  - `obj_rtx/post_route_util.rpt`
  - `obj_rtx/vivado.log`
- Result:
  - `timing_met = true`
  - `WNS = +0.135 ns`
  - `TNS = 0.0`
  - `Slice LUTs = 27936`

### Final state

- `fp_add` is single-cycle in production RTL.
- The merged branch keeps the sphere-intersector latency reduction.
- Full-design timing is positive at 100 MHz.
- End-to-end render RMSE gates pass on `canonical_balls`, `chicken`, and `knight` at `scale=2`, `frames=4`.
- Generated render artifacts remain untracked under `images/` and local metrics outputs.
