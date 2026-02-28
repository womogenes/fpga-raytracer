import glob
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
from make_scene_buffer import Material, Object


LEFT_MAT_IDX = 0
RIGHT_MAT_IDX = 1
LEFT_EMIT = (0.8, 0.1, 0.2)
RIGHT_EMIT = (0.1, 0.7, 0.3)
TEST_OBJECTS = [
    Object(mat_idx=LEFT_MAT_IDX, sphere_center=(-1.0, 4.0, 0.0), sphere_rad=1.0, obj_type=0),
    Object(mat_idx=RIGHT_MAT_IDX, sphere_center=(1.0, 4.0, 0.0), sphere_rad=1.0, obj_type=0),
]
TEST_MATERIALS = [
    Material(color=(1.0, 1.0, 1.0), emit_color=LEFT_EMIT, spec_color=(1.0, 1.0, 1.0), smoothness=0.0, specular_prob=0.0),
    Material(color=(1.0, 1.0, 1.0), emit_color=RIGHT_EMIT, spec_color=(1.0, 1.0, 1.0), smoothness=0.0, specular_prob=0.0),
]


def normalize(vec):
    arr = np.asarray(vec, dtype=float)
    return tuple(arr / np.linalg.norm(arr))


def write_material_mem(path: Path) -> None:
    packed = []
    for mat in TEST_MATERIALS:
        bits, width = mat.pack_bits()
        packed.append(hex(bits)[2:].zfill((width + 3) // 4))
    path.write_text("\n".join(packed) + "\n")


async def stream_scene(dut):
    dut.num_objs.value = len(TEST_OBJECTS)
    while True:
        for obj in TEST_OBJECTS:
            dut.obj.value = obj.pack_bits()[0]
            await ClockCycles(dut.clk, 1)


async def launch_ray(dut, direction):
    dut.ray_origin.value = make_fp_vec3((0.0, 0.0, 0.0))
    dut.ray_dir.value = make_fp_vec3(direction)
    dut.ray_valid.value = 1
    await ClockCycles(dut.clk, 1)
    dut.ray_valid.value = 0
    await with_timeout(RisingEdge(dut.ray_done), 5000, "ns")
    await ReadOnly()


def assert_color_close(actual, expected):
    for got, want in zip(actual, expected):
        assert abs(got - want) < 0.08, f"expected {expected}, got {actual}"


@cocotb.test()
async def test_module(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst.value = 1
    dut.ray_valid.value = 0
    dut.ray_origin.value = 0
    dut.ray_dir.value = 0
    dut.obj.value = 0
    dut.num_objs.value = 0
    dut.max_bounces.value = 1
    dut.lfsr_seed.value = int("0123456789abcdef01234567", 16)
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 3)

    cocotb.start_soon(stream_scene(dut))
    await ClockCycles(dut.clk, 3)

    await launch_ray(dut, normalize((-1.0, 4.0, 0.0)))
    assert_color_close(convert_fp_vec3(dut.pixel_color.value), LEFT_EMIT)

    await ClockCycles(dut.clk, 2)

    await launch_ray(dut, normalize((1.0, 4.0, 0.0)))
    assert_color_close(convert_fp_vec3(dut.pixel_color.value), RIGHT_EMIT)

    await ClockCycles(dut.clk, 2)

    await launch_ray(dut, normalize((0.0, 0.0, 1.0)))
    assert_color_close(convert_fp_vec3(dut.pixel_color.value), (0.0, 0.0, 0.0))


def runner():
    sim = os.getenv("SIM", "icarus")
    build_dir = proj_path / "sim" / "sim_build" / "ray_tracer"
    build_data_dir = build_dir / "data"
    build_data_dir.mkdir(parents=True, exist_ok=True)
    write_material_mem(build_data_dir / "test_ray_tracer_mat_dict.mem")

    sources = [
        proj_path / "hdl" / "constants.sv",
        proj_path / "hdl" / "types" / "types.sv",
        proj_path / "hdl" / "pipeline.sv",
        proj_path / "hdl" / "mem" / "xilinx_true_dual_port_read_first_2_clock_ram.v",
        *glob.glob(f"{proj_path}/hdl/rng/*.sv", recursive=True),
        *glob.glob(f"{proj_path}/hdl/math/*.sv", recursive=True),
        proj_path / "hdl" / "rtx" / "material_dictionary.sv",
        proj_path / "hdl" / "rtx" / "ray_intersector.sv",
        proj_path / "hdl" / "rtx" / "ray_reflector.sv",
        proj_path / "hdl" / "rtx" / "ray_tracer.sv",
        proj_path / "sim" / "rtx" / "ray_tracer_tb.sv",
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
        hdl_toplevel="ray_tracer_tb",
        always=True,
        build_args=build_test_args,
        parameters={},
        timescale=("1ns", "1ps"),
        waves=True,
        build_dir=build_dir,
    )
    runner.test(
        hdl_toplevel="ray_tracer_tb",
        test_module=".".join(Path(__file__).resolve().with_suffix("").relative_to(proj_path).parts),
        test_args=[],
        waves=True,
    )


if __name__ == "__main__":
    runner()
