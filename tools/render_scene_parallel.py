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
from PIL import Image


REPO_ROOT = Path(__file__).resolve().parents[1]
TESTBENCH = REPO_ROOT / "sim" / "rtx" / "test_rtx_parallel.py"
IMAGES_ROOT = REPO_ROOT / "images"
METRICS_ROOT = REPO_ROOT / "metrics"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", required=True)
    parser.add_argument("--scale", type=float, default=2.0)
    parser.add_argument("--frames", type=int, default=1)
    parser.add_argument("--repeats", type=int, default=1)
    parser.add_argument("--chunks", type=int, default=None)
    return parser.parse_args()


def timestamp_dirname() -> str:
    return datetime.now().strftime("%Y-%m-%d-%H-%M-%S")


def image_rmse(path_a: Path, path_b: Path) -> float:
    pil_a = Image.open(path_a).convert("RGB")
    pil_b = Image.open(path_b).convert("RGB")
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


def main() -> int:
    args = parse_args()
    scene_path = (REPO_ROOT / args.json).resolve()
    if not scene_path.exists():
        raise FileNotFoundError(scene_path)

    scene_name = scene_path.stem
    timestamp = timestamp_dirname()
    image_run_dir = IMAGES_ROOT / scene_name / timestamp
    metrics_run_dir = METRICS_ROOT / scene_name / timestamp
    image_run_dir.mkdir(parents=True, exist_ok=False)
    metrics_run_dir.mkdir(parents=True, exist_ok=False)
    shutil.copy2(scene_path, metrics_run_dir / scene_path.name)

    width = int(32 * args.scale)
    height = int(18 * args.scale)
    root_png = REPO_ROOT / f"test_rtx_{width}x{height}_f{args.frames}.png"
    root_metrics = root_png.with_suffix(".metrics.json")

    summary: dict[str, object] = {
        "scene": scene_path.name,
        "timestamp": timestamp,
        "scale": args.scale,
        "frames": args.frames,
        "repeats": args.repeats,
        "diff_metric": "rmse_rgb_0_to_255",
        "image_dir": str(image_run_dir.relative_to(REPO_ROOT)),
        "metrics_dir": str(metrics_run_dir.relative_to(REPO_ROOT)),
        "runs": [],
        "rmse_vs_run1": {},
    }

    for run_idx in range(1, args.repeats + 1):
        for stale_path in (root_png, root_metrics):
            if stale_path.exists():
                stale_path.unlink()

        run_log = metrics_run_dir / f"run{run_idx}.log"
        cmd = [
            sys.executable,
            str(TESTBENCH),
            f"--scale={args.scale}",
            f"--frames={args.frames}",
            "--json",
            str(scene_path),
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

        if root_png.exists():
            shutil.move(root_png, run_png)
        if root_metrics.exists():
            shutil.move(root_metrics, run_metrics)

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

    reference_png = image_run_dir / "run1.png"
    if reference_png.exists():
        for run_idx in range(2, args.repeats + 1):
            run_png = image_run_dir / f"run{run_idx}.png"
            if run_png.exists():
                summary["rmse_vs_run1"][f"run{run_idx}"] = image_rmse(reference_png, run_png)

    (metrics_run_dir / "summary.json").write_text(json.dumps(summary, indent=2))
    print(image_run_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
