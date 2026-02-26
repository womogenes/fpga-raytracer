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
from utils import convert_fp, convert_fp_vec3, make_fp, make_fp_vec3

SPHERE_DELAY = 20


def vec_close(actual: tuple[float, float, float], expected: tuple[float, float, float], *, tol: float = 0.03) -> None:
    for idx, (got, exp) in enumerate(zip(actual, expected)):
        abs_err = abs(got - exp)
        rel_err = 0.0 if exp == 0 else abs_err / abs(exp)
        assert abs_err <= tol or rel_err <= 0.02, (
            f"vec idx={idx} expected={expected} actual={actual} abs_err={abs_err} rel_err={rel_err}"
        )


def scalar_close(actual: float, expected: float, *, tol: float = 0.03) -> None:
    abs_err = abs(actual - expected)
    rel_err = 0.0 if expected == 0 else abs_err / abs(expected)
    assert abs_err <= tol or rel_err <= 0.02, (
        f"expected={expected} actual={actual} abs_err={abs_err} rel_err={rel_err}"
    )


def normalize(vec: tuple[float, float, float]) -> tuple[float, float, float]:
    mag = math.sqrt(sum(component * component for component in vec))
    return tuple(component / mag for component in vec)


def sphere_expected(case: dict[str, object]) -> dict[str, object]:
    ray_origin = case["ray_origin"]
    ray_dir = case["ray_dir"]
    sphere_center = case["sphere_center"]
    sphere_rad = case["sphere_rad"]
    sphere_rad_inv = case["sphere_rad_inv"]

    l_vec = tuple(ro - sc for ro, sc in zip(ray_origin, sphere_center))
    b = 2.0 * sum(rd * lv for rd, lv in zip(ray_dir, l_vec))
    c = sum(lv * lv for lv in l_vec) - (sphere_rad * sphere_rad)
    discr = b * b - (4.0 * c)
    if discr < 0:
        return {"hit": False}

    x0 = (-b - math.sqrt(discr)) / 2.0
    if x0 < 0:
        return {"hit": False}

    hit_pos = tuple(ro + (rd * x0) for ro, rd in zip(ray_origin, ray_dir))
    hit_norm = tuple((hp - sc) * sphere_rad_inv for hp, sc in zip(hit_pos, sphere_center))
    return {
        "hit": True,
        "hit_dist": x0,
        "hit_pos": hit_pos,
        "hit_norm": hit_norm,
    }


@cocotb.test()
async def test_module(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst.value = 1
    await ClockCycles(dut.clk, 5)
    dut.rst.value = 0

    rng = random.Random(0)
    deterministic_cases = [
        {
            "ray_origin": (0.0, 0.0, 0.0),
            "ray_dir": (0.0, 1.0, 0.0),
            "sphere_center": (0.0, 4.0, 0.0),
            "sphere_rad": 1.0,
            "sphere_rad_inv": 1.0,
        },
        {
            "ray_origin": (0.0, 0.0, 0.0),
            "ray_dir": normalize((0.5, 1.0, 0.0)),
            "sphere_center": (0.0, 3.0, 0.0),
            "sphere_rad": 0.5,
            "sphere_rad_inv": 2.0,
        },
        {
            "ray_origin": (0.0, 0.0, 0.0),
            "ray_dir": (0.0, 1.0, 0.0),
            "sphere_center": (2.0, 4.0, 0.0),
            "sphere_rad": 0.5,
            "sphere_rad_inv": 2.0,
        },
        {
            "ray_origin": (0.0, 0.0, 0.0),
            "ray_dir": normalize((0.25, 1.0, 0.25)),
            "sphere_center": (0.5, 4.5, 0.5),
            "sphere_rad": 2.0,
            "sphere_rad_inv": 0.5,
        },
    ]

    random_cases = []
    for _ in range(128):
        ray_dir = normalize((
            rng.uniform(-0.4, 0.4),
            1.0,
            rng.uniform(-0.4, 0.4),
        ))
        sphere_rad = rng.choice([0.5, 1.0, 2.0])
        random_cases.append({
            "ray_origin": (0.0, 0.0, 0.0),
            "ray_dir": ray_dir,
            "sphere_center": (
                rng.uniform(-1.5, 1.5),
                rng.uniform(2.0, 6.0),
                rng.uniform(-1.5, 1.5),
            ),
            "sphere_rad": sphere_rad,
            "sphere_rad_inv": 1.0 / sphere_rad,
        })
    cases = deterministic_cases + random_cases

    miss_case = {
        "ray_origin": (0.0, 0.0, 0.0),
        "ray_dir": (0.0, 1.0, 0.0),
        "sphere_center": (6.0, 3.0, 6.0),
        "sphere_rad": 0.5,
        "sphere_rad_inv": 2.0,
    }

    expected_queue: list[dict[str, object]] = []
    hit_count_nonlocal = [0]
    miss_count_nonlocal = [0]

    async def drive_case(case: dict[str, object]) -> None:
        dut.ray_origin.value = make_fp_vec3(case["ray_origin"])
        dut.ray_dir.value = make_fp_vec3(case["ray_dir"])
        dut.sphere_center.value = make_fp_vec3(case["sphere_center"])
        dut.sphere_rad_sq.value = make_fp(case["sphere_rad"] ** 2)
        dut.sphere_rad_inv.value = make_fp(case["sphere_rad_inv"])
        expected_queue.append(sphere_expected(case))
        await RisingEdge(dut.clk)
        if len(expected_queue) > SPHERE_DELAY:
            expected = expected_queue.pop(0)
            got_hit = bool(dut.hit.value.integer)
            assert got_hit == expected["hit"], f"hit mismatch for expected={expected}"
            if got_hit:
                hit_dist = convert_fp(dut.hit_dist.value.integer)
                hit_pos = convert_fp_vec3(dut.hit_pos.value.integer)
                hit_norm = convert_fp_vec3(dut.hit_norm.value.integer)
                scalar_close(hit_dist, expected["hit_dist"])
                vec_close(hit_pos, expected["hit_pos"])
                vec_close(hit_norm, expected["hit_norm"])
                hit_count_nonlocal[0] += 1
            else:
                miss_count_nonlocal[0] += 1

    for _ in range(SPHERE_DELAY):
        await drive_case(miss_case)

    for case in cases:
        await drive_case(case)

    for _ in range(SPHERE_DELAY):
        await drive_case(miss_case)

    seen_hits = hit_count_nonlocal[0]
    seen_misses = miss_count_nonlocal[0]
    assert seen_hits > 0, "expected at least one sphere hit"
    assert seen_misses > 0, "expected at least one sphere miss"


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
        proj_path / "hdl" / "math" / "fp_add_fast.sv",
        proj_path / "hdl" / "math" / "fp_mul.sv",
        proj_path / "hdl" / "math" / "fp_inv_sqrt.sv",
        proj_path / "hdl" / "math" / "fp_inv_sqrt_fast.sv",
        proj_path / "hdl" / "math" / "fp_sqrt.sv",
        proj_path / "hdl" / "math" / "fp_sqrt_fast.sv",
        proj_path / "hdl" / "math" / "fp_vec3_ops.sv",
        proj_path / "hdl" / "math" / "fp_vec3_add_fast.sv",
        proj_path / "hdl" / "math" / "fp_vec3_dot_fast.sv",
        proj_path / "hdl" / "math" / "quadratic_solver.sv",
        proj_path / "hdl" / "math" / "quadratic_solver_fast.sv",
        proj_path / "hdl" / "math" / "sphere_intersector.sv",
    ]
    hdl_toplevel = "sphere_intersector"
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
