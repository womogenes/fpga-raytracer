import glob
import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles

import numpy as np

sys.path.append(str(Path(__file__).resolve().parent))
sys.path.append(str(Path(__file__).resolve().parent.parent))
from utils import make_fp_vec3


FAST_DELAY = 19
BLEND_DELAY = 37
TEST_MATERIALS = [
    "3e999a3d33333c999a3b999a0000000000003f00003f00003f00003f000000",
    "3d00003e00003e80000000003a999a3b999a3ecccd3e999a3e66663f0000ff",
    "3c999a3e00003e999a3947ae39eb853a47ae3ecccd3e999a3b999a3e0000ff",
]

test_file = os.path.basename(__file__).replace(".py", "")


def normalize(vec):
    arr = np.asarray(vec, dtype=float)
    norm = np.linalg.norm(arr)
    assert norm > 1e-9
    return arr / norm


def signal_is_high(signal) -> bool:
    value = signal.value
    return bool(value.is_resolvable and value.integer)


async def launch_case(dut, *, ray_dir, ray_color, income_light, hit_pos, hit_normal, hit_mat_idx):
    dut.ray_dir.value = make_fp_vec3(tuple(ray_dir))
    dut.ray_color.value = make_fp_vec3(tuple(ray_color))
    dut.income_light.value = make_fp_vec3(tuple(income_light))
    dut.hit_pos.value = make_fp_vec3(tuple(hit_pos))
    dut.hit_normal.value = make_fp_vec3(tuple(hit_normal))
    dut.hit_mat_idx.value = hit_mat_idx
    await ClockCycles(dut.clk, 2)
    dut.hit_valid.value = 1
    await ClockCycles(dut.clk, 1)
    dut.hit_valid.value = 0


async def wait_for_done(dut, expected_cycles):
    for cycle in range(1, expected_cycles + 1):
        await ClockCycles(dut.clk, 1)
        if cycle < expected_cycles:
            assert not signal_is_high(dut.reflect_done), f"reflect_done rose early at cycle {cycle}"
    assert signal_is_high(dut.reflect_done), f"reflect_done did not rise at cycle {expected_cycles}"


@cocotb.test()
async def test_module(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst.value = 1
    dut.hit_valid.value = 0
    dut.ray_dir.value = 0
    dut.ray_color.value = 0
    dut.income_light.value = 0
    dut.hit_pos.value = 0
    dut.hit_normal.value = 0
    dut.hit_mat_idx.value = 0
    dut.lfsr_seed.value = int("0123456789abcdef01234567", 16)
    await ClockCycles(dut.clk, 10)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    ray_color = (0.75, 0.5, 0.25)
    income_light = (0.1, 0.2, 0.3)
    hit_pos = (1.0, -2.0, 3.0)
    hit_normal = normalize((0.0, 0.0, 1.0))

    await launch_case(
        dut,
        ray_dir=normalize((1.0, -0.25, -1.0)),
        ray_color=ray_color,
        income_light=income_light,
        hit_pos=hit_pos,
        hit_normal=hit_normal,
        hit_mat_idx=0,
    )
    await wait_for_done(dut, FAST_DELAY - 1)
    assert dut.mat_dict_idx.value.integer == 0
    await ClockCycles(dut.clk, 2)
    await ClockCycles(dut.clk, 4)

    in_dir = normalize((1.0, -1.0, -0.5))
    normal = normalize((0.0, 0.0, 1.0))
    ray_color = (0.9, 0.4, 0.2)
    income_light = (0.0, 0.25, 0.5)

    await launch_case(
        dut,
        ray_dir=in_dir,
        ray_color=ray_color,
        income_light=income_light,
        hit_pos=(0.0, 1.0, 2.0),
        hit_normal=normal,
        hit_mat_idx=1,
    )
    await wait_for_done(dut, FAST_DELAY - 1)
    assert dut.mat_dict_idx.value.integer == 1
    await ClockCycles(dut.clk, 2)
    await ClockCycles(dut.clk, 4)

    ray_color = (0.6, 0.7, 0.8)
    income_light = (0.3, 0.2, 0.1)

    await launch_case(
        dut,
        ray_dir=normalize((-0.5, 1.0, -0.2)),
        ray_color=ray_color,
        income_light=income_light,
        hit_pos=(2.0, -1.0, 0.5),
        hit_normal=normalize((0.1, 0.2, 1.0)),
        hit_mat_idx=2,
    )
    await wait_for_done(dut, BLEND_DELAY - 1)
    await ClockCycles(dut.clk, 2)


def runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent.parent
    build_dir = proj_path / "sim" / "sim_build"
    build_data_dir = build_dir / "data"
    build_data_dir.mkdir(parents=True, exist_ok=True)
    (build_data_dir / "test_ray_reflector_mat_dict.mem").write_text("\n".join(TEST_MATERIALS) + "\n")
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "constants.sv",
        proj_path / "hdl" / "types" / "types.sv",
        proj_path / "hdl" / "pipeline.sv",
        proj_path / "hdl" / "mem" / "xilinx_true_dual_port_read_first_2_clock_ram.v",
        *glob.glob(f"{proj_path}/hdl/rng/*.sv", recursive=True),
        *glob.glob(f"{proj_path}/hdl/math/*.sv", recursive=True),
        proj_path / "hdl" / "rtx" / "material_dictionary.sv",
        proj_path / "hdl" / "rtx" / "ray_reflector.sv",
        proj_path / "sim" / "rtx" / "ray_reflector_tb.sv",
    ]
    build_test_args = [
        "-Wno-WIDTHEXPAND",
        "-Wno-MULTIDRIVEN",
        "-Wno-WIDTHTRUNC",
        "-Wno-TIMESCALEMOD",
        "-Wno-PINMISSING",
        "-Wno-BLKSEQ",
    ]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="ray_reflector_tb",
        always=True,
        build_args=build_test_args,
        parameters={},
        timescale=("1ns", "1ps"),
        waves=True,
        build_dir=build_dir,
    )
    runner.test(
        hdl_toplevel="ray_reflector_tb",
        test_module=test_file,
        test_args=[],
        waves=True,
    )


if __name__ == "__main__":
    runner()
