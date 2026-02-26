import os
import pprint
import random
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles

proj_path = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(proj_path))
sys.path.append(str(proj_path / "sim"))

from utils import convert_fp, make_fp


def sample_fp_value():
    sign = -1.0 if random.random() < 0.5 else 1.0
    exp = random.randint(-10, 10)
    mant = 1.0 + random.random()
    return sign * mant * (2.0**exp)


@cocotb.test()
async def test_module(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.a.value = 0
    dut.b.value = 0
    dut.is_sub.value = 0
    await ClockCycles(dut.clk, 4)

    mismatches = []
    for _ in range(2000):
      a = sample_fp_value()
      b = sample_fp_value()
      is_sub = random.randint(0, 1)

      dut.a.value = make_fp(a)
      dut.b.value = make_fp(b)
      dut.is_sub.value = is_sub
      await ClockCycles(dut.clk, 1)
      new_val = dut.sum_new.value.integer
      await ClockCycles(dut.clk, 1)
      old_val = dut.sum_baseline.value.integer
      if new_val != old_val:
        ref = a - b if is_sub else a + b
        new_float = convert_fp(new_val)
        old_float = convert_fp(old_val)
        mismatches.append(
          {
            "a": a,
            "b": b,
            "is_sub": is_sub,
            "new_bits": new_val,
            "old_bits": old_val,
            "new_float": new_float,
            "old_float": old_float,
            "ref_float": ref,
            "new_abs_err": abs(new_float - ref),
            "old_abs_err": abs(old_float - ref),
          }
        )
        if len(mismatches) >= 20:
          break

    assert not mismatches, pprint.pformat(mismatches, sort_dicts=False)


def runner():
    sim = os.getenv("SIM", "icarus")
    build_dir = proj_path / "sim" / "sim_build" / "fp_add_vs_baseline"
    sources = [
        proj_path / "hdl" / "constants.sv",
        proj_path / "hdl" / "types" / "types.sv",
        proj_path / "hdl" / "pipeline.sv",
        proj_path / "hdl" / "math" / "clz.sv",
        proj_path / "hdl" / "math" / "fp_add.sv",
        proj_path / "sim" / "math" / "fp_ops" / "fp_add_baseline_compat.sv",
        proj_path / "sim" / "math" / "fp_ops" / "fp_add_compare_tb.sv",
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
        hdl_toplevel="fp_add_compare_tb",
        always=True,
        build_args=build_test_args,
        timescale=("1ns", "1ps"),
        waves=True,
        build_dir=build_dir,
    )
    runner.test(
        hdl_toplevel="fp_add_compare_tb",
        test_module=".".join(Path(__file__).resolve().with_suffix("").relative_to(proj_path).parts),
        waves=True,
    )


if __name__ == "__main__":
    runner()
