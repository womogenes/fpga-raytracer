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

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ctrl"))
from make_scene_buffer import Object

SPHERE_DELAY = 20
RAY_INTERSECTOR_OVERHEAD = 2


def scalar_close(actual: float, expected: float, *, tol: float = 0.05) -> None:
    abs_err = abs(actual - expected)
    rel_err = 0.0 if expected == 0 else abs_err / abs(expected)
    assert abs_err <= tol or rel_err <= 0.03, (
        f"expected={expected} actual={actual} abs_err={abs_err} rel_err={rel_err}"
    )


async def scene_buffer_driver(dut, objs: list[Object]) -> None:
    while True:
        for obj in objs:
            dut.obj.value = obj.pack_bits()[0]
            await RisingEdge(dut.clk)


async def launch_ray(dut, ray_origin: tuple[float, float, float], ray_dir: tuple[float, float, float]) -> int:
    dut.ray_origin.value = make_fp_vec3(ray_origin)
    dut.ray_dir.value = make_fp_vec3(ray_dir)
    dut.ray_valid.value = 1
    await RisingEdge(dut.clk)
    dut.ray_valid.value = 0
    cycles = 1
    while True:
        await RisingEdge(dut.clk)
        cycles += 1
        if dut.hit_valid.value.integer:
            return cycles


@cocotb.test()
async def test_module(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst.value = 1
    dut.ray_valid.value = 0
    dut.obj.value = 0
    dut.num_objs.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst.value = 0

    sphere_scene = [
        Object(mat_idx=7, sphere_center=(0.0, 4.0, 0.0), sphere_rad=1.0, obj_type=0),
    ]
    dut.num_objs.value = len(sphere_scene)
    sphere_task = cocotb.start_soon(scene_buffer_driver(dut, sphere_scene))
    await ClockCycles(dut.clk, 3)
    cycles = await launch_ray(dut, (0.0, 0.0, 0.0), (0.0, 1.0, 0.0))
    assert cycles == SPHERE_DELAY + len(sphere_scene) + RAY_INTERSECTOR_OVERHEAD, (
        f"unexpected sphere latency: {cycles}"
    )
    assert dut.hit_any.value.integer == 1
    assert dut.hit_mat_idx.value.integer == 7
    scalar_close(convert_fp(dut.hit_dist.value.integer), 3.0)
    sphere_task.kill()

    triangle = Object(
        mat_idx=11,
        obj_type=1,
        trig=((-1.0, 5.0, -1.0), (2.0, 0.0, 0.0), (0.0, 0.0, 2.0)),
        trig_norm=(0.0, -1.0, 0.0),
    )
    miss_sphere = Object(mat_idx=9, sphere_center=(3.0, 4.0, 0.0), sphere_rad=0.5, obj_type=0)
    mixed_scene = [miss_sphere, triangle]
    dut.num_objs.value = len(mixed_scene)
    mixed_task = cocotb.start_soon(scene_buffer_driver(dut, mixed_scene))
    await ClockCycles(dut.clk, 3)
    cycles = await launch_ray(dut, (0.0, 0.0, 0.0), (0.0, 1.0, 0.0))
    assert cycles == SPHERE_DELAY + len(mixed_scene) + RAY_INTERSECTOR_OVERHEAD, (
        f"unexpected mixed latency: {cycles}"
    )
    assert dut.hit_any.value.integer == 1
    assert dut.hit_mat_idx.value.integer == 11
    scalar_close(convert_fp(dut.hit_dist.value.integer), 5.0, tol=0.08)
    mixed_task.kill()

    reordered_scene = [triangle, miss_sphere]
    dut.num_objs.value = len(reordered_scene)
    reordered_task = cocotb.start_soon(scene_buffer_driver(dut, reordered_scene))
    await ClockCycles(dut.clk, 3)
    cycles = await launch_ray(dut, (0.0, 0.0, 0.0), (0.0, 1.0, 0.0))
    assert cycles == SPHERE_DELAY + len(reordered_scene) + RAY_INTERSECTOR_OVERHEAD, (
        f"unexpected reordered latency: {cycles}"
    )
    assert dut.hit_any.value.integer == 1
    assert dut.hit_mat_idx.value.integer == 11
    scalar_close(convert_fp(dut.hit_dist.value.integer), 5.0, tol=0.08)
    hit_pos = convert_fp_vec3(dut.hit_pos.value.integer)
    assert math.isfinite(hit_pos[0]) and math.isfinite(hit_pos[1]) and math.isfinite(hit_pos[2])
    reordered_task.kill()


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
        proj_path / "hdl" / "math" / "fp_inv.sv",
        proj_path / "hdl" / "math" / "fp_sqrt.sv",
        proj_path / "hdl" / "math" / "fp_sqrt_fast.sv",
        proj_path / "hdl" / "math" / "fp_vec3_ops.sv",
        proj_path / "hdl" / "math" / "fp_vec3_add_fast.sv",
        proj_path / "hdl" / "math" / "fp_vec3_dot_fast.sv",
        proj_path / "hdl" / "math" / "quadratic_solver.sv",
        proj_path / "hdl" / "math" / "quadratic_solver_fast.sv",
        proj_path / "hdl" / "math" / "sphere_intersector.sv",
        proj_path / "hdl" / "math" / "trig_intersector.sv",
        proj_path / "hdl" / "rtx" / "ray_intersector.sv",
    ]
    hdl_toplevel = "ray_intersector"
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
