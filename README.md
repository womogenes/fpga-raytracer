# RAYTRACER: Real-time A+-qualitY TRiangle And CirclE Renderer

This repo contains the source code for [@womogenes](https://github.com/womogenes) and [@FWJK35's](https://github.com/fwjk35) final project for the Fall 2025 version of [6.205 Digital Systems Laboratory](https://fpga.mit.edu) at MIT.

- [Final video demo (YouTube)](https://youtu.be/eS05SkVaAhU)
- [Final report (PDF)](https://fpga.mit.edu/6205/_util/get_upload?id=e9ccceecfed2f7a79b6aa0fe88123d915e9cd917847c2159a8104bd5745ee9bf032f51d658502524dcc6bf67ac0d3b5860bfa5076ccca066f1767c9c213a5676)

Here's a test scene we made in Blender than flashed to the FPGA (it took about 24 minutes to render fully):

![](gallery/chess.png)

The core design is in SystemVerilog, though we have build files and tooling specifically for the [Genesys 2](https://digilent.com/shop/genesys-2-amd-kintex-7-fpga-development-board), which contains the Kintex-7 FPGA with 16 Mbits of BRAM and and 1 GB of DDR3 DRAM.

Prior to February 2026, we used to primarily support the [Nexys Video](https://digilent.com/reference/programmable-logic/nexys-video/start), which contains the Artix-7 FPGA with 13 Mbits of on-chip BRAM and 512 MB of DDR3 DRAM.

For the first ~10 weeks we used the [Real Digital Urbana Board](https://www.realdigital.org/hardware/urbana) which had fewer LUTs. Build files exist in git history somewhere.

## How to build

If you want to test this for yourself in hardware:

1. Secure a Genesys 2 board ($1099), or a Nexys Video board ($540) and go back to commit `27255c7`.
2. Install Xilinx Vivado (nontrivial; will add instructions later)
3. Synthesize with
   ```
   time vivado -mode batch -source build_rtx.tcl -nojournal -log "obj/vivado.log"
   ```
   or using the Vivado GUI (though I prefer the command-line version). When synthesizing for the Genesys 2 board, the part is `xc7k325t-ffg900-2`. If running Vivado in Docker, we currently need to run
   ```sh
   export LD_PRELOAD=/lib/x86_64-linux-gnu/libudev.so.1
   ```
   first (source: https://myon.info/blog/2024/07/06/vivado-docker) else everythig crashes.
4. Run
   ```
   python ctrl/make_scene_buffer.py <scene_file.json>
   ```
   to create `data/mat_dict.mem` and `data/scene_buffer.mem`, which are required for build (else you'll render a black screen). The canonical json we used for testing is `ctrl/scenes/canonical_balls.json.`
5. Flash to the board with
   ```
   openFPGALoader -b genesys2 obj/final.bit
   ```
6. Hook up the board to a display via HDMI
7. (Optional) Install cocotb and pyserial (and a few other things; I need to add a `requirements.txt` at some point) and flash new scenes with
   ```
   python ctrl/flash_scene.py <scene_file.json>
   ```
   This requires having a UART connection to the board. You may need to modify this line in `flash_scene.py`:
   ```
   SERIAL_PORTNAME = "/dev/ttyUSB2"  # CHANGE ME to match your system's serial port name!
   ```
   with the right port name.

If you don't have the Genesys 2, a comparable board will work provided it has enough logic slices, HDMI output, and sufficient DRAM. You will need to modify `xdc/top_level.xdc` with the right pinout labels. e.g. for the Nexys Video, see `https://github.com/Digilent/digilent-xdc/blob/master/Nexys-Video-Master.xdc`.

## Migrating from Nexys Video to Genesys 2

Codex helped me migrate everything from the Nexys Video to the Genesys 2 board. Here's what it said about what needed to change:

- Clocking:
  - Change `top_level` to take `sysclk_p/sysclk_n` instead of a single-ended `clk_100mhz`.
  - Add an MMCM-based divider (`hdl/clock/clkwiz.sv`) to derive a 100MHz internal clock for the rest of the design.
  - Update `xdc/top_level.xdc` to LOC `sysclk_p/n` and `create_clock` it at 200MHz (Genesys 2 SYSCLK pins are `AD12/AD11`).

- XDC/pinout (Genesys 2 peripherals + DDR3 IO standards):
  - Update `xdc/top_level.xdc` for Genesys 2 LED/switch/button/HDMI/UART pins (Digilent master XDC is a good starting point: https://github.com/Digilent/digilent-xdc/blob/master/Genesys-2-Master.xdc).
  - Add DDR3 constraints for the lower 16-bit subset (SSTL15 / DIFF_SSTL15). Avoid MIG-style `*_T_DCI` IOSTANDARDs here; we had to use plain `SSTL15` to get a reliable build/boot.
  - Set `BITSTREAM.CONFIG.UNUSEDPIN PULLNONE` to avoid weak pulls on DDR3-connected "unused" pins interfering with training.
  - Ensure `sw[6]`/`sw[7]` are constrained as `LVCMOS33` (Genesys 2 bank voltage).
  - If Vivado warns "set_property expects at least one object", an XDC `get_ports { ... }` doesn't match any RTL port name.

- DDR3 interface correctness (Genesys 2 MT41J256M16-class wiring):
  - Wire `ddr3_cs_n` and include `A[14]` (`ddr3_addr[14:0]`) through `top_level` and the framebuffer wrapper.
  - Configure the DDR3 top accordingly (`ROW_BITS=15`, `SDRAM_CAPACITY=4`, `ODELAY_SUPPORTED=1`, `BIST_MODE=0`).

## Project structure

A breakdown of the file structure is in `CODE_PROVENANCE.md`.

## Floating point

We use 24-bit floating point for most operations. We call this data type `fp`, and a bunch of modules exist to deal with operations on `fp` numbers. Most of these live in `hdl/math`. A few examples:

- `fp_add` implements the addition of two `fp` numbers
- `fp_mul` implements the multiplication of two `fp` numbers
- `fp_inv_sqrt` implements calculating the fast inverse square root of an `fp` number
- `fp_shift` implements changing the exponent of an `fp` number by some constant amount (efficient multiplication by powers of two)
- `fp_vec3_ops` implements a bunch of vector operations, e.g for adding `fp_vec3`s, multiplying them element-wise, calculating their dot products, scaling them by scalars (represented as `fp`s), and normalizing them.

## Possible optimizations

We anticipate getting cooked by LUT usage at some point, so here are some areas for optimization:

- `fp_inv_sqrt`: we can save ~250 LUTs per stage cut. This does change the cycle count of everything.
- `lerp`: since the value of `t` is only ever `mat.smoothness` or `1`, we can assume the value of `t` is always `1 - math.smoothness` or `0` and these are precomputable.

## So you want to mess with floating point?

We use 24-bit floating point here as a reasonable tradeoff between timing and precision, but if you want to tweak the floating point, here's how:

1. Find `sim/utils.py` and change the bit widths.
2. Run `ctrl/find_constants.py` and copy the output block to `hdl/constants.sv`. This figures out magic constants for the inverse square root bit hack, among other things.
