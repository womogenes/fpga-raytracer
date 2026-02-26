import os
import sys

from pathlib import Path

import matplotlib
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly
from cocotb.runner import get_runner

from enum import Enum
import random
import ctypes
import numpy as np

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from PIL import Image
from tqdm import tqdm

sys.path.append(Path(__file__).resolve().parent.parent._str)
from utils import convert_fp, make_fp, convert_fp_vec3, make_fp_vec3

WIDTH = 32 * 1
HEIGHT = 18 * 1

test_file = os.path.basename(__file__).replace(".py", "")

@cocotb.test()
async def test_module(dut):
    """cocotb test for the lazy mult module"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut._log.info("Holding reset...")
    dut.rst.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0    

    # Manual timing
    await ClockCycles(dut.clk, 3, False)

    dut.ray_origin.value = make_fp_vec3((0, 0, 0))
    dut.ray_dir.value = make_fp_vec3((1/np.sqrt(3), 1/np.sqrt(3), 1/np.sqrt(3)))

    dut.v0.value = make_fp_vec3((-1, 4, -1))
    dut.v0v1.value = make_fp_vec3((3, 0, 0))
    dut.v0v2.value = make_fp_vec3((0, 0, 3))
    dut.normal.value = make_fp_vec3((0, -1, 0))

    await ClockCycles(dut.clk, 1, False)
    dut.v0.value = make_fp_vec3((0, 6, 2))
    dut.v0v1.value = make_fp_vec3((-2, -2, -4))
    dut.v0v2.value = make_fp_vec3((2, -2, -4))
    dut.normal.value = make_fp_vec3((0, -2, 1))

    await ClockCycles(dut.clk, 1, False)
    dut.v0.value = make_fp_vec3((-1, 4, -1))
    dut.v0v1.value = make_fp_vec3((3, 0, 0))
    dut.v0v2.value = make_fp_vec3((0, 0, 3))
    dut.normal.value = make_fp_vec3((0, -1, 0))

    await ClockCycles(dut.clk, 30, False)
    
    # dut._log.info(f"{convert_fp_vec3(dut.hit_norm)}")

    # dut.v0.value = make_fp_vec3((0, 6, 2))
    # dut.v0v1.value = make_fp_vec3((-2, -2, -4))
    # dut.v0v2.value = make_fp_vec3((2, -2, -4))
    # dut.normal.value = make_fp_vec3((0, -2, 1))
    
    num_points = 1_000
    points = []
    missedpoints = []
    for i in range(num_points):
        dut.ray_origin.value = make_fp_vec3((0, 0, 0))
        random_val = np.random.random((2,))
        random_dir = np.array([random_val[0] - 0.5, 0.5, random_val[1] - 0.5])
        dirvec = random_dir / np.linalg.vector_norm(random_dir)
        dut.ray_dir.value = make_fp_vec3(dirvec)
        await ClockCycles(dut.clk, 20)
        await ReadOnly()
        if dut.hit.value:
            # print(convert_fp_vec3(dut.hit_pos.value))
            points.append(convert_fp_vec3(dut.hit_pos.value))
            # print(convert_fp_vec3(dut.hit_normal.value))
            # points.append(dirvec)
        else:
            missedpoints.append(convert_fp_vec3(dut.hit_pos.value))
        await ClockCycles(dut.clk, 1)

    fig = plt.figure(figsize=(12, 12))
    ax = fig.add_subplot(projection='3d')
    ax.set_aspect('equal')
    ax.set_xlim3d(-3, 3)
    ax.set_ylim3d(-2, 6)
    ax.set_zlim3d(-3, 3)

    if len(points) > 0:
        x_data, y_data, z_data = zip(*points)

        ax.scatter(x_data, y_data, z_data, s=2, alpha=1, color="blue")
    if len(missedpoints) > 0:
        x_data, y_data, z_data = zip(*missedpoints)
        ax.scatter(x_data, y_data, z_data, s=2, alpha=1, color="red")
    assert len(points) > 0, "expected at least one triangle hit"
    plt.close(fig)


def runner():
    """Module tester."""

    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent.parent
    sys.path.insert(0, str(proj_path))
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "pipeline.sv",
        proj_path / "hdl" / "constants.sv",
        proj_path / "hdl" / "types" / "types.sv",
        proj_path / "hdl" / "math" / "clz.sv",
        proj_path / "hdl" / "math" / "fp_shift.sv",
        proj_path / "hdl" / "math" / "fp_add.sv",
        proj_path / "hdl" / "math" / "fp_mul.sv",
        proj_path / "hdl" / "math" / "fp_inv.sv",
        proj_path / "hdl" / "math" / "fp_inv_sqrt.sv",
        proj_path / "hdl" / "math" / "fp_sqrt.sv",
        proj_path / "hdl" / "math" / "fp_vec3_ops.sv",
        proj_path / "hdl" / "math" / "trig_intersector.sv",
    ]
    build_test_args = ["-Wall"]

    # values for parameters defined earlier in the code.
    parameters = {}

    hdl_toplevel = "trig_intersector"
    
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=hdl_toplevel,
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
        build_dir=(proj_path / "sim" / "sim_build")
    )
    run_test_args = []
    test_module = ".".join(Path(__file__).resolve().with_suffix("").relative_to(proj_path).parts)
    runner.test(
        hdl_toplevel=hdl_toplevel,
        test_module=test_module,
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    runner()
