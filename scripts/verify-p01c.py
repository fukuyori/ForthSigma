#!/usr/bin/env python3
"""P01c cell-layout and rotation matrices, optionally checked against local Gforth."""
import argparse
import csv
import itertools
import json
import pathlib
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("sigma", nargs="?", default="zig-out/bin/sigma")
parser.add_argument("--gforth-build", type=pathlib.Path)
parser.add_argument("--report", type=pathlib.Path)
args = parser.parse_args()
cases = []
with pathlib.Path("docs/gforth-p00-runtime-cases.tsv").open() as handle:
    for row in csv.DictReader(handle, delimiter="\t"):
        if row["word"] in {"2,", "ROL", "ROR"}:
            cases.append((row["case_id"], row["input"], row["expected"].split()))
recorded = len(cases)
mask = (1 << 64) - 1


def cell(value):
    value &= mask
    return value if value < 1 << 63 else value - (1 << 64)


bits_values = [0, 1, 2, 1 << 63, mask, 0x0123456789abcdef, 0xaaaaaaaaaaaaaaaa, 0x5555555555555555]
counts = list(range(130)) + [-129, -128, -127, -65, -64, -63, -1, -(1 << 63), (1 << 63) - 1]
for name, bits, count in itertools.product(["ROL", "ROR"], bits_values, counts):
    shift = count % 64
    expected = cell(((bits << shift) | (bits >> (64 - shift))) if name == "ROL" else ((bits >> shift) | (bits << (64 - shift))))
    for compiled in [False, True]:
        index = len(cases)
        prefix = f": P01C-C{index} {name} ; " if compiled else ""
        word = f"P01C-C{index}" if compiled else name
        cases.append((f"{name}:{index}", prefix + f"{cell(bits)} {count} {word} .", [str(expected)]))
# The pair values and alignment/compilation modes have independent domains.
for low, high in itertools.product([0, 1, -1, -(1 << 63), (1 << 63) - 1], repeat=2):
    for unaligned, compiled in itertools.product([False, True], repeat=2):
        index = len(cases)
        prefix = f": P01C-C{index} 2, ; " if compiled else ""
        word = f"P01C-C{index}" if compiled else "2,"
        padding = "1 C, " if unaligned else ""
        program = prefix + padding + f"HERE {low} {high} {word} HERE OVER - . DUP @ . CELL+ @ ."
        cases.append((f"2,:{index}", program, ["16", str(high), str(low)]))
commands = {"sigma": [str(pathlib.Path(args.sigma).resolve()), "--max-steps", "100000", "-e"]}
if args.gforth_build:
    build = args.gforth_build.resolve()
    commands["gforth"] = [str(build / "gforth-ditc"), "-p", str(build) + ":~+", "-i", str(build / "gforth.fi"), "-e"]
batches = []
batch, size = [], 0
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
report = {"words": 3, "recorded_cases": recorded, "boundary_compiled_and_layout_cases": len(cases) - recorded, "total_cases": len(cases), "batches": len(batches), "checked": list(commands), "pass": True}
if args.report:
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report))
