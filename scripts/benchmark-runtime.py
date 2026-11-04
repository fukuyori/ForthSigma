#!/usr/bin/env python3
"""Compare compiled Forth kernels; run with Linux binaries inside WSL/Linux."""

import argparse
import json
import os
import platform
import resource
import statistics
import subprocess
from pathlib import Path


# Original, deliberately small kernels. These are diagnostics, not a general
# Forth benchmark suite. Every BENCH-RUN leaves one integer checksum.
CASES = {
    "arithmetic": ": BENCH-RUN 1 BENCH-ITERATIONS 0 DO 3 * 7 + 65535 AND LOOP ;",
    "stacks": ": BENCH-RUN 1 2 3 BENCH-ITERATIONS 0 DO ROT SWAP OVER + 65535 AND DUP NIP LOOP + + ;",
    "calls": ": BENCH-A 1+ ; : BENCH-B BENCH-A BENCH-A ; : BENCH-C BENCH-B BENCH-B ; : BENCH-RUN 0 BENCH-ITERATIONS 0 DO BENCH-C LOOP ;",
    "variables": "VARIABLE BENCH-V 7 CONSTANT BENCH-K : BENCH-RUN 0 BENCH-V ! BENCH-ITERATIONS 0 DO BENCH-K BENCH-V +! LOOP BENCH-V @ ;",
    "loops": ": BENCH-RUN 0 BENCH-ITERATIONS 0 DO I 7 AND + LOOP ;",
    "plus-loop": ": BENCH-RUN 0 BENCH-ITERATIONS 0 DO I 7 AND + 2 +LOOP ;",
    "extended": ": BENCH-RUN 1 BENCH-ITERATIONS 0 DO 2* 1+ DUP 3 RSHIFT XOR 65535 AND LOOP ;",
    "float": ": BENCH-RUN 0e BENCH-ITERATIONS 0 DO 1e F+ 1e F* LOOP F>S ;",
}


def engine(value):
    label, separator, path = value.partition("=")
    if not separator or not label or not path:
        raise argparse.ArgumentTypeError("expected LABEL=EXECUTABLE")
    return label, path


def sample(path, gforth, source):
    command = [path, "-e", source] if gforth else [path, source]
    start = resource.getrusage(resource.RUSAGE_CHILDREN)
    result = subprocess.run(command, capture_output=True, text=True, timeout=120, check=True)
    end = resource.getrusage(resource.RUSAGE_CHILDREN)
    lines = [line.split() for line in result.stdout.splitlines() if line.startswith("BENCH ")]
    if len(lines) != 1 or len(lines[0]) != 3 or result.stderr.strip():
        raise RuntimeError(f"unexpected output: {result.stdout!r} {result.stderr!r}")
    kernel_wall_us, checksum = map(int, lines[0][1:])
    # UTIME is calendar time and may step backwards under WSL time correction.
    # Child user+system CPU time is independent of that clock and scheduling
    # pauses. It includes startup/compilation, so use long kernels and report
    # this explicitly rather than presenting it as execution-only time.
    micros = round((end.ru_utime + end.ru_stime - start.ru_utime - start.ru_stime) * 1_000_000)
    if micros <= 0:
        raise RuntimeError("measurement too short; increase --iterations")
    return micros, checksum, kernel_wall_us


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sigma", action="append", type=engine, default=[])
    parser.add_argument("--gforth", action="append", type=engine, default=[])
    parser.add_argument("--iterations", type=int, default=10_000_000)
    parser.add_argument("--rounds", type=int, default=7)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    engines = [(label, path, False) for label, path in args.sigma]
    engines += [(label, path, True) for label, path in args.gforth]
    if len(engines) < 2 or args.iterations < 2 or args.rounds < 1:
        parser.error("need at least two engines, iterations >= 2 and rounds >= 1")
    if len({label for label, _, _ in engines}) != len(engines):
        parser.error("engine labels must be unique")
    report = {"timing": "process user+system CPU time, including startup/compilation",
              "platform": platform.platform(), "cpu_affinity": sorted(os.sched_getaffinity(0)),
              "iterations": args.iterations, "rounds": args.rounds, "engines": engines, "cases": {}}
    for name, definition in CASES.items():
        source = (f"{args.iterations} CONSTANT BENCH-ITERATIONS {definition} "
                  ': BENCH-TIMED UTIME 2>R BENCH-RUN 2R> UTIME 2SWAP D- ." BENCH " D. . CR ; BENCH-TIMED BYE')
        values = {label: [] for label, _, _ in engines}
        wall_values = {label: [] for label, _, _ in engines}
        expected = None
        # One unreported run, then alternate the engine order to reduce drift bias.
        for round_index in range(args.rounds + 1):
            order = engines if round_index % 2 == 0 else list(reversed(engines))
            for label, path, gforth in order:
                micros, checksum, kernel_wall_us = sample(path, gforth, source)
                if expected is None:
                    expected = checksum
                if checksum != expected:
                    raise RuntimeError(f"{name}/{label}: checksum {checksum}, expected {expected}")
                if round_index:
                    values[label].append(micros)
                    wall_values[label].append(kernel_wall_us)
        rows = {label: {"median_us": statistics.median(times), "min_us": min(times),
                        "max_us": max(times), "samples_us": times,
                        "kernel_wall_samples_us": wall_values[label]} for label, times in values.items()}
        report["cases"][name] = {"checksum": expected, "engines": rows}
        print(name + ": " + ", ".join(f"{label}={row['median_us'] / 1000:.3f}ms"
                                     for label, row in rows.items()), flush=True)
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
