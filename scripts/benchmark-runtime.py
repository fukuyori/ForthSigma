#!/usr/bin/env python3
"""Compare compiled Forth kernels; run with Linux binaries inside WSL/Linux."""

import argparse
import ctypes
import hashlib
import json
import os
import platform
import queue
import resource
import shutil
import statistics
import subprocess
import threading
import time
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


def process_clock(pid):
    # Linux pid_t and clockid_t are ints. Use the documented libc API rather
    # than encoding a PID into a Linux clock number ourselves.
    # https://github.com/mkerrisk/man-pages/blob/master/man3/clock_getcpuclockid.3
    function = ctypes.CDLL(None).clock_getcpuclockid
    function.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_int)]
    function.restype = ctypes.c_int
    clock_id = ctypes.c_int()
    error = function(pid, ctypes.byref(clock_id))
    if error:
        raise OSError(error, os.strerror(error))
    return clock_id.value


def sample(path, gforth, source):
    command = [path, "-e", source] if gforth else [path, source]
    start = resource.getrusage(resource.RUSAGE_CHILDREN)
    # The first KEY parks the child after compilation; the second keeps its
    # process clock available until we have sampled it. Send one byte, not a
    # newline that could accidentally satisfy both KEYs.
    with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT) as child:
        lines = queue.Queue()

        def read_lines():
            try:
                for line in iter(child.stdout.readline, b""):
                    lines.put(line)
            finally:
                lines.put(None)

        reader = threading.Thread(target=read_lines, daemon=True)
        reader.start()

        def receive():
            try:
                line = lines.get(timeout=120)
            except queue.Empty as error:
                raise RuntimeError("timed out waiting for benchmark child") from error
            if line is None:
                raise RuntimeError("benchmark child exited before completing the protocol")
            return line.strip()

        def release():
            child.stdin.write(b"x")
            child.stdin.flush()

        try:
            if (line := receive()) != b"BENCH-READY":
                raise RuntimeError(f"unexpected startup output: {line!r}")
            clock_id = process_clock(child.pid)
            cpu_start = time.clock_gettime_ns(clock_id)
            wall_start = time.monotonic_ns()
            release()
            line = receive()
            cpu_end = time.clock_gettime_ns(clock_id)
            wall_end = time.monotonic_ns()
            fields = line.split()
            if len(fields) != 2 or fields[0] != b"BENCH-DONE":
                raise RuntimeError(f"unexpected benchmark output: {line!r}")
            checksum = int(fields[1])
            release()
            child.stdin.close()
            child.wait(timeout=120)
            reader.join(timeout=5)
            if reader.is_alive():
                raise RuntimeError("benchmark output reader did not finish")
            remaining = []
            while not lines.empty():
                if (line := lines.get_nowait()) is not None:
                    remaining.append(line)
            if child.returncode or remaining:
                raise RuntimeError(f"benchmark exit={child.returncode}, extra output={remaining!r}")
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            reader.join(timeout=5)
    end = resource.getrusage(resource.RUSAGE_CHILDREN)
    micros = (cpu_end - cpu_start) / 1000
    if micros <= 0:
        raise RuntimeError("measurement too short; increase --iterations")
    total_cpu_us = (end.ru_utime + end.ru_stime - start.ru_utime - start.ru_stime) * 1_000_000
    return micros, checksum, (wall_end - wall_start) / 1000, total_cpu_us


def metadata(label, executable, gforth):
    found = shutil.which(executable)
    if found is None:
        raise FileNotFoundError(executable)
    path = Path(found).resolve()
    result = {"label": label, "path": str(path), "kind": "gforth" if gforth else "sigma"}
    if gforth:
        version = subprocess.run([str(path), "--version"], capture_output=True, text=True, check=True)
        result["version"] = (version.stdout + version.stderr).strip()
    else:
        result["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sigma", action="append", type=engine, default=[])
    parser.add_argument("--gforth", action="append", type=engine, default=[])
    parser.add_argument("--iterations", type=int, default=100_000_000)
    parser.add_argument("--rounds", type=int, default=7)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    engines = [(label, path, False) for label, path in args.sigma]
    engines += [(label, path, True) for label, path in args.gforth]
    if len(engines) < 2 or args.iterations < 2 or args.rounds < 1:
        parser.error("need at least two engines, iterations >= 2 and rounds >= 1")
    if len({label for label, _, _ in engines}) != len(engines):
        parser.error("engine labels must be unique")
    report = {"schema_version": 2,
              "timing": "child process CPU clock between READY and DONE; startup/compilation excluded; boundary I/O included",
              "platform": platform.platform(), "cpu_affinity": sorted(os.sched_getaffinity(0)),
              "iterations": args.iterations, "rounds": args.rounds,
              "engines": [metadata(*item) for item in engines], "cases": {}}
    for name, definition in CASES.items():
        source = (f"{args.iterations} CONSTANT BENCH-ITERATIONS {definition} "
                  '." BENCH-READY" CR KEY DROP BENCH-RUN ." BENCH-DONE " . CR KEY DROP BYE')
        values = {label: [] for label, _, _ in engines}
        wall_values = {label: [] for label, _, _ in engines}
        total_values = {label: [] for label, _, _ in engines}
        expected = None
        # One unreported run, then alternate the engine order to reduce drift bias.
        for round_index in range(args.rounds + 1):
            order = engines if round_index % 2 == 0 else list(reversed(engines))
            for label, path, gforth in order:
                micros, checksum, wall_us, total_cpu_us = sample(path, gforth, source)
                if expected is None:
                    expected = checksum
                if checksum != expected:
                    raise RuntimeError(f"{name}/{label}: checksum {checksum}, expected {expected}")
                if round_index:
                    values[label].append(micros)
                    wall_values[label].append(wall_us)
                    total_values[label].append(total_cpu_us)
        rows = {label: {"median_us": statistics.median(times), "min_us": min(times),
                        "max_us": max(times), "samples_us": times,
                        "monotonic_wall_samples_us": wall_values[label],
                        "total_process_cpu_samples_us": total_values[label]} for label, times in values.items()}
        report["cases"][name] = {"checksum": expected, "engines": rows}
        print(name + ": " + ", ".join(f"{label}={row['median_us'] / 1000:.3f}ms"
                                     for label, row in rows.items()), flush=True)
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
