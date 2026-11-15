#!/usr/bin/env python3
"""P01a recorded cases and boundary matrices; optionally compare with local Gforth."""
import argparse
import csv
import json
import pathlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("sigma", nargs="?", default="zig-out/bin/sigma")
parser.add_argument("--gforth-build", type=pathlib.Path)
parser.add_argument("--report", type=pathlib.Path)
args = parser.parse_args()
names = ["0<=", "D0<=", "D0<>", "D0>", "D0>=", "D<=", "D<>", "D>", "D>=", "DU<=", "DU>", "DU>=", "U<=", "U>=", "UMAX", "UMIN"]
cases = []
with pathlib.Path("docs/gforth-p00-runtime-cases.tsv").open() as handle:
    for row in csv.DictReader(handle, delimiter="\t"):
        if row["word"] in names:
            cases.append((row["case_id"], row["input"], row["expected"].split()))
recorded = len(cases)


def cell(value):
    bits = value & ((1 << 64) - 1)
    return bits if bits < 1 << 63 else bits - (1 << 64)


def cells(value, double):
    return f"{cell(value)} {cell(value >> 64)}" if double else str(cell(value))


def flag(value):
    return -1 if value else 0


def add(name, operands, expected):
    key = len(cases)
    cases.append((f"boundary:{name}:{key}", f"{operands} {name} .", [str(expected)]))
    cases.append((f"compiled:{name}:{key}", f": P01A-C{key} {name} ; {operands} P01A-C{key} .", [str(expected)]))


for name in names:
    if name.startswith("D0") or name == "0<=":
        width = 128 if name.startswith("D") else 64
        for value in [-(1 << (width - 1)), -1, 0, 1, (1 << (width - 1)) - 1]:
            predicate = {"0<=": value <= 0, "D0<=": value <= 0, "D0<>": value != 0, "D0>": value > 0, "D0>=": value >= 0}[name]
            add(name, cells(value, width == 128), flag(predicate))
        continue
    unsigned = name.startswith("U") or name.startswith("DU")
    double = name.startswith("D")
    values = ([0, 1, (1 << 64) - 1, 1 << 64, (1 << 127) - 1, 1 << 127, (1 << 128) - 1] if double and unsigned else
              [-(1 << 127), -(1 << 64), -1, 0, 1, (1 << 64) - 1, 1 << 64, (1 << 127) - 1] if double else
              [0, 1, 2, (1 << 63) - 1, 1 << 63, (1 << 64) - 1])
    for a in values:
        for b in values:
            if name == "UMAX": expected = cell(max(a, b))
            elif name == "UMIN": expected = cell(min(a, b))
            elif name.endswith("<="): expected = flag(a <= b)
            elif name.endswith(">="): expected = flag(a >= b)
            elif name.endswith("<>"): expected = flag(a != b)
            else: expected = flag(a > b)
            add(name, cells(a, double) + " " + cells(b, double), expected)

commands = {"sigma": [str(pathlib.Path(args.sigma).resolve()), "--max-steps", "100000", "-e"]}
if args.gforth_build:
    build = args.gforth_build.resolve()
    commands["gforth"] = [str(build / "gforth-ditc"), "-p", str(build) + ":~+", "-i", str(build / "gforth.fi"), "-e"]
batches = []
batch = []
size = 0
for case in cases:
    if size + len(case[1]) > 2500 and batch:
        batches.append(batch)
        batch, size = [], 0
    batch.append(case)
    size += len(case[1]) + 1
if batch: batches.append(batch)
for batch in batches:
    program = " ".join(case[1] for case in batch) + " DEPTH . BYE"
    expected = [value for case in batch for value in case[2]] + ["0"]
    for name, command in commands.items():
        result = subprocess.run(command + [program], capture_output=True, text=True, timeout=15, input="")
        assert result.returncode == 0 and result.stdout.split() == expected, (name, [c[0] for c in batch], result.stdout, result.stderr)
report = {"words": len(names), "recorded_cases": recorded, "boundary_and_compiled_cases": len(cases) - recorded, "total_cases": len(cases), "batches": len(batches), "checked": list(commands), "pass": True}
if args.report:
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report))
