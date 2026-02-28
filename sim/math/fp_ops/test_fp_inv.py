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

import matplotlib.pyplot as plt

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
    dut.x.value = make_fp(-7)
    await ClockCycles(dut.clk, 1)
    dut.x.value = make_fp(0.25)
    await ClockCycles(dut.clk, 1)
    dut.x.value = make_fp(1)
    await ClockCycles(dut.clk, 10)


    DELAY_CYCLES = 6
    

    N_SAMPLES = 1000

    async def mean_rel_err(vec_scale: float):
        xs = np.exp2((np.random.rand(N_SAMPLES) - 0.5) * 2 * vec_scale)

        # Clock in one per cycle brrr
        dut_ans = []
        for i in range(N_SAMPLES):
            x = make_fp(xs[i])

            dut.x.value = x

            await ClockCycles(dut.clk, 1)
            dut_ans.append(convert_fp(dut.inv.value))

        for _ in range(DELAY_CYCLES):
            await ClockCycles(dut.clk, 1)
            dut_ans.append(convert_fp(dut.inv.value))

        # Get answers!
        await ClockCycles(dut.clk, DELAY_CYCLES * 2)
        dut_ans = np.array(dut_ans[DELAY_CYCLES:])
        exp_ans = 1 / xs

        dut._log.info(f"{dut_ans[0]=:.6f}, {exp_ans[0]=:.6f}")

        rel_err = np.abs(dut_ans / exp_ans - 1)
        dut._log.info(f"vector scale: {scale:>2}\tmean relative error: {np.mean(rel_err) * 100:.6f}%")

        return np.mean(rel_err)

    # for scale in range(1, 63):
    scale = 32
    await mean_rel_err(scale)

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
        proj_path / "hdl" / "math" / "fp_inv_sqrt.sv",
        proj_path / "hdl" / "math" / "fp_inv.sv",
    ]
    build_test_args = ["-Wall"]

    # values for parameters defined earlier in the code.
    parameters = {}

    hdl_toplevel = "fp_inv"
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
