import glob
import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, RisingEdge, ReadOnly

import numpy as np

sys.path.append(str(Path(__file__).resolve().parent))
sys.path.append(str(Path(__file__).resolve().parent.parent))
sys.path.append(str(Path(__file__).resolve().parent.parent.parent / "ctrl"))
from utils import convert_fp_vec3, make_fp_vec3
from make_scene_buffer import Material


REFLECT_DELAY = 37
TEST_MATERIALS = [
    Material(
        color=(0.5, 0.25, 0.75),
        emit_color=(0.1, 0.2, 0.3),
        spec_color=(0.9, 0.8, 0.7),
        smoothness=1.0,
        specular_prob=0.0,
    ),
    Material(
        color=(0.2, 0.4, 0.6),
        emit_color=(0.05, 0.15, 0.25),
        spec_color=(0.8, 0.6, 0.4),
        smoothness=1.0,
        specular_prob=1.0,
    ),
    Material(
        color=(0.7, 0.6, 0.5),
        emit_color=(0.0, 0.0, 0.0),
        spec_color=(0.3, 0.2, 0.9),
        smoothness=0.5,
        specular_prob=1.0,
    ),
    Material(
        color=(0.4, 0.3, 0.2),
        emit_color=(0.2, 0.05, 0.1),
        spec_color=(0.6, 0.4, 0.9),
        smoothness=1.0,
        specular_prob=1.0,
    ),
]

test_file = os.path.basename(__file__).replace(".py", "")


def normalize(vec):
    arr = np.asarray(vec, dtype=float)
    norm = np.linalg.norm(arr)
    assert norm > 1e-9
    return arr / norm


def signal_is_high(signal) -> bool:
    value = signal.value
    return bool(value.is_resolvable and value.integer)


def assert_vec_close(actual, expected, tol=0.03):
    for got, want in zip(actual, expected):
        assert abs(got - want) < tol, f"expected {expected}, got {actual}"


def specular_reflect(in_dir, normal):
    in_dir = np.asarray(in_dir, dtype=float)
    normal = np.asarray(normal, dtype=float)
    return tuple(in_dir - 2.0 * np.dot(in_dir, normal) * normal)


async def launch_case(dut, *, ray_dir, ray_color, income_light, hit_pos, hit_normal, hit_mat_idx):
    dut.ray_dir.value = make_fp_vec3(tuple(ray_dir))
    dut.ray_color.value = make_fp_vec3(tuple(ray_color))
    dut.income_light.value = make_fp_vec3(tuple(income_light))
    dut.hit_pos.value = make_fp_vec3(tuple(hit_pos))
    dut.hit_normal.value = make_fp_vec3(tuple(hit_normal))
    dut.hit_mat_idx.value = hit_mat_idx
    await ClockCycles(dut.clk, 2)
    dut.hit_valid.value = 1
    await ClockCycles(dut.clk, 1)
    dut.hit_valid.value = 0


async def wait_for_done(dut, expected_cycles):
    for cycle in range(1, expected_cycles + 1):
        await ClockCycles(dut.clk, 1)
        if cycle < expected_cycles:
            assert not signal_is_high(dut.reflect_done), f"reflect_done rose early at cycle {cycle}"
    assert signal_is_high(dut.reflect_done), f"reflect_done did not rise at cycle {expected_cycles}"


def reflect_outputs(dut):
    return {
        "new_dir": convert_fp_vec3(dut.new_dir.value),
        "new_origin": convert_fp_vec3(dut.new_origin.value),
        "new_color": convert_fp_vec3(dut.new_color.value),
        "new_income_light": convert_fp_vec3(dut.new_income_light.value),
    }


def assert_outputs_close(actual, expected, tol=0.03):
    for key, want in expected.items():
        assert_vec_close(actual[key], want, tol=tol)


