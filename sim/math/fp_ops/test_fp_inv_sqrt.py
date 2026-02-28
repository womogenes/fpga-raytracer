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
from utils import convert_fp, make_fp

test_file = os.path.basename(__file__).replace(".py", "")

@cocotb.test()
async def test_pipeline(dut):
    """
    Test if this module is truly pipelined by clocking in one value per clock cycle
    """
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut._log.info("Holding reset...")
    dut.rst.value = 1
    dut.x_valid.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst.value = 0

    # Assume some-cycle delay for this module
    DELAY_CYCLES = 8

    N_SAMPLES = 100
    x = np.exp2(np.random.rand(N_SAMPLES) * 63 - 31)
    x_fp = list(map(make_fp, x))

    # Clock in one per cycle brrr
    dut_ans = []
    dut.x_valid.value = 1
    for i in range(N_SAMPLES):
        dut.x.value = x_fp[i]
        await ClockCycles(dut.clk, 1)
        dut_ans.append(convert_fp(dut.inv_sqrt.value))

        # Output must be continually good to go
        if i >= DELAY_CYCLES:
            assert dut.inv_sqrt_valid.value
            pass

    dut.x_valid.value = 0

    for _ in range(DELAY_CYCLES):
        # assert dut.inv_sqrt_valid.value
        await ClockCycles(dut.clk, 1)
        dut_ans.append(convert_fp(dut.inv_sqrt.value))

    # Get answers!
    await ClockCycles(dut.clk, DELAY_CYCLES * 2)

    dut_ans = np.array(dut_ans[DELAY_CYCLES:])
    
    rel_err = np.abs((dut_ans / np.power(x, -0.5)) - 1)
    dut._log.info(f"mean relative error: {np.mean(rel_err) * 100:.6f}%")


@cocotb.test()
async def test_module(dut):
    """cocotb test for the fp inv sqrt module"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut._log.info("Holding reset...")
    dut.rst.value = 1
    await ClockCycles(dut.clk, 3)
    dut.rst.value = 0

    async def do_test(x: float):
        """
        Do a single test on 1/sqrt(x) using fp_inv_sqrt
        """
        x_f = make_fp(x)

        # Clock in value for 1 cycle
        dut.x.value = x_f
        dut.x_valid.value = 1
        await ClockCycles(dut.clk, 1)
        dut.x_valid.value = 0

        await RisingEdge(dut.inv_sqrt_valid)

        res = convert_fp(dut.inv_sqrt.value)
        await ClockCycles(dut.clk, 1)
        return res
    
    # x = -38000
    # y = 39000
    # res = await do_test(x, y, 0)
    # dut._log.info(f"{res=}, {x+y=}")
    # return
    dut._log.info(f"{make_fp(math.sqrt(2**63)):b}")
    dut._log.info(f"{make_fp(math.sqrt(2**63)):x}")

    # 0 1011110 0110_1010_0000_1010 = sqrt(2**63) = magic number
    # 0 1000001 0000_0000_0000_0000 = x = 4
    # 0 0111101 1110_1010_0000_1010 = magic number - (x >> 1)
    # dut._log.info(f"half={make_fp(0.5):x}")
    
    n_tests = 1_000
    total_err = 0
    x = 4.0
    
    exp_ans = 1/math.sqrt(x)
    dut_ans = await do_test(x)
    error = abs(dut_ans - exp_ans)

    dut._log.info(f"{x=:.5} {exp_ans=:.5} {dut_ans=:.5} {error=:.5}")

    for _ in range(n_tests):
        x = 2 ** (random.random() * 63 - 31)
        
        exp_ans = 1/math.sqrt(x)
        dut_ans = await do_test(x)
        error = abs(math.log2(dut_ans) - math.log2(exp_ans))

        dut._log.info(f"{x=:.5} {exp_ans=:.5} {dut_ans=:.5} {error=:.5}")

        total_err += abs((exp_ans / dut_ans) - 1)

    dut._log.info(f"Mean error: {total_err / n_tests * 100:.6f}%")


def runner():
    """Module tester."""

    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent.parent.parent
    sys.path.insert(0, str(proj_path))
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "constants.sv",
        proj_path / "hdl" / "pipeline.sv",
        proj_path / "hdl" / "types" / "types.sv",
        proj_path / "hdl" / "math" / "clz.sv",
        proj_path / "hdl" / "math" / "fp_shift.sv",
        proj_path / "hdl" / "math" / "fp_add.sv",
        proj_path / "hdl" / "math" / "fp_mul.sv",
        proj_path / "hdl" / "math" / "fp_inv_sqrt.sv"

    ]
    build_test_args = ["-Wall"]

    # values for parameters defined earlier in the code.
    parameters = {}

    hdl_toplevel = "fp_inv_sqrt"
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
