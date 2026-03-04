import warnings
warnings.filterwarnings("ignore", category=UserWarning)

import os
import sys
import shutil
import json
import subprocess
import glob
import hashlib
from pathlib import Path
from argparse import ArgumentParser, BooleanOptionalAction

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from cocotb.runner import get_runner

import numpy as np
import time

from PIL import Image
from tqdm import tqdm

sys.path.append(str(Path(__file__).resolve().parent))
sys.path.append(str(Path(__file__).resolve().parent.parent))
sys.path.append(str(Path(__file__).resolve().parent.parent.parent / "ctrl"))

from utils import make_fp_vec3, pack_bits, FP_BITS, FP_VEC3_BITS
from make_scene_buffer import export_scene

from multiprocessing import Pool

parser = ArgumentParser()
parser.add_argument("--chunks", type=int, default=None)
parser.add_argument("--scale", type=float, default=0.5)
parser.add_argument("--frames", type=int, default=1)
parser.add_argument("--waves", action=BooleanOptionalAction, default=False)
parser.add_argument("--json", type=str, default=None)
parser.add_argument("--seed", type=lambda value: int(value, 0), default=0x123456789ABCDEF123456789)
parser.add_argument("--data-dir", type=Path, default=None)
parser.add_argument("--output-prefix", type=Path, default=None)

args = parser.parse_args()
WAVES = args.waves

if "TEST_WIDTH" in os.environ:
    WIDTH = int(os.environ["TEST_WIDTH"])
    HEIGHT = int(os.environ["TEST_HEIGHT"])
    N_FRAMES = int(os.environ["TEST_N_FRAMES"])
    scale = WIDTH / 32
    assert "CAM_DATA" in os.environ
    CAM_DATA = json.loads(os.environ["CAM_DATA"])
    MAX_BOUNCES = int(os.environ["MAX_BOUNCES"])
    BASE_SEED = int(os.environ["TEST_SEED"], 0)

else:
    scale = args.scale
    WIDTH = int(32 * scale)
    HEIGHT = int(18 * scale)
    N_FRAMES = args.frames
    BASE_SEED = args.seed

    if args.json:
        data_dir = args.data_dir or Path(os.environ.get("RTX_DATA_DIR", Path(__file__).resolve().parent.parent.parent / "data"))
        data_dir.mkdir(parents=True, exist_ok=True)
        os.environ["RTX_DATA_DIR"] = str(data_dir)
        export_scene(args.json, out_dir=data_dir)
        with open(args.json) as fin:
            data = json.load(fin)
            CAM_DATA = data["camera"]
            MAX_BOUNCES = data["max_bounces"]

    else:
        CAM_DATA = {
            "origin": [0, 0, 0],
            "forward": [0, WIDTH, 0],
            "right": [2, 0, 0],
            "up": [0, 0, 2],
        }
        MAX_BOUNCES = 3

CPU_COUNT = os.cpu_count() or 1
N_CHUNKS = args.chunks or (2 * CPU_COUNT * N_FRAMES)
TOTAL_PIXELS = WIDTH * HEIGHT

