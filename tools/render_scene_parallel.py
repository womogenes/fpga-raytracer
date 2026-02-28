#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
TESTBENCH = ROOT / "sim" / "rtx" / "test_rtx_parallel.py"
REF_ROOT = ROOT / "tools" / "ref" / "s2f4"
MANIFEST = json.loads((REF_ROOT / "manifest.json").read_text())
SCENES = {scene["name"]: scene for scene in MANIFEST["scenes"]}


def rmse(path_a: Path, path_b: Path, blur_radius: float | None = None) -> float:
    """
    Compute root mean-squared error between two image PNGs.
    Optionally use blur RMSE which downsamples before comparing.
    """
    img_a = Image.open(path_a).convert("RGB")
    img_b = Image.open(path_b).convert("RGB")
    if blur_radius:
        img_a = img_a.filter(ImageFilter.GaussianBlur(radius=blur_radius))
        img_b = img_b.filter(ImageFilter.GaussianBlur(radius=blur_radius))
    arr_a = np.asarray(img_a, dtype=np.float64)
    arr_b = np.asarray(img_b, dtype=np.float64)
    return float(np.sqrt(np.mean((arr_a - arr_b) ** 2)))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("scene", nargs="?", default="canonical_balls")
    parser.add_argument("--chunks", type=int)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=0x123456789ABCDEF123456789)
    args = parser.parse_args()

    if args.scene not in SCENES:
        raise KeyError(f"unknown scene: {args.scene}")

    scene_cfg = SCENES[args.scene]
    scene_json = ROOT / "ctrl" / "scenes" / f"{args.scene}.json"
    ref_png = REF_ROOT / f"{args.scene}.png"
    if not scene_json.exists():
        raise FileNotFoundError(scene_json)
    if not ref_png.exists():
        raise FileNotFoundError(ref_png)

    stamp = datetime.now().strftime("%Y-%m-%d-%H-%M-%S")
    out_dir = ROOT / "metrics" / args.scene / stamp
    data_dir = ROOT / "sim" / "sim_build" / "render_data" / args.scene / stamp
    out_dir.mkdir(parents=True, exist_ok=False)
    data_dir.mkdir(parents=True, exist_ok=False)
    out_prefix = out_dir / "render"

    cmd = [
        sys.executable,
        str(TESTBENCH),
        f"--scale={MANIFEST['scale']}",
        f"--frames={MANIFEST['frames']}",
        f"--seed=0x{args.seed:024x}",
        "--json",
        str(scene_json),
        "--data-dir",
        str(data_dir),
        "--output-prefix",
        str(out_prefix),
        "--no-waves",
    ]
    if args.chunks is not None:
        cmd.append(f"--chunks={args.chunks}")

    start = time.perf_counter()
    with (out_dir / "run.log").open("w") as log:
        rc = subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=False).returncode
    elapsed = time.perf_counter() - start

    if rc != 0:
        print("status: FAILED")
        print(f"scene: {args.scene}")
        print(f"raw rmse: n/a (thresh {scene_cfg['raw_rmse']:.1f})")
        print(f"blur rmse: n/a (thresh {scene_cfg['blur_rmse']:.1f})")
        print(f"time: {elapsed:.1f}s")
        return rc

    png = out_prefix.with_suffix(".png")
    raw = rmse(png, ref_png)
    blur = rmse(png, ref_png, blur_radius=MANIFEST["blur_radius"])
    passed = raw <= scene_cfg["raw_rmse"] and blur <= scene_cfg["blur_rmse"]

    print(f"status: {'PASSED' if passed else 'FAILED'}")
    print(f"scene: {args.scene}")
    print(f"raw rmse: {raw:.1f} (thresh {scene_cfg['raw_rmse']:.1f})")
    print(f"blur rmse: {blur:.1f} (thresh {scene_cfg['blur_rmse']:.1f})")
    print(f"time: {elapsed:.1f}s")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
