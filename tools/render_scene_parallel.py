#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


REPO_ROOT = Path(__file__).resolve().parents[1]
TESTBENCH = REPO_ROOT / "sim" / "rtx" / "test_rtx_parallel.py"
IMAGES_ROOT = REPO_ROOT / "images"
METRICS_ROOT = REPO_ROOT / "metrics"
RENDER_DATA_ROOT = REPO_ROOT / "sim" / "sim_build" / "render_data"

SCENE_THRESHOLD_FLOORS = {
    "chicken": {
        "raw_rmse": 30.0,
        "blur_rmse": 6.5,
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", default="ctrl/scenes/canonical_balls.json")
    parser.add_argument("--scale", type=float, default=2.0)
    parser.add_argument("--frames", type=int, default=1)
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--chunks", type=int, default=None)
    parser.add_argument("--blur-radius", type=float, default=2.0)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=0x123456789ABCDEF123456789)
    parser.add_argument("--update-gold", action=argparse.BooleanOptionalAction, default=False)
    parser.add_argument("--enforce-gold", action=argparse.BooleanOptionalAction, default=True)
    return parser.parse_args()


def timestamp_dirname() -> str:
    return datetime.now().strftime("%Y-%m-%d-%H-%M-%S")


def _load_rgb(path: Path, *, blur_radius: float | None = None) -> Image.Image:
    img = Image.open(path).convert("RGB")
    if blur_radius:
        img = img.filter(ImageFilter.GaussianBlur(radius=blur_radius))
    return img


def image_size(path: Path) -> tuple[int, int]:
    with Image.open(path) as img:
        return img.size


def image_rmse(path_a: Path, path_b: Path, *, blur_radius: float | None = None) -> float:
    pil_a = _load_rgb(path_a, blur_radius=blur_radius)
    pil_b = _load_rgb(path_b, blur_radius=blur_radius)
    if pil_a.size != pil_b.size:
        common_size = (
            min(pil_a.size[0], pil_b.size[0]),
            min(pil_a.size[1], pil_b.size[1]),
        )
        pil_a = pil_a.resize(common_size, Image.Resampling.BILINEAR)
        pil_b = pil_b.resize(common_size, Image.Resampling.BILINEAR)
    img_a = np.asarray(pil_a, dtype=np.float64)
    img_b = np.asarray(pil_b, dtype=np.float64)
    return float(np.sqrt(np.mean((img_a - img_b) ** 2)))


def expected_correct_stats(paths: list[Path], *, blur_radius: float | None = None) -> dict[str, float] | None:
    if len(paths) < 2:
        return None
    vals = []
    for idx, path_a in enumerate(paths):
        for path_b in paths[idx + 1 :]:
            vals.append(image_rmse(path_a, path_b, blur_radius=blur_radius))
    return {
        "count": len(vals),
        "min": min(vals),
        "mean": sum(vals) / len(vals),
        "max": max(vals),
    }


def stats_vs_reference(path: Path, refs: list[Path], *, blur_radius: float | None = None) -> dict[str, object] | None:
    if not refs:
        return None
    vals = []
    best_ref = None
    best_val = None
    for ref in refs:
        val = image_rmse(path, ref, blur_radius=blur_radius)
        vals.append((ref, val))
        if best_val is None or val < best_val:
            best_ref = ref
            best_val = val
    only_vals = [val for _, val in vals]
    return {
        "count": len(vals),
        "min": min(only_vals),
        "mean": sum(only_vals) / len(only_vals),
        "max": max(only_vals),
        "closest_reference": best_ref.name if best_ref is not None else None,
    }


def compatible_gold_refs(refs: list[Path], *, required_size: tuple[int, int]) -> list[Path]:
    return [ref for ref in refs if image_size(ref) == required_size]


def main() -> int:
    args = parse_args()
    scene_path = (REPO_ROOT / args.json).resolve()
    if not scene_path.exists():
        raise FileNotFoundError(scene_path)

    scene_name = scene_path.stem
    threshold_floor = SCENE_THRESHOLD_FLOORS.get(scene_name, {})
    timestamp = timestamp_dirname()
    image_run_dir = IMAGES_ROOT / scene_name / timestamp
    metrics_run_dir = METRICS_ROOT / scene_name / timestamp
    gold_dir = IMAGES_ROOT / scene_name / "_gold"
    render_data_dir = RENDER_DATA_ROOT / scene_name / timestamp
    image_run_dir.mkdir(parents=True, exist_ok=False)
    metrics_run_dir.mkdir(parents=True, exist_ok=False)
    render_data_dir.mkdir(parents=True, exist_ok=False)
    gold_dir.mkdir(parents=True, exist_ok=True)
    width = int(32 * args.scale)
    height = int(18 * args.scale)

    summary: dict[str, object] = {
        "scene": scene_path.name,
        "timestamp": timestamp,
        "scale": args.scale,
        "frames": args.frames,
        "image_size": {
            "width": width,
            "height": height,
        },
        "repeats": args.repeats,
        "seed": f"0x{args.seed:024x}",
        "blur_radius": args.blur_radius,
        "diff_metric": "rmse_rgb_0_to_255_and_blur_rmse_rgb_0_to_255",
        "image_dir": str(image_run_dir.relative_to(REPO_ROOT)),
        "metrics_dir": str(metrics_run_dir.relative_to(REPO_ROOT)),
        "gold_dir": str(gold_dir.relative_to(REPO_ROOT)),
        "render_data_dir": str(render_data_dir.relative_to(REPO_ROOT)),
        "gold_reference_compatibility": {
            "required_size": {
                "width": width,
                "height": height,
            },
            "available_gold_count": 0,
            "compatible_gold_count": 0,
        },
        "runs": [],
        "raw_rmse_vs_run1": {},
        "blur_rmse_vs_run1": {},
        "expected_correct_value": {
            "raw_rmse": None,
            "blur_rmse": None,
        },
        "expected_correct_stats": {
            "raw_rmse": None,
            "blur_rmse": None,
        },
        "gold_reference_match": {
            "raw_rmse": None,
            "blur_rmse": None,
        },
        "passes_expected_correct_value": {
            "raw_rmse": None,
            "blur_rmse": None,
        },
    }

    for run_idx in range(1, args.repeats + 1):
        run_log = metrics_run_dir / f"run{run_idx}.log"
        output_prefix = metrics_run_dir / f"render_{scene_name}_{int(32 * args.scale)}x{int(18 * args.scale)}_f{args.frames}_run{run_idx}"
        cmd = [
            sys.executable,
            str(TESTBENCH),
            f"--scale={args.scale}",
            f"--frames={args.frames}",
            f"--seed=0x{args.seed:024x}",
            "--json",
            str(scene_path),
            "--data-dir",
            str(render_data_dir),
            "--output-prefix",
            str(output_prefix),
            "--no-waves",
        ]
        if args.chunks is not None:
            cmd.append(f"--chunks={args.chunks}")

        completed = subprocess.run(
            cmd,
            cwd=REPO_ROOT,
            stdout=run_log.open("w"),
            stderr=subprocess.STDOUT,
            check=False,
        )

        run_png = image_run_dir / f"run{run_idx}.png"
        run_metrics = metrics_run_dir / f"run{run_idx}.metrics.json"
        output_png = output_prefix.with_suffix(".png")
        output_metrics = output_prefix.with_suffix(".metrics.json")

        if output_png.exists():
            shutil.move(output_png, run_png)
        if output_metrics.exists():
            shutil.move(output_metrics, run_metrics)

        run_record: dict[str, object] = {
            "run": run_idx,
            "exit_code": completed.returncode,
            "log": run_log.name,
            "png": run_png.name if run_png.exists() else None,
            "metrics_json": run_metrics.name if run_metrics.exists() else None,
        }
        if run_metrics.exists():
            run_record["metrics"] = json.loads(run_metrics.read_text())
        summary["runs"].append(run_record)

        if completed.returncode != 0:
            (metrics_run_dir / "summary.json").write_text(json.dumps(summary, indent=2))
            return completed.returncode

        if run_png.exists() and args.update_gold:
            shutil.copy2(run_png, gold_dir / f"{timestamp}-run{run_idx}.png")

    reference_png = image_run_dir / "run1.png"
    if reference_png.exists():
        for run_idx in range(2, args.repeats + 1):
            run_png = image_run_dir / f"run{run_idx}.png"
            if run_png.exists():
                summary["raw_rmse_vs_run1"][f"run{run_idx}"] = image_rmse(reference_png, run_png)
                summary["blur_rmse_vs_run1"][f"run{run_idx}"] = image_rmse(
                    reference_png,
                    run_png,
                    blur_radius=args.blur_radius,
                )

    gold_pngs = sorted(gold_dir.glob("*.png"))
    if args.enforce_gold and not gold_pngs:
        raise FileNotFoundError(f"no gold references found for scene {scene_name}: {gold_dir}")
    compatible_gold_pngs = compatible_gold_refs(gold_pngs, required_size=(width, height))
    summary["gold_reference_compatibility"]["available_gold_count"] = len(gold_pngs)
    summary["gold_reference_compatibility"]["compatible_gold_count"] = len(compatible_gold_pngs)

    raw_stats = expected_correct_stats(compatible_gold_pngs)
    blur_stats = expected_correct_stats(compatible_gold_pngs, blur_radius=args.blur_radius)
    summary["expected_correct_stats"]["raw_rmse"] = raw_stats
    summary["expected_correct_stats"]["blur_rmse"] = blur_stats
    summary["expected_correct_value"]["raw_rmse"] = None if raw_stats is None else raw_stats["max"]
    summary["expected_correct_value"]["blur_rmse"] = None if blur_stats is None else blur_stats["max"]
    if raw_stats is not None and "raw_rmse" in threshold_floor:
        summary["expected_correct_value"]["raw_rmse"] = max(
            threshold_floor["raw_rmse"],
            0.0 if summary["expected_correct_value"]["raw_rmse"] is None else summary["expected_correct_value"]["raw_rmse"],
        )
    if blur_stats is not None and "blur_rmse" in threshold_floor:
        summary["expected_correct_value"]["blur_rmse"] = max(
            threshold_floor["blur_rmse"],
            0.0 if summary["expected_correct_value"]["blur_rmse"] is None else summary["expected_correct_value"]["blur_rmse"],
        )

    if reference_png.exists():
        summary["gold_reference_match"]["raw_rmse"] = stats_vs_reference(reference_png, compatible_gold_pngs)
        summary["gold_reference_match"]["blur_rmse"] = stats_vs_reference(
            reference_png,
            compatible_gold_pngs,
            blur_radius=args.blur_radius,
        )

    raw_expected = summary["expected_correct_value"]["raw_rmse"]
    blur_expected = summary["expected_correct_value"]["blur_rmse"]
    raw_match = summary["gold_reference_match"]["raw_rmse"]
    blur_match = summary["gold_reference_match"]["blur_rmse"]
    summary["passes_expected_correct_value"]["raw_rmse"] = (
        None if raw_expected is None or raw_match is None else raw_match["min"] <= raw_expected
    )
    summary["passes_expected_correct_value"]["blur_rmse"] = (
        None if blur_expected is None or blur_match is None else blur_match["min"] <= blur_expected
    )

    (metrics_run_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    print(image_run_dir)
    print(json.dumps(summary, indent=2, sort_keys=True))

    if args.enforce_gold:
        for metric_name, passed in summary["passes_expected_correct_value"].items():
            if passed is False:
                print(f"gold RMSE check failed for {metric_name}", file=sys.stderr)
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
