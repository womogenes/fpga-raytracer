import math
import os
import random
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, RisingEdge

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from utils import convert_fp, make_fp

DELAY_CYCLES = 12


def solver_expected(b: float, c: float) -> tuple[bool, float | None, bool]:
    discr = b * b - (4.0 * c)
    if discr < 0:
        return False, None, False
    return True, (-b - math.sqrt(discr)) / 2.0, abs(discr) < 1e-9


def assert_close(actual: float, expected: float, case: tuple[float, float]) -> None:
    abs_err = abs(actual - expected)
    rel_err = 0.0 if expected == 0 else abs_err / abs(expected)
    assert abs_err <= 0.02 or rel_err <= 0.01, (
        f"case={case} expected={expected} actual={actual} abs_err={abs_err} rel_err={rel_err}"
    )


@cocotb.test()
async def test_module(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst.value = 1
    dut.b.value = 0
    dut.c.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst.value = 0

    rng = random.Random(0)
    fixed_cases = [
        (-8.0, 12.0),
        (-6.0, 8.0),
        (-4.0, 4.0),
        (0.0, -4.0),
        (1.0, 1.0),
        (2.0, 2.0),
        (0.0, 1.0),
    ]
    random_cases = []
    for _ in range(200):
        b = rng.uniform(-12.0, 4.0)
        c = rng.uniform(-8.0, 16.0)
        random_cases.append((b, c))
    cases = fixed_cases + random_cases

    idle_case = (0.0, 1.0)
    expected_queue: list[tuple[tuple[float, float], bool, float | None, bool]] = []
    checked_nonlocal = [0]

    async def drive_case(case: tuple[float, float]) -> None:
        b, c = case
        dut.b.value = make_fp(b)
        dut.c.value = make_fp(c)
        expected_valid, expected_x0, tangent_case = solver_expected(b, c)
        expected_queue.append((case, expected_valid, expected_x0, tangent_case))
        await RisingEdge(dut.clk)
        if len(expected_queue) > DELAY_CYCLES:
            prev_case, prev_valid, prev_x0, prev_tangent = expected_queue.pop(0)
            got_valid = bool(dut.valid.value.integer)
            if not prev_tangent:
                assert got_valid == prev_valid, f"valid mismatch for case={prev_case}"
            if prev_valid and not prev_tangent:
                got_x0 = convert_fp(dut.x0.value.integer)
                assert_close(got_x0, prev_x0, prev_case)
                residual = abs((got_x0 * got_x0) + (prev_case[0] * got_x0) + prev_case[1])
                assert residual <= 0.1, f"residual too large for case={prev_case}: {residual}"
            checked_nonlocal[0] += 1

    for _ in range(DELAY_CYCLES):
        await drive_case(idle_case)

    for case in cases:
        await drive_case(case)

    for _ in range(DELAY_CYCLES):
        await drive_case(idle_case)

    checked = checked_nonlocal[0]
    assert checked == len(cases) + DELAY_CYCLES, f"expected {len(cases) + DELAY_CYCLES} checks, got {checked}"


def runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parents[2]
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
        proj_path / "hdl" / "math" / "quadratic_solver.sv",
    ]
    hdl_toplevel = "quadratic_solver"
    test_module = ".".join(Path(__file__).resolve().with_suffix("").relative_to(proj_path).parts)

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=hdl_toplevel,
        always=True,
        build_args=["-Wall"],
        parameters={},
        timescale=("1ns", "1ps"),
        waves=True,
        build_dir=(proj_path / "sim" / "sim_build"),
    )
    runner.test(
        hdl_toplevel=hdl_toplevel,
        test_module=test_module,
        test_args=[],
        waves=True,
    )


if __name__ == "__main__":
    runner()
