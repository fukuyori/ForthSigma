#!/usr/bin/env python3
"""P01b symbolic stack matrices and return-stack/loop cases against local Gforth."""
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
names = {"2NIP", "2RDROP", "2TUCK", "FOURTH", "RDROP", "THIRD"}
recorded = []
with pathlib.Path("docs/gforth-p00-runtime-cases.tsv").open() as handle:
    for row in csv.DictReader(handle, delimiter="\t"):
        if row["word"] in names:
            recorded.append((row["case_id"], row["input"], row["expected"].split()))
cases = []
values = [0, 1, -1, -(1 << 63), (1 << 63) - 1]
for name in ["2NIP", "2TUCK", "THIRD", "FOURTH"]:
    for items in itertools.product(values, repeat=3 if name == "THIRD" else 4):
        stack = [42, *items]
        if name == "2NIP": result = [42, *items[2:]]
        elif name == "2TUCK": result = [42, *items[2:], *items]
        elif name == "THIRD": result = stack + [items[0]]
        else: result = stack + [items[0]]
        expected = [str(value) for value in reversed(result)]
        for compiled in [False, True]:
            index = len(cases)
            definition = f": P01B-C{index} {name} ; " if compiled else ""
            word = f"P01B-C{index}" if compiled else name
            program = definition + " ".join(map(str, stack)) + " " + word + " ." * len(result)
            cases.append((f"{name}:{index}", program, expected))
for a, b in itertools.product(values, repeat=2):
    for name, body in [("RDROP", f"{a} >R {b} >R RDROP R> ."),
                       ("2RDROP", f"{a} >R {b} 7 2>R 2RDROP R> .")]:
        index = len(cases)
        cases.append((f"{name}:{index}", f": P01B-R{index} {body} ; P01B-R{index}", [str(a)]))
cases.extend([
    ("loop", ": P01B-L 3 0 DO I >R RDROP I . LOOP ; P01B-L", ["0", "1", "2"]),
    ("nested-loop", ": P01B-N 2 0 DO 2 0 DO I J 2>R 2RDROP I . J . LOOP LOOP ; P01B-N", ["0", "0", "1", "0", "0", "1", "1", "1"]),
    ("catch", ": P01B-F 7 >R RDROP -99 THROW ; : P01B-O 42 >R ['] P01B-F CATCH . R> . ; P01B-O", ["-99", "42"]),
    ("locals", ": P01B-A { a -- } a DUP 2>R 2RDROP a . ; 5 P01B-A", ["5"]),
])
commands = {"sigma": [str(pathlib.Path(args.sigma).resolve()), "--max-steps", "100000", "-e"]}
if args.gforth_build:
    build = args.gforth_build.resolve()
    commands["gforth"] = [str(build / "gforth-ditc"), "-p", str(build) + ":~+", "-i", str(build / "gforth.fi"), "-e"]
# P00 return-stack cases reuse TEST, so run them independently.
batches = [[case] for case in recorded]
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
report = {"words": 6, "recorded_cases": len(recorded), "boundary_compiled_and_return_cases": len(cases), "total_cases": len(recorded) + len(cases), "batches": len(batches), "checked": list(commands), "pass": True}
if args.report:
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report))