CHUNK_SIZE = (TOTAL_PIXELS + N_CHUNKS - 1) // N_CHUNKS
CHUNK_RANGES = [
    (i * CHUNK_SIZE, min((i + 1) * CHUNK_SIZE - 1, TOTAL_PIXELS - 1))
    for i in range((TOTAL_PIXELS + CHUNK_SIZE - 1) // CHUNK_SIZE)
]
NUM_CHUNKS_ACTUAL = len(CHUNK_RANGES)

test_file = os.path.basename(__file__).replace(".py", "")

proj_path = Path(__file__).resolve().parent.parent.parent
data_dir = args.data_dir or Path(os.environ.get("RTX_DATA_DIR", proj_path / "data"))
SCENE_BUF_MEM_PATH = str(data_dir / "scene_buffer.mem")
MAT_DICT_MEM_PATH = str(data_dir / "mat_dict.mem")

with open(SCENE_BUF_MEM_PATH, "r") as fin:
    NUM_OBJS = fin.read().strip().count("\n") + 1

run_instance_key_parts = [
    str(Path(args.json).resolve()) if args.json else "<no-scene>",
    str(data_dir.resolve()),
    str(args.output_prefix.resolve()) if args.output_prefix else "<no-output-prefix>",
    f"{WIDTH}x{HEIGHT}",
    f"f{N_FRAMES}",
    f"seed{BASE_SEED:024x}",
]
default_run_instance_tag = hashlib.sha1("::".join(run_instance_key_parts).encode()).hexdigest()[:16]
RUN_INSTANCE_TAG = os.environ.get("RTX_RUN_INSTANCE_TAG", default_run_instance_tag)
RUN_TAG = f"{WIDTH}x{HEIGHT}_f{N_FRAMES}_seed{BASE_SEED:024x}_{RUN_INSTANCE_TAG}"
CHUNKS_OUT_DIR = Path(os.environ.get(
    "RTX_CHUNKS_OUT_DIR",
    proj_path / "sim" / "sim_build" / "rtx_parallel" / "chunks" / RUN_TAG,
))
if "PIXEL_START_IDX" not in os.environ:
    shutil.rmtree(CHUNKS_OUT_DIR, ignore_errors=True)
os.makedirs(CHUNKS_OUT_DIR, exist_ok=True)

BUILD_DIR = Path(os.environ.get(
    "RTX_BUILD_DIR",
    proj_path / "sim" / "sim_build" / "rtx_parallel" / f"verilator_{WIDTH}x{HEIGHT}_{RUN_INSTANCE_TAG}",
))
os.makedirs(BUILD_DIR, exist_ok=True)

SIM = os.getenv("SIM", "verilator")
HDL_TOPLEVEL = "rtx_tb_parallel"

sys.path.append(str(proj_path / "sim"))

SOURCES = [
    proj_path / "hdl" / "pipeline.sv",
    proj_path / "hdl" / "constants.sv",
    proj_path / "hdl" / "types" / "types.sv",
    *glob.glob(f"{proj_path}/hdl/math/*.sv", recursive=True),
    *glob.glob(f"{proj_path}/hdl/rng/*.sv", recursive=True),
    proj_path / "hdl" / "mem" / "xilinx_true_dual_port_read_first_2_clock_ram.v",
    *glob.glob(f"{proj_path}/hdl/rtx/*.sv", recursive=True),
]

BUILD_TEST_ARGS = [
    "-Wno-WIDTHEXPAND",
    "-Wno-MULTIDRIVEN",
    "-Wno-WIDTHTRUNC",
    "-Wno-TIMESCALEMOD",
    "-Wno-PINMISSING",
    "-Wno-BLKSEQ",
]

PARAMETERS = {
    "WIDTH": WIDTH,
    "HEIGHT": HEIGHT,
}


def chunk_seed(chunk_idx: int) -> int:
    mixed = (BASE_SEED ^ (0x9E3779B97F4A7C15 * (chunk_idx + 1))) & ((1 << 96) - 1)
    lower = mixed & ((1 << 48) - 1)
    upper = (mixed >> 48) & ((1 << 48) - 1)
    if lower == 0:
        mixed |= 1
    if upper == 0:
        mixed |= 1 << 48
    return mixed


@cocotb.test()
async def test_module(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    chunk_idx = int(os.environ.get("CHUNK_IDX", "0"))
    dut.lfsr_seed.value = chunk_seed(chunk_idx)
    dut.rst.value = 1

    cam_scale = WIDTH / 1280
    dut.cam.value = pack_bits([
        (make_fp_vec3(CAM_DATA["origin"]), FP_VEC3_BITS),
        (make_fp_vec3([v * cam_scale for v in CAM_DATA["forward"]]), FP_VEC3_BITS),
        (make_fp_vec3(CAM_DATA["right"]), FP_VEC3_BITS),
        (make_fp_vec3(CAM_DATA["up"]), FP_VEC3_BITS),
    ])
    
    dut.num_objs.value = NUM_OBJS
    dut.max_bounces.value = MAX_BOUNCES

    await ClockCycles(dut.clk, 100)
    dut.rst.value = 0

    def unpack_color8(color8):
        return (
            ((color8 >> 0) & 0b11111) << 3,
            ((color8 >> 5) & 0b111111) << 2,
            ((color8 >> 11) & 0b11111) << 3
        )

    pixel_start_idx = int(os.environ["PIXEL_START_IDX"])
    pixel_end_idx = int(os.environ["PIXEL_END_IDX"])
    n_pixels = pixel_end_idx - pixel_start_idx + 1
    pixel_values = np.zeros((n_pixels, 3))
    total_samples = N_FRAMES * n_pixels
    total_chunk_cycles = 0
    issued = 0
    completed = 0
    stall_cycles = 0

    progress = tqdm(total=total_samples, ncols=120, desc=f"[chunk {chunk_idx:>3}/{NUM_CHUNKS_ACTUAL:<3}]")

    while completed < total_samples:
        request_pending = issued < total_samples
        if request_pending:
            pixel_idx = (issued % n_pixels) + pixel_start_idx
            dut.pixel_v_in.value = pixel_idx // WIDTH
            dut.pixel_h_in.value = pixel_idx % WIDTH
            dut.new_ray.value = 1
        else:
            dut.new_ray.value = 0
        await cocotb.triggers.ReadOnly()
        launch_now = request_pending and dut.launch_caster.value.integer == 1

        await ClockCycles(dut.clk, 1)
        total_chunk_cycles += 1

        if launch_now:
            issued += 1
            stall_cycles = 0

        if dut.ray_done.value.integer:
            pixel_h_done = dut.pixel_h_out.value.integer
            pixel_v_done = dut.pixel_v_out.value.integer
            done_pixel_idx = pixel_v_done * WIDTH + pixel_h_done
            assert pixel_start_idx <= done_pixel_idx <= pixel_end_idx, (
                f"completed pixel {done_pixel_idx} outside chunk {pixel_start_idx}-{pixel_end_idx}"
            )

            pixel_color = unpack_color8(dut.rtx_pixel.value.integer)
            r, g, b = pixel_color
            pixel_values[done_pixel_idx - pixel_start_idx] += (r, g, b)
            completed += 1
            progress.update(1)
            stall_cycles = 0
        else:
            stall_cycles += 1
            assert stall_cycles < 50000, (
                f"render stalled after {stall_cycles} cycles: issued={issued}, completed={completed}, "
                f"ray_done={dut.ray_done.value.integer}, "
                f"work_count={dut.tracer.work_count.value.integer}, "
                f"intx_active={dut.tracer.intx_active.value.integer}, "
                f"reflect_inflight={dut.tracer.reflect_inflight_count.value.integer}"
            )

    progress.close()

    save_path = CHUNKS_OUT_DIR / f"chunk_{chunk_idx:04}.npy"
    np.save(save_path, np.floor(pixel_values / N_FRAMES))
    stats_path = CHUNKS_OUT_DIR / f"chunk_{chunk_idx:04}.json"
    with open(stats_path, "w") as fout:
        json.dump(
            {
                "chunk_idx": chunk_idx,
                "cycles": total_chunk_cycles,
                "pixel_samples": N_FRAMES * n_pixels,
                "output_pixels": n_pixels,
            },
            fout,
        )
    dut._log.info(f"Saved pixel chunk to {save_path}")


def build_verilator():
    print(f"Building Verilator for {WIDTH}x{HEIGHT}...")

    os.makedirs(BUILD_DIR / "data", exist_ok=True)
    shutil.copy(SCENE_BUF_MEM_PATH, BUILD_DIR / "data" / "scene_buffer.mem")
    shutil.copy(MAT_DICT_MEM_PATH, BUILD_DIR / "data" / "mat_dict.mem")

    runner = get_runner(SIM)
    runner.build(
        sources=SOURCES,
        hdl_toplevel=HDL_TOPLEVEL,
        always=False,
        build_args=BUILD_TEST_ARGS,
        parameters=PARAMETERS,
        timescale=("1ns", "1ps"),
        waves=WAVES,
        build_dir=BUILD_DIR,
    )

    print(f"Build complete. Executable cached in {BUILD_DIR}")


def run_test_worker(pixel_start_idx: int, pixel_end_idx: int, chunk_idx: int):
    os.environ["PIXEL_START_IDX"] = str(pixel_start_idx)
    os.environ["PIXEL_END_IDX"] = str(pixel_end_idx)
    os.environ["CHUNK_IDX"] = str(chunk_idx)

    os.environ["TEST_WIDTH"] = str(WIDTH)
    os.environ["TEST_HEIGHT"] = str(HEIGHT)
    os.environ["TEST_N_FRAMES"] = str(N_FRAMES)

    if CAM_DATA:
        os.environ["CAM_DATA"] = json.dumps(CAM_DATA)
        os.environ["MAX_BOUNCES"] = str(MAX_BOUNCES)
    os.environ["TEST_SEED"] = hex(BASE_SEED)
    os.environ["RTX_RUN_INSTANCE_TAG"] = RUN_INSTANCE_TAG
    os.environ["RTX_CHUNKS_OUT_DIR"] = str(CHUNKS_OUT_DIR)
    os.environ["RTX_BUILD_DIR"] = str(BUILD_DIR)

    runner = get_runner(SIM)
    runner.build(
        sources=SOURCES,
        hdl_toplevel=HDL_TOPLEVEL,
        always=False,
        build_args=BUILD_TEST_ARGS,
        parameters=PARAMETERS,
        timescale=("1ns", "1ps"),
        waves=WAVES,
        build_dir=BUILD_DIR,
    )

    runner.test(
        hdl_toplevel=HDL_TOPLEVEL,
        test_module=test_file,
        test_args=[],
        waves=WAVES,
    )

    return chunk_idx


def worker(task):
    """Wrapper for Pool.map"""
    chunk_idx, start_idx, end_idx = task
    return run_test_worker(start_idx, end_idx, chunk_idx)


if __name__ == "__main__":
    print(f"Resolution: {WIDTH}x{HEIGHT}")
    print(f"Frames: {N_FRAMES}")
    print(f"Chunks: {NUM_CHUNKS_ACTUAL}")
    print(f"Seed: 0x{BASE_SEED:024x}")
    print(f"Worker processes: {CPU_COUNT}")
    print()

    # Build Verilator once
    build_start = time.time()
    build_verilator()
    build_time = time.time() - build_start
    print(f"Build time: {build_time:.1f}s\n")

    # Create tasks for parallel execution
    tasks = [(chunk_idx, start_idx, end_idx)
             for chunk_idx, (start_idx, end_idx) in enumerate(CHUNK_RANGES)]

    # Run tests in parallel
    print("Starting parallel render...")
    render_start = time.time()
    with Pool(processes=CPU_COUNT) as pool:
        pool.map(worker, tasks)
    render_time = time.time() - render_start

    # Gather chunks and combine
    print("\nCombining chunks...")
    pixel_chunks = []
    total_cycles = 0
    total_pixel_samples = 0
    total_output_pixels = 0
    for chunk_idx in range(len(CHUNK_RANGES)):
        chunk_path = CHUNKS_OUT_DIR / f"chunk_{chunk_idx:04}.npy"
        stats_path = CHUNKS_OUT_DIR / f"chunk_{chunk_idx:04}.json"
        if not chunk_path.exists():
            raise FileNotFoundError(f"Expected chunk file missing: {chunk_path}")
        if not stats_path.exists():
            raise FileNotFoundError(f"Expected chunk stats missing: {stats_path}")
        pixel_chunks.append(np.load(chunk_path))
        with open(stats_path) as fin:
            chunk_stats = json.load(fin)
        total_cycles += chunk_stats["cycles"]
        total_pixel_samples += chunk_stats["pixel_samples"]
        total_output_pixels += chunk_stats["output_pixels"]

    pixels_all = np.concatenate(pixel_chunks)
    img = Image.fromarray(pixels_all.reshape((HEIGHT, WIDTH, 3)).astype("uint8"))
    output_prefix = args.output_prefix or Path(f"test_rtx_{WIDTH}x{HEIGHT}_f{N_FRAMES}")
    output_file = Path(output_prefix).with_suffix(".png")
    output_file.parent.mkdir(parents=True, exist_ok=True)
    img.save(output_file)
    metrics = {
        "frames": N_FRAMES,
        "seed": f"0x{BASE_SEED:024x}",
        "total_cycles": total_cycles,
        "pixel_samples": total_pixel_samples,
        "output_pixels": total_output_pixels,
        "cycles_per_pixel_per_frame": total_cycles / total_pixel_samples,
        "cycles_per_output_pixel_all_frames": total_cycles / total_output_pixels,
    }
    metrics_path = output_file.with_suffix(".metrics.json")
    with open(metrics_path, "w") as fout:
        json.dump(metrics, fout, indent=2)

    total_time = time.time() - build_start
    print(f"\n=== Render complete ===")
    print(f"Output: {output_file}")
    print(f"Build time: {build_time:.1f}s")
    print(f"Render time: {render_time:.1f}s ({render_time/60:.1f} min)")
    print(f"Total time: {total_time:.1f}s ({total_time/60:.1f} min)")
    print(f"Total cycles: {total_cycles}")
    print(f"Cycles per pixel per frame: {metrics['cycles_per_pixel_per_frame']:.3f}")
    print(f"Cycles per output pixel across all frames: {metrics['cycles_per_output_pixel_all_frames']:.3f}")
