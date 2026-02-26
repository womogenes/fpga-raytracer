import os
import sys

from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, ReadOnly
from cocotb.runner import get_runner

from enum import Enum
import random
import ctypes
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from PIL import Image
from tqdm import tqdm

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
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

    print(convert_fp(0x430000))

    # dut.ray_origin.value = make_fp_vec3((0, 0, 0))
    # dut.ray_dir.value = make_fp_vec3((0, 1, 0))

    # dut.sphere_center.value = make_fp_vec3((0, 4, 0))
    # dut.sphere_rad_sq.value = make_fp(1)
    # dut.sphere_rad_inv.value = make_fp(1)
    # await ClockCycles(dut.clk, 1, False)
    # dut.sphere_center.value = make_fp_vec3((0, 4, 1))
    # dut.sphere_rad_sq.value = make_fp(0.25)
    # dut.sphere_rad_inv.value = make_fp(2)
    # await ClockCycles(dut.clk, 1, False)
    dut.sphere_center.value = make_fp_vec3((0, 4, 0))
    dut.sphere_rad_sq.value = make_fp(1)
    dut.sphere_rad_inv.value = make_fp(1)
    # await ClockCycles(dut.clk, 30, False)
    # dut._log.info(f"{convert_fp_vec3(dut.hit_norm)}")
    # return 

    num_points = 1_000
    points = []
    normalpoints = []
    for i in range(num_points):
        dut.ray_origin.value = make_fp_vec3((0, 0, 0))
        random_val = np.random.random((2,))
        random_dir = np.array([random_val[0] - 0.5, 1, random_val[1] - 0.5])
        dirvec = random_dir / np.linalg.vector_norm(random_dir)
        dut.ray_dir.value = make_fp_vec3(dirvec)
        await ClockCycles(dut.clk, 30)
        if (dut.hit.value):
            # print(convert_fp_vec3(dut.hit_pos.value))
            points.append(convert_fp_vec3(dut.hit_pos.value))
            # print(convert_fp_vec3(dut.hit_normal.value))
            normalpoints.append(convert_fp_vec3(dut.hit_norm.value))
            # points.append(dirvec)
        await ClockCycles(dut.clk, 1)

    assert points, "expected at least one sphere hit"
    assert normalpoints, "expected at least one normal sample"

    fig = plt.figure(figsize=(12, 12))
    ax = fig.add_subplot(projection='3d')
    ax.set_aspect('equal')
    ax.set_xlim3d(-2, 2)
    ax.set_ylim3d(-2, 5)
    ax.set_zlim3d(-2, 2)

    if points:
        x_data, y_data, z_data = zip(*points)
        ax.scatter(x_data, y_data, z_data, s=2, alpha=1, color="blue")
    if normalpoints:
        x_data, y_data, z_data = zip(*normalpoints)
        ax.scatter(x_data, y_data, z_data, s=2, alpha=1, color="red")
    plt.close(fig)


def runner():
    """Module tester."""

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
        proj_path / "hdl" / "math" / "fp_inv_sqrt.sv",
        proj_path / "hdl" / "math" / "fp_sqrt.sv",
        proj_path / "hdl" / "math" / "fp_vec3_ops.sv",
        proj_path / "hdl" / "math" / "quadratic_solver.sv",
        proj_path / "hdl" / "math" / "sphere_intersector.sv",
    ]
    build_test_args = ["-Wall"]

    # values for parameters defined earlier in the code.
    parameters = {}

    hdl_toplevel = "sphere_intersector"
    test_module = ".".join(Path(__file__).resolve().with_suffix("").relative_to(proj_path).parts)
    
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
    runner.test(
        hdl_toplevel=hdl_toplevel,
        test_module=test_module,
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    runner()
