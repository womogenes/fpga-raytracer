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

from utils import convert_fp_vec3, make_fp_vec3


def sample_vec():
    return [
        (1.0 + random.random()) * (2.0 ** random.randint(-10, 10))
        for _ in range(3)
    ]


@cocotb.test()
async def test_module(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst.value = 1
    dut.v.value = 0
    await ClockCycles(dut.clk, 4)
    dut.rst.value = 0

    mismatches = []
    for _ in range(200):
        v = sample_vec()
        dut.v.value = make_fp_vec3(v)
        await ClockCycles(dut.clk, 12)
        new_val = dut.normed_new.value.integer
        await ClockCycles(dut.clk, 4)
        old_val = dut.normed_baseline.value.integer

        if new_val != old_val:
            mismatches.append(
                {
                    "v": v,
                    "new_bits": new_val,
                    "old_bits": old_val,
                    "new_vec": convert_fp_vec3(new_val),
                    "old_vec": convert_fp_vec3(old_val),
                }
            )
            if len(mismatches) >= 20:
                break

        await ClockCycles(dut.clk, 2)

    assert not mismatches, pprint.pformat(mismatches, sort_dicts=False)


@cocotb.test()
async def test_streaming_module(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst.value = 1
    dut.v.value = 0
    await ClockCycles(dut.clk, 4)
    dut.rst.value = 0

    inputs = [sample_vec() for _ in range(400)]
    new_outputs = []
    old_outputs = []

    for v in inputs:
        dut.v.value = make_fp_vec3(v)
        await ClockCycles(dut.clk, 1)
        new_outputs.append(dut.normed_new.value.integer)
        old_outputs.append(dut.normed_baseline.value.integer)

    for _ in range(20):
        await ClockCycles(dut.clk, 1)
        new_outputs.append(dut.normed_new.value.integer)
        old_outputs.append(dut.normed_baseline.value.integer)

    mismatches = []
    for i, v in enumerate(inputs):
        new_val = new_outputs[i + 12]
        old_val = old_outputs[i + 16]
        if new_val != old_val:
            mismatches.append(
                {
                    "index": i,
                    "v": v,
                    "new_bits": new_val,
                    "old_bits": old_val,
                    "new_vec": convert_fp_vec3(new_val),
                    "old_vec": convert_fp_vec3(old_val),
                }
            )
            if len(mismatches) >= 20:
                break

    assert not mismatches, pprint.pformat(mismatches, sort_dicts=False)


def runner():
    sim = os.getenv("SIM", "icarus")
    build_dir = proj_path / "sim" / "sim_build" / "fp_vec3_normalize_vs_baseline"
    sources = [
        proj_path / "hdl" / "constants.sv",
        proj_path / "hdl" / "types" / "types.sv",
        proj_path / "hdl" / "pipeline.sv",
        proj_path / "hdl" / "math" / "clz.sv",
        proj_path / "hdl" / "math" / "fp_shift.sv",
        proj_path / "hdl" / "math" / "fp_mul.sv",
        proj_path / "hdl" / "math" / "fp_add.sv",
        proj_path / "hdl" / "math" / "fp_inv_sqrt.sv",
        proj_path / "hdl" / "math" / "fp_vec3_ops.sv",
        proj_path / "sim" / "math" / "fp_ops" / "fp_add_baseline_compat.sv",
        proj_path / "sim" / "math" / "fp_ops" / "fp_inv_sqrt_baseline_compat.sv",
        proj_path / "sim" / "math" / "fp_ops" / "fp_vec3_dot_baseline_compat.sv",
        proj_path / "sim" / "math" / "fp_ops" / "fp_vec3_normalize_baseline_compat.sv",
        proj_path / "sim" / "math" / "fp_ops" / "fp_vec3_normalize_compare_tb.sv",
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
        hdl_toplevel="fp_vec3_normalize_compare_tb",
        always=True,
        build_args=build_test_args,
        timescale=("1ns", "1ps"),
        waves=True,
        build_dir=build_dir,
    )
    runner.test(
        hdl_toplevel="fp_vec3_normalize_compare_tb",
        test_module=".".join(Path(__file__).resolve().with_suffix("").relative_to(proj_path).parts),
        waves=True,
    )


if __name__ == "__main__":
    runner()
