import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, ReadOnly

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


async def issue_lane(dut, lane_idx, direction):
    getattr(dut, f"ray{lane_idx}_origin").value = make_fp_vec3((0.0, 0.0, 0.0))
    getattr(dut, f"ray{lane_idx}_dir").value = make_fp_vec3(direction)
    getattr(dut, f"ray{lane_idx}_valid").value = 1
    await ClockCycles(dut.clk, 1)
    getattr(dut, f"ray{lane_idx}_valid").value = 0


async def wait_for_hits(dut):
    hit_results = {}
    for _ in range(256):
        await ClockCycles(dut.clk, 1)
        await ReadOnly()
        if dut.hit0_valid.value.integer and 0 not in hit_results:
            hit_results[0] = (
                dut.hit0_mat_idx.value.integer,
                convert_fp_vec3(dut.hit0_pos.value),
                dut.hit0_any.value.integer,
            )
        if dut.hit1_valid.value.integer and 1 not in hit_results:
            hit_results[1] = (
                dut.hit1_mat_idx.value.integer,
                convert_fp_vec3(dut.hit1_pos.value),
                dut.hit1_any.value.integer,
            )
        if len(hit_results) == 2:
            return hit_results
    raise AssertionError("timed out waiting for both intersector lanes to finish")


@cocotb.test()
async def test_shared_stream_overlap(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst.value = 1
    dut.num_objs.value = len(TEST_OBJECTS)
    dut.ray0_origin.value = 0
    dut.ray0_dir.value = 0
    dut.ray0_valid.value = 0
    dut.ray1_origin.value = 0
    dut.ray1_dir.value = 0
    dut.ray1_valid.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 3)

    for launch_offset in range(len(TEST_OBJECTS)):
        await ClockCycles(dut.clk, launch_offset)
        await issue_lane(dut, 0, normalize((-1.5, 4.0, 0.0)))
        await issue_lane(dut, 1, normalize((1.5, 4.0, 0.0)))
        hit_results = await wait_for_hits(dut)

        lane0_mat_idx, lane0_pos, lane0_any = hit_results[0]
        lane1_mat_idx, lane1_pos, lane1_any = hit_results[1]
        assert lane0_any == 1
        assert lane1_any == 1
        assert lane0_mat_idx == 0
        assert lane1_mat_idx == 1
        assert lane0_pos[0] < 0.0
        assert lane1_pos[0] > 0.0

        await ClockCycles(dut.clk, 3)


def runner():
    sim = os.getenv("SIM", "icarus")
    build_dir = proj_path / "sim" / "sim_build" / "ray_intersector_multi"
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
        proj_path / "sim" / "rtx" / "ray_intersector_multi_tb.sv",
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
        hdl_toplevel="ray_intersector_multi_tb",
        always=True,
        build_args=build_test_args,
        parameters={},
        timescale=("1ns", "1ps"),
        waves=True,
        build_dir=build_dir,
    )
    runner.test(
        hdl_toplevel="ray_intersector_multi_tb",
        test_module=".".join(Path(__file__).resolve().with_suffix("").relative_to(proj_path).parts),
        test_args=[],
        waves=True,
    )


if __name__ == "__main__":
    runner()
