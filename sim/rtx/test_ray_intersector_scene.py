import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, ReadOnly, RisingEdge, with_timeout

import numpy as np

proj_path = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(proj_path))
sys.path.append(str(proj_path / "sim"))
sys.path.append(str(proj_path / "ctrl"))

from utils import convert_fp_vec3, make_fp_vec3
from make_scene_buffer import Object


TEST_OBJECTS = [
    Object(mat_idx=0, sphere_center=(-1.5, 4.0, 0.0), sphere_rad=1.0, obj_type=0),
    Object(mat_idx=1, sphere_center=(1.5, 4.0, 0.0), sphere_rad=1.0, obj_type=0),
    Object(mat_idx=2, sphere_center=(0.0, 8.0, 0.0), sphere_rad=1.0, obj_type=0),
    Object(mat_idx=3, sphere_center=(0.0, -8.0, 0.0), sphere_rad=1.0, obj_type=0),
]
def normalize(vec):
    arr = np.asarray(vec, dtype=float)
    return tuple(arr / np.linalg.norm(arr))


def write_scene_mem(path: Path):
    entries = []
    for obj in TEST_OBJECTS:
        bits, width = obj.pack_bits()
        entries.append(hex(bits)[2:].zfill((width + 3) // 4))
    path.write_text("\n".join(entries) + "\n")


async def launch_ray(dut, direction):
    dut.ray_origin.value = make_fp_vec3((0.0, 0.0, 0.0))
    dut.ray_dir.value = make_fp_vec3(direction)
    dut.ray_valid.value = 1
    await ClockCycles(dut.clk, 1)
    dut.ray_valid.value = 0
    await with_timeout(RisingEdge(dut.hit_valid), 5000, "ns")
    await ReadOnly()

async def expect_hit(dut, *, launch_offset, direction, expected_idx, x_sign):
    await ClockCycles(dut.clk, launch_offset)
    await launch_ray(dut, direction)
    assert dut.hit_any.value.integer == 1
    assert dut.hit_mat_idx.value.integer == expected_idx, (
        f"launch_offset={launch_offset} expected mat_idx={expected_idx}, got {dut.hit_mat_idx.value.integer}"
    )
    hit_pos = convert_fp_vec3(dut.hit_pos.value)
    if x_sign < 0:
        assert hit_pos[0] < 0.0
    elif x_sign > 0:
        assert hit_pos[0] > 0.0


@cocotb.test()
async def test_module(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst.value = 1
    dut.ray_valid.value = 0
    dut.ray_origin.value = 0
    dut.ray_dir.value = 0
    dut.num_objs.value = len(TEST_OBJECTS)
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 3)

    for launch_offset in range(len(TEST_OBJECTS)):
        await expect_hit(
            dut,
            launch_offset=launch_offset,
            direction=normalize((-1.5, 4.0, 0.0)),
            expected_idx=0,
            x_sign=-1,
        )
        await ClockCycles(dut.clk, 2)

        await expect_hit(
            dut,
            launch_offset=launch_offset,
            direction=normalize((1.5, 4.0, 0.0)),
            expected_idx=1,
            x_sign=1,
        )
        await ClockCycles(dut.clk, 2)

        await expect_hit(
            dut,
            launch_offset=launch_offset,
            direction=normalize((0.0, 8.0, 0.0)),
            expected_idx=2,
            x_sign=0,
        )
        await ClockCycles(dut.clk, 2)


def runner():
    sim = os.getenv("SIM", "icarus")
    build_dir = proj_path / "sim" / "sim_build" / "ray_intersector_scene"
    build_data_dir = build_dir / "data"
    build_data_dir.mkdir(parents=True, exist_ok=True)
    write_scene_mem(build_data_dir / "test_ray_intersector_scene_buffer.mem")

    sources = [
        proj_path / "hdl" / "constants.sv",
        proj_path / "hdl" / "types" / "types.sv",
        proj_path / "hdl" / "pipeline.sv",
        proj_path / "hdl" / "mem" / "xilinx_true_dual_port_read_first_2_clock_ram.v",
        *sorted((proj_path / "hdl" / "math").glob("*.sv")),
        proj_path / "hdl" / "rtx" / "scene_buffer.sv",
        proj_path / "hdl" / "rtx" / "ray_intersector.sv",
        proj_path / "sim" / "rtx" / "ray_intersector_scene_tb.sv",
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
        hdl_toplevel="ray_intersector_scene_tb",
        always=True,
        build_args=build_test_args,
        parameters={},
        timescale=("1ns", "1ps"),
        waves=True,
        build_dir=build_dir,
    )
    runner.test(
        hdl_toplevel="ray_intersector_scene_tb",
        test_module=".".join(Path(__file__).resolve().with_suffix("").relative_to(proj_path).parts),
        test_args=[],
        waves=True,
    )


if __name__ == "__main__":
    runner()
