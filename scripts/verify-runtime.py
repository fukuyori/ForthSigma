#!/usr/bin/env python3
"""Verify recursion recovery and binary pipe output of a native Sigma executable."""

import argparse
import json
import os
from pathlib import Path
import queue
import subprocess
import threading


def run(executable, source, expected, input_bytes=b""):
    result = subprocess.run([executable, source], input=input_bytes, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=30)
    if result.returncode or result.stdout != expected:
        raise AssertionError(f"exit={result.returncode}; expected={expected[:100]!r}; actual={result.stdout[:500]!r}")


def prompt_before_input(executable, newline):
    # No input is sent until the prompt is observed: this detects a missing
    # flush before KEY, which a pre-filled stdin pipe cannot detect.
    with subprocess.Popen([executable, '." PROMPT " KEY EMIT CR'], stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as child:
        received = queue.Queue()

        def read_bytes():
            try:
                for byte in iter(lambda: child.stdout.read(1), b""):
                    received.put(byte)
            finally:
                received.put(None)

        reader = threading.Thread(target=read_bytes, daemon=True)
        reader.start()
        try:
            prompt = b"".join(received.get(timeout=10) or b"" for _ in b"PROMPT ")
            if prompt != b"PROMPT ":
                raise AssertionError(f"prompt before input: {prompt!r}")
            child.stdin.write(b"x")
            child.stdin.flush()
            child.stdin.close()
            child.wait(timeout=10)
            reader.join(timeout=5)
            if reader.is_alive():
                raise AssertionError("output reader did not finish")
            tail = bytearray()
            while not received.empty():
                if (byte := received.get_nowait()) is not None:
                    tail.extend(byte)
            if child.returncode or tail != b"x" + newline:
                raise AssertionError(f"KEY output: exit={child.returncode}, {tail!r}")
        finally:
            if child.poll() is None:
                child.kill()
                child.wait()
            reader.join(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sigma", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    executable = str(args.sigma.resolve(strict=True))
    newline = b"\r\n" if os.name == "nt" else b"\n"
    passed = []
    recursion = {
        "execute": ("VARIABLE XT : X DUP IF 1- XT @ EXECUTE THEN ; ' X XT ! ", "X", 1023),
        "defer": ("DEFER D : Y DUP IF 1- D THEN ; ' Y IS D ", "Y", 511),
        "catch": ("VARIABLE XT : Z DUP IF 1- XT @ CATCH THROW THEN ; ' Z XT ! ", "Z", 1023),
    }
    for name, (definition, word, limit) in recursion.items():
        for depth in (limit, limit + 1):
            source = f"{definition}{depth} ' {word} CATCH . DROP 40 2 + ."
            run(executable, source, b"0 42 " if depth == limit else b"-5 42 ")
            passed.append(f"{name}-{depth}")

    cases = {
        "stdout-stderr-order": ('." A" S" B" STDERR WRITE-FILE THROW ." C" CR', b"ABC" + newline),
        "system-order": ('." before " S" echo mid" SYSTEM ." after" CR', b"before mid" + newline + b"after" + newline),
        "large-output": (': OUT 9000 0 DO I 26 MOD 65 + EMIT LOOP ; OUT CR', bytes(65 + i % 26 for i in range(9000)) + newline),
        "flush-file": ('." A" STDOUT FLUSH-FILE THROW ." B" CR', b"AB" + newline),
        "normal-exit-flush": ('." no-newline"', b"no-newline"),
        "bye-flush": ('." before-bye" BYE ." unreachable"', b"before-bye"),
    }
    for name, (source, expected) in cases.items():
        run(executable, source, expected)
        passed.append(name)
    prompt_before_input(executable, newline)
    passed.append("prompt-before-key-input")
    report = {"executable": executable, "platform": os.name, "passed": passed}
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"{len(passed)} checks passed: {executable}")


if __name__ == "__main__":
    main()
