import os
import sys

from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from cocotb.runner import get_runner

import math
import random

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from utils import FP_EXP_BITS, FP_EXP_OFFSET, FP_MANT_BITS, convert_fp, make_fp

test_file = os.path.basename(__file__).replace(".py", "")

@cocotb.test()
async def test_module(dut):
    """cocotb test for fp_add"""
    dut._log.info("Starting...")
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut._log.info("Holding reset...")
    dut.rst.value = 1
    await ClockCycles(dut.clk, 3)
    dut.rst.value = 0

    rng = random.Random(0)

    def expected_value(x: float, y: float, is_sub: bool) -> float:
        result = x - y if is_sub else x + y
        if result == 0:
            return 0

        sign = int(result < 0)
        value = abs(result)
        exp = int(math.floor(math.log2(value)))
        exp_biased = exp + FP_EXP_OFFSET
        frac = value / (2 ** exp)
        mant = int((frac - 1.0) * (1 << FP_MANT_BITS) + 0.5)
        if mant == (1 << FP_MANT_BITS):
            mant = 0
            exp_biased += 1
        packed = (sign << (FP_EXP_BITS + FP_MANT_BITS)) | (exp_biased << FP_MANT_BITS) | mant
        return convert_fp(packed)

    def assert_close(actual: float, expected: float, case: tuple[float, float, bool]) -> None:
        if expected == 0:
            assert actual == 0, f"expected zero for case={case}, got {actual}"
            return
        abs_err = abs(actual - expected)
        rel_err = abs_err / abs(expected)
        assert abs_err <= 0.02 or rel_err <= 0.005, (
            f"case={case} expected={expected} actual={actual} "
            f"abs_err={abs_err} rel_err={rel_err}"
        )

    fixed_cases = [
        (0.0, 0.0, False),
        (0.0, 0.0, True),
        (1.5, 1.5, True),
        (-42.25, -42.25, True),
        (63.5, 0.25, False),
        (63.5, 0.25, True),
        (1.0, -1.0, False),
        (-1.0, 1.0, False),
        (128.0, 0.001953125, False),
        (128.0, 0.001953125, True),
    ]
    random_cases = []
    for _ in range(500):
        x = (rng.random() - 0.5) * 200
        y = (rng.random() - 0.5) * 200
        is_sub = rng.random() < 0.5
        random_cases.append((x, y, is_sub))
    cases = fixed_cases + random_cases

    dut.a.value = 0
    dut.b.value = 0
    dut.is_sub.value = 0
    await RisingEdge(dut.clk)

    expected_queue = []
    total_rel_err = 0.0
    total_checked = 0

    for case in cases:
        x, y, is_sub = case
        dut.a.value = make_fp(x)
        dut.b.value = make_fp(y)
        dut.is_sub.value = is_sub
        expected_queue.append((case, expected_value(x, y, is_sub)))

        await RisingEdge(dut.clk)
        if len(expected_queue) > 1:
            prev_case, prev_expected = expected_queue.pop(0)
            dut_ans = convert_fp(dut.sum.value)
            assert_close(dut_ans, prev_expected, prev_case)
            if prev_expected != 0:
                total_rel_err += abs((dut_ans - prev_expected) / prev_expected)
            total_checked += 1

    await RisingEdge(dut.clk)
    final_case, final_expected = expected_queue.pop(0)
    final_ans = convert_fp(dut.sum.value)
    assert_close(final_ans, final_expected, final_case)
    if final_expected != 0:
        total_rel_err += abs((final_ans - final_expected) / final_expected)
    total_checked += 1

    dut._log.info(f"Checked {total_checked} streamed cases")
    dut._log.info(f"Mean relative error: {total_rel_err / max(total_checked, 1) * 100:.6f}%")


def runner():
    """Module tester."""

    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent.parent.parent
    sys.path.insert(0, str(proj_path))
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "constants.sv",
        proj_path / "hdl" / "types" / "types.sv",
        proj_path / "hdl" / "math" / "clz.sv",
        proj_path / "hdl" / "math" / "fp_add.sv"
    ]
    build_test_args = ["-Wall"]

    # values for parameters defined earlier in the code.
    parameters = {}

    hdl_toplevel = "fp_add"
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
