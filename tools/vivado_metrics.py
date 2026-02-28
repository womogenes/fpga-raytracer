#!/usr/bin/env python3

from __future__ import annotations

import json
import re
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path


VIVADO_COMPOSE_DIR = Path.home() / "code" / "vivado"
CONTAINER_NAME = "vivado"
CONTAINER_VIVADO_CANDIDATES = (
    "/tools/Xilinx/2025.1/Vivado/bin/vivado",
    "/opt/Xilinx/2025.1/Vivado/bin/vivado",
)
LD_PRELOAD = "/lib/x86_64-linux-gnu/libudev.so.1"
CONTAINER_LOCALE = "C.utf8"


@dataclass
class VivadoMetrics:
    slice_luts: int
    wns_ns: float
    tns_ns: float
    timing_met: bool
    post_route_util_report: str
    post_route_timing_summary_report: str
    vivado_log: str


def _repo_paths() -> tuple[Path, Path]:
    repo_root = Path(__file__).resolve().parents[1]
    code_root = Path.home() / "code"
    try:
        repo_suffix = repo_root.relative_to(code_root)
    except ValueError as exc:
        raise RuntimeError(f"{repo_root} is not under {code_root}") from exc
    container_project_dir = Path("/root/code") / repo_suffix
    return repo_root, container_project_dir


def _run(cmd: list[str], *, cwd: Path | None = None) -> None:
    subprocess.run(cmd, cwd=cwd, check=True)


def _find_container_vivado() -> str:
    for candidate in CONTAINER_VIVADO_CANDIDATES:
        probe = subprocess.run(
            [
                "docker",
                "exec",
                CONTAINER_NAME,
                "bash",
                "-lc",
                f"test -x {candidate}",
            ],
            check=False,
        )
        if probe.returncode == 0:
            return candidate
    checked = ", ".join(CONTAINER_VIVADO_CANDIDATES)
    raise RuntimeError(f"Could not find Vivado in container {CONTAINER_NAME}; checked {checked}")


def _parse_post_route_util(path: Path) -> int:
    lut_re = re.compile(r"^\|\s*Slice LUTs\s*\|\s*([0-9]+)\s*\|")
    for line in path.read_text().splitlines():
        match = lut_re.match(line)
        if match:
            return int(match.group(1))
    raise RuntimeError(f"Could not find Slice LUTs in {path}")


def _parse_post_route_timing_summary(path: Path) -> tuple[float, float, bool]:
    lines = path.read_text().splitlines()
    for idx, line in enumerate(lines):
        if "WNS(ns)" not in line or "TNS(ns)" not in line:
            continue
        for candidate in lines[idx + 1 : idx + 4]:
            stripped = candidate.strip()
            if not stripped or stripped.startswith("-"):
                continue
            fields = stripped.split()
            if len(fields) < 2:
                continue
            wns_ns = float(fields[0])
            tns_ns = float(fields[1])
            timing_met = "All user specified timing constraints are met." in "\n".join(
                lines[idx : idx + 12]
            )
            return wns_ns, tns_ns, timing_met
    raise RuntimeError(f"Could not find timing summary values in {path}")


def _parse_log_fallback(log_path: Path) -> tuple[int, float, float]:
    log_text = log_path.read_text()

    lut_match = re.search(r"^\|\s*Slice LUTs\s*\|\s*([0-9]+)\s*\|", log_text, re.MULTILINE)
    timing_match = re.search(
        r"^\s*(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+[0-9]+\s+[0-9]+",
        log_text,
        re.MULTILINE,
    )
    if not lut_match or not timing_match:
        raise RuntimeError(f"Could not parse fallback metrics from {log_path}")
    return int(lut_match.group(1)), float(timing_match.group(1)), float(timing_match.group(2))


def compute_vivado_metrics() -> VivadoMetrics:
    repo_root, container_project_dir = _repo_paths()
    output_dir = repo_root / "obj_rtx"
    output_dir.mkdir(exist_ok=True)

    post_route_util = output_dir / "post_route_util.rpt"
    post_route_timing = output_dir / "post_route_timing_summary.rpt"
    vivado_log = output_dir / "vivado.log"

    for stale_path in (post_route_util, post_route_timing, vivado_log, output_dir / "final.bit"):
        if stale_path.exists():
            stale_path.unlink()

    _run(["docker", "compose", "up", "-d"], cwd=VIVADO_COMPOSE_DIR)
    container_vivado = _find_container_vivado()

    batch_cmd = (
        f"cd {container_project_dir} && "
        f"export LANG={CONTAINER_LOCALE} LC_ALL={CONTAINER_LOCALE} && "
        f"export LD_PRELOAD={LD_PRELOAD} && "
        f"{container_vivado} -mode batch -source tcl/build_rtx.tcl -nojournal -log obj_rtx/vivado.log"
    )
    _run(["docker", "exec", CONTAINER_NAME, "bash", "-lc", batch_cmd])

    if post_route_util.exists() and post_route_timing.exists():
        slice_luts = _parse_post_route_util(post_route_util)
        wns_ns, tns_ns, timing_met = _parse_post_route_timing_summary(post_route_timing)
    elif vivado_log.exists():
        slice_luts, wns_ns, tns_ns = _parse_log_fallback(vivado_log)
        timing_met = "All user specified timing constraints are met." in vivado_log.read_text()
    else:
        raise RuntimeError("Vivado run completed without post-route reports or vivado.log")

    return VivadoMetrics(
        slice_luts=slice_luts,
        wns_ns=wns_ns,
        tns_ns=tns_ns,
        timing_met=timing_met,
        post_route_util_report=str(post_route_util),
        post_route_timing_summary_report=str(post_route_timing),
        vivado_log=str(vivado_log),
    )


if __name__ == "__main__":
    print(json.dumps(asdict(compute_vivado_metrics()), indent=2, sort_keys=True))
