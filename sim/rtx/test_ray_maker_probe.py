import json
import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles

repo_root = Path(os.environ.get("RAY_MAKER_PROJ_PATH", Path(__file__).resolve().parents[2]))
script_dir = Path(__file__).resolve().parent
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from utils import FP_VEC3_BITS, convert_fp_vec3, make_fp_vec3, pack_bits

WIDTH = int(os.environ["RAY_MAKER_WIDTH"])
HEIGHT = int(os.environ["RAY_MAKER_HEIGHT"])
PIXELS = json.loads(os.environ["RAY_MAKER_PIXELS"])
CAM_DATA = json.loads(os.environ["RAY_MAKER_CAMERA"])
TRACE_CYCLES = int(os.environ.get("RAY_MAKER_TRACE_CYCLES", "0"))


def signal_is_high(signal) -> bool:
    value = signal.value
    return bool(value.is_resolvable and value.integer)


def safe_signal_int(signal):
    value = signal.value
    if value.is_resolvable:
        return value.integer
    return None


@cocotb.test()
async def test_module(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst.value = 1
    dut.new_ray.value = 0
    dut.pixel_h_in.value = 0
    dut.pixel_v_in.value = 0
    dut.lfsr_seed.value = int("0123456789abcdef01234567", 16)

    cam_scale = WIDTH / 1280
    dut.cam.value = pack_bits([
        (make_fp_vec3(CAM_DATA["origin"]), FP_VEC3_BITS),
        (make_fp_vec3([v * cam_scale for v in CAM_DATA["forward"]]), FP_VEC3_BITS),
        (make_fp_vec3(CAM_DATA["right"]), FP_VEC3_BITS),
        (make_fp_vec3(CAM_DATA["up"]), FP_VEC3_BITS),
    ])

    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    results = []
    for pixel_h, pixel_v in PIXELS:
        dut.pixel_h_in.value = pixel_h
        dut.pixel_v_in.value = pixel_v
        dut.new_ray.value = 1
        await ClockCycles(dut.clk, 1)
        dut.new_ray.value = 0

        if TRACE_CYCLES:
            trace = []
            for cycle in range(TRACE_CYCLES):
                await ClockCycles(dut.clk, 1)
                trace.append(
                    {
                        "cycle": cycle + 1,
                        "ray_valid": signal_is_high(dut.ray_valid),
                        "pixel_h_out": safe_signal_int(dut.pixel_h_out),
                        "pixel_v_out": safe_signal_int(dut.pixel_v_out),
                        "ray_dir": convert_fp_vec3(dut.ray_dir.value),
                    }
                )
            results.append(
                {
                    "pixel_h_in": pixel_h,
                    "pixel_v_in": pixel_v,
                    "trace": trace,
                }
            )
            continue

        for _ in range(64):
            await ClockCycles(dut.clk, 1)
            if signal_is_high(dut.ray_valid):
                results.append(
                    {
                        "pixel_h_in": pixel_h,
                        "pixel_v_in": pixel_v,
                        "pixel_h_out": dut.pixel_h_out.value.integer,
                        "pixel_v_out": dut.pixel_v_out.value.integer,
                        "ray_dir": convert_fp_vec3(dut.ray_dir.value),
                    }
                )
                break
        else:
            raise AssertionError(f"ray_valid did not assert for pixel {(pixel_h, pixel_v)}")

    print(json.dumps(results))


def runner():
    sim = os.getenv("SIM", "icarus")
    test_module = Path(__file__).resolve().stem
    build_dir = repo_root / "sim" / "sim_build" / "ray_maker_probe"
    sources = [
        repo_root / "hdl" / "pipeline.sv",
        repo_root / "hdl" / "constants.sv",
        repo_root / "hdl" / "types" / "types.sv",
        *sorted((repo_root / "hdl" / "math").glob("*.sv")),
        *sorted((repo_root / "hdl" / "rng").glob("*.sv")),
        repo_root / "hdl" / "rtx" / "ray_maker.sv",
        Path(__file__).resolve().parent / "ray_maker_probe_tb.sv",
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
        hdl_toplevel="ray_maker_probe_tb",
        always=True,
        build_args=build_test_args,
        parameters={"WIDTH": WIDTH, "HEIGHT": HEIGHT},
        timescale=("1ns", "1ps"),
        build_dir=build_dir,
    )
    runner.test(
        hdl_toplevel="ray_maker_probe_tb",
        test_module=test_module,
        test_dir=script_dir,
        extra_env={"PYTHONPATH": os.pathsep.join([str(script_dir), os.environ.get("PYTHONPATH", "")]).rstrip(os.pathsep)},
    )


if __name__ == "__main__":
    runner()
