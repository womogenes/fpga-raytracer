Investigate the reflector module in hdl/ and see if it can be re-pipelined. Harden the tests in sim/ and verify using end-to-end tests using RMSE etc. in tools/ that this generates correct scenes. Iterate using canonical_balls.json. At the very end, render canonical_balls.json along with chicken.json and knight.json and report the new cycles per pixel.

Do not worry about timing. Don't use Vivado; it's not installed yet.

Also for fun, at the very end, render canonical_balls.json and knight.json at scale=10 for previewing.
