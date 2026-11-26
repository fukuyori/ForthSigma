#!/usr/bin/env python3
"""Measure submit stages with a headless public T1 workload."""
import argparse
import json
import os
import runpy
import statistics
import subprocess
import tempfile
from pathlib import Path


parser = argparse.ArgumentParser()
parser.add_argument("binary", type=Path, help="task-acceptance sigma executable")
parser.add_argument("--turns", type=int, default=50)
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="forthsigma-submit-") as tmp:
    root = Path(__file__).resolve().parents[2]
    paths = runpy.run_path(str(Path(__file__).with_name("acceptance-fixtures.py")))["generate"](root, Path(tmp), 1)
    # Repeat submissions with no pacing or key input; keep one stable snapshot.
    path = paths["T1"]
    text = path.read_text()
    text = text.replace('1 0 DO AS @', f'{args.turns} 0 DO AS @')
    path.write_text(text)
    env = os.environ.copy()
    env["SIGMA_ACCEPTANCE_SMOKE"] = "0"
    run = subprocess.run([str(args.binary.resolve()), str(paths["T1"])], cwd=root, env=env,
                         text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if run.returncode:
        raise SystemExit(run.stdout)
    samples = {}
    for line in run.stdout.splitlines():
        if not line.startswith("ACCEPTANCE {"):
            continue
        try:
            event = json.loads(line[len("ACCEPTANCE "):])
        except json.JSONDecodeError:
            continue
        metric = event.get("metric", "")
        if metric.startswith("submit_") and "start" in event:
            samples.setdefault(metric, []).append(event["end"] - event["start"])
    expected = args.turns
    for metric, values in sorted(samples.items()):
        if len(values) != expected:
            print(f"{metric}: n={len(values)} (expected {expected})")
            continue
        first, later = values[:1], values[1:]
        print(f"{metric} first: n={len(first)} median_ns={statistics.median(first):.0f} max_ns={max(first)}")
        if later:
            print(f"{metric} later: n={len(later)} median_ns={statistics.median(later):.0f} max_ns={max(later)}")