def specular_expected(*, material, ray_dir, ray_color, income_light, hit_pos, hit_normal):
    hit_pos = np.asarray(hit_pos, dtype=float)
    hit_normal = np.asarray(hit_normal, dtype=float)
    ray_color = np.asarray(ray_color, dtype=float)
    income_light = np.asarray(income_light, dtype=float)
    return {
        "new_dir": specular_reflect(ray_dir, hit_normal),
        "new_origin": tuple(hit_pos + (2 ** -17) * hit_normal),
        "new_color": tuple(ray_color * np.asarray(material.spec_color, dtype=float)),
        "new_income_light": tuple(
            income_light + ray_color * np.asarray(material.emit_color, dtype=float)
        ),
    }


@cocotb.test()
async def test_module(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst.value = 1
    dut.hit_valid.value = 0
    dut.ray_dir.value = 0
    dut.ray_color.value = 0
    dut.income_light.value = 0
    dut.hit_pos.value = 0
    dut.hit_normal.value = 0
    dut.hit_mat_idx.value = 0
    dut.lfsr_seed.value = int("0123456789abcdef01234567", 16)
    await ClockCycles(dut.clk, 10)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    ray_color = (0.75, 0.5, 0.25)
    income_light = (0.1, 0.2, 0.3)
    hit_pos = (1.0, -2.0, 3.0)
    hit_normal = normalize((0.0, 0.0, 1.0))

    await launch_case(
        dut,
        ray_dir=normalize((1.0, -0.25, -1.0)),
        ray_color=ray_color,
        income_light=income_light,
        hit_pos=hit_pos,
        hit_normal=hit_normal,
        hit_mat_idx=0,
    )
    await wait_for_done(dut, REFLECT_DELAY)
    assert dut.mat_dict_idx.value.integer == 0
    assert_vec_close(convert_fp_vec3(dut.new_color.value), (0.375, 0.125, 0.1875))
    assert_vec_close(convert_fp_vec3(dut.new_income_light.value), (0.175, 0.3, 0.375))
    await ClockCycles(dut.clk, 2)

    in_dir = normalize((1.0, -1.0, -0.5))
    normal = normalize((0.0, 0.0, 1.0))
    ray_color = (0.9, 0.4, 0.2)
    income_light = (0.0, 0.25, 0.5)

    await launch_case(
        dut,
        ray_dir=in_dir,
        ray_color=ray_color,
        income_light=income_light,
        hit_pos=(0.0, 1.0, 2.0),
        hit_normal=normal,
        hit_mat_idx=1,
    )
    await wait_for_done(dut, REFLECT_DELAY)
    assert dut.mat_dict_idx.value.integer == 1
    assert_vec_close(convert_fp_vec3(dut.new_color.value), (0.72, 0.24, 0.08))
    assert_vec_close(convert_fp_vec3(dut.new_income_light.value), (0.045, 0.31, 0.55))
    await ClockCycles(dut.clk, 2)

    ray_color = (0.6, 0.7, 0.8)
    income_light = (0.3, 0.2, 0.1)

    await launch_case(
        dut,
        ray_dir=normalize((-0.5, 1.0, -0.2)),
        ray_color=ray_color,
        income_light=income_light,
        hit_pos=(2.0, -1.0, 0.5),
        hit_normal=normalize((0.1, 0.2, 1.0)),
        hit_mat_idx=2,
    )
    await wait_for_done(dut, REFLECT_DELAY)
    await ClockCycles(dut.clk, 2)


@cocotb.test()
async def test_back_to_back_fixed_latency(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.rst.value = 1
    dut.hit_valid.value = 0
    dut.ray_dir.value = 0
    dut.ray_color.value = 0
    dut.income_light.value = 0
    dut.hit_pos.value = 0
    dut.hit_normal.value = 0
    dut.hit_mat_idx.value = 0
    dut.lfsr_seed.value = int("0123456789abcdef01234567", 16)
    await ClockCycles(dut.clk, 10)
    dut.rst.value = 0
    await ClockCycles(dut.clk, 2)

    case0 = {
        "ray_dir": normalize((1.0, -1.0, -0.5)),
        "ray_color": (0.9, 0.4, 0.2),
        "income_light": (0.0, 0.25, 0.5),
        "hit_pos": (0.0, 1.0, 2.0),
        "hit_normal": normalize((0.0, 0.0, 1.0)),
        "hit_mat_idx": 1,
    }
    case1 = {
        "ray_dir": normalize((-0.2, 0.5, -1.0)),
        "ray_color": (0.6, 0.8, 0.3),
        "income_light": (0.15, 0.05, 0.4),
        "hit_pos": (-1.0, 0.5, 1.5),
        "hit_normal": normalize((0.0, 1.0, 1.0)),
        "hit_mat_idx": 3,
    }

    expected0 = specular_expected(
        material=TEST_MATERIALS[1],
        ray_dir=case0["ray_dir"],
        ray_color=case0["ray_color"],
        income_light=case0["income_light"],
        hit_pos=case0["hit_pos"],
        hit_normal=case0["hit_normal"],
    )
    expected1 = specular_expected(
        material=TEST_MATERIALS[3],
        ray_dir=case1["ray_dir"],
        ray_color=case1["ray_color"],
        income_light=case1["income_light"],
        hit_pos=case1["hit_pos"],
        hit_normal=case1["hit_normal"],
    )

    dut.ray_dir.value = make_fp_vec3(case0["ray_dir"])
    dut.ray_color.value = make_fp_vec3(case0["ray_color"])
    dut.income_light.value = make_fp_vec3(case0["income_light"])
    dut.hit_pos.value = make_fp_vec3(case0["hit_pos"])
    dut.hit_normal.value = make_fp_vec3(case0["hit_normal"])
    dut.hit_mat_idx.value = case0["hit_mat_idx"]
    dut.hit_valid.value = 1
    await ClockCycles(dut.clk, 1)

    dut.ray_dir.value = make_fp_vec3(case1["ray_dir"])
    dut.ray_color.value = make_fp_vec3(case1["ray_color"])
    dut.income_light.value = make_fp_vec3(case1["income_light"])
    dut.hit_pos.value = make_fp_vec3(case1["hit_pos"])
    dut.hit_normal.value = make_fp_vec3(case1["hit_normal"])
    dut.hit_mat_idx.value = case1["hit_mat_idx"]
    await ClockCycles(dut.clk, 1)

    dut.hit_valid.value = 0
    await RisingEdge(dut.reflect_done)
    await ReadOnly()
    assert_outputs_close(reflect_outputs(dut), expected0)

    await ClockCycles(dut.clk, 1)
    assert signal_is_high(dut.reflect_done)
    await ReadOnly()
    assert_outputs_close(reflect_outputs(dut), expected1)


def runner():
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent.parent
    build_dir = proj_path / "sim" / "sim_build"
    build_data_dir = build_dir / "data"
    build_data_dir.mkdir(parents=True, exist_ok=True)
    mat_lines = []
    for material in TEST_MATERIALS:
        bits, width = material.pack_bits()
        mat_lines.append(hex(bits)[2:].zfill((width + 3) // 4))
    (build_data_dir / "test_ray_reflector_mat_dict.mem").write_text("\n".join(mat_lines) + "\n")
    sys.path.insert(0, str(proj_path))
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "constants.sv",
        proj_path / "hdl" / "types" / "types.sv",
        proj_path / "hdl" / "pipeline.sv",
        proj_path / "hdl" / "mem" / "xilinx_true_dual_port_read_first_2_clock_ram.v",
        *glob.glob(f"{proj_path}/hdl/rng/*.sv", recursive=True),
        *glob.glob(f"{proj_path}/hdl/math/*.sv", recursive=True),
        proj_path / "hdl" / "rtx" / "material_dictionary.sv",
        proj_path / "hdl" / "rtx" / "ray_reflector.sv",
        proj_path / "sim" / "rtx" / "ray_reflector_tb.sv",
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
        hdl_toplevel="ray_reflector_tb",
        always=True,
        build_args=build_test_args,
        parameters={},
        timescale=("1ns", "1ps"),
        waves=True,
        build_dir=build_dir,
    )
    runner.test(
        hdl_toplevel="ray_reflector_tb",
        test_module=".".join(Path(__file__).resolve().with_suffix("").relative_to(proj_path).parts),
        test_args=[],
        waves=True,
    )


if __name__ == "__main__":
    runner()
