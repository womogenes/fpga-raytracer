import math
import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, RisingEdge

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from utils import convert_fp, convert_fp_vec3, make_fp_vec3

TRIG_DELAY = 14
EPSILON = 1e-3


def dot(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return sum(x * y for x, y in zip(a, b))


def cross(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (
        (a[1] * b[2]) - (a[2] * b[1]),
        (a[2] * b[0]) - (a[0] * b[2]),
        (a[0] * b[1]) - (a[1] * b[0]),
    )


def add(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return tuple(x + y for x, y in zip(a, b))


def sub(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return tuple(x - y for x, y in zip(a, b))


def scale(a: tuple[float, float, float], s: float) -> tuple[float, float, float]:
    return tuple(x * s for x in a)


def normalize(vec: tuple[float, float, float]) -> tuple[float, float, float]:
    mag = math.sqrt(dot(vec, vec))
    return tuple(component / mag for component in vec)


def scalar_close(actual: float, expected: float, *, tol: float = 0.05) -> None:
    abs_err = abs(actual - expected)
    rel_err = 0.0 if expected == 0 else abs_err / abs(expected)
    assert abs_err <= tol or rel_err <= 0.03, (
        f"expected={expected} actual={actual} abs_err={abs_err} rel_err={rel_err}"
    )


def vec_close(actual: tuple[float, float, float], expected: tuple[float, float, float], *, tol: float = 0.05) -> None:
    for got, exp in zip(actual, expected):
        scalar_close(got, exp, tol=tol)


def trig_expected(case: dict[str, object]) -> dict[str, object]:
    ray_origin = case["ray_origin"]
    ray_dir = case["ray_dir"]
    v0 = case["v0"]
    edge1 = case["v0v1"]
    edge2 = case["v0v2"]
    normal = case["normal"]
    obj_type = case["obj_type"]

    pvec = cross(ray_dir, edge2)
    det = dot(edge1, pvec)
    if det <= EPSILON:
        return {"hit": False}

    tvec = sub(ray_origin, v0)
    u = dot(tvec, pvec)
    qvec = cross(tvec, edge1)
    v = dot(ray_dir, qvec)

    if obj_type == 1:
        in_bounds = u >= 0.0 and v >= 0.0 and (u + v) <= det
    elif obj_type == 2:
        in_bounds = u >= 0.0 and u <= det and v >= 0.0 and v <= det
    else:
        in_bounds = True

    if not in_bounds:
        return {"hit": False}

    t_unnormalized = dot(edge2, qvec)
    t = t_unnormalized / det
    if t <= EPSILON:
        return {"hit": False}

    return {
        "hit": True,
        "hit_dist": t,
        "hit_pos": add(ray_origin, scale(ray_dir, t)),
        "hit_norm": normal,
    }


@cocotb.test()
async def test_module(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst.value = 1
    dut.ray_origin.value = 0
    dut.ray_dir.value = 0
    dut.v0.value = 0
    dut.v0v1.value = 0
    dut.v0v2.value = 0
    dut.normal.value = 0
    dut.obj_type.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0

    hit_triangle = {
        "ray_origin": (0.0, 0.0, 0.0),
        "ray_dir": (0.0, 1.0, 0.0),
        "v0": (-1.0, 4.0, -1.0),
        "v0v1": (2.0, 0.0, 0.0),
        "v0v2": (0.0, 0.0, 2.0),
        "normal": (0.0, -1.0, 0.0),
        "obj_type": 1,
    }
    miss_triangle = {
        "ray_origin": (0.0, 0.0, 0.0),
        "ray_dir": normalize((2.0, 4.0, 0.0)),
        "v0": (-1.0, 4.0, -1.0),
        "v0v1": (2.0, 0.0, 0.0),
        "v0v2": (0.0, 0.0, 2.0),
        "normal": (0.0, -1.0, 0.0),
        "obj_type": 1,
    }
    hit_parallelogram = {
        "ray_origin": (0.0, 0.0, 0.0),
        "ray_dir": normalize((0.5, 4.0, 0.5)),
        "v0": (-1.0, 4.0, -1.0),
        "v0v1": (2.0, 0.0, 0.0),
        "v0v2": (0.0, 0.0, 2.0),
        "normal": (0.0, -1.0, 0.0),
        "obj_type": 2,
    }
    hit_plane = {
        "ray_origin": (0.0, 0.0, 0.0),
        "ray_dir": normalize((3.0, 4.0, 0.0)),
        "v0": (-1.0, 4.0, -1.0),
        "v0v1": (2.0, 0.0, 0.0),
        "v0v2": (0.0, 0.0, 2.0),
        "normal": (0.0, -1.0, 0.0),
        "obj_type": 3,
    }

    cases = [miss_triangle, hit_triangle, hit_parallelogram, hit_plane]
    idle_case = miss_triangle
    expected_queue: list[dict[str, object]] = []

    async def drive_case(case: dict[str, object]) -> None:
        dut.ray_origin.value = make_fp_vec3(case["ray_origin"])
        dut.ray_dir.value = make_fp_vec3(case["ray_dir"])
        dut.v0.value = make_fp_vec3(case["v0"])
        dut.v0v1.value = make_fp_vec3(case["v0v1"])
        dut.v0v2.value = make_fp_vec3(case["v0v2"])
        dut.normal.value = make_fp_vec3(case["normal"])
        dut.obj_type.value = case["obj_type"]
        expected_queue.append(trig_expected(case))
        await RisingEdge(dut.clk)
        if len(expected_queue) > TRIG_DELAY:
            expected = expected_queue.pop(0)
            got_hit = bool(dut.hit.value.integer)
            assert got_hit == expected["hit"], f"hit mismatch for expected={expected}"
            if got_hit:
                scalar_close(convert_fp(dut.hit_dist.value.integer), expected["hit_dist"], tol=0.08)
                vec_close(convert_fp_vec3(dut.hit_pos.value.integer), expected["hit_pos"], tol=0.08)
                vec_close(convert_fp_vec3(dut.hit_norm.value.integer), expected["hit_norm"], tol=0.08)

    for _ in range(TRIG_DELAY):
        await drive_case(idle_case)

    for case in cases:
        await drive_case(case)

    for _ in range(TRIG_DELAY):
        await drive_case(idle_case)


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
        proj_path / "hdl" / "math" / "fp_inv.sv",
        proj_path / "hdl" / "math" / "fp_inv_sqrt.sv",
        proj_path / "hdl" / "math" / "fp_sqrt.sv",
        proj_path / "hdl" / "math" / "fp_vec3_ops.sv",
        proj_path / "hdl" / "math" / "trig_intersector.sv",
    ]
    hdl_toplevel = "trig_intersector"
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
