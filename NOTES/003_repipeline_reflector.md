## Instructions

Make a new git worktree for this project.

Goal: decrease cycle count of reflector module. Reflecctor wins MUST apply to canonical balls. We care heavily (perhaps most of all) about non-reflective surfaces. Your improvement/re-pipelining should decrease cycle count for ALL surfaces, not add more fast paths.

1. Read AGENTS.md and README.md.
2. First, spend time building mental picture of the reflector in hdl/ and all dependent modules --- get a sense of what the paths through this module are, and confirm your understanding with testbenches. Build out a document that describes this.
3. We are trying to repipeline this thing to reduce total cycle count. Feel free to redesign this module entirely. Try wild ideas. Creativity will be rewarded.
4. This module must remain fully pipelined (capapble of processing one ray per cycle).
5. Harden the reflector testbench in sim/ and verify using end-to-end tests using RMSE etc. in tools/ that this generates correct scenes. Iterate using canonical_balls.json. At the very end, render canonical_balls.json along with chicken.json and knight.json and report the new cycles per pixel.
6. Do not worry about timing. Don't use Vivado.
7. Aim for at least a 10% reduction in rendering time.

For fun, at the very end, render canonical_balls.json and knight.json at scale=10 with frames=4 for previewing and report percentage speedup.

Clean up after you finish.
