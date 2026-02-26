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
