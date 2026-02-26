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
import math

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from utils import convert_fp, make_fp, make_fp_vec3, convert_fp_vec3

test_file = os.path.basename(__file__).replace(".py", "")

@cocotb.test()
async def test_module(dut):
    """
    Test module: vec3 addition using fp
    """
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut._log.info("Holding reset...")
    dut.rst.value = 1
    await ClockCycles(dut.clk, 3)
    dut.rst.value = 0

    DELAY_CYCLES = 3

    N_SAMPLES = 1000

    # Generate random (N, 3) tensors for inputs
    a_vecs = np.exp2(np.random.rand(N_SAMPLES, 3) * 63 - 31)
    a_vecs_fp = list(map(make_fp_vec3, a_vecs))

    b_vecs = np.exp2(np.random.rand(N_SAMPLES, 3) * 63 - 31)
    b_vecs_fp = list(map(make_fp_vec3, b_vecs))

    # Clock in one per cycle brrr
    dut_ans = []
    for i in range(N_SAMPLES):
        a_fp_vec3 = a_vecs_fp[i]
        b_fp_vec3 = b_vecs_fp[i]

        dut.v.value = a_fp_vec3
        dut.w.value = b_fp_vec3

        await ClockCycles(dut.clk, 1)
        # await RisingEdge(dut.clk)
        dut_ans.append(convert_fp(dut.dot.value))

    for _ in range(DELAY_CYCLES):
        await ClockCycles(dut.clk, 1)
        dut_ans.append(convert_fp(dut.dot.value))

    # Get answers!
    await ClockCycles(dut.clk, DELAY_CYCLES * 2)
    dut_ans = np.array(dut_ans[DELAY_CYCLES:])
    exp_ans = (a_vecs * b_vecs).sum(axis=1)

    rel_err = np.abs(dut_ans / exp_ans - 1)
    dut._log.info(f"mean relative error: {np.mean(rel_err) * 100:.6f}%")


def runner():
    """Module tester."""

    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent.parent.parent
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
        proj_path / "hdl" / "math" / "fp_vec3_ops.sv",
    ]
    build_test_args = ["-Wall"]

    # values for parameters defined earlier in the code.
    parameters = {}

    hdl_toplevel = "fp_vec3_dot"
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
