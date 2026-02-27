import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles

import numpy as np

sys.path.append(str(Path(__file__).resolve().parent))
sys.path.append(str(Path(__file__).resolve().parent.parent))
from utils import convert_fp_vec3, make_fp_vec3


SPECULAR_REFLECT_DELAY = 8
ABS_TOL = 3e-3

test_file = os.path.basename(__file__).replace(".py", "")


def normalize(vec):
    arr = np.asarray(vec, dtype=float)
    norm = np.linalg.norm(arr)
    assert norm > 1e-9
    return arr / norm


@cocotb.test()
async def test_module(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0

    rng = np.random.default_rng(0)
    samples = [
        (normalize((1.0, -1.0, 0.0)), normalize((0.0, 1.0, 0.0))),
        (normalize((0.2, -1.0, 0.0)), normalize((0.0, 1.0, 0.0))),
        (normalize((1.0, 0.0, 0.0)), normalize((1.0, 0.0, 0.0))),
        (normalize((1.0, 2.0, -3.0)), normalize((-1.0, 4.0, 2.0))),
    ]
    for _ in range(256):
        in_dir = normalize(rng.normal(size=3))
        normal = normalize(rng.normal(size=3))
        samples.append((in_dir, normal))

    dut_outputs = []
    for cycle in range(len(samples) + SPECULAR_REFLECT_DELAY):
        if cycle < len(samples):
            in_dir, normal = samples[cycle]
            dut.in_dir.value = make_fp_vec3(tuple(in_dir))
            dut.normal.value = make_fp_vec3(tuple(normal))

        await ClockCycles(dut.clk, 1)

        if cycle >= SPECULAR_REFLECT_DELAY:
            dut_outputs.append(np.asarray(convert_fp_vec3(dut.out_dir.value.integer), dtype=float))

    expected = []
    for in_dir, normal in samples:
        expected.append(in_dir - 2.0 * np.dot(in_dir, normal) * normal)
    expected = np.asarray(expected)
    observed = np.asarray(dut_outputs)

    abs_err = np.abs(observed - expected)
    max_abs_err = float(abs_err.max())
    mean_abs_err = float(abs_err.mean())

    dut._log.info(f"specular_reflect max_abs_err={max_abs_err:.6f} mean_abs_err={mean_abs_err:.6f}")
    assert observed.shape == expected.shape
    assert max_abs_err < ABS_TOL


def runner():
    hdl_toplevel_lang = os.getenv("HDL_TOPLEVEL_LANG", "verilog")
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent.parent
    build_dir = proj_path / "sim" / "sim_build" / f"{test_file}_{sim}"
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
        proj_path / "hdl" / "math" / "fp_vec3_ops.sv",
        proj_path / "hdl" / "math" / "specular_reflect.sv",
    ]
    build_test_args = ["-Wall"]

    sys.path.append(str(proj_path / "sim"))
    hdl_toplevel = "specular_reflect"

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel=hdl_toplevel,
        always=True,
        build_args=build_test_args,
        parameters={},
        timescale=("1ns", "1ps"),
        waves=True,
        build_dir=build_dir,
    )
    runner.test(
        hdl_toplevel=hdl_toplevel,
        test_module=test_file,
        test_args=[],
        waves=True,
    )


if __name__ == "__main__":
    runner()
