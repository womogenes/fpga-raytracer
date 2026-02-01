# RAYTRACER: Real-time A+-qualitY TRiangle And CirclE Renderer

This repo contains the source code for [@womogenes](https://github.com/womogenes) and [@FWJK35's](https://github.com/fwjk35) final project for the Fall 2025 version of [6.205 Digital Systems Laboratory](https://fpga.mit.edu) at MIT.

- [Final video demo (YouTube)](https://youtu.be/eS05SkVaAhU)
- [Final report (PDF)](https://fpga.mit.edu/6205/_util/get_upload?id=e9ccceecfed2f7a79b6aa0fe88123d915e9cd917847c2159a8104bd5745ee9bf032f51d658502524dcc6bf67ac0d3b5860bfa5076ccca066f1767c9c213a5676)

Here's a test scene we made in Blender than flashed to the FPGA (it took about 24 minutes to render fully):

<center>
<img src="https://cdn.discordapp.com/attachments/1312647913213530223/1448456347225161759/IMG_0024.jpg?ex=69808a58&is=697f38d8&hm=6d904f176e5d2dac2c951b2ab3fc70fa1ac6d7eff7e3b2383f53fd0495724930&">
</center>

The core design is in SystemVerilog, though we have build files and tooling specifically for the [Nexys Video](https://digilent.com/reference/programmable-logic/nexys-video/start) board, which contains the Artix-7 FPGA with 13 Mbits of on-chip BRAM and 512 MB of DDR3 DRAM.

<center>
<img src="https://cdn.discordapp.com/attachments/1312647913213530223/1448483570057220138/IMG_0025.jpg?ex=6980a3b2&is=697f5232&hm=ef170720a4ac38976904231dfea3e840b4dbf8eb9500a670d6230c226128dddd&" width="400">
</center>

For the first ~10 weeks we used the [Real Digital Urbana Board](https://www.realdigital.org/hardware/urbana) which had fewer LUTs. Build files exist in git history somewhere.

## How to build

If you want to test this for yourself in hardware:

1. Buy a Nexys Video board ($540). If you want to use a cheaper board the LUT usdage might not work.
2. Install Xilinx Vivado (nontrivial; will add instructions later)
3. Synthesize with
   ```
   time vivado -mode batch -source build_rtx.tcl -nojournal -log "obj/vivado.log"
   ```
   or using the Vivado GUI (though I prefer the command-line version)
4. Run
   ```
   python ctrl/make_scene_buffer.py <scene_file.json>
   ```
   to create `data/mat_dict.mem` and `data/scene_buffer.mem`, which are required for build (else you'll render a black screen). The canonical json we used for testing is `ctrl/scenes/canonical_balls.json.`
5. Flash to the board with
   ```
   openFPGALoader -b nexysVideo obj/final.bit
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

If you don't have the Nexys video, a comparable board will work provided it has enough logic slices, HDMI output, and sufficient DRAM. You will need to modify `xdc/top_level.xdc` with the right pinout labels. We based ours off of `https://github.com/Digilent/digilent-xdc/blob/master/Nexys-Video-Master.xdc` as well as somee file that Joe gave us.

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

1. Find `sim/utils.py` and change
