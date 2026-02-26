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
